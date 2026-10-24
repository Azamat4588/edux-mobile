// Harakat (3.8, veb 1.40 «Harakat qoidalari»): har harakat foydalanuvchi harakatiga javob yoki nima o'zgarganini ko'rsatadi.
// Daraja: To'liq — hammasi; Kam — faqat so'nish (siljish, sanash va grafik o'sishi yo'q); O'chiq — hech narsa.
// Qurilmada «harakatni kamaytirish» (MediaQuery.disableAnimations) yoqilgan bo'lsa — O'chiq kabi.
//
// Bu yerda: [Motion] (daraja, davomiylik, «seansda bir marta»), [IntroScope]/[IntroItem] — bosh sahifadagi yagona
// orkestrlangan yuklanish (≤ 600 ms), [CountUpText] — raqam sanab o'tishi, [Pressable] — bosilganda .97 kichrayish,
// [Sparkline] — mini-grafik (bir marta chapdan o'ngga ochiladi).
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'design.dart';
import 'theme.dart';

class Motion {
  Motion._();

  /// Joriy daraja: foydalanuvchi tanlovi + qurilma sozlamasi.
  static MotionLevel of(BuildContext context) =>
      motionLevelOf(AppColors.choice.motion, systemReduced: MediaQuery.maybeDisableAnimationsOf(context) ?? false);

  /// To'liq harakat (siljish, sanash, grafik o'sishi).
  static bool rich(BuildContext context) => of(context) == MotionLevel.full;

  /// Harakat umuman bormi.
  static bool any(BuildContext context) => of(context) != MotionLevel.off;

  /// Daraja «O'chiq» bo'lsa — nol.
  static Duration duration(BuildContext context, Duration value) => any(context) ? value : Duration.zero;

  static final Set<String> _played = <String>{};

  /// Seansda bir marta: birinchi chaqiruvda true.
  static bool once(String key) => _played.add(key);

  /// Testlar uchun: «bir marta» belgilarini tozalash.
  @visibleForTesting
  static void resetSession() => _played.clear();
}

// ---------------------------------------------------------------------------
// Bosh sahifadagi yagona yuklanish: hero → kartalar → ro'yxatlar, jami ≤ 600 ms, seansda bir marta.
// ---------------------------------------------------------------------------

class IntroScope extends StatefulWidget {
  const IntroScope({super.key, required this.id, required this.child});

  /// Seans kaliti (masalan, `home-teacher`): shu sahifa ikkinchi marta ochilganda harakat takrorlanmaydi.
  final String id;
  final Widget child;

  /// Umumiy davomiylik.
  static const Duration total = Duration(milliseconds: 600);

  @override
  State<IntroScope> createState() => _IntroScopeState();
}

class _IntroScopeState extends State<IntroScope> with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  MotionLevel _level = MotionLevel.full;
  bool _decided = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_decided) return;
    _decided = true;
    _level = Motion.of(context);
    if (_level != MotionLevel.off && Motion.once('intro:${widget.id}')) {
      _controller = AnimationController(vsync: this, duration: IntroScope.total)..forward();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _IntroData(animation: _controller, level: _level, child: widget.child);
}

class _IntroData extends InheritedWidget {
  const _IntroData({required this.animation, required this.level, required super.child});

  final Animation<double>? animation;
  final MotionLevel level;

  @override
  bool updateShouldNotify(_IntroData oldWidget) => oldWidget.animation != animation || oldWidget.level != level;
}

/// Yuklanish ketma-ketligidagi bo'lak: [index] — tartib (0 — hero). [shiftOnly] — faqat siljiydi (hero: shaffoflik 0 dan
/// boshlanmaydi, birinchi ko'rinish kechikmaydi).
class IntroItem extends StatelessWidget {
  const IntroItem({super.key, required this.index, required this.child, this.shiftOnly = false});

