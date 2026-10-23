// Savollar bankidan o'yinlar: viktorina-blits, to'g'ri yoki noto'g'ri, millioner, omon qol, duel.
// To'g'ri variant faqat javobdan keyin serverdan keladi.
import 'package:flutter/material.dart';

import '../../../core/api.dart';
import '../../../core/games.dart';
import '../../../core/i18n.dart';
import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import 'game_host.dart';

const Duration _rightPause = Duration(milliseconds: 650);
const Duration _wrongPause = Duration(milliseconds: 1300);

// --- Viktorina-blits -------------------------------------------------------

class QuizBoard extends GameBoard {
  const QuizBoard({super.key, required super.host});

  @override
  State<QuizBoard> createState() => _QuizBoardState();
}

class _QuizBoardState extends State<QuizBoard> {
  late final QuizStart _start = QuizStart.fromJson(widget.host.session);
  int _index = 0;
  int? _picked;
  int? _right;
  int _score = 0;

  Future<void> _choose(GameQuestion question, GameOption option) async {
    if (_picked != null || widget.host.left.value == 0) return;
    setState(() => _picked = option.id);
    final data = await widget.host.send(<String, Object?>{'question_id': question.id, 'option_id': option.id});
    if (!mounted) return;
    if (data == null) {
      setState(() => _picked = null);
      return;
    }
    final result = ChoiceResult.fromJson(data);
    setState(() {
      _right = result.correctOptionId;
      if (result.correct) _score++;
    });
    await gamePause(result.correct ? _rightPause : _wrongPause);
    if (!mounted) return;
    if (_index + 1 >= _start.questions.length) {
      await widget.host.finish();
    } else {
      setState(() {
        _index++;
        _picked = null;
        _right = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_start.questions.isEmpty) return EmptyState(text: tr('Savollar topilmadi.'));
    final question = _start.questions[_index.clamp(0, _start.questions.length - 1)];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: <Widget>[
        GameProgress(
          value: _index + (_right != null ? 1 : 0),
          total: _start.questions.length,
          label: tr('{0} / {1}', <Object?>[_index + 1, _start.questions.length]),
          trailing: Pill(tr("To'g'ri: {0}", <Object?>[_score]), color: AppColors.success),
        ),
        const SizedBox(height: 16),
        QuestionCard(body: question.body, imageUrl: question.imageUrl == null ? null : widget.host.imageUrl(question.imageUrl!)),
        const SizedBox(height: 12),
        OptionList(question: question, host: widget.host, picked: _picked, right: _right, onChoose: (option) => _choose(question, option)),
      ],
    );
  }
}

// --- To'g'ri yoki noto'g'ri ------------------------------------------------

class TrueFalseBoard extends GameBoard {
  const TrueFalseBoard({super.key, required super.host});

  @override
  State<TrueFalseBoard> createState() => _TrueFalseBoardState();
}

class _TrueFalseBoardState extends State<TrueFalseBoard> {
  late final TrueFalseStart _start = TrueFalseStart.fromJson(widget.host.session);
  int _index = 0;
  int _correct = 0;
  int _wrong = 0;
  int _streak = 0;
  bool _waiting = false;
  bool? _lastOk;
  bool? _lastTruth;

