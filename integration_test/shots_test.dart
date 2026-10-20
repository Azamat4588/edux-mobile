// Screenshots of every role (tool/shots/README.md). Runs on an Android emulator against tool/shots/server.py:
//   flutter test integration_test/shots_test.dart --dart-define=EDUX_SERVER=http://10.0.2.2:8000
// The app is started exactly like lib/main.dart; login goes through the real login form. Each screen is captured
// by the fixture server (POST /__shot/<name> -> `adb exec-out screencap -p`). Nothing in lib/ is changed.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:edux/app.dart';
import 'package:edux/core/api.dart';
import 'package:edux/core/push.dart' show rootNavigator;
import 'package:edux/core/notification_store.dart';
import 'package:edux/core/session.dart';
import 'package:edux/core/widgets.dart';
import 'package:edux/features/auth/login_page.dart';
import 'package:edux/features/billing/billing_page.dart';
import 'package:edux/features/callcenter/callcenter_page.dart';
import 'package:edux/features/crm/leads_page.dart';
import 'package:edux/features/crm/tasks_page.dart';
import 'package:edux/features/finance/finance_page.dart';
import 'package:edux/features/fun/achievements_page.dart';
import 'package:edux/features/fun/games_page.dart';
import 'package:edux/features/fun/labs_page.dart';
import 'package:edux/features/notifications/notifications_page.dart';
import 'package:edux/features/olympiad/olympiad_page.dart';
import 'package:edux/features/olympiad/olympiad_store.dart';
import 'package:edux/features/olympiad/olympiads_page.dart';
import 'package:edux/features/scanner/scans_page.dart';
import 'package:edux/features/staff/attendance_page.dart';
import 'package:edux/features/staff/exams_page.dart';
import 'package:edux/features/staff/students_page.dart';
import 'package:edux/features/student/assignments_page.dart';
import 'package:edux/features/student/certificates_page.dart';
import 'package:edux/features/student/courses_page.dart';
import 'package:edux/features/student/my_tests_page.dart';
import 'package:edux/features/support/support_page.dart';
import 'package:edux/features/testing/topic_tests_page.dart';
import 'package:edux/features/tutor/tutor_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String password = 'password';

class RoleSpec {
  const RoleSpec(this.index, this.role, this.phone);
  final int index;
  final String role;
  final String phone;
  String get prefix => '${index.toString().padLeft(2, '0')}-$role';
}

const List<RoleSpec> roles = <RoleSpec>[
  RoleSpec(1, 'director', '+998900000001'),
  RoleSpec(2, 'admin', '+998901110001'),
  RoleSpec(3, 'cashier', '+998901110004'),
  RoleSpec(4, 'marketer', '+998901110005'),
  RoleSpec(5, 'teacher', '+998901110002'),
  RoleSpec(6, 'student', '+998900000005'),
  RoleSpec(7, 'guardian', '+998900000009'),
  RoleSpec(8, 'owner', '+998900000000'),
];

late IntegrationTestWidgetsFlutterBinding binding;
final List<String> problems = <String>[];

Future<void> post(String path, [List<int> body = const <int>[]]) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final request = await client.postUrl(Uri.parse('${defaultServer.replaceAll(RegExp(r'/+$'), '')}$path'));
    request.contentLength = body.length;
    if (body.isNotEmpty) request.add(body);
    final response = await request.close().timeout(const Duration(seconds: 60));
    await response.drain<void>();
    if (response.statusCode >= 400) throw HttpException('HTTP ${response.statusCode}');
  } finally {
    client.close(force: true);
  }
}

Future<void> say(String message) async {
  // ignore: avoid_print
  print('SHOTS: $message');
  try {
    await post('/__log', utf8.encode(message));
  } catch (_) {}
}

class Shooter {
  Shooter(this.tester, this.spec);

  final WidgetTester tester;
  final RoleSpec spec;
  int _n = 0;
  final List<String> taken = <String>[];

  Session get session => AppScope.read(tester.element(find.byType(MaterialApp).first));

