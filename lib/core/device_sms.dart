// «O'z telefonimdan» SMS (backend 1.36, docs/crm.md): shlyuzsiz — tizim matnni tayyorlaydi, xodim telefonining standart
// SMS ilovasi `sms:` havolasi bilan ochiladi. Android: `sms:+998...?body=`, iOS: `sms:+998...&body=` (matn rawurlencode).
// Toza mantiq — test/device_sms_test.dart.
import 'api.dart';

/// Havola (server `links` bermasa — o'zimiz quramiz, server bilan bir xil).
String deviceSmsLink(String phone, String body, {bool ios = false}) {
  final digits = phone.replaceAll(RegExp(r'[^\d+]'), '');
  final number = digits.startsWith('+') ? digits : '+$digits';
  return 'sms:$number${ios ? '&' : '?'}body=${Uri.encodeComponent(body)}';
}

/// Xabar uchun havola: serverdagi `links.android|ios`, bo'lmasa — qurilgan.
String deviceSmsLinkOf(Map<String, dynamic> message, {bool ios = false}) {
  final link = asText(asMap(message['links'])[ios ? 'ios' : 'android']);
  return link.isNotEmpty ? link : deviceSmsLink(asText(message['phone']), asText(message['body']), ios: ios);
}
