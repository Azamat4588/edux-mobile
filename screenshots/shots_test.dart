// Ilova skrinshotlari (README, do'konlar, yordam maqolalari): haqiqiy ekranlar demo ma'lumot bilan, haqiqiy shriftlar bilan
// 390×844 @3x (1170×2532 PNG). Tarmoq — soxta: screenshots/fixtures/<tashkilot>/<rol>/<yo'l>.json (demo serverdan olingan).
// Ishga tushirish: `flutter test screenshots/shots_test.dart` → screenshots/out/*.png
// CI: .github/workflows/screenshots.yml (qo'lda) rasmlarni `screenshots` branch'iga yozadi.
// Bu papka test/ emas (oddiy `flutter test` da ishlamaydi) — test uchun ochiq a'zolar shu yerda ham ishlatiladi.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:edux/core/api.dart';
import 'package:edux/core/games.dart';
import 'package:edux/core/adaptive.dart';
import 'package:edux/core/feedback.dart';
import 'package:edux/core/home_today.dart';
import 'package:edux/core/home_widgets.dart';
import 'package:edux/core/i18n.dart';
import 'package:edux/core/nav.dart';
import 'package:edux/core/notification_store.dart';
import 'package:edux/core/session.dart';
import 'package:edux/core/theme.dart';
import 'package:edux/core/widgets.dart';
import 'package:edux/features/auth/login_page.dart';
import 'package:edux/features/fun/games/game_host.dart';
import 'package:edux/features/fun/games/result_view.dart';
import 'package:edux/features/fun/games_page.dart';
import 'package:edux/features/fun/play_page.dart';
import 'package:edux/features/guardian/guardian_home_page.dart';
import 'package:edux/features/help/help_pages.dart';
import 'package:edux/features/notifications/notifications_page.dart';
import 'package:edux/features/settings/appearance_page.dart';
import 'package:edux/features/settings/settings_page.dart';
import 'package:edux/features/scanner/scanner_hub_page.dart';
import 'package:edux/features/shell/home_shell.dart';
import 'package:edux/features/staff/attendance_page.dart';
import 'package:edux/features/staff/journal_page.dart';
import 'package:edux/features/staff/staff_home_page.dart';
import 'package:edux/features/student/my_payments_page.dart';
import 'package:edux/features/student/my_tests_page.dart';
import 'package:edux/features/student/student_home_page.dart';
import 'package:edux/features/support/support_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const Size kLogical = Size(390, 844);
const double kRatio = 3;
final Directory outDir = Directory('screenshots/out');
final List<String> missing = <String>[];

dynamic readJson(String path) => jsonDecode(File(path).readAsStringSync());

/// Soxta server: GET — fixture fayli; o'yin so'rovlari — test/fixtures/games (start, answer, finish).
class FakeServer {
  FakeServer(this.org, this.role);

  final String org;
  final String role;
  String game = 'quiz';
  int _answer = 0;

  String _name(String path) {
    if (RegExp(r'^public/support/[A-Za-z0-9*]+$').hasMatch(path)) return 'public__support__ticket';
    return path.replaceAll('/', '__');
  }

  dynamic _fixture(String path) {
    final name = _name(path);
    for (final dir in <String>['screenshots/fixtures/$org/$role', 'screenshots/fixtures/$org/guest', 'screenshots/fixtures/center/guest']) {
      final file = File('$dir/$name.json');
      if (file.existsSync()) return jsonDecode(file.readAsStringSync());
    }
    return null;
  }

  Map<String, dynamic> _game() => asMap(readJson('test/fixtures/games/$game.json'));

  Future<http.Response> handle(http.Request request) async {
    final path = request.url.path.replaceFirst(RegExp(r'^/api/v1/'), '');
    Object? body;
    if (request.method == 'POST' && path == 'my/games') {
      game = asText(asMap(jsonDecode(request.body))['game'], game);
      _answer = 0;
      return _json(_game()['start'], 201);
    }
    if (request.method == 'POST' && RegExp(r'^my/games/\d+/answer$').hasMatch(path)) {
      final answers = asList(_game()['answers'], 'answers');
      if (_answer >= answers.length) return _json(<String, dynamic>{'message': 'demo'}, 422);
      return _json(answers[_answer++]['response']);
    }
    if (request.method == 'POST' && RegExp(r'^my/games/\d+/finish$').hasMatch(path)) return _json(_game()['finish']);
    body = _fixture(path);
    if (body == null) {
      missing.add('$org/$role ${request.method} $path');
      return _json(<String, dynamic>{'message': 'Topilmadi'}, 404);
    }
    return _json(body);
  }

