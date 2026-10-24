// O'yin ekranlari uchun umumiy qism: qobiq (PlayPage) bilan aloqa, savol kartasi, javob tugmalari, raqam klaviaturasi.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/games.dart';
import '../../../core/i18n.dart';
import '../../../core/theme.dart';
import '../../../core/widgets.dart';

/// Qobiq o'yin ekraniga beradigan imkoniyatlar. Testda va skrinshotlarda soxta `send` bilan yaratiladi.
class GameHost {
  GameHost({
    required this.session,
    required this.send,
    required this.finish,
    ValueListenable<int?>? left,
    ValueListenable<DateTime>? clock,
    this.imageUrl = _same,
  })  : left = left ?? ValueNotifier<int?>(null),
        clock = clock ?? ValueNotifier<DateTime>(DateTime.now());

  /// `POST my/games` javobi (o'yin payloadi).
  final Map<String, dynamic> session;

  /// Bitta yurish (`answer`); xato bo'lsa null (xabarni qobiq ko'rsatadi).
  final Future<Map<String, dynamic>?> Function(Map<String, Object?> body) send;

  /// Yakunlash (`finish`); krossvord javoblarni shu yerda yuboradi.
  final Future<void> Function([Map<String, Object?> extra]) finish;

  /// Umumiy qolgan vaqt (soniya); vaqti yo'q o'yinda null.
  final ValueListenable<int?> left;

  /// Har 250 ms yangilanadigan soat — savolga vaqt beriladigan o'yinlar uchun.
  final ValueListenable<DateTime> clock;

  /// Nisbiy rasm manzili → to'liq manzil.
  final String Function(String path) imageUrl;

  /// Vaqt tugaganda yakunga qo'shiladigan javoblar (krossvord).
  Map<String, Object?> Function()? timeoutPayload;

  static String _same(String path) => path;
}

/// O'yin ekrani vidjetlari uchun umumiy asos.
abstract class GameBoard extends StatefulWidget {
  const GameBoard({super.key, required this.host});

  final GameHost host;
}

/// Javob tugmasi holati.
enum OptionState { idle, waiting, right, wrong, hidden }

/// Savol matni va rasmi (formulalar MathText bilan).
class QuestionCard extends StatelessWidget {
  const QuestionCard({super.key, required this.body, this.imageUrl, this.footer});

  final String body;
  final String? imageUrl;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        MathText(body, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.ink, height: 1.35)),
        if (imageUrl != null) ...<Widget>[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(imageUrl!, errorBuilder: (_, __, ___) => const SizedBox()),
          ),
        ],
        if (footer != null) ...<Widget>[const SizedBox(height: 12), footer!],
      ]),
    );
  }
}

/// Variant tugmasi (viktorina, millioner, omon qol, duel).
class OptionButton extends StatelessWidget {
  const OptionButton({super.key, required this.text, required this.state, required this.onTap, this.imageUrl, this.letter});

  final String text;
  final OptionState state;
  final VoidCallback? onTap;
  final String? imageUrl;
  final String? letter;

  @override
  Widget build(BuildContext context) {
    if (state == OptionState.hidden) {
      // 50/50: olib tashlangan variant joyi saqlanadi (tugmalar sakramasin).
      return Opacity(
        opacity: 0.35,
        child: _frame(AppColors.line, AppColors.card, Text(text, style: TextStyle(color: AppColors.muted, decoration: TextDecoration.lineThrough))),
      );
    }
    final color = switch (state) {
      OptionState.right => AppColors.success,
      OptionState.wrong => AppColors.danger,
      OptionState.waiting => AppColors.brand,
      _ => AppColors.line,
    };
    return Semantics(
      button: true,
      selected: state != OptionState.idle,
      child: Material(
        color: state == OptionState.idle ? AppColors.card : AppColors.soft(color),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: color, width: state == OptionState.idle ? 1 : 2)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(children: <Widget>[
              if (letter != null) ...<Widget>[
                Text(letter!, style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.muted)),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  MathText(text, style: TextStyle(fontSize: 15.5, color: AppColors.ink)),
                  if (imageUrl != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Image.network(imageUrl!, height: 90, cacheHeight: 270, errorBuilder: (_, __, ___) => const SizedBox()),
                    ),
                ]),
              ),
              if (state == OptionState.right) Icon(Icons.check_circle_rounded, color: AppColors.success),
              if (state == OptionState.wrong) Icon(Icons.cancel_rounded, color: AppColors.danger),
              if (state == OptionState.waiting) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _frame(Color border, Color fill, Widget child) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(14), border: Border.all(color: border)),
        child: Row(children: <Widget>[Expanded(child: child)]),
      );
}

/// Variant holati: tanlangan, to'g'ri javob ma'lum bo'lgandan keyin.
OptionState optionState({required int id, int? picked, int? right, List<int> removed = const <int>[]}) {
  if (removed.contains(id)) return OptionState.hidden;
  if (picked == null) return OptionState.idle;
  if (right != null && right == id) return OptionState.right;
  if (picked == id) return right == null ? OptionState.waiting : OptionState.wrong;
  return OptionState.idle;
}

const List<String> optionLetters = <String>['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H'];

