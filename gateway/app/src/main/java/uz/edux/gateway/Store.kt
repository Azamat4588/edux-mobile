package uz.edux.gateway

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.security.SecureRandom

/**
 * Ilova holati (SharedPreferences): ulanish (server, token, tashkilot), yoqilgan vazifalar, har vazifa holati va
 * yuborilmagan qo'ng'iroq hodisalari navbati. Hamma yozuvlar commit() bilan — jarayon o'ldirilsa ham yo'qolmaydi.
 */
object Store {
    private const val PREFS = "edux_gateway"

    private fun prefs(context: Context) = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    // --- Ulanish ---

    fun deviceId(context: Context): String {
        val p = prefs(context)
        p.getString("device_id", null)?.let { return it }
        val bytes = ByteArray(12).also { SecureRandom().nextBytes(it) }
        val id = "gw-" + bytes.joinToString("") { "%02x".format(it) }
        p.edit().putString("device_id", id).commit()
        return id
    }

    data class Pairing(
        val server: String,
        val token: String,
        val scope: String,
        val organizationId: Int,
        val organizationName: String,
        val userName: String,
        val sms: Boolean,
        val calls: Boolean,
    ) {
        /** SMS navbati yo'li: tashkilot yoki platforma. */
        val smsPrefix: String get() = if (scope == "platform") "platform/sms/gateway" else "crm/sms/gateway"
    }

    fun pairing(context: Context): Pairing? {
        val raw = prefs(context).getString("pairing", null) ?: return null
        return try {
            val o = JSONObject(raw)
            Pairing(
                o.getString("server"), o.getString("token"), o.optString("scope", "organization"), o.optInt("organization_id"),
                o.optString("organization_name"), o.optString("user_name"), o.optBoolean("sms"), o.optBoolean("calls"),
            )
        } catch (_: Exception) {
            null
        }
    }

    fun savePairing(context: Context, server: String, answer: JSONObject) {
        val capabilities = answer.optJSONObject("capabilities") ?: JSONObject()
        val organization = answer.optJSONObject("organization")
        val o = JSONObject()
            .put("server", server)
            .put("token", answer.getString("token"))
            .put("scope", answer.optString("scope", "organization"))
            .put("organization_id", organization?.optInt("id") ?: 0)
            .put("organization_name", organization?.optString("name") ?: "EduX")
            .put("user_name", answer.optJSONObject("user")?.optString("name") ?: "")
            .put("sms", capabilities.optBoolean("sms"))
            .put("calls", capabilities.optBoolean("calls"))
        prefs(context).edit()
            .putString("pairing", o.toString())
            .putBoolean("sms_on", capabilities.optBoolean("sms"))
            .putBoolean("calls_on", capabilities.optBoolean("calls"))
            .remove("status_sms").remove("status_calls").remove("pending")
            .commit()
    }

    fun clear(context: Context) {
        prefs(context).edit().remove("pairing").remove("status_sms").remove("status_calls").remove("pending")
            .putBoolean("sms_on", false).putBoolean("calls_on", false).commit()
    }

    // --- Vazifalar ---

    fun smsOn(context: Context): Boolean = pairing(context)?.sms == true && prefs(context).getBoolean("sms_on", false)

    fun callsOn(context: Context): Boolean = pairing(context)?.calls == true && prefs(context).getBoolean("calls_on", false)

    fun setSms(context: Context, on: Boolean) = prefs(context).edit().putBoolean("sms_on", on).commit()

    fun setCalls(context: Context, on: Boolean) = prefs(context).edit().putBoolean("calls_on", on).commit()

    /** Xizmat ishlashi kerakmi (qo'riqchi shunga qaraydi). */
    fun active(context: Context): Boolean = smsOn(context) || callsOn(context)

    // --- Holat (ekranda ko'rinadi) ---

    @Synchronized
    fun status(context: Context, key: String): JSONObject = try {
        JSONObject(prefs(context).getString("status_$key", "{}") ?: "{}")
    } catch (_: Exception) {
        JSONObject()
    }

    @Synchronized
    fun updateStatus(context: Context, key: String, change: (JSONObject) -> Unit) {
        val status = status(context, key)
        change(status)
        prefs(context).edit().putString("status_$key", status.toString()).commit()
    }

    fun heartbeat(context: Context) = prefs(context).edit().putLong("heartbeat", System.currentTimeMillis()).apply()

    fun lastHeartbeat(context: Context): Long = prefs(context).getLong("heartbeat", 0)

    // --- Qo'ng'iroq hodisalari navbati ---

    private const val MAX_PENDING = 500

    @Synchronized
    fun pending(context: Context): JSONArray = try {
        JSONArray(prefs(context).getString("pending", "[]") ?: "[]")
    } catch (_: Exception) {
        JSONArray()
    }

    @Synchronized
    fun enqueue(context: Context, event: JSONObject) {
        val events = pending(context)
        events.put(event)
        while (events.length() > MAX_PENDING) events.remove(0)
        prefs(context).edit().putString("pending", events.toString()).commit()
    }

    /** Birinchi [count] ta hodisa yuborildi — navbatdan olinadi. */
    @Synchronized
    fun drop(context: Context, count: Int) {
        val events = pending(context)
        val left = JSONArray()
        for (i in count until events.length()) left.put(events.get(i))
        prefs(context).edit().putString("pending", left.toString()).commit()
    }
}
