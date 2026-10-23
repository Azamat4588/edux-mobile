// 3.4.1: server javoblari (test/fixtures — demo serverdan har rol bilan olingan haqiqiy JSON, tokenlar yashirilgan)
// mobil parse mantiqiga beriladi. Server javob shakli o'zgarsa — CI shu yerda qizil bo'ladi.
// Fixture'larni yangilash: hisobotdagi build_fixtures.py (demo server, nusxa baza).
import 'dart:convert';
import 'dart:io';

import 'package:edux/core/api.dart';
import 'package:edux/core/design.dart';
import 'package:edux/core/external_links.dart';
import 'package:edux/core/home_today.dart';
import 'package:edux/core/lms.dart';
import 'package:edux/core/nav.dart';
import 'package:edux/core/payments.dart';
import 'package:edux/core/session.dart';
import 'package:edux/features/guardian/guardian_repository.dart';
import 'package:edux/features/scanner/exam_kit.dart';
import 'package:edux/features/staff/exams_page.dart';
import 'package:flutter_test/flutter_test.dart';

dynamic fixture(String name) => jsonDecode(File('test/fixtures/$name.json').readAsStringSync());

Map<String, dynamic> fixtureMap(String name) => asMap(fixture(name));

Session sessionFor(String org, String role) => Session()..context = fixtureMap('${org}_${role}_context');

List<String> navKeys(Session session) => buildNav(NavContext(role: session.role, can: session.can)).map((section) => section.key).toList();

