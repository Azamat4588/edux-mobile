package uz.edux.gateway

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Handler
import android.os.Looper
import org.json.JSONObject
import org.linphone.core.Account
import org.linphone.core.AudioDevice
import org.linphone.core.Call
import org.linphone.core.Core
import org.linphone.core.CoreListenerStub
import org.linphone.core.Factory
import org.linphone.core.Reason
import org.linphone.core.RegistrationState
import org.linphone.core.TransportType

/**
 * SIP softfon (EduX ATS): operator kompyuterdagi MicroSIP o'rniga shu telefonda qo'ng'iroq qabul qiladi va qiladi —
 * SIM kerak emas, suhbat ATS da yozib olinadi. Ma'lumotlar (server, port, login, parol) — GET crm/callcenter/sip.
 * Vebdagi «Qo'ng'iroq» (EduX'dan qo'ng'iroq) avval softfonni jiringlatadi — «EduX» nomli qo'ng'iroq o'zi ko'tariladi.
 * Linphone yadrosi asosiy ipda yaratiladi va ishlaydi (hamma chaqiruvlar onMain orqali).
 */
object SipPhone {
    const val CALL_CHANNEL = "edux_gateway_sip"
    const val CALL_NOTIFICATION_ID = 5301

    private val main = Handler(Looper.getMainLooper())
    private var core: Core? = null
    private var appContext: Context? = null
    private var signature: String? = null
    private var connectedAt = 0L

    @Volatile var registration: String = "none"
        private set

    @Volatile var lastError: String = ""
        private set

