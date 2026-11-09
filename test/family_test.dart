import 'package:edux/core/nav.dart';
import 'package:edux/core/push.dart';
import 'package:flutter_test/flutter_test.dart';

NavContext ctx(String role, Set<String> allowed) => NavContext(role: role, can: allowed.contains);

void main() {
  test('3.22: o\'quvchi — dars hisobotlari, uyda mashq, yakka darslar (CRM bilan)', () {
    final withCrm = buildNav(ctx('student', <String>{'crm', 'lms'}));
    final tabs = withCrm.firstWhere((item) => item.key == 'courses').tabs.map((tab) => tab.key).toList();
    expect(tabs, containsAll(<String>['my.lessons', 'my.practice', 'my.booking']));
    final noCrm = buildNav(ctx('student', <String>{'lms'}));
    expect(noCrm.firstWhere((item) => item.key == 'courses').tabs.map((tab) => tab.key), isNot(contains('my.lessons')));
  });

  test('3.22: push havolalari — oila sahifalari', () {
    String type(String link, [String? serverType]) =>
        PushService.normalize(<String, dynamic>{'link': link, if (serverType != null) 'type': serverType})['type'].toString();
    expect(type('/child/lessons', 'lesson_report'), 'lesson_report');
    expect(type('/lessons', 'progress_report'), 'lesson_report');
    expect(type('/child/practice'), 'practice');
    expect(type('/child/booking', 'booking'), 'family_booking');
    expect(type('/booking', 'booking'), 'family_booking');
    expect(type('/child/reenroll', 'reenroll'), 'reenroll');
    expect(PushService.normalize(<String, dynamic>{'link': '/child/lessons?student=7'})['student_id'], '7');
  });

  test('3.25: qayta ro\'yxat — faqat rahbar va administrator, maktab yoki CRM bilan', () {
    List<String> tabs(String role, Set<String> allowed) =>
        buildNav(ctx(role, allowed)).where((item) => item.key == 'students').expand((item) => item.tabs).map((tab) => tab.key).toList();
    expect(tabs('director', <String>{'students', 'reenroll'}), contains('reenroll'));
    expect(tabs('director', <String>{'students'}), isNot(contains('reenroll')));
  });
}
