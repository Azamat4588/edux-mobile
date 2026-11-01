import 'package:edux/core/nav.dart';
import 'package:flutter_test/flutter_test.dart';

NavContext ctx(String role, Set<String> allowed) => NavContext(role: role, can: allowed.contains);

void main() {
  test('direktor: birinchi 4 bo\'lim pastki menyuda, qolgani «Yana»da', () {
    final sections = buildNav(ctx('director', <String>{'crm', 'students', 'leads', 'attendance', 'testing', 'scan', 'lms_staff', 'finance', 'p2p', 'tasks', 'billing'}));
    expect(sections.map((item) => item.key).toList(), <String>['home', 'students', 'education', 'testing', 'finance', 'comms', 'settings']);
    final bottom = bottomNav(sections);
    expect(bottom.map((item) => item.key).toList(), <String>['home', 'students', 'education', 'testing']);
    expect(bottom.every((item) => item.kind == 'section'), isTrue);
    expect(overflowSections(sections, bottom).map((item) => item.key).toList(), <String>['finance', 'comms', 'settings']);
    expect(sectionOfTab(sections, 'pay.p2p')?.key, 'finance');
    expect(bottomActive(bottom, section: 'testing'), 'testing');
    expect(bottomActive(bottom, section: 'finance'), isNull);
  });

  test('yorliqsiz bo\'lim chiqmaydi (LMS yo\'q)', () {
    final sections = buildNav(ctx('director', <String>{'students', 'testing'}));
    expect(sections.any((item) => item.key == 'education'), isFalse);
    expect(bottomNav(sections).map((item) => item.key).toList(), <String>['home', 'students', 'testing']);
  });

  test('kassir: to\'lovlar, qarzdorlar, o\'quvchilar', () {
    final sections = buildNav(ctx('cashier', <String>{'crm', 'students', 'p2p', 'tasks'}));
    expect(bottomNav(sections).map((item) => item.key).toList(), <String>['home', 'payments', 'debtors', 'students']);
    expect(sections.firstWhere((item) => item.key == 'payments').tabs.map((tab) => tab.key), contains('pay.p2p'));
    expect(buildNav(ctx('cashier', <String>{})), isEmpty);
  });

  test('ota-ona: bitta bo\'lim — pastki menyuda yorliqlar, «Kurslar» Yana\'da', () {
    final sections = buildNav(ctx('guardian', <String>{'school', 'testing', 'crm', 'lms'}));
    expect(sections, hasLength(1));
    final bottom = bottomNav(sections);
    expect(bottom.map((item) => item.key).toList(), <String>['child', 'child.diary', 'child.tests', 'child.payments']);
    expect(bottom.first.kind, 'tab');
    final more = overflowSections(sections, bottom);
    expect(more.single.tabs.single.key, 'child.courses');
    expect(bottomActive(bottom, tab: 'child.courses'), isNull);
    expect(bottomActive(bottom, tab: 'child.tests'), 'child.tests');
  });

  test('o\'quvchi va mehmon', () {
    final student = buildNav(ctx('student', <String>{'testing', 'lms', 'fun', 'school'}));
    expect(bottomNav(student).map((item) => item.key).toList(), <String>['home', 'tests', 'courses', 'diary']);
    expect(student.firstWhere((item) => item.key == 'courses').tabs.map((tab) => tab.key), contains('fun.labs'));
    final guest = buildNav(ctx('student', <String>{'guest', 'testing'}));
    expect(guest.single.key, 'my');
  });

  test('platforma egasi: platforma SMS shlyuzi', () {
    final sections = buildNav(ctx('', <String>{'platform_sms'}));
    expect(sections.single.tabs.single.key, 'platform.sms');
  });

  test('platforma egasi (3.11): ilovada to\'liq platforma paneli', () {
    final owner = buildNav(ctx('', <String>{'platform', 'platform_sms'}));
    expect(owner.map((item) => item.key).toList(), <String>['home', 'organizations', 'invoices', 'inbox', 'system']);
    expect(bottomNav(owner).map((item) => item.key).toList(), <String>['home', 'organizations', 'invoices', 'inbox']);
    expect(owner.last.tabs.map((tab) => tab.key).toList(), <String>['platform.sessions', 'platform.sms']);
    // iPhone: SMS shlyuzsiz.
    final ios = buildNav(ctx('', <String>{'platform'}));
    expect(ios.last.tabs.map((tab) => tab.key).toList(), <String>['platform.sessions']);
    // Tashkilotda ham ishlaydi: bitta «Platforma» bo'limi oxirida.
    final director = buildNav(ctx('director', <String>{'platform', 'students'}));
    expect(director.last.key, 'platform');
    expect(director.last.tabs.first.key, 'platform.dashboard');
  });
}
