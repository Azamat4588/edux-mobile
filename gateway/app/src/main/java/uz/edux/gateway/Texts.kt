package uz.edux.gateway

import android.content.Context
import java.util.Locale

/** Ilova matnlari: o'zbekcha (standart) va ruscha — telefon tiliga qarab. */
object Texts {
    private val UZ = mapOf(
        "notify_title" to "EduX Shlyuz ishlayapti",
        "notify_body" to "SMS: {0} · Qo'ng'iroqlar: {1}",
        "notify_off" to "o'chiq",
        "dial_title" to "EduX: qo'ng'iroq qiling",
        "dial_body" to "{0} raqamini terish uchun bosing",
        "channel_service" to "Shlyuz xizmati",
        "channel_dial" to "Qo'ng'iroq qilish",
        "title" to "EduX Shlyuz",
        "intro" to "SMS va qo'ng'iroqlar uchun alohida ilova. Telefon qulflangan yoki ilova yopilgan bo'lsa ham to'xtamasdan ishlaydi.",
        "pair_title" to "Telefonni ulash",
        "pair_steps" to "Vebda: SMS sahifasi yoki Sozlamalar → Call markaz → «Ulash kodini yaratish». Keyin QR kodni skanerlang yoki kodni yozing.",
        "scan" to "QR kodni skanerlash",
        "server" to "Server manzili (masalan, https://edux.uz)",
        "code" to "Ulash kodi (8 belgi)",
        "pair" to "Ulash",
        "pairing" to "Ulanmoqda...",
        "pair_failed" to "Ulanmadi: {0}",
        "no_internet" to "Serverga ulanib bo'lmadi. Internet va manzilni tekshiring.",
        "paired_as" to "{0} · {1}",
        "sms" to "SMS yuborish",
        "calls" to "Qo'ng'iroqlar (call markaz)",
        "sms_status" to "Yuborildi: {0} · xato: {1}",
        "calls_status" to "Yozildi: {0} · navbatda: {1} · terildi: {2}",
        "last_poll" to "Server bilan oxirgi aloqa: {0}",
        "never" to "hali yo'q",
        "stopped" to "To'xtatildi: {0}",
        "check_title" to "Uzilmasligi uchun",
        "check_battery" to "Batareya cheklovi o'chirilgan",
        "check_notifications" to "Bildirishnomalarga ruxsat",
        "check_sms" to "SMS yuborishga ruxsat",
        "check_calls" to "Qo'ng'iroq ruxsatlari (jurnal, holat, terish)",
        "check_data" to "Fon internetiga ruxsat (trafik tejash o'chiq)",
        "check_autostart" to "Avtoishga tushirish (Xiaomi, Huawei, Oppo, Vivo...) — qo'lda yoqing",
        "fix" to "Tuzatish",
        "open" to "Ochish",
        "ok" to "✓",
        "bad" to "✗",
        "unpair" to "Telefonni uzish",
        "unpair_confirm" to "Telefon uzilsinmi? Qayta ulash uchun vebda yangi kod kerak bo'ladi.",
        "yes" to "Ha",
        "no" to "Yo'q",
        "tip" to "Maslahat: telefonni quvvatga ulab qo'ying, Wi-Fi yoki mobil internet doim yoniq tursin. Ilovani «so'nggi ilovalar» ro'yxatidan surib yopmang.",
        "version" to "Versiya {0}",
        "not_allowed" to "Bu telefonga ruxsat berilmagan",
        "stopped_title" to "EduX Shlyuz to'xtab qoldi",
        "stopped_body" to "Qayta ishga tushirish uchun bosing va batareya cheklovini o'chiring.",
    )

    private val RU = mapOf(
        "notify_title" to "EduX Шлюз работает",
        "notify_body" to "SMS: {0} · Звонки: {1}",
        "notify_off" to "выкл",
        "dial_title" to "EduX: позвоните",
        "dial_body" to "Нажмите, чтобы набрать {0}",
        "channel_service" to "Служба шлюза",
        "channel_dial" to "Звонок",
        "title" to "EduX Шлюз",
        "intro" to "Отдельное приложение для SMS и звонков. Работает без перерывов, даже если телефон заблокирован или приложение закрыто.",
        "pair_title" to "Подключение телефона",
        "pair_steps" to "В вебе: страница SMS или Настройки → Колл-центр → «Создать код подключения». Затем отсканируйте QR-код или введите код.",
        "scan" to "Сканировать QR-код",
        "server" to "Адрес сервера (например, https://edux.uz)",
        "code" to "Код подключения (8 символов)",
        "pair" to "Подключить",
        "pairing" to "Подключение...",
        "pair_failed" to "Не подключено: {0}",
        "no_internet" to "Не удалось связаться с сервером. Проверьте интернет и адрес.",
        "paired_as" to "{0} · {1}",
        "sms" to "Отправка SMS",
        "calls" to "Звонки (колл-центр)",
        "sms_status" to "Отправлено: {0} · ошибок: {1}",
        "calls_status" to "Записано: {0} · в очереди: {1} · набрано: {2}",
        "last_poll" to "Последняя связь с сервером: {0}",
        "never" to "ещё нет",
        "stopped" to "Остановлено: {0}",
        "check_title" to "Чтобы не отключалось",
        "check_battery" to "Ограничение батареи снято",
        "check_notifications" to "Разрешение на уведомления",
        "check_sms" to "Разрешение на отправку SMS",
        "check_calls" to "Разрешения на звонки (журнал, состояние, набор)",
        "check_data" to "Фоновый интернет разрешён (экономия трафика выкл.)",
        "check_autostart" to "Автозапуск (Xiaomi, Huawei, Oppo, Vivo...) — включите вручную",
        "fix" to "Исправить",
        "open" to "Открыть",
        "ok" to "✓",
        "bad" to "✗",
        "unpair" to "Отключить телефон",
        "unpair_confirm" to "Отключить телефон? Для повторного подключения понадобится новый код в вебе.",
        "yes" to "Да",
        "no" to "Нет",
        "tip" to "Совет: держите телефон на зарядке, Wi-Fi или мобильный интернет всегда включены. Не смахивайте приложение из списка недавних.",
        "version" to "Версия {0}",
        "not_allowed" to "Этому телефону не выдано разрешение",
        "stopped_title" to "EduX Шлюз остановился",
        "stopped_body" to "Нажмите, чтобы запустить снова, и снимите ограничение батареи.",
    )

    fun get(context: Context, key: String): String {
        val language = context.resources.configuration.locales[0]?.language ?: Locale.getDefault().language
        val map = if (language == "ru") RU else UZ
        return map[key] ?: UZ[key] ?: key
    }

    fun format(context: Context, key: String, vararg args: Any?): String {
        var text = get(context, key)
        args.forEachIndexed { index, value -> text = text.replace("{$index}", value?.toString() ?: "") }
        return text
    }
}
