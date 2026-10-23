// So'z to'plamlaridan o'yinlar: juftini top, xotira kartalari, so'z yig'ish, dor, tez yozish, flesh-kartalar,
// guruhlash (va sonlarni guruhlash — xuddi shu ekran). Har yurish serverda tekshiriladi.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/api.dart';
import '../../../core/games.dart';
import '../../../core/i18n.dart';
import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import 'game_host.dart';

// --- Juftini top (yopiq kartalar) -----------------------------------------------

class MatchBoard extends GameBoard {
  const MatchBoard({super.key, required super.host});

  @override
  State<MatchBoard> createState() => _MatchBoardState();
}

class _MatchBoardState extends State<MatchBoard> {
  late final MatchStart _start = MatchStart.fromJson(widget.host.session);
  final Set<String> _done = <String>{};
  final List<String> _open = <String>[];
  bool _wrong = false;
  bool _waiting = false;
  int _mistakes = 0;

  Future<void> _flip(WordCard card) async {
    if (_waiting || _done.contains(card.id) || _open.contains(card.id) || _open.length == 2) return;
    setState(() => _open.add(card.id));
    if (_open.length < 2) return;
    setState(() => _waiting = true);
    final data = await widget.host.send(<String, Object?>{'a': _open[0], 'b': _open[1]});
    if (!mounted) return;
    if (data == null) {
      setState(() {
        _open.clear();
        _waiting = false;
      });
      return;
    }
    final match = data['match'] == true;
    _mistakes = asInt(data['mistakes'], _mistakes);
    if (match) {
      setState(() {
        _done.addAll(_open);
        _open.clear();
        _waiting = false;
      });
      if (_done.length >= _start.cards.length) await widget.host.finish();
      return;
    }
    setState(() => _wrong = true);
    await gamePause(const Duration(milliseconds: 900));
    if (!mounted) return;
    setState(() {
      _open.clear();
      _wrong = false;
      _waiting = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(children: <Widget>[
          Expanded(child: Text(tr('Juftliklar: {0} / {1}', <Object?>[_done.length ~/ 2, _start.pairs]), style: const TextStyle(fontWeight: FontWeight.w700))),
          Pill(tr('Xatolar: {0}', <Object?>[_mistakes]), color: _mistakes > 0 ? AppColors.danger : AppColors.muted),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Align(alignment: Alignment.centerLeft, child: Text(tr("Atama va uning ma'nosini juftlang."), style: TextStyle(color: AppColors.muted, fontSize: 13))),
      ),
      Expanded(
        child: GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 200, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.7),
          itemCount: _start.cards.length,
          itemBuilder: (context, index) {
            final card = _start.cards[index];
            final done = _done.contains(card.id);
            final open = _open.contains(card.id);
            final visible = done || open;
            final color = done ? AppColors.success : (_wrong && open ? AppColors.danger : AppColors.brand);
            return Semantics(
              button: true,
              label: visible ? card.text : tr('Yopiq karta'),
              child: AnimatedContainer(
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
                          : Icon(Icons.help_outline_rounded, color: AppColors.onBrand),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ]);
  }
}

// --- Xotira kartalari (ochiq kartalar) -----------------------------------------

class MemoryBoard extends GameBoard {
  const MemoryBoard({super.key, required super.host});

  @override
  State<MemoryBoard> createState() => _MemoryBoardState();
}

class _MemoryBoardState extends State<MemoryBoard> {
  late final MemoryStart _start = MemoryStart.fromJson(widget.host.session);
  final Set<String> _done = <String>{};
  String? _term;
  String? _definition;
  bool _wrong = false;
  bool _waiting = false;
  int _mistakes = 0;

  Future<void> _pick({String? term, String? definition}) async {
    if (_waiting) return;
    setState(() {
      if (term != null) _term = _term == term ? null : term;
      if (definition != null) _definition = _definition == definition ? null : definition;
    });
    if (_term == null || _definition == null) return;
    setState(() => _waiting = true);
    final data = await widget.host.send(<String, Object?>{'term': _term, 'definition': _definition});
    if (!mounted) return;
    if (data == null) {
      setState(() {
        _waiting = false;
        _term = null;
        _definition = null;
      });
      return;
    }
    _mistakes = asInt(data['mistakes'], _mistakes);
    if (data['correct'] == true) {
      setState(() {
        _done
          ..add(_term!)
          ..add(_definition!);
        _term = null;
        _definition = null;
        _waiting = false;
      });
      if (_done.length >= _start.terms.length * 2) await widget.host.finish();
      return;
    }
    setState(() => _wrong = true);
    await gamePause(const Duration(milliseconds: 700));
    if (!mounted) return;
    setState(() {
      _wrong = false;
      _term = null;
      _definition = null;
      _waiting = false;
    });
  }

  Widget _tile(WordCard card, bool selected, VoidCallback onTap, {bool term = false}) {
    final done = _done.contains(card.id);
    final color = done ? AppColors.success : (selected ? (_wrong ? AppColors.danger : AppColors.brand) : AppColors.line);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: done || selected ? AppColors.soft(color) : AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: color, width: selected ? 2 : 1)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: done ? null : onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            alignment: Alignment.centerLeft,
            child: Text(
              card.text,
              style: TextStyle(
                fontWeight: term ? FontWeight.w800 : FontWeight.w500,
                fontSize: card.text.length > 40 ? 12.5 : 14,
                color: done ? AppColors.muted : AppColors.ink,
                decoration: done ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: <Widget>[
        Row(children: <Widget>[
          Expanded(child: Text(tr('Juftliklar: {0} / {1}', <Object?>[_done.length ~/ 2, _start.terms.length]), style: const TextStyle(fontWeight: FontWeight.w700))),
          Pill(tr('Xatolar: {0}', <Object?>[_mistakes]), color: _mistakes > 0 ? AppColors.danger : AppColors.muted),
        ]),
        const SizedBox(height: 4),
        Text(tr("Chapdan so'zni, o'ngdan uning ma'nosini tanlang."), style: TextStyle(color: AppColors.muted, fontSize: 13)),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Expanded(
            flex: 4,
            child: Column(children: <Widget>[
              for (final card in _start.terms) _tile(card, _term == card.id, () => _pick(term: card.id), term: true),
            ]),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 6,
            child: Column(children: <Widget>[
              for (final card in _start.definitions) _tile(card, _definition == card.id, () => _pick(definition: card.id)),
            ]),
          ),
        ]),
      ],
    );
  }
}

// --- So'z yig'ish -------------------------------------------------------------

class ScrambleBoard extends GameBoard {
  const ScrambleBoard({super.key, required super.host});

  @override
  State<ScrambleBoard> createState() => _ScrambleBoardState();
}

class _ScrambleBoardState extends State<ScrambleBoard> {
  late final ScrambleStart _start = ScrambleStart.fromJson(widget.host.session);
  int _word = 0;
  final List<int> _used = <int>[];
  WordResult? _result;
  bool _waiting = false;
  int _correct = 0;

  String get _typed {
    final letters = _start.words[_word].letters;
    return _used.map((i) => letters[i]).join();
  }

  Future<void> _check({bool skip = false}) async {
    if (_waiting || _result != null) return;
    setState(() => _waiting = true);
    final data = await widget.host.send(<String, Object?>{'index': _word, 'value': skip ? '' : _typed});
    if (!mounted) return;
    setState(() => _waiting = false);
    if (data == null) return;
    final result = WordResult.fromJson(data);
    setState(() {
      _result = result;
      if (result.correct) _correct++;
    });
  }

  Future<void> _next() async {
    if (_word + 1 >= _start.words.length) {
      await widget.host.finish();
      return;
    }
    setState(() {
      _word++;
      _used.clear();
      _result = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_start.words.isEmpty) return EmptyState(text: tr("So'zlar topilmadi."));
    final word = _start.words[_word.clamp(0, _start.words.length - 1)];
    final result = _result;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: <Widget>[
        GameProgress(
          value: _word + (result != null ? 1 : 0),
          total: _start.words.length,
          label: tr("{0}-so'z / {1}", <Object?>[_word + 1, _start.words.length]),
          trailing: Pill(tr("To'g'ri: {0}", <Object?>[_correct]), color: AppColors.success),
        ),
        const SizedBox(height: 14),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(tr("Ma'nosi"), style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
            const SizedBox(height: 4),
            Text(word.text, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.ink)),
          ]),
        ),
        const SizedBox(height: 16),
        Container(
          constraints: const BoxConstraints(minHeight: 58),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: result == null ? AppColors.brand : (result.correct ? AppColors.success : AppColors.danger), width: 1.5),
          ),
          alignment: Alignment.center,
          child: Text(
            _used.isEmpty ? tr('Harflarni bosing') : _typed,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: _used.isEmpty ? 14 : 24,
              letterSpacing: _used.isEmpty ? 0 : 3,
              fontWeight: FontWeight.w800,
              color: _used.isEmpty ? AppColors.muted : AppColors.ink,
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (result != null) ...<Widget>[
          FeedbackBar(
            correct: result.correct,
            text: result.correct ? tr("To'g'ri!") : tr("To'g'ri javob: {0}", <Object?>[result.answer]),
            action: FilledButton(onPressed: _next, child: Text(_word + 1 >= _start.words.length ? tr('Natija') : tr('Keyingisi'))),
          ),
        ] else ...<Widget>[
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (var i = 0; i < word.letters.length; i++)
                SizedBox(
                  width: 48,
                  height: 48,
                  child: FilledButton(
                    onPressed: _used.contains(i) || _waiting ? null : () => setState(() => _used.add(i)),
                    style: FilledButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(48, 48)),
                    child: Text(word.letters[i], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Row(children: <Widget>[
            IconButton.outlined(
              tooltip: tr("O'chirish"),
              onPressed: _used.isEmpty ? null : () => setState(_used.removeLast),
              icon: const Icon(Icons.backspace_outlined),
            ),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton(onPressed: _waiting ? null : () => _check(skip: true), child: Text(tr("O'tkazib yuborish")))),
            const SizedBox(width: 8),
            Expanded(child: FilledButton(onPressed: _used.isEmpty || _waiting ? null : _check, child: Text(tr('Tekshirish')))),
          ]),
        ],
      ],
    );
  }
}

