// Umumiy komponentlar (3.8, «Daftar 2: hoshiya»): yuklanish holatlari (skelet), internetsiz nusxa, kartalar, ko'rsatkichlar,
// holat chiplari, ism bosh harfli doiralar, bo'sh holat illyustratsiyalari, sahifa sarlavhasi bandi, xabarlar (toast).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import 'adaptive.dart';
import 'api.dart';
import 'design.dart';
import 'format.dart';
import 'help_links.dart';
import 'i18n.dart';
import 'illustrations.dart';
import 'motion.dart';
import 'offline_cache.dart';
import 'theme.dart';

/// Ma'lumot yuklanadigan sahifa qismi: yuklanmoqda (skelet) / xato (qayta urinish) / natija. Pastga tortib yangilash bilan.
///
/// [cacheKey] berilsa (3.1), muvaffaqiyatli javob telefonda saqlanadi va internet bo'lmaganda o'sha nusxa
/// «Internet yo'q» belgisi bilan ko'rsatiladi. Saqlangan JSON dan T ni tiklash uchun [decode] (bo'lmasa — `as T`).
class AsyncView<T> extends StatefulWidget {
  const AsyncView({
    super.key,
    required this.load,
    required this.builder,
    this.refreshable = true,
    this.cacheKey,
    this.decode,
    this.skeleton,
  });

  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, Future<void> Function() reload) builder;
  final bool refreshable;
  final String? cacheKey;
  final T Function(dynamic raw)? decode;

  /// Yuklanayotganda ko'rsatiladigan skelet (bo'lmasa — ro'yxat skeleti).
  final Widget? skeleton;

  @override
  State<AsyncView<T>> createState() => AsyncViewState<T>();
}

class AsyncViewState<T> extends State<AsyncView<T>> {
  T? _data;
  bool _hasData = false;
  Object? _error;
  bool _loading = true;

  /// Internetsiz nusxa ko'rsatilmoqda: u qachon saqlangan.
  DateTime? _offlineAt;

  bool get offline => _offlineAt != null;

  @override
  void initState() {
    super.initState();
    reload();
  }

  static bool _isOffline(Object error) => error is ApiException && (error.isNetwork || error.status >= 500);

  Future<void> reload() async {
    if (mounted) setState(() => _loading = true);
    try {
      final data = await widget.load();
      if (!mounted) return;
      setState(() {
        _data = data;
        _hasData = true;
        _error = null;
        _loading = false;
        _offlineAt = null;
      });
      final key = widget.cacheKey;
      if (key != null) unawaited(OfflineCache.write(key, data));
    } catch (error) {
      if (!mounted) return;
      final key = widget.cacheKey;
      if (key != null && _isOffline(error) && (!_hasData || _offlineAt != null)) {
        final cached = await OfflineCache.read(key);
        if (!mounted) return;
        T? value;
        if (cached != null) {
          try {
            final decode = widget.decode;
            value = decode != null ? decode(cached.data) : cached.data as T;
          } catch (_) {
            value = null;
          }
        }
        if (cached != null && value != null) {
          final repeated = _offlineAt != null;
          setState(() {
            _data = value;
            _hasData = true;
            _error = null;
            _loading = false;
            _offlineAt = cached.savedAt;
          });
          if (repeated) showMessage(context, errorText(error), error: true);
          return;
        }
      }
      setState(() {
        _error = error;
        _loading = false;
      });
      if (_hasData) showMessage(context, errorText(error), error: true);
    }
  }

  /// Ma'lumot birinchi marta paydo bo'lganda — yumshoq so'nish (skeletdan keyin).
  bool _fadeIn = false;