  Future<void> _answer(bool value) async {
    if (_waiting || _lastOk != null || widget.host.left.value == 0) return;
    final item = _start.items[_index];
    setState(() => _waiting = true);
    final data = await widget.host.send(<String, Object?>{'item': item.id, 'value': value});
    if (!mounted) return;
    setState(() => _waiting = false);
    if (data == null) return;
    final ok = data['correct'] == true;
    setState(() {
      _lastOk = ok;
      _lastTruth = data['truth'] == true;
      _streak = asInt(data['streak']);
      ok ? _correct++ : _wrong++;
    });
    await gamePause(ok ? const Duration(milliseconds: 450) : const Duration(milliseconds: 1100));
    if (!mounted) return;
    if (_index + 1 >= _start.items.length) {
      await widget.host.finish();
    } else {
      setState(() {
        _index++;
        _lastOk = null;
        _lastTruth = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_start.items.isEmpty) return EmptyState(text: tr('Savollar topilmadi.'));
    final item = _start.items[_index.clamp(0, _start.items.length - 1)];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: <Widget>[
        Wrap(spacing: 6, runSpacing: 6, children: <Widget>[
          Pill(tr("To'g'ri: {0}", <Object?>[_correct]), color: AppColors.success),
          Pill(tr('Xatolar: {0}', <Object?>[_wrong]), color: _wrong > 0 ? AppColors.danger : AppColors.muted),
          if (_streak >= 2) Pill(tr('Seriya: {0}', <Object?>[_streak]), color: AppColors.warning),
        ]),
        const SizedBox(height: 14),
        QuestionCard(
          body: item.body,
          imageUrl: item.imageUrl == null ? null : widget.host.imageUrl(item.imageUrl!),
          footer: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.soft(AppColors.brand), borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text(tr('Javob:'), style: TextStyle(fontSize: 12.5, color: AppColors.muted, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              MathText(item.text, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.ink)),
            ]),
          ),
        ),
        const SizedBox(height: 14),
        if (_lastOk != null)
          FeedbackBar(
            correct: _lastOk!,
            text: _lastOk! ? tr("To'g'ri!") : (_lastTruth == true ? tr("Bu javob to'g'ri edi.") : tr("Bu javob noto'g'ri edi.")),
          )
        else
          Row(children: <Widget>[
            Expanded(
              child: _BigChoice(
                icon: Icons.close_rounded,
                label: tr("Noto'g'ri"),
                color: AppColors.danger,
                onTap: _waiting ? null : () => _answer(false),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _BigChoice(
                icon: Icons.check_rounded,
                label: tr("To'g'ri"),
                color: AppColors.success,
                onTap: _waiting ? null : () => _answer(true),
              ),
            ),
          ]),
        const SizedBox(height: 10),
        Text(tr('{0} / {1}', <Object?>[_index + 1, _start.items.length]), textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
      ],
    );
  }
}

class _BigChoice extends StatelessWidget {
  const _BigChoice({required this.icon, required this.label, required this.color, required this.onTap});

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.soft(color),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: color, width: 1.5)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 22),
          child: Column(children: <Widget>[
            Icon(icon, color: color, size: 34),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: color)),
          ]),
        ),
      ),
    );
  }
}

// --- Savolga vaqt beriladigan o'yinlar uchun umumiy holat ---------------------

mixin _QuestionTimer<T extends GameBoard> on State<T> {
  DateTime askedAt = DateTime.now();
  int get perQuestion;
  bool get answering;
  void onQuestionTimeout();

  int get questionLeft => questionSecondsLeft(perQuestion, askedAt, widget.host.clock.value);

  void _onClock() {
    if (!mounted) return;
    setState(() {});
    if (questionLeft == 0 && !answering) onQuestionTimeout();
  }

  void startTimer() {
    askedAt = DateTime.now();
    widget.host.clock.addListener(_onClock);
  }

  void stopTimer() => widget.host.clock.removeListener(_onClock);

  @override
  void dispose() {
    stopTimer();
    super.dispose();
  }
}

// --- Millioner -------------------------------------------------------------

class MillionaireBoard extends GameBoard {
  const MillionaireBoard({super.key, required super.host});

  @override
  State<MillionaireBoard> createState() => _MillionaireBoardState();
}

class _MillionaireBoardState extends State<MillionaireBoard> with _QuestionTimer<MillionaireBoard> {
  late final MillionaireStart _start = MillionaireStart.fromJson(widget.host.session);
  late GameQuestion? _question = _start.question;
  late bool _fifty = _start.fifty;
  late bool _swap = _start.swap;
  int _level = 0;
  int _prize = 0;
  List<int> _removed = <int>[];
  int? _picked;
  int? _right;
  bool _waiting = false;
  final ScrollController _ladder = ScrollController();

  @override
  int get perQuestion => _start.perQuestion;

  @override
  bool get answering => _picked != null || _waiting;

