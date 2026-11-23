package uz.edux.gateway

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.Network
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.os.SystemClock
import android.telephony.TelephonyManager
import org.json.JSONObject

/**
 * Yagona fon xizmati (doimiy bildirishnoma): SMS navbati va qo'ng'iroqlar — ikki alohida ipda, bittasi qotsa ikkinchisi
 * to'xtamaydi. Uzilmaslik uchun:
 *  - START_STICKY + onTaskRemoved/onDestroy da qayta ishga tushirish (Watchdog.restartSoon);
 *  - doimiy PARTIAL_WAKE_LOCK va Wi-Fi qulfi — ekran o'chganda ham protsessor va internet ishlaydi;
 *  - internet qaytishi bilan darhol tekshiradi (NetworkCallback);
 *  - qo'riqchi (WorkManager 15 daqiqa + AlarmManager 10 daqiqa) xizmat o'lgan bo'lsa qayta ko'taradi;
 *  - telefon qayta yoqilsa yoki ilova yangilansa — BootReceiver.
 */
class GatewayService : Service() {
    companion object {
        const val CHANNEL = "edux_gateway"
        const val DIAL_CHANNEL = "edux_gateway_dial"
        const val NOTIFICATION_ID = 5101
        const val DIAL_NOTIFICATION_ID = 5102
        private const val ACTION_POKE = "uz.edux.gateway.POKE"
        private const val ACTION_MIC = "uz.edux.gateway.MIC"

        @Volatile var running = false

        /** Kerak bo'lsa (ulangan va biror vazifa yoqilgan) xizmatni ishga tushiradi. Qaytaradi: muvaffaqiyatli. */
        fun ensure(context: Context): Boolean {
            if (!Store.active(context)) return false
            return start(context)
        }

        fun start(context: Context): Boolean = try {
            val intent = Intent(context, GatewayService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) context.startForegroundService(intent) else context.startService(intent)
            true
        } catch (_: Exception) {
            // Android 12+: fonda ishga tushirishga ruxsat yo'q (batareya cheklovi) — foydalanuvchiga eslatma.
            Watchdog.notifyStopped(context)
            false
        }

        fun poke(context: Context) {
            if (!running) {
                ensure(context)
                return
            }
            try { context.startService(Intent(context, GatewayService::class.java).setAction(ACTION_POKE)) } catch (_: Exception) {}
        }

        /** SIP qo'ng'irog'i ekrani ochiq (ilova oldingi planda) — xizmat mikrofon turini oladi (Android 14). */
        fun promoteMicrophone(context: Context) {
            try { context.startService(Intent(context, GatewayService::class.java).setAction(ACTION_MIC)) } catch (_: Exception) {}
        }

        fun stop(context: Context) {
            try { context.stopService(Intent(context, GatewayService::class.java)) } catch (_: Exception) {}
        }
    }