  @override
  Widget build(BuildContext context) {
    if (!_hasData) {
      _fadeIn = true;
      if (_loading) return widget.skeleton ?? const SkeletonList();
      final error = _error;
      if (error is ApiException && error.isForbidden) return ForbiddenState(details: error.message, onRetry: reload);
      return ErrorState(message: errorText(_error), onRetry: reload);
    }
    var child = widget.builder(context, _data as T, reload);
    if (widget.refreshable) {
      child = RefreshIndicator(onRefresh: reload, color: AppColors.accent, backgroundColor: AppColors.raised, strokeWidth: 2.4, child: child);
    }
    final offlineAt = _offlineAt;
    if (offlineAt != null) {
      child = Column(children: <Widget>[
        OfflineBanner(savedAt: offlineAt, onRetry: _loading ? null : reload),
        Expanded(child: child),
      ]);
    }
    // Daraxt tuzilishi doim bir xil (sahifa holati saqlanadi): so'nish faqat birinchi paydo bo'lishda.
    final fade = _fadeIn && Motion.any(context);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: fade ? 0 : 1, end: 1),
      duration: AppDurations.d2,
      curve: Curves.easeOut,
      onEnd: () => _fadeIn = false,
      child: child,
      builder: (context, value, child) => Opacity(opacity: value, child: child),
    );
  }
}

/// Chap chetida hoshiya (daftar chizig'i) bo'lgan blok: diqqat talab qiladigan karta, toast, banner.
class HoshiyaBox extends StatelessWidget {
  const HoshiyaBox({super.key, required this.child, required this.color, this.background, this.radius, this.padding = EdgeInsets.zero});

  final Widget child;
  final Color color;
  final Color? background;
  final BorderRadius? radius;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: radius ?? BorderRadius.zero,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          border: Border(left: BorderSide(color: color, width: AppSpacing.hoshiya)),
        ),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// «Internet yo'q — saqlangan nusxa» belgisi (sahifa tepasida).
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, required this.savedAt, this.onRetry});

  final DateTime savedAt;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return HoshiyaBox(
      color: AppColors.toneWarning,
      background: AppColors.warningBg,
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      child: Row(children: <Widget>[
        Icon(Icons.cloud_off_rounded, size: 18, color: AppColors.warning),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            tr("Internet yo'q. {0} holatidagi ma'lumot ko'rsatilmoqda.", <Object?>[dateTime(savedAt.toIso8601String())]),
            style: TextStyle(fontSize: 12.5, color: AppColors.ink),
          ),
        ),
        TextButton(onPressed: onRetry, child: Text(tr('Yangilash'))),
      ]),
    );
  }
}

/// Yuklanish skeleti: sokin kulrang bloklar (veb: `loading-line`).
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, this.height = 14, this.radius = 6});

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(color: AppColors.sunken, borderRadius: BorderRadius.circular(radius)),
    );
  }
}

/// Skelet «nafas olishi» — faqat To'liq darajada (Kam va O'chiq — harakatsiz).
class _Pulse extends StatefulWidget {
  const _Pulse({required this.child});

  final Widget child;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100), lowerBound: 0.55, upperBound: 1, value: 1);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started && Motion.rich(context)) {
      _started = true;
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(opacity: _controller, child: widget.child);
}

/// Ro'yxat sahifalari uchun skelet: kartalar (doira + ikki qator).
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 6, this.header = false});

  final int count;

  /// Tepada katta blok (bosh sahifa: hero va ko'rsatkichlar).
  final bool header;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: tr('Yuklanmoqda...'),
      liveRegion: true,
      child: _Pulse(
        child: ListView(
          physics: const NeverScrollableScrollPhysics(),
          padding: readable(context, const EdgeInsets.all(AppSpacing.l), max: kGridWidth),
          children: <Widget>[
            if (header) ...<Widget>[
              Container(
                height: 132,
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border(left: BorderSide(color: AppColors.sunken, width: AppSpacing.hoshiya)),
                ),
                padding: const EdgeInsets.all(18),
                child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  SkeletonBox(width: 110, height: 12),
                  SizedBox(height: 12),
                  SkeletonBox(width: 220, height: 24),
                  SizedBox(height: 14),
                  SkeletonBox(width: 160),
                ]),
              ),
              const SizedBox(height: AppSpacing.m),
              Row(children: <Widget>[
                Expanded(child: SkeletonBox(height: 112, radius: AppRadius.card)),
                const SizedBox(width: AppSpacing.m),
                Expanded(child: SkeletonBox(height: 112, radius: AppRadius.card)),
              ]),
              const SizedBox(height: AppSpacing.m),
            ],
            for (var i = 0; i < count; i++)
              Container(
                margin: const EdgeInsets.only(bottom: AppSpacing.s),
                padding: const EdgeInsets.all(AppSpacing.l),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(color: AppColors.line),
                ),
                child: Row(children: <Widget>[
                  const SkeletonBox(width: 38, height: 38, radius: 19),
                  const SizedBox(width: AppSpacing.m),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                      SkeletonBox(width: i.isEven ? 180 : 140),
                      const SizedBox(height: AppSpacing.s),
                      SkeletonBox(width: i.isEven ? 110 : 150, height: 10),
                    ]),
                  ),
                ]),
              ),
          ],
        ),
      ),
    );
  }
}

