// 3.34: do'kon (Google Play / App Store) uchun yig'ilgan nusxa: `--dart-define=EDUX_STORE=true`.
//
// Google Play SEND_SMS / RECEIVE_SMS ruxsatini faqat standart SMS ilovasi va bir nechta istisnoga beradi — telefondan
// ommaviy SMS (SMS shlyuz) va bank SMS'ini o'qish shu istisnolarga kirmaydi. Shuning uchun do'kon nusxasida bu ikki
// imkoniyat yo'q (AndroidManifest'dan ruxsatlar ham olib tashlanadi: `dart run tool/configure_platforms.dart --store`).
// To'liq imkoniyatli APK saytdan («Ilovalar» sahifasi) yuklanadi.
const bool kStoreBuild = bool.fromEnvironment('EDUX_STORE');
