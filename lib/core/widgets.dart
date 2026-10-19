// Umumiy komponentlar: yuklanish holatlari (skelet), internetsiz nusxa, kartalar, ko'rsatkichlar, xabarlar.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import 'api.dart';
import 'format.dart';
import 'i18n.dart';
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

  @override
  Widget build(BuildContext context) {
    if (!_hasData) {
      if (_loading) return widget.skeleton ?? const SkeletonList();
      final error = _error;
      if (error is ApiException && error.isForbidden) return ForbiddenState(details: error.message, onRetry: reload);
      return ErrorState(message: errorText(_error), onRetry: reload);
    }
    var child = widget.builder(context, _data as T, reload);
    if (widget.refreshable) child = RefreshIndicator(onRefresh: reload, child: child);
    final offlineAt = _offlineAt;
    if (offlineAt == null) return child;
    return Column(children: <Widget>[
      OfflineBanner(savedAt: offlineAt, onRetry: _loading ? null : reload),
      Expanded(child: child),
    ]);
  }
}

/// «Internet yo'q — saqlangan nusxa» belgisi (sahifa tepasida).
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, required this.savedAt, this.onRetry});

  final DateTime savedAt;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.soft(AppColors.warning),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
        child: Row(children: <Widget>[
          const Icon(Icons.cloud_off_rounded, size: 18, color: AppColors.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              tr("Internet yo'q. {0} holatidagi ma'lumot ko'rsatilmoqda.", <Object?>[dateTime(savedAt.toIso8601String())]),
              style: TextStyle(fontSize: 12.5, color: AppColors.ink),
            ),
          ),
          TextButton(onPressed: onRetry, child: Text(tr('Yangilash'))),
        ]),
      ),
    );
  }
}

/// Yuklanish skeleti: yumshoq «nafas olayotgan» kulrang bloklar.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, this.height = 14, this.radius = 8});

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.line.withAlpha(AppColors.dark ? 200 : 255),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class _Pulse extends StatefulWidget {
  const _Pulse({required this.child});

  final Widget child;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900), lowerBound: 0.45, upperBound: 1)
        ..repeat(reverse: true);

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

  /// Tepada katta karta (bosh sahifa ko'rsatkichlari uchun).
  final bool header;

  @override
  Widget build(BuildContext context) {
    return _Pulse(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.l),
        children: <Widget>[
          if (header) ...<Widget>[
            const SkeletonBox(width: 180, height: 22),
            const SizedBox(height: AppSpacing.s),
            const SkeletonBox(width: 120),
            const SizedBox(height: AppSpacing.l),
            Row(children: const <Widget>[
              Expanded(child: SkeletonBox(height: 96, radius: AppRadius.card)),
              SizedBox(width: AppSpacing.m),
              Expanded(child: SkeletonBox(height: 96, radius: AppRadius.card)),
            ]),
            const SizedBox(height: AppSpacing.m),
          ],
          for (var i = 0; i < count; i++)
            Container(
              margin: const EdgeInsets.only(bottom: AppSpacing.m),
              padding: const EdgeInsets.all(AppSpacing.l),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: AppColors.line),
              ),
              child: Row(children: <Widget>[
                const SkeletonBox(width: 40, height: 40, radius: 20),
                const SizedBox(width: AppSpacing.m),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                    SkeletonBox(width: i.isEven ? 180 : 140),
                    const SizedBox(height: AppSpacing.s),
                    SkeletonBox(width: i.isEven ? 110 : 150, height: 11),
                  ]),
                ),
              ]),
            ),
        ],
      ),
    );
  }
}

String errorText(Object? error) {
  if (error is ApiException) return error.message;
  return tr("Ma'lumotni yuklab bo'lmadi.");
}

void showMessage(BuildContext context, String text, {bool error = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(text),
      behavior: SnackBarBehavior.floating,
      backgroundColor: error ? AppColors.danger : AppColors.ink,
    ));
}

