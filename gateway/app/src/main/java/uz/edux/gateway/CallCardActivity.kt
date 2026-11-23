package uz.edux.gateway

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import android.text.InputType
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.RadioButton
import android.widget.RadioGroup
import android.widget.ScrollView
import android.widget.Toast
import org.json.JSONArray
import org.json.JSONObject
import java.net.URLEncoder

/**
 * Qo'ng'iroq kartasi: kim (lid, o'quvchi, ota-ona, so'nggi qo'ng'iroqlar), skriptlar va natija (qiziqdi, sinov darsi,
 * qayta qo'ng'iroq ...). Natija — POST crm/callcenter/calls/{id}/outcome; id noma'lum bo'lsa (SIP) — phone/recent.
 */
class CallCardActivity : Activity() {
    companion object {
        fun intent(context: Context, phone: String, callId: Long, outcome: Boolean): Intent =
            Intent(context, CallCardActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                .putExtra("phone", phone).putExtra("call_id", callId).putExtra("outcome", outcome)
                // Har karta alohida (bildirishnomalar bir-birini almashtirmasin).
                .setData(android.net.Uri.parse("eduxgw://card/$callId/${phone.filter { it.isDigit() }}"))
    }

    private lateinit var root: LinearLayout
    private var phone = ""
    private var callId = 0L
    private var busy = false

    private fun t(key: String) = Texts.get(this, key)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        phone = intent.getStringExtra("phone") ?: ""
        callId = intent.getLongExtra("call_id", 0)
        val scroll = ScrollView(this).apply { setBackgroundColor(Color.parseColor("#F5F7F8")) }
        root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(Ui.dp(this@CallCardActivity, 18), Ui.dp(this@CallCardActivity, 24), Ui.dp(this@CallCardActivity, 18), Ui.dp(this@CallCardActivity, 32))
        }
        scroll.addView(root)
        setContentView(scroll)
        root.addView(Ui.text(this, phone, 24f, Ui.BRAND, bold = true))
        root.addView(Ui.text(this, t("loading"), 14f, Ui.MUTED))
        Thread {
            val card = CallCenter.caller(this, phone)
            runOnUiThread { render(card) }
        }.start()
    }

    private fun render(card: JSONObject?) {
        root.removeAllViews()
        root.addView(Ui.text(this, phone, 24f, Ui.BRAND, bold = true))
        if (card == null) {
            root.addView(Ui.text(this, t("card_failed"), 14f, Ui.DANGER))
        } else {
            val info = Ui.card(this)
            info.addView(Ui.text(this, CallCenter.summary(this, card) ?: "", 16f, bold = true))
            val students = card.optJSONArray("students") ?: JSONArray()
            for (i in 0 until students.length()) {
                val s = students.getJSONObject(i)
                val balance = s.opt("balance")
                if (balance != null && balance != JSONObject.NULL) info.addView(Ui.text(this, Texts.format(this, "card_balance", s.optString("name"), balance.toString()), 14f, Ui.MUTED))
            }
            val calls = card.optJSONArray("calls") ?: JSONArray()
            if (calls.length() > 0) info.addView(Ui.text(this, t("card_calls"), 14f, bold = true))
            for (i in 0 until minOf(3, calls.length())) {
                val c = calls.getJSONObject(i)
                val line = listOf(c.optString("created_at").take(16).replace("T", " "), c.optString("direction"), c.optString("result"), c.optString("outcome"))
                    .filter { it.isNotEmpty() && it != "null" }.joinToString(" · ")
                info.addView(Ui.text(this, line, 13f, Ui.MUTED))
            }
            root.addView(info)
            val scripts = card.optJSONArray("scripts") ?: JSONArray()
            if (scripts.length() > 0) {
                val box = Ui.card(this)
                box.addView(Ui.text(this, t("card_scripts"), 15f, bold = true))
                for (i in 0 until scripts.length()) {
                    val s = scripts.getJSONObject(i)
                    box.addView(Ui.text(this, s.optString("title"), 14f, bold = true))
                    box.addView(Ui.text(this, s.optString("body"), 14f, Ui.MUTED))
                }
                root.addView(box)
            }
            outcomeForm(card.optJSONObject("outcomes") ?: JSONObject())
        }
        root.addView(Ui.button(this, t("card_call"), primary = false) { CallCenter.dial(this, phone) })
    }

    private fun outcomeForm(outcomes: JSONObject) {
        if (outcomes.length() == 0) return
        val box = Ui.card(this)
        box.addView(Ui.text(this, t("outcome_title"), 16f, bold = true))
        val group = RadioGroup(this)
        val keys = outcomes.keys().asSequence().toList()
        keys.forEachIndexed { index, key ->
            group.addView(RadioButton(this).apply { id = index + 1; text = outcomes.optString(key); textSize = 15f })
        }
        box.addView(group)
        val note = EditText(this).apply {
            hint = t("outcome_note")
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_CAP_SENTENCES or InputType.TYPE_TEXT_FLAG_MULTI_LINE
        }
        box.addView(note)
        val status = Ui.text(this, "", 14f, Ui.DANGER)
        box.addView(Ui.button(this, t("outcome_save")) {
            val selected = group.checkedRadioButtonId
            if (selected <= 0 || busy) return@button
            busy = true
            status.setTextColor(Ui.MUTED)
            status.text = t("loading")
            val outcome = keys[selected - 1]
            Thread {
                var id = callId
                if (id == 0L) {
                    val recent = CallCenter.call(this, "GET", "crm/callcenter/phone/recent?phone=" + URLEncoder.encode(phone, "UTF-8"))
                    id = recent?.json()?.optJSONObject("call")?.optLong("id") ?: 0L
                }
                val response = if (id > 0) CallCenter.call(this, "POST", "crm/callcenter/calls/$id/outcome",
                    JSONObject().put("outcome", outcome).apply { if (note.text.isNotBlank()) put("note", note.text.toString().take(255)) }) else null
                runOnUiThread {
                    busy = false
                    if (response?.ok == true) {
                        CallCenter.clearOutcome(this)
                        Toast.makeText(this, t("outcome_saved"), Toast.LENGTH_SHORT).show()
                        finish()
                    } else {
                        status.setTextColor(Ui.DANGER)
                        status.text = if (id == 0L) t("outcome_no_call") else (response?.message() ?: t("no_internet"))
                    }
                }
            }.start()
        })
        box.addView(status)
        root.addView(box)
    }
}