// --- Dor ----------------------------------------------------------------------

class HangmanBoard extends GameBoard {
  const HangmanBoard({super.key, required super.host});

  @override
  State<HangmanBoard> createState() => _HangmanBoardState();
}

class _HangmanBoardState extends State<HangmanBoard> {
  late final HangmanStart _start = HangmanStart.fromJson(widget.host.session);
  late final List<List<String>> _masks = _start.words.map((word) => List<String>.of(word.mask)).toList();
  final Map<String, bool> _guessed = <String, bool>{};
  final FocusNode _focus = FocusNode();
  int _index = 0;
  int _misses = 0;
  String _status = 'play';
  String _answer = '';
  int _solved = 0;
  bool _waiting = false;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Future<void> _guess(String letter) async {
    if (_waiting || _status != 'play' || _guessed.containsKey(letter)) return;
    setState(() => _waiting = true);
    final data = await widget.host.send(<String, Object?>{'index': _index, 'letter': letter});
    if (!mounted) return;
    setState(() => _waiting = false);
    if (data == null) return;
    final step = HangmanStep.fromJson(data);
    setState(() {
      _guessed[letter] = step.hit;
      _apply(step);
    });
  }

  Future<void> _giveUp() async {
    if (_waiting || _status != 'play') return;
    setState(() => _waiting = true);
    final data = await widget.host.send(<String, Object?>{'index': _index, 'give_up': true});
    if (!mounted) return;
    setState(() => _waiting = false);
    if (data != null) setState(() => _apply(HangmanStep.fromJson(data)));
  }

