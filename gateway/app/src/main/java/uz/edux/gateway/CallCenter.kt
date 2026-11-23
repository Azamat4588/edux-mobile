package uz.edux.gateway

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject
import java.net.URLEncoder

/**
 * Call markaz (1.1): operator holati, qo'ng'iroq qiluvchi kartasi (kiruvchi qo'ng'iroq jiringlaganda — bildirishnoma),
 * qo'ng'iroqdan keyin natija (bildirishnoma → CallCardActivity), qayta qo'ng'iroqlar navbati. Hamma so'rovlar fon ipida.
 */
object CallCenter {
    const val CARD_CHANNEL = "edux_gateway_card"
    private const val CARD_ID = 5201
    private const val OUTCOME_ID = 5202

    private fun pairing(context: Context): Store.Pairing? = Store.pairing(context)?.takeIf { it.calls }

    fun call(context: Context, method: String, path: String, body: JSONObject? = null): Api.Response? {
        val pairing = pairing(context) ?: return null
        return try { Api.call(pairing, Store.deviceId(context), method, path, body) } catch (_: Exception) { null }
    }

    /** Operator holati: available | break | offline. */
    fun setStatus(context: Context, status: String, done: (Boolean) -> Unit) {
        Thread {
            val response = call(context, "PUT", "crm/callcenter/status", JSONObject().put("status", status))
            if (response?.ok == true) Store.updateStatus(context, "calls") { it.put("operator", status) }
            done(response?.ok == true)
            GatewayService.poke(context) // so'rov oralig'i holatga qarab o'zgaradi
        }.start()
    }

    fun caller(context: Context, phone: String): JSONObject? {
        val response = call(context, "GET", "crm/callcenter/caller?phone=" + URLEncoder.encode(phone, "UTF-8")) ?: return null
        return if (response.ok) response.json() else null
    }

    /** Karta uchun qisqa matn: «Qodirov Sanjar · o'quvchi · M-11» yoki «Lid: Aziza (yangi)». */
    fun summary(context: Context, card: JSONObject?): String? {
        if (card == null) return null
        val students = card.optJSONArray("students") ?: JSONArray()
        if (students.length() > 0) {
            val s = students.getJSONObject(0)
            val groups = s.optJSONArray("groups")?.let { g -> (0 until g.length()).joinToString(", ") { g.optString(it) } } ?: ""
            val who = if (s.optBoolean("parent")) Texts.format(context, "card_parent", s.optString("parent_name").ifEmpty { "—" }) else Texts.get(context, "card_student")
            return listOf(s.optString("name"), who, groups).filter { it.isNotEmpty() }.joinToString(" · ")
        }
        val leads = card.optJSONArray("leads") ?: JSONArray()
        if (leads.length() > 0) {
            val l = leads.getJSONObject(0)
            return listOf(Texts.get(context, "card_lead") + ": " + l.optString("name"), l.optString("interest")).filter { it.isNotBlank() }.joinToString(" · ")
        }
        return Texts.get(context, "card_unknown")
    }

    private fun channel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(NotificationChannel(CARD_CHANNEL, Texts.get(context, "channel_card"), NotificationManager.IMPORTANCE_HIGH))
        }
    }

    private fun builder(context: Context): Notification.Builder =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(context, CARD_CHANNEL) else @Suppress("DEPRECATION") Notification.Builder(context)

    /** Kiruvchi qo'ng'iroq jiringlayapti — kim ekanini darhol ko'rsatish (SIM qo'ng'irog'i uchun). */
    fun showCaller(context: Context, phone: String) {
        Thread {
            val card = caller(context, phone)
            val text = summary(context, card) ?: return@Thread
            channel(context)
            val open = PendingIntent.getActivity(context, 10, CallCardActivity.intent(context, phone, 0, false),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val note = builder(context).setSmallIcon(R.drawable.ic_notification)
                .setContentTitle(phone)
                .setContentText(text)
                .setStyle(Notification.BigTextStyle().bigText(text))
                .setContentIntent(open)
                .setAutoCancel(true)
                .setTimeoutAfter(120000)
                .build()
            try { (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).notify(CARD_ID, note) } catch (_: Exception) {}
        }.start()
    }

    /** Qo'ng'iroq tugadi — natija yozish taklifi. callId = 0: SIP qo'ng'irog'i (id serverdan raqam bo'yicha olinadi). */
    fun askOutcome(context: Context, phone: String, callId: Long) {
        channel(context)
        val open = PendingIntent.getActivity(context, 11, CallCardActivity.intent(context, phone, callId, true),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val note = builder(context).setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(Texts.get(context, "outcome_title"))
            .setContentText(Texts.format(context, "outcome_body", phone))
            .setContentIntent(open)
            .setAutoCancel(true)
            .setTimeoutAfter(6 * 60 * 60 * 1000L)
            .build()
        try {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.cancel(CARD_ID)
            manager.notify(OUTCOME_ID, note)
        } catch (_: Exception) {}
    }

    fun clearOutcome(context: Context) {
        try { (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(OUTCOME_ID) } catch (_: Exception) {}
    }

    /** Raqamni terish: SIP ulangan bo'lsa — softfon orqali, aks holda SIM (CALL_PHONE bo'lsa darhol, yo'qsa terish oynasi). */
    fun dial(context: Context, phone: String) {
        if (SipPhone.ready()) {
            SipPhone.dial(context, phone)
            return
        }
        val uri = android.net.Uri.fromParts("tel", phone, null)
        if (Device.granted(context, android.Manifest.permission.CALL_PHONE)) {
            try {
                (context.getSystemService(Context.TELECOM_SERVICE) as android.telecom.TelecomManager).placeCall(uri, android.os.Bundle())
                return
            } catch (_: Exception) {}
        }
        try { context.startActivity(Intent(Intent.ACTION_DIAL, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) } catch (_: Exception) {}
    }
}