  final int index;
  final bool shiftOnly;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final data = context.dependOnInheritedWidgetOfExactType<_IntroData>();
    final animation = data?.animation;
    if (data == null || animation == null) return child;
    final start = math.min(index * 0.14, 0.56);
    final curve = CurvedAnimation(parent: animation, curve: Interval(start, math.min(start + 0.44, 1.0), curve: Curves.easeOutCubic));
    final shift = data.level == MotionLevel.full ? 6.0 : 0.0;
    return AnimatedBuilder(
      animation: curve,
      child: child,
      builder: (context, child) {
        final t = curve.value;
        Widget result = Transform.translate(offset: Offset(0, (1 - t) * shift * (shiftOnly ? 1.4 : 1)), child: child);
        if (!shiftOnly) result = Opacity(opacity: t, child: result);
        return result;
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Raqam sanab o'tishi: 0 dan, faqat birinchi ochilishda (vaqt va sana sanalmaydi).
// ---------------------------------------------------------------------------

/// Matndagi birinchi sonni ajratadi: «1 200 000 so'm» → (oldi, 1200000, keyingi, ajratgich). Vaqt (16:00), kasr,
/// nisbat (8/12) va sana — null.
({String before, int value, String after, String separator})? splitCountable(String text) {
  if (text.contains(':') || text.contains('/') || RegExp(r'\d[.,]\d').hasMatch(text)) return null;
  final match = RegExp(r'^(\D*?)(\d{1,3}(?:[   ]\d{3})+|\d+)(\D*)$').firstMatch(text);
  if (match == null) return null;
  final digits = match.group(2)!;
  final separator = RegExp(r'[   ]').firstMatch(digits)?.group(0) ?? '';
  final value = int.tryParse(digits.replaceAll(RegExp(r'\D'), ''));
  if (value == null) return null;
  return (before: match.group(1)!, value: value, after: match.group(3)!, separator: separator);
}

/// Butun sonni guruhlab yozadi (ajratgich bo'sh bo'lsa — guruhsiz).
String groupDigitsWith(int value, String separator) {
  final text = '$value';
  if (separator.isEmpty || text.length <= 3) return text;
  final buffer = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    if (i > 0 && (text.length - i) % 3 == 0) buffer.write(separator);
    buffer.write(text[i]);
  }
  return buffer.toString();
}

class CountUpText extends StatefulWidget {
  const CountUpText(this.text, {super.key, required this.countKey, this.style, this.maxLines, this.overflow});

  final String text;

  /// Seans kaliti: bir raqam (masalan, «qarzdorlar») seansda bir marta sanaladi.
  final String countKey;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  static const Duration duration = Duration(milliseconds: 700);

  @override
  State<CountUpText> createState() => _CountUpTextState();
}

class _CountUpTextState extends State<CountUpText> {
  bool? _animate;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _animate ??= Motion.rich(context) && splitCountable(widget.text) != null && Motion.once('count:${widget.countKey}');
  }

  @override
  Widget build(BuildContext context) {
    final parts = splitCountable(widget.text);
    if (_animate != true || parts == null || parts.value == 0) {
      return Text(widget.text, style: widget.style, maxLines: widget.maxLines, overflow: widget.overflow);
    }
    return Semantics(
      label: widget.text,
      excludeSemantics: true,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: parts.value.toDouble()),
        duration: CountUpText.duration,
        curve: Curves.easeOutCubic,
        builder: (context, value, _) => Text(
          '${parts.before}${groupDigitsWith(value.round(), parts.separator)}${parts.after}',
          style: widget.style,
          maxLines: widget.maxLines,
          overflow: widget.overflow,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bosilish: .97 ga kichrayadi (veb: --press-scale), 120 ms.
// ---------------------------------------------------------------------------

class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.enabled = true});

  final Widget child;
  final bool enabled;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool value) {
    if (_down != value && mounted) setState(() => _down = value);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || !Motion.any(context)) return widget.child;
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(scale: _down ? 0.97 : 1, duration: AppDurations.d1, curve: Curves.easeOut, child: widget.child),
    );
  }
}

// ---------------------------------------------------------------------------
// Mini-grafik (veb: Home/Sparkline.vue): chiziq, ostida yumshoq maydon, oxirgi nuqta.
// ---------------------------------------------------------------------------

class Sparkline extends StatefulWidget {
  const Sparkline({super.key, required this.values, this.color, this.height = 30, this.label = '', this.animationKey});

  final List<num> values;
  final Color? color;
  final double height;
  final String label;

  /// Seans kaliti: grafik bir marta chapdan o'ngga ochiladi.
  final String? animationKey;

  @override
  State<Sparkline> createState() => _SparklineState();
}

class _SparklineState extends State<Sparkline> with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final key = widget.animationKey;
    final play = key != null && Motion.rich(context) && Motion.once('spark:$key');
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 620), value: play ? 0 : 1);
    if (play) _controller!.animateTo(1, curve: Curves.easeOutCubic);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? AppColors.accent;
    return Semantics(
      label: widget.label,
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: AnimatedBuilder(
          animation: _controller!,
          builder: (context, _) => CustomPaint(painter: SparklinePainter(values: widget.values, color: color, progress: _controller!.value)),
        ),
      ),
    );
  }
}