String errorText(Object? error) {
  if (error is ApiException) return error.message;
  return tr("Ma'lumotni yuklab bo'lmadi.");
}

/// Toast (veb: `toast` + `data-tone`): ko'tarilgan sirt, chap chetida hoshiya — xato qizil, oddiy xabar asosiy rangda.
void showMessage(BuildContext context, String text, {bool error = false, String? actionLabel, VoidCallback? onAction}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final tone = error ? AppColors.toneDanger : AppColors.accent;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      padding: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      content: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          Container(width: AppSpacing.hoshiya, color: tone),
          const SizedBox(width: 12),
          Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 14, right: 4),
            child: Icon(error ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded, size: 20, color: error ? AppColors.danger : AppColors.brand),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(text, style: TextStyle(color: AppColors.ink, fontSize: 14.5, height: 1.35)),
            ),
          ),
          const SizedBox(width: 12),
        ]),
      ),
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.raised,
      duration: onAction == null ? const Duration(seconds: 4) : const Duration(seconds: 8),
      action: onAction == null ? null : SnackBarAction(label: actionLabel ?? tr('Ochish'), textColor: AppColors.accentStrong, onPressed: onAction),
    ));
}

/// Pastki menyu bo'limi ko'rinib turibdimi (IndexedStack ochilgan bo'limlarni tirik saqlaydi — yashirin bo'limdagi
/// davriy so'rovlar to'xtab tursin). Ustida bo'lmasa — ko'rinadi deb olinadi.
class TabVisibility extends InheritedWidget {
  const TabVisibility({super.key, required this.visible, required super.child});

  final bool visible;

  static bool of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<TabVisibility>()?.visible ?? true;

  @override
  bool updateShouldNotify(TabVisibility oldWidget) => oldWidget.visible != visible;
}

Future<bool> confirm(BuildContext context, String text, {String? action, bool danger = false}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      content: Text(text, style: TextStyle(fontSize: 15.5, color: AppColors.ink, height: 1.4)),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Bekor qilish'))),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: AppColors.dangerFill, foregroundColor: Colors.white) : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(action ?? tr('Tasdiqlash')),
        ),
      ],
    ),
  );
  return result ?? false;
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, this.onRetry, this.showHelp = true});

  final String message;
  final VoidCallback? onRetry;

  /// «Muammolar va yechimlar» maqolasi havolasi (3.5).
  final bool showHelp;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          EmptyIllustration(EmptyArt.search, width: 104, color: AppColors.danger),
          const SizedBox(height: 14),
          Text(tr("Ma'lumotni yuklab bo'lmadi"), textAlign: TextAlign.center, style: AppTheme.title(size: 18)),
          const SizedBox(height: 6),
          Text(message, textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 14.5, height: 1.4)),
          if (onRetry != null) ...<Widget>[
            const SizedBox(height: 18),
            FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh, size: 20), label: Text(tr('Qayta urinish'))),
          ],
          if (showHelp) ...<Widget>[
            const SizedBox(height: 6),
            const ProblemsLink(),
          ],
        ]),
      ),
    );
  }
}

