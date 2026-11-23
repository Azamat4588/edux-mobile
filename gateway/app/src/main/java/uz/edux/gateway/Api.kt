package uz.edux.gateway

import org.json.JSONObject
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL

/** EduX serveriga so'rov (fon ipida chaqiriladi). */
object Api {
    class Response(val code: Int, val body: String) {
        val ok: Boolean get() = code in 200..299

        /** Token bekor qilingan, ruxsat yo'q yoki telefon vebda o'chirilgan. */
        val revoked: Boolean get() = code == 401 || code == 403

        fun json(): JSONObject = try { JSONObject(body) } catch (_: Exception) { JSONObject() }

        fun message(): String = json().optString("message").ifEmpty { "HTTP $code" }
    }

    fun call(
        server: String,
        method: String,
        path: String,
        body: JSONObject? = null,
        token: String? = null,
        organization: Int = 0,
        deviceId: String? = null,
    ): Response {
        val connection = URL(server.trimEnd('/') + "/api/v1/" + path).openConnection() as HttpURLConnection
        try {
            connection.requestMethod = method
            connection.connectTimeout = 15000
            connection.readTimeout = 25000
            connection.useCaches = false
            connection.setRequestProperty("Accept", "application/json")
            connection.setRequestProperty("X-Requested-With", "EduXGateway")
            connection.setRequestProperty("X-Platform", "android")
            connection.setRequestProperty("X-App-Version", BuildConfig.VERSION_NAME)
            if (deviceId != null) connection.setRequestProperty("X-Device-Id", deviceId)
            if (token != null) connection.setRequestProperty("Authorization", "Bearer $token")
            if (organization > 0) connection.setRequestProperty("X-Organization", organization.toString())
            if (body != null) {
                connection.doOutput = true
                connection.setRequestProperty("Content-Type", "application/json; charset=utf-8")
                OutputStreamWriter(connection.outputStream, Charsets.UTF_8).use { it.write(body.toString()) }
            }
            val code = connection.responseCode
            val stream = if (code >= 400) connection.errorStream else connection.inputStream
            return Response(code, stream?.bufferedReader(Charsets.UTF_8)?.use { it.readText() } ?: "")
        } finally {
            connection.disconnect()
        }
    }

    fun call(pairing: Store.Pairing, deviceId: String, method: String, path: String, body: JSONObject? = null): Response =
        call(pairing.server, method, path, body, pairing.token, if (pairing.scope == "platform") 0 else pairing.organizationId, deviceId)
}
