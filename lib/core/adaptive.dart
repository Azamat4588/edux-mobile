// iPad va keng ekranlar (3.7): yon menyu (NavigationRail), ro'yxat + tafsilot (ikki ustun), o'qish kengligi va moslashuvchan
// to'r. Keng ekran — oynaning eng qisqa tomoni ≥ 600 (iPad, Split View'da katta oyna, planshet); telefon va Slide Over —
// oddiy (pastki menyu, bitta ustun). Toza mantiq va vidjetlar — test/adaptive_test.dart.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'illustrations.dart';
import 'motion.dart';
import 'theme.dart';
import 'widgets.dart';

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
            child: _DetailScope(state: null, owner: this, selected: null, child: SectionScope.none(child: ReadableArea(child: detail))),
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
            const EmptyIllustration(EmptyArt.notebook, width: 120),
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
  const AdaptiveDestination({required this.icon, required this.label, this.badge = 0, this.color});

  final IconData icon;
  final String label;

  /// Bo'lim rangi (rangli menyu ikonalari, Maktab/Bahor faol bandi).
  final Color? color;

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

Widget _badged(Widget icon, int badge) {
  if (badge <= 0) return icon;
  return Badge(
    label: Text(badge > 99 ? '99+' : '$badge'),
    backgroundColor: AppColors.dangerFill,
    textColor: Colors.white,
    child: icon,
  );
}

/// Pastki menyu (telefon, veb 1.41 bottom-nav): sarlavha paneli rangida, faol bandning belgisi to'liq asosiy rangli
/// tabletka ichida (oq belgi), yorlig'i asosiy rangda; bosilganda belgi .9 ga kichrayib prujina bilan qaytadi.
/// «Suzuvchi» menyuda (Yumshoq shablon) — chetlardan ajralgan, yumaloq panel.
class AppNavBar extends StatelessWidget {
  const AppNavBar({super.key, required this.destinations, required this.selected, required this.onSelect});

  final List<AdaptiveDestination> destinations;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final floating = AppColors.choice.floatingNav;
    final dense = AppColors.choice.dense;
    final height = dense ? 58.0 : 64.0;
    final row = SizedBox(
      height: height,
      child: Row(children: <Widget>[
        for (var i = 0; i < destinations.length; i++)
          Expanded(child: _NavBarItem(item: destinations[i], active: i == selected, onTap: () => onSelect(i))),
      ]),
    );
    if (!floating) {
      return Material(
        color: AppColors.chrome,
        child: DecoratedBox(
          decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
          child: SafeArea(top: false, child: row),
        ),
      );
    }
    final radius = BorderRadius.circular((AppRadius.card + 8).clamp(10, 30).toDouble());
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
        child: DecoratedBox(
          decoration: BoxDecoration(borderRadius: radius, boxShadow: AppColors.shadow3),
          child: Material(
            color: AppColors.chrome,
            shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: AppColors.line)),
            clipBehavior: Clip.antiAlias,
            child: row,
          ),
        ),
      ),
    );
  }
}

class _NavBarItem extends StatefulWidget {
  const _NavBarItem({required this.item, required this.active, required this.onTap});

  final AdaptiveDestination item;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_NavBarItem> createState() => _NavBarItemState();
}

class _NavBarItemState extends State<_NavBarItem> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final active = widget.active;
    final duration = Motion.duration(context, AppDurations.d2);
    final rich = Motion.rich(context);
    final fg = active ? AppColors.onBrand : AppColors.subtle;
    return Semantics(
      selected: active,
      button: true,
      label: item.badge > 0 ? '${item.label}, ${item.badge}' : item.label,
      excludeSemantics: true,
      child: InkResponse(
        onTap: widget.onTap,
        onHighlightChanged: (value) => setState(() => _down = value),
        containedInkWell: true,
        highlightShape: BoxShape.rectangle,
        highlightColor: Colors.transparent,
        splashColor: AppColors.accent.withAlpha(20),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            AnimatedScale(
              scale: _down && rich ? 0.9 : 1,
              duration: _down ? AppDurations.d1 : AppDurations.d2,
              curve: _down ? Curves.easeOut : AppCurves.spring,
              child: AnimatedContainer(
                duration: duration,
                curve: AppCurves.out,
                width: 54,
                height: 30,
                decoration: BoxDecoration(color: active ? AppColors.accent : Colors.transparent, borderRadius: BorderRadius.circular(99)),
                child: Center(child: _badged(Icon(item.icon, size: 21, color: fg), item.badge)),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, fontWeight: active ? FontWeight.w700 : FontWeight.w600, color: active ? AppColors.accentStrong : AppColors.subtle),
            ),
          ]),
        ),
      ),
    );
  }
}

/// iPad yon menyusi (veb 1.41 sidebar): tepada tashkilot bloki, faol band — to'liq rangli tabletka (Atlas — shafran,
/// Maktab/Bahor — bo'lim rangining och tusi); rangli ikonalar har bo'lim o'z rangida.
class AppRail extends StatelessWidget {
  const AppRail({super.key, required this.destinations, required this.selected, required this.onSelect, required this.extended, this.header});

  final List<AdaptiveDestination> destinations;
  final int selected;
  final ValueChanged<int> onSelect;
  final bool extended;