  void _apply(HangmanStep step) {
    _masks[_index] = step.mask;
    _misses = step.misses;
    _status = step.status;
    if (step.over) {
      _answer = step.answer ?? '';
      if (step.status == 'solved') _solved++;
    }
  }

  Future<void> _next() async {
    if (_index + 1 >= _start.words.length) {
      await widget.host.finish();
      return;
    }
    setState(() {
      _index++;
      _guessed.clear();
      _misses = 0;
      _status = 'play';
      _answer = '';
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.enter && _status != 'play') {
      _next();
      return KeyEventResult.handled;
    }
    final letter = keyLetter(event.character ?? '', _start.alphabet);
    if (letter == null) return KeyEventResult.ignored;
    _guess(letter);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    if (_start.words.isEmpty) return EmptyState(text: tr("So'zlar topilmadi."));
    final word = _start.words[_index.clamp(0, _start.words.length - 1)];
    final mask = _masks[_index];
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: <Widget>[
          GameProgress(
            value: _index + (_status != 'play' ? 1 : 0),
            total: _start.words.length,
            label: tr("{0}-so'z, {1} ta", <Object?>[_index + 1, _start.words.length]),
            trailing: Pill(tr('Topildi: {0}', <Object?>[_solved]), color: AppColors.success),
          ),
          const SizedBox(height: 14),
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Row(children: <Widget>[
                Expanded(child: Text(tr("Ma'nosi"), style: TextStyle(color: AppColors.muted, fontSize: 12.5))),
                // Xatolar shkalasi: dor rasmi o'rniga bo'laklar — har xato bittasini bo'yaydi.
                Semantics(
                  label: tr('Xatolar: {0} / {1}', <Object?>[_misses, _start.misses]),
                  child: Row(children: <Widget>[
                    for (var n = 1; n <= _start.misses; n++)
                      Container(
                        width: 14,
                        height: 7,
                        margin: const EdgeInsets.only(left: 3),
                        decoration: BoxDecoration(color: n <= _misses ? AppColors.danger : AppColors.line, borderRadius: BorderRadius.circular(4)),
                      ),
                  ]),
                ),
              ]),
              const SizedBox(height: 6),
              Text(word.text, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.ink)),
              const SizedBox(height: 16),
              Semantics(
                liveRegion: true,
                label: hangmanMaskText(mask),
                child: Wrap(spacing: 6, runSpacing: 8, children: <Widget>[
                  for (final char in mask)
                    Container(
                      width: char == ' ' ? 14 : 30,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: char == ' '
                          ? null
                          : BoxDecoration(border: Border(bottom: BorderSide(color: char.isEmpty ? AppColors.line : AppColors.brand, width: 3))),
                      child: Text(char, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.ink)),
                    ),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 14),
          if (_status != 'play')
            FeedbackBar(
              correct: _status == 'solved',
              text: _status == 'solved' ? tr('Topdingiz: {0}', <Object?>[_answer]) : tr("So'z: {0}", <Object?>[_answer]),
              action: FilledButton(onPressed: _next, child: Text(_index + 1 >= _start.words.length ? tr('Natija') : tr("Keyingi so'z"))),
            )
          else ...<Widget>[
            Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: <Widget>[
              for (final letter in _start.alphabet) _LetterKey(letter: letter, state: _guessed[letter], onTap: _waiting ? null : () => _guess(letter)),
            ]),
            const SizedBox(height: 12),
            Center(child: TextButton(onPressed: _waiting ? null : _giveUp, child: Text(tr("Taslim bo'lish")))),
          ],
        ],
      ),
    );
  }
}

