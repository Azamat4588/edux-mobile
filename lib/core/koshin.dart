// Dizayn v3 «Koshin» (veb 1.41) ning yagona dadil elementi — girih yulduzi va koshin plitkalar:
// - [GirihStar] — sakkiz qirrali yulduz (ikki aylangan kvadrat): to'liq (muhr, bo'sh holat foni) yoki chiziqli (plitka burchagi);
// - [GirihPatternPainter] — kirish paneli va splash naqshi (oq, 6%);
// - [KoshinTile] — «Bugun» ko'rsatkichi: to'liq rangli plitka, burchakda girih, katta raqam (Commissioner), oddiy jumla;
// - [SuccessStamp] — «bajarildi» muhri (to'lov qabul qilindi, saqlandi).
// Geometriya veb bilan bir xil (viewBox 100: kvadrat 17..83, rx 9; chiziqli — 19..81, rx 4, doira r15 va r5).
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'design.dart';
import 'motion.dart';
import 'theme.dart';

/// Girih yulduzi yo'li (0..1 birlikda, [size] ga ko'paytiriladi).
Path girihPath(Size size, {bool line = false}) {
  final scale = size.shortestSide / 100;
  final inset = line ? 19.0 : 17.0;
  final side = 100 - inset * 2;
  final radius = Radius.circular((line ? 4 : 9) * scale);
  final rect = RRect.fromRectAndRadius(Rect.fromLTWH(inset * scale, inset * scale, side * scale, side * scale), radius);
  // 45° burilish markaz atrofida (ustunlar bo'yicha 4×4 matritsa).
  final c = 50 * scale;
  final cos = math.cos(math.pi / 4);
  final sin = math.sin(math.pi / 4);
  final rotation = Float64List.fromList(<double>[cos, sin, 0, 0, -sin, cos, 0, 0, 0, 0, 1, 0, c - cos * c + sin * c, c - sin * c - cos * c, 0, 1]);
  final first = Path()..addRRect(rect);
  final second = first.transform(rotation);
  if (line) return first..addPath(second, Offset.zero);
  return Path.combine(PathOperation.union, first, second);
}

class GirihStarPainter extends CustomPainter {
  GirihStarPainter({required this.color, this.line = false, this.stroke = 3});

  final Color color;
  final bool line;

  /// Chiziq qalinligi (viewBox birligida).
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 100;
    if (!line) {
      canvas.drawPath(girihPath(size), Paint()..color = color);
      return;
    }
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke * scale
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(girihPath(size, line: true), paint);
    final center = Offset(50 * scale, 50 * scale);
    canvas.drawCircle(center, 15 * scale, paint);
    canvas.drawCircle(center, 5 * scale, Paint()..color = color);
  }

  @override
  bool shouldRepaint(GirihStarPainter oldDelegate) => oldDelegate.color != color || oldDelegate.line != line || oldDelegate.stroke != stroke;
}

/// Girih yulduzi (bezak — ekran o'quvchidan yashirin).
class GirihStar extends StatelessWidget {
  const GirihStar({super.key, required this.size, required this.color, this.line = false});

  final double size;
  final Color color;
  final bool line;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(child: CustomPaint(size: Size.square(size), painter: GirihStarPainter(color: color, line: line)));
  }
}

/// Takrorlanuvchi chiziqli girih naqshi (veb: .auth-panel::before — 7.5rem qadam, oq 6%).
class GirihPatternPainter extends CustomPainter {
  GirihPatternPainter({this.color = const Color(0x0FFFFFFF), this.step = 120});

  final Color color;
  final double step;

