// Ko'rsatish uchun formatlash: pul, sana, vaqt, son.
import 'i18n.dart';

String groupDigits(num value) {
  final digits = value.abs().round().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// 1600000 -> "1 600 000 so'm"
String money(num? amount) {
  final value = amount ?? 0;
  final sign = value < 0 ? '−' : '';
  return '$sign${groupDigits(value)} ${tr("so'm")}';
}

String number(num? value, {int decimals = 1}) {
  if (value == null) return '—';
  if (value == value.roundToDouble()) return value.round().toString();
  return value.toStringAsFixed(decimals).replaceAll('.', I18n.locale == 'en' ? '.' : ',');
}

DateTime? parseDate(Object? value) {
  if (value == null) return null;
  final parsed = DateTime.tryParse(value.toString());
  return parsed?.toLocal();
}

String two(int value) => value.toString().padLeft(2, '0');

/// "2026-10-16T12:30:00Z" -> "16.10.2026"
String date(Object? value) {
  final parsed = parseDate(value);
  if (parsed == null) return value == null ? '—' : value.toString();
  return '${two(parsed.day)}.${two(parsed.month)}.${parsed.year}';
}

/// "16.10.2026 17:30"
String dateTime(Object? value) {
  final parsed = parseDate(value);
  if (parsed == null) return '—';
  return '${date(value)} ${two(parsed.hour)}:${two(parsed.minute)}';
}

String isoDay(DateTime day) => '${day.year}-${two(day.month)}-${two(day.day)}';

const List<String> _weekdays = <String>['Dushanba', 'Seshanba', 'Chorshanba', 'Payshanba', 'Juma', 'Shanba', 'Yakshanba'];
const List<String> _months = <String>[
  'Yanvar', 'Fevral', 'Mart', 'Aprel', 'May', 'Iyun', 'Iyul', 'Avgust', 'Sentabr', 'Oktabr', 'Noyabr', 'Dekabr',
];

/// 1 = dushanba
String weekdayName(int weekday) => tr(_weekdays[(weekday - 1).clamp(0, 6)]);

String monthName(int month) => tr(_months[(month - 1).clamp(0, 11)]);

/// "Payshanba, 16 Oktabr"
String dayTitle(DateTime day) => '${weekdayName(day.weekday)}, ${day.day} ${monthName(day.month)}';

String percent(num? value) => value == null ? '—' : '${number(value)}%';
