// Qo'llab-quvvatlash (murojaat) — server 1.38 API (docs/support.md): kontekst (ilova, versiya, OS, ekran), rasm
// biriktirish, yopish va baho. Eski server (1.37 gacha) qo'shimcha maydonlarni e'tiborsiz qoldiradi, `attachments`
// cheklovi kelmaydi — rasm tugmasi ko'rinmaydi. Toza mantiq — test/support_test.dart.
import 'api.dart';

/// Murojaatga avtomatik qo'shiladigan ma'lumot: `context[app]`, `context[app_version]`, `context[os]` ... (bo'shlari tushiriladi).
Map<String, String> supportContext({
  required String app,
  required String version,
  String? os,
  String? page,
  String? device,
  String? screen,
}) {
  String cut(String? value, int max) {
    final text = (value ?? '').trim();
    return text.length > max ? text.substring(0, max) : text;
  }

  final result = <String, String>{
    'app': cut(app, 20),
    'app_version': cut(version, 30),
    'os': cut(os, 60),
    'page': cut(page, 300),
    'device': cut(device, 80),
    'screen': cut(screen, 20),
  };
  result.removeWhere((_, value) => value.isEmpty);
  return result;
}

/// Multipart uchun tekis maydonlar: {context: {app: android}} → {'context[app]': 'android'}; null va bo'sh tushiriladi.
Map<String, String> supportFields(Map<String, Object?> payload) {
  final result = <String, String>{};
  payload.forEach((key, value) {
    if (value == null) return;
    if (value is Map) {
      value.forEach((inner, innerValue) {
        final text = innerValue == null ? '' : '$innerValue';
        if (text.isNotEmpty) result['$key[$inner]'] = text;
      });
      return;
    }
    final text = '$value';
    if (text.isNotEmpty) result[key] = text;
  });
  return result;
}

/// Rasm biriktirish cheklovlari (`GET public/support` → attachments). Eski serverda — o'chiq.
class SupportAttachmentRules {
  const SupportAttachmentRules({this.enabled = false, this.maxFiles = 0, this.maxKb = 0, this.types = const <String>[]});

  factory SupportAttachmentRules.fromMeta(Map<String, dynamic> meta) {
    final raw = asMap(meta['attachments']);
    if (raw.isEmpty) return const SupportAttachmentRules();
    return SupportAttachmentRules(
      enabled: raw['enabled'] == true,
      maxFiles: asInt(raw['max_files'], 3),
      maxKb: asInt(raw['max_kb'], 5120),
      types: asRawList(raw['types']).map((item) => '$item'.toLowerCase()).where((item) => item.isNotEmpty).toList(),
    );
  }

  final bool enabled;
  final int maxFiles;
  final int maxKb;
  final List<String> types;

  bool get allowed => enabled && maxFiles > 0;

  /// Fayl turi ruxsat etilganmi (kengaytma bo'yicha; jpeg = jpg).
  bool acceptsName(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0) return false;
    var ext = name.substring(dot + 1).toLowerCase();
    if (ext == 'jpeg') ext = 'jpg';
    final list = types.isEmpty ? const <String>['jpg', 'png', 'webp'] : types;
    return list.contains(ext) || (ext == 'jpg' && list.contains('jpeg'));
  }

  bool acceptsSize(int bytes) => maxKb <= 0 || bytes <= maxKb * 1024;
}

/// Murojaat holati: yopish faqat ochiq/javob berilganda; baho — faqat yopilganda (server: rate yopilmaganda 422).
bool supportCanClose(String status) => status == 'open' || status == 'answered';

bool supportCanRate(Map<String, dynamic> ticket) => asText(ticket['status']) == 'closed' && ticket.containsKey('helpful');

/// Xabardagi biriktirilgan rasmlar (yangi server): [{name, mime, size, url}].
List<Map<String, dynamic>> supportAttachments(Map<String, dynamic> message) =>
    asRawList(message['attachments']).whereType<Map>().map((item) => Map<String, dynamic>.from(item)).where((item) => asText(item['url']).isNotEmpty).toList();

/// Aloqa kanallari (meta.contacts): faqat to'ldirilganlari.
Map<String, String> supportContacts(Map<String, dynamic> meta) {
  final contacts = asMap(meta['contacts']);
  final result = <String, String>{};
  for (final key in <String>['phone', 'telegram', 'email', 'hours']) {
    final value = asText(contacts[key]).trim();
    if (value.isNotEmpty) result[key] = key == 'telegram' ? value.replaceFirst(RegExp(r'^@'), '') : value;
  }
  return result;
}
