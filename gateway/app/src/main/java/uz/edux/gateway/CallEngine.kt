package uz.edux.gateway

import android.Manifest
import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.CallLog
import android.telephony.TelephonyManager
import org.json.JSONArray
import org.json.JSONObject
import java.net.URLEncoder

/**
 * Qo'ng'iroqlar («Telefon orqali» call markaz): telefon holati (jiringlash → ko'tarildi → tugadi), tugagach qo'ng'iroqlar
 * jurnalidan raqam, davomiylik va natija serverga (POST crm/callcenter/phone/events; internet bo'lmasa navbatda);
 * vebdan «Qo'ng'iroq» bosilsa raqamni teradi (GET phone/next).
 */
class CallEngine(private val context: Context, private val wake: () -> Unit) {
    /** Joriy qo'ng'iroq. */
    private class Current(val id: String, val direction: String, var number: String?, val startedAt: Long) {
        var answeredAt: Long = 0
        var ringingSent = false
    }

    private var current: Current? = null
    private var lastDialNumber: String? = null
    private var lastDialAt: Long = 0
    private var registered = false
    private val main = Handler(Looper.getMainLooper())

    fun reset() {
        registered = false
    }

    // --- Telefon holati (GatewayService qabul qiluvchisidan) ---

    private fun clean(number: String?): String? {
        val value = number?.filter { it.isDigit() || it == '+' }
        return if (value.isNullOrEmpty()) null else value
    }

    private fun event(call: Current, phase: String): JSONObject {
        val row = JSONObject().put("id", call.id).put("phase", phase).put("direction", call.direction)
        if (call.number != null) row.put("phone", call.number)
        return row
    }

    @Synchronized
    fun onState(state: String, rawNumber: String?) {
        if (!Store.callsOn(context)) return
        val now = System.currentTimeMillis()
        val number = clean(rawNumber)
        when (state) {
            TelephonyManager.EXTRA_STATE_RINGING -> {
                val call = current ?: Current(now.toString(), "in", number, now).also { current = it }
                if (call.number == null && number != null) call.number = number
                if (!call.ringingSent && call.number != null) {
                    call.ringingSent = true
                    Store.enqueue(context, event(call, "ringing"))
                    wake()
                    // Kim qo'ng'iroq qilyapti — lid yoki o'quvchi kartasi bildirishnomada.
                    CallCenter.showCaller(context, call.number!!)
                }
            }
            TelephonyManager.EXTRA_STATE_OFFHOOK -> {
                var call = current
                if (call == null) {
                    // Jiringlashsiz ko'tarilish — chiquvchi qo'ng'iroq (raqam: vebdan terilgan bo'lsa ma'lum, aks holda jurnaldan).
                    val dialed = if (now - lastDialAt < 60000) lastDialNumber else null
                    call = Current(now.toString(), "out", dialed, now)
                    current = call
                }
                if (call.answeredAt == 0L) {
                    call.answeredAt = now
                    if (call.number != null) {
                        Store.enqueue(context, event(call, if (call.direction == "in") "talking" else "ringing"))
                        wake()
                    }
                }
            }
            TelephonyManager.EXTRA_STATE_IDLE -> {
                val call = current ?: return
                current = null
                // Qo'ng'iroqlar jurnali yozilishiga ulgursin.
                main.postDelayed({ Thread { finish(call, now) }.start() }, 2500)
            }
        }
    }

    private fun finish(call: Current, endedAt: Long) {
        val row = event(call, "end")
        var number = call.number
        var direction = call.direction
        var duration = if (call.answeredAt > 0) ((endedAt - call.answeredAt) / 1000).toInt() else 0
        var result = if (call.answeredAt > 0) "answered" else "no_answer"
        val log = readCallLog(call.startedAt - 15000)
        if (log != null) {
            number = log.optString("number").ifEmpty { number }
            direction = log.optString("direction", direction)
            duration = log.optInt("duration", duration)
            result = log.optString("result", result)
        }
        if (number == null) return // yashirin raqam — yozilmaydi
        row.put("phone", number).put("direction", direction).put("duration", duration).put("result", result)
        Store.enqueue(context, row)
        wake()
    }

