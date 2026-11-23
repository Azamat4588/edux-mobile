package uz.edux.gateway

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import java.util.concurrent.TimeUnit

/**
 * Qo'riqchi: xizmat tizim tomonidan o'ldirilsa yoki ishga tushmasa — qayta ko'taradi.
 *  - WorkManager (15 daqiqa) — telefon qayta yoqilgandan keyin ham o'zi tiklanadi;
 *  - AlarmManager.setAndAllowWhileIdle (10 daqiqa, Doze'da ham ishlaydi) va «tez qayta ishga tushirish» (5 s).
 */
object Watchdog {
    private const val WORK = "edux-gateway-keepalive"
    private const val INTERVAL_MS = 10 * 60 * 1000L
    private const val STOPPED_ID = 5103

    fun schedule(context: Context) {
        try {
            WorkManager.getInstance(context.applicationContext).enqueueUniquePeriodicWork(
                WORK, ExistingPeriodicWorkPolicy.KEEP,
                PeriodicWorkRequestBuilder<KeepAliveWorker>(15, TimeUnit.MINUTES).build(),
            )
        } catch (_: Exception) {}
        alarm(context, INTERVAL_MS)
    }

    fun restartSoon(context: Context) = alarm(context, 5000)

    fun cancel(context: Context) {
        try { WorkManager.getInstance(context.applicationContext).cancelUniqueWork(WORK) } catch (_: Exception) {}
        try { (context.getSystemService(Context.ALARM_SERVICE) as AlarmManager).cancel(pending(context)) } catch (_: Exception) {}
    }

    private fun pending(context: Context): PendingIntent = PendingIntent.getBroadcast(
        context, 0, Intent(context, AlarmReceiver::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun alarm(context: Context, delayMs: Long) {
        try {
            val alarms = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            alarms.setAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, SystemClock.elapsedRealtime() + delayMs, pending(context))
        } catch (_: Exception) {}
    }

    /** Xizmatni fonda ishga tushirib bo'lmadi (batareya cheklovi) — bosilsa ilova ochiladi va xizmat tiklanadi. */
    fun notifyStopped(context: Context) {
        try {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                manager.createNotificationChannel(NotificationChannel(GatewayService.DIAL_CHANNEL, Texts.get(context, "channel_dial"), NotificationManager.IMPORTANCE_HIGH))
            }
            val open = PendingIntent.getActivity(context, 3, Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(context, GatewayService.DIAL_CHANNEL) else @Suppress("DEPRECATION") Notification.Builder(context)
            manager.notify(STOPPED_ID, builder.setSmallIcon(R.drawable.ic_notification)
                .setContentTitle(Texts.get(context, "stopped_title"))
                .setContentText(Texts.get(context, "stopped_body"))
                .setContentIntent(open).setAutoCancel(true).build())
        } catch (_: Exception) {}
    }

    fun clearStopped(context: Context) {
        try { (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(STOPPED_ID) } catch (_: Exception) {}
    }
}

class KeepAliveWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result {
        GatewayService.ensure(applicationContext)
        return Result.success()
    }
}

class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (!Store.active(context)) return
        GatewayService.ensure(context)
        Watchdog.schedule(context)
    }
}

/** Telefon qayta yoqildi yoki ilova yangilandi — ulangan bo'lsa xizmat o'zi ishga tushadi. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (!Store.active(context)) return
        GatewayService.ensure(context)
        Watchdog.schedule(context)
    }
}
