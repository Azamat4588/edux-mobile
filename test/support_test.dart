// Qo'llab-quvvatlash (server 1.38 API, docs/support.md): kontekst, multipart maydonlari, rasm cheklovlari, holatlar,
// push (type=support) va to'lov tizimlari ro'yxati. Fixture'lar — API hujjatidagi javob shakli.
import 'dart:convert';
import 'dart:io';

import 'package:edux/core/api.dart';
import 'package:edux/core/payments.dart';
import 'package:edux/core/push.dart';
import 'package:edux/core/support.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> fixture(String name) => asMap(jsonDecode(File('test/fixtures/$name.json').readAsStringSync()));

void main() {
  test('kontekst: bo\'shlari tushadi, uzunlik cheklanadi', () {
    final context = supportContext(app: 'android', version: '3.5.0', os: 'Android 14', page: 'help', screen: '390x844', device: '');
    expect(context, <String, String>{'app': 'android', 'app_version': '3.5.0', 'os': 'Android 14', 'page': 'help', 'screen': '390x844'});
    expect(supportContext(app: 'ios', version: '3.5.0', os: 'x' * 100)['os']!.length, 60);
    // Ilova versiyasi (push va murojaat kontekstida) pubspec.yaml bilan bir xil.
    final pubspec = RegExp(r'^version:\s*([0-9.]+)', multiLine: true).firstMatch(File('pubspec.yaml').readAsStringSync())!.group(1);
    expect(PushService.appVersion, pubspec);
  });

  test('multipart maydonlari: context[...] tekislanadi', () {
    final fields = supportFields(<String, Object?>{
      'name': 'Ali',
      'organization_id': 5,
      'website': null,
      'subject': '',
      'context': <String, String>{'app': 'android', 'app_version': '3.5.0', 'os': ''},
    });
    expect(fields, <String, String>{'name': 'Ali', 'organization_id': '5', 'context[app]': 'android', 'context[app_version]': '3.5.0'});
  });

  test('meta: aloqa va rasm cheklovlari', () {
    final meta = fixture('support_meta');
    final rules = SupportAttachmentRules.fromMeta(meta);
    expect(rules.allowed, isTrue);
    expect(rules.maxFiles, 3);
    expect(rules.acceptsName('ekran.PNG'), isTrue);
    expect(rules.acceptsName('rasm.jpeg'), isTrue);
    expect(rules.acceptsName('rasm.heic'), isFalse);
    expect(rules.acceptsName('fayl'), isFalse);
    expect(rules.acceptsSize(5120 * 1024), isTrue);
    expect(rules.acceptsSize(5120 * 1024 + 1), isFalse);
    expect(supportContacts(meta), <String, String>{
      'phone': '+998 71 200 45 45',
      'telegram': 'edux_support',
      'email': 'support@edux.uz',
      'hours': 'Du–Sha, 9:00–18:00',
    });
    // Eski server (1.37): attachments yo'q — rasm tugmasi chiqmaydi.
    expect(SupportAttachmentRules.fromMeta(<String, dynamic>{'topics': <String, dynamic>{}}).allowed, isFalse);
    expect(supportContacts(<String, dynamic>{'contacts': <String, dynamic>{'phone': null, 'telegram': '@edux', 'email': ''}}), <String, String>{'telegram': 'edux'});
  });

  test('murojaat: rasmlar, yopish va baho', () {
    final ticket = fixture('support_ticket');
    final messages = asList(ticket['messages'], 'messages');
    expect(supportAttachments(messages.first).single['name'], 'ekran.png');
    expect(supportAttachments(messages.last), isEmpty);
    expect(supportAttachments(<String, dynamic>{'body': 'eski server'}), isEmpty);
    expect(supportCanRate(ticket), isTrue);
    expect(supportCanRate(<String, dynamic>{'status': 'closed'}), isFalse); // eski server: baho yo'q
    expect(supportCanClose('open'), isTrue);
    expect(supportCanClose('answered'), isTrue);
    expect(supportCanClose('closed'), isFalse);
    final mine = asList(fixture('support_mine'));
    expect(asText(mine.single['token']).length, 40);
  });

  test('push: murojaatga javob', () {
    final data = PushService.normalize(<String, dynamic>{'type': 'support', 'ticket_id': '12', 'route': 'info.support.ticket', 'token': 'T' * 40});
    expect(data['type'], 'support');
    expect(data['token'], 'T' * 40);
    final fromLink = PushService.normalize(<String, dynamic>{'link': '/support/t/${'A' * 40}'});
    expect(fromLink['type'], 'support');
    expect(fromLink['token'], 'A' * 40);
  });

  test("to'lov tizimlari: tayyorlari server tartibida, P2P alohida", () {
    final providers = <String, dynamic>{'uzum': true, 'click': false, 'payme': true, 'p2p': true, 'alif': true};
    expect(readyProviders(providers), <String>['uzum', 'payme', 'p2p', 'alif']);
    expect(readyProviders(providers, withP2p: false), <String>['uzum', 'payme', 'alif']);
    expect(readyProviders(providers, withP2p: false).map((key) => providerNames[key]).toList(), <String>['Uzum Bank', 'Payme', 'Alif Pay']);
  });
}