  Future<void> wait(Duration duration) async {
    final end = DateTime.now().add(duration);
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  bool _busy() {
    for (final type in <Type>[SkeletonList, SkeletonBox, CircularProgressIndicator, LinearProgressIndicator, RefreshProgressIndicator]) {
      if (find.byType(type).evaluate().isNotEmpty) return true;
    }
    return false;
  }

  /// Waits until the visible page has no skeletons / spinners (or the timeout), then lets animations finish.
  Future<void> settle({Duration timeout = const Duration(seconds: 20)}) async {
    await wait(const Duration(milliseconds: 600));
    final end = DateTime.now().add(timeout);
    while (_busy() && DateTime.now().isBefore(end)) {
      await wait(const Duration(milliseconds: 250));
    }
    await wait(const Duration(milliseconds: 900));
  }

  Future<bool> waitFor(Finder finder, {Duration timeout = const Duration(seconds: 30)}) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      if (finder.evaluate().isNotEmpty) return true;
      await wait(const Duration(milliseconds: 250));
    }
    return finder.evaluate().isNotEmpty;
  }

  String _texts() {
    final out = <String>[];
    for (final element in find.byType(Text).evaluate()) {
      final widget = element.widget as Text;
      final value = (widget.data ?? widget.textSpan?.toPlainText() ?? '').replaceAll('\n', ' ').trim();
      if (value.isNotEmpty && !out.contains(value)) out.add(value);
      if (out.length >= 30) break;
    }
    return out.join(' | ');
  }

  Future<void> shot(String name, {bool wait = true}) async {
    if (wait) await settle();
    _n++;
    final file = '${spec.prefix}-${_n.toString().padLeft(2, '0')}-$name';
    final states = <String>[
      if (find.byType(ErrorState).evaluate().isNotEmpty) 'ERROR-STATE',
      if (find.byType(ForbiddenState).evaluate().isNotEmpty) 'FORBIDDEN-STATE',
      if (find.byType(EmptyState).evaluate().isNotEmpty) 'empty-state',
      if (_busy()) 'still-loading',
    ];
    try {
      await post('/__shot/$file');
    } catch (error) {
      // Fallback: Flutter surface screenshot uploaded to the server.
      try {
        await binding.convertFlutterSurfaceToImage();
        await tester.pump();
        final bytes = await binding.takeScreenshot(file);
        await post('/__shot/$file', bytes);
      } catch (inner) {
        problems.add('$file: screenshot failed ($error / $inner)');
      }
    }
    taken.add(file);
    await say('$file ${states.isEmpty ? '' : '[${states.join(',')}] '}:: ${_texts()}');
  }

  /// Taps a bottom navigation destination by its label.
  Future<bool> tab(String label) async {
    final finder = find.descendant(of: find.byType(NavigationBar), matching: find.text(label));
    if (finder.evaluate().isEmpty) {
      await say('${spec.prefix}: tab "$label" not found');
      return false;
    }
    await tester.tap(finder.first);
    await tester.pump();
    return true;
  }

  /// Taps a TabBar tab (inside the current page) by its text.
  Future<bool> innerTab(String label) async {
    final finder = find.descendant(of: find.byType(TabBar), matching: find.text(label));
    if (finder.evaluate().isEmpty) {
      await say('${spec.prefix}: inner tab "$label" not found');
      return false;
    }
    await tester.tap(finder.last);
    await tester.pump();
    return true;
  }

  Future<void> open(String name, Widget page, {Future<void> Function()? then}) async {
    try {
      unawaited(rootNavigator.currentState!.push(MaterialPageRoute<void>(builder: (_) => page)));
      await shot(name);
      if (then != null) await then();
    } catch (error, stack) {
      problems.add('${spec.prefix} $name: $error');
      await say('${spec.prefix} $name FAILED: $error\n$stack');
    } finally {
      rootNavigator.currentState?.popUntil((route) => route.isFirst);
      await wait(const Duration(milliseconds: 500));
    }
  }

  Future<void> scrollDown({double by = 900}) async {
    final scrollables = find.byType(Scrollable);
    if (scrollables.evaluate().isEmpty) return;
    await tester.drag(scrollables.first, Offset(0, -by));
    await wait(const Duration(milliseconds: 900));
  }

  Future<List<Map<String, dynamic>>> list(String path, {Map<String, Object?>? query, String key = 'data'}) async {
    try {
      return asList(await session.api.get(path, query: query), key);
    } catch (error) {
      await say('${spec.prefix}: list $path failed: $error');
      return <Map<String, dynamic>>[];
    }
  }
}