/// 403: bo'lim tashkilotda yoqilmagan yoki shu rolga ruxsat yo'q — qo'rqitmaydigan tushuntirish bilan.
class ForbiddenState extends StatelessWidget {
  const ForbiddenState({super.key, this.details, this.onRetry});

  final String? details;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          EmptyIllustration(EmptyArt.notebook, width: 104, color: AppColors.warning),
          const SizedBox(height: 14),
          Text(tr("Bu bo'lim hozircha mavjud emas"), textAlign: TextAlign.center, style: AppTheme.title(size: 18)),
          const SizedBox(height: 6),
          Text(tr("Tashkilotingizda bu imkoniyat yoqilmagan yoki sizga ruxsat berilmagan. Savollar bo'lsa, o'quv markazi yoki maktab ma'muriyatiga murojaat qiling."),
              textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, height: 1.4)),
          if (details != null && details!.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Text(details!, textAlign: TextAlign.center, style: TextStyle(color: AppColors.subtle, fontSize: 12)),
          ],
          if (onRetry != null) ...<Widget>[
            const SizedBox(height: 16),
            OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: Text(tr('Qayta urinish'))),
          ],
        ]),
      ),
    );
  }
}

/// Bo'sh holat (veb: `empty-state[data-art]`): illyustratsiya, nima bo'lgani va keyingi qadam (bitta tugma).
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.text, this.icon = Icons.inbox_outlined, this.action, this.art});

  final String text;
  final IconData icon;
  final Widget? action;

  /// Illyustratsiya (berilmasa — [icon] ga qarab tanlanadi).
  final EmptyArt? art;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        EmptyIllustration(art ?? artForIcon(icon), width: 112),
        const SizedBox(height: 16),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Text(text, textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 15, height: 1.45)),
        ),
        if (action != null) ...<Widget>[const SizedBox(height: 18), action!],
      ]),
    );
  }
}

/// Karta (veb: `card`): shablonga qarab chegarali / soyali / tekis. [tone] — chap chetida hoshiya (diqqat talab qiladi).
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap, this.color, this.tone});

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color? color;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.card);
    Widget content = Padding(padding: padding, child: child);
    if (tone != null) {
      content = DecoratedBox(decoration: BoxDecoration(border: Border(left: BorderSide(color: tone!, width: AppSpacing.hoshiya))), child: content);
    }
    Widget card = Material(
      color: color ?? AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: AppColors.cardBorder)),
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? content : InkWell(onTap: onTap, child: content),
    );
    if (AppColors.cardShadow.isNotEmpty) {
      card = DecoratedBox(decoration: BoxDecoration(borderRadius: radius, boxShadow: AppColors.cardShadow), child: card);
    }
    return onTap == null ? card : Pressable(child: card);
  }
}

/// Bo'lim sarlavhasi (veb: section-title) — sarlavha shriftida, ixtiyoriy o'ng harakat.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(2, AppColors.choice.dense ? 16 : 22, 2, 10),
      child: Row(children: <Widget>[
        Expanded(child: Semantics(header: true, child: Text(title, style: AppTheme.title(size: AppColors.choice.dense ? 15.5 : 17)))),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

/// Belgi plitkasi (veb: icon-tile tile-*): rangli yumshoq kvadrat ichida belgi.
class IconTile extends StatelessWidget {
  const IconTile({super.key, required this.icon, required this.colors, this.size = 36});

  final IconData icon;
  final StatusColors colors;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: colors.bg, borderRadius: BorderRadius.circular((AppRadius.control * 0.9).clamp(4, 14).toDouble())),
      child: Icon(icon, size: size * 0.52, color: colors.fg),
    );
  }
}

/// Rang → plitka (holat ranglari — jadvaldagi fon; boshqasi — yumshoq fon).
StatusColors tileOf(Color color) => StatusColors(color, AppColors.soft(color));

