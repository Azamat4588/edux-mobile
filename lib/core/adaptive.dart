// iPad va keng ekranlar (3.7): yon menyu (NavigationRail), ro'yxat + tafsilot (ikki ustun), o'qish kengligi va moslashuvchan
// to'r. Keng ekran — oynaning eng qisqa tomoni ≥ 600 (iPad, Split View'da katta oyna, planshet); telefon va Slide Over —
// oddiy (pastki menyu, bitta ustun). Toza mantiq va vidjetlar — test/adaptive_test.dart.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// Keng ekran chegarasi (oynaning eng qisqa tomoni).
const double kWideShortestSide = 600;

/// Ikki ustun (ro'yxat + tafsilot) uchun kerakli kenglik.
const double kTwoPaneWidth = 720;

/// O'qish uchun kontent kengligi (matn, formalar, kartalar ro'yxati).
const double kReadableWidth = 840;

/// Katalog va bosh sahifa to'rlari uchun kengroq chegara.
const double kGridWidth = 1180;

bool isWideSize(Size size) => size.shortestSide >= kWideShortestSide;

bool isWideScreen(BuildContext context) => isWideSize(MediaQuery.sizeOf(context));

/// Menyuda nechta bo'lim (qolgani «Yana» da): telefon — 4, keng ekran — 6.
int navLimit(bool wide) => wide ? 6 : 4;

/// Yon menyu yorliqlari ikonka yonida (kengaytirilgan) — keng oynada.
bool railExtended(double width) => width >= 1180;

/// Ikki ustunli rejimda ro'yxat ustuni kengligi.
double masterPaneWidth(double width) => width >= 1100 ? 400 : 340;

/// Ikki ustunli rejim yoqiladimi: keng ekran va joy yetarli.
bool useTwoPane({required bool wide, required double width}) => wide && width >= kTwoPaneWidth;

/// O'qish kengligidan oshgan joy ikki chetga teng bo'linadi (kontent o'rtada qoladi, aylantirish butun kenglikda).
EdgeInsets readableInsets(double width, EdgeInsets base, {double max = kReadableWidth}) {
  final content = width - base.left - base.right;
  if (!width.isFinite || content <= max) return base;
  final extra = (content - max) / 2;
  return base.copyWith(left: base.left + extra, right: base.right + extra);
}

/// Shu joyning haqiqiy kengligi (yon menyu va ustunlarsiz) — [readable] uchun.
class ReadableArea extends StatelessWidget {
  const ReadableArea({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) => _ReadableScope(width: box.maxWidth, child: child));
  }
}

class _ReadableScope extends InheritedWidget {
  const _ReadableScope({required this.width, required super.child});

  final double width;

  @override
  bool updateShouldNotify(_ReadableScope oldWidget) => oldWidget.width != width;
}

/// Ro'yxat ichki chegarasi: telefonda — [base] o'zi, keng ekranda kontent o'rtada, [max] kenglikda.
EdgeInsets readable(BuildContext context, EdgeInsets base, {double max = kReadableWidth}) {
  final scope = context.dependOnInheritedWidgetOfExactType<_ReadableScope>();
  final width = scope?.width ?? MediaQuery.sizeOf(context).width;
  return readableInsets(width, base, max: max);
}

/// Ro'yxat bo'lmagan sahifa (forma, maqola) uchun: kontent o'rtada, ko'pi bilan [max] kenglikda.
class ReadableBox extends StatelessWidget {
  const ReadableBox({super.key, required this.child, this.max = kReadableWidth});

  final Widget child;
  final double max;

  @override
  Widget build(BuildContext context) {
    return Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: BoxConstraints(maxWidth: max), child: child));
  }
}

/// To'r ustunlari soni: [minTile] kenglikdagi kartalar sig'gancha, [minColumns]…[maxColumns] oralig'ida.
int gridColumns(double width, {double minTile = 220, int minColumns = 2, int maxColumns = 4, double spacing = 10}) {
  if (!width.isFinite || width <= 0) return minColumns;
  final fit = ((width + spacing) / (minTile + spacing)).floor();
  if (fit < minColumns) return minColumns;
  if (fit > maxColumns) return maxColumns;
  return fit;
}

/// Kartalar to'ri: telefonda 2 (yoki [minColumns]) ustun, keng ekranda ko'proq; qatordagi kartalar bir xil balandlikda.
class AdaptiveGrid extends StatelessWidget {
  const AdaptiveGrid({
    super.key,
    required this.children,
    this.minTile = 220,
    this.minColumns = 2,
    this.maxColumns = 4,
    this.spacing = 10,
  });