Future<bool> confirm(BuildContext context, String text, {String? action, bool danger = false}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      content: Text(text),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Bekor qilish'))),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: AppColors.danger) : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(action ?? tr('Tasdiqlash')),
        ),
      ],
    ),
  );
  return result ?? false;
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          _StateIcon(icon: Icons.cloud_off_rounded, color: AppColors.danger),
          const SizedBox(height: 14),
          Text(message, textAlign: TextAlign.center, style: TextStyle(color: AppColors.ink, fontSize: 15)),
          if (onRetry != null) ...<Widget>[
            const SizedBox(height: 16),
            OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: Text(tr('Qayta urinish'))),
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
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: AppColors.soft(AppColors.warning), shape: BoxShape.circle),
            child: const Icon(Icons.lock_outline_rounded, size: 32, color: AppColors.warning),
          ),
          const SizedBox(height: 14),
          Text(tr("Bu bo'lim hozircha mavjud emas"),
              textAlign: TextAlign.center, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.ink)),
          const SizedBox(height: 6),
          Text(tr("Tashkilotingizda bu imkoniyat yoqilmagan yoki sizga ruxsat berilmagan. Savollar bo'lsa, o'quv markazi yoki maktab ma'muriyatiga murojaat qiling."),
              textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
          if (details != null && details!.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Text(details!, textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 12)),
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

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.text, this.icon = Icons.inbox_outlined, this.action});

  final String text;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        _StateIcon(icon: icon, color: AppColors.brand),
        const SizedBox(height: 14),
        Text(text, textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 15, height: 1.35)),
        if (action != null) ...<Widget>[const SizedBox(height: 16), action!],
      ]),
    );
  }
}

/// Bo'sh / xato holatlaridagi katta belgi (yumshoq doira ichida).
class _StateIcon extends StatelessWidget {
  const _StateIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(color: AppColors.soft(color), shape: BoxShape.circle),
      child: Icon(icon, size: 34, color: color.withAlpha(200)),
    );
  }
}

/// Oq karta (veb-tizimdagi `card`).
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap, this.color});

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color ?? AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card), side: BorderSide(color: AppColors.line)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
      child: Row(children: <Widget>[
        Expanded(child: Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink))),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

/// Bosh sahifadagi rangli ko'rsatkich.
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
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: color.withAlpha(28), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 19, color: color),
          ),
          const Spacer(),
          if (onTap != null) Icon(Icons.chevron_right, size: 18, color: AppColors.muted),
        ]),
        const SizedBox(height: 10),
        Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.ink)),
        const SizedBox(height: 2),
        Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: AppColors.muted)),
        if (hint != null && hint!.isNotEmpty)
          Text(hint!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

/// Ikki ustunli ko'rsatkichlar to'ri.
class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += 2) {
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
            Expanded(child: children[i]),
            const SizedBox(width: 10),
            Expanded(child: i + 1 < children.length ? children[i + 1] : const SizedBox()),
          ]),
        ),
      ));
    }
    return Column(children: rows);
  }
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, Color? color}) : _color = color;

  final String text;
  final Color? _color;
  Color get color => _color ?? AppColors.brand;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: color.withAlpha(26), borderRadius: BorderRadius.circular(99)),
      child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
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
              style: TextStyle(fontWeight: FontWeight.w600, color: valueColor ?? AppColors.ink)),
        ),
      ]),
    );
  }
}

/// Bosh harflar doirasi.
class Avatar extends StatelessWidget {
  const Avatar(this.name, {super.key, this.size = 40, Color? color}) : _color = color;

  final String name;
  final double size;
  final Color? _color;
  Color get color => _color ?? AppColors.brand;

  @override
  Widget build(BuildContext context) {
    final parts = name.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();
    final letters = parts.take(2).map((part) => part.substring(0, 1).toUpperCase()).join();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color.withAlpha(30), shape: BoxShape.circle),
      child: Text(letters, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: size * 0.36)),
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