/// Ko'rsatkich kartasi.
class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.label, required this.value, required this.icon, Color? color, this.hint, this.onTap}) : _color = color;

  final String label;
  final String value;
  final IconData icon;
  final Color? _color;
  Color get color => _color ?? AppColors.brand;
  final String? hint;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Row(children: <Widget>[
          IconTile(icon: icon, colors: tileOf(color), size: 34),
          const Spacer(),
          if (onTap != null) Icon(Icons.chevron_right, size: 18, color: AppColors.subtle),
        ]),
        const SizedBox(height: 10),
        CountUpText(value,
            countKey: 'stat:$label',
            maxLines: 1,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.ink, fontFeatures: AppTheme.tabular, letterSpacing: -0.3)),
        const SizedBox(height: 2),
        Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: AppColors.muted, height: 1.3)),
        if (hint != null && hint!.isNotEmpty)
          Text(hint!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

/// Ko'rsatkichlar to'ri: telefonda 2 ustun, keng ekranda (iPad) 4 tagacha.
class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => AdaptiveGrid(minTile: 170, children: children);
}

/// Holat belgisi — «chip» (veb 1.40): chapda rangli nuqta, yumshoq to'rtburchak.
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, Color? color, this.dot = true}) : _color = color;

  final String text;
  final Color? _color;
  final bool dot;
  Color get color => _color ?? AppColors.brand;

  @override
  Widget build(BuildContext context) {
    final neutral = color == AppColors.muted || color == AppColors.subtle;
    final fg = neutral ? AppColors.muted : color;
    final bg = neutral ? AppColors.sunken : AppColors.soft(color);
    return Container(
      padding: EdgeInsets.fromLTRB(dot ? 7 : 8, 3, 8, 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadius.chip)),
      child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
        if (dot) ...<Widget>[
          Container(width: 6, height: 6, decoration: BoxDecoration(color: fg, shape: BoxShape.circle)),
          const SizedBox(width: 6),
        ],
        Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg, height: 1.25))),
      ]),
    );
  }
}

class KeyValue extends StatelessWidget {
  const KeyValue(this.label, this.value, {super.key, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Expanded(child: Text(label, style: TextStyle(color: AppColors.muted))),
        const SizedBox(width: 12),
        Flexible(
          child: Text(value,
              textAlign: TextAlign.end,
              style: TextStyle(fontWeight: FontWeight.w600, color: valueColor ?? AppColors.ink, fontFeatures: AppTheme.tabular)),
        ),
      ]),
    );
  }
}

/// Bosh harflar doirasi (veb: Avatar.vue): rang ismdan barqaror — bir odam har doim bir rangda.
/// [heroTag] berilsa — ro'yxatdan tafsilotga o'tishda doira «uchib» o'tadi (Hero).
class Avatar extends StatelessWidget {
  const Avatar(this.name, {super.key, this.size = 40, Color? color, this.heroTag}) : _color = color;

  final String name;
  final double size;
  final Color? _color;
  final Object? heroTag;

  @override
  Widget build(BuildContext context) {
    final explicit = _color;
    final colors = explicit == null ? AppColors.tileFor(name) : tileOf(explicit);
    final circle = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: colors.bg, shape: BoxShape.circle),
      child: Text(
        initialsOf(name),
        style: TextStyle(color: colors.fg, fontWeight: FontWeight.w700, fontSize: size * 0.36, letterSpacing: 0.2, height: 1),
      ),
    );
    final tag = heroTag;
    if (tag == null || !Motion.any(context)) return circle;
    return Hero(tag: tag, child: Material(type: MaterialType.transparency, child: circle));
  }
}

// ---------------------------------------------------------------------------
// Sahifa sarlavhasi bandi (veb: page-band): bo'lim rangining 7% foni, chap chetida hoshiya, bo'lim yo'li
// («Kundalik ish › Davomat») va bo'lim yorliqlari. Faqat menyu bo'limlarining asosiy sahifalarida (HomeShell beradi);
// ochilgan tafsilot sahifalari — oddiy sarlavha paneli.
// ---------------------------------------------------------------------------

