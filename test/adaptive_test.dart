// 3.7 (iPhone va iPad): keng ekran mantig'i, yon menyu (NavigationRail) va ro'yxat + tafsilot (MasterDetail).
import 'package:edux/core/adaptive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// iPad Pro 12.9" (yotiq): 1366×1024; iPhone 15 Pro Max: 430×932.
Future<void> setView(WidgetTester tester, Size logical) async {
  tester.view.physicalSize = logical * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
}

const List<AdaptiveDestination> destinations = <AdaptiveDestination>[
  AdaptiveDestination(icon: Icons.home_outlined, label: 'Bosh sahifa'),
  AdaptiveDestination(icon: Icons.groups_outlined, label: "O'quvchilar", badge: 3),
  AdaptiveDestination(icon: Icons.menu, label: 'Yana'),
];

Widget navApp({int selected = 0, ValueChanged<int>? onSelect}) => MaterialApp(
      home: AdaptiveNavScaffold(
        destinations: destinations,
        selected: selected,
        onSelect: onSelect ?? (_) {},
        body: const Center(child: Text('Kontent')),
      ),
    );

/// Ro'yxat: har qator [openDetail] bilan ochadi (telefonda — yangi sahifa, iPad'da — o'ng ustun).
class _Master extends StatelessWidget {
  const _Master();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ro\'yxat')),
      body: ListView(children: <Widget>[
        for (var i = 1; i <= 3; i++)
          Builder(
            builder: (context) => ListTile(
              title: Text('Qator $i'),
              selected: isDetailSelected(context, 'row-$i'),
              onTap: () => openDetail(context, id: 'row-$i', builder: (_) => _Detail(index: i)),
            ),
          ),
      ]),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: !isEmbeddedDetail(context), title: Text('Tafsilot $index')),
      body: Text(isEmbeddedDetail(context) ? 'ustunda' : 'sahifada'),
    );
  }
}

