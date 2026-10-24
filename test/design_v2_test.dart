// 3.8 «Daftar 2: hoshiya»: tema tokenlari (docs/design.md jadvali), shablon tanlash, animatsiya darajasi va qurilmadagi
// «harakatni kamaytirish», bosh sahifa mantig'i (diqqat ro'yxati, darslar holati), iPad yon menyusi va sahifa bandi.
import 'package:edux/core/adaptive.dart';
import 'package:edux/core/design.dart';
import 'package:edux/core/home_today.dart';
import 'package:edux/core/illustrations.dart';
import 'package:edux/core/motion.dart';
import 'package:edux/core/theme.dart';
import 'package:edux/core/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(Widget child, {bool reduce = false}) => MaterialApp(
      theme: buildTheme(),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
          child: Scaffold(body: child),
        ),
      ),
    );

Finder introOpacity() => find.descendant(of: find.byType(IntroItem), matching: find.byType(Opacity));

void main() {
  setUp(() {
    Motion.resetSession();
    AppTheme.apply(dark: false, accent: accentOf('blue'));
  });

  group('tokenlar', () {
    test('9 shablon × 2 rejim: docs/design.md jadvalidagi aniq qiymatlar', () {
      expect(themeOptions['template'], hasLength(9));
      for (final template in themeOptions['template']!) {
        expect(templatePalettes[template], hasLength(2), reason: template);
      }
      AppTheme.apply(dark: false, accent: accentOf('blue'), choice: const ThemeChoice(template: 'paper'));
      expect(AppColors.canvas, const Color(0xFFEEECE4));
      expect(AppColors.card, const Color(0xFFFBFAF6));
      expect(AppColors.ink, const Color(0xFF1F1B16));
      expect(AppColors.line, const Color(0xFFDDD8CB));
      AppTheme.apply(dark: true, accent: accentOf('blue'), choice: const ThemeChoice(template: 'ocean'));
      expect(AppColors.canvas, const Color(0xFF08151C));
      expect(AppColors.navActiveFg, const Color(0xFF8DB4FF));
      AppTheme.apply(dark: false, accent: accentOf('blue'), choice: const ThemeChoice(template: 'graphite'));
      expect(AppColors.navBg, const Color(0xFF1F232B));
      expect(AppColors.navDark, isTrue);
      expect(AppColors.lineStrong, const Color(0xFF8A93A3));
    });

    test('12 asosiy rang va holat ranglari', () {
      expect(accents, hasLength(12));
      expect(themeOptions['accent'], accents.map((accent) => accent.key).toList());
      expect(accentOf('teal').c600, const Color(0xFF007595));
      expect(accentOf('noma\'lum').key, 'blue');
      AppTheme.apply(dark: false, accent: accentOf('emerald'));
      expect(AppColors.accent, const Color(0xFF007A55));
      expect(AppColors.accentStrong, const Color(0xFF006045));
      expect(AppColors.successBg, const Color(0xFFECFDF5));
      expect(AppColors.soft(AppColors.danger), const Color(0xFFFFF1F2));
      AppTheme.apply(dark: true, accent: accentOf('emerald'));
      expect(AppColors.success, const Color(0xFF5EE9B5));
      expect(AppColors.warningBg, const Color(0xFF2C2B31));
      expect(AppColors.brand, const Color(0xFF5EE9B5)); // tungi rejimda matn — 300
    });

    test('karta uslubi: shablonga qarab va aniq tanlov', () {
      AppTheme.apply(dark: false, accent: accentOf('blue'), choice: const ThemeChoice(template: 'ocean'));
      expect(AppColors.cardBorder, Colors.transparent); // Okean — tekis
      expect(AppColors.cardShadow, isEmpty);
      AppTheme.apply(dark: false, accent: accentOf('blue'), choice: const ThemeChoice(template: 'ocean', cards: 'bordered'));
      expect(AppColors.cardBorder, const Color(0xFFD3E1E9));
      AppTheme.apply(dark: false, accent: accentOf('blue'), choice: const ThemeChoice(template: 'spring'));
      expect(AppColors.cardShadow.single.blurRadius, 0); // «stiker» soyasi
    });
  });

  group('shablon tanlash', () {
    test('qatlamlar: platforma → tashkilot → shaxsiy; «auto» shablondan', () {
      final choice = ThemeChoice.resolve(<Map<String, dynamic>>[
        <String, dynamic>{'template': 'classic', 'font': 'onest', 'density': 'auto', 'motion': 'full'},
        <String, dynamic>{'template': 'spring', 'accent': 'forest'},
        <String, dynamic>{'motion': 'reduced', 'size': 'xl'},
      ]);
      expect(choice.template, 'spring');
      expect(choice.accent, 'forest');
      expect(choice.font, 'golos'); // platformaning o'zgartirilmagan «onest» standarti — mobilda Golos
      expect(choice.fontFamily, 'GolosText');
      expect(choice.titleFamily, 'Nunito');
      expect(choice.effectiveDensity, 'comfy');
      expect(choice.effectivePattern, 'dots');
      expect(choice.effectiveCards, 'shadow');
      expect(choice.motion, 'reduced');
      expect(choice.textScale, closeTo(19 / 16, 1e-9));
    });

    test('tashkilot tanlagan shrift va Klassik sarlavhasi (Literata)', () {
      final choice = ThemeChoice.resolve(<Map<String, dynamic>>[
        <String, dynamic>{'font': 'onest'},
        <String, dynamic>{'font': 'manrope'},
        <String, dynamic>{},
      ]);
      expect(choice.fontFamily, 'Manrope');
      expect(choice.titleFamily, 'Literata');
      expect(choice.serifTitles, isTrue);
      expect(const ThemeChoice(template: 'soft').floatingNav, isTrue);
      expect(const ThemeChoice(template: 'soft', sidebar: 'full').floatingNav, isFalse);
      expect(const ThemeChoice(template: 'compact').dense, isTrue);
      expect(const ThemeChoice(template: 'night').darkChrome, isTrue);
    });

    test("copyWith: noto'g'ri qiymat e'tiborsiz", () {
      const base = ThemeChoice();
      final next = base.copyWith(<String, String?>{'template': 'paper', 'accent': 'neon', 'motion': 'off'});
      expect(next.template, 'paper');
      expect(next.accent, 'blue');
      expect(next.motion, 'off');
      expect(next.key, isNot(base.key));
    });
  });

  group('harakat', () {
    test('daraja: tanlov va qurilma sozlamasi', () {
      expect(motionLevelOf('full'), MotionLevel.full);
      expect(motionLevelOf('reduced'), MotionLevel.reduced);
      expect(motionLevelOf('off'), MotionLevel.off);
      expect(motionLevelOf('full', systemReduced: true), MotionLevel.off);
    });

    test('sanaladigan raqam: vaqt va nisbat sanalmaydi', () {
      expect(splitCountable("1 200 000 so'm")!.value, 1200000);
      expect(splitCountable("1 200 000 so'm")!.separator, ' ');
      expect(splitCountable('26')!.value, 26);
      expect(splitCountable('16:00'), isNull);
      expect(splitCountable('8 / 12'), isNull);
      expect(splitCountable('4.5'), isNull);
      expect(groupDigitsWith(1200000, ' '), '1 200 000');
      expect(groupDigitsWith(950, ' '), '950');
    });

    testWidgets("To'liq darajada raqam 0 dan sanaladi, seansda bir marta", (tester) async {
      await tester.pumpWidget(host(const CountUpText('120', countKey: 'test')));
      expect(find.text('120'), findsNothing);
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.text('120'), findsOneWidget);
      // Ikkinchi marta — darhol.
      await tester.pumpWidget(host(const SizedBox()));
      await tester.pumpWidget(host(const CountUpText('120', countKey: 'test')));
      expect(find.text('120'), findsOneWidget);
    });

    testWidgets("qurilmada harakat kamaytirilgan: sanash va yuklanish harakati yo'q", (tester) async {
      await tester.pumpWidget(host(
        const IntroScope(id: 'reduce', child: Column(children: <Widget>[IntroItem(index: 1, child: CountUpText('99', countKey: 'reduce'))])),
        reduce: true,
      ));
      expect(find.text('99'), findsOneWidget);
      expect(introOpacity(), findsNothing);
    });

    testWidgets('«O\'chiq» daraja: bosilganda kichraymaydi, intro yo\'q', (tester) async {
      AppTheme.apply(dark: false, accent: accentOf('blue'), choice: const ThemeChoice(motion: 'off'));
      await tester.pumpWidget(host(const IntroScope(id: 'off', child: IntroItem(index: 0, child: Pressable(child: Text('Tugma'))))));
      expect(find.byType(AnimatedScale), findsNothing);
      expect(introOpacity(), findsNothing);
      expect(find.text('Tugma'), findsOneWidget);
    });

    testWidgets("To'liq daraja: bosh sahifa yuklanishi ≤ 600 ms", (tester) async {
      await tester.pumpWidget(host(const IntroScope(id: 'full', child: IntroItem(index: 3, child: Text('Karta')))));
      expect(tester.widget<Opacity>(introOpacity()).opacity, lessThan(1));
      await tester.pump(IntroScope.total);
      expect(tester.widget<Opacity>(introOpacity()).opacity, 1);
    });
  });

  group('bosh sahifa mantig\'i', () {
    test('diqqat ro\'yxati: qizil → sariq → ma\'lumot, nollar tushadi', () {
      final sorted = sortAttention(const <AttentionItem>[
        AttentionItem(key: 'a', tone: 'info', count: 2, text: 'a'),
        AttentionItem(key: 'b', tone: 'warning', count: 1, text: 'b'),
        AttentionItem(key: 'c', tone: 'danger', count: 0, text: 'c'),
        AttentionItem(key: 'd', tone: 'danger', count: 4, text: 'd'),
      ]);
      expect(sorted.map((item) => item.key), <String>['d', 'b', 'a']);
    });

    test("darslar: o'tdi / hozir / keyingi / bekor", () {
      final states = lessonStates(<Map<String, dynamic>>[
        <String, dynamic>{'start': '14:00', 'end': '15:00', 'status': 'planned'},
        <String, dynamic>{'start': '15:30', 'end': '17:00', 'status': 'planned'},
        <String, dynamic>{'start': '17:00', 'end': '18:30', 'status': 'cancelled'},
        <String, dynamic>{'start': '18:00', 'end': '19:00', 'status': 'planned'},
        <String, dynamic>{'start': '19:00', 'end': '20:00', 'status': 'planned'},
      ], DateTime(2026, 10, 23, 15, 40));
      expect(states, <LessonState>[LessonState.done, LessonState.now, LessonState.off, LessonState.next, LessonState.later]);
    });

    test("oy tushumi o'zgarishi va avatar rangi", () {
      expect(monthDeltaPercent(<num>[0, 100, 112]), 12);
      expect(monthDeltaPercent(<num>[0, 50]), isNull);
      expect(stableIndex('Karimova Nodira', 6), stableIndex('Karimova Nodira', 6));
      expect(initialsOf('Karimova Nodira'), 'KN');
      expect(initialsOf(''), '?');
    });

    test('illyustratsiyalar: SVG yo\'llari chiziladi', () {
      for (final art in EmptyArt.values) {
        for (final element in emptyArtSvg[art]!) {
          final bounds = artElementPath(element).getBounds();
          expect(bounds.isEmpty && bounds.width == 0 && bounds.height == 0, isFalse, reason: '$art $element');
          expect(bounds.right, lessThanOrEqualTo(96.5), reason: '$art $element');
        }
      }
      expect(artForIcon(Icons.groups_outlined), EmptyArt.people);
      expect(artForIcon(Icons.receipt_long_outlined), EmptyArt.wallet);
      expect(artForIcon(Icons.star), EmptyArt.notebook);
    });
  });

  group('karkas', () {
    testWidgets("iPad: yon menyu tashkilot bloki va hoshiya bilan", (tester) async {
      tester.view.physicalSize = const Size(1366, 1024) * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: const AdaptiveNavScaffold(
          destinations: <AdaptiveDestination>[
            AdaptiveDestination(icon: Icons.home_outlined, label: 'Bosh sahifa'),
            AdaptiveDestination(icon: Icons.menu, label: 'Yana'),
          ],
          selected: 0,
          onSelect: _noop,
          railHeader: Text('Ilm yo\'li'),
          body: Text('Kontent'),
        ),
      ));
      expect(find.byType(AppRail), findsOneWidget);
      expect(find.text("Ilm yo'li"), findsOneWidget);
      expect(tester.widget<AppRail>(find.byType(AppRail)).extended, isTrue);
    });

    testWidgets("bo'lim sahifasida sarlavha bandi: bo'lim yo'li va yorliqlar", (tester) async {
      final picked = <int>[];
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: SectionScope(
          section: 'students',
          label: "O'quvchilar",
          cluster: 'Kundalik ish',
          color: const Color(0xFF7C3AED),
          tabs: const <SectionTab>[SectionTab('students', "Ro'yxat"), SectionTab('attendance', 'Davomat')],
          onSelect: picked.add,
          child: Builder(builder: (context) => Scaffold(appBar: pageBar(context, title: const Text("Ro'yxat")), body: const SizedBox())),
        ),
      ));
      expect(find.text("Kundalik ish › O'quvchilar"), findsOneWidget);
      expect(find.text('Davomat'), findsOneWidget);
      await tester.tap(find.text('Davomat'));
      expect(picked, <int>[1]);
    });

    testWidgets("ochilgan sahifada — oddiy sarlavha (band yo'q)", (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: Builder(builder: (context) => Scaffold(appBar: pageBar(context, title: const Text('Tafsilot')), body: const SizedBox())),
      ));
      expect(find.text('Tafsilot'), findsOneWidget);
      expect(find.textContaining('›'), findsNothing);
    });
  });
}

void _noop(int _) {}