  @override
  void paint(Canvas canvas, Size size) {
    final star = GirihStarPainter(color: color, line: true);
    for (var y = 0.0; y < size.height; y += step) {
      for (var x = 0.0; x < size.width; x += step) {
        canvas.save();
        canvas.translate(x, y);
        star.paint(canvas, Size.square(step));
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(GirihPatternPainter oldDelegate) => oldDelegate.color != color || oldDelegate.step != step;
}

/// Koshin plitka ranglari (shablonga qarab): to'liq rangli yoki och (Ixcham, Grafit).
class KoshinTileColors {
  const KoshinTileColors({required this.background, required this.value, required this.text, required this.hint, required this.chip, required this.girih, this.border});

  final Color background;
  final Color value;
  final Color text;
  final Color hint;

  /// Belgi qutisi va o'zgarish tabletkasi foni.
  final Color chip;
  final Color girih;
  final Color? border;

  /// Veb: .today-card[data-hue] va Ixcham/Grafit uchun och variant (app.css).
  factory KoshinTileColors.of(KoshinHue hue) {
    final tile = Koshin.of(hue);
    if (AppColors.choice.quietTiles) {
      final value = AppColors.dark ? Color.lerp(tile, Colors.white, 0.45)! : Color.lerp(AppColors.ink, tile, 0.8)!;
      return KoshinTileColors(
        background: Color.lerp(AppColors.card, tile, 0.09)!,
        value: readableOn(value, Color.lerp(AppColors.card, tile, 0.09)!),
        text: AppColors.ink,
        hint: AppColors.subtle,
        chip: tile.withAlpha(36),
        girih: tile.withAlpha(46),
        border: Color.lerp(AppColors.cardBorder == Colors.transparent ? AppColors.line : AppColors.cardBorder, tile, 0.26),
      );
    }
    final fg = Koshin.onTile(hue);
    final shafran = hue == KoshinHue.shafran;
    return KoshinTileColors(
      background: tile,
      value: fg,
      text: fg,
      hint: fg.withAlpha(shafran ? 209 : 214),
      chip: shafran ? Koshin.shafranInk.withAlpha(26) : Colors.white.withAlpha(51),
      girih: fg.withAlpha(41),
    );
  }
}

/// «Bugun» koshin plitkasi (veb: TodayCard.vue 1.41). Bosilganda: plitka biroz kichrayadi va girih 22.5° buriladi.
class KoshinTile extends StatefulWidget {
  const KoshinTile({
    super.key,
    required this.hue,
    required this.value,
    required this.text,
    this.hint = '',
    this.icon,
    this.delta,
    this.footer,
    this.onTap,
    this.valueBuilder,
    this.minHeight,
    this.semanticLabel,
  });

  final KoshinHue hue;
  final String value;
  final String text;
  final String hint;
  final IconData? icon;

  /// O'ng yuqoridagi tabletka («+12%»).
  final String? delta;

  /// Pastdagi qo'shimcha (mini-grafik).
  final Widget? footer;
  final VoidCallback? onTap;

  /// Raqam vidjeti (sanab o'tish uchun): uslub beriladi.
  final Widget Function(TextStyle style)? valueBuilder;
  final double? minHeight;
  final String? semanticLabel;

  @override
  State<KoshinTile> createState() => _KoshinTileState();
}

class _KoshinTileState extends State<KoshinTile> {
  bool _down = false;

  void _set(bool value) {
    if (_down != value && mounted) setState(() => _down = value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = KoshinTileColors.of(widget.hue);
    final dense = AppColors.choice.dense;
    final radius = BorderRadius.circular(AppRadius.kpi);
    final long = widget.value.length > 8;
    final valueStyle = AppTheme.display(size: long ? (dense ? 19 : 22) : (dense ? 28 : 33), color: colors.value);
    final rich = Motion.rich(context);
    final interactive = widget.onTap != null;
    final pad = (16 * AppColors.choice.densityFactor).clamp(12, 19).toDouble();
    final body = Padding(
      padding: EdgeInsets.fromLTRB(pad, pad - 2, pad - 2, pad - 2),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Row(children: <Widget>[
          if (widget.icon != null)
            Container(
              width: dense ? 32 : 36,
              height: dense ? 32 : 36,
              decoration: BoxDecoration(color: colors.chip, borderRadius: BorderRadius.circular(AppRadius.control)),
              child: Icon(widget.icon, size: dense ? 17 : 19, color: colors.value),
            ),
          const Spacer(),
          if (widget.delta != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: colors.chip, borderRadius: BorderRadius.circular(99)),
              child: Text(widget.delta!, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: colors.value)),
            ),
        ]),
        SizedBox(height: dense ? 8 : 10),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: widget.valueBuilder?.call(valueStyle) ?? Text(widget.value, maxLines: 1, style: valueStyle),
        ),
        const SizedBox(height: 5),
        Text(widget.text, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: colors.text, height: 1.3)),
        if (widget.hint.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(widget.hint, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: colors.hint, height: 1.35)),
          ),
        if (widget.footer != null) ...<Widget>[const SizedBox(height: 8), widget.footer!],
      ]),
    );
    final content = Stack(children: <Widget>[
      Positioned(
        right: -28,
        top: -28,
        child: AnimatedRotation(
          turns: _down && rich ? 1 / 16 : 0,
          duration: AppDurations.d3,
          curve: AppCurves.out,
          child: GirihStar(size: 120, color: colors.girih, line: true),
        ),
      ),
      ConstrainedBox(constraints: BoxConstraints(minHeight: widget.minHeight ?? (dense ? 120 : 140)), child: body),
    ]);
    Widget tile = Material(
      color: colors.background,
      shape: RoundedRectangleBorder(borderRadius: radius, side: colors.border == null ? BorderSide.none : BorderSide(color: colors.border!)),
      clipBehavior: Clip.antiAlias,
      child: interactive
          ? InkWell(
              onTap: widget.onTap,
              onHighlightChanged: _set,
              splashColor: colors.text.withAlpha(28),
              highlightColor: colors.text.withAlpha(14),
              child: content,
            )
          : content,
    );
    if (interactive) tile = Pressable(scale: 0.97, child: tile);
    return Semantics(
      button: interactive,
      label: widget.semanticLabel ?? '${widget.value}, ${widget.text}${widget.hint.isEmpty ? '' : ', ${widget.hint}'}',
      excludeSemantics: true,
      child: tile,
    );
  }
}

