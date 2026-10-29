// 3.9 dizayn v3 «Koshin»: tema tokenlari (docs/design.md jadvali), koshin plitkalar, shablon tanlash, animatsiya darajasi
// va qurilmadagi «harakatni kamaytirish», bosh sahifa yuklanishi (≤ 700 ms), iPad yon menyusi va sahifa bandi.
import 'package:edux/core/adaptive.dart';
import 'package:edux/core/design.dart';
import 'package:edux/core/home_today.dart';
import 'package:edux/core/home_widgets.dart';
import 'package:edux/core/illustrations.dart';
import 'package:edux/core/koshin.dart';
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
    AppTheme.apply(dark: false, accent: accentOf('teal'));
  });

  group('tokenlar', () {
    test('9 shablon × 2 rejim: docs/design.md jadvalidagi aniq qiymatlar', () {
      for (final template in themeOptions['template']!) {
        expect(templatePalettes[template], hasLength(2), reason: template);
      }
      AppTheme.apply(dark: false, accent: accentOf('teal'));
      expect(AppColors.canvas, const Color(0xFFF2F6F9));
      expect(AppColors.card, const Color(0xFFFFFFFF));
      expect(AppColors.ink, const Color(0xFF111C3A));
      expect(AppColors.line, const Color(0xFFDDE5EC));
      expect(AppColors.navActiveBg, const Color(0xFF00808B));
      expect(AppColors.chrome, const Color(0xFFFFFFFF));
      AppTheme.apply(dark: false, accent: accentOf('teal'), choice: const ThemeChoice(template: 'atlas'));
      expect(AppColors.canvas, const Color(0xFFFAF4F8));
      expect(AppColors.navBg, const Color(0xFF3A1342));
      expect(AppColors.navActiveBg, Koshin.shafran);
      expect(AppColors.navActiveFg, Koshin.shafranInk);
      expect(AppColors.navDark, isTrue);
      AppTheme.apply(dark: true, accent: accentOf('teal'), choice: const ThemeChoice(template: 'ocean'));
      expect(AppColors.canvas, const Color(0xFF07151B));
      expect(AppColors.chrome, const Color(0xFF0A1A21));
      AppTheme.apply(dark: false, accent: accentOf('teal'), choice: const ThemeChoice(template: 'graphite'));
      expect(AppColors.navBg, const Color(0xFF16191F));
      expect(AppColors.lineStrong, const Color(0xFF8A93A3));
      AppTheme.apply(dark: false, accent: accentOf('teal'), choice: const ThemeChoice(template: 'school'));
      expect(AppColors.navActiveBg, const Color(0xFFE1EDEE));
      expect(AppColors.canvas, const Color(0xFFF3F7FF));
      AppTheme.apply(dark: true, accent: accentOf('teal'), choice: const ThemeChoice(template: 'night'));
      expect(AppColors.navBg, const Color(0xFF0A1640));
    });

    test('12 asosiy rang (Feruza standart) va holat ranglari', () {
      expect(accents, hasLength(12));
      expect(accents.first.key, 'teal');
      expect(themeOptions['accent']!.toSet(), accents.map((accent) => accent.key).toSet());
      expect(accentOf('teal').c600, const Color(0xFF00808B));
      expect(accentOf('noma\'lum').key, 'teal');
      for (final accent in accents) {
        expect(contrastRatio(Colors.white, accent.c600), greaterThanOrEqualTo(4.5), reason: accent.key);
      }
      AppTheme.apply(dark: false, accent: accentOf('emerald'));
      expect(AppColors.accent, const Color(0xFF008561));
      expect(AppColors.accentStrong, const Color(0xFF006E50));
      expect(AppColors.successBg, const Color(0xFFECFDF5));
      expect(AppColors.soft(AppColors.danger), const Color(0xFFFFF1F2));
      AppTheme.apply(dark: true, accent: accentOf('emerald'));
      expect(AppColors.success, const Color(0xFF5EE9B5));
      expect(AppColors.warningBg, const Color(0xFF2C2C33));
      expect(AppColors.brand, const Color(0xFF67E0B3)); // tungi rejimda matn — 300
      expect(AppColors.toneDanger, Koshin.anor);
    });

    test('koshin ranglari: plitka matni o\'qiladi (oq yoki shafran siyohi)', () {
      for (final hue in KoshinHue.values) {
        expect(contrastRatio(Koshin.onTile(hue), Koshin.of(hue)), greaterThanOrEqualTo(4.5), reason: hue.name);
      }
      // To'liq rangli (Koshin) va och (Ixcham, Grafit) plitka.
      expect(KoshinTileColors.of(KoshinHue.anor).background, Koshin.anor);
      for (final template in <String>['compact', 'graphite']) {
        for (final dark in <bool>[false, true]) {
          AppTheme.apply(dark: dark, accent: accentOf('teal'), choice: ThemeChoice(template: template));
          for (final hue in KoshinHue.values) {
            final colors = KoshinTileColors.of(hue);
            expect(colors.background, isNot(Koshin.of(hue)));
            expect(contrastRatio(colors.value, colors.background), greaterThanOrEqualTo(4.5), reason: '$template $dark ${hue.name}');
            expect(contrastRatio(colors.text, colors.background), greaterThanOrEqualTo(4.5), reason: '$template $dark ${hue.name}');
          }
        }
      }
    });

    test('karta uslubi: v3 standarti soyasiz; Okean tekis; Bahor stiker', () {
      AppTheme.apply(dark: false, accent: accentOf('teal'));
      expect(AppColors.cardBorder, const Color(0xFFDDE5EC));
      expect(AppColors.cardShadow, isEmpty);
      AppTheme.apply(dark: false, accent: accentOf('teal'), choice: const ThemeChoice(template: 'ocean'));
      expect(AppColors.cardBorder, Colors.transparent);
      AppTheme.apply(dark: false, accent: accentOf('teal'), choice: const ThemeChoice(template: 'ocean', cards: 'bordered'));
      expect(AppColors.cardBorder, const Color(0xFFD0E4EA));
      AppTheme.apply(dark: false, accent: accentOf('teal'), choice: const ThemeChoice(template: 'spring'));
      expect(AppColors.cardShadow.first.blurRadius, 0); // «stiker» soyasi
      expect(AppRadius.kpi, greaterThan(AppRadius.card));
    });
  });

  group('shablon tanlash', () {
    test('qatlamlar va «auto» shablondan', () {
      final choice = ThemeChoice.resolve(<Map<String, dynamic>>[
        <String, dynamic>{'template': 'classic', 'font': 'onest', 'density': 'auto', 'motion': 'full'},
        <String, dynamic>{'template': 'spring', 'accent': 'forest'},
        <String, dynamic>{'motion': 'reduced', 'size': 'xl'},
      ]);
      expect(choice.template, 'spring');
      expect(choice.accent, 'forest');
      expect(choice.fontFamily, 'Onest');
      expect(choice.titleFamily, 'Nunito');
      expect(choice.effectiveDensity, 'comfy');
      expect(choice.effectivePattern, 'dots');
      expect(choice.effectiveCards, 'shadow');
      expect(choice.motion, 'reduced');
      expect(choice.textScale, closeTo(19 / 16, 1e-9));
    });

    test("copyWith: eski qiymat yangisiga, noto'g'ri qiymat e'tiborsiz", () {
      const base = ThemeChoice();
      final next = base.copyWith(<String, String?>{'template': 'paper', 'accent': 'neon', 'motion': 'off'});
      expect(next.template, 'atlas');
      expect(next.accent, 'teal');
      expect(next.motion, 'off');
      expect(next.key, isNot(base.key));
    });
  });

  group('harakat', () {
    test('daraja: tanlov va qurilma sozlamasi (kamaytirish — kamida «Kam»)', () {
      expect(motionLevelOf('full'), MotionLevel.full);
      expect(motionLevelOf('reduced'), MotionLevel.reduced);
      expect(motionLevelOf('off'), MotionLevel.off);
      expect(motionLevelOf('full', systemReduced: true), MotionLevel.reduced);
      expect(motionLevelOf('off', systemReduced: true), MotionLevel.off);
    });

    test('yuklanish jadvali: hamma bo\'lak 700 ms ichida, plitkalar 45 ms navbat bilan', () {
      for (var order = 0; order < 8; order++) {
        final slot = IntroTiming.tile(order);
        expect(slot.$1 + slot.$2, lessThanOrEqualTo(IntroScope.total.inMilliseconds), reason: 'tile $order');
      }
      expect(IntroTiming.tile(1).$1 - IntroTiming.tile(0).$1, 45);
      for (var index = 0; index < 6; index++) {
        final slot = IntroTiming.block(index);
        expect(slot.$1 + slot.$2, lessThanOrEqualTo(IntroScope.total.inMilliseconds), reason: 'block $index');
      }
      expect(IntroScope.total.inMilliseconds, lessThanOrEqualTo(700));
    });

    test('sanaladigan raqam: vaqt va nisbat sanalmaydi', () {
      expect(splitCountable("1 200 000 so'm")!.value, 1200000);
      expect(splitCountable("1 200 000 so'm")!.separator, ' ');
      expect(splitCountable('26')!.value, 26);
      expect(splitCountable('16:00'), isNull);
      expect(splitCountable('8 / 12'), isNull);
      expect(splitCountable('4.5'), isNull);
      expect(groupDigitsWith(1200000, ' '), '1 200 000');
    });

    testWidgets("To'liq darajada raqam 0 dan sanaladi, seansda bir marta", (tester) async {
      await tester.pumpWidget(host(const CountUpText('120', countKey: 'test')));
      expect(find.text('120'), findsNothing);
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.text('120'), findsOneWidget);
      await tester.pumpWidget(host(const SizedBox()));
      await tester.pumpWidget(host(const CountUpText('120', countKey: 'test')));
      expect(find.text('120'), findsOneWidget);
    });

    testWidgets("qurilmada harakat kamaytirilgan: sanash va siljish yo'q, faqat so'nish", (tester) async {
      await tester.pumpWidget(host(
        const IntroScope(
          id: 'reduce',
          child: Column(children: <Widget>[
            IntroTile(order: 0, child: CountUpText('99', countKey: 'reduce')),
            IntroItem(index: 0, shiftOnly: true, child: Text('Salom')),
          ]),
        ),
        reduce: true,
      ));
      expect(find.text('99'), findsOneWidget);
      expect(find.descendant(of: find.byType(IntroTile), matching: find.byType(FadeTransition)), findsOneWidget);
      // Hero faqat siljiydi — «Kam» da harakatsiz.
      expect(find.descendant(of: find.byType(IntroItem), matching: find.byType(Transform)), findsNothing);
      await tester.pump(IntroScope.total);
    });

    testWidgets("«O'chiq» daraja: bosilganda kichraymaydi, intro yo'q", (tester) async {
      AppTheme.apply(dark: false, accent: accentOf('teal'), choice: const ThemeChoice(motion: 'off'));
      await tester.pumpWidget(host(const IntroScope(id: 'off', child: IntroItem(index: 0, child: Pressable(child: Text('Tugma'))))));
      expect(find.byType(AnimatedScale), findsNothing);
      expect(introOpacity(), findsNothing);
      expect(find.text('Tugma'), findsOneWidget);
    });

    testWidgets("To'liq daraja: bosh sahifa yuklanishi ≤ 700 ms, plitka «qo'yiladi»", (tester) async {
      await tester.pumpWidget(host(const IntroScope(
        id: 'full',
        child: Column(children: <Widget>[IntroItem(index: 2, child: Text('Karta')), IntroTile(order: 1, child: Text('Plitka'))]),
      )));
      expect(tester.widget<Opacity>(introOpacity()).opacity, lessThan(1));
      final tileOpacity = find.descendant(of: find.byType(IntroTile), matching: find.byType(Opacity));
      expect(tester.widget<Opacity>(tileOpacity).opacity, lessThan(1));
      await tester.pump(IntroScope.total);
      expect(tester.widget<Opacity>(introOpacity()).opacity, 1);
      expect(tester.widget<Opacity>(tileOpacity).opacity, 1);
      // Ikkinchi ochilishda — harakatsiz.
      await tester.pumpWidget(host(const SizedBox()));
      await tester.pumpWidget(host(const IntroScope(id: 'full', child: IntroItem(index: 2, child: Text('Karta')))));
      expect(introOpacity(), findsNothing);
    });

    testWidgets("muvaffaqiyat muhri: to'liq, kam va o'chiq darajada chiziladi", (tester) async {
      await tester.pumpWidget(host(const Center(child: SuccessStamp())));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(SuccessStamp.duration);
      expect(find.byType(SuccessStamp), findsOneWidget);
      await tester.pumpWidget(host(const Center(child: SuccessStamp(size: 60)), reduce: true));
      await tester.pump(SuccessStamp.duration);
      AppTheme.apply(dark: false, accent: accentOf('teal'), choice: const ThemeChoice(motion: 'off'));
      await tester.pumpWidget(host(const Center(child: SuccessStamp(size: 50))));
      expect(tester.takeException(), isNull);
    });
  });

  group('bosh sahifa', () {
    testWidgets('koshin plitka: holat rangida, girih yulduzi bilan, bosiladi', (tester) async {
      var opened = '';
      await tester.pumpWidget(host(SizedBox(
        width: 400,
        child: TodayGrid(
          items: const <TodayItem>[
            TodayItem(key: 'debt', value: '3', text: "o'quvchining qarzi bor", tone: TodayTone.danger, icon: 'warning', target: 'crm.debtors'),
            TodayItem(key: 'lessons', value: '16:00', text: 'ING-5', icon: 'calendar'),
          ],
          onOpen: (target) => opened = target,
        ),
      )));
      await tester.pump(const Duration(seconds: 1));
      final tiles = tester.widgetList<KoshinTile>(find.byType(KoshinTile)).toList();
      expect(tiles.map((tile) => tile.hue), <KoshinHue>[KoshinHue.anor, KoshinHue.lojuvard]);
      expect(find.byType(GirihStar), findsNWidgets(2));
      await tester.tap(find.text("o'quvchining qarzi bor"));
      await tester.pump(const Duration(milliseconds: 300));
      expect(opened, 'crm.debtors');
    });

    test('diqqat ro\'yxati: anor → shafran → ma\'lumot, nollar tushadi', () {
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
      ], DateTime(2026, 10, 23, 15, 40));
      expect(states, <LessonState>[LessonState.done, LessonState.now, LessonState.off, LessonState.next]);
    });

    test("illyustratsiyalar va girih: yo'llar chiziladi", () {
      for (final art in EmptyArt.values) {
        for (final element in emptyArtSvg[art]!) {
          final bounds = artElementPath(element).getBounds();
          expect(bounds.width > 0 || bounds.height > 0, isTrue, reason: '$art $element');
          expect(bounds.right, lessThanOrEqualTo(96.5), reason: '$art $element');
        }
      }
      final star = girihPath(const Size.square(100)).getBounds();
      expect(star.left, inExclusiveRange(0, 17)); // aylangan kvadrat burchagi 17 dan tashqariga chiqadi
      expect(star.width, closeTo(star.height, 0.01));
      expect(artForIcon(Icons.groups_outlined), EmptyArt.people);
      expect(artForIcon(Icons.star), EmptyArt.notebook);
    });
  });

  group('karkas', () {
    testWidgets('iPad: yon menyu tashkilot bloki bilan, faol band — to\'liq rangli tabletka', (tester) async {
      tester.view.physicalSize = const Size(1366, 1024) * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: const AdaptiveNavScaffold(
          destinations: <AdaptiveDestination>[
            AdaptiveDestination(icon: Icons.home_outlined, label: 'Bosh sahifa', color: Color(0xFF2D4BD0)),
            AdaptiveDestination(icon: Icons.menu, label: 'Yana'),
          ],
          selected: 0,
          onSelect: _noop,
          railHeader: Text("Ilm yo'li"),
          body: Text('Kontent'),
        ),
      ));
      expect(find.byType(AppRail), findsOneWidget);
      expect(find.text("Ilm yo'li"), findsOneWidget);
      expect(tester.widget<AppRail>(find.byType(AppRail)).extended, isTrue);
      final (bg, fg) = railActiveColors(const AdaptiveDestination(icon: Icons.home_outlined, label: 'x'));
      expect(bg, AppColors.navActiveBg);
      expect(contrastRatio(fg, bg), greaterThanOrEqualTo(4.5));
    });

    testWidgets("bo'lim sahifasida sarlavha bandi: bo'lim belgisi, yo'li va yorliqlar", (tester) async {
      final picked = <int>[];
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: SectionScope(
          section: 'students',
          label: "O'quvchilar",
          cluster: 'Kundalik ish',
          color: const Color(0xFF0B8576),
          icon: Icons.groups_outlined,
          tabs: const <SectionTab>[SectionTab('students', "Ro'yxat"), SectionTab('attendance', 'Davomat')],
          onSelect: picked.add,
          child: Builder(builder: (context) => Scaffold(appBar: pageBar(context, title: const Text("Ro'yxat")), body: const SizedBox())),
        ),
      ));
      expect(find.text('Kundalik ish'), findsOneWidget);
      expect(find.byType(SectionMark), findsOneWidget);
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
      expect(find.byType(SectionMark), findsNothing);
    });
  });
}

void _noop(int _) {}
