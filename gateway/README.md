# EduX Shlyuz (Android)

SMS va qo'ng'iroqlar uchun alohida, yengil Android ilova (Kotlin, Flutter'siz). Asosiy EduX ilovasidagi «SMS shlyuz» va
«Telefon orqali» rejimlari Android fon cheklovlari tufayli uzilib qolardi — bu ilova faqat shu ishni qiladi.

- **Ulash:** vebda (SMS sahifasi, Sozlamalar → Call markaz, platforma SMS sozlamalari) «Ulash kodini yaratish» → ilovada
  QR (`eduxgw://pair?s=<server>&c=<kod>`) yoki kod. Server: `POST /api/v1/gateway/pair` → faqat shlyuz yo'llarida
  ishlaydigan token (server `SessionManager::GATEWAY`).
- **Ish:** `GatewayService` — bitta fon xizmati, ikki ip (SMS: `crm|platform/sms/gateway/*`; qo'ng'iroqlar:
  `crm/callcenter/phone/*`), doimiy wake lock va Wi-Fi qulfi, internet qaytganda darhol, START_STICKY.
- **Qo'riqchi:** WorkManager (15 daq.) + AlarmManager `setAndAllowWhileIdle` (10 daq.) + qayta yoqilish/yangilanish.
- **Uzilmasligi uchun** (ilova ekranida tekshiriladi): batareya cheklovi o'chiq, bildirishnomalar, ruxsatlar, fon interneti,
  Xiaomi/Huawei/Oppo/Vivo avtoishga tushirish.

Yig'ish: `.github/workflows/gateway.yml` (`gradle -p gateway assembleRelease`), main'da «gateway-latest» relizi —
`edux-shlyuz.apk`.
