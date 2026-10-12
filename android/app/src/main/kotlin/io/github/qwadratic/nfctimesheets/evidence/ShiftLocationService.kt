package io.github.qwadratic.nfctimesheets.evidence

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import io.github.qwadratic.nfctimesheets.AppLanguage
import io.github.qwadratic.nfctimesheets.MainActivity
import io.github.qwadratic.nfctimesheets.R
import io.github.qwadratic.nfctimesheets.TimeSheetsApplication
import io.github.qwadratic.nfctimesheets.core.ApiFailure
import kotlinx.coroutines.*
import java.time.Instant

/** Started only while the worker screen is resumed. No background-location permission,
 * boot receiver or hidden restart. Android may stop it; the screen re-arms on resume. */
class ShiftLocationService : Service(), LocationListener {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val app get() = application as TimeSheetsApplication
    private val manager by lazy { getSystemService(Context.LOCATION_SERVICE) as LocationManager }
    private var uuid: String? = null
    private var interval = 0L
    private var lastSent = 0L
    private var sending = false
    private var loop: Job? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val requested = intent?.getStringExtra("shift")
        if (requested == null || !hasPermission(this)) { stopSelf(); return START_NOT_STICKY }
        val text = AppLanguage.wrap(this)
        val notifications = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) notifications.createNotificationChannel(
            NotificationChannel(CHANNEL, text.getString(R.string.evidence_location_title), NotificationManager.IMPORTANCE_LOW))
        val pending = PendingIntent.getActivity(this, 418, Intent(this, MainActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        startForeground(418, NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_shift).setContentTitle(text.getString(R.string.evidence_location_title))
            .setContentText(text.getString(R.string.evidence_location_body)).setContentIntent(pending).setOngoing(true).build())
        if (uuid == requested && loop?.isActive == true) return START_NOT_STICKY
        uuid = requested
        lastSent = 0
        interval = 0
        loop?.cancel()
        manager.removeUpdates(this)
        loop = scope.launch {
            while (isActive) {
                val worker = app.workers.read()
                val open = withContext(Dispatchers.IO) { worker?.let { app.store.openShift(it.id) } }
                if (app.cookies.header() == null || open == null || open.clientUuid != uuid || open.locationIntervalSeconds <= 0 ||
                    Instant.now().isAfter(open.startTime.plusSeconds(8 * 3600))) { stopSelf(); break }
                if (!hasPermission(this@ShiftLocationService)) { stopSelf(); break }
                if (interval != open.locationIntervalSeconds * 1000L) {
                    interval = open.locationIntervalSeconds * 1000L
                    manager.removeUpdates(this@ShiftLocationService)
                    for (provider in listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)) {
                        try {
                            if (manager.isProviderEnabled(provider)) manager.requestLocationUpdates(provider, interval, 0f, this@ShiftLocationService, Looper.getMainLooper())
                        } catch (_: SecurityException) { stopSelf() }
                          catch (_: IllegalArgumentException) { /* This device has no such provider. */ }
                    }
                }
                try {
                    val remote = app.api.currentOpenShift()
                    if (remote?.clientUuid != uuid) { stopSelf(); break }
                } catch (failure: ApiFailure) {
                    if (failure.status == 401 || failure.status == 403) { stopSelf(); break }
                }
                delay(30_000)
            }
        }
        return START_NOT_STICKY
    }

    override fun onLocationChanged(location: Location) {
        val shift = uuid ?: return
        val now = android.os.SystemClock.elapsedRealtime()
        if (sending || (lastSent != 0L && now - lastSent < interval) || !location.hasAccuracy() ||
            kotlin.math.abs(System.currentTimeMillis() - location.time) > 120_000) return
        sending = true
        scope.launch {
            try {
                val worker = app.workers.read()
                val active = withContext(Dispatchers.IO) { worker?.let { app.store.openShift(it.id) } }
                if (active?.clientUuid != shift || app.cookies.header() == null) { stopSelf(); return@launch }
                app.api.sendLocation(shift, Instant.ofEpochMilli(location.time), location.latitude, location.longitude, location.accuracy.toDouble())
                lastSent = now
            } catch (failure: ApiFailure) {
                // Coordinates are never queued to another session or sent after a shift.
                // A network gap is a gap; never fabricate an observation to fill it.
                if (failure.status == 401 || failure.code == "shift_not_active") stopSelf()
                lastSent = now
            } finally { sending = false }
        }
    }

    @Deprecated("Required on older Android versions")
    override fun onStatusChanged(provider: String?, status: Int, extras: android.os.Bundle?) = Unit
    override fun onProviderEnabled(provider: String) = Unit
    override fun onProviderDisabled(provider: String) = Unit

    override fun onDestroy() {
        manager.removeUpdates(this)
        scope.cancel()
        super.onDestroy()
    }

    companion object {
        private const val CHANNEL = "shift_location"
        fun hasPermission(context: Context) =
            ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
        fun start(context: Context, shift: String): Boolean = try {
            ContextCompat.startForegroundService(context, Intent(context, ShiftLocationService::class.java).putExtra("shift", shift))
            true
        } catch (_: IllegalStateException) { false } catch (_: SecurityException) { false }
        fun stop(context: Context) { context.stopService(Intent(context, ShiftLocationService::class.java)) }
    }
}
