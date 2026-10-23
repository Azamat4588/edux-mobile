// Krossvord (javoblar yakunda tekshiriladi), matematik sprint va ketma-ketlik (har javob serverda).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/games.dart';
import '../../../core/i18n.dart';
import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import 'game_host.dart';

// --- Krossvord ----------------------------------------------------------------

/// Yashirin maydondagi belgi: o'chirish (backspace) tugmasini sezish uchun maydon hech qachon bo'sh qolmaydi.
const String _sentinel = '​';

class CrosswordBoard extends GameBoard {
  const CrosswordBoard({super.key, required super.host});

  @override
  State<CrosswordBoard> createState() => _CrosswordBoardState();
}

class _CrosswordBoardState extends State<CrosswordBoard> {
  late final CrosswordStart _start = CrosswordStart.fromJson(widget.host.session);
  late final Map<String, CrosswordCell> _cells = crosswordCells(_start.entries);
  final Map<String, String> _letters = <String, String>{};
  final TextEditingController _input = TextEditingController(text: _sentinel);
  final FocusNode _focus = FocusNode();
  late int _active = _start.entries.isEmpty ? -1 : _start.entries.first.id;
  String? _cursor;

  CrosswordEntry? get _entry {
    for (final entry in _start.entries) {
      if (entry.id == _active) return entry;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    widget.host.timeoutPayload = _payload;
    final entry = _entry;
    if (entry != null) _cursor = entryKeys(entry).first;
  }

  @override
  void dispose() {
    widget.host.timeoutPayload = null;
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  Map<String, Object?> _payload() => <String, Object?>{'answers': crosswordAnswers(_start.entries, _letters)};

  int get _filled => _cells.keys.where((key) => (_letters[key] ?? '').isNotEmpty).length;

  void _focusInput() {
    _input.value = const TextEditingValue(text: _sentinel, selection: TextSelection.collapsed(offset: 1));
    _focus.requestFocus();
    SystemChannels.textInput.invokeMethod<void>('TextInput.show');
  }

  void _selectCell(String key) {
    final cell = _cells[key];
    if (cell == null) return;
    setState(() {
      if (_cursor == key && cell.entries.length > 1) {
        _active = cell.entries.firstWhere((id) => id != _active, orElse: () => _active);
      } else if (!cell.entries.contains(_active)) {
        _active = cell.entries.first;
      }
      _cursor = key;
    });
    _focusInput();
  }

  void _selectEntry(CrosswordEntry entry) {
    final keys = entryKeys(entry);
    setState(() {
      _active = entry.id;
      _cursor = keys.firstWhere((key) => (_letters[key] ?? '').isEmpty, orElse: () => keys.first);
    });
    _focusInput();
  }

  void _onChanged(String value) {
    final entry = _entry;
    final cursor = _cursor;
    if (entry == null || cursor == null) {
      _focusInput();
      return;
    }
    if (value.isEmpty) {
      // O'chirish: katak bo'sh bo'lsa — oldingi katakka o'tib, uni tozalaydi.
      setState(() {
        if ((_letters[cursor] ?? '').isNotEmpty) {
          _letters[cursor] = '';
        } else {
          final previous = nextCell(entry, cursor, -1);
          _letters[previous] = '';
          _cursor = previous;
        }
      });
    } else {
      final typed = value.replaceAll(_sentinel, '').characters.where((char) => RegExp(r'\p{L}', unicode: true).hasMatch(char)).toList();
      if (typed.isNotEmpty) {
        setState(() {
          var key = cursor;
          for (final char in typed) {
            _letters[key] = char.toUpperCase();
            key = nextCell(entry, key);
          }
          _cursor = key;
        });
      }
    }
    _input.value = const TextEditingValue(text: _sentinel, selection: TextSelection.collapsed(offset: 1));
  }

  Future<void> _submit() async {
    if (_filled < _cells.length) {
      final ok = await confirm(context, tr("Hamma kataklar to'ldirilmagan. Yakunlaysizmi?"), action: tr('Yakunlash'));
      if (!ok) return;
    }
    await widget.host.finish(_payload());
  }

  @override
  Widget build(BuildContext context) {
    if (_start.entries.isEmpty) return EmptyState(text: tr("So'zlar topilmadi."));
    final entry = _entry;
    final active = entry == null ? const <String>{} : entryKeys(entry).toSet();
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
      children: <Widget>[
        // Tizim klaviaturasi uchun yashirin maydon.
        SizedBox(
          height: 1,
          child: Opacity(
            opacity: 0,
            child: TextField(
              controller: _input,
              focusNode: _focus,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.visiblePassword,
              textCapitalization: TextCapitalization.characters,
              onChanged: _onChanged,
              onSubmitted: (_) {
                final index = _start.entries.indexWhere((item) => item.id == _active);
                _selectEntry(_start.entries[(index + 1) % _start.entries.length]);
              },
            ),
          ),
        ),
        AppCard(
          padding: const EdgeInsets.all(8),
          child: LayoutBuilder(builder: (context, constraints) {
            final size = (constraints.maxWidth / _start.width).clamp(18.0, 44.0);
            return Center(
              child: SizedBox(
                width: size * _start.width,
                height: size * _start.height,
                child: Stack(children: <Widget>[
                  for (final entry in _cells.entries)
                    Positioned(
                      left: entry.value.x * size,
                      top: entry.value.y * size,
                      width: size,
                      height: size,
                      child: _Cell(
                        letter: _letters[entry.key] ?? '',
                        number: entry.value.n,
                        active: active.contains(entry.key),
                        cursor: entry.key == _cursor,
                        size: size,
                        label: tr('Katak {0}, {1}', <Object?>[entry.value.x + 1, entry.value.y + 1]),
                        onTap: () => _selectCell(entry.key),
                      ),
                    ),
                ]),
              ),
            );
          }),
        ),
        const SizedBox(height: 6),
        Text(tr("To'ldirildi: {0} / {1} katak", <Object?>[_filled, _cells.length]), textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 13)),
        const SizedBox(height: 10),
        if (entry != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: AppColors.soft(AppColors.brand), borderRadius: BorderRadius.circular(12)),
            child: Text.rich(TextSpan(children: <InlineSpan>[
              TextSpan(text: '${entry.n}. ', style: const TextStyle(fontWeight: FontWeight.w800)),
              TextSpan(text: entry.text),
              TextSpan(text: '  (${tr('{0} harf', <Object?>[entry.length])})', style: TextStyle(color: AppColors.muted, fontSize: 13)),
            ]), style: TextStyle(color: AppColors.ink, fontSize: 15)),
          ),
        for (final across in <bool>[true, false]) ...<Widget>[
          if (_start.entries.any((item) => item.across == across)) ...<Widget>[
            SectionTitle(across ? tr('Eniga') : tr("Bo'yiga")),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(children: <Widget>[
                for (final item in _start.entries.where((item) => item.across == across))
                  ListTile(
                    dense: true,
                    selected: item.id == _active,
                    selectedTileColor: AppColors.soft(AppColors.brand),
                    leading: Text('${item.n}.', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    minLeadingWidth: 24,
                    title: Text(item.text, style: TextStyle(color: AppColors.ink)),
                    trailing: Text('${entryKeys(item).where((key) => (_letters[key] ?? '').isNotEmpty).length}/${item.length}',
                        style: TextStyle(color: AppColors.muted, fontSize: 12)),
                    onTap: () => _selectEntry(item),
                  ),
              ]),
            ),
          ],
        ],
        const SizedBox(height: 18),
        FilledButton.icon(onPressed: _submit, icon: const Icon(Icons.fact_check_outlined), label: Text(tr('Yakunlash va tekshirish'))),
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.letter, required this.number, required this.active, required this.cursor, required this.size, required this.label, required this.onTap});