  /// Tepadagi blok (tashkilot belgisi va nomi); bo'lmasa — EduX belgisi.
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final width = extended ? 248.0 : 92.0;
    return Material(
      color: AppColors.navBg,
      child: SafeArea(
        right: false,
        child: SizedBox(
          width: width,
          child: ListView(padding: const EdgeInsets.only(top: 12, bottom: 16), children: <Widget>[
            Padding(
              padding: EdgeInsets.fromLTRB(extended ? 12 : 0, 0, extended ? 12 : 0, 16),
              child: header ?? Center(child: Image.asset('assets/brand/mark.png', width: 36, height: 36, semanticLabel: 'EduX')),
            ),
            for (var i = 0; i < destinations.length; i++)
              _RailItem(item: destinations[i], active: i == selected, extended: extended, onTap: () => onSelect(i)),
          ]),
        ),
      ),
    );
  }
}

/// Faol band ranglari: [fon, matn].
(Color, Color) railActiveColors(AdaptiveDestination item) {
  final section = item.color;
  if (AppColors.choice.sectionTinted && section != null) {
    return (AppTheme.sectionActive(section), AppColors.dark ? Colors.white : AppColors.ink);
  }
  return (AppColors.navActiveBg, AppColors.navActiveFg);
}

/// Faol bo'lmagan band belgisi: rangli ikonalarda bo'lim rangi (to'q menyuda — och tusi), aks holda menyu matni.
Color railIconColor(AdaptiveDestination item) {
  final section = item.color;
  if (!AppColors.choice.coloredIcons || section == null) return AppColors.navFg;
  if (AppColors.navDark) return Color.lerp(section, Colors.white, 0.45)!;
  return readableOn(section, AppColors.navBg, min: 3);
}

class _RailItem extends StatelessWidget {
  const _RailItem({required this.item, required this.active, required this.extended, required this.onTap});

  final AdaptiveDestination item;
  final bool active;
  final bool extended;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final duration = Motion.duration(context, AppDurations.d2);
    final (activeBg, activeFg) = railActiveColors(item);
    final fg = active ? activeFg : AppColors.navFg;
    final radius = BorderRadius.circular(AppColors.choice.template == 'spring' || AppColors.choice.template == 'soft' ? 99 : AppRadius.control);
    final icon = _badged(Icon(item.icon, size: 22, color: active ? activeFg : railIconColor(item)), item.badge);
    final label = Text(
      item.label,
      maxLines: extended ? 1 : 2,
      overflow: TextOverflow.ellipsis,
      textAlign: extended ? TextAlign.start : TextAlign.center,
      style: TextStyle(
        fontSize: extended ? 14.5 : 11.5,
        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
        color: extended ? fg : (active ? (AppColors.navDark ? Colors.white : AppColors.ink) : AppColors.navFg),
      ),
    );
    return Semantics(
      selected: active,
      button: true,
      label: item.label,
      excludeSemantics: true,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: extended ? 12 : 10, vertical: 2),
        child: Pressable(
          scale: 0.97,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: extended
                ? AnimatedContainer(
                    duration: duration,
                    curve: AppCurves.out,
                    height: 46,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(color: active ? activeBg : Colors.transparent, borderRadius: radius),
                    child: Row(children: <Widget>[icon, const SizedBox(width: 14), Expanded(child: label)]),
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                      AnimatedContainer(
                        duration: duration,
                        curve: AppCurves.out,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        decoration: BoxDecoration(color: active ? activeBg : Colors.transparent, borderRadius: BorderRadius.circular(99)),
                        child: icon,
                      ),
                      const SizedBox(height: 4),
                      label,
                    ]),
                  ),
          ),
        ),
      ),
    );
  }
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
    this.railHeader,
  });

  final List<AdaptiveDestination> destinations;
  final int selected;
  final ValueChanged<int> onSelect;
  final Widget body;

  /// Kontent ustidagi banner (masalan, obuna tugagani haqida).
  final Widget? top;

  /// Majburiy rejim (skrinshot va testlar uchun); null — ekran o'lchamidan.
  final bool? wide;

  /// Yon menyu tepasidagi blok (tashkilot).
  final Widget? railHeader;

  @override
  Widget build(BuildContext context) {
    final isWide = wide ?? isWideScreen(context);
    final count = destinations.length;
    final index = count == 0 ? 0 : (selected < 0 ? 0 : (selected >= count ? count - 1 : selected));
    final content = top == null ? body : Column(children: <Widget>[top!, Expanded(child: body)]);
    if (!isWide || count < 2) {
      return Scaffold(
        body: content,
        bottomNavigationBar: count < 2 ? null : AppNavBar(destinations: destinations, selected: index, onSelect: onSelect),
      );
    }
    final extended = railExtended(MediaQuery.sizeOf(context).width);
    return CallbackShortcuts(
      bindings: navShortcuts(count, onSelect),
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
            AppRail(destinations: destinations, selected: index, onSelect: onSelect, extended: extended, header: railHeader),
            VerticalDivider(width: 1, thickness: 1, color: AppColors.navLine),
            Expanded(child: ReadableArea(child: content)),
          ]),
        ),
      ),
    );
  }
}