Future<void> seedNotifications(String role) async {
  final now = DateTime.now();
  final items = <Map<String, Object?>>[
    if (role == 'student' || role == 'guardian') ...<Map<String, Object?>>[
      <String, Object?>{'title': "To'lov qabul qilindi", 'body': "M-11 guruhi uchun 450 000 so'm to'lov qabul qilindi. Rahmat!", 'type': 'payment', 'm': 25},
      <String, Object?>{'title': 'Test natijasi', 'body': 'Matematika: 2-chorak nazorat ishi — 8 / 10 ball (80%).', 'type': 'attempt', 'm': 140},
      <String, Object?>{'title': 'Yangi uy vazifasi', 'body': "«Kasrlarni qo'shish va ayirish» darsi bo'yicha vazifa berildi.", 'type': 'assignment', 'm': 60 * 26},
      <String, Object?>{'title': 'Davomat', 'body': 'Ergasheva Mohinur bugun M-11 darsiga keldi (15:02).', 'type': 'arrival', 'm': 60 * 50, 'read': true},
    ] else ...<Map<String, Object?>>[
      <String, Object?>{'title': 'Yangi lid', 'body': 'Rahmonov Davron — Matematika, abituriyent (Telegram).', 'type': 'lead', 'm': 12},
      <String, Object?>{'title': "To'lov qabul qilindi", 'body': "Ergasheva Mohinur: 450 000 so'm (naqd), M-11.", 'type': 'payment', 'm': 95},
      <String, Object?>{'title': 'Vazifa muddati', 'body': "Qarzdorlarga qo'ng'iroq qilish — bugun 18:00 gacha.", 'type': 'task', 'm': 60 * 5},
      <String, Object?>{'title': 'Test yakunlandi', 'body': 'IELTS Mock #2 — Oktyabr: 6 ta natija tekshirildi.', 'type': 'attempt', 'm': 60 * 30, 'read': true},
    ],
  ];
  final encoded = <Map<String, Object?>>[
    for (var i = 0; i < items.length; i++)
      <String, Object?>{
        'id': 'shots-$role-$i',
        'title': items[i]['title'],
        'body': items[i]['body'],
        'data': <String, Object?>{'type': items[i]['type']},
        'received_at': now.subtract(Duration(minutes: items[i]['m']! as int)).toIso8601String(),
        'read': items[i]['read'] == true,
      },
  ];
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('notifications.items', jsonEncode(encoded));
  await NotificationStore.instance.load();
}

Future<void> resetDevice() async {
  try {
    await const FlutterSecureStorage().deleteAll();
  } catch (_) {}
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();
  await prefs.setString('locale', 'uz');
  await prefs.setString('theme.mode', 'light');
}

Future<Shooter> startAndLogin(WidgetTester tester, RoleSpec spec, {bool shootLogin = false}) async {
  await resetDevice();
  final session = Session();
  await tester.pumpWidget(AppScope(session: session, child: const EduxApp()));
  await session.restore();
  final s = Shooter(tester, spec);
  if (!await s.waitFor(find.byType(LoginPage))) throw StateError('login page not shown');
  await s.settle();
  if (shootLogin) await s.shot('login');
  final fields = find.byType(TextField);
  await tester.enterText(fields.at(0), spec.phone);
  await tester.enterText(fields.at(1), password);
  await tester.pump();
  if (shootLogin) await s.shot('login-filled', wait: false);
  FocusManager.instance.primaryFocus?.unfocus();
  await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  await tester.tap(find.widgetWithText(FilledButton, 'Kirish'));
  await tester.pump();
  final shell = spec.role == 'owner' ? find.byType(NoOrganizationPage) : find.byType(NavigationBar);
  if (!await s.waitFor(shell, timeout: const Duration(seconds: 45))) {
    await s.shot('login-failed', wait: false);
    throw StateError('${spec.role}: did not reach the home screen');
  }
  await seedNotifications(spec.role);
  return s;
}