class SectionTab {
  const SectionTab(this.key, this.label);

  final String key;
  final String label;
}

class SectionScope extends InheritedWidget {
  const SectionScope({
    super.key,
    required this.section,
    required this.label,
    required this.color,
    this.cluster,
    this.tabs = const <SectionTab>[],
    this.selected = 0,
    this.onSelect,
    required super.child,
  });

  /// Bo'lim yo'q (ikki ustunli sahifaning o'ng ustuni — band takrorlanmaydi).
  const SectionScope.none({super.key, required super.child})
      : section = '',
        label = '',
        color = const Color(0x00000000),
        cluster = null,
        tabs = const <SectionTab>[],
        selected = 0,
        onSelect = null;

  final String section;
  final String label;
  final Color color;
  final String? cluster;
  final List<SectionTab> tabs;
  final int selected;
  final ValueChanged<int>? onSelect;

  bool get active => section.isNotEmpty;

  static SectionScope? of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<SectionScope>();
    return scope != null && scope.active ? scope : null;
  }

  @override
  bool updateShouldNotify(SectionScope oldWidget) =>
      oldWidget.section != section || oldWidget.selected != selected || oldWidget.tabs.length != tabs.length || oldWidget.label != label;
}

/// Sarlavha paneli (AppBar o'rnida, bir xil parametrlar): bo'lim sahifasida — band, aks holda — oddiy panel.
PreferredSizeWidget pageBar(
  BuildContext context, {
  Widget? title,
  List<Widget>? actions,
  PreferredSizeWidget? bottom,
  bool automaticallyImplyLeading = true,
  Color? backgroundColor,
  Color? foregroundColor,
  double? titleSpacing,
  TextStyle? titleTextStyle,
  Widget? leading,
}) {
  final scope = SectionScope.of(context);
  final route = ModalRoute.of(context);
  final canPop = route?.canPop ?? false;
  if (scope == null || canPop || backgroundColor != null) {
    return AppBar(
      title: title,
      actions: actions,
      bottom: bottom,
      automaticallyImplyLeading: automaticallyImplyLeading,
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      titleSpacing: titleSpacing,
      titleTextStyle: titleTextStyle,
      leading: leading,
    );
  }
  final chips = scope.tabs.length > 1 ? _SectionChips(scope: scope) : null;
  PreferredSizeWidget? fullBottom = bottom;
  if (chips != null) {
    final height = _SectionChips.height + (bottom?.preferredSize.height ?? 0);
    fullBottom = PreferredSize(
      preferredSize: Size.fromHeight(height),
      child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[chips, if (bottom != null) bottom]),
    );
  }
  final tint = Color.alphaBlend(scope.color.withAlpha(AppColors.dark ? 26 : 18), AppColors.chrome);
  final path = <String>[if (scope.cluster != null) scope.cluster!, scope.label];
  return AppBar(
    toolbarHeight: 60,
    backgroundColor: tint,
    automaticallyImplyLeading: automaticallyImplyLeading,
    leading: leading,
    titleSpacing: titleSpacing ?? 20,
    actions: actions,
    bottom: fullBottom,
    flexibleSpace: Align(
      alignment: Alignment.centerLeft,
      child: Container(width: AppSpacing.hoshiya, color: scope.color),
    ),
    title: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: <Widget>[
      Text(
        path.join(' › '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.subtle, letterSpacing: 0.1),
      ),
      const SizedBox(height: 1),
      DefaultTextStyle.merge(
        style: titleTextStyle ?? AppTheme.title(size: AppColors.choice.dense ? 17 : 19, color: AppColors.ink),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        child: title ?? Text(scope.label),
      ),
    ]),
  );
}

class _SectionChips extends StatelessWidget {
  const _SectionChips({required this.scope});

  final SectionScope scope;