  @override
  void initState() {
    super.initState();
    startTimer();
  }

  @override
  void dispose() {
    _ladder.dispose();
    super.dispose();
  }

  @override
  void onQuestionTimeout() => _choose(null);

  Future<void> _choose(GameOption? option) async {
    final question = _question;
    if (question == null || answering) return;
    setState(() {
      _picked = option?.id ?? -1;
      _waiting = true;
    });
    final data = await widget.host.send(<String, Object?>{'question_id': question.id, 'option_id': option?.id});
    if (!mounted) return;
    setState(() => _waiting = false);
    if (data == null) {
      setState(() => _picked = null);
      return;
    }
    final result = ChoiceResult.fromJson(data);
    setState(() {
      _right = result.correctOptionId;
      _level = result.level;
      _prize = result.prize;
    });
    await gamePause(result.correct ? _rightPause : _wrongPause);
    if (!mounted) return;
    if (result.over || result.next == null) {
      stopTimer();
      await widget.host.finish();
      return;
    }
    setState(() {
      _question = result.next;
      _picked = null;
      _right = null;
      _removed = <int>[];
      askedAt = DateTime.now();
    });
    _scrollLadder();
  }

  void _scrollLadder() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_ladder.hasClients) return;
      final target = (_level * 82.0 - 120).clamp(0.0, _ladder.position.maxScrollExtent);
      _ladder.animateTo(target, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    });
  }

  Future<void> _lifeline(String action) async {
    if (answering) return;
    setState(() => _waiting = true);
    final data = await widget.host.send(<String, Object?>{'action': action});
    if (!mounted) return;
    setState(() => _waiting = false);
    if (data == null) return;
    setState(() {
      final lifelines = asMap(data['lifelines']);
      _fifty = lifelines['fifty'] == true;
      _swap = lifelines['swap'] == true;
      if (action == 'fifty') {
        _removed = asRawList(data['remove']).map(asInt).toList();
      } else {
        _question = GameQuestion.maybe(data['question']) ?? _question;
        _removed = <int>[];
        askedAt = DateTime.now();
      }
    });
  }

  Future<void> _walk() async {
    if (answering) return;
    final prize = millionaireWalkPrize(_start.ladder, _level);
    final ok = await confirm(context, tr("O'yinni to'xtatib, {0} ballni olasizmi?", <Object?>[prize]), action: tr("To'xtash"));
    if (!ok || !mounted) return;
    setState(() => _waiting = true);
    final data = await widget.host.send(<String, Object?>{'action': 'walk'});
    if (!mounted) return;
    setState(() => _waiting = false);
    if (data != null) {
      stopTimer();
      await widget.host.finish();
    }
  }

  @override
  Widget build(BuildContext context) {
    final question = _question;
    if (question == null) return EmptyState(text: tr('Savollar topilmadi.'));
    final ladder = _start.ladder;
    return Column(children: <Widget>[
      SizedBox(
        height: 52,
        child: ListView.separated(
          controller: _ladder,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          itemCount: ladder.length,
          separatorBuilder: (_, __) => const SizedBox(width: 6),
          itemBuilder: (context, i) {
            final current = i == _level;
            final passed = i < _level;
            final safe = _start.safe.contains(i);
            return Semantics(
              label: '${i + 1}: ${ladder[i]}${safe ? ' (${tr('kafolatlangan')})' : ''}',
              selected: current,
              child: Container(
                width: 76,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: current ? AppColors.brand : (passed ? AppColors.soft(AppColors.success) : AppColors.card),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: current ? AppColors.brand : (safe ? AppColors.warning : AppColors.line)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                  Text(
                    '${ladder[i]}',
                    style: TextStyle(
                      fontWeight: current || safe ? FontWeight.w800 : FontWeight.w600,
                      fontSize: 13,
                      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                      color: current ? AppColors.onBrand : (passed ? AppColors.success : AppColors.ink),
                    ),
                  ),
                  // Kafolatlangan bosqich belgisi (yulduzcha shriftga bog'liq emas — ikonka).
                  if (safe) Icon(Icons.star_rounded, size: 13, color: current ? AppColors.onBrand : AppColors.warning),
                ]),
              ),
            );
          },
        ),
      ),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: <Widget>[
            Row(children: <Widget>[
              Expanded(
                child: Text(
                  tr('{0}-savol · {1} ball uchun', <Object?>[_level + 1, _level < ladder.length ? ladder[_level] : _prize]),
                  style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600),
                ),
              ),
              SecondsBadge(seconds: questionLeft),
            ]),
            const SizedBox(height: 12),
            QuestionCard(body: question.body, imageUrl: question.imageUrl == null ? null : widget.host.imageUrl(question.imageUrl!)),
            const SizedBox(height: 12),
            OptionList(question: question, host: widget.host, picked: _picked, right: _right, removed: _removed, enabled: !_waiting, onChoose: _choose),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
              OutlinedButton(onPressed: _fifty && !answering ? () => _lifeline('fifty') : null, child: const Text('50/50')),
              OutlinedButton.icon(
                onPressed: _swap && !answering ? () => _lifeline('swap') : null,
                icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                label: Text(tr('Almashtirish')),
              ),
              OutlinedButton.icon(
                onPressed: answering ? null : _walk,
                icon: const Icon(Icons.flag_outlined, size: 18),
                label: Text(tr("To'xtash ({0})", <Object?>[millionaireWalkPrize(ladder, _level)])),
              ),
            ]),
          ],
        ),
      ),
    ]);
  }
}