  final String letter;
  final int? number;
  final bool active;
  final bool cursor;
  final double size;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$label${letter.isEmpty ? '' : ': $letter'}',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.all(1.2),
          decoration: BoxDecoration(
            color: cursor ? AppColors.soft(AppColors.warning) : (active ? AppColors.soft(AppColors.brand) : AppColors.card),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: cursor ? AppColors.warning : (active ? AppColors.brand : AppColors.muted.withAlpha(110)), width: cursor ? 2 : 1),
          ),
          child: Stack(children: <Widget>[
            if (number != null)
              Positioned(
                left: 2,
                top: 0,
                child: Text('$number', style: TextStyle(fontSize: size * 0.26, fontWeight: FontWeight.w700, color: AppColors.muted)),
              ),
            Center(child: Text(letter, style: TextStyle(fontSize: size * 0.5, fontWeight: FontWeight.w800, color: AppColors.ink))),
          ]),
        ),
      ),
    );
  }
}

// --- Matematik sprint ---------------------------------------------------------

class MathSprintBoard extends GameBoard {
  const MathSprintBoard({super.key, required super.host});

  @override
  State<MathSprintBoard> createState() => _MathSprintBoardState();
}

class _MathSprintBoardState extends State<MathSprintBoard> {
  late final MathSprintStart _start = MathSprintStart.fromJson(widget.host.session);
  int _index = 0;
  int _correct = 0;
  int _wrong = 0;
  String _value = '';
  bool _waiting = false;
  bool? _lastOk;
  String _lastAnswer = '';

  Future<void> _submit() async {
    if (_waiting || parseGameNumber(_value) == null || widget.host.left.value == 0 || _index >= _start.problems.length) return;
    setState(() => _waiting = true);
    final data = await widget.host.send(<String, Object?>{'id': _start.problems[_index].id, 'value': _value});
    if (!mounted) return;
    setState(() => _waiting = false);
    if (data == null) return;
    final result = WordResult.fromJson(data);
    if (result.late) {
      await widget.host.finish();
      return;
    }
    setState(() {
      _lastOk = result.correct;
      _lastAnswer = result.answer;
      result.correct ? _correct++ : _wrong++;
      _value = '';
      _index++;
    });
    if (_index >= _start.problems.length) await widget.host.finish();
  }