  http.Response _json(Object? data, [int status = 200]) =>
      http.Response.bytes(utf8.encode(jsonEncode(data)), status, headers: <String, String>{'content-type': 'application/json; charset=utf-8'});
}

Session sessionFor(String org, String role, {String mode = 'light', String? accent, String? template}) {
  final server = FakeServer(org, role);
  final session = Session(client: MockClient(server.handle));
  if (role == 'guest') {
    session.restoring = false;
    // Kirish oynasi: rejim va shablon platforma standarti orqali.
    session.siteTheme = <String, dynamic>{'mode': mode, if (accent != null) 'accent': accent, if (template != null) 'template': template};
    return session;
  }
  final dir = 'screenshots/fixtures/$org/$role';
  final me = asMap(readJson('$dir/me.json'));
  final user = asMap(me['user'])
    ..['appearance'] = <String, dynamic>{'mode': mode, if (accent != null) 'accent': accent, if (template != null) 'template': template};
  final memberships = asList(me['memberships'], 'memberships').map(Membership.fromJson).toList();
  session.debugSignIn(
    server: 'https://edux.kuchkarov.uz',
    token: 'demo',
    user: user,
    memberships: memberships,
    organizationId: memberships.first.organizationId,
    context: asMap(readJson('$dir/context.json')),
  );
  final site = File('$dir/site.json');
  if (site.existsSync()) {
    final theme = asMap(asMap(jsonDecode(site.readAsStringSync()))['theme']);
    session
      ..siteDesign = theme
      ..siteTheme = asMap(theme['defaults']);
  }
  return session;
}

/// Pastki menyu (HomeShell bilan bir xil manba: nav.dart, AppNavBar) — sahifa ilovadagidek ko'rinsin.
Widget? bottomBar(Session session, String? tab, {int limit = 4}) {
  if (tab == null) return null;
  final sections = buildNav(navContextOf(session));
  final bottom = bottomNav(sections, limit: limit);
  final badge = session.can('feedback_manage') ? feedbackNewCount(session.context) : 0;
  final feedbackSection = sectionOfTab(sections, 'feedback')?.key;
  final shown = bottom.any((item) => item.section == feedbackSection);
  final destinations = <AdaptiveDestination>[
    for (final item in bottom) AdaptiveDestination(icon: navIcon(item.icon), label: item.label, badge: item.section == feedbackSection ? badge : 0),
    AdaptiveDestination(icon: Icons.menu, label: tr('Yana'), badge: feedbackSection != null && !shown ? badge : 0),
  ];
  final section = sectionOfTab(sections, tab);
  var index = bottom.indexWhere((item) => item.key == tab || (section != null && item.section == section.key));
  if (index < 0) index = destinations.length - 1;
  return AppNavBar(destinations: destinations, selected: index, onSelect: (_) {});
}

/// Bo'lim sahifasi sarlavha bandi bilan (HomeShell kabi: bo'lim yo'li, hoshiya, yorliqlar).
Widget scoped(Session session, String? tab, Widget page) {
  if (tab == null || tab == 'home' || tab == 'more' || session.isGuardian) return page;
  final sections = buildNav(navContextOf(session));
  final section = sectionOfTab(sections, tab);
  if (section == null || section.key == 'home') return page;
  return SectionScope(
    section: section.key,
    label: section.label,
    cluster: clusterOf(section.key),
    color: Color(sectionColorOf(section.key)),
    tabs: <SectionTab>[for (final item in section.tabs) SectionTab(item.key, item.label)],
    selected: section.tabs.indexWhere((item) => item.key == tab).clamp(0, section.tabs.length - 1),
    onSelect: (_) {},
    child: page,
  );
}