class _LetterKey extends StatelessWidget {
  const _LetterKey({required this.letter, required this.state, required this.onTap});

  final String letter;

  /// null — bosilmagan, true — bor, false — yo'q.
  final bool? state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final used = state != null;
    final color = state == true ? AppColors.success : AppColors.muted;
    return SizedBox(
      width: 40,
      height: 44,
      child: Material(
        color: used ? AppColors.soft(color) : AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: used ? Colors.transparent : AppColors.line)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: used ? null : onTap,
          child: Center(
            child: Text(
              letter,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: used ? color : AppColors.ink,
                decoration: state == false ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// --- Tez yozish ---------------------------------------------------------------

class TypingBoard extends GameBoard {
  const TypingBoard({super.key, required super.host});

  @override
  State<TypingBoard> createState() => _TypingBoardState();
}

class _TypingBoardState extends State<TypingBoard> {
  late final TypingStart _start = TypingStart.fromJson(widget.host.session);
  final TextEditingController _input = TextEditingController();
  final FocusNode _focus = FocusNode();
  int _index = 0;
  int _correct = 0;
  WordResult? _result;
  bool _waiting = false;

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_waiting) return;
    if (_result != null) {
      await _next();
      return;
    }
    setState(() => _waiting = true);
    final data = await widget.host.send(<String, Object?>{'index': _start.items[_index].id, 'value': _input.text.trim()});
    if (!mounted) return;
    setState(() => _waiting = false);
    if (data == null) return;
    final result = WordResult.fromJson(data);
    setState(() {
      _result = result;
      if (result.correct) _correct++;
    });
    if (result.correct) {
      await gamePause(const Duration(milliseconds: 500));
      if (mounted && _result == result) await _next();
    }
  }

  Future<void> _next() async {
    if (_index + 1 >= _start.items.length) {
      await widget.host.finish();
      return;
    }
    setState(() {
      _index++;
      _result = null;
      _input.clear();
    });
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    if (_start.items.isEmpty) return EmptyState(text: tr("So'zlar topilmadi."));
    final item = _start.items[_index.clamp(0, _start.items.length - 1)];
    final result = _result;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: <Widget>[
        GameProgress(
          value: _index + (result != null ? 1 : 0),
          total: _start.items.length,
          label: tr("{0}-so'z / {1}", <Object?>[_index + 1, _start.items.length]),
          trailing: Pill(tr("To'g'ri: {0}", <Object?>[_correct]), color: AppColors.success),
        ),
        const SizedBox(height: 14),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(tr('Tarjimasi'), style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
            const SizedBox(height: 4),
            Text(item.text, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: AppColors.ink)),
            const SizedBox(height: 6),
            Text(tr('{0} harf', <Object?>[item.length]), style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
          ]),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _input,
          focusNode: _focus,
          autofocus: true,
          enabled: result == null,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.done,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: 1),
          decoration: InputDecoration(hintText: tr("So'zni yozing")),
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 12),
        if (result != null)
          FeedbackBar(
            correct: result.correct,
            text: result.correct ? tr("To'g'ri!") : tr("To'g'ri javob: {0}", <Object?>[result.answer]),
            action: result.correct ? null : FilledButton(onPressed: _next, child: Text(_index + 1 >= _start.items.length ? tr('Natija') : tr('Keyingisi'))),
          )
        else
          Row(children: <Widget>[
            Expanded(
              child: OutlinedButton(
                onPressed: _waiting
                    ? null
                    : () {
                        _input.clear();
                        _submit();
                      },
                child: Text(tr("O'tkazib yuborish")),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: FilledButton(onPressed: _waiting ? null : _submit, child: Text(tr('Tekshirish')))),
          ]),
      ],
    );
  }
}

