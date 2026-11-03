// 3.16: «Profil» (ism, parol, telefon raqami — server 1.50) va davomatdagi «Kamera bilan» (checkins/scan + group_id).
// Javob shakllari — backend ProfileController / AuthController::payload / CheckinController::scan bo'yicha.
import 'dart:convert';

import 'package:edux/core/api.dart';
import 'package:edux/core/profile.dart';
import 'package:edux/core/session.dart';
import 'package:edux/features/settings/profile_page.dart';
import 'package:edux/features/staff/attendance_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> authPayload({String name = 'Demo', String phone = '+998901112233', bool hasPassword = true}) => <String, dynamic>{
      'user': <String, dynamic>{
        'id': 1,
        'name': name,
        'phone': phone,
        'is_platform_admin': false,
        'has_password': hasPassword,
        'telegram_linked': false,
        'appearance': <String, dynamic>{},
      },
      'memberships': <Map<String, dynamic>>[
        <String, dynamic>{'organization_id': 1, 'organization': "Ilm yo'li", 'role': 'teacher'},
      ],
      'mode': 'platform',
      'new_requests': 0,
      'new_support': 0,
      'documents_awaiting': 0,
    };

http.Response reply(Object body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: <String, String>{'content-type': 'application/json; charset=utf-8'});

Session sessionWith(
  Future<http.Response> Function(String method, String path, Map<String, dynamic> body) handler, {
  bool hasPassword = true,
  List<String> features = const <String>['access'],
}) {
  final session = Session(client: MockClient((request) async {
    final path = request.url.path.replaceFirst(RegExp(r'^/api/v1/'), '');
    final body = request.body.isEmpty ? <String, dynamic>{} : asMap(jsonDecode(request.body));
    return handler(request.method, path, body);
  }));
  session.debugSignIn(
    server: 'https://edux.test',
    token: 'demo',
    user: asMap(authPayload(hasPassword: hasPassword)['user']),
    memberships: <Membership>[Membership(1, "Ilm yo'li", 'teacher')],
    organizationId: 1,
    context: <String, dynamic>{
      'role': 'teacher',
      'modules': <String>['crm'],
      'features': features,
      'organization': <String, dynamic>{'name': "Ilm yo'li"},
    },
  );
  return session;
}

