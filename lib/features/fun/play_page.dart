// O'yin oynasi: viktorina-blits (javob serverda tekshiriladi), «Juftini top» (xotira kartalari), «So'z yig'ish».
// POST /my/games → sessiya; quiz: POST /my/games/{id}/answer; oxirida POST /my/games/{id}/finish → ball, rekord, reyting.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'fun_labels.dart';

class PlayPage extends StatefulWidget {
  const PlayPage({super.key, required this.game, required this.id, required this.title});

  /// quiz | match | scramble
  final String game;

  /// quiz — fan id, boshqalari — so'z to'plami id.
  final int id;
  final String title;

  @override
  State<PlayPage> createState() => _PlayPageState();
}

class _PlayPageState extends State<PlayPage> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _session = <String, dynamic>{};
  Map<String, dynamic>? _result;
  bool _finishing = false;
  DateTime _started = DateTime.now();
  Timer? _ticker;
  int _elapsed = 0;

  // Viktorina
  int _index = 0;
  int? _picked;
  int? _right;
  int _score = 0;

  // Juftini top
  List<_Card> _cards = <_Card>[];
  final List<_Card> _open = <_Card>[];
  int _mistakes = 0;

  // So'z yig'ish
  int _word = 0;
  final List<String> _typed = <String>[];
  final List<int> _used = <int>[];
  final List<String> _answers = <String>[];

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  int? get _seconds => _session['seconds'] == null ? null : asInt(_session['seconds']);
  int? get _left => _seconds == null ? null : (_seconds! - _elapsed).clamp(0, 1 << 30);

  Future<void> _start() async {
    _ticker?.cancel();
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    try {
      final body = widget.game == 'quiz'
          ? <String, Object?>{'game': 'quiz', 'subject_id': widget.id}
          : <String, Object?>{'game': widget.game, 'word_set_id': widget.id};
      final data = asMap(await AppScope.read(context).api.post('my/games', body));
      if (!mounted) return;
      setState(() {
        _session = data;
        _index = 0;
        _picked = null;
        _right = null;
        _score = 0;
        _mistakes = 0;
        _open.clear();
        _cards = asList(data['cards'], 'cards')
            .map((card) => _Card(asInt(card['pair']), asText(card['text']), asText(card['side'])))
            .toList();
        _word = 0;
        _typed.clear();
        _used.clear();
        _answers
          ..clear()
          ..addAll(List<String>.filled(asList(data['words'], 'words').length, ''));
        _started = DateTime.now();
        _elapsed = 0;
        _loading = false;
      });
      _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
        if (!mounted || _result != null) return;
        setState(() => _elapsed = DateTime.now().difference(_started).inSeconds);
        if (_left == 0 && !_finishing) _finish(_extra());
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    }
  }

  Map<String, Object?> _extra() {
    if (widget.game == 'match') {
      return <String, Object?>{'mistakes': _mistakes, 'duration_ms': DateTime.now().difference(_started).inMilliseconds};
    }
    if (widget.game == 'scramble') {
      if (_typed.isNotEmpty && _word < _answers.length) _answers[_word] = _typed.join();
      return <String, Object?>{'answers': _answers};
    }
    return <String, Object?>{};
  }

  Future<void> _finish(Map<String, Object?> extra) async {
    if (_finishing || _result != null) return;
    _finishing = true;
    _ticker?.cancel();
    try {
      final data = asMap(await AppScope.read(context).api.post('my/games/${asInt(_session['session_id'])}/finish', extra));
      if (mounted) setState(() => _result = data);
    } on ApiException catch (error) {
      if (mounted) {
        showMessage(context, error.message, error: true);
        setState(() => _error = error.message);
      }
    } finally {
      _finishing = false;
    }
  }

  // --- Viktorina ---
  Future<void> _choose(Map<String, dynamic> question, int optionId) async {
    if (_picked != null || _left == 0) return;
    setState(() => _picked = optionId);
    try {
      final data = asMap(await AppScope.read(context).api.post('my/games/${asInt(_session['session_id'])}/answer', <String, Object?>{
        'question_id': asInt(question['id']),
        'option_id': optionId,
      }));
      if (!mounted) return;
      setState(() {
        _right = asInt(data['correct_option_id']);
        if (data['correct'] == true) _score++;
      });
    } on ApiException {
      if (mounted) setState(() => _right = -1);
    }
    await Future<void>.delayed(const Duration(milliseconds: 650));
    if (!mounted || _result != null) return;
    final total = asList(_session['questions'], 'questions').length;
    if (_index + 1 >= total) {
      await _finish(<String, Object?>{});
    } else {
      setState(() {
        _index++;
        _picked = null;
        _right = null;
      });
    }
  }

  // --- Juftini top ---
  void _flip(_Card card) {
    if (card.done || _open.contains(card) || _open.length == 2) return;
    setState(() => _open.add(card));
    if (_open.length < 2) return;
    final a = _open[0];
    final b = _open[1];
    if (a.pair == b.pair && a.side != b.side) {
      setState(() {
        a.done = true;
        b.done = true;
        _open.clear();
      });
      if (_cards.every((item) => item.done)) _finish(_extra());
    } else {
      setState(() => _mistakes++);
      Future<void>.delayed(const Duration(milliseconds: 900), () {
        if (mounted) setState(_open.clear);
      });
    }
  }

  // --- So'z yig'ish ---
  void _tap(String letter, int index) {
    if (_used.contains(index)) return;
    setState(() {
      _used.add(index);
      _typed.add(letter);
    });
  }

  void _back() {
    if (_typed.isEmpty) return;
    setState(() {
      _typed.removeLast();
      _used.removeLast();
    });
  }

  void _next({bool skip = false}) {
    final words = asList(_session['words'], 'words');
    _answers[_word] = skip ? '' : _typed.join();
    if (_word + 1 >= words.length) {
      _finish(<String, Object?>{'answers': _answers});
      return;
    }
    setState(() {
      _word++;
      _typed.clear();
      _used.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final left = _left;
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text(tr(gameTitleLabels[widget.game] ?? widget.game)),
          Text(widget.title, style: TextStyle(fontSize: 12.5, color: AppColors.muted, fontWeight: FontWeight.w500)),
        ]),
        actions: <Widget>[
          if (!_loading && _result == null && _session.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Row(children: <Widget>[
                  Icon(Icons.timer_outlined, size: 20, color: left != null && left <= 10 ? AppColors.danger : AppColors.ink),
                  const SizedBox(width: 4),
                  Text(clock(left ?? _elapsed),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                        color: left != null && left <= 10 ? AppColors.danger : AppColors.ink,
                      )),
                ]),
              ),
            ),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_result != null) return _ResultView(result: _result!, onAgain: _start);
    if (_session.isEmpty) return ErrorState(message: _error ?? tr("O'yinni boshlab bo'lmadi."), onRetry: _start);
    switch (widget.game) {
      case 'quiz':
        return _quiz();
      case 'match':
        return _match();
      default:
        return _scramble();
    }
  }

  Widget _quiz() {
    final questions = asList(_session['questions'], 'questions');
    if (questions.isEmpty) return EmptyState(text: tr('Savollar topilmadi.'));
    final question = questions[_index.clamp(0, questions.length - 1)];
    final api = AppScope.read(context).api;
    final options = asList(question['options'], 'options');
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: <Widget>[
        Row(children: <Widget>[
          Text(tr('{0} / {1}', <Object?>[_index + 1, questions.length]), style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600)),
          const Spacer(),
          Pill(tr("To'g'ri: {0}", <Object?>[_score]), color: AppColors.success),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(value: (_index + 1) / questions.length, minHeight: 6),
        ),
        const SizedBox(height: 16),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            MathText(asText(question['body']), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.ink)),
            if (asText(question['image_url']).isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(api.absolute(asText(question['image_url'])), errorBuilder: (_, __, ___) => const SizedBox()),
              ),
            ],
          ]),
        ),
        const SizedBox(height: 12),
        for (final option in options) ...<Widget>[
          _QuizOption(
            option: option,
            state: _optionState(asInt(option['id'])),
            imageUrl: asText(option['image_url']).isEmpty ? null : api.absolute(asText(option['image_url'])),
            onTap: () => _choose(question, asInt(option['id'])),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  /// 0 — oddiy, 1 — to'g'ri, 2 — noto'g'ri tanlangan, 3 — tanlangan (javob kutilmoqda).
  int _optionState(int id) {
    if (_picked == null) return 0;
    if (_right != null && _right == id) return 1;
    if (_picked == id) return _right == null ? 3 : 2;
    return 0;
  }

  Widget _match() {
    final done = _cards.where((card) => card.done).length ~/ 2;
    return Column(children: <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(children: <Widget>[
          Text(tr('Juftliklar: {0} / {1}', <Object?>[done, _cards.length ~/ 2]), style: const TextStyle(fontWeight: FontWeight.w700)),
          const Spacer(),
          Pill(tr('Xatolar: {0}', <Object?>[_mistakes]), color: _mistakes > 0 ? AppColors.danger : AppColors.muted),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(tr("Atama va uning ma'nosini juftlang."), style: TextStyle(color: AppColors.muted, fontSize: 13)),
      ),
      Expanded(
        child: GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.9,
          ),
          itemCount: _cards.length,
          itemBuilder: (context, index) {
            final card = _cards[index];
            final visible = card.done || _open.contains(card);
            final wrong = _open.length == 2 && _open.contains(card);
            final color = card.done ? AppColors.success : (wrong ? AppColors.danger : AppColors.brand);
            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                color: visible ? AppColors.soft(color) : AppColors.brand,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: visible ? color : AppColors.brand, width: 1.5),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _flip(card),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: visible
                        ? Text(card.text,
                            textAlign: TextAlign.center,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: card.side == 'term' ? FontWeight.w800 : FontWeight.w500,
                              color: AppColors.ink,
                              fontSize: card.text.length > 40 ? 12 : 14,
                            ))
                        : const Icon(Icons.help_outline_rounded, color: Colors.white),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ]);
  }

  Widget _scramble() {
    final words = asList(_session['words'], 'words');
    if (words.isEmpty) return EmptyState(text: tr("So'zlar topilmadi."));
    final word = words[_word.clamp(0, words.length - 1)];
    final letters = ((word['letters'] as List?) ?? const <dynamic>[]).map((item) => '$item').toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: <Widget>[
        Text(tr("{0}-so'z / {1}", <Object?>[_word + 1, words.length]), style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(tr("Ma'nosi"), style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
            const SizedBox(height: 4),
            Text(asText(word['hint']), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          ]),
        ),
        const SizedBox(height: 16),
        Container(
          constraints: const BoxConstraints(minHeight: 58),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.brand, width: 1.5),
          ),
          alignment: Alignment.center,
          child: Text(
            _typed.isEmpty ? tr('Harflarni bosing') : _typed.join(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: _typed.isEmpty ? 14 : 24,
              letterSpacing: _typed.isEmpty ? 0 : 3,
              fontWeight: FontWeight.w800,
              color: _typed.isEmpty ? AppColors.muted : AppColors.ink,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (var i = 0; i < letters.length; i++)
              SizedBox(
                width: 46,
                height: 46,
                child: FilledButton(
                  onPressed: _used.contains(i) ? null : () => _tap(letters[i], i),
                  style: FilledButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(46, 46)),
                  child: Text(letters[i], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),
        Row(children: <Widget>[
          IconButton.outlined(tooltip: tr("O'chirish"), onPressed: _typed.isEmpty ? null : _back, icon: const Icon(Icons.backspace_outlined)),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton(onPressed: () => _next(skip: true), child: Text(tr("O'tkazib yuborish")))),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton(
              onPressed: _typed.isEmpty ? null : () => _next(),
              child: Text(_word + 1 >= words.length ? tr('Yakunlash') : tr('Keyingisi')),
            ),
          ),
        ]),
      ],
    );
  }
}

