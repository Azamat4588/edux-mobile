package uz.edux.gateway

import android.Manifest
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings

/** Telefon haqida va «uzilmasligi uchun» tekshiruvlar (batareya, avtoishga tushirish, ruxsatlar). */
object Device {
    fun model(): String = "${Build.MANUFACTURER} ${Build.MODEL}".trim()

    fun name(): String = Build.MODEL ?: "Android"

    fun granted(context: Context, permission: String): Boolean =
        context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    fun smsPermissions(): Array<String> = arrayOf(Manifest.permission.SEND_SMS)

    fun callPermissions(): Array<String> =
        arrayOf(Manifest.permission.READ_PHONE_STATE, Manifest.permission.READ_CALL_LOG, Manifest.permission.CALL_PHONE)

    fun notificationsAllowed(context: Context): Boolean =
        Build.VERSION.SDK_INT < 33 || granted(context, "android.permission.POST_NOTIFICATIONS")

    /** Batareya tejash ilovani uxlatmaydimi (Doze'da ham internet). */
    fun batteryUnrestricted(context: Context): Boolean {
        val power = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        return power.isIgnoringBatteryOptimizations(context.packageName)
    }

    /** Fon ma'lumotlari cheklanmaganmi (Data Saver). */
    fun backgroundDataAllowed(context: Context): Boolean {
        val connectivity = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        return connectivity.restrictBackgroundStatus != ConnectivityManager.RESTRICT_BACKGROUND_STATUS_ENABLED
    }

    fun requestBatteryExemption(context: Context) {
        try {
            @Suppress("BatteryLife")
            context.startActivity(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:${context.packageName}")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        } catch (_: Exception) {
            openAppSettings(context)
        }
    }

    fun openAppSettings(context: Context) {
        try {
            context.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        } catch (_: Exception) {}
    }

    fun openDataSaver(context: Context) {
        try {
            context.startActivity(Intent(Settings.ACTION_IGNORE_BACKGROUND_DATA_RESTRICTIONS_SETTINGS, Uri.parse("package:${context.packageName}")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        } catch (_: Exception) {
            openAppSettings(context)
        }
    }

    /** Xiaomi, Huawei, Oppo, Vivo, Samsung va boshqalarning «avtoishga tushirish» sahifalari (bo'lmasa — ilova sozlamalari). */
    private val AUTOSTART = listOf(
        ComponentName("com.miui.securitycenter", "com.miui.permcenter.autostart.AutoStartManagementActivity"),
        ComponentName("com.letv.android.letvsafe", "com.letv.android.letvsafe.AutobootManageActivity"),
        ComponentName("com.huawei.systemmanager", "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"),
        ComponentName("com.huawei.systemmanager", "com.huawei.systemmanager.optimize.process.ProtectActivity"),
        ComponentName("com.huawei.systemmanager", "com.huawei.systemmanager.appcontrol.activity.StartupAppControlActivity"),
        ComponentName("com.coloros.safecenter", "com.coloros.safecenter.permission.startup.StartupAppListActivity"),
        ComponentName("com.coloros.safecenter", "com.coloros.safecenter.startupapp.StartupAppListActivity"),
        ComponentName("com.oppo.safe", "com.oppo.safe.permission.startup.StartupAppListActivity"),
        ComponentName("com.iqoo.secure", "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity"),
        ComponentName("com.iqoo.secure", "com.iqoo.secure.ui.phoneoptimize.BgStartUpManager"),
        ComponentName("com.vivo.permissionmanager", "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"),
        ComponentName("com.samsung.android.lool", "com.samsung.android.sm.ui.battery.BatteryActivity"),
        ComponentName("com.asus.mobilemanager", "com.asus.mobilemanager.entry.FunctionActivity"),
        ComponentName("com.oneplus.security", "com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity"),
        ComponentName("com.transsion.phonemaster", "com.cyin.himgr.autostart.AutoStartActivity"),
    )

    /** Shu telefonda avtoishga tushirish sahifasi bormi (Xiaomi, Huawei ...). */
    fun hasAutostart(context: Context): Boolean = AUTOSTART.any { resolvable(context, it) }

    fun openAutostart(context: Context) {
        for (component in AUTOSTART) {
            if (!resolvable(context, component)) continue
            try {
                context.startActivity(Intent().setComponent(component).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                return
            } catch (_: Exception) {}
        }
        openAppSettings(context)
    }

    private fun resolvable(context: Context, component: ComponentName): Boolean = try {
        context.packageManager.resolveActivity(Intent().setComponent(component), PackageManager.MATCH_DEFAULT_ONLY) != null
    } catch (_: Exception) {
        false
    }
}
