package uz.edux.gateway

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import org.linphone.core.Call
import java.lang.ref.WeakReference

/** SIP qo'ng'irog'i ekrani: kim, holat va vaqt, javob berish / rad etish / ovozsiz / karnay / tugatish. */
class SipCallActivity : Activity() {
    companion object {
        private var instance: WeakReference<SipCallActivity>? = null

        fun intent(context: Context, action: String?): Intent =
            Intent(context, SipCallActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP).also { if (action != null) it.action = action }

        fun open(context: Context) {
            try { context.startActivity(intent(context, null)) } catch (_: Exception) {}
        }

        fun refresh() {
            instance?.get()?.let { activity -> activity.runOnUiThread { activity.render() } }
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    private lateinit var title: TextView
    private lateinit var subtitle: TextView
    private lateinit var info: TextView
    private lateinit var incoming: LinearLayout
    private lateinit var active: LinearLayout
    private lateinit var mute: Button
    private lateinit var speaker: Button
    private val tick = object : Runnable {
        override fun run() {
            render()
            handler.postDelayed(this, 1000)
        }
    }

    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()

    private fun button(label: String, color: Int, action: () -> Unit): Button = Button(this).apply {
        text = label
        isAllCaps = false
        textSize = 16f
        setTextColor(Color.WHITE)
        background = GradientDrawable().apply { setColor(color); cornerRadius = dp(28).toFloat() }
        layoutParams = LinearLayout.LayoutParams(0, dp(56), 1f).apply { setMargins(dp(6), dp(6), dp(6), dp(6)) }
        setOnClickListener { action() }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= 27) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON)
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setBackgroundColor(Color.parseColor("#0B3B3B"))
            setPadding(dp(20), dp(64), dp(20), dp(32))
        }
        title = TextView(this).apply { textSize = 28f; setTextColor(Color.WHITE); typeface = Typeface.DEFAULT_BOLD; gravity = Gravity.CENTER }
        subtitle = TextView(this).apply { textSize = 16f; setTextColor(Color.parseColor("#B8D8D8")); gravity = Gravity.CENTER; setPadding(0, dp(8), 0, 0) }
        info = TextView(this).apply { textSize = 15f; setTextColor(Color.WHITE); gravity = Gravity.CENTER; setPadding(0, dp(24), 0, 0) }
        root.addView(title)
        root.addView(subtitle)
        root.addView(info, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
        incoming = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        incoming.addView(button(Texts.get(this, "sip_decline"), Color.parseColor("#C0392B")) { SipPhone.decline() })
        incoming.addView(button(Texts.get(this, "sip_answer"), Color.parseColor("#1E8E5A")) { SipPhone.accept() })
        active = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        val controls = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        mute = button(Texts.get(this, "sip_mute"), Color.parseColor("#2C5F5F")) { SipPhone.toggleMute(); handler.postDelayed({ render() }, 200) }
        speaker = button(Texts.get(this, "sip_speaker"), Color.parseColor("#2C5F5F")) { SipPhone.toggleSpeaker(); handler.postDelayed({ render() }, 200) }
        controls.addView(mute)
        controls.addView(speaker)
        active.addView(controls)
        val end = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        end.addView(button(Texts.get(this, "sip_hangup"), Color.parseColor("#C0392B")) { SipPhone.hangup() })
        active.addView(end)
        root.addView(incoming)
        root.addView(active)
        setContentView(root)
        instance = WeakReference(this)
        handle(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handle(intent)
    }

    private fun handle(intent: Intent?) {
        when (intent?.action) {
            "answer" -> SipPhone.accept()
            "decline" -> SipPhone.decline()
        }
        render()
        // Qo'ng'iroq qiluvchi kartasi (lid/o'quvchi).
        val call = SipPhone.current() ?: return
        val phone = SipPhone.number(call) ?: return
        Thread {
            val text = CallCenter.summary(this, CallCenter.caller(this, phone)) ?: return@Thread
            runOnUiThread { info.text = text }
        }.start()
    }

    override fun onResume() {
        super.onResume()
        // Ekran ko'rinib turibdi — xizmat mikrofon turini oladi (Android 14: fonda mikrofon faqat shunda).
        GatewayService.promoteMicrophone(this)
        handler.post(tick)
    }

    override fun onPause() {
        handler.removeCallbacks(tick)
        super.onPause()
    }

    override fun onDestroy() {
        if (instance?.get() === this) instance = null
        super.onDestroy()
    }

    fun render() {
        val call = SipPhone.current()
        if (call == null) {
            finish()
            return
        }
        title.text = SipPhone.name(call)
        val ringing = call.state == Call.State.IncomingReceived
        subtitle.text = when (call.state) {
            Call.State.IncomingReceived -> Texts.get(this, "sip_incoming")
            Call.State.OutgoingInit, Call.State.OutgoingProgress, Call.State.OutgoingRinging -> Texts.get(this, "sip_calling")
            Call.State.Connected, Call.State.StreamsRunning, Call.State.Paused, Call.State.PausedByRemote -> {
                val seconds = call.duration
                "%02d:%02d".format(seconds / 60, seconds % 60)
            }
            else -> Texts.get(this, "sip_ended")
        }
        incoming.visibility = if (ringing) View.VISIBLE else View.GONE
        active.visibility = if (ringing) View.GONE else View.VISIBLE
        mute.text = Texts.get(this, if (SipPhone.muted()) "sip_unmute" else "sip_mute")
        speaker.text = Texts.get(this, if (SipPhone.speaker()) "sip_earpiece" else "sip_speaker")
    }
}
