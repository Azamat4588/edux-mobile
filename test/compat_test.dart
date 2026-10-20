// 3.2: server 1.29 bilan moslik — push manzillari, obuna hisob qatorlari, rol va qo'shimcha imkoniyatlar.
import 'package:edux/core/push.dart';
import 'package:edux/core/session.dart';
import 'package:edux/features/billing/billing_page.dart';
import 'package:flutter_test/flutter_test.dart';

Session _session(String role, {List<String> modules = const <String>[], List<String>? features, Map<String, dynamic> extra = const <String, dynamic>{}}) {
  final session = Session();
  session.context = <String, dynamic>{
    'role': role,
    'modules': modules,
    if (features != null) 'features': features,
    ...extra,
  };
  return session;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('push: data.type yoki veb manzili', () {
    test('ma\'lum tur o\'zgarmaydi', () {
      final data = PushService.normalize(<String, dynamic>{'type': 'attempt', 'attempt_id': '5'});
      expect(data['type'], 'attempt');
      expect(data['attempt_id'], '5');
    });

    test('route (veb route nomi) — avval; id lar link dan', () {
      final guardian = PushService.normalize(<String, dynamic>{
        'type': 'attempt',
        'route': 'child.tests',
        'link': '/child/tests?student=7',
        'student_id': '7',
      });
      expect(guardian['type'], 'attempt');
      expect(guardian['student_id'], '7');
      expect(PushService.normalize(<String, dynamic>{'type': 'attendance', 'route': 'child.diary'})['type'], 'diary');
      expect(PushService.normalize(<String, dynamic>{'type': 'arrival', 'route': 'child', 'link': '/child?student=3'})['type'], 'child');
      expect(PushService.normalize(<String, dynamic>{'type': 'attempt', 'route': 'my.attempt', 'link': '/my/attempts/15'})['attempt_id'], '15');
      expect(PushService.normalize(<String, dynamic>{'route': 'crm.leads', 'link': '/crm/leads?lead=9'})['lead_id'], '9');
      expect(PushService.normalize(<String, dynamic>{'route': 'my.payments', 'link': '/home/payments'})['type'], 'payment');
    });

    test('route/url dan tur va id', () {
      expect(PushService.normalize(<String, dynamic>{'url': 'https://app.edux.uz/my/attempts/15'})['attempt_id'], '15');
      expect(PushService.normalize(<String, dynamic>{'link': '/child/payments?student=7'})['type'], 'payment');
      expect(PushService.normalize(<String, dynamic>{'link': '/child/payments?student=7'})['student_id'], '7');
      expect(PushService.normalize(<String, dynamic>{'route': '/child/tests'})['type'], 'attempt');
      expect(PushService.normalize(<String, dynamic>{'route': '/child/diary'})['type'], 'diary');
      expect(PushService.normalize(<String, dynamic>{'url': '/crm/leads?lead=9'})['lead_id'], '9');
      expect(PushService.normalize(<String, dynamic>{'url': '/crm/tasks'})['type'], 'task');
      expect(PushService.normalize(<String, dynamic>{'url': '/learn/assignments'})['type'], 'assignment');
    });

    test('notanish manzil — tur bo\'sh (bosh sahifa)', () {
      expect(PushService.normalize(<String, dynamic>{'url': '/settings/ai'})['type'], isNull);
      expect(PushService.normalize(<String, dynamic>{})['type'], isNull);
    });
  });

  group('obuna hisob qatorlari', () {
    test('tanish andozalar o\'zbekcha holicha (tarjimasiz)', () {
      expect(billingLine("O'quvchilar: 50 gacha"), "O'quvchilar: 50 gacha");
      expect(billingLine('CRM (12 kun)'), 'CRM (12 kun)');
      expect(billingLine("3 oylik to'lov chegirmasi (5%)"), "3 oylik to'lov chegirmasi (5%)");
      expect(billingTier("100 dan ko'p"), "100 dan ko'p");
    });

    test('qolgan kunlar manfiy bo\'lmaydi', () {
      expect(daysLeft('2000-01-01'), 0);
      expect(daysLeft(null), 0);
    });
  });

  group('rol, modul va qo\'shimchalar (server middleware bilan bir xil)', () {
    test('o\'qituvchi CRM bo\'lsa ham umumiy o\'quvchilar ro\'yxatini ko\'radi', () {
      final teacher = _session('teacher', modules: <String>['crm', 'testing']);
      expect(teacher.canSeeStudents, isTrue);
      expect(teacher.usesCrmStudents, isFalse);
      expect(teacher.canSeeOverview, isTrue);
    });

    test('kassir: CRM siz o\'quvchilar yo\'q, overview yo\'q', () {
      expect(_session('cashier').canSeeStudents, isFalse);
      final cashier = _session('cashier', modules: <String>['crm']);
      expect(cashier.canSeeStudents, isTrue);
      expect(cashier.usesCrmStudents, isTrue);
      expect(cashier.canSeeOverview, isFalse);
      expect(cashier.canSeeLeads, isFalse);
    });

    test('kirish nazorati va SMS shlyuz qo\'shimchaga bog\'liq', () {
      final director = _session('director', modules: <String>['crm'], features: <String>['callcenter']);
      expect(director.canCheckIn, isFalse);
      expect(director.canUseKiosk, isFalse);
      expect(director.canUseSmsGateway, isFalse);
      final full = _session('director', modules: <String>['crm'], features: <String>['access', 'sms']);
      expect(full.canCheckIn, isTrue);
      expect(full.canUseSmsGateway, isTrue);
    });

    test('coin: CRM sozlamasida o\'chirilsa yashiriladi', () {
      expect(_session('student', modules: <String>['crm'], extra: <String, dynamic>{'coins_enabled': false}).coinsEnabled, isFalse);
      expect(_session('student', modules: <String>['crm']).coinsEnabled, isTrue);
      expect(_session('student', modules: <String>['testing']).coinsEnabled, isFalse);
      expect(_session('student', modules: <String>['testing'], features: <String>[]).hasRewards, isFalse);
    });

    test('obuna sahifasi: bitta tashkilot rejimida yo\'q', () {
      expect(_session('director').canManageBilling, isTrue);
      expect(_session('director', extra: <String, dynamic>{'mode': 'single'}).canManageBilling, isFalse);
      expect(_session('teacher').canManageBilling, isFalse);
    });
  });
}