// --- Flesh-kartalar -----------------------------------------------------------

class FlashcardsBoard extends GameBoard {
  const FlashcardsBoard({super.key, required super.host});

  @override
  State<FlashcardsBoard> createState() => _FlashcardsBoardState();
}

class _FlashcardsBoardState extends State<FlashcardsBoard> {
  late final FlashcardsStart _start = FlashcardsStart.fromJson(widget.host.session);
  late List<int> _queue = List<int>.generate(_start.cards.length, (i) => i);
  bool _flipped = false;
  bool _waiting = false;
  int _known = 0;

  Future<void> _answer(bool known) async {
    if (_waiting || _queue.isEmpty) return;
    final card = _start.cards[_queue.first];
    setState(() => _waiting = true);
    final data = await widget.host.send(<String, Object?>{'id': card.id, 'known': known});
    if (!mounted) return;
    setState(() => _waiting = false);
    if (data == null) return;
    setState(() {
      _known = asInt(data['known'], _known);
      _queue = nextQueue(_queue, known);
      _flipped = false;
    });
    if (_queue.isEmpty || asInt(data['left'], 1) == 0) await widget.host.finish();
  }

  @override
  Widget build(BuildContext context) {
    if (_start.cards.isEmpty) return EmptyState(text: tr("So'zlar topilmadi."));
    if (_queue.isEmpty) return const Center(child: CircularProgressIndicator());
    final card = _start.cards[_queue.first];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: <Widget>[
        GameProgress(
          value: _known,
          total: _start.cards.length,
          label: tr('Bilaman: {0} / {1}', <Object?>[_known, _start.cards.length]),
          trailing: Pill(tr('Navbatda: {0}', <Object?>[_queue.length]), color: AppColors.muted),
        ),
        const SizedBox(height: 16),
        Semantics(
          button: true,
          label: _flipped ? card.body : tr("Ma'nosini ko'rish uchun bosing"),
          child: GestureDetector(
            onTap: () => setState(() => _flipped = !_flipped),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: Container(
                key: ValueKey<String>('${card.id}-$_flipped'),
                constraints: const BoxConstraints(minHeight: 240),
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: _flipped ? AppColors.soft(AppColors.brand) : AppColors.card,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _flipped ? AppColors.brand : AppColors.cardBorder, width: 1.5),
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
                  Text(card.text, textAlign: TextAlign.center, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.ink)),
                  const SizedBox(height: 14),
                  if (_flipped)
                    Text(card.body, textAlign: TextAlign.center, style: TextStyle(fontSize: 18, color: AppColors.ink, height: 1.35))
                  else
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
                      Icon(Icons.touch_app_outlined, size: 18, color: AppColors.muted),
                      const SizedBox(width: 6),
                      Text(tr("Ma'nosini ko'rish uchun bosing"), style: TextStyle(color: AppColors.muted)),
                    ]),
                ]),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(children: <Widget>[
          Expanded(
            child: SizedBox(
              height: 52,
              child: OutlinedButton.icon(
                onPressed: _waiting ? null : () => _answer(false),
                icon: Icon(Icons.replay_rounded, color: AppColors.warning),
                label: Text(tr('Bilmayman')),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 52,
              child: FilledButton.icon(onPressed: _waiting ? null : () => _answer(true), icon: const Icon(Icons.check_rounded), label: Text(tr('Bilaman'))),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Text(tr('«Bilmayman» kartalari navbat oxiriga qaytadi.'), textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
      ],
    );
  }
}

// --- Guruhlash / sonlarni guruhlash -------------------------------------------

class SortingBoard extends GameBoard {
  const SortingBoard({super.key, required super.host});

  @override
  State<SortingBoard> createState() => _SortingBoardState();
}

class _SortingBoardState extends State<SortingBoard> {
  late final SortingStart _start = SortingStart.fromJson(widget.host.session);
  int _index = 0;
  int _correct = 0;
  int _wrong = 0;
  int? _picked;
  SortResult? _result;
  bool _waiting = false;

  Future<void> _choose(SortCategory category) async {
    if (_waiting || _result != null || widget.host.left.value == 0) return;
    setState(() {
      _waiting = true;
      _picked = category.id;
    });
    final data = await widget.host.send(<String, Object?>{'item': _start.items[_index].id, 'category': category.id});
    if (!mounted) return;
    setState(() => _waiting = false);
    if (data == null) {
      setState(() => _picked = null);
      return;
    }
    final result = SortResult.fromJson(data);
    setState(() {
      _result = result;
      result.correct ? _correct++ : _wrong++;
    });
    await gamePause(result.correct ? const Duration(milliseconds: 450) : const Duration(milliseconds: 1100));
    if (!mounted) return;
    if (_index + 1 >= _start.items.length) {
      await widget.host.finish();
      return;
    }
    setState(() {
      _index++;
      _picked = null;
      _result = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_start.items.isEmpty || _start.categories.isEmpty) return EmptyState(text: tr("So'zlar topilmadi."));
    final item = _start.items[_index.clamp(0, _start.items.length - 1)];
    final result = _result;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: <Widget>[
        GameProgress(
          value: _index + (result != null ? 1 : 0),
          total: _start.items.length,
          label: tr('{0} / {1}', <Object?>[_index + 1, _start.items.length]),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
            Pill(tr("To'g'ri: {0}", <Object?>[_correct]), color: AppColors.success),
            const SizedBox(width: 6),
            Pill(tr('Xatolar: {0}', <Object?>[_wrong]), color: _wrong > 0 ? AppColors.danger : AppColors.muted),
          ]),
        ),
        const SizedBox(height: 18),
        Text(tr('Qaysi guruhga tegishli?'), textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
        const SizedBox(height: 8),
        AppCard(
          child: Container(
            constraints: const BoxConstraints(minHeight: 90),
            alignment: Alignment.center,
            child: MathText(item.text, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.ink)),
          ),
        ),
        const SizedBox(height: 16),
        for (final category in _start.categories) ...<Widget>[
          OptionButton(
            text: category.title,
            state: result == null
                ? (_picked == category.id ? OptionState.waiting : OptionState.idle)
                : (category.id == result.category ? OptionState.right : (_picked == category.id ? OptionState.wrong : OptionState.idle)),
            onTap: _waiting || result != null ? null : () => _choose(category),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}