    private fun onMain(block: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) block() else main.post(block)
    }

    fun ready(): Boolean = registration == "ok"

    fun current(): Call? = core?.currentCall ?: core?.calls?.firstOrNull()

    private val listener = object : CoreListenerStub() {
        override fun onAccountRegistrationStateChanged(core: Core, account: Account, state: RegistrationState?, message: String) {
            registration = when (state) {
                RegistrationState.Ok -> "ok"
                RegistrationState.Progress -> "progress"
                RegistrationState.Failed -> "failed"
                RegistrationState.Cleared, RegistrationState.None -> "none"
                else -> registration
            }
            lastError = if (state == RegistrationState.Failed) message else ""
            appContext?.let { ctx -> Store.updateStatus(ctx, "sip") { it.put("registration", registration).put("last_error", lastError).put("at", System.currentTimeMillis()) } }
        }

        override fun onCallStateChanged(core: Core, call: Call, state: Call.State?, message: String) {
            val ctx = appContext ?: return
            when (state) {
                Call.State.IncomingReceived -> {
                    // EduX'dan qo'ng'iroq (vebda «Qo'ng'iroq» bosildi) — operator o'zi boshlagan, darhol ko'tariladi.
                    if (call.remoteAddress.displayName == "EduX") {
                        call.accept()
                        SipCallActivity.open(ctx)
                    } else {
                        ringing(ctx, call)
                        number(call)?.let { CallCenter.showCaller(ctx, it) }
                    }
                }
                Call.State.OutgoingInit -> SipCallActivity.open(ctx)
                Call.State.Connected, Call.State.StreamsRunning -> {
                    if (connectedAt == 0L) connectedAt = System.currentTimeMillis()
                    cancelRinging(ctx)
                }
                Call.State.End, Call.State.Error, Call.State.Released -> {
                    cancelRinging(ctx)
                    if (state != Call.State.Released && connectedAt > 0) {
                        val phone = number(call)
                        connectedAt = 0
                        // Natija: qo'ng'iroq ATS jurnaliga yozilishiga ulgursin, keyin id raqam bo'yicha olinadi.
                        if (phone != null) main.postDelayed({ CallCenter.askOutcome(ctx, phone, 0) }, 4000)
                    }
                }
                else -> {}
            }
            SipCallActivity.refresh()
        }
    }

    /** Qo'ng'iroq qiluvchi raqami (ATS «+998...» yoki «998...» beradi). */
    fun number(call: Call): String? {
        val user = call.remoteAddress.username ?: return null
        val digits = user.filter { it.isDigit() || it == '+' }
        return if (digits.length >= 5) digits else null
    }

    fun name(call: Call): String = call.remoteAddress.displayName?.takeIf { it.isNotBlank() && it != "EduX" } ?: (number(call) ?: "")

    /** Ma'lumot o'zgarmagan bo'lsa qayta ulanmaydi. */
    fun start(context: Context, credentials: JSONObject) {
        val app = context.applicationContext
        val server = credentials.optString("server")
        val username = credentials.optString("username")
        val password = credentials.optString("password")
        val port = credentials.optInt("port", 5060)
        if (server.isEmpty() || username.isEmpty()) return
        val key = "$server:$port:$username:$password"
        onMain {
            if (core != null && signature == key) return@onMain
            stopNow()
            appContext = app
            try {
                val factory = Factory.instance()
                val created = factory.createCore(null, null, app)
                created.isVideoCaptureEnabled = false
                created.isVideoDisplayEnabled = false
                created.isKeepAliveEnabled = true
                val auth = factory.createAuthInfo(username, null, password, null, null, server, null)
                val params = created.createAccountParams()
                params.identityAddress = factory.createAddress("sip:$username@$server")
                val proxy = factory.createAddress("sip:$server:$port")
                proxy?.transport = if (credentials.optString("transport").equals("TCP", true)) TransportType.Tcp else TransportType.Udp
                params.serverAddress = proxy
                params.isRegisterEnabled = true
                params.expires = 300
                val account = created.createAccount(params)
                created.addAuthInfo(auth)
                created.addAccount(account)
                created.defaultAccount = account
                created.addListener(listener)
                created.start()
                core = created
                signature = key
                registration = "progress"
            } catch (e: Exception) {
                registration = "failed"
                lastError = e.message ?: e.javaClass.simpleName
            }
        }
    }

    fun stop() = onMain { stopNow() }

    private fun stopNow() {
        core?.let {
            try {
                it.removeListener(listener)
                it.stop()
            } catch (_: Exception) {}
        }
        core = null
        signature = null
        registration = "none"
    }

    fun dial(context: Context, phone: String) = onMain {
        val active = core ?: return@onMain
        val server = Store.sipCredentials(context)?.optString("server") ?: return@onMain
        val clean = phone.filter { it.isDigit() || it == '+' }
        val address = Factory.instance().createAddress("sip:$clean@$server") ?: return@onMain
        val params = active.createCallParams(null) ?: return@onMain
        active.inviteAddressWithParams(address, params)
    }

    fun accept() = onMain { current()?.accept() }

    fun decline() = onMain {
        val call = current() ?: return@onMain
        if (call.state == Call.State.IncomingReceived) call.decline(Reason.Declined) else call.terminate()
    }

    fun hangup() = onMain { current()?.terminate() }

    fun muted(): Boolean = core?.isMicEnabled == false

    fun toggleMute() = onMain { core?.let { it.isMicEnabled = !it.isMicEnabled } }

    fun speaker(): Boolean = current()?.outputAudioDevice?.type == AudioDevice.Type.Speaker

    fun toggleSpeaker() = onMain {
        val call = current() ?: return@onMain
        val wanted = if (speaker()) AudioDevice.Type.Earpiece else AudioDevice.Type.Speaker
        core?.audioDevices?.firstOrNull { it.type == wanted }?.let { call.outputAudioDevice = it }
    }

    // --- Kiruvchi qo'ng'iroq bildirishnomasi (qulflangan ekranda ham — to'liq ekran) ---

    private fun ringing(context: Context, call: Call) {
        try {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                manager.createNotificationChannel(NotificationChannel(CALL_CHANNEL, Texts.get(context, "channel_sip"), NotificationManager.IMPORTANCE_HIGH))
            }
            val open = PendingIntent.getActivity(context, 20, SipCallActivity.intent(context, null), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val answer = PendingIntent.getActivity(context, 21, SipCallActivity.intent(context, "answer"), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val decline = PendingIntent.getActivity(context, 22, SipCallActivity.intent(context, "decline"), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(context, CALL_CHANNEL) else @Suppress("DEPRECATION") Notification.Builder(context)
            val note = builder.setSmallIcon(R.drawable.ic_notification)
                .setContentTitle(Texts.get(context, "sip_incoming"))
                .setContentText(name(call))
                .setCategory(Notification.CATEGORY_CALL)
                .setFullScreenIntent(open, true)
                .setContentIntent(open)
                .setOngoing(true)
                .addAction(Notification.Action.Builder(Icon.createWithResource(context, R.drawable.ic_notification), Texts.get(context, "sip_answer"), answer).build())
                .addAction(Notification.Action.Builder(Icon.createWithResource(context, R.drawable.ic_notification), Texts.get(context, "sip_decline"), decline).build())
                .build()
            manager.notify(CALL_NOTIFICATION_ID, note)
        } catch (_: Exception) {}
    }

    private fun cancelRinging(context: Context) {
        try { (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(CALL_NOTIFICATION_ID) } catch (_: Exception) {}
    }

    /** Holat (ekran va server hisoboti uchun). */
    fun state(): JSONObject = JSONObject().put("registration", registration).put("last_error", lastError).put("in_call", current() != null)
}