  final List<Widget> children;
  final double minTile;
  final int minColumns;
  final int maxColumns;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final columns = gridColumns(box.maxWidth, minTile: minTile, minColumns: minColumns, maxColumns: maxColumns, spacing: spacing);
      final rows = <Widget>[];
      for (var start = 0; start < children.length; start += columns) {
        final cells = <Widget>[];
        for (var column = 0; column < columns; column++) {
          if (column > 0) cells.add(SizedBox(width: spacing));
          final index = start + column;
          cells.add(Expanded(child: index < children.length ? children[index] : const SizedBox()));
        }
        rows.add(Padding(
          padding: EdgeInsets.only(bottom: spacing),
          child: IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: cells)),
        ));
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
    });
  }
}

// ---------------------------------------------------------------------------
// Ro'yxat + tafsilot (master/detail)
// ---------------------------------------------------------------------------

/// Ikki ustunli sahifa: chapda ro'yxat ([master]), o'ngda tanlangan yozuv. Telefonda (va tor oynada) — faqat ro'yxat,
/// yozuv [openDetail] bilan yangi sahifada ochiladi. Ro'yxat holati (qidiruv, aylantirish) burilishda saqlanadi.
class MasterDetail extends StatefulWidget {
  const MasterDetail({super.key, required this.master, this.placeholder, this.hint});

  final Widget master;

  /// Hech narsa tanlanmaganda o'ng ustun (bo'lmasa — [DetailPlaceholder] va [hint]).
  final Widget? placeholder;
  final String? hint;

  @override
  State<MasterDetail> createState() => MasterDetailState();
}

class MasterDetailState extends State<MasterDetail> {
  final GlobalKey _masterKey = GlobalKey(debugLabel: 'master');
  Object? _id;
  WidgetBuilder? _builder;

  /// O'ng ustundagi sahifaning saqlanmagan o'zgarishlari: boshqa yozuv tanlanishidan oldin so'raladi (false — qoladi).
  Future<bool> Function()? guard;

  /// Tanlangan yozuv (ro'yxatda belgilash uchun).
  Object? get selected => _id;

  Future<void> show(Object id, WidgetBuilder builder) async {
    if (_id == id) return;
    final check = guard;
    if (check != null && !await check()) return;
    if (!mounted) return;
    setState(() {
      guard = null;
      _id = id;
      _builder = builder;
    });
  }

  void clear() {
    if (!mounted) return;
    setState(() {
      guard = null;
      _id = null;
      _builder = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final wide = isWideScreen(context);
    return LayoutBuilder(builder: (context, box) {
      final master = KeyedSubtree(key: _masterKey, child: widget.master);
      if (!useTwoPane(wide: wide, width: box.maxWidth)) {
        return _DetailScope(state: null, owner: null, selected: null, child: master);
      }
      final builder = _builder;
      final id = _id;
      final detail = builder == null || id == null
          ? (widget.placeholder ?? DetailPlaceholder(text: widget.hint))
          : KeyedSubtree(key: ValueKey<Object>(id), child: Builder(builder: builder));
      return _DetailScope(
        state: this,
        owner: null,
        selected: id,
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          SizedBox(width: masterPaneWidth(box.maxWidth), child: ReadableArea(child: master)),
          VerticalDivider(width: 1, thickness: 1, color: AppColors.line),
          Expanded(
            child: _DetailScope(state: null, owner: this, selected: null, child: ReadableArea(child: detail)),
          ),
        ]),
      );
    });
  }
}

class _DetailScope extends InheritedWidget {
  const _DetailScope({required this.state, required this.owner, required this.selected, required super.child});

  /// Ro'yxat ustunida: yozuv shu holatga ochiladi (null — yangi sahifa).
  final MasterDetailState? state;

  /// O'ng ustunda: ikki ustunli sahifa holati.
  final MasterDetailState? owner;
  final Object? selected;

  @override
  bool updateShouldNotify(_DetailScope oldWidget) =>
      oldWidget.state != state || oldWidget.owner != owner || oldWidget.selected != selected;
}

/// Yozuvni ochish: ikki ustunli rejimda — o'ng ustunda, aks holda yangi sahifada (sahifa yopilguncha kutadi).
Future<void> openDetail(BuildContext context, {required Object id, required WidgetBuilder builder}) async {
  final state = context.getInheritedWidgetOfExactType<_DetailScope>()?.state;
  if (state != null && state.mounted) {
    await state.show(id, builder);
    return;
  }
  await Navigator.of(context).push(MaterialPageRoute<void>(builder: builder));
}

/// Yozuv o'ng ustunda ochiqmi (ro'yxatda belgilash).
bool isDetailSelected(BuildContext context, Object id) => context.dependOnInheritedWidgetOfExactType<_DetailScope>()?.selected == id;