void main() {
  test('keng ekran, menyu va ustunlar chegaralari', () {
    expect(isWideSize(const Size(1024, 1366)), isTrue); // iPad tik
    expect(isWideSize(const Size(1366, 1024)), isTrue); // iPad yotiq
    expect(isWideSize(const Size(678, 1024)), isTrue); // Split View — yarim ekran
    expect(isWideSize(const Size(320, 1024)), isFalse); // Slide Over
    expect(isWideSize(const Size(932, 430)), isFalse); // iPhone yotiq
    expect(navLimit(true), greaterThan(navLimit(false)));
    expect(navLimit(false), 4);
    expect(useTwoPane(wide: true, width: 944), isTrue);
    expect(useTwoPane(wide: true, width: 600), isFalse);
    expect(useTwoPane(wide: false, width: 932), isFalse);
    expect(railExtended(1366), isTrue);
    expect(railExtended(1024), isFalse);
    expect(masterPaneWidth(1300), 400);
    expect(masterPaneWidth(900), 340);
  });

  test("o'qish kengligi: ortiqcha joy ikki chetga teng bo'linadi", () {
    const base = EdgeInsets.fromLTRB(16, 12, 16, 24);
    expect(readableInsets(390, base), base);
    final wide = readableInsets(1286, base);
    expect(wide.left, wide.right);
    expect(1286 - wide.left - wide.right, closeTo(kReadableWidth, 0.001));
    expect(wide.top, 12);
    expect(wide.bottom, 24);
    expect(readableInsets(double.infinity, base), base);
  });

  test("to'r ustunlari soni", () {
    expect(gridColumns(358), 2); // telefon: kamida 2
    expect(gridColumns(358, minTile: 320, minColumns: 1, maxColumns: 3), 1);
    expect(gridColumns(1148, minTile: 320, minColumns: 1, maxColumns: 3), 3);
    expect(gridColumns(808, minTile: 170), 4);
    expect(gridColumns(560, minTile: 170), 3);
    expect(gridColumns(double.infinity), 2);
  });

  testWidgets('telefonda — pastki menyu', (tester) async {
    await setView(tester, const Size(430, 932));
    await tester.pumpWidget(navApp());
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.text('3'), findsOneWidget); // belgi
  });

  testWidgets("iPad'da — yon menyu, bosilganda va ⌘2 bilan bo'lim tanlanadi", (tester) async {
    await setView(tester, const Size(1024, 1366));
    final picked = <int>[];
    await tester.pumpWidget(navApp(onSelect: picked.add));
    await tester.pump();
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(tester.widget<NavigationRail>(find.byType(NavigationRail)).extended, isFalse);
    await tester.tap(find.text('Yana'));
    expect(picked, <int>[2]);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    expect(picked, <int>[2, 1]);
  });

  testWidgets('iPad yotiq — kengaytirilgan yon menyu', (tester) async {
    await setView(tester, const Size(1366, 1024));
    await tester.pumpWidget(navApp());
    expect(tester.widget<NavigationRail>(find.byType(NavigationRail)).extended, isTrue);
  });

  testWidgets("iPad'da ro'yxat va tafsilot yonma-yon (yangi sahifa ochilmaydi)", (tester) async {
    await setView(tester, const Size(1366, 1024));
    await tester.pumpWidget(const MaterialApp(home: MasterDetail(master: _Master(), hint: 'Qatorni tanlang')));
    expect(find.text('Qatorni tanlang'), findsOneWidget);
    await tester.tap(find.text('Qator 2'));
    await tester.pumpAndSettle();
    expect(find.text('Tafsilot 2'), findsOneWidget);
    expect(find.text('ustunda'), findsOneWidget);
    expect(find.text('Qator 1'), findsOneWidget); // ro'yxat joyida
    expect(find.byType(BackButton), findsNothing);
    expect(tester.widget<ListTile>(find.widgetWithText(ListTile, 'Qator 2')).selected, isTrue);
    await tester.tap(find.text('Qator 3'));
    await tester.pumpAndSettle();
    expect(find.text('Tafsilot 3'), findsOneWidget);
    expect(find.text('Tafsilot 2'), findsNothing);
  });

  testWidgets("saqlanmagan o'zgarish bo'lsa boshqa qator tanlanmaydi", (tester) async {
    await setView(tester, const Size(1366, 1024));
    await tester.pumpWidget(const MaterialApp(home: MasterDetail(master: _Master())));
    await tester.tap(find.text('Qator 1'));
    await tester.pumpAndSettle();
    final state = tester.state<MasterDetailState>(find.byType(MasterDetail));
    state.guard = () async => false;
    await tester.tap(find.text('Qator 2'));
    await tester.pumpAndSettle();
    expect(find.text('Tafsilot 1'), findsOneWidget);
    expect(state.selected, 'row-1');
    state.guard = () async => true;
    await tester.tap(find.text('Qator 2'));
    await tester.pumpAndSettle();
    expect(find.text('Tafsilot 2'), findsOneWidget);
  });

  testWidgets('telefonda tafsilot yangi sahifada ochiladi', (tester) async {
    await setView(tester, const Size(430, 932));
    await tester.pumpWidget(const MaterialApp(home: MasterDetail(master: _Master())));
    await tester.tap(find.text('Qator 1'));
    await tester.pumpAndSettle();
    expect(find.text('Tafsilot 1'), findsOneWidget);
    expect(find.text('sahifada'), findsOneWidget);
    expect(find.text('Qator 2'), findsNothing); // ro'yxat orqada
    expect(find.byType(BackButton), findsOneWidget);
  });

  testWidgets("to'r: telefonda 2, iPad'da 4 ustun", (tester) async {
    Widget grid() => MaterialApp(
          home: Scaffold(
            body: ListView(padding: const EdgeInsets.all(16), children: <Widget>[
              AdaptiveGrid(minTile: 170, children: <Widget>[for (var i = 0; i < 4; i++) Card(key: ValueKey<int>(i), child: Text('K$i'))]),
            ]),
          ),
        );
    await setView(tester, const Size(430, 932));
    await tester.pumpWidget(grid());
    expect(tester.getTopLeft(find.byKey(const ValueKey<int>(2))).dy, greaterThan(tester.getTopLeft(find.byKey(const ValueKey<int>(1))).dy));
    await setView(tester, const Size(1024, 1366));
    await tester.pumpWidget(grid());
    await tester.pump();
    expect(tester.getTopLeft(find.byKey(const ValueKey<int>(3))).dy, tester.getTopLeft(find.byKey(const ValueKey<int>(0))).dy);
  });
}
