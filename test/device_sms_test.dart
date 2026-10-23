import 'package:edux/core/device_sms.dart';
import 'package:edux/core/external_links.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sms: havolasi Android va iOS uchun', () {
    expect(deviceSmsLink('+998 90 123-45-67', "Salom, to'lov"), 'sms:+998901234567?body=Salom%2C%20to\'lov');
    expect(deviceSmsLink('998901234567', 'a b', ios: true), 'sms:+998901234567&body=a%20b');
    expect(deviceSmsLinkOf(<String, dynamic>{'links': <String, dynamic>{'android': 'sms:+1?body=x'}, 'phone': '1', 'body': 'y'}), 'sms:+1?body=x');
    expect(deviceSmsLinkOf(<String, dynamic>{'phone': '+998901112233', 'body': 'z'}, ios: true), 'sms:+998901112233&body=z');
  });

  test('WebView: tizim havolalari', () {
    expect(isSystemLink('sms:+998901234567?body=x'), isTrue);
    expect(isSystemLink('SMSTO:+998901234567:Salom'), isTrue);
    expect(isSystemLink('tel:+998901234567'), isTrue);
    expect(isSystemLink('https://edux.uz/labs/x'), isFalse);
    expect(systemLinkUri('SMSTO:+998901234567:Salom dunyo').toString(), 'sms:+998901234567?body=Salom%20dunyo');
    expect(systemLinkUri('smsto:+998901234567').toString(), 'sms:+998901234567');
    expect(systemLinkUri('sms:+1?body=a').toString(), 'sms:+1?body=a');
  });
}
