package io.github.qwadratic.nfctimesheets.ui

import android.Manifest
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.core.content.FileProvider
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import io.github.qwadratic.nfctimesheets.R
import io.github.qwadratic.nfctimesheets.evidence.ShiftLocationService
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.io.File

/** Camera capture has no picker or imported-image path. A process death cancels the
 * pending close; the durable shift remains open and a new attempt needs a fresh photo. */
@Composable
fun ShiftEvidenceUi(model: TimeSheetViewModel) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val capture by model.evidenceCapture.collectAsStateWithLifecycle()
    val error by model.evidenceError.collectAsStateWithLifecycle()
    val log by model.log.collectAsStateWithLifecycle()
    val session by model.session.collectAsStateWithLifecycle()
    val active = log.open?.takeIf { session is SessionState.SignedIn && it.locationIntervalSeconds > 0 }
    var cameraFile by rememberSaveable { mutableStateOf<String?>(null) }
    var prompted by rememberSaveable { mutableStateOf<String?>(null) }
    var showLocation by remember { mutableStateOf(false) }
    var locationFailed by remember { mutableStateOf(false) }
    val permissions = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
        if (ShiftLocationService.hasPermission(context) && active != null) {
            locationFailed = !ShiftLocationService.start(context, active.clientUuid)
        } else locationFailed = true
    }
    LifecycleResumeEffect(active?.clientUuid, active?.locationIntervalSeconds) {
        if (active == null) ShiftLocationService.stop(context)
        else if (ShiftLocationService.hasPermission(context)) locationFailed = !ShiftLocationService.start(context, active.clientUuid)
        else if (prompted != active.clientUuid) { prompted = active.clientUuid; showLocation = true }
        onPauseOrDispose { /* The visible foreground service owns active-shift tracking. */ }
    }
    val camera = rememberLauncherForActivityResult(ActivityResultContracts.TakePicture()) { success ->
        val file = cameraFile?.let(::File)
        cameraFile = null
        val at = java.time.Instant.now()
        scope.launch {
            val jpeg = withContext(Dispatchers.IO) {
                try {
                    if (!success || file == null) null else compressProof(file)
                } catch (_: Exception) { null } finally { file?.delete() }
            }
            model.deliverEvidencePhoto(jpeg, at)
        }
    }
    LaunchedEffect(capture) {
        if (capture != null && cameraFile == null) {
            try {
                val dir = File(context.cacheDir, "proof").apply { mkdirs() }
                // No image survives the next attempt, even after process death.
                dir.listFiles()?.forEach { it.delete() }
                val file = File.createTempFile("capture-", ".jpg", dir)
                cameraFile = file.absolutePath
                camera.launch(FileProvider.getUriForFile(context, context.packageName + ".evidence", file))
            } catch (_: Exception) {
                cameraFile?.let { File(it).delete() }; cameraFile = null
                model.deliverEvidencePhoto(null)
            }
        }
    }
    if (showLocation) AlertDialog(
        onDismissRequest = { showLocation = false; locationFailed = true },
        title = { Text(stringResource(R.string.evidence_location_title)) },
        text = { Text(stringResource(R.string.evidence_location_explain, active?.locationIntervalSeconds ?: 0)) },
        confirmButton = { TextButton(onClick = {
            showLocation = false
            permissions.launch(arrayOf(Manifest.permission.ACCESS_COARSE_LOCATION, Manifest.permission.ACCESS_FINE_LOCATION))
        }) { Text(stringResource(R.string.evidence_allow)) } },
        dismissButton = { TextButton(onClick = { showLocation = false; locationFailed = true }) { Text(stringResource(R.string.evidence_later)) } },
    )
    if (locationFailed) AlertDialog(
        onDismissRequest = { locationFailed = false },
        title = { Text(stringResource(R.string.evidence_location_title)) },
        text = { Text(stringResource(R.string.evidence_location_unavailable)) },
        confirmButton = { TextButton(onClick = { locationFailed = false }) { Text(stringResource(R.string.evidence_ok)) } },
    )
    if (error != null) AlertDialog(
        onDismissRequest = model::dismissEvidenceError,
        title = { Text(stringResource(R.string.evidence_photo_title)) },
        text = { Text(stringResource(stringIdFor(error!!))) },
        confirmButton = { TextButton(onClick = model::dismissEvidenceError) { Text(stringResource(R.string.evidence_ok)) } },
    )
}

private fun compressProof(file: File): ByteArray? {
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    BitmapFactory.decodeFile(file.absolutePath, bounds)
    if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
    var sample = 1
    while (maxOf(bounds.outWidth, bounds.outHeight) / sample > 1600) sample *= 2
    val image = BitmapFactory.decodeFile(file.absolutePath, BitmapFactory.Options().apply { inSampleSize = sample }) ?: return null
    return try {
        val output = ByteArrayOutputStream()
        image.compress(Bitmap.CompressFormat.JPEG, 80, output)
        output.toByteArray().takeIf { it.size <= 2 * 1024 * 1024 }
    } finally { image.recycle() }
}
