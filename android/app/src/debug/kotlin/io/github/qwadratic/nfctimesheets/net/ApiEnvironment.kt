package io.github.qwadratic.nfctimesheets.net

import android.content.Context
import io.github.qwadratic.nfctimesheets.BuildConfig

/** adb run-as can opt a DEBUG install into the isolated local API; release has no override. */
fun apiBaseUrl(context: Context): String {
    val override = context.getSharedPreferences("debug_api", Context.MODE_PRIVATE).getString("base", "").orEmpty()
    val uri = runCatching { java.net.URI(override) }.getOrNull()
    val local = uri?.scheme == "http" && uri.host == "127.0.0.1" && uri.port in 1..65535 &&
        uri.userInfo == null && uri.query == null && uri.fragment == null && uri.path.orEmpty().isEmpty()
    return if (local) override else "https://${BuildConfig.API_HOST}"
}