Future<void> staffFlow(Shooter s) async {
  final role = s.spec.role;
  final session = s.session;
  await s.shot('home');
  await s.scrollDown();
  await s.shot('home-more', wait: false);
  if (await s.tab('Testlar')) await s.shot('tests');
  if (await s.tab('Skaner')) await s.shot('scanner');
  if (await s.tab(session.term('students', "O'quvchilar"))) await s.shot('students');
  if (await s.tab("Ko'proq")) {
    await s.shot('more');
    await s.scrollDown(by: 700);
    await s.shot('more-scrolled', wait: false);
  }
  await s.tab('Bosh sahifa');

  if (session.canSeeStudents) {
    final students = session.usesCrmStudents
        ? await s.list('crm/students', query: <String, Object?>{'page': 1})
        : await s.list('students', query: <String, Object?>{'page': 1, 'mine': session.isTeacher ? 1 : null});
    if (students.isNotEmpty) {
      final student = students.firstWhere((item) => asText(item['full_name']).contains('Mohinur'), orElse: () => students.first);
      await s.open('student-card', StudentCardPage(studentId: asInt(student['id']), name: asText(student['full_name'])), then: () async {
        await s.scrollDown();
        await s.shot('student-card-more', wait: false);
      });
    }
  }
  if (session.hasModule('testing') && <String>['director', 'admin', 'teacher'].contains(role)) {
    final exams = await s.list('exams');
    final exam = exams.firstWhere((item) => asText(item['status']) != 'draft', orElse: () => exams.isEmpty ? <String, dynamic>{} : exams.first);
    if (exam.isNotEmpty) await s.open('exam-detail', ExamDetailPage(exam: exam));
  }
  if (session.canSeeFinance) {
    await s.open('finance-today', const FinancePage(), then: () async {
      if (await s.innerTab('Qarzdorlar')) await s.shot('finance-debtors');
      if (await s.innerTab('Hisobot')) await s.shot('finance-report');
    });
  }
  if (session.canCallCenter) {
    await s.open('callcenter-live', const CallCenterPage(), then: () async {
      if (await s.innerTab('Navbat')) await s.shot('callcenter-queue');
      if (await s.innerTab('Jurnal')) await s.shot('callcenter-log');
      if (await s.innerTab('Skriptlar')) await s.shot('callcenter-scripts');
    });
  }
  if (session.canSeeLeads) {
    await s.open('leads', const LeadsPage());
    final leads = await s.list('crm/leads', query: <String, Object?>{'status': 'new', 'archived': 0});
    if (leads.isNotEmpty) await s.open('lead', LeadPage(leadId: asInt(leads.first['id'])));
  }
  if (session.canSeeTasks) await s.open('tasks', const TasksPage());
  if (session.canMarkAttendance) {
    await s.open('attendance', const AttendancePage());
    final groups = await s.list('crm/groups', query: <String, Object?>{'active': 1});
    if (groups.isNotEmpty) {
      final group = groups.firstWhere((item) => asText(item['name']) == 'M-11', orElse: () => groups.first);
      await s.open('attendance-sheet', AttendanceSheetPage(groupId: asInt(group['id']), groupName: asText(group['name'])));
    }
  }
  if (session.canScan) await s.open('scans', const ScansPage(initialTab: 1));
  if (session.canBuildTopicTests) await s.open('topic-tests', const TopicTestsPage());
  if (session.canUseStaffAi) await s.open('ai-assistant', const StaffAssistantPage());
  if (session.canManageBilling) {
    await s.open('billing', const BillingPage(), then: () async {
      await s.scrollDown();
      await s.shot('billing-more', wait: false);
      await s.scrollDown();
      await s.shot('billing-more-2', wait: false);
    });
  }
  await s.open('notifications', const NotificationsPage());
  await supportFlow(s);
}

