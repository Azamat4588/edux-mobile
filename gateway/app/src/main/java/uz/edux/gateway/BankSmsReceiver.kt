package uz.edux.gateway

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Bank SMS'lari (kartaga o'tkazma): faqat ro'yxatdagi jo'natuvchilardan (UZCARD, HUMO, banklar) kelgan SMS navbatga
 * yoziladi va xizmat ularni serverga yuboradi (POST crm/sms/gateway/incoming). Shaxsiy SMS saqlanmaydi va yuborilmaydi.
 */
class BankSmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION || !Store.bankOn(context)) return
        val messages = try { Telephony.Sms.Intents.getMessagesFromIntent(intent) } catch (_: Exception) { null } ?: return
        if (messages.isEmpty()) return
        val sender = messages[0].originatingAddress ?: return
        if (!matches(sender, Store.senders(context))) return
        val body = messages.joinToString("") { it.messageBody ?: "" }
        val time = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ssXXX", Locale.US).format(Date(messages[0].timestampMillis))
        Store.enqueueBank(context, JSONObject().put("sender", sender.take(60)).put("body", body.take(2000)).put("received_at", time))
        GatewayService.poke(context)
    }

    companion object {
        private fun norm(value: String) = value.lowercase(Locale.ROOT).replace(Regex("[^a-z0-9а-яё]"), "")

        /** Jo'natuvchi ro'yxatdagilardan biri (katta-kichik harf, bo'shliq va belgilarsiz; «Uzcard.uz» ham «UZCARD» ga mos). */
        fun matches(sender: String, senders: List<String>): Boolean {
            val value = norm(sender)
            if (value.isEmpty()) return false
            return senders.any { val key = norm(it); key.isNotEmpty() && (value == key || value.startsWith(key)) }
        }
    }
}