Future<void> pumpPage(WidgetTester tester, Session session, Widget page) async {
  tester.view.physicalSize = const Size(430, 1600) * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(AppScope(session: session, child: MaterialApp(home: page)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> tapText(WidgetTester tester, String text, {bool first = false}) async {
  final finder = first ? find.text(text).first : find.text(text).last;
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('javoblar va so\'rov tanalari', () {
    test('profile/phone: verify=true — kod kutiladi, foydalanuvchi yo\'q', () {
      final result = PhoneChangeResult.fromJson(<String, dynamic>{'verify': true, 'phone': '+998907654321'});
      expect(result.verify, isTrue);
      expect(result.phone, '+998907654321');
      expect(result.auth, isNull);
    });

    test('profile/phone: verify=false — raqam almashdi, auth payload bilan', () {
      final result = PhoneChangeResult.fromJson(<String, dynamic>{'verify': false, 'phone': '+998907654321', ...authPayload(phone: '+998907654321')});
      expect(result.verify, isFalse);
      expect(asMap(result.auth!['user'])['phone'], '+998907654321');
      expect(PhoneChangeResult.fromJson(null).verify, isFalse);
    });

    test('profile/password: joriy parol faqat hisobda parol bo\'lsa', () {
      final withCurrent = passwordChangeBody(hasPassword: true, current: 'eski', password: 'yangi123', confirmation: 'yangi123', logoutOthers: true);
      expect(withCurrent, <String, Object?>{'current_password': 'eski', 'password': 'yangi123', 'password_confirmation': 'yangi123', 'logout_others': true});
      final withoutCurrent = passwordChangeBody(hasPassword: false, current: '', password: 'yangi123', confirmation: 'yangi123', logoutOthers: false);
      expect(withoutCurrent.containsKey('current_password'), isFalse);
      expect(withoutCurrent['logout_others'], isFalse);
    });

    test('checkins/scan: student_id (xodim kartasida — null), bugungi kun', () {
      expect(scannedStudentId(<String, dynamic>{'status': 'ok', 'student_id': 42}), 42);
      expect(scannedStudentId(<String, dynamic>{'status': 'ok', 'student_id': null}), isNull);
      expect(scannedStudentId(<String, dynamic>{}), isNull);
      expect(sameDay(DateTime(2026, 11, 3, 23, 59), DateTime(2026, 11, 3, 0, 1)), isTrue);
      expect(sameDay(DateTime(2026, 11, 3), DateTime(2026, 11, 2)), isFalse);
    });
  });

  test('Session.applyProfile: foydalanuvchi va internetsiz nusxa yangilanadi', () async {
    final session = sessionWith((method, path, body) async => reply(<String, dynamic>{}, 404));
    expect(session.userPhone, '+998901112233');
    expect(session.hasPassword, isTrue);
    await session.applyProfile(authPayload(name: 'Yangi Ism', phone: '+998907654321'));
    expect(session.userName, 'Yangi Ism');
    expect(session.userPhone, '+998907654321');
    expect(session.memberships.single.role, 'teacher');
    final prefs = await SharedPreferences.getInstance();
    final offline = asMap(jsonDecode(prefs.getString('offline.me')!));
    expect(asMap(offline['user'])['phone'], '+998907654321');
    // Javobda foydalanuvchi bo'lmasa — hech narsa o'zgarmaydi.
    await session.applyProfile(<String, dynamic>{'message': 'ok'});
    expect(session.userName, 'Yangi Ism');
  });

  testWidgets('Profil: ism saqlanadi', (tester) async {
    final sent = <String>[];
    final session = sessionWith((method, path, body) async {
      sent.add('$method $path ${jsonEncode(body)}');
      if (method == 'PUT' && path == 'profile') return reply(authPayload(name: asText(body['name'])));
      return reply(<String, dynamic>{'message': 'topilmadi'}, 404);
    });
    await pumpPage(tester, session, const ProfilePage());
    expect(find.text('Telefon raqami — tizimga kirish logini'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Aziz Karimov');
    await tapText(tester, 'Saqlash', first: true);
    expect(sent.single, startsWith('PUT profile {"name":"Aziz Karimov"}'));
    expect(session.userName, 'Aziz Karimov');
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
  });

  testWidgets('Profil: telefon raqami SMS kod bilan almashadi', (tester) async {
    final sent = <String>[];
    final session = sessionWith((method, path, body) async {
      sent.add('$method $path');
      if (path == 'profile/phone') {
        expect(body['password'], 'parol123');
        return reply(<String, dynamic>{'verify': true, 'phone': '+998907654321'});
      }
      if (path == 'profile/phone/confirm') {
        if (body['code'] != '123456') return reply(<String, dynamic>{'message': "Kod noto'g'ri."}, 422);
        return reply(authPayload(phone: '+998907654321'));
      }
      return reply(<String, dynamic>{'message': 'topilmadi'}, 404);
    });
    await pumpPage(tester, session, const ProfilePage());
    await tester.enterText(find.widgetWithText(TextField, 'Yangi raqam'), '+998 90 765 43 21');
    await tester.enterText(find.widgetWithText(TextField, 'Joriy parol').first, 'parol123');
    await tapText(tester, 'Raqamni almashtirish');
    expect(find.widgetWithText(TextField, 'Tasdiqlash kodi'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Tasdiqlash kodi'), '000000');
    await tapText(tester, 'Tasdiqlash');
    expect(find.text("Kod noto'g'ri."), findsOneWidget);
    expect(session.userPhone, '+998901112233');

    await tester.enterText(find.widgetWithText(TextField, 'Tasdiqlash kodi'), '123456');
    await tapText(tester, 'Tasdiqlash');
    expect(session.userPhone, '+998907654321');
    expect(find.widgetWithText(TextField, 'Tasdiqlash kodi'), findsNothing);
    expect(sent, <String>['POST profile/phone', 'POST profile/phone/confirm', 'POST profile/phone/confirm']);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
  });

  testWidgets('Profil: SMS o\'chiq — raqam darhol almashadi', (tester) async {
    final session = sessionWith((method, path, body) async {
      if (path == 'profile/phone') {
        return reply(<String, dynamic>{'verify': false, 'phone': '+998907654321', ...authPayload(phone: '+998907654321')});
      }
      return reply(<String, dynamic>{'message': 'topilmadi'}, 404);
    });
    await pumpPage(tester, session, const ProfilePage());
    await tester.enterText(find.widgetWithText(TextField, 'Yangi raqam'), '+998907654321');
    await tester.enterText(find.widgetWithText(TextField, 'Joriy parol').first, 'parol123');
    await tapText(tester, 'Raqamni almashtirish');
    expect(session.userPhone, '+998907654321');
    expect(find.widgetWithText(TextField, 'Tasdiqlash kodi'), findsNothing);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
  });

  testWidgets('Profil: parolsiz hisob — parol o\'rnatish, joriy parol so\'ralmaydi', (tester) async {
    Map<String, dynamic>? sentBody;
    final session = sessionWith((method, path, body) async {
      if (method == 'PUT' && path == 'profile/password') {
        sentBody = body;
        return reply(<String, dynamic>{'message': 'Parol yangilandi.', 'closed': 0});
      }
      return reply(<String, dynamic>{'message': 'topilmadi'}, 404);
    }, hasPassword: false);
    await pumpPage(tester, session, const ProfilePage());
    expect(find.text("Parol o'rnatish"), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Joriy parol'), findsNothing);
    expect(find.widgetWithText(TextField, 'Yangi raqam'), findsNothing);
    await tester.enterText(find.widgetWithText(TextField, 'Yangi parol'), 'yangi1234');
    await tester.enterText(find.widgetWithText(TextField, 'Yangi parolni takrorlang'), 'yangi1234');
    await tapText(tester, 'Saqlash');
    expect(sentBody, <String, dynamic>{'password': 'yangi1234', 'password_confirmation': 'yangi1234', 'logout_others': true});
    expect(session.hasPassword, isTrue);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
  });

  testWidgets('Davomat: «Kirish nazorati»siz «Kamera bilan» — tushuntirish oynasi', (tester) async {
    final session = sessionWith((method, path, body) async {
      if (path == 'crm/attendance') {
        return reply(<String, dynamic>{
          'lesson': <String, dynamic>{'topic': null},
          'students': <Map<String, dynamic>>[
            <String, dynamic>{'id': 5, 'full_name': 'Ali Valiyev', 'status': null, 'enrollment': 'active'},
          ],
        });
      }
      return reply(<String, dynamic>{'message': 'topilmadi'}, 404);
    }, features: const <String>['ai']);
    await pumpPage(tester, session, const AttendanceSheetPage(groupId: 3, groupName: 'Ingliz tili A1'));
    expect(find.text('Ali Valiyev'), findsOneWidget);
    await tester.tap(find.byTooltip('Kamera bilan'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.textContaining('«Kirish nazorati» qo\'shimchasi bilan ishlaydi'), findsOneWidget);
    await tester.tap(find.text('Tushunarli'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
  });
}
