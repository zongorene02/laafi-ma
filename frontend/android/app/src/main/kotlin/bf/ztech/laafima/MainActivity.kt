package bf.ztech.laafima

import android.content.ComponentName
import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Activité unique. Expose le canal `bf.ztech.laafima/disguise` : le
 * camouflage change l'icône et le nom de l'application sur l'écran du
 * téléphone (« Calculatrice ») en basculant entre deux alias du manifeste.
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setIconDisguised" -> {
                    val disguised = call.argument<Boolean>("disguised") ?: false
                    try {
                        setIconDisguised(disguised)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("disguise_failed", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Active d'abord l'alias voulu, PUIS désactive l'autre : il reste toujours
     * une entrée dans le lanceur. `DONT_KILL_APP` évite de fermer
     * l'application pendant le changement.
     */
    private fun setIconDisguised(disguised: Boolean) {
        val base = MainActivity::class.java.name.substringBeforeLast('.')
        val normal = ComponentName(this, "$base.DefaultLauncherAlias")
        val calculator = ComponentName(this, "$base.CalculatorAlias")
        val (enable, disable) = if (disguised) calculator to normal else normal to calculator
        packageManager.setComponentEnabledSetting(
            enable,
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
            PackageManager.DONT_KILL_APP,
        )
        packageManager.setComponentEnabledSetting(
            disable,
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
            PackageManager.DONT_KILL_APP,
        )
    }

    private companion object {
        const val CHANNEL = "bf.ztech.laafima/disguise"
    }
}