/// «Yana» sahifasi (HomeShell._more bilan bir xil tuzilma: to'dalar bo'yicha bo'limlar, xabarlar va yordam, sozlamalar).
Widget morePage(Session session) {
  final sections = buildNav(navContextOf(session));
  final overflow = overflowSections(sections, bottomNav(sections));
  final groups = <String, List<Widget>>{};
  for (final section in overflow) {
    for (final tab in section.tabs) {
      groups.putIfAbsent(clusterOf(section.key) ?? tr("Bo'limlar"), () => <Widget>[]).add(MenuTile(
            icon: navIcon(section.icon),
            color: Color(sectionColorOf(section.key)),
            label: section.tabs.length > 1 ? '${section.label}: ${tab.label}' : tab.label,
            onTap: () {},
          ));
    }
  }
  return SettingsPage(groups: <MenuGroup>[
    for (final entry in groups.entries) MenuGroup(entry.key, entry.value),
    MenuGroup(tr('Xabarlar va yordam'), <Widget>[
      MenuTile(icon: Icons.notifications_none_rounded, color: AppColors.accent, label: tr('Bildirishnomalar'), onTap: () {}),
      MenuTile(icon: Icons.support_agent_outlined, color: const Color(0xFF0891B2), label: tr('Murojaatlar'), onTap: () {}),
    ]),
  ]);
}

Widget appFor(Session session, Widget page, {String? tab, GlobalKey? boundary}) {
  final choice = session.themeChoice;
  AppTheme.apply(dark: choice.mode == 'dark', accent: session.accent, choice: choice);
  return RepaintBoundary(
    key: boundary,
    child: AppScope(
      session: session,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        locale: Locale(I18n.locale),
        supportedLocales: const <Locale>[Locale('uz'), Locale('ru'), Locale('en')],
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(body: scoped(session, tab, page), bottomNavigationBar: bottomBar(session, tab)),
      ),
    ),
  );
}

