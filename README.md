# EduX — mobil ilova (Android va iPhone)

Flutter'da yozilgan to'liq native ilova (WebView emas). EduX serveri bilan o'sha API orqali ishlaydi, o'zbek, rus va ingliz tillarida.

## Yuklab olish

Har `main` push'dan keyin GitHub Actions ilovani yig'adi va **Releases → latest** ga qo'yadi:
ko'pchilik telefonlar uchun `app-arm64-v8a-release.apk`, eski telefonlar uchun `app-armeabi-v7a-release.apk`.

Actions sozlamalari (Settings → Secrets and variables → Actions):

| Nomi | Turi | Nima uchun |
|---|---|---|
| `EDUX_SERVER` | Variable | Ilova ulanadigan server, masalan `https://app.edux.uz` |
| `GOOGLE_SERVICES_JSON` | Secret | Firebase `google-services.json` matni — push-bildirishnomalar uchun |
| `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` | Secret | Play Market imzosi (bo'lmasa sinov kaliti) |

Play Market uchun `.aab`: Actions → Build → «Run workflow».

## 3.0 da yangi

**Kirish**
- Bir martalik kod bilan kirish: telefon raqamga kod Telegramga (hisob bog'langan bo'lsa) yoki SMS bilan keladi (`POST auth/code`, `auth/code/verify`).
- «Telegram orqali kirish»: bot ochiladi, «Start» bosilgach ilova o'zi kiradi (`POST auth/telegram-link`, `GET auth/telegram-link/{key}` — 2 soniyada bir so'rov, ilovaga qaytilganda darhol).
- Tugmalar server sozlamasiga qarab ko'rinadi (`GET auth/options`). Ota-ona hisobsiz ham **to'lov havolasi** (`/p/…`) bilan to'lay oladi.

**O'quvchi**
- **Olimpiadalarim**: havola (`…/o/…`) orqali qo'shilish, ro'yxatdan o'tish, badal to'lovi (Click/Payme), testni ilovadagi test oynasida ishlash, natija, o'rin va sertifikat, e'lonlar va reyting.
- **AI ustoz**: chat (formulalar LaTeX'da), suhbatlar tarixi, oylik limit. Test oynasi ochiq bo'lsa ustoz o'chadi (server ham tekshiradi).
- **O'yinlar**: viktorina-blits, «Juftini top», «So'z yig'ish» — rekord va reyting. **Yutuqlarim**: XP, daraja, ketma-ket kunlar, nishonlar, haftalik reyting.
- **Virtual laboratoriya**: tasodifiy qiymatli topshiriqlar, 3 ta urinish, XP.
- Onlayn to'lovdan keyin buyurtma holati kuzatiladi (`GET pay/orders/{id}`), balans o'zi yangilanadi.
- **Murojaatlar**: qo'llab-quvvatlashga yozish va yozishma (barcha rollar uchun).

**Ota-ona — «Farzandim»**
- Bir nechta farzand bo'lsa — tepada almashtirgich (tanlov eslab qolinadi).
- Tablar: **Umumiy** (balans va to'lash, davomat, so'nggi baholar va natijalar), **Kundalik** (maktab moduli), **Testlar**, **To'lov** (hisoblanmalar, to'lovlar, onlayn to'lov).
- Barcha so'rovlar `lib/features/guardian/guardian_repository.dart` da — endpointlar to'plami bitta joyda almashtiriladi.

**Tashkilot imkoniyatlari**
- `GET context` dagi `modules` va `features` (ai, olympiad, fun, …) bo'yicha menyu tuziladi: yoqilmagan bo'lim ko'rinmaydi.
- Server 403 qaytarsa, «Bu bo'lim hozircha mavjud emas» degan tushunarli oyna chiqadi.

## 2.0 da yangi

- Tungi, kunduzgi va «qurilmaga qarab» rejim; tashkilot tanlagan asosiy rang (veb bilan umumiy sozlama).
- Push-bildirishnomalar (Firebase): to'lov, davomat, test natijasi, baho, sertifikat, yangi lid, vazifa. Bosilganda kerakli sahifa ochiladi.
- Mock imtihonlar: bo'limlar o'z vaqti bilan, Listening audio (bir marta), Reading matni, ochiq javob va esse, IELTS band / daraja natijasi.
- O'quvchi: «Mock natijalarim» (o'sish), «Sertifikatlarim» (QR sahifa).
- Xodim (CRM): lidlar (holat, qo'ng'iroq, izoh, yangi lid) va vazifalar (bugun, muddati o'tgan, bajarildi).

## Imkoniyatlar

**O'qituvchi / administrator**
- Bosh sahifa: bugungi darslar, qisqa statistika, tezkor amallar.
- **Skaner** — javob varaqalarini kamera bilan tekshirish (pastda batafsil).
- Testlar: ro'yxat, natijalar reytingi, skanerni shu test uchun ochish.
- O'quvchilar: qidiruv, karta (balans, guruhlar, to'lovlar), to'lov qabul qilish.
- Davomat: guruh bo'yicha belgilash.
- Skanlar: telefon navbati, tekshiruv kutayotganlar (javoblarni qo'lda tuzatish, tasdiqlash yoki rad etish), serverdagi tarix.

**O'quvchi**
- Balans va onlayn to'lov, yaqin darslar, test natijalari, baholar, coinlar.
- Onlayn testlar (taymer, javoblar serverga darhol saqlanadi, natija va tahlil). Formulalar LaTeX'da ko'rsatiladi.
- Kurslar, darslar, materiallarni ochish; uy vazifasini matn yoki daftar surati bilan yuborish.
- Kundalik: haftalik jadval, mavzu, uy vazifasi, baho, davomat.

- Olimpiadalar, AI ustoz, o'yinlar, yutuqlar, virtual laboratoriya (tashkilotda yoqilgan bo'lsa), murojaatlar.

