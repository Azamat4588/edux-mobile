package uz.edux.gateway

import android.app.Activity
import android.graphics.Color
import android.os.Bundle
import android.widget.LinearLayout
import android.widget.ScrollView
import org.json.JSONArray

/** Qayta qo'ng'iroqlar navbati: javobsiz qolgan qo'ng'iroqlar (GET crm/callcenter/queue) — qo'ng'iroq qilish yoki «bajarildi». */
class QueueActivity : Activity() {
    private lateinit var root: LinearLayout

    private fun t(key: String) = Texts.get(this, key)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val scroll = ScrollView(this).apply { setBackgroundColor(Color.parseColor("#F5F7F8")) }
        root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(Ui.dp(this@QueueActivity, 18), Ui.dp(this@QueueActivity, 24), Ui.dp(this@QueueActivity, 18), Ui.dp(this@QueueActivity, 32))
        }
        scroll.addView(root)
        setContentView(scroll)
    }

    override fun onResume() {
        super.onResume()
        load()
    }

    private fun load() {
        root.removeAllViews()
        root.addView(Ui.text(this, t("queue_title"), 22f, Ui.BRAND, bold = true))
        root.addView(Ui.text(this, t("loading"), 14f, Ui.MUTED))
        Thread {
            val response = CallCenter.call(this, "GET", "crm/callcenter/queue")
            runOnUiThread { render(if (response?.ok == true) response.json().optJSONArray("data") ?: JSONArray() else null) }
        }.start()
    }

    private fun render(items: JSONArray?) {
        root.removeAllViews()
        root.addView(Ui.text(this, t("queue_title"), 22f, Ui.BRAND, bold = true))
        if (items == null) {
            root.addView(Ui.text(this, t("no_internet"), 14f, Ui.DANGER))
        } else if (items.length() == 0) {
            root.addView(Ui.text(this, t("queue_empty"), 15f, Ui.MUTED))
        }
        for (i in 0 until (items?.length() ?: 0)) {
            val item = items!!.getJSONObject(i)
            val phone = item.optString("phone")
            val box = Ui.card(this)
            box.addView(Ui.text(this, item.optString("caller").takeIf { it.isNotEmpty() && it != "null" } ?: phone, 16f, bold = true))
            box.addView(Ui.text(this, Texts.format(this, "queue_line", phone, item.optString("created_at").take(16).replace("T", " "), item.optInt("attempts")), 13f, Ui.MUTED))
            val row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
            row.addView(Ui.chip(this, t("card_call"), true) { CallCenter.dial(this, phone) })
            row.addView(Ui.chip(this, t("queue_card"), false) { startActivity(CallCardActivity.intent(this, phone, item.optLong("id"), true)) })
            row.addView(Ui.chip(this, t("queue_done"), false) {
                Thread {
                    CallCenter.call(this, "POST", "crm/callcenter/calls/${item.optLong("id")}/handled", org.json.JSONObject())
                    runOnUiThread { load() }
                }.start()
            })
            box.addView(row)
            root.addView(box)
        }
        root.addView(Ui.button(this, t("refresh"), primary = false) { load() })
    }
}
