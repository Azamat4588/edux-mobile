// WebView ichidagi tizim havolalari (sms:, SMSTO:, tel:, mailto:, tg:) — WebView ochmaydi, telefonning o'z ilovasiga uzatiladi.
import 'package:url_launcher/url_launcher.dart';

/// Havola tizim ilovasiga tegishlimi (SMS, qo'ng'iroq, pochta, Telegram).
bool isSystemLink(String url) => RegExp(r'^(sms|smsto|mms|mmsto|tel|mailto|tg):', caseSensitive: false).hasMatch(url.trim());

/// `SMSTO:+998901234567:matn` (QR kod ko'rinishi) → `sms:+998901234567?body=matn`; boshqasi o'zgarmaydi.
Uri systemLinkUri(String url) {
  final match = RegExp(r'^smsto:([^:]*)(?::([\s\S]*))?$', caseSensitive: false).firstMatch(url.trim());
  if (match == null) return Uri.parse(url.trim());
  final body = match.group(2);
  return Uri.parse('sms:${match.group(1)}${body == null || body.isEmpty ? '' : '?body=${Uri.encodeComponent(body)}'}');
}

Future<bool> openSystemLink(String url) => launchUrl(systemLinkUri(url), mode: LaunchMode.externalApplication);

/// WebView faqat shu server manzilida yursin: sxema, xost va port aynan bir xil bo'lishi shart
/// (`startsWith` yetmaydi — `https://edux.uz.boshqa.sayt` ham mos kelib qolardi).
bool sameOrigin(String url, String base) {
  final a = Uri.tryParse(url.trim());
  final b = Uri.tryParse(base.trim());
  if (a == null || b == null || !a.hasScheme || a.host.isEmpty || b.host.isEmpty) return false;
  return a.scheme.toLowerCase() == b.scheme.toLowerCase() && a.host.toLowerCase() == b.host.toLowerCase() && a.port == b.port;
}
