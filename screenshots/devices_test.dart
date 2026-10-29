// App Store skrinshotlari (3.7): iPhone 6.7" — 430×932 @3x (1290×2796 PNG) va iPad 12.9" — 1024×1366 @2x (2048×2732 PNG),
// yorug' va tungi rejim. Ekranlar ilovadagidek: telefonda pastki menyu, iPad'da yon menyu va ikki ustun (ro'yxat + tafsilot).
// Demo ma'lumot — screenshots/fixtures/ (shots_test.dart bilan umumiy soxta server). Natija: screenshots/out/ios, screenshots/out/ipad.
//   flutter test screenshots/devices_test.dart
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:io';
import 'dart:ui' as ui;

import 'package:edux/core/adaptive.dart';
import 'package:edux/core/api.dart';
import 'package:edux/core/feedback.dart';
import 'package:edux/core/home_today.dart';
import 'package:edux/core/home_widgets.dart';
import 'package:edux/core/i18n.dart';
import 'package:edux/core/nav.dart';
import 'package:edux/core/session.dart';
import 'package:edux/core/theme.dart';
import 'package:edux/features/auth/login_page.dart';
import 'package:edux/features/auth/organization_picker.dart';
import 'package:edux/features/feedback/feedback_pages.dart';
import 'package:edux/features/fun/games_page.dart';
import 'package:edux/features/fun/labs_page.dart';
import 'package:edux/features/settings/appearance_page.dart';
import 'package:edux/features/shell/home_shell.dart';
import 'package:edux/features/staff/attendance_page.dart';
import 'package:edux/features/staff/journal_page.dart';
import 'package:edux/features/staff/staff_home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'shots_test.dart' show loadFonts, missing, readJson, scoped, sessionFor, settle;

/// Qurilma: nom (papka), mantiqiy o'lcham, piksel zichligi.
class Device {
  const Device(this.folder, this.size, this.ratio, {required this.wide});

  final String folder;
  final Size size;
  final double ratio;
  final bool wide;
}

const Device iphone = Device('ios', Size(430, 932), 3, wide: false);
const Device ipad = Device('ipad', Size(1024, 1366), 2, wide: true);

/// Android telefon (Play Market): 1080×2340 — 360×780 @3x.
const Device android = Device('android', Size(360, 780), 3, wide: false);

/// Ilova karkasi: menyu (telefonda pastki, iPad'da yon) — HomeShell bilan bir xil manba (nav.dart, AdaptiveNavScaffold).
Widget deviceApp(Session session, Widget page, {required Device device, String? tab, GlobalKey? boundary}) {
  final choice = session.themeChoice;
  AppTheme.apply(dark: choice.mode == 'dark', accent: session.accent, choice: choice);
  Widget body = page;
  if (tab != null) {
    final sections = buildNav(navContextOf(session));
    final bottom = bottomNav(sections, limit: navLimit(device.wide));
    final section = sectionOfTab(sections, tab);
    var index = bottom.indexWhere((item) => item.key == tab || (section != null && item.section == section.key));
    // «Yangi» fikrlar soni — fikrlar bo'limida (menyuda bo'lmasa «Yana» da), HomeShell kabi.
    final badge = session.can('feedback_manage') ? feedbackNewCount(session.context) : 0;
    final feedbackSection = sectionOfTab(sections, 'feedback')?.key;
    final shown = bottom.any((item) => item.section == feedbackSection);
    final destinations = <AdaptiveDestination>[
      for (final item in bottom) AdaptiveDestination(icon: navIcon(item.icon), label: item.label, badge: item.section == feedbackSection ? badge : 0),
      AdaptiveDestination(icon: Icons.menu, label: tr('Yana'), badge: feedbackSection != null && !shown ? badge : 0),
    ];
    if (index < 0) index = destinations.length - 1;
    body = AdaptiveNavScaffold(
      wide: device.wide,
      destinations: destinations,
      selected: index,
      onSelect: (_) {},
      railHeader: RailOrg(name: session.organizationName, logo: null, subtitle: session.membership == null ? '' : roleLabel(session.membership!.role)),
      body: scoped(session, tab, page),
    );
  }
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
        home: body,
      ),
    ),
  );
}