class _Card {
  _Card(this.pair, this.text, this.side);

  final int pair;
  final String text;
  final String side;
  bool done = false;
}

class _QuizOption extends StatelessWidget {
  const _QuizOption({required this.option, required this.state, required this.onTap, this.imageUrl});

  final Map<String, dynamic> option;
  final int state;
  final VoidCallback onTap;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final color = state == 1
        ? AppColors.success
        : state == 2
            ? AppColors.danger
            : state == 3
                ? AppColors.brand
                : AppColors.line;
    return Material(
      color: state == 0 ? AppColors.card : AppColors.soft(color),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: color, width: state == 0 ? 1 : 2)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(children: <Widget>[
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                MathText(asText(option['body']), style: TextStyle(fontSize: 15.5, color: AppColors.ink)),
                if (imageUrl != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Image.network(imageUrl!, height: 90, errorBuilder: (_, __, ___) => const SizedBox()),
                  ),
              ]),
            ),
            if (state == 1) const Icon(Icons.check_circle_rounded, color: AppColors.success),
            if (state == 2) const Icon(Icons.cancel_rounded, color: AppColors.danger),
            if (state == 3) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          ]),
        ),
      ),
    );
  }
}

class _ResultView extends StatelessWidget {
  const _ResultView({required this.result, required this.onAgain});