/// Variantlar ro'yxati.
class OptionList extends StatelessWidget {
  const OptionList({super.key, required this.question, required this.host, required this.onChoose, this.picked, this.right, this.removed = const <int>[], this.enabled = true});

  final GameQuestion question;
  final GameHost host;
  final ValueChanged<GameOption> onChoose;
  final int? picked;
  final int? right;
  final List<int> removed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      for (var i = 0; i < question.options.length; i++) ...<Widget>[
        OptionButton(
          letter: i < optionLetters.length ? optionLetters[i] : null,
          text: question.options[i].body,
          imageUrl: question.options[i].imageUrl == null ? null : host.imageUrl(question.options[i].imageUrl!),
          state: optionState(id: question.options[i].id, picked: picked, right: right, removed: removed),
          onTap: !enabled || picked != null || removed.contains(question.options[i].id) ? null : () => onChoose(question.options[i]),
        ),
        const SizedBox(height: 8),
      ],
    ]);
  }
}

/// «3 / 15» va jarayon chizig'i.
class GameProgress extends StatelessWidget {
  const GameProgress({super.key, required this.value, required this.total, required this.label, this.trailing});

  final int value;
  final int total;
  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      Row(children: <Widget>[
        Expanded(child: Text(label, style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600))),
        if (trailing != null) trailing!,
      ]),
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(value: total == 0 ? 0 : (value / total).clamp(0, 1).toDouble(), minHeight: 6, backgroundColor: AppColors.line),
      ),
    ]);
  }
}

/// Savolga qolgan vaqt (soniya) — 5 soniyadan kam qolsa qizil.
class SecondsBadge extends StatelessWidget {
  const SecondsBadge({super.key, required this.seconds});

  final int seconds;

  @override
  Widget build(BuildContext context) {
    final low = seconds <= 5;
    return Semantics(
      label: tr('Qolgan vaqt: {0}', <Object?>['$seconds']),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: low ? AppColors.soft(AppColors.danger) : AppColors.soft(AppColors.muted), borderRadius: BorderRadius.circular(10)),
        child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Icon(Icons.timer_outlined, size: 16, color: low ? AppColors.danger : AppColors.ink),
          const SizedBox(width: 4),
          Text('$seconds',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                color: low ? AppColors.danger : AppColors.ink,
              )),
        ]),
      ),
    );
  }
}

/// Javobdan keyingi qisqa natija qatori (to'g'ri / xato + to'g'ri javob).
class FeedbackBar extends StatelessWidget {
  const FeedbackBar({super.key, required this.correct, required this.text, this.action});

  final bool correct;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final color = correct ? AppColors.success : AppColors.danger;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        decoration: BoxDecoration(color: AppColors.soft(color), borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withAlpha(90))),
        child: Row(children: <Widget>[
          Icon(correct ? Icons.check_circle_rounded : Icons.cancel_rounded, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink))),
          if (action != null) action!,
        ]),
      ),
    );
  }
}

/// Raqam klaviaturasi (matematik sprint, ketma-ketlik): telefonda tizim klaviaturasidan tezroq.
class NumberPad extends StatelessWidget {
  const NumberPad({super.key, required this.value, required this.onChanged, required this.onSubmit, this.enabled = true});

  final String value;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmit;
  final bool enabled;

  void _press(String key) {
    if (!enabled) return;
    if (key == 'del') {
      if (value.isNotEmpty) onChanged(value.substring(0, value.length - 1));
    } else if (key == '−') {
      onChanged(value.startsWith('−') ? value.substring(1) : '−$value');
    } else if (value.replaceAll('−', '').length < 9) {
      onChanged('$value$key');
    }
  }

  @override
  Widget build(BuildContext context) {
    const rows = <List<String>>[
      <String>['1', '2', '3'],
      <String>['4', '5', '6'],
      <String>['7', '8', '9'],
      <String>['−', '0', 'del'],
    ];
    return Column(children: <Widget>[
      for (final row in rows)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: <Widget>[
            for (var i = 0; i < row.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 54,
                  child: OutlinedButton(
                    onPressed: enabled ? () => _press(row[i]) : null,
                    style: OutlinedButton.styleFrom(padding: EdgeInsets.zero, backgroundColor: AppColors.card),
                    child: row[i] == 'del'
                        ? Icon(Icons.backspace_outlined, color: AppColors.ink, semanticLabel: tr("O'chirish"))
                        : Text(row[i], style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.ink)),
                  ),
                ),
              ),
            ],
          ]),
        ),
      SizedBox(
        width: double.infinity,
        height: 52,
        child: FilledButton.icon(
          onPressed: enabled && value.replaceAll('−', '').isNotEmpty ? onSubmit : null,
          icon: const Icon(Icons.keyboard_return_rounded),
          label: Text(tr('Javob berish'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
      ),
    ]);
  }
}

/// Javob ko'rsatilgandan keyin keyingi savolga o'tish uchun kichik kutish.
Future<void> gamePause(Duration duration) => Future<void>.delayed(duration);

/// Davriy taymer (dispose bilan bekor qilinadi).
Timer gameTicker(VoidCallback tick) => Timer.periodic(const Duration(milliseconds: 250), (_) => tick());