// --- Omon qol --------------------------------------------------------------

class SurvivalBoard extends GameBoard {
  const SurvivalBoard({super.key, required super.host});

  @override
  State<SurvivalBoard> createState() => _SurvivalBoardState();
}

class _SurvivalBoardState extends State<SurvivalBoard> with _QuestionTimer<SurvivalBoard> {
  late final SurvivalStart _start = SurvivalStart.fromJson(widget.host.session);
  late GameQuestion? _question = _start.question;
  late int _lives = _start.lives;
  int _passed = 0;
  int? _picked;
  int? _right;
  bool _waiting = false;

  @override
  int get perQuestion => _start.perQuestion;

  @override
  bool get answering => _picked != null || _waiting;

  @override
  void initState() {
    super.initState();
    startTimer();
  }

  @override
  void onQuestionTimeout() => _choose(null);

  Future<void> _choose(GameOption? option) async {
    final question = _question;
    if (question == null || answering) return;
    setState(() {
      _picked = option?.id ?? -1;
      _waiting = true;
    });
    final data = await widget.host.send(<String, Object?>{'question_id': question.id, 'option_id': option?.id});
    if (!mounted) return;
    setState(() => _waiting = false);
    if (data == null) {
      setState(() => _picked = null);
      return;
    }
    final result = ChoiceResult.fromJson(data);
    setState(() {
      _right = result.correctOptionId;
      _lives = result.lives ?? _lives;
      if (result.correct) _passed++;
    });
    await gamePause(result.correct ? _rightPause : _wrongPause);
    if (!mounted) return;
    if (result.over || result.next == null) {
      stopTimer();
      await widget.host.finish();
      return;
    }
    setState(() {
      _question = result.next;
      _picked = null;
      _right = null;
      askedAt = DateTime.now();
    });
  }

  @override
  Widget build(BuildContext context) {
    final question = _question;
    if (question == null) return EmptyState(text: tr('Savollar topilmadi.'));
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: <Widget>[
        Row(children: <Widget>[
          Semantics(
            label: tr('Jonlar: {0}', <Object?>[_lives]),
            child: Row(children: <Widget>[
              for (var i = 0; i < _start.lives; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 2),
                  child: Icon(i < _lives ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: i < _lives ? AppColors.danger : AppColors.muted, size: 26),
                ),
            ]),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(tr("O'tildi: {0}", <Object?>[_passed]), style: const TextStyle(fontWeight: FontWeight.w700))),
          SecondsBadge(seconds: questionLeft),
        ]),
        const SizedBox(height: 14),
        QuestionCard(body: question.body, imageUrl: question.imageUrl == null ? null : widget.host.imageUrl(question.imageUrl!)),
        const SizedBox(height: 12),
        OptionList(question: question, host: widget.host, picked: _picked, right: _right, enabled: !_waiting, onChoose: _choose),
      ],
    );
  }
}

