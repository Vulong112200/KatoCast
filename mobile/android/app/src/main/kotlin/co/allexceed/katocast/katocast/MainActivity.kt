package co.allexceed.katocast.katocast

import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "katocast/oem"

    // Danh sách component "Tự khởi động / Autostart" theo hãng (best-effort).
    // Thử lần lượt, mở cái đầu tiên tồn tại. Không hãng nào khớp → false.
    private val autoStartComponents = listOf(
        // ZTE / Nubia (thiết bị mục tiêu Nubia Air 5G).
        ComponentName("com.zte.heartyservice", "com.zte.heartyservice.autorun.AppAutoRunManager"),
        ComponentName("cn.nubia.security2", "cn.nubia.security.appmanage.autostart.ui.AutoStartActivity"),
        ComponentName("cn.nubia.security", "cn.nubia.security.appmanage.autostart.ui.AutoStartActivity"),
        // Xiaomi / Redmi / POCO (MIUI/HyperOS).
        ComponentName("com.miui.securitycenter", "com.miui.permcenter.autostart.AutoStartManagementActivity"),
        // Oppo / Realme (ColorOS).
        ComponentName("com.coloros.safecenter", "com.coloros.safecenter.permission.startup.StartupAppListActivity"),
        ComponentName("com.coloros.safecenter", "com.coloros.safecenter.startupapp.StartupAppListActivity"),
        ComponentName("com.oppo.safe", "com.oppo.safe.permission.startup.StartupAppListActivity"),
        // vivo (FuntouchOS/OriginOS).
        ComponentName("com.vivo.permissionmanager", "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"),
        ComponentName("com.iqoo.secure", "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity"),
        // Huawei / Honor (EMUI/MagicOS).
        ComponentName("com.huawei.systemmanager", "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"),
        ComponentName("com.huawei.systemmanager", "com.huawei.systemmanager.optimize.process.ProtectActivity"),
        // Letv.
        ComponentName("com.letv.android.letvsafe", "com.letv.android.letvsafe.AutobootManageActivity"),
    )

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openAutoStart" -> result.success(openAutoStart())
                    "openBatterySettings" -> result.success(openBatterySettings())
                    else -> result.notImplemented()
                }
            }
    }

    /// Mở đúng màn "Tự khởi động" của hãng nếu tìm được; trả false nếu không có
    /// (Dart sẽ fallback mở trang App Info tiêu chuẩn).
    private fun openAutoStart(): Boolean {
        for (component in autoStartComponents) {
            try {
                val intent = Intent().apply {
                    setComponent(component)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(intent)
                return true
            } catch (_: Exception) {
                // Component không tồn tại trên máy này → thử cái tiếp theo.
            }
        }
        return false
    }

    /// Mở trang xin bỏ tối ưu hoá pin cho chính app (whitelist).
    private fun openBatterySettings(): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val intent = Intent(
                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                    Uri.parse("package:$packageName"),
                ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
                true
            } else {
                false
            }
        } catch (_: Exception) {
            false
        }
    }
}