Future<void> studentFlow(Shooter s) async {
  final session = s.session;
  await s.shot('home');
  await s.scrollDown();
  await s.shot('home-more', wait: false);
  if (await s.tab('Testlar')) await s.shot('tests');
  if (await s.tab('Kurslar')) await s.shot('courses');
  if (await s.tab('Kundalik')) await s.shot('diary');
  if (await s.tab("Ko'proq")) {
    await s.shot('more');
    await s.scrollDown(by: 700);
    await s.shot('more-scrolled', wait: false);
  }
  await s.tab('Bosh sahifa');

  final exams = await s.list('my/exams', key: 'exams');
  final done = exams.where((item) => asInt(asMap(item['attempt'])['id']) > 0).toList();
  if (done.isNotEmpty) {
    await s.open('test-result', AttemptResultPage(attemptId: asInt(asMap(done.first['attempt'])['id'])), then: () async {
      await s.scrollDown();
      await s.shot('test-result-more', wait: false);
    });
  }
  final courses = await s.list('lms/my/courses', key: 'courses');
  if (courses.isNotEmpty) {
    final course = courses.first;
    await s.open('course', CoursePage(courseId: asInt(course['id']), title: asText(course['title'])));
    try {
      final detail = asMap(await session.api.get('lms/my/courses/${asInt(course['id'])}'));
      final sections = asList(detail['sections']);
      final lessons = sections.expand((section) => asList(section['lessons'])).toList();
      if (lessons.isNotEmpty) await s.open('lesson', LessonPage(lessonId: asInt(lessons.first['id'])));
    } catch (error) {
      await say('lesson lookup failed: $error');
    }
  }
  if (session.hasModule('lms')) await s.open('assignments', const AssignmentsPage());
  await s.open('certificates', const CertificatesPage());
  if (session.hasModule('testing')) await s.open('mock-results', const MockProgressPage());
  if (session.hasFeature('olympiad')) {
    const tokens = <String>['qpawfft3s432', 'sklssskru2zd', '0khb5onxpi7z'];
    for (final token in tokens.reversed) {
      await OlympiadStore.remember(session, token);
    }
    await s.open('olympiads', const OlympiadsPage());
    await s.open('olympiad', const OlympiadPage(token: 'sklssskru2zd'));
  }
  if (session.canUseTutor) await s.open('ai-tutor', const TutorPage());
  if (session.hasFeature('fun')) {
    await s.open('games', const GamesPage());
    await s.open('achievements', const AchievementsPage());
    await s.open('labs', const LabsPage());
  }
  await s.open('notifications', const NotificationsPage());
  await supportFlow(s);
}

Future<void> guardianFlow(Shooter s) async {
  await s.shot('child-overview');
  await s.scrollDown();
  await s.shot('child-overview-more', wait: false);
  if (await s.innerTab('Kundalik')) await s.shot('child-diary');
  if (await s.innerTab('Testlar')) await s.shot('child-tests');
  if (await s.innerTab("To'lov va davomat")) await s.shot('child-payments');
  if (await s.tab("Ko'proq")) await s.shot('more');
  await s.tab('Farzandim');
  await s.open('notifications', const NotificationsPage());
  await supportFlow(s);
}

Future<void> supportFlow(Shooter s) async {
  await s.open('support', const SupportPage());
  final tickets = await s.list('my/support');
  if (tickets.isNotEmpty) await s.open('support-ticket', TicketPage(token: asText(tickets.first['token'])));
}

Future<void> ownerFlow(Shooter s) async {
  await s.shot('no-organization');
}

void main() {
  binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  for (final spec in roles) {
    testWidgets('screenshots: ${spec.prefix}', (tester) async {
      final original = FlutterError.onError;
      final errors = <String>[];
      FlutterError.onError = (details) {
        final text = details.exceptionAsString().split('\n').first;
        if (errors.length < 40) errors.add(text);
        // ignore: avoid_print
        print('SHOTS FLUTTER ERROR [${spec.prefix}]: ${details.exceptionAsString()}');
      };
      Shooter? shooter;
      try {
        shooter = await startAndLogin(tester, spec, shootLogin: spec.index == 1);
        switch (spec.role) {
          case 'student':
            await studentFlow(shooter);
          case 'guardian':
            await guardianFlow(shooter);
          case 'owner':
            await ownerFlow(shooter);
          default:
            await staffFlow(shooter);
        }
      } catch (error, stack) {
        problems.add('${spec.prefix}: $error');
        await say('${spec.prefix} FAILED: $error\n$stack');
      } finally {
        try {
          await shooter?.session.signOut();
          await tester.pump(const Duration(milliseconds: 500));
        } catch (_) {}
        FlutterError.onError = original;
      }
      await say('${spec.prefix}: ${shooter?.taken.length ?? 0} screenshots; flutter errors: ${errors.isEmpty ? 'none' : errors.toSet().join(' || ')}');
    }, timeout: const Timeout(Duration(minutes: 20)));
  }

  tearDownAll(() async {
    await say('DONE. problems: ${problems.isEmpty ? 'none' : problems.join(' || ')}');
  });
}