**Ota-ona**
- «Farzandim»: farzand almashtirgich; Umumiy, Kundalik, Testlar, To'lov tablari; onlayn to'lov.

## Skaner qanday ishlaydi

Varaqani o'qish telefonning o'zida, C++ dagi `packages/edux_omr` yadrosida bajariladi (Dart FFI, alohida isolate). Yadro serverdagi `omr-service` bilan aynan bir xil varaqa tuzilishi va chegaralardan foydalanadi.

1. Kamera oqimi ~9 kadr/s tahlil qilinadi: 4 ta ArUco burchak belgisi topiladi, varaqa ramkada ko'rsatiladi. Masofa, aniqlik, yorug'lik va qimirlash tekshiriladi, foydalanuvchiga maslahat chiqadi ("yaqinroq", "telefonni qimirlatmang" ...).
2. Varaqa 3 kadr davomida barqaror bo'lsa — avtomatik suratga olinadi (tugma bilan ham bo'ladi).
3. Perspektiva tekislanadi, yorug'lik notekisligi olib tashlanadi, QR (test, variant, o'quvchi kodi) va kataklar o'qiladi. ~0,2 s.
4. Test kaliti (`GET /scans/kit/{exam}`) telefonda saqlangan bo'lsa — ball va o'quvchi ismi **darhol, internetsiz** ko'rsatiladi; shubhali kataklar sariq rangda belgilanadi.
5. Rasm va telefon natijasi navbatga qo'yiladi va fonda serverga yuboriladi. Server o'zi ham qayta o'qiydi:
   - natijalar bir xil → avtomatik baholanadi;
   - farq bo'lsa → `device_mismatch` belgisi bilan "Tekshiruv"ga tushadi;
   - server o'qiy olmasa yoki ishlamasa → telefon natijasi saqlanadi va tekshiruvga yuboriladi.
6. Internet bo'lmasa navbat telefonda saqlanadi va aloqa tiklanganda o'zi yuboriladi.

Uzluksiz rejimda varaqani almashtirish kifoya — bir varaqa ikki marta olinmaydi. Galereyadan bir nechta rasmni birdaniga tekshirish ham mumkin.

**Sinov natijalari** (`packages/edux_omr/tool/test.sh`): 96 ta sun'iy varaqa (burilish, perspektiva, xiralik, soya, shovqin, JPEG) — telefon yadrosi natijalari server o'quvchisi bilan 96/96 bir xil, javoblar 100% to'g'ri; QR server o'qiy olmaydigan xiralikda ham o'qiladi.

## Yig'ish

Talablar: Flutter 3.24 yoki yangiroq, Android Studio (Android SDK + NDK), iPhone uchun macOS + Xcode 15+ va CocoaPods.

```bash
bash setup.sh          # android/ va ios/ papkalarini yaratadi, ruxsatlar va ikonkani sozlaydi
flutter run --dart-define=EDUX_SERVER=https://app.sizning-domen.uz
```

Windows'da `setup.sh` o'rniga:

```
flutter create --org uz.edux --project-name edux --platforms=android,ios .
del test\widget_test.dart
flutter pub get
dart run tool/configure_platforms.dart
dart run flutter_launcher_icons
```

`EDUX_SERVER` — ilova sukut bo'yicha ulanadigan server. Kirish oynasida foydalanuvchi uni o'zgartirishi ham mumkin (taklif havolasi bilan kirganda server havoladan olinadi).

### Android

```bash
flutter build apk --release --split-per-abi --dart-define=EDUX_SERVER=https://app.sizning-domen.uz
flutter build appbundle --release --dart-define=EDUX_SERVER=https://app.sizning-domen.uz   # Google Play uchun
```

