// O'yin natijasi: ball, to'g'ri javoblar, vaqt, XP (kunlik chegara izohi bilan), rekord, tahlil va reyting.
import 'package:flutter/material.dart';

import '../../../core/games.dart';
import '../../../core/i18n.dart';
import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../fun_labels.dart';

class GameResultView extends StatefulWidget {
  const GameResultView({super.key, required this.result, required this.onAgain, this.onClose, this.closeLabel});

  final GameResult result;
  final VoidCallback onAgain;

  /// «Boshqa o'yin» / «Darsga qaytish».
  final VoidCallback? onClose;
  final String? closeLabel;

  @override
  State<GameResultView> createState() => _GameResultViewState();
}

class _GameResultViewState extends State<GameResultView> {
  bool _all = false;

  static const Map<String, String> _outcomeLabels = <String, String>{
    'win': "G'alaba!",
    'draw': 'Durang',
    'lose': 'Bu safar raqib kuchliroq',
  };

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    final duel = result.duel;
    final review = result.review;
    final visible = _all ? review : review.take(8).toList();
    final facts = <String>[
      tr('Rekordingiz: {0}', <Object?>[result.best]),
      if (result.total > 0) tr("{0}% to'g'ri", <Object?>[result.percent]),
      if (duel != null) tr('{0}: {1} ball', <Object?>[duel.opponent, duel.opponentScore]),
      if (result.level != null && result.level! > 0) tr('{0}-bosqich', <Object?>[result.level]),
      if (result.bestStreak != null && result.bestStreak! > 0) tr('Eng uzun seriya: {0}', <Object?>[result.bestStreak]),
      if (result.knownFirst != null) tr('Birinchi urinishda: {0}', <Object?>[result.knownFirst]),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: <Widget>[
        AppCard(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
          child: Semantics(
            liveRegion: true,
            child: Column(children: <Widget>[
              if (duel != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    tr(_outcomeLabels[duel.outcome] ?? _outcomeLabels['lose']!),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: duel.outcome == 'win' ? AppColors.success : (duel.outcome == 'draw' ? AppColors.ink : AppColors.danger),
                    ),
                  ),
                ),
              Icon(Icons.emoji_events_rounded, size: 46, color: result.record ? AppColors.sun : AppColors.muted.withAlpha(120)),
              Text(tr('Ball'), style: TextStyle(color: AppColors.muted)),
              Text('${result.score}', style: TextStyle(fontSize: 46, fontWeight: FontWeight.w900, color: AppColors.ink, height: 1.1)),
              if (result.record) ...<Widget>[
                const SizedBox(height: 6),
                Pill(tr('Yangi rekord!'), color: AppColors.success),
              ],
              const SizedBox(height: 16),
              Row(children: <Widget>[
                _Fact(label: tr("To'g'ri"), value: result.total > 0 ? '${result.correct} / ${result.total}' : '${result.correct}'),
                const SizedBox(width: 8),
                _Fact(label: tr('Vaqt'), value: clock(result.durationMs ~/ 1000)),
                const SizedBox(width: 8),
                _Fact(label: 'XP', value: '+${result.xp}', color: result.xp > 0 ? AppColors.success : AppColors.muted),
              ]),
              const SizedBox(height: 12),
              Text(facts.join(' · '), textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 13)),
              if (result.xpCapped) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  (result.xpDailyLimit ?? 0) > 0
                      ? tr("XP har o'yin uchun bir marta beriladi, o'yinlardan kuniga eng ko'pi {0} XP.", <Object?>[result.xpDailyLimit])
                      : tr("XP har o'yin uchun bir marta beriladi."),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(onPressed: widget.onAgain, icon: const Icon(Icons.replay_rounded), label: Text(tr("Yana o'ynash"))),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: widget.onClose ?? () => Navigator.of(context).pop(),
                  child: Text(widget.closeLabel ?? tr("Boshqa o'yin")),
                ),
              ),
            ]),
          ),
        ),
        if (review.isNotEmpty) ...<Widget>[
          SectionTitle(tr('Tahlil')),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(
              result.mistakes > 0
                  ? tr("{0} ta xato — to'g'ri javoblarni ko'rib chiqing.", <Object?>[result.mistakes])
                  : tr("Hammasi to'g'ri yoki javobsiz qolgan savollar."),
              style: TextStyle(color: AppColors.muted, fontSize: 13),
            ),
          ),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(children: <Widget>[
              for (var i = 0; i < visible.length; i++) ...<Widget>[
                if (i > 0) Divider(height: 1, color: AppColors.line),
                _ReviewTile(row: visible[i]),
              ],
              if (review.length > 8)
                TextButton(
                  onPressed: () => setState(() => _all = !_all),
                  child: Text(_all ? tr('Qisqartirish') : tr("Hammasini ko'rsatish ({0})", <Object?>[review.length])),
                ),
            ]),
          ),
        ],
        if (result.leaderboard.isNotEmpty) ...<Widget>[
          SectionTitle(tr('Reyting')),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(children: <Widget>[
              for (var i = 0; i < result.leaderboard.length; i++) ...<Widget>[
                if (i > 0) Divider(height: 1, color: AppColors.line),
                Container(
                  color: result.leaderboard[i].me ? AppColors.soft(AppColors.brand) : null,
                  child: ListTile(
                    dense: true,
                    leading: Text('${i + 1}.', style: const TextStyle(fontWeight: FontWeight.w800)),
                    title: Text(
                      result.leaderboard[i].me ? '${result.leaderboard[i].name} (${tr('siz')})' : result.leaderboard[i].name,
                      style: TextStyle(fontWeight: result.leaderboard[i].me ? FontWeight.w800 : FontWeight.w500, color: AppColors.ink),
                    ),
                    trailing: Text('${result.leaderboard[i].score}', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.ink)),
                  ),
                ),
              ],
            ]),
          ),
        ],
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(12)),
        child: Column(children: <Widget>[
          Text(label, style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: color ?? AppColors.ink, fontFeatures: const <FontFeature>[FontFeature.tabularFigures()])),
        ]),
      ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({required this.row});

  final ReviewRow row;

  @override
  Widget build(BuildContext context) {
    final icon = row.ok == true ? Icons.check_circle_rounded : (row.ok == false ? Icons.cancel_rounded : Icons.schedule_rounded);
    final color = row.ok == true ? AppColors.success : (row.ok == false ? AppColors.danger : AppColors.muted);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, size: 20, color: color)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            MathText(row.body, style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 2),
            if (row.truth != null)
              Text('${tr('Javob:')} ${row.answer} — ${row.truth! ? tr("to'g'ri") : tr("noto'g'ri")}', style: TextStyle(color: AppColors.muted, fontSize: 13))
            else
              Text('${tr("To'g'ri javob:")} ${row.answer}', style: TextStyle(color: AppColors.muted, fontSize: 13)),
            if (row.value.isNotEmpty && row.ok == false) Text(tr('siz: {0}', <Object?>[row.value]), style: TextStyle(color: AppColors.danger, fontSize: 13)),
            if (row.explanation.isNotEmpty) Text(row.explanation, style: TextStyle(color: AppColors.muted, fontSize: 12)),
          ]),
        ),
      ]),
    );
  }
}