Future<void> captureTo(WidgetTester tester, GlobalKey boundary, Device device, String name) async {
  await tester.runAsync(() async {
    for (final element in find.byType(Image).evaluate()) {
      final widget = element.widget as Image;
      await precacheImage(widget.image, element);
    }
  });
  await tester.pump();
  await tester.runAsync(() async {
    final render = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await render.toImage(pixelRatio: device.ratio);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('screenshots/out/${device.folder}')..createSync(recursive: true);
    File('${dir.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

/// Bitta ekran ikkala rejimda (yorug' va tungi).
Future<void> shootDevice(
  WidgetTester tester,
  Device device,
  String name, {
  required String org,
  required String role,
  required Widget Function() page,
  String? tab,
  String? template,
  String? accent,
  Future<void> Function(WidgetTester tester)? act,
}) async {
  final binding = TestWidgetsFlutterBinding.instance;
  binding.platformDispatcher.views.first.physicalSize = device.size * device.ratio;
  binding.platformDispatcher.views.first.devicePixelRatio = device.ratio;
  await tester.runAsync(() => I18n.load('uz'));
  for (final mode in <String>['light', 'dark']) {
    final session = sessionFor(org, role, mode: mode, template: template, accent: accent);
    final boundary = GlobalKey();
    // Testda soyalar sukut bo'yicha qora chiziq bo'lib chiziladi — haqiqiy soyalar yoqiladi (oxirida qaytariladi).
    debugDisableShadows = false;
    await tester.pumpWidget(deviceApp(session, page(), device: device, tab: tab, boundary: boundary));
    await settle(tester);
    if (act != null) {
      await act(tester);
      await settle(tester, 10);
    }
    await captureTo(tester, boundary, device, mode == 'dark' ? '$name-tungi' : name);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
    debugDisableShadows = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await loadFonts();
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTouch;
    homeClock = () => DateTime(2026, 10, 23, 15, 40);
  });

  tearDownAll(() {
    if (missing.isNotEmpty) {
      // ignore: avoid_print
      print('Fixture topilmadi:\n${missing.toSet().join('\n')}');
    }
  });

  void quietImages() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exception is NetworkImageLoadException || '${details.exception}'.contains('HTTP request failed')) return;
      previous?.call(details);
    };
    addTearDown(() => FlutterError.onError = previous);
  }

  final teacherGroups = asList(readJson('screenshots/fixtures/center/teacher/crm__groups.json'), 'groups');
  final attendance = asMap(readJson('screenshots/fixtures/center/teacher/crm__attendance.json'));
  final journalOptions = asMap(readJson('screenshots/fixtures/school/teacher/school__journal__options.json'));
  final journals = asList(journalOptions['journals'], 'journals');
  final writable = journals.firstWhere((journal) => journal['can_write'] == true, orElse: () => journals.first);
  final feedbackList = asList(readJson('screenshots/fixtures/center/director/feedback.json'));
  final featured = feedbackList.firstWhere((item) => asText(item['kind']) == 'complaint' && item['assignee'] != null, orElse: () => feedbackList.first);

  for (final device in <Device>[iphone, ipad, android]) {
    final prefix = device.folder;

    testWidgets('$prefix 00 kirish', (tester) async {
      quietImages();
      await shootDevice(tester, device, '00-kirish', org: 'center', role: 'guest', page: () => const LoginPage());
    });

    testWidgets('$prefix 01 bosh sahifa', (tester) async {
      quietImages();
      await shootDevice(tester, device, '01-bosh-sahifa', org: 'center', role: 'teacher', page: () => StaffHomePage(onOpen: (_) {}), tab: 'home');
      await shootDevice(tester, device, '01-bosh-sahifa-direktor', org: 'center', role: 'director', page: () => StaffHomePage(onOpen: (_) {}), tab: 'home', template: 'graphite');
    });

    testWidgets('$prefix 08 korinish', (tester) async {
      quietImages();
      await shootDevice(tester, device, '08-korinish', org: 'center', role: 'teacher', page: () => const AppearancePage(), template: 'atlas');
    });

    testWidgets('$prefix 02 jurnal', (tester) async {
      quietImages();
      if (device.wide) {
        // iPad: chapda jurnallar, o'ngda tanlangan jurnal darslari.
        await shootDevice(tester, device, '02-jurnal', org: 'school', role: 'teacher', tab: 'school.journal',
            page: () => const MasterDetail(master: JournalPage()), act: (tester) async {
          await tester.tap(find.text(asText(writable['subject'])).first);
        });
      } else {
        await shootDevice(tester, device, '02-jurnal', org: 'school', role: 'teacher',
            page: () => JournalGridPage(journal: writable, terms: asList(journalOptions['terms'], 'terms'), termId: asInt(journalOptions['current_term_id'])));
      }
    });

    testWidgets('$prefix 03 davomat', (tester) async {
      quietImages();
      Future<void> mark(WidgetTester tester) async {
        final came = find.text('Keldi');
        for (var i = 0; i < 3 && i < came.evaluate().length; i++) {
          await tester.tap(came.at(i));
          await tester.pump();
        }
        if (find.text('Kechikdi').evaluate().length > 3) {
          await tester.tap(find.text('Kechikdi').at(3));
          await tester.pump();
        }
      }

      final group = asMap(attendance['group']);
      if (device.wide) {
        // iPad: chapda guruhlar, o'ngda davomat varaqasi (ikki ustun).
        final name = asText(group['name'], teacherGroups.isEmpty ? '' : asText(teacherGroups.first['name']));
        await shootDevice(tester, device, '03-davomat', org: 'center', role: 'teacher', tab: 'attendance',
            page: () => const MasterDetail(master: AttendancePage()), act: (tester) async {
          await tester.tap(find.text(name).first);
          await settle(tester, 10);
          await mark(tester);
        });
      } else {
        await shootDevice(tester, device, '03-davomat', org: 'center', role: 'teacher',
            page: () => AttendanceSheetPage(groupId: asInt(group['id']), groupName: asText(group['name'])), act: mark);
      }
    });

    testWidgets('$prefix 04 oyinlar', (tester) async {
      quietImages();
      await shootDevice(tester, device, '04-oyinlar', org: 'center', role: 'student', page: () => const GamesPage(), tab: 'fun.games', template: 'spring', accent: 'sunset');
    });

    testWidgets('$prefix 05 laboratoriyalar', (tester) async {
      quietImages();
      await shootDevice(tester, device, '05-laboratoriyalar', org: 'center', role: 'student', page: () => const LabsPage(), tab: 'fun.labs');
      await shootDevice(tester, device, '05-laboratoriyalar-darslik', org: 'center', role: 'student', page: () => const LabsPage(initialTab: 1), tab: 'fun.labs');
    });

    testWidgets('$prefix 06 fikr bildirish', (tester) async {
      quietImages();
      await shootDevice(tester, device, '06-fikr-bildirish', org: 'center', role: 'guardian', page: () => const MyFeedbackPage(), tab: 'child',
          act: (tester) async {
        await tester.tap(find.text('Taklif').first);
        await tester.enterText(find.byType(TextField).first, "Shanba kunlari ham qo'shimcha dars bo'lsa yaxshi bo'lardi — ish kunlari olib kelishga ulgurmaymiz.");
        FocusManager.instance.primaryFocus?.unfocus();
      });
      await shootDevice(tester, device, '06-mening-fikrlarim', org: 'center', role: 'guardian', page: () => const MyFeedbackPage(initialTab: 1), tab: 'child');
    });

    testWidgets('$prefix 07 rahbar fikrlar', (tester) async {
      quietImages();
      if (device.wide) {
        await shootDevice(tester, device, '07-fikrlar', org: 'center', role: 'director', tab: 'feedback', template: 'ocean',
            page: () => const MasterDetail(master: FeedbackAdminPage()), act: (tester) async {
          await tester.tap(find.byType(FeedbackAdminTile).at(feedbackList.indexOf(featured)));
        });
      } else {
        await shootDevice(tester, device, '07-fikrlar', org: 'center', role: 'director', page: () => const FeedbackAdminPage(), tab: 'feedback', template: 'ocean');
        await shootDevice(tester, device, '07-fikr-tafsilot', org: 'center', role: 'director', page: () => FeedbackAdminDetailPage(id: asInt(featured['id'])));
      }
    });
  }
}