// --- Duel ------------------------------------------------------------------

class DuelBoard extends GameBoard {
  const DuelBoard({super.key, required super.host});

  @override
  State<DuelBoard> createState() => _DuelBoardState();
}

class _DuelBoardState extends State<DuelBoard> with _QuestionTimer<DuelBoard> {
  late final DuelStart _start = DuelStart.fromJson(widget.host.session);
  int _index = 0;
  int _mine = 0;
  int _theirs = 0;
  int? _picked;
  int? _right;
  bool _waiting = false;
  bool? _opponentOk;

  @override
  int get perQuestion => _start.perQuestion;

  @override
  bool get answering => _picked != null || _waiting;

  @override
  void initState() {
    super.initState();
    startTimer();
  }

  @override
  void onQuestionTimeout() => _choose(null);

  Future<void> _choose(GameOption? option) async {
    if (answering || _index >= _start.questions.length) return;
    final question = _start.questions[_index];
    setState(() {
      _picked = option?.id ?? -1;
      _waiting = true;
    });
    final data = await widget.host.send(<String, Object?>{'question_id': question.id, 'option_id': option?.id});
    if (!mounted) return;
    setState(() => _waiting = false);
    if (data == null) {
      setState(() => _picked = null);
      return;
    }
    final result = ChoiceResult.fromJson(data);
    setState(() {
      _right = result.correctOptionId;
      _mine += result.points;
      _theirs += result.opponentPoints;
      _opponentOk = result.opponentCorrect;
    });
    await gamePause(const Duration(milliseconds: 1200));
    if (!mounted) return;
    if (_index + 1 >= _start.questions.length) {
      stopTimer();
      await widget.host.finish();
      return;
    }
    setState(() {
      _index++;
      _picked = null;
      _right = null;
      _opponentOk = null;
      askedAt = DateTime.now();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_start.questions.isEmpty) return EmptyState(text: tr('Savollar topilmadi.'));
    final question = _start.questions[_index.clamp(0, _start.questions.length - 1)];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: <Widget>[
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: <Widget>[
            Expanded(child: _DuelSide(name: tr('Siz'), score: _mine, color: AppColors.brand)),
            Text(tr('{0} / {1}', <Object?>[_index + 1, _start.questions.length]), style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700)),
            Expanded(
              child: _DuelSide(
                name: _start.bot ? '${_start.opponent} (${tr('bot')})' : _start.opponent,
                score: _theirs,
                color: AppColors.warning,
                end: true,
                mark: _opponentOk,
              ),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        Row(children: <Widget>[
          Expanded(child: Text(tr("Tez va to'g'ri javob — ko'proq ball."), style: TextStyle(color: AppColors.muted, fontSize: 13))),
          SecondsBadge(seconds: questionLeft),
        ]),
        const SizedBox(height: 12),
        QuestionCard(body: question.body, imageUrl: question.imageUrl == null ? null : widget.host.imageUrl(question.imageUrl!)),
        const SizedBox(height: 12),
        OptionList(question: question, host: widget.host, picked: _picked, right: _right, enabled: !_waiting, onChoose: _choose),
      ],
    );
  }
}

class _DuelSide extends StatelessWidget {
  const _DuelSide({required this.name, required this.score, required this.color, this.end = false, this.mark});

  final String name;
  final int score;
  final Color color;
  final bool end;
  final bool? mark;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: end ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: <Widget>[
      Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
      Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
        if (mark != null && end) ...<Widget>[
          Icon(mark! ? Icons.check_circle_rounded : Icons.cancel_rounded, size: 18, color: mark! ? AppColors.success : AppColors.danger),
          const SizedBox(width: 4),
        ],
        Text('$score',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: color, fontFeatures: const <FontFeature>[FontFeature.tabularFigures()])),
      ]),
    ]);
  }
}