  @override
  Widget build(BuildContext context) {
    if (_start.problems.isEmpty) return EmptyState(text: tr('Misollar topilmadi.'));
    final problem = _start.problems[_index.clamp(0, _start.problems.length - 1)];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: <Widget>[
        Row(children: <Widget>[
          Pill(tr("To'g'ri: {0}", <Object?>[_correct]), color: AppColors.success),
          const SizedBox(width: 6),
          Pill(tr('Xatolar: {0}', <Object?>[_wrong]), color: _wrong > 0 ? AppColors.danger : AppColors.muted),
          const Spacer(),
          if (_lastOk != null)
            Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
              Icon(_lastOk! ? Icons.check_circle_rounded : Icons.cancel_rounded, size: 18, color: _lastOk! ? AppColors.success : AppColors.danger),
              const SizedBox(width: 4),
              if (!_lastOk!) Text(tr("To'g'ri javob: {0}", <Object?>[_lastAnswer]), style: TextStyle(color: AppColors.danger, fontSize: 12.5, fontWeight: FontWeight.w600)),
            ]),
        ]),
        const SizedBox(height: 16),
        AppCard(
          child: Container(
            constraints: const BoxConstraints(minHeight: 96),
            alignment: Alignment.center,
            child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
              MathText(problem.text, style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: AppColors.ink)),
              const SizedBox(height: 10),
              Text(
                _value.isEmpty ? '?' : _value,
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: _value.isEmpty ? AppColors.muted : AppColors.brand, fontFeatures: const <FontFeature>[FontFeature.tabularFigures()]),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        NumberPad(value: _value, enabled: !_waiting, onChanged: (value) => setState(() => _value = value), onSubmit: _submit),
      ],
    );
  }
}

// --- Ketma-ketlik --------------------------------------------------------------

class SequenceBoard extends GameBoard {
  const SequenceBoard({super.key, required super.host});

  @override
  State<SequenceBoard> createState() => _SequenceBoardState();
}

class _SequenceBoardState extends State<SequenceBoard> {
  late final SequenceStart _start = SequenceStart.fromJson(widget.host.session);
  int _index = 0;
  int _correct = 0;
  String _value = '';
  bool _waiting = false;
  WordResult? _result;

  Future<void> _submit() async {
    if (_waiting || _result != null || parseGameNumber(_value) == null || widget.host.left.value == 0) return;
    setState(() => _waiting = true);
    final data = await widget.host.send(<String, Object?>{'id': _start.items[_index].id, 'value': _value});
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
    if (_index + 1 >= _start.items.length) {
      await widget.host.finish();
      return;
    }
    setState(() {
      _index++;
      _value = '';
      _result = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_start.items.isEmpty) return EmptyState(text: tr('Misollar topilmadi.'));
    final item = _start.items[_index.clamp(0, _start.items.length - 1)];
    final result = _result;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: <Widget>[
        GameProgress(
          value: _index + (result != null ? 1 : 0),
          total: _start.items.length,
          label: tr('{0} / {1}', <Object?>[_index + 1, _start.items.length]),
          trailing: Pill(tr("To'g'ri: {0}", <Object?>[_correct]), color: AppColors.success),
        ),
        const SizedBox(height: 16),
        Text(tr('Keyingi sonni toping'), textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
        const SizedBox(height: 8),
        AppCard(
          child: Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: <Widget>[
            for (final term in item.terms) _Term(text: term < 0 ? '−${-term}' : '$term'),
            _Term(text: result?.answer.replaceAll('-', '−') ?? (_value.isEmpty ? '?' : _value), highlight: true, ok: result?.correct),
          ]),
        ),
        const SizedBox(height: 14),
        if (result != null)
          FeedbackBar(
            correct: result.correct,
            text: result.correct ? tr("To'g'ri! {0}", <Object?>[result.explanation]) : tr("To'g'ri javob: {0}. {1}", <Object?>[result.answer, result.explanation]),
            action: FilledButton(onPressed: _next, child: Text(_index + 1 >= _start.items.length ? tr('Natija') : tr('Keyingisi'))),
          )
        else
          NumberPad(value: _value, enabled: !_waiting, onChanged: (value) => setState(() => _value = value), onSubmit: _submit),
      ],
    );
  }
}

class _Term extends StatelessWidget {
  const _Term({required this.text, this.highlight = false, this.ok});

  final String text;
  final bool highlight;
  final bool? ok;

  @override
  Widget build(BuildContext context) {
    final color = ok == null ? AppColors.brand : (ok! ? AppColors.success : AppColors.danger);
    return Container(
      constraints: const BoxConstraints(minWidth: 52),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: highlight ? AppColors.soft(color) : AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: highlight ? color : AppColors.line, width: highlight ? 2 : 1),
      ),
      child: Text(text,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: highlight ? color : AppColors.ink, fontFeatures: const <FontFeature>[FontFeature.tabularFigures()])),
    );
  }
}