class SparklinePainter extends CustomPainter {
  SparklinePainter({required this.values, required this.color, this.progress = 1});

  final List<num> values;
  final Color color;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2 || size.width <= 0) return;
    final list = values.map((value) => value.toDouble()).toList();
    final max = math.max(list.reduce(math.max), 1.0);
    final min = math.min(list.reduce(math.min), 0.0);
    final span = (max - min) == 0 ? 1.0 : max - min;
    final step = size.width / (list.length - 1);
    final points = <Offset>[
      for (var i = 0; i < list.length; i++) Offset(i * step, size.height - 3 - ((list[i] - min) / span) * (size.height - 6)),
    ];
    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      line.lineTo(point.dx, point.dy);
    }
    final area = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(-4, -4, (size.width + 8) * progress, size.height + 8));
    canvas.drawPath(area, Paint()..color = color.withAlpha(30));
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    if (progress >= 1) canvas.drawCircle(points.last, 3, Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(SparklinePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color || oldDelegate.values != values;
}

// ---------------------------------------------------------------------------
// Ro'yxat (veb: TransitionGroup «list»): yangi element chapdan siljib paydo bo'ladi, o'chgani so'nib yig'iladi.
// Ma'lumot ro'yxati o'zgarganda kalitlar bo'yicha farq topiladi — AnimatedList shu farqni o'ynaydi.
// ---------------------------------------------------------------------------

class DiffAnimatedList<T> extends StatefulWidget {
  const DiffAnimatedList({
    super.key,
    required this.items,
    required this.keyOf,
    required this.itemBuilder,
    this.padding,
    this.physics,
    this.skipRemoval,
  });

  final List<T> items;
  final String Function(T item) keyOf;
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  final EdgeInsetsGeometry? padding;
  final ScrollPhysics? physics;

  /// O'chirish harakati kerak emas (masalan, surib o'chirilgan — Dismissible o'zi yig'ib bo'lgan).
  final bool Function(T item)? skipRemoval;

  @override
  State<DiffAnimatedList<T>> createState() => _DiffAnimatedListState<T>();
}

class _DiffAnimatedListState<T> extends State<DiffAnimatedList<T>> {
  final GlobalKey<AnimatedListState> _list = GlobalKey<AnimatedListState>();
  late List<T> _items = List<T>.of(widget.items);

  @override
  void didUpdateWidget(DiffAnimatedList<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final state = _list.currentState;
    final next = widget.items;
    if (state == null) {
      _items = List<T>.of(next);
      return;
    }
    final level = Motion.of(context);
    final nextKeys = next.map(widget.keyOf).toSet();
    // O'chirilganlar — oxiridan boshiga (indekslar siljimasin).
    for (var i = _items.length - 1; i >= 0; i--) {
      final old = _items[i];
      if (nextKeys.contains(widget.keyOf(old))) continue;
      _items.removeAt(i);
      final skip = level == MotionLevel.off || (widget.skipRemoval?.call(old) ?? false);
      state.removeItem(
        i,
        (context, animation) => skip
            ? const SizedBox.shrink()
            : FadeTransition(
                opacity: animation,
                child: SizeTransition(sizeFactor: CurvedAnimation(parent: animation, curve: Curves.easeInOutCubic), child: widget.itemBuilder(context, old, i)),
              ),
        duration: skip ? Duration.zero : AppDurations.d3,
      );
    }
    // Yangilari — yangi ro'yxatdagi o'rniga.
    final oldKeys = _items.map(widget.keyOf).toSet();
    for (var i = 0; i < next.length; i++) {
      if (oldKeys.contains(widget.keyOf(next[i]))) continue;
      _items.insert(i.clamp(0, _items.length), next[i]);
      state.insertItem(i.clamp(0, _items.length - 1), duration: level == MotionLevel.off ? Duration.zero : AppDurations.d2);
    }
    _items = List<T>.of(next);
  }

  @override
  Widget build(BuildContext context) {
    final rich = Motion.rich(context);
    return AnimatedList(
      key: _list,
      padding: widget.padding,
      physics: widget.physics,
      initialItemCount: _items.length,
      itemBuilder: (context, index, animation) {
        if (index >= _items.length) return const SizedBox.shrink();
        final child = widget.itemBuilder(context, _items[index], index);
        final fade = FadeTransition(opacity: animation, child: child);
        if (!rich) return fade;
        return SlideTransition(
          position: Tween<Offset>(begin: const Offset(-0.03, 0), end: Offset.zero).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
          child: fade,
        );
      },
    );
  }
}
