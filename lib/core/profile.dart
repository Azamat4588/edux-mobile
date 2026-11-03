// 3.16: «Profil» (server 1.50) — ism, parol va telefon raqami (kirish logini) javoblarini o'qish, so'rov tanalari.
// UI: lib/features/settings/profile_page.dart. Davomatdagi kamera (checkins/scan + group_id) javobi ham shu yerda.
import 'api.dart';

/// POST profile/phone javobi: verify=true — yangi raqamga SMS kod yuborildi (profile/phone/confirm kutiladi);
/// verify=false — raqam darhol almashdi, javobda to'liq auth payload (user, memberships ...) bor.
class PhoneChangeResult {
  const PhoneChangeResult({required this.verify, required this.phone, this.auth});

  factory PhoneChangeResult.fromJson(dynamic data) {
    final map = asMap(data);
    return PhoneChangeResult(
      verify: map['verify'] == true,
      phone: asText(map['phone']),
      auth: map['user'] is Map ? map : null,
    );
  }

  final bool verify;
  final String phone;

  /// Raqam almashganda — yangilangan foydalanuvchi (Session.applyProfile ga beriladi).
  final Map<String, dynamic>? auth;
}

/// PUT profile/password tanasi: joriy parol faqat hisobda parol bo'lsa yuboriladi.
Map<String, Object?> passwordChangeBody({
  required bool hasPassword,
  required String current,
  required String password,
  required String confirmation,
  required bool logoutOthers,
}) =>
    <String, Object?>{
      if (hasPassword) 'current_password': current,
      'password': password,
      'password_confirmation': confirmation,
      'logout_others': logoutOthers,
    };

/// Ikki sana bir kunmi (davomat varaqasi bugungi darsmi).
bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// checkins/scan javobidan davomatga belgilanadigan o'quvchi ID si (xodim kartasi yoki eski server — null).
int? scannedStudentId(dynamic data) {
  final id = asInt(asMap(data)['student_id']);
  return id > 0 ? id : null;
}
