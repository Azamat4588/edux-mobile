package uz.edux.gateway

import android.Manifest
import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.telephony.SmsManager
import org.json.JSONArray
import org.json.JSONObject
import java.net.URLEncoder
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference

/**
 * SMS shlyuz: serverdagi navbatdan SMS'larni olib (GET next), shu telefon SIM kartasidan yuboradi va natijani
 * qaytaradi (POST report). Chegaralar, tanaffus va boshqa telefonga o'tkazish — serverda (PhonePool).
 */
class SmsEngine(private val context: Context) {
    private val ids = AtomicInteger(10000)
    private val thread: HandlerThread by lazy { HandlerThread("edux-sms-results").apply { start() } }
    private var registered = false

    /** Bir aylanish. Qaytaradi: keyingi tekshiruvgacha kutish (ms); 0 — darhol yana. */
    fun cycle(pairing: Store.Pairing, deviceId: String): Long {
        if (!registered) {
            val reg = Api.call(pairing, deviceId, "POST", "${pairing.smsPrefix}/register",
                JSONObject().put("name", Device.name()).put("device_model", Device.model()).put("device_id", deviceId))
            if (reg.revoked) return revoked(reg)
            if (!reg.ok) return failed(reg.message())
            registered = true
        }
        flushBank(pairing, deviceId)
        val next = Api.call(pairing, deviceId, "GET", "${pairing.smsPrefix}/next?limit=10&device_id=" + URLEncoder.encode(deviceId, "UTF-8"))
        if (next.revoked || next.code == 404) return revoked(next)
        if (!next.ok) return failed(next.message())
        val data = next.json()
        val messages = data.optJSONArray("messages") ?: JSONArray()
        Store.updateStatus(context, "sms") {
            it.put("last_poll", System.currentTimeMillis()).remove("last_error")
            it.put("paused_until", data.optString("paused_until", ""))
        }
        if (messages.length() == 0) return IDLE_MS
        val pause = data.optLong("pause_ms", 5000).coerceIn(500L, 120000L)
        val results = JSONArray()
        for (i in 0 until messages.length()) {
            val item = messages.getJSONObject(i)
            val error = send(item.optString("phone"), item.optString("body"))
            results.put(JSONObject().put("id", item.optLong("id")).put("ok", error == null).apply { if (error != null) put("error", error) })
            Store.updateStatus(context, "sms") {
                if (error == null) {
                    it.put("sent", it.optInt("sent") + 1).put("last_sent", System.currentTimeMillis())
                } else {
                    it.put("failed", it.optInt("failed") + 1).put("last_error", error)
                }
            }
            if (i < messages.length() - 1) Thread.sleep(pause)
        }
        // Natija yuborilmasa — server 10 daqiqadan keyin xabarlarni qayta navbatga qo'yadi (takror yuborilishi mumkin),
        // shuning uchun bir necha marta urinamiz.
        var reported = false
        for (attempt in 1..3) {
            val report = Api.call(pairing, deviceId, "POST", "${pairing.smsPrefix}/report", JSONObject().put("device_id", deviceId).put("results", results))
            if (report.ok || report.code in 400..499) {
                reported = true
                break
            }
            Thread.sleep(3000L * attempt)
        }
        if (!reported) return failed("report")
        val full = messages.length() >= 10 && data.isNull("paused_until")
        return if (full) 0 else pause.coerceAtLeast(2000)
    }

    /** Bank SMS'lari navbatini serverga yuboradi (kartaga o'tkazmani avtomatik tasdiqlash uchun). */
    private fun flushBank(pairing: Store.Pairing, deviceId: String) {
        if (pairing.scope == "platform") return
        while (true) {
            val items = Store.bankPending(context)
            if (items.length() == 0) return
            val batch = JSONArray()
            for (i in 0 until minOf(50, items.length())) batch.put(items.get(i))
            val response = Api.call(pairing, deviceId, "POST", "crm/sms/gateway/incoming", JSONObject().put("device_id", deviceId).put("messages", batch))
            if (!response.ok && response.code != 422) {
                Store.updateStatus(context, "sms") { it.put("bank_error", response.message()) }
                return
            }
            Store.dropBank(context, batch.length())
            Store.updateStatus(context, "sms") {
                it.put("bank_sent", it.optInt("bank_sent") + batch.length()).remove("bank_error")
            }
            // Server sozlamada SMS manbasini o'chirgan — bank SMS'larini yig'ish to'xtaydi.
            if (response.ok && !response.json().optBoolean("enabled", true)) {
                Store.setBank(context, false)
                Store.updateStatus(context, "sms") { it.put("bank_error", "server: disabled") }
                return
            }
        }
    }

    fun reset() {
        registered = false
    }

    private fun revoked(response: Api.Response): Long {
        registered = false
        Store.updateStatus(context, "sms") { it.put("last_error", response.message()).put("stopped", response.code) }
        Store.setSms(context, false)
        return -1
    }

    private fun failed(error: String): Long {
        Store.updateStatus(context, "sms") { it.put("last_error", error).put("last_poll", System.currentTimeMillis()) }
        return ERROR_MS
    }

    @Suppress("DEPRECATION")
    private fun manager(): SmsManager =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) context.getSystemService(SmsManager::class.java) else SmsManager.getDefault()

    /** null — yuborildi; aks holda xato matni. Natija operatordan kutiladi (60 s). */
    private fun send(phone: String, body: String): String? {
        if (context.checkSelfPermission(Manifest.permission.SEND_SMS) != PackageManager.PERMISSION_GRANTED) return "no_permission"
        if (phone.isBlank() || body.isBlank()) return "bad_args"
        val manager = manager()
        val parts = manager.divideMessage(body)
        val action = "uz.edux.gateway.SMS_SENT_" + ids.getAndIncrement()
        val latch = CountDownLatch(parts.size)
        val failed = AtomicReference<String?>(null)
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (resultCode != Activity.RESULT_OK) failed.compareAndSet(null, "error code $resultCode")
                latch.countDown()
            }
        }
        val handler = Handler(thread.looper)
        val filter = IntentFilter(action)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(receiver, filter, null, handler, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            context.registerReceiver(receiver, filter, null, handler)
        }
        try {
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            val intents = ArrayList<PendingIntent>()
            for (i in parts.indices) {
                intents.add(PendingIntent.getBroadcast(context, ids.getAndIncrement(), Intent(action).setPackage(context.packageName), flags))
            }
            if (parts.size > 1) manager.sendMultipartTextMessage(phone, null, parts, intents, null)
            else manager.sendTextMessage(phone, null, body, intents[0], null)
            if (!latch.await(60, TimeUnit.SECONDS)) return "timeout"
            return failed.get()
        } catch (e: Exception) {
            return e.message ?: "send error"
        } finally {
            try { context.unregisterReceiver(receiver) } catch (_: Exception) {}
        }
    }

    companion object {
        const val IDLE_MS = 15000L
        const val ERROR_MS = 30000L
    }
}
