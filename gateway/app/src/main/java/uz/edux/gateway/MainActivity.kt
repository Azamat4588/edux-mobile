package uz.edux.gateway

import android.app.AlertDialog
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.InputType
import android.text.format.DateUtils
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.Switch
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import com.journeyapps.barcodescanner.ScanContract
import com.journeyapps.barcodescanner.ScanOptions
import org.json.JSONObject

/**
 * Bitta ekran: ulanmagan bo'lsa — QR/kod bilan ulash; ulangan bo'lsa — SMS va qo'ng'iroqlar holati, kalitlar va
 * «uzilmasligi uchun» tekshiruv ro'yxati (batareya, ruxsatlar, fon interneti, avtoishga tushirish).
 */
class MainActivity : ComponentActivity() {
    private val handler = Handler(Looper.getMainLooper())
    private lateinit var root: LinearLayout
    private var refresh: (() -> Unit)? = null
    private var busy = false

    private val brand = Color.parseColor("#0F6E6E")
    private val muted = Color.parseColor("#5B6577")
    private val danger = Color.parseColor("#B42318")
    private val success = Color.parseColor("#067647")

    private val scanner = registerForActivityResult(ScanContract()) { result ->
        result.contents?.let { pairFromLink(it) }
    }

    private val permissions = registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
        GatewayService.poke(this)
        render()
    }

    private val tick = object : Runnable {
        override fun run() {
            refresh?.invoke()
            handler.postDelayed(this, 2000)
        }
    }

    private fun t(key: String) = Texts.get(this, key)

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val scroll = ScrollView(this).apply { setBackgroundColor(Color.parseColor("#F5F7F8")) }
        root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(18), dp(24), dp(18), dp(32))
        }
        scroll.addView(root)
        setContentView(scroll)
        handleLink(intent)
        render()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleLink(intent)
    }

    override fun onResume() {
        super.onResume()
        // Ilova ochilishi — xizmat tirikligini tekshirish uchun ham qulay payt.
        GatewayService.ensure(this)
        render()
        handler.post(tick)
    }

    override fun onPause() {
        handler.removeCallbacks(tick)
        super.onPause()
    }

    private fun handleLink(intent: Intent?) {
        val data = intent?.data ?: return
        if (data.scheme == "eduxgw" && Store.pairing(this) == null) pairFromLink(data.toString())
    }

    // --- Ko'rinish yordamchilari ---

    private fun text(value: String, size: Float = 15f, color: Int = Color.parseColor("#101828"), bold: Boolean = false): TextView =
        TextView(this).apply {
            text = value
            textSize = size
            setTextColor(color)
            if (bold) typeface = Typeface.DEFAULT_BOLD
            setPadding(0, dp(4), 0, dp(4))
        }

    private fun card(): LinearLayout = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(dp(16), dp(14), dp(16), dp(14))
        background = GradientDrawable().apply {
            setColor(Color.WHITE)
            cornerRadius = dp(14).toFloat()
            setStroke(dp(1), Color.parseColor("#E4E7EC"))
        }
        layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply { topMargin = dp(12) }
    }

    private fun button(label: String, primary: Boolean = true, action: () -> Unit): Button = Button(this).apply {
        text = label
        isAllCaps = false
        setTextColor(if (primary) Color.WHITE else brand)
        background = GradientDrawable().apply {
            setColor(if (primary) brand else Color.TRANSPARENT)
            cornerRadius = dp(10).toFloat()
            if (!primary) setStroke(dp(1), brand)
        }
        setOnClickListener { action() }
        layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply { topMargin = dp(8) }
    }

    private fun ago(time: Long): String =
        if (time <= 0) t("never") else DateUtils.getRelativeTimeSpanString(time, System.currentTimeMillis(), DateUtils.SECOND_IN_MILLIS).toString()

    // --- Ekranlar ---

    private fun render() {
        root.removeAllViews()
        refresh = null
        root.addView(text(t("title"), 24f, brand, bold = true))
        val pairing = Store.pairing(this)
        if (pairing == null) renderPairing() else renderStatus(pairing)
        root.addView(text(Texts.format(this, "version", BuildConfig.VERSION_NAME), 12f, muted).apply { gravity = Gravity.CENTER; setPadding(0, dp(18), 0, 0) })
    }

    private fun renderPairing() {
        root.addView(text(t("intro"), 15f, muted))
        val box = card()
        box.addView(text(t("pair_title"), 17f, bold = true))
        box.addView(text(t("pair_steps"), 14f, muted))
        box.addView(button(t("scan")) {
            scanner.launch(ScanOptions().setDesiredBarcodeFormats(ScanOptions.QR_CODE).setBeepEnabled(false).setOrientationLocked(true).setPrompt(t("scan")))
        })
        val server = EditText(this).apply {
            hint = t("server")
            inputType = InputType.TYPE_TEXT_VARIATION_URI
            setSingleLine()
        }
        val code = EditText(this).apply {
            hint = t("code")
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_CAP_CHARACTERS
            setSingleLine()
        }
        box.addView(server)
        box.addView(code)
        val status = text("", 14f, danger)
        box.addView(button(t("pair"), primary = false) {
            var url = server.text.toString().trim()
            if (url.isNotEmpty() && !url.startsWith("http")) url = "https://$url"
            pair(url, code.text.toString(), status)
        })
        box.addView(status)
        root.addView(box)
    }

    private fun pairFromLink(link: String) {
        val uri = Uri.parse(link.trim())
        val server = uri.getQueryParameter("s")
        val code = uri.getQueryParameter("c")
        if (uri.scheme != "eduxgw" || server.isNullOrEmpty() || code.isNullOrEmpty()) {
            render()
            root.addView(text(Texts.format(this, "pair_failed", link), 14f, danger))
            return
        }
        render()
        val status = text(t("pairing"), 14f, muted)
        root.addView(status)
        pair(server, code, status)
    }

    private fun pair(server: String, code: String, status: TextView) {
        if (busy || server.isEmpty() || code.isBlank()) return
        busy = true
        status.setTextColor(muted)
        status.text = t("pairing")
        Thread {
            val body = JSONObject()
                .put("code", code.trim())
                .put("device_id", Store.deviceId(this))
                .put("name", Device.name())
                .put("device_model", Device.model())
                .put("app_version", BuildConfig.VERSION_NAME)
            val response = try { Api.call(server, "POST", "gateway/pair", body) } catch (_: Exception) { null }
            runOnUiThread {
                busy = false
                when {
                    response == null -> { status.setTextColor(danger); status.text = t("no_internet") }
                    !response.ok -> {
                        val errors = response.json().optJSONObject("errors")
                        val message = errors?.optJSONArray("code")?.optString(0) ?: response.message()
                        status.setTextColor(danger)
                        status.text = Texts.format(this, "pair_failed", message)
                    }
                    else -> {
                        Store.savePairing(this, server.trimEnd('/'), response.json())
                        askPermissions()
                        if (!Device.batteryUnrestricted(this)) Device.requestBatteryExemption(this)
                        GatewayService.ensure(this)
                        Watchdog.schedule(this)
                        render()
                    }
                }
            }
        }.start()
    }

    private fun askPermissions() {
        val wanted = mutableListOf<String>()
        if (Store.smsOn(this)) wanted += Device.smsPermissions()
        if (Store.bankOn(this)) wanted += android.Manifest.permission.RECEIVE_SMS
        if (Store.callsOn(this)) wanted += Device.callPermissions()
        if (Store.sipOn(this)) wanted += android.Manifest.permission.RECORD_AUDIO
        if (Build.VERSION.SDK_INT >= 33) wanted += "android.permission.POST_NOTIFICATIONS"
        val missing = wanted.filter { !Device.granted(this, it) }
        if (missing.isNotEmpty()) permissions.launch(missing.toTypedArray())
    }

    private fun toggle(label: String, checked: Boolean, onChange: (Boolean) -> Unit): Switch = Switch(this).apply {
        text = label
        textSize = 16f
        typeface = Typeface.DEFAULT_BOLD
        isChecked = checked
        setOnCheckedChangeListener { _, on -> onChange(on) }
    }

    private fun applied(on: Boolean) {
        if (on) {
            askPermissions()
            GatewayService.ensure(this)
            GatewayService.poke(this)
            Watchdog.schedule(this)
        } else if (!Store.active(this)) {
            GatewayService.stop(this)
            Watchdog.cancel(this)
        } else {
            GatewayService.poke(this)
        }
    }

    private fun renderStatus(pairing: Store.Pairing) {
        root.addView(text(Texts.format(this, "paired_as", pairing.organizationName, pairing.userName), 15f, muted))
        val updates = mutableListOf<() -> Unit>()

        // Operator holati (call markaz).
        if (pairing.calls) {
            val box = card()
            box.addView(text(t("operator"), 15f, bold = true))
            val row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
            val chips = mutableMapOf<String, Button>()
            fun paint(current: String) {
                row.removeAllViews()
                for (key in listOf("available", "break", "offline")) {
                    val chip = Ui.chip(this, t("status_$key"), current == key) {
                        paint(key)
                        CallCenter.setStatus(this, key) { ok -> if (!ok) runOnUiThread { paint(Store.status(this, "calls").optString("operator", "offline")) } }
                    }
                    chips[key] = chip
                    row.addView(chip)
                }
            }
            paint(Store.status(this, "calls").optString("operator", "offline"))
            box.addView(row)
            root.addView(box)
        }

        if (pairing.sms) {
            val box = card()
            box.addView(toggle(t("sms"), Store.smsOn(this)) { on ->
                Store.setSms(this, on)
                if (on) Store.updateStatus(this, "sms") { it.remove("stopped") }
                applied(on)
                render()
            })
            val line1 = text("", 14f, muted)
            val line2 = text("", 13f, muted)
            val line3 = text("", 13f, danger)
            box.addView(line1); box.addView(line2); box.addView(line3)
            if (pairing.scope != "platform" && Store.smsOn(this)) {
                box.addView(toggle(t("bank"), Store.bankOn(this)) { on -> Store.setBank(this, on); applied(true); render() })
                if (Store.bankOn(this)) {
                    box.addView(text(t("bank_hint"), 13f, muted))
                    val senders = EditText(this).apply {
                        setText(Store.senders(this@MainActivity).joinToString(", "))
                        textSize = 13f
                        inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE
                    }
                    box.addView(senders)
                    box.addView(button(t("bank_save"), primary = false) { Store.setSenders(this, senders.text.toString()) })
                    val bank = text("", 13f, muted)
                    box.addView(bank)
                    updates += {
                        val status = Store.status(this, "sms")
                        bank.text = Texts.format(this, "bank_status", status.optInt("bank_sent")) +
                            status.optString("bank_error").let { if (it.isEmpty()) "" else " · $it" }
                    }
                }
            }
            root.addView(box)
            updates += {
                val status = Store.status(this, "sms")
                line1.text = Texts.format(this, "sms_status", status.optInt("sent"), status.optInt("failed"))
                line2.text = Texts.format(this, "last_poll", ago(status.optLong("last_poll")))
                val error = status.optString("last_error")
                line3.text = when {
                    status.has("stopped") -> Texts.format(this, "stopped", error)
                    error.isNotEmpty() && Store.smsOn(this) -> error
                    else -> ""
                }
                line3.visibility = if (line3.text.isEmpty()) View.GONE else View.VISIBLE
            }
        }

        if (pairing.calls) {
            val box = card()
            box.addView(toggle(t("calls"), Store.callsOn(this)) { on ->
                Store.setCalls(this, on)
                if (on) Store.updateStatus(this, "calls") { it.remove("stopped") }
                applied(on)
                render()
            })
            val line1 = text("", 14f, muted)
            val line2 = text("", 13f, muted)
            val line3 = text("", 13f, danger)
            box.addView(line1); box.addView(line2); box.addView(line3)
            if (Store.callsOn(this)) {
                box.addView(toggle(t("sip"), Store.sipOn(this)) { on -> Store.setSip(this, on); applied(true); render() })
                val sip = text("", 13f, muted)
                box.addView(sip)
                updates += {
                    val status = Store.status(this, "sip")
                    sip.text = when {
                        !Store.sipOn(this) -> ""
                        status.has("available") && !status.optBoolean("available") -> t("sip_unavailable")
                        SipPhone.registration == "failed" -> Texts.format(this, "sip_state_failed", SipPhone.lastError)
                        else -> t("sip_state_" + SipPhone.registration)
                    }
                    sip.setTextColor(if (SipPhone.registration == "ok") success else muted)
                    sip.visibility = if (sip.text.isEmpty()) View.GONE else View.VISIBLE
                }
                box.addView(button(t("queue_open"), primary = false) { startActivity(Intent(this, QueueActivity::class.java)) })
            }
            root.addView(box)
            updates += {
                val status = Store.status(this, "calls")
                line1.text = Texts.format(this, "calls_status", status.optInt("logged"), Store.pending(this).length(), status.optInt("dialed"))
                line2.text = Texts.format(this, "last_poll", ago(status.optLong("last_poll")))
                val error = status.optString("last_error")
                line3.text = when {
                    status.has("stopped") -> Texts.format(this, "stopped", error)
                    error.isNotEmpty() && Store.callsOn(this) -> error
                    else -> ""
                }
                line3.visibility = if (line3.text.isEmpty()) View.GONE else View.VISIBLE
            }
        }

        // Uzilmasligi uchun: har band — holat va «Tuzatish».
        val checks = card()
        checks.addView(text(t("check_title"), 17f, bold = true))
        fun check(label: String, ok: () -> Boolean, fix: () -> Unit) {
            val row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
            val mark = text("", 16f, success, bold = true).apply { setPadding(0, 0, dp(10), 0) }
            val title = text(label, 14f).apply { layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f) }
            val action = Button(this).apply {
                text = t("fix")
                isAllCaps = false
                setTextColor(brand)
                setBackgroundColor(Color.TRANSPARENT)
                setOnClickListener { fix() }
            }
            row.addView(mark)
            row.addView(title)
            row.addView(action)
            checks.addView(row)
            updates += {
                val good = ok()
                mark.text = if (good) t("ok") else t("bad")
                mark.setTextColor(if (good) success else danger)
                action.visibility = if (good) View.GONE else View.VISIBLE
            }
        }
        check(t("check_battery"), { Device.batteryUnrestricted(this) }) { Device.requestBatteryExemption(this) }
        check(t("check_notifications"), { Device.notificationsAllowed(this) }) { askPermissions(); Device.openAppSettings(this) }
        if (pairing.sms) check(t("check_sms"), { Device.smsPermissions().all { Device.granted(this, it) } && (!Store.bankOn(this) || Device.granted(this, android.Manifest.permission.RECEIVE_SMS)) }) { askPermissions() }
        if (pairing.calls) check(t("check_calls"), { Device.callPermissions().all { Device.granted(this, it) } }) { askPermissions() }
        if (Store.sipOn(this)) check(t("check_microphone"), { Device.granted(this, android.Manifest.permission.RECORD_AUDIO) }) { askPermissions() }
        check(t("check_data"), { Device.backgroundDataAllowed(this) }) { Device.openDataSaver(this) }
        if (Device.hasAutostart(this)) {
            checks.addView(text(t("check_autostart"), 14f))
            checks.addView(button(t("open"), primary = false) { Device.openAutostart(this) })
        }
        checks.addView(text(t("tip"), 13f, muted))
        root.addView(checks)

        // Diagnostika: server tomonidan ko'rinadigan holat (SMS kanali, ro'yxat, call markaz, SIP).
        val diag = card()
        val diagText = text("", 13f, muted)
        diag.addView(button(t("diagnose"), primary = false) { diagnose(pairing, diagText) })
        diag.addView(diagText)
        root.addView(diag)

        root.addView(button(t("unpair"), primary = false) { confirmUnpair(pairing) })
        refresh = { updates.forEach { it() } }
        refresh?.invoke()
    }

    private fun diagnose(pairing: Store.Pairing, out: TextView) {
        out.setTextColor(muted)
        out.text = t("diag_running")
        Thread {
            val lines = mutableListOf<String>()
            lines += "${if (GatewayService.running) "✓" else "✗"} ${t("diag_service")}"
            val response = try { Api.call(pairing, Store.deviceId(this), "GET", "gateway/me") } catch (e: Exception) { null }
            when {
                response == null -> lines += "✗ ${t("diag_server")}: ${t("no_internet")}"
                response.revoked -> lines += "✗ ${t("diag_token")}: ${response.message()}"
                !response.ok -> lines += "✗ ${t("diag_server")}: ${response.message()}"
                else -> {
                    lines += "✓ ${t("diag_server")}"
                    val rows = response.json().optJSONArray("diagnostics")
                    for (i in 0 until (rows?.length() ?: 0)) {
                        val row = rows!!.getJSONObject(i)
                        lines += "${if (row.optBoolean("ok")) "✓" else "✗"} ${row.optString("note")}"
                    }
                }
            }
            if (Store.sipOn(this)) lines += "${if (SipPhone.ready()) "✓" else "✗"} ${t("diag_sip")}: ${t("sip_state_" + SipPhone.registration)} ${SipPhone.lastError}"
            GatewayService.poke(this)
            runOnUiThread {
                out.setTextColor(Color.parseColor("#101828"))
                out.text = lines.joinToString("\n")
            }
        }.start()
    }

    private fun confirmUnpair(pairing: Store.Pairing) {
        AlertDialog.Builder(this)
            .setMessage(t("unpair_confirm"))
            .setPositiveButton(t("yes")) { _, _ ->
                val deviceId = Store.deviceId(this)
                Thread {
                    // Serverdagi yozuvlar ham o'chadi (internet bo'lmasa — rahbar vebda uzadi).
                    try {
                        val body = JSONObject().put("device_id", deviceId)
                        if (pairing.sms) Api.call(pairing, deviceId, "POST", "${pairing.smsPrefix}/unregister", body)
                        if (pairing.calls) Api.call(pairing, deviceId, "POST", "crm/callcenter/phone/unregister", body)
                        Api.call(pairing, deviceId, "POST", "gateway/unpair", JSONObject())
                    } catch (_: Exception) {}
                }.start()
                Store.clear(this)
                GatewayService.stop(this)
                Watchdog.cancel(this)
                render()
            }
            .setNegativeButton(t("no"), null)
            .show()
    }
}