    /** Qo'ng'iroqlar jurnalidagi shu qo'ng'iroq (since dan keyingi eng yangisi). */
    private fun readCallLog(since: Long): JSONObject? {
        if (!Device.granted(context, Manifest.permission.READ_CALL_LOG)) return null
        return try {
            context.contentResolver.query(
                CallLog.Calls.CONTENT_URI,
                arrayOf(CallLog.Calls.NUMBER, CallLog.Calls.TYPE, CallLog.Calls.DURATION),
                "${CallLog.Calls.DATE} >= ?", arrayOf(since.toString()), "${CallLog.Calls.DATE} DESC",
            )?.use { cursor ->
                if (!cursor.moveToFirst()) return null
                val type = cursor.getInt(1)
                val duration = cursor.getInt(2)
                val pair: Pair<String, String> = when (type) {
                    CallLog.Calls.OUTGOING_TYPE -> "out" to (if (duration > 0) "answered" else "no_answer")
                    CallLog.Calls.INCOMING_TYPE -> "in" to "answered"
                    CallLog.Calls.REJECTED_TYPE -> "in" to "rejected"
                    CallLog.Calls.BLOCKED_TYPE -> return null
                    else -> "in" to "no_answer" // MISSED, VOICEMAIL
                }
                JSONObject().put("number", clean(cursor.getString(0)) ?: "").put("direction", pair.first).put("duration", duration).put("result", pair.second)
            }
        } catch (_: Exception) {
            null
        }
    }

    // --- Server bilan ---

    private fun permissionsQuery(): String {
        val map = mapOf(
            "call_log" to Device.granted(context, Manifest.permission.READ_CALL_LOG),
            "phone_state" to Device.granted(context, Manifest.permission.READ_PHONE_STATE),
            "call_phone" to Device.granted(context, Manifest.permission.CALL_PHONE),
        )
        return map.entries.joinToString("") { "&permissions%5B${it.key}%5D=${if (it.value) 1 else 0}" }
    }

    /** Bir aylanish: hodisalarni yuborish va terish buyrug'ini olish. Qaytaradi: kutish (ms), -1 — to'xtatildi. */
    fun cycle(pairing: Store.Pairing, deviceId: String): Long {
        val fresh = !registered
        if (!registered) {
            val permissions = JSONObject()
                .put("call_log", Device.granted(context, Manifest.permission.READ_CALL_LOG))
                .put("phone_state", Device.granted(context, Manifest.permission.READ_PHONE_STATE))
                .put("call_phone", Device.granted(context, Manifest.permission.CALL_PHONE))
            val reg = Api.call(pairing, deviceId, "POST", "crm/callcenter/phone/register",
                JSONObject().put("device_id", deviceId).put("name", Device.name()).put("device_model", Device.model()).put("permissions", permissions))
            if (reg.revoked) return revoked(reg)
            if (!reg.ok) return failed(reg.message())
            registered = true
        }
        flush(pairing, deviceId)?.let { return it }
        val next = Api.call(pairing, deviceId, "GET", "crm/callcenter/phone/next?device_id=" + URLEncoder.encode(deviceId, "UTF-8") + permissionsQuery())
        if (next.revoked || next.code == 404) {
            // 404: yozuv o'chirilgan bo'lsa — qayta ro'yxatdan o'tamiz; yangi ro'yxatdan keyin ham 404 — rahbar o'chirgan.
            if (next.code == 404 && !fresh) {
                registered = false
                return failed(next.message())
            }
            return revoked(next)
        }
        if (!next.ok) return failed(next.message())
        val data = next.json()
        val pollMs = data.optLong("poll_ms", 30000).coerceIn(3000L, 120000L)
        Store.updateStatus(context, "calls") {
            it.put("last_poll", System.currentTimeMillis()).put("log", data.optString("log", "all")).remove("last_error")
            it.put("operator", data.optString("status", "offline"))
            it.put("pending", Store.pending(context).length())
        }
        val dial = data.optJSONObject("dial")
        if (dial != null && dial.optString("phone").isNotEmpty()) {
            dial(dial.optString("phone"))
            Store.updateStatus(context, "calls") { it.put("dialed", it.optInt("dialed") + 1) }
        }
        return pollMs
    }