List<String> tabKeys(Session session) =>
    buildNav(NavContext(role: session.role, can: session.can)).expand((section) => section.tabs).map((tab) => tab.key).toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('kirish va kontekst', () {
    test('auth/login: token, foydalanuvchi va a\'zoliklar', () {
      final login = fixtureMap('center_director_auth_login');
      expect(login['token'], isA<String>());
      expect(asMap(login['user'])['name'], isNotEmpty);
      final membership = asList(login['memberships']).first;
      expect(asInt(membership['organization_id']), greaterThan(0));
      expect(membership['role'], 'director');
    });

    test('context: rol, modullar, qo\'shimchalar, obuna', () {
      for (final name in <String>['center_director', 'center_cashier', 'center_student', 'school_teacher', 'school_guardian']) {
        final context = fixtureMap('${name}_context');
        expect(context['role'], isA<String>(), reason: name);
        expect(context['modules'], isA<List>(), reason: name);
        expect(context['features'], isA<List>(), reason: name);
        expect(asMap(context['organization'])['name'], isNotEmpty, reason: name);
        expect(context['subscription'], isA<Map>(), reason: name);
      }
    });

    test('site: ko\'rinish standarti (ThemeChoice)', () {
      final site = fixtureMap('center_director_site');
      final theme = asMap(site['theme']);
      final choice = ThemeChoice.resolve(<Map<String, dynamic>>[asMap(theme['defaults'])]);
      expect(themeOptions['template'], contains(choice.template));
      expect(themeOptions['accent'], contains(choice.accent));
      expect(theme['allow_user'], isA<bool>());
    });
  });

  group('menyu — haqiqiy kontekst bilan', () {
    test('o\'quv markazi direktori: o\'quvchilar, moliya, aloqa', () {
      final keys = tabKeys(sessionFor('center', 'director'));
      expect(keys, containsAll(<String>['home', 'students', 'crm.leads', 'attendance', 'crm.payments', 'crm.debtors', 'exams']));
    });

    test('kassir: to\'lovlar va qarzdorlar; maktabda (CRMsiz) — kartaga o\'tkazmalar', () {
      expect(tabKeys(sessionFor('center', 'cashier')), containsAll(<String>['crm.payments', 'crm.debtors']));
      final school = sessionFor('school', 'cashier');
      expect(school.hasModule('crm'), isFalse);
      expect(tabKeys(school), contains('pay.p2p'), reason: 'CRMsiz kassir menyusi bo\'sh qolmasin');
    });

    test('maktab o\'qituvchisi va ota-ona: kundalik', () {
      expect(navKeys(sessionFor('school', 'teacher')), contains('groups'));
      expect(tabKeys(sessionFor('school', 'guardian')), contains('child.diary'));
      expect(tabKeys(sessionFor('school', 'student')), contains('school.diary'));
    });
  });

  group('bosh sahifa «Bugun» kartalari', () {
    test('direktor: overview + crm/dashboard + crm/timetable', () {
      final timetable = fixtureMap('center_director_crm_timetable');
      final cards = managerToday(
        fixtureMap('center_director_overview'),
        dashboard: fixtureMap('center_director_crm_dashboard'),
        lessons: asList(timetable['items']),
      );
      expect(cards, isNotEmpty);
      final debtors = cards.firstWhere((card) => card.key == 'debtors');
      expect(debtors.value, '${asInt(asMap(fixtureMap('center_director_crm_dashboard')['counters'])['debtors'])}');
    });

    test('o\'qituvchi (markaz va maktab)', () {
      expect(teacherToday(fixtureMap('center_teacher_overview')), isNotEmpty);
      final school = teacherToday(fixtureMap('school_teacher_overview'));
      expect(school.map((card) => card.key), contains('lessons'));
    });

    test('kassir: crm/payments summary va crm/debtors count', () {
      final payments = fixtureMap('center_cashier_crm_payments');
      final debtors = fixtureMap('center_cashier_crm_debtors');
      expect(payments['summary'], isA<Map>());
      expect(debtors.containsKey('count') && debtors.containsKey('total_debt'), isTrue);
      final cards = cashierToday(payments, debtors);
      expect(cards.last.value, '${asInt(debtors['count'])}');
    });

    test('marketolog: crm/leads counts', () {
      final leads = fixtureMap('center_marketer_crm_leads');
      expect(leads['counts'], isA<Map>());
      final cards = marketerToday(asMap(leads['counts']));
      expect(cards.first.value, '${asInt(asMap(leads['counts'])['new'])}');
    });

    test('o\'quvchi: my/insights + crm/me upcoming', () {
      final insights = fixtureMap('center_student_my_insights');
      final upcoming = asList(fixtureMap('center_student_crm_me')['upcoming']);
      final cards = studentToday(insights, upcoming: upcoming);
      expect(cards.map((card) => card.key), containsAll(<String>['balance', 'tests', 'homework']));
      if (upcoming.isNotEmpty) expect(cards.map((card) => card.key), contains('next'));
    });

    test('ota-ona (maktab): kundalik bloki', () {
      final insights = fixtureMap('school_guardian_my_insights');
      final cards = studentToday(insights, guardian: true);
      expect(cards, isNotEmpty);
      final school = asMap(insights['school']);
      expect(school['absence_totals'], isA<Map>());
      expect(asList(school['subjects']).first['current_average'], anyOf(isNull, isA<num>()));
    });
  });

  group('to\'lovlar', () {
    test('pay/options: usullar ro\'yxati', () {
      final methods = payMethods(fixtureMap('center_student_pay_options'));
      expect(methods.map((method) => method.key), contains('p2p'));
      expect(methods.every((method) => method.name.isNotEmpty), isTrue);
    });

    test('kartaga o\'tkazma buyurtmasi: rekvizit, summa, muddat', () {
      final order = fixtureMap('center_student_pay_order_p2p');
      final p2p = asMap(order['p2p']);
      expect(asText(p2p['card']), isNotEmpty);
      expect(asInt(p2p['amount']), greaterThanOrEqualTo(asInt(order['amount'])));
      expect(DateTime.tryParse(asText(p2p['expires_at'])), isNotNull);
      // Vaqt fixture'dagi muddatga nisbatan (CI istalgan kuni ishlaydi).
      final expires = DateTime.parse(asText(p2p['expires_at']));
      expect(p2pState(order, expires.subtract(const Duration(minutes: 1))), 'waiting');
      expect(p2pState(order, expires.add(const Duration(minutes: 1))), 'expired');
      final status = fixtureMap('center_student_pay_order');
      expect(status['status'], 'open');
    });

    test('pay/p2p (kassir): kutilayotgan buyurtma', () {
      final data = fixtureMap('center_director_pay_p2p');
      final pending = asList(data['pending']);
      expect(pending, isNotEmpty);
      expect(asInt(pending.first['p2p_amount']), greaterThan(0));
      expect(asMap(pending.first['student'])['full_name'], isNotEmpty);
      expect(asList(data['unknown']), isA<List>());
    });

    test('ota-ona: crm/my/children', () {
      final children = asList(fixtureMap('center_guardian_crm_my_children')['children']);
      expect(children, isNotEmpty);
      expect(children.first['groups'], isA<List>());
      expect(children.first.containsKey('balance'), isTrue);
    });
  });

  group('testlar va skaner', () {
    test('exams/{id}/results: Natijalar varag\'i', () {
      final table = examResultsTable(fixtureMap('center_director_exam_results_filled'));
      expect(table.header.length, greaterThanOrEqualTo(12));
      expect(table.rows, isNotEmpty);
      expect(examResultsTable(<String, dynamic>{}).rows, isEmpty);
    });

    test('scans/kit: kalitlar va o\'quvchilar', () {
      final kit = ExamKit.fromJson(fixtureMap('center_director_scans_kit_filled'));
      expect(kit.questions, greaterThan(0));
      expect(kit.keys, isNotEmpty);
      expect(kit.keys.values.first.length, kit.questions);
      expect(kit.students, isNotEmpty);
      final draft = ExamKit.fromJson(fixtureMap('center_director_scans_kit'));
      expect(draft.keys, isEmpty);
    });
  });

  group('LMS', () {
    test('lms/my/courses va dars bloklari', () {
      expect(asList(fixtureMap('center_student_lms_my_courses')['courses'], 'courses'), isNotEmpty);
      final course = fixtureMap('center_student_lms_my_course');
      expect(course['sections'], isA<List>());
      final blocks = lessonBlocks(fixtureMap('center_student_lms_my_lesson'));
      expect(blocks.map((block) => block.type), contains('content'));
    });
  });

  group('ota-ona farzandlari', () {
    test('school/my/students → GuardianChild (sinflar)', () {
      final students = asList(fixtureMap('school_guardian_school_my_students')['students']);
      expect(students, isNotEmpty);
      expect(students.first['classes'], isA<List>());
      final child = GuardianChild(id: asInt(students.first['id']), name: asText(students.first['full_name']));
      expect(child.firstName, isNotEmpty);
    });
  });

  group('xavfsiz o\'qish (null/tur xatolari crash bermasin)', () {
    test('asRawList va asNumOrNull', () {
      expect(asRawList(null), isEmpty);
      expect(asRawList(<String, dynamic>{'a': 1}), isEmpty);
      expect(asRawList(<int>[1, 2]).length, 2);
      expect(asNumOrNull('12.5'), 12.5);
      expect(asNumOrNull(null), isNull);
      expect(asNumOrNull('abc'), isNull);
      expect(asNumOrNull(3), 3);
    });

    test('sameOrigin: faqat aynan shu server', () {
      expect(sameOrigin('https://edux.uz/labs/ph1', 'https://edux.uz'), isTrue);
      expect(sameOrigin('https://edux.uz.evil.com/x', 'https://edux.uz'), isFalse);
      expect(sameOrigin('http://edux.uz/x', 'https://edux.uz'), isFalse);
      expect(sameOrigin('https://EDUX.uz:443/x', 'https://edux.uz'), isTrue);
      expect(sameOrigin('javascript:alert(1)', 'https://edux.uz'), isFalse);
    });
  });
}