Play Market uchun imzo: `keytool -genkey -v -keystore edux.jks -keyalg RSA -keysize 2048 -validity 10000 -alias edux`, so'ng `android/key.properties` va `android/app/build.gradle` dagi `signingConfigs` ni Flutter qo'llanmasi bo'yicha sozlang (https://docs.flutter.dev/deployment/android). Kalit faylini repozitoriyga qo'shmang.

### iPhone

```bash
cd ios && pod install && cd ..
open ios/Runner.xcworkspace     # Signing & Capabilities → Team, Bundle ID uz.edux.edux
flutter build ipa --release --dart-define=EDUX_SERVER=https://app.sizning-domen.uz
```

Tayyor `.ipa` ni Transporter yoki Xcode Organizer orqali App Store Connect / TestFlight'ga yuklang. Kamera va galereya ruxsat matnlari `configure_platforms.dart` tomonidan qo'shilgan.

### GitHub Actions

`.github/workflows/build.yml` har push'da testlarni ishga tushiradi, Android APK yig'adi (Artifacts bo'limida) va iOS'ni imzosiz tekshirib ko'radi. Server manzilini repozitoriy o'zgaruvchisi `EDUX_SERVER` orqali bering.

## Testlar

```bash
flutter test                              # Dart: baholash, formatlash
cd packages/edux_omr && bash tool/test.sh /yo'l/edux/omr-service 96   # C++ yadro ↔ server o'quvchisi
```

`test.sh` uchun g++ va Python 3 (`omr-service/requirements-dev.txt` dagi paketlar) kerak; birinchi argument — EduX server arxividagi `omr-service` papkasi.

## Server talablari

EduX server **1.8.0** yoki yangiroq: `device_result` maydoni va `GET /api/v1/scans/kit/{exam}` shu versiyada qo'shilgan. Eski serverda ilova ishlaydi, lekin telefon natijasi solishtirilmaydi va internetsiz baholash bo'lmaydi.

3.0 imkoniyatlari uchun server **1.28** tavsiya etiladi (`context.features`). `features` qaytarmaydigan eski serverda qo'shimcha bo'limlar cheklanmagan deb hisoblanadi va mavjud bo'lmagan bo'lim ochilsa, 403/404 xabari ko'rsatiladi.

## Tuzilma

```
lib/
  core/              API, sessiya, tarjima, format, mavzu, umumiy vidjetlar
  features/
    auth/            kirish (parol, bir martalik kod, Telegram), tashkilot tanlash
    shell/           rolga, modul va imkoniyatlarga qarab pastki menyu
    scanner/         skaner, navbat, test kaliti, natija, tekshiruv
    staff/           bosh sahifa, o'quvchilar, to'lov, davomat, testlar
    student/         bosh sahifa, onlayn testlar, kurslar, uy vazifasi, kundalik, to'lov, to'lov havolasi
    guardian/        «Farzandim» va GuardianRepository (ota-onaning barcha so'rovlari)
    olympiad/        olimpiadalarim, olimpiada sahifasi
    tutor/           AI ustoz
    fun/             o'yinlar, yutuqlar, virtual laboratoriya
    support/         murojaatlar
    settings/        til, skaner sozlamalari, chiqish
packages/edux_omr/   C++ OMR yadrosi (quirc — ISC, stb — public domain) va Dart FFI
assets/i18n/         ru.json, en.json (kalit — o'zbekcha matn)
tool/                platforma sozlash, tarjima tekshiruvi
```

## Cheklovlar

- Olimpiadalar ro'yxati: serverda o'quvchi uchun «mening olimpiadalarim» endpointi yo'q — ochilgan/ro'yxatdan o'tilgan olimpiada havolalari telefonda saqlanadi. `/o/…`, `/p/…` havolalarini ilovaga to'g'ridan-to'g'ri ochish (App Links / Universal Links) hali sozlanmagan: havola nusxalanib ilovaga qo'yiladi.
- Virtual laboratoriyada vebdagi interaktiv tajriba (mayatnik, linza animatsiyasi) yo'q — topshiriq matni, qiymatlar va javob.
- Tashqi (boshqa markazdagi) ishtirokchi olimpiada testini brauzerdagi shaxsiy havola orqali ishlaydi.

- Push-bildirishnomalar yo'q (Telegram bot orqali bildirishnomalar ishlaydi). Firebase qo'shish uchun alohida loyiha sozlamalari kerak.
- Faqat HTTPS serverlar: Android/iOS sukut bo'yicha shifrlanmagan HTTP'ni bloklaydi. Mahalliy sinov uchun `http://` kerak bo'lsa, AndroidManifest'ga `android:usesCleartextTraffic="true"` qo'shing.
- Ilova yozilgan muhitda Flutter SDK yo'q edi: C++ yadro to'liq sinovdan o'tgan, Dart kodi sintaksis bo'yicha tekshirilgan, lekin birinchi `flutter analyze` / `flutter run` ni ishlab chiquvchi kompyuterida bajarish kerak.