    /** Navbatdagi hodisalarni yuboradi. null — davom etish; son — shu kutish bilan to'xtash. */
    private fun flush(pairing: Store.Pairing, deviceId: String): Long? {
        while (true) {
            val events = Store.pending(context)
            if (events.length() == 0) return null
            val batch = JSONArray()
            for (i in 0 until minOf(50, events.length())) batch.put(events.get(i))
            val response = Api.call(pairing, deviceId, "POST", "crm/callcenter/phone/events", JSONObject().put("device_id", deviceId).put("events", batch))
            if (response.revoked) return revoked(response)
            if (response.code == 404) {
                registered = false
                return failed(response.message())
            }
            if (response.code == 422 || response.ok) {
                // 422 — noto'g'ri hodisa: qayta yuborilmaydi (navbat tiqilib qolmasin).
                Store.drop(context, batch.length())
                val logged = response.json().optInt("logged")
                // Gaplashilgan qo'ng'iroqqa natija yozish taklifi (qiziqdi, sinov darsi, qayta qo'ng'iroq ...).
                val created = response.json().optJSONArray("calls") ?: JSONArray()
                for (i in 0 until created.length()) {
                    val item = created.getJSONObject(i)
                    for (j in 0 until batch.length()) {
                        val row = batch.getJSONObject(j)
                        if (row.optString("id") == item.optString("event") && row.optString("phase") == "end" && row.optString("result") == "answered") {
                            CallCenter.askOutcome(context, row.optString("phone"), item.optLong("call_id"))
                        }
                    }
                }
                Store.updateStatus(context, "calls") {
                    it.put("logged", it.optInt("logged") + logged).put("pending", Store.pending(context).length())
                    if (logged > 0) it.put("last_call", System.currentTimeMillis())
                    if (!response.ok) it.put("last_error", response.message())
                }
                continue
            }
            return failed(response.message())
        }
    }

    private fun revoked(response: Api.Response): Long {
        registered = false
        Store.updateStatus(context, "calls") { it.put("last_error", response.message()).put("stopped", response.code) }
        Store.setCalls(context, false)
        return -1
    }

    private fun failed(error: String): Long {
        Store.updateStatus(context, "calls") { it.put("last_error", error).put("last_poll", System.currentTimeMillis()) }
        return 20000
    }

    /** Vebdan «Qo'ng'iroq»: raqamni terish (SIP ulangan bo'lsa — softfon, aks holda SIM). */
    private fun dial(phone: String) {
        lastDialNumber = clean(phone)
        lastDialAt = System.currentTimeMillis()
        if (SipPhone.ready() || Device.granted(context, Manifest.permission.CALL_PHONE)) {
            CallCenter.dial(context, phone)
            return
        }
        // Ruxsat yo'q: bildirishnoma — bosilsa terish oynasi (fonda oyna ochib bo'lmaydi).
        try {
            val uri = Uri.fromParts("tel", phone, null)
            val tap = PendingIntent.getActivity(context, 2, Intent(Intent.ACTION_DIAL, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(context, GatewayService.DIAL_CHANNEL) else @Suppress("DEPRECATION") Notification.Builder(context)
            val note = builder.setSmallIcon(R.drawable.ic_notification)
                .setContentTitle(Texts.get(context, "dial_title"))
                .setContentText(Texts.get(context, "dial_body").replace("{0}", phone))
                .setContentIntent(tap).setAutoCancel(true).build()
            (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).notify(GatewayService.DIAL_NOTIFICATION_ID, note)
        } catch (_: Exception) {}
    }

}