/// Sahifa ikki ustunli rejimning o'ng ustunida (orqaga tugmasi va `pop` kerak emas).
bool isEmbeddedDetail(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_DetailScope>()?.owner != null;

/// O'ng ustundagi sahifa egasi (saqlanmagan o'zgarishlar himoyasi uchun: `owner.guard = ...`).
MasterDetailState? detailOwner(BuildContext context) => context.getInheritedWidgetOfExactType<_DetailScope>()?.owner;

/// Hech narsa tanlanmagan o'ng ustun.
class DetailPlaceholder extends StatelessWidget {
  const DetailPlaceholder({super.key, this.text, this.icon = Icons.touch_app_outlined});

  final String? text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.surface,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            Icon(icon, size: 48, color: AppColors.muted.withAlpha(150)),
            if (text != null && text!.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              Text(text!, textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 15)),
            ],
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Asosiy menyu: telefonda pastki, keng ekranda yon (NavigationRail)
// ---------------------------------------------------------------------------

class AdaptiveDestination {
  const AdaptiveDestination({required this.icon, required this.label, this.badge = 0});

  final IconData icon;
  final String label;

  /// Yangi yozuvlar soni (masalan, «Yangi» fikrlar) — 0 bo'lsa ko'rinmaydi.
  final int badge;
}

const List<LogicalKeyboardKey> _digitKeys = <LogicalKeyboardKey>[
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
  LogicalKeyboardKey.digit6,
  LogicalKeyboardKey.digit7,
  LogicalKeyboardKey.digit8,
  LogicalKeyboardKey.digit9,
];

/// Klaviatura (iPad Magic Keyboard, planshet): ⌘1…⌘9 (yoki Ctrl) — menyu bandlari.
Map<ShortcutActivator, VoidCallback> navShortcuts(int count, ValueChanged<int> onSelect) {
  final result = <ShortcutActivator, VoidCallback>{};
  for (var i = 0; i < count && i < _digitKeys.length; i++) {
    result[SingleActivator(_digitKeys[i], meta: true)] = () => onSelect(i);
    result[SingleActivator(_digitKeys[i], control: true)] = () => onSelect(i);
  }
  return result;
}

Widget _destinationIcon(AdaptiveDestination item) {
  final icon = Icon(item.icon);
  if (item.badge <= 0) return icon;
  return Badge(label: Text(item.badge > 99 ? '99+' : '${item.badge}'), child: icon);
}

/// Asosiy oyna karkasi: telefonda pastki menyu, keng ekranda chapda yon menyu (kengaytirilgan — katta oynada).
class AdaptiveNavScaffold extends StatelessWidget {
  const AdaptiveNavScaffold({
    super.key,
    required this.destinations,
    required this.selected,
    required this.onSelect,
    required this.body,
    this.top,
    this.wide,
  });

  final List<AdaptiveDestination> destinations;
  final int selected;
  final ValueChanged<int> onSelect;
  final Widget body;

  /// Kontent ustidagi banner (masalan, obuna tugagani haqida).
  final Widget? top;

  /// Majburiy rejim (skrinshot va testlar uchun); null — ekran o'lchamidan.
  final bool? wide;

  @override
  Widget build(BuildContext context) {
    final isWide = wide ?? isWideScreen(context);
    final count = destinations.length;
    final index = count == 0 ? 0 : (selected < 0 ? 0 : (selected >= count ? count - 1 : selected));
    final content = top == null ? body : Column(children: <Widget>[top!, Expanded(child: body)]);
    if (!isWide || count < 2) {
      return Scaffold(
        body: content,
        bottomNavigationBar: count < 2
            ? null
            : NavigationBar(
                selectedIndex: index,
                onDestinationSelected: onSelect,
                destinations: <NavigationDestination>[
                  for (final item in destinations) NavigationDestination(icon: _destinationIcon(item), label: item.label),
                ],
              ),
      );
    }
    final extended = railExtended(MediaQuery.sizeOf(context).width);
    final rail = NavigationRail(
      selectedIndex: index,
      onDestinationSelected: onSelect,
      extended: extended,
      minExtendedWidth: 232,
      labelType: extended ? NavigationRailLabelType.none : NavigationRailLabelType.all,
      backgroundColor: AppColors.card,
      groupAlignment: -1,
      leading: Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: Image.asset('assets/brand/mark.png', width: 36, height: 36, semanticLabel: 'EduX'),
      ),
      destinations: <NavigationRailDestination>[
        for (final item in destinations)
          NavigationRailDestination(icon: _destinationIcon(item), label: Text(item.label, maxLines: 2, overflow: TextOverflow.ellipsis)),
      ],
    );
    return CallbackShortcuts(
      bindings: navShortcuts(count, onSelect),
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
            Material(color: AppColors.card, child: SafeArea(right: false, child: rail)),
            VerticalDivider(width: 1, thickness: 1, color: AppColors.line),
            Expanded(child: ReadableArea(child: content)),
          ]),
        ),
      ),
    );
  }
}
