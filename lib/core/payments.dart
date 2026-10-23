// Onlayn to'lov usullari (backend 1.35, docs/payments.md): Click, Payme, Uzum Bank, Paynet, Oson, Alif Pay va
// «Kartaga o'tkazma» (P2P). Toza mantiq — test/payments_test.dart.
import 'api.dart';
import 'format.dart';

/// To'lov usuli (GET pay/options → methods): tartib server bergan tartib (direktor sozlaydi).
class PayMethod {
  const PayMethod({required this.key, required this.name, this.fee = 0, this.min = 0});

  factory PayMethod.fromJson(Map<String, dynamic> json) => PayMethod(
        key: asText(json['key']),
        name: asText(json['name'], asText(json['key'])),
        fee: asDouble(json['fee']),
        min: asInt(json['min']),
      );

  final String key;
  final String name;

  /// Komissiya, % (faqat ko'rsatish uchun).
  final double fee;

  /// Direktor belgilagan minimal summa (0 — cheklanmagan).
  final int min;

  bool get isP2p => key == 'p2p';
}

const Map<String, String> _legacyNames = <String, String>{'click': 'Click', 'payme': 'Payme'};

/// Usullar ro'yxati: yangi server — `methods` (tartib bilan); eski server (1.35 gacha) — `providers` {click: true, payme: true}.
List<PayMethod> payMethods(Map<String, dynamic> options) {
  final raw = options['methods'];
  if (raw is List) {
    return raw.whereType<Map>().map((item) => PayMethod.fromJson(Map<String, dynamic>.from(item))).where((item) => item.key.isNotEmpty).toList();
  }
  final providers = asMap(options['providers']);
  return <PayMethod>[
    for (final key in <String>['click', 'payme'])
      if (providers[key] == true) PayMethod(key: key, name: _legacyNames[key]!),
  ];
}

/// Usul shu summaga ruxsat beradimi (minimal summa).
bool methodAllows(PayMethod method, int amount) => method.min <= 0 || amount >= method.min;

/// Faqat raqamlar.
String digitsOnly(String value) => value.replaceAll(RegExp(r'\D'), '');

/// Karta raqami 4 tadan guruhlab: "8600123412341234" → "8600 1234 1234 1234".
String cardGroups(String value) {
  final digits = digitsOnly(value);
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && i % 4 == 0) buffer.write(' ');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// Noyob summa ko'rinishi: 150037 → "150 037" (o'tkazmada aynan shu summa yoziladi).
String p2pAmountText(int amount) => groupDigits(amount);

/// Noyob summa bilan asosiy summa farqi (masalan, +37 yoki −12 so'm) — to'lovchiga tushuntirish uchun.
int p2pDelta(int unique, int base) => unique - base;

/// Muddat tugashiga qolgan vaqt (manfiy bo'lmaydi).
Duration p2pRemaining(DateTime? expiresAt, DateTime now) {
  if (expiresAt == null) return Duration.zero;
  final left = expiresAt.difference(now);
  return left.isNegative ? Duration.zero : left;
}

/// Taymer: "14:05" yoki "1:02:09".
String countdown(Duration value) {
  final total = value.inSeconds < 0 ? 0 : value.inSeconds;
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final seconds = total % 60;
  String two(int number) => number.toString().padLeft(2, '0');
  return hours > 0 ? '$hours:${two(minutes)}:${two(seconds)}' : '${two(minutes)}:${two(seconds)}';
}

/// P2P holati buyurtma javobidan: paid — tasdiqlandi, void — bekor, expired — muddati o'tdi, waiting — kutilmoqda.
String p2pState(Map<String, dynamic> order, DateTime now) {
  final status = asText(order['status']);
  if (status == 'paid') return 'paid';
  if (status == 'void') return 'void';
  final p2p = asMap(order['p2p']);
  if (p2p.isEmpty) return 'waiting';
  final expires = DateTime.tryParse(asText(p2p['expires_at']))?.toLocal();
  if (p2p['expired'] == true || (expires != null && !expires.isAfter(now))) return 'expired';
  return 'waiting';
}

/// To'lov tizimi tugmasi rangi (ARGB).
int providerColor(String key) {
  const colors = <String, int>{
    'click': 0xFF0B6CF2,
    'payme': 0xFF00BAC6,
    'uzum': 0xFF7000FF,
    'paynet': 0xFF00A651,
    'oson': 0xFFF7941D,
    'alif': 0xFF39B54A,
    'p2p': 0xFF334155,
  };
  return colors[key] ?? 0xFF1F63F5;
}