  static const double height = 48;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(18, 4, 16, 10),
        itemCount: scope.tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final active = i == scope.selected;
          return Semantics(
            selected: active,
            button: true,
            child: Material(
              color: active ? AppColors.accent : AppColors.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.chip + 3),
                side: BorderSide(color: active ? AppColors.accent : AppColors.line),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: active ? null : () => scope.onSelect?.call(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Center(
                    child: Text(
                      scope.tabs[i].label,
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: active ? Colors.white : AppColors.ink),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Matn + LaTeX formulalar ($...$, \(...\), $$...$$, \[...\]) — veb-tizimdagi RichText kabi.
class MathText extends StatelessWidget {
  const MathText(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  static final RegExp _pattern =
      RegExp(r'\$\$([\s\S]+?)\$\$|\\\[([\s\S]+?)\\\]|\\\(([\s\S]+?)\\\)|\$(?!\s)([^$\n]*?[^\s$])\$(?!\d)');

  @override
  Widget build(BuildContext context) {
    final base = style ?? DefaultTextStyle.of(context).style;
    final matches = _pattern.allMatches(text).toList();
    if (matches.isEmpty) return Text(text, style: base);
    final spans = <InlineSpan>[];
    var last = 0;
    for (final match in matches) {
      if (match.start > last) spans.add(TextSpan(text: text.substring(last, match.start)));
      final display = match.group(1) != null || match.group(2) != null;
      final formula = match.group(1) ?? match.group(2) ?? match.group(3) ?? match.group(4) ?? '';
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 2, vertical: display ? 6 : 0),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Math.tex(
              formula,
              mathStyle: display ? MathStyle.display : MathStyle.text,
              textStyle: base,
              onErrorFallback: (error) => Text(match.group(0) ?? formula, style: base),
            ),
          ),
        ),
      ));
      last = match.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return Text.rich(TextSpan(style: base, children: spans));
  }
}

/// Fon naqshi (veb: data-pattern): nuqtali yoki chiziqli, juda nozik; «Maktab» — katak (sahifa boshida, pastga so'nadi).
class CanvasPattern extends StatelessWidget {
  const CanvasPattern({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final pattern = AppColors.choice.effectivePattern;
    if (pattern == 'none' && !AppColors.choice.notebook) return child;
    return CustomPaint(painter: PatternPainter(pattern: AppColors.choice.notebook && pattern == 'none' ? 'grid' : pattern, color: AppColors.lineStrong), child: child);
  }
}

class PatternPainter extends CustomPainter {
  PatternPainter({required this.pattern, required this.color});

  final String pattern;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color.withAlpha(AppColors.dark ? 70 : 120);
    if (pattern == 'dots') {
      const step = 18.0;
      for (var y = 9.0; y < size.height; y += step) {
        for (var x = 9.0; x < size.width; x += step) {
          canvas.drawCircle(Offset(x, y), 1, paint);
        }
      }
    } else if (pattern == 'lines') {
      paint.strokeWidth = 1;
      for (var y = 24.0; y < size.height; y += 24) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), paint..color = color.withAlpha(AppColors.dark ? 40 : 70));
      }
    } else if (pattern == 'grid') {
      // Katak daftar: tepada 320px, pastga so'nadi.
      const step = 20.0;
      final limit = size.height < 320 ? size.height : 320.0;
      for (var y = 0.0; y <= limit; y += step) {
        final alpha = ((1 - y / limit) * (AppColors.dark ? 40 : 70)).round();
        canvas.drawLine(Offset(0, y), Offset(size.width, y), Paint()..color = color.withAlpha(alpha));
      }
      for (var x = 0.0; x <= size.width; x += step) {
        final shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[color.withAlpha(AppColors.dark ? 40 : 70), color.withAlpha(0)],
        ).createShader(Rect.fromLTWH(x, 0, 1, limit));
        canvas.drawLine(Offset(x, 0), Offset(x, limit), Paint()..shader = shader);
      }
    }
  }

  @override
  bool shouldRepaint(PatternPainter oldDelegate) => oldDelegate.pattern != pattern || oldDelegate.color != color;
}