/// FontManifest dagi barcha shriftlar (Onest/Manrope/Nunito, Material ikonkalari, formulalar shriftlari).
Future<void> loadFonts() async {
  final manifest = jsonDecode(await rootBundle.loadString('FontManifest.json')) as List<dynamic>;
  for (final entry in manifest.cast<Map<String, dynamic>>()) {
    final family = entry['family'] as String;
    final loader = FontLoader(family.startsWith('packages/') ? family : family);
    for (final font in (entry['fonts'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    await loader.load();
    // Material ikonkalari ba'zan «MaterialIcons» nomi bilan, paket shriftlari esa qisqa nom bilan ham so'raladi.
    if (family.startsWith('packages/')) {
      final short = family.split('/').last;
      final alias = FontLoader(short);
      for (final font in (entry['fonts'] as List<dynamic>).cast<Map<String, dynamic>>()) {
        alias.addFont(rootBundle.load(font['asset'] as String));
      }
      await alias.load();
    }
  }
}

Future<void> settle(WidgetTester tester, [int frames = 20]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> capture(WidgetTester tester, GlobalKey boundary, String name) async {
  await tester.runAsync(() async {
    // Rasmlar (asset) yuklanishi uchun
    for (final element in find.byType(Image).evaluate()) {
      final widget = element.widget as Image;
      await precacheImage(widget.image, element);
    }
  });
  await tester.pump();
  await tester.runAsync(() async {
    final render = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await render.toImage(pixelRatio: kRatio);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    outDir.createSync(recursive: true);
    File('${outDir.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

/// Bitta ekran: sahifa, yuklanish, ixtiyoriy harakatlar, rasm.
Future<void> shoot(
  WidgetTester tester,
  String name, {
  required String org,
  required String role,
  required Widget page,
  String? tab,
  String mode = 'light',
  String? accent,
  String? template,
  String locale = 'uz',
  Future<void> Function(WidgetTester tester)? act,
}) async {
  await tester.runAsync(() => I18n.load(locale));
  final session = sessionFor(org, role, mode: mode, accent: accent, template: template);
  final boundary = GlobalKey();
  // Testda soyalar sukut bo'yicha qora chiziq bo'lib chiziladi — haqiqiy soyalar (oxirida qaytariladi).
  debugDisableShadows = false;
  await tester.pumpWidget(appFor(session, page, tab: tab, boundary: boundary));
  await settle(tester);
  if (act != null) {
    await act(tester);
    await settle(tester, 6);
  }
  await capture(tester, boundary, name);
  // Taymerlar (o'yin soati va h.k.) to'xtasin
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 2));
  debugDisableShadows = true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await loadFonts();
    // Telefondagidek: klaviatura fokus ramkasi chizilmaydi.
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTouch;
    // Demo kun va vaqt: juma, 23-oktabr, 15:40 (darslar vaqt chizig'ida «hozir» va «keyingi» ko'rinadi).
    homeClock = () => DateTime(2026, 10, 23, 15, 40);
  });

  setUp(() {
    final binding = TestWidgetsFlutterBinding.instance;
    binding.platformDispatcher.views.first.physicalSize = kLogical * kRatio;
    binding.platformDispatcher.views.first.devicePixelRatio = kRatio;
  });

  tearDownAll(() {
    if (missing.isNotEmpty) {
      // ignore: avoid_print
      print('Fixture topilmadi:\n${missing.toSet().join('\n')}');
    }
  });

  // Tarmoq rasmlari (logo, avatar) testda yuklanmaydi — xato emas.
  void quietImages() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exception is NetworkImageLoadException || '${details.exception}'.contains('HTTP request failed')) return;
      previous?.call(details);
    };
    addTearDown(() => FlutterError.onError = previous);
  }

  testWidgets('01 kirish', (tester) async {
    quietImages();
    await shoot(tester, '01-kirish', org: 'center', role: 'guest', page: const LoginPage());
    await shoot(tester, '01-kirish-tungi', org: 'center', role: 'guest', page: const LoginPage(), mode: 'dark');
  });

  testWidgets('02 oqituvchi bosh sahifa', (tester) async {
    quietImages();
    await shoot(tester, '02-oqituvchi-bosh', org: 'center', role: 'teacher', page: StaffHomePage(onOpen: (_) {}), tab: 'home');
    await shoot(tester, '02-oqituvchi-bosh-tungi', org: 'center', role: 'teacher', page: StaffHomePage(onOpen: (_) {}), tab: 'home', mode: 'dark');
  });

  testWidgets('02a direktor bosh sahifa va shablonlar', (tester) async {
    quietImages();
    await shoot(tester, '02-direktor-bosh', org: 'center', role: 'director', page: StaffHomePage(onOpen: (_) {}), tab: 'home');
    await shoot(tester, '02-direktor-bosh-grafit-tungi', org: 'center', role: 'director', page: StaffHomePage(onOpen: (_) {}), tab: 'home', mode: 'dark', template: 'graphite');
    await shoot(tester, '02-oqituvchi-bosh-atlas', org: 'center', role: 'teacher', page: StaffHomePage(onOpen: (_) {}), tab: 'home', template: 'atlas');
    await shoot(tester, '02-oqituvchi-bosh-okean-tungi', org: 'center', role: 'teacher', page: StaffHomePage(onOpen: (_) {}), tab: 'home', mode: 'dark', template: 'ocean', accent: 'teal');
  });

  testWidgets('14 korinish', (tester) async {
    quietImages();
    await shoot(tester, '14-korinish', org: 'center', role: 'teacher', page: const AppearancePage());
    await shoot(tester, '14-korinish-bahor', org: 'center', role: 'student', page: const AppearancePage(), template: 'spring', accent: 'sunset');
  });

  testWidgets('02b yana menyusi', (tester) async {
    quietImages();
    final session = sessionFor('center', 'teacher');
    await shoot(tester, '02-oqituvchi-yana', org: 'center', role: 'teacher', page: morePage(session), tab: 'more');
  });

  testWidgets('02c bildirishnomalar', (tester) async {
    quietImages();
    final now = DateTime.now();
    SharedPreferences.setMockInitialValues(<String, Object>{
      'notifications.items': jsonEncode(<Map<String, Object?>>[
        <String, Object?>{'id': '1', 'title': 'Ergasheva Mohinur keldi', 'body': 'M-9 darsiga 14:02 da keldi.', 'data': <String, Object?>{'type': 'arrival'}, 'received_at': now.subtract(const Duration(minutes: 12)).toIso8601String()},
        <String, Object?>{'id': '2', 'title': "To'lov qabul qilindi", 'body': "Oktabr oyi uchun M-9 guruhi to'lovi: 450 000 so'm (Click).", 'data': <String, Object?>{'type': 'payment'}, 'received_at': now.subtract(const Duration(hours: 3)).toIso8601String()},
        <String, Object?>{'id': '3', 'title': 'Yangi test', 'body': 'Matematika: 1-chorak nazorat ishi — topshirish kerak.', 'data': <String, Object?>{'type': 'attempt'}, 'received_at': now.subtract(const Duration(days: 1)).toIso8601String(), 'read': true},
        <String, Object?>{'id': '4', 'title': 'Murojaatingizga javob', 'body': "Krossvord o'yinida harf yozilmayapti — javob berildi.", 'data': <String, Object?>{'type': 'support'}, 'received_at': now.subtract(const Duration(days: 1, hours: 2)).toIso8601String(), 'read': true},
      ]),
    });
    await tester.runAsync(() => NotificationStore.instance.load());
    await shoot(tester, '02-bildirishnomalar', org: 'center', role: 'teacher', page: const NotificationsPage());
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('03 jurnal', (tester) async {
    quietImages();
    final options = asMap(readJson('screenshots/fixtures/school/teacher/school__journal__options.json'));
    final journals = asList(options['journals'], 'journals');
    final terms = asList(options['terms'], 'terms');
    await shoot(tester, '03-jurnal', org: 'school', role: 'teacher', page: const JournalPage(), tab: 'school.journal');
    if (journals.isNotEmpty) {
      await shoot(tester, '03-jurnal-baholar',
          org: 'school', role: 'teacher', page: JournalGridPage(journal: journals.firstWhere((j) => j['can_write'] == true, orElse: () => journals.first), terms: terms, termId: asInt(options['current_term_id'])));
    }
  });

  testWidgets('04 davomat', (tester) async {
    quietImages();
    final sheet = asMap(readJson('screenshots/fixtures/center/teacher/crm__attendance.json'));
    final group = asMap(sheet['group']);
    await shoot(tester, '04-davomat', org: 'center', role: 'teacher', page: AttendanceSheetPage(groupId: asInt(group['id']), groupName: asText(group['name'])),
        act: (tester) async {
      // Bir nechta o'quvchi belgilangan holat
      final came = find.text('Keldi');
      for (var i = 0; i < 3 && i < came.evaluate().length; i++) {
        await tester.tap(came.at(i));
        await tester.pump();
      }
      if (find.text('Kechikdi').evaluate().length > 3) {
        await tester.tap(find.text('Kechikdi').at(3));
        await tester.pump();
      }
    });
    await shoot(tester, '04-davomat-guruhlar', org: 'center', role: 'teacher', page: const AttendancePage(), tab: 'attendance');
  });

  testWidgets('05 skaner', (tester) async {
    quietImages();
    await shoot(tester, '05-skaner', org: 'center', role: 'teacher', page: const ScannerHubPage(), tab: 'scanner');
  });

  testWidgets('06 oquvchi bosh sahifa', (tester) async {
    quietImages();
    await shoot(tester, '06-oquvchi-bosh', org: 'center', role: 'student', page: const StudentHomePage(), tab: 'home');
    await shoot(tester, '06-oquvchi-bosh-tungi', org: 'center', role: 'student', page: const StudentHomePage(), tab: 'home', mode: 'dark');
    await shoot(tester, '06-oquvchi-bosh-bahor', org: 'center', role: 'student', page: const StudentHomePage(), tab: 'home', template: 'spring', accent: 'sunset');
  });

  testWidgets('07 testlar', (tester) async {
    quietImages();
    await shoot(tester, '07-testlar', org: 'center', role: 'student', page: const MyTestsPage(), tab: 'my');
  });

  testWidgets('08 oyinlar katalogi', (tester) async {
    quietImages();
    await shoot(tester, '08-oyinlar', org: 'center', role: 'student', page: const GamesPage(), tab: 'fun.games');
    await shoot(tester, '08-oyinlar-tungi', org: 'center', role: 'student', page: const GamesPage(), tab: 'fun.games', mode: 'dark', act: (tester) async {
      await tester.drag(find.byType(ListView).first, const Offset(0, -1450));
      await settle(tester, 5);
    });
  });

  testWidgets('09 oyinlar', (tester) async {
    quietImages();
    // Viktorina: to'g'ri javob belgilangan holat
    await shoot(tester, '09-oyin-viktorina', org: 'center', role: 'student', page: const PlayPage(game: 'quiz', id: 2, title: 'Fizika'), act: (tester) async {
      final first = asMap(asList(asMap(readJson('test/fixtures/games/quiz.json'))['answers'], 'answers').first['response']);
      final start = asMap(asMap(readJson('test/fixtures/games/quiz.json'))['start']);
      final question = asList(start['questions'], 'questions').first;
      final right = asList(question['options'], 'options').firstWhere((option) => asInt(option['id']) == asInt(first['correct_option_id']));
      await tester.tap(find.widgetWithText(OptionButton, asText(right['body'])).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 560));
    });
    await shoot(tester, '09-oyin-millioner', org: 'center', role: 'student', page: const PlayPage(game: 'millionaire', id: 2, title: 'Fizika'), act: (tester) async {
      await tester.tap(find.text('50/50'));
      await settle(tester, 5);
    });
    await shoot(tester, '09-oyin-krossvord', org: 'center', role: 'student', page: const PlayPage(game: 'crossword', id: 2, title: 'Ingliz tili: hayvonlar'),
        act: (tester) async {
      // Katak tanlangan holat (javoblar yozilmaydi — demo to'plam savollari serverdagi tuzatishdan keyin to'g'ri chiqadi).
      await tester.tap(find.text('1').first);
      await tester.pump();
    });
    await shoot(tester, '09-oyin-dor', org: 'center', role: 'student', page: const PlayPage(game: 'hangman', id: 6, title: 'Informatika: atamalar'), act: (tester) async {
      final start = asMap(asMap(readJson('test/fixtures/games/hangman.json'))['start']);
      final alphabet = asRawList(start['alphabet']).map((item) => '$item').toList();
      for (final letter in <String>[alphabet.first, 'X', 'O']) {
        if (!alphabet.contains(letter)) continue;
        await tester.tap(find.text(letter).last);
        await settle(tester, 3);
      }
    });
    // Natija ekrani: demo natija (viktorina, 12 / 15).
    final finish = asMap(asMap(readJson('test/fixtures/games/quiz.json'))['finish']);
    final review = asList(finish['review'], 'review');
    for (var i = 0; i < review.length; i++) {
      review[i]['ok'] = i != 3 && i != 8 && i != 12;
    }
    finish
      ..['score'] = 1236
      ..['correct'] = 12
      ..['duration_ms'] = 72400
      ..['xp'] = 14
      ..['best'] = 1236
      ..['review'] = review
      ..['leaderboard'] = <Map<String, Object?>>[
        <String, Object?>{'name': 'Ergasheva Mohinur', 'score': 1236, 'me': true},
        <String, Object?>{'name': 'Karimov Sardor', 'score': 1180, 'me': false},
        <String, Object?>{'name': 'Hasanova Malika', 'score': 960, 'me': false},
      ];
    await shoot(tester, '09-oyin-natija', org: 'center', role: 'student',
        page: Scaffold(appBar: AppBar(title: Text(tr('Viktorina-blits'))), body: GameResultView(result: GameResult.fromJson(finish), onAgain: () {})));
  });

  testWidgets('10 ota-ona farzandim', (tester) async {
    quietImages();
    await shoot(tester, '10-ota-ona', org: 'center', role: 'guardian', page: GuardianHomePage(tab: ValueNotifier<String>('child')), tab: 'child');
    // Yumshoq shablon (ota-onalar uchun): suzuvchi pastki menyu, soyali kartalar.
    await shoot(tester, '10-ota-ona-yumshoq', org: 'center', role: 'guardian', page: GuardianHomePage(tab: ValueNotifier<String>('child')), tab: 'child', template: 'soft', accent: 'violet');
  });

  testWidgets('11 tolovlarim', (tester) async {
    quietImages();
    await shoot(tester, '11-tolovlarim', org: 'center', role: 'student', page: const MyPaymentsPage(), tab: 'my.payments');
  });

  testWidgets('12 yordam', (tester) async {
    quietImages();
    await shoot(tester, '12-yordam', org: 'center', role: 'teacher', page: const HelpPage());
    await shoot(tester, '12-yordam-maqola', org: 'center', role: 'teacher', page: const HelpArticlePage(slug: 'oqituvchi-telefonda'));
  });

  testWidgets('13 murojaat', (tester) async {
    quietImages();
    await shoot(tester, '13-murojaatlar', org: 'center', role: 'student', page: const SupportPage());
    await shoot(tester, '13-murojaat', org: 'center', role: 'student', page: const TicketPage(token: 'demoTokenDemoTokenDemoTokenDemoToken1234'));
  });
}