    @Volatile private var stopping = false
    private val smsSignal = Object()
    private val callSignal = Object()
    private var smsThread: Thread? = null
    private var callThread: Thread? = null
    private var reportThread: Thread? = null
    private val reportSignal = Object()
    private var sipCheckedAt = 0L
    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null
    private var lockAt = 0L
    private lateinit var sms: SmsEngine
    private lateinit var calls: CallEngine
    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    private val stateReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val state = intent?.getStringExtra(TelephonyManager.EXTRA_STATE) ?: return
            @Suppress("DEPRECATION")
            val number = intent?.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER)
            calls.onState(state, number)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        running = true
        sms = SmsEngine(this)
        calls = CallEngine(this) { signal(callSignal) }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(NotificationChannel(CHANNEL, Texts.get(this, "channel_service"), NotificationManager.IMPORTANCE_LOW).apply { setShowBadge(false) })
            manager.createNotificationChannel(NotificationChannel(DIAL_CHANNEL, Texts.get(this, "channel_dial"), NotificationManager.IMPORTANCE_HIGH))
        }
        val filter = IntentFilter(TelephonyManager.ACTION_PHONE_STATE_CHANGED)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(stateReceiver, filter, Context.RECEIVER_EXPORTED)
            } else {
                @Suppress("UnspecifiedRegisterReceiverFlag")
                registerReceiver(stateReceiver, filter)
            }
        } catch (_: Exception) {}
        try {
            val callback = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) {
                    signal(smsSignal)
                    signal(callSignal)
                }
            }
            (getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager).registerDefaultNetworkCallback(callback)
            networkCallback = callback
        } catch (_: Exception) {}
    }

    private fun notification(): Notification {
        val smsStatus = Store.status(this, "sms")
        val callStatus = Store.status(this, "calls")
        val off = Texts.get(this, "notify_off")
        val body = Texts.format(this, "notify_body",
            if (Store.smsOn(this)) smsStatus.optInt("sent").toString() else off,
            if (Store.callsOn(this)) callStatus.optInt("logged").toString() else off)
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(this, CHANNEL) else @Suppress("DEPRECATION") Notification.Builder(this)
        val open = PendingIntent.getActivity(this, 1, Intent(this, MainActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        return builder.setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(Texts.get(this, "notify_title"))
            .setContentText(body)
            .setContentIntent(open)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .build()
    }

    private fun refreshNotification() {
        try { (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).notify(NOTIFICATION_ID, notification()) } catch (_: Exception) {}
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        try {
            if (Build.VERSION.SDK_INT >= 34) {
                var type = ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
                if (intent?.action == ACTION_MIC && Device.granted(this, android.Manifest.permission.RECORD_AUDIO)) {
                    type = type or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                }
                try {
                    startForeground(NOTIFICATION_ID, notification(), type)
                } catch (_: Exception) {
                    startForeground(NOTIFICATION_ID, notification(), ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
                }
            } else {
                startForeground(NOTIFICATION_ID, notification())
            }
        } catch (_: Exception) {
            Watchdog.notifyStopped(this)
            stopSelf()
            return START_NOT_STICKY
        }
        if (!Store.active(this)) {
            stopping = true
            stopSelf()
            return START_NOT_STICKY
        }
        Watchdog.clearStopped(this)
        Watchdog.schedule(this)
        acquireLocks()
        stopping = false
        if (smsThread?.isAlive != true) smsThread = Thread({ loop(smsSignal, "sms") }, "edux-gw-sms").also { it.start() }
        if (callThread?.isAlive != true) callThread = Thread({ loop(callSignal, "calls") }, "edux-gw-calls").also { it.start() }
        if (reportThread?.isAlive != true) reportThread = Thread({ reportLoop() }, "edux-gw-report").also { it.start() }
        signal(smsSignal)
        signal(callSignal)
        return START_STICKY
    }

    private fun signal(lock: Object) = synchronized(lock) { lock.notifyAll() }

    private fun pause(lock: Object, ms: Long) {
        if (ms <= 0 || stopping) return
        synchronized(lock) { try { lock.wait(ms) } catch (_: InterruptedException) {} }
    }

    @Suppress("DEPRECATION")
    private fun acquireLocks() {
        val now = SystemClock.elapsedRealtime()
        if (wakeLock?.isHeld == true && now - lockAt < 30 * 60 * 1000L) return
        lockAt = now
        try {
            if (wakeLock == null) {
                wakeLock = (getSystemService(Context.POWER_SERVICE) as PowerManager)
                    .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "edux:gateway").apply { setReferenceCounted(false) }
            }
            // Bir soatlik — har 30 daqiqada yangilanadi (tizim «cheksiz» qulfni yoqtirmaydi).
            wakeLock?.acquire(60 * 60 * 1000L)
        } catch (_: Exception) {}
        try {
            if (wifiLock == null) {
                val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                val mode = if (Build.VERSION.SDK_INT >= 29) WifiManager.WIFI_MODE_FULL_HIGH_PERF else WifiManager.WIFI_MODE_FULL
                wifiLock = wifi.createWifiLock(mode, "edux:gateway").apply { setReferenceCounted(false) }
            }
            if (wifiLock?.isHeld != true) wifiLock?.acquire()
        } catch (_: Exception) {}
    }

    private fun loop(lock: Object, kind: String) {
        val deviceId = Store.deviceId(this)
        while (!stopping) {
            acquireLocks()
            val pairing = Store.pairing(this)
            if (pairing == null || !Store.active(this)) {
                stopping = true
                stopForegroundCompat()
                stopSelf()
                break
            }
            val enabled = if (kind == "sms") Store.smsOn(this) else Store.callsOn(this)
            if (!enabled) {
                if (kind == "sms") sms.reset() else calls.reset()
                pause(lock, 60000)
                continue
            }
            if (kind == "calls") syncSip(pairing, deviceId)
            val wait = try {
                if (kind == "sms") sms.cycle(pairing, deviceId) else calls.cycle(pairing, deviceId)
            } catch (e: Exception) {
                // Internet yo'q, server javob bermadi va h.k. — keyingi aylanishda qayta urinadi.
                Store.updateStatus(this, kind) { it.put("last_error", e.message ?: e.javaClass.simpleName).put("last_poll", System.currentTimeMillis()) }
                20000L
            }
            Store.heartbeat(this)
            refreshNotification()
            if (wait > 0) pause(lock, wait)
        }
    }

    /** SIP softfon: yoqilgan bo'lsa — ma'lumotni (10 daqiqada bir) yangilab, ro'yxatdan o'tadi; o'chirilsa — uziladi. */
    private fun syncSip(pairing: Store.Pairing, deviceId: String) {
        if (!Store.sipOn(this)) {
            if (SipPhone.registration != "none") SipPhone.stop()
            return
        }
        val now = System.currentTimeMillis()
        if (Store.sipCredentials(this) == null || now - sipCheckedAt > 10 * 60 * 1000L || SipPhone.registration == "failed") {
            sipCheckedAt = now
            try {
                val response = Api.call(pairing, deviceId, "GET", "crm/callcenter/sip")
                if (response.ok) {
                    val credentials = response.json().optJSONObject("credentials")
                    Store.setSipCredentials(this, credentials)
                    Store.updateStatus(this, "sip") {
                        it.put("available", credentials != null).put("number", response.json().optString("number"))
                    }
                }
            } catch (_: Exception) {}
        }
        Store.sipCredentials(this)?.let { SipPhone.start(this, it) } ?: SipPhone.stop()
    }

    /** Holat hisoboti serverga (har 5 daqiqada): vebda «Ulangan telefonlar» da nosozlik sababi ko'rinadi. */
    private fun reportLoop() {
        while (!stopping) {
            try {
                val pairing = Store.pairing(this) ?: break
                val checks = JSONObject()
                    .put("battery", Device.batteryUnrestricted(this))
                    .put("notifications", Device.notificationsAllowed(this))
                    .put("background_data", Device.backgroundDataAllowed(this))
                if (pairing.sms) checks.put("sms_permission", Device.smsPermissions().all { Device.granted(this, it) })
                if (pairing.calls) checks.put("call_permissions", Device.callPermissions().all { Device.granted(this, it) })
                if (Store.sipOn(this)) checks.put("microphone", Device.granted(this, android.Manifest.permission.RECORD_AUDIO))
                fun part(key: String, on: Boolean): JSONObject {
                    val status = Store.status(this, key)
                    return JSONObject().put("on", on).put("last_error", status.optString("last_error")).put("last_poll", status.optLong("last_poll"))
                        .put("sent", status.optInt("sent")).put("failed", status.optInt("failed")).put("logged", status.optInt("logged"))
                }
                val body = JSONObject()
                    .put("app_version", BuildConfig.VERSION_NAME)
                    .put("android", Build.VERSION.RELEASE)
                    .put("service", true)
                    .put("sms", part("sms", Store.smsOn(this)).put("bank", Store.bankOn(this)).put("bank_error", Store.status(this, "sms").optString("bank_error")))
                    .put("calls", part("calls", Store.callsOn(this)).put("pending", Store.pending(this).length()))
                    .put("sip", SipPhone.state().put("on", Store.sipOn(this)))
                    .put("checks", checks)
                Api.call(pairing, Store.deviceId(this), "POST", "gateway/status", body)
            } catch (_: Exception) {}
            if (!stopping) synchronized(reportSignal) { try { reportSignal.wait(5 * 60 * 1000L) } catch (_: InterruptedException) {} }
        }
    }

    @Suppress("DEPRECATION")
    private fun stopForegroundCompat() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) stopForeground(Service.STOP_FOREGROUND_REMOVE) else stopForeground(true)
        } catch (_: Exception) {}
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // Ilova «so'nggi ilovalar» dan surib yopildi — xizmat qayta ko'tariladi.
        if (Store.active(this)) Watchdog.restartSoon(this)
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        stopping = true
        running = false
        signal(smsSignal)
        signal(callSignal)
        signal(reportSignal)
        SipPhone.stop()
        try { unregisterReceiver(stateReceiver) } catch (_: Exception) {}
        networkCallback?.let { try { (getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager).unregisterNetworkCallback(it) } catch (_: Exception) {} }
        try { if (wakeLock?.isHeld == true) wakeLock?.release() } catch (_: Exception) {}
        try { if (wifiLock?.isHeld == true) wifiLock?.release() } catch (_: Exception) {}
        // Tizim xizmatni o'ldirgan bo'lsa (vazifa hali yoqilgan) — qayta ko'tariladi.
        if (Store.active(this)) Watchdog.restartSoon(this)
        super.onDestroy()
    }
}