/// «Bajarildi» muhri (veb: SuccessStamp.vue): girih yulduzi ichida belgi. To'liq: muhr kattadan bosiladi (−14° → 0),
/// shafran halqa tarqaladi, belgi chiziladi (≈ 1 s); Kam — paydo bo'ladi; O'chiq — darhol.
class SuccessStamp extends StatefulWidget {
  const SuccessStamp({super.key, this.size = 72, this.color});

  final double size;
  final Color? color;

  static const Duration duration = Duration(milliseconds: 960);

  @override
  State<SuccessStamp> createState() => _SuccessStampState();
}

class _SuccessStampState extends State<SuccessStamp> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: SuccessStamp.duration);
  MotionLevel? _level;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_level != null) return;
    _level = Motion.of(context);
    if (_level == MotionLevel.off) {
      _controller.value = 1;
    } else {
      _controller.duration = _level == MotionLevel.full ? SuccessStamp.duration : AppDurations.d2;
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? AppColors.toneSuccess;
    final full = _level == MotionLevel.full;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = _controller.value;
            if (!full) {
              return Opacity(opacity: t, child: CustomPaint(painter: _StampPainter(color: color, check: 1)));
            }
            const ms = 960.0;
            double part(double from, double length) => ((t * ms - from) / length).clamp(0.0, 1.0);
            // Bosilish: 0–560 ms — scale 1.7 → .92 → 1, burilish −14° → 2° → 0.
            final press = part(0, 560);
            final double scale;
            final double angle;
            if (press < 0.55) {
              final k = Curves.easeOut.transform(press / 0.55);
              scale = 1.7 + (0.92 - 1.7) * k;
              angle = -14 + 16 * k;
            } else {
              final k = Curves.easeInOut.transform((press - 0.55) / 0.45);
              scale = 0.92 + 0.08 * k;
              angle = 2 - 2 * k;
            }
            final ring = part(260, 700);
            final check = AppCurves.out.transform(part(380, 360));
            return Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: <Widget>[
              if (ring > 0 && ring < 1)
                Opacity(
                  opacity: 0.55 * (1 - ring),
                  child: Transform.scale(
                    scale: 0.7 + 1.2 * AppCurves.out.transform(ring),
                    child: Container(
                      width: widget.size,
                      height: widget.size,
                      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Koshin.shafran, width: 3)),
                    ),
                  ),
                ),
              Opacity(
                opacity: (press / 0.3).clamp(0.0, 1.0),
                child: Transform.rotate(
                  angle: angle * math.pi / 180,
                  child: Transform.scale(scale: scale, child: CustomPaint(size: Size.square(widget.size), painter: _StampPainter(color: color, check: check))),
                ),
              ),
            ]);
          },
        ),
      ),
    );
  }
}

class _StampPainter extends CustomPainter {
  _StampPainter({required this.color, required this.check});

  final Color color;

  /// Belgi chizilishi (0..1).
  final double check;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(girihPath(size), Paint()..color = color);
    if (check <= 0) return;
    final scale = size.shortestSide / 100;
    final path = Path()
      ..moveTo(35 * scale, 51 * scale)
      ..lineTo(45 * scale, 61 * scale)
      ..lineTo(66 * scale, 39 * scale);
    final metric = path.computeMetrics().toList();
    final total = metric.fold<double>(0, (sum, item) => sum + item.length);
    var left = total * check;
    final drawn = Path();
    for (final item in metric) {
      if (left <= 0) break;
      drawn.addPath(item.extractPath(0, math.min(left, item.length)), Offset.zero);
      left -= item.length;
    }
    canvas.drawPath(
      drawn,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8 * scale
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_StampPainter oldDelegate) => oldDelegate.check != check || oldDelegate.color != color;
}

/// Bo'lim belgisi plitkasi (veb: page-band-context .nav-icon-tile): bo'lim rangida to'liq kvadrat, oq belgi.
class SectionMark extends StatelessWidget {
  const SectionMark({super.key, required this.icon, required this.color, this.size = 30});

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular((AppRadius.control * 0.85).clamp(3, 12).toDouble())),
      child: Icon(icon, size: size * 0.56, color: Colors.white),
    );
  }
}

/// Lojuvard banner (kirish paneli oilasi): «lojuvard tun» foni, oq girih naqshi — yutuqlar darajasi, olimpiada sarlavhasi.
class KoshinBanner extends StatelessWidget {
  const KoshinBanner({super.key, required this.child, this.padding = const EdgeInsets.all(18), this.radius = 18});

  final Widget child;
  final EdgeInsets padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: Koshin.night, borderRadius: BorderRadius.circular(radius)),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(painter: GirihPatternPainter(step: 84, color: const Color(0x14FFFFFF)), child: Padding(padding: padding, child: child)),
    );
  }
}