  final Map<String, dynamic> result;
  final VoidCallback onAgain;

  @override
  Widget build(BuildContext context) {
    final board = asList(result['leaderboard'], 'leaderboard');
    final solutions = ((result['solutions'] as List?) ?? const <dynamic>[]).map((item) => '$item').toList();
    final best = asInt(result['best']);
    final score = asInt(result['score']);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      children: <Widget>[
        AppCard(
          child: Column(children: <Widget>[
            const Icon(Icons.emoji_events_rounded, size: 52, color: AppColors.sun),
            const SizedBox(height: 6),
            Text('$score', style: TextStyle(fontSize: 44, fontWeight: FontWeight.w900, color: AppColors.ink)),
            Text(tr('ball'), style: TextStyle(color: AppColors.muted)),
            const SizedBox(height: 10),
            Text(
              '${tr("To'g'ri: {0} / {1}", <Object?>[asInt(result['correct']), asInt(result['total'])])} · ${tr('Rekordingiz: {0}', <Object?>[best])}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (score >= best && score > 0) ...<Widget>[
              const SizedBox(height: 8),
              Pill(tr('Yangi rekord!'), color: AppColors.success),
            ],
            if (solutions.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              Text(tr("So'zlar: {0}", <Object?>[solutions.join(', ')]), textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
            ],
          ]),
        ),
        if (board.isNotEmpty) ...<Widget>[
          SectionTitle(tr('Reyting')),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(children: <Widget>[
              for (var i = 0; i < board.length; i++) ...<Widget>[
                if (i > 0) const Divider(),
                ListTile(
                  dense: true,
                  leading: Text('${i + 1}.', style: const TextStyle(fontWeight: FontWeight.w800)),
                  title: Text(asText(board[i]['name'])),
                  trailing: Text('${asInt(board[i]['score'])}', style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
              ],
            ]),
          ),
        ],
        const SizedBox(height: 20),
        FilledButton.icon(onPressed: onAgain, icon: const Icon(Icons.replay_rounded), label: Text(tr("Yana o'ynash"))),
        const SizedBox(height: 10),
        OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr("Boshqa o'yin"))),
      ],
    );
  }
}
