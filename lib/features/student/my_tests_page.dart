// O'quvchi testlari: ro'yxat, ilovada ishlash (taymer, javoblar darhol saqlanadi) va natija tahlili.
import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../chat/chat_pages.dart';
import '../../core/adaptive.dart';
import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/help_links.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'certificates_page.dart';

const Map<String, String> _stateLabels = <String, String>{
  'open': 'Topshirish mumkin',
  'in_progress': 'Davom ettirish',
  'finished': 'Topshirilgan',
  'upcoming': 'Hali boshlanmagan',
  'closed': 'Yopilgan',
};

/// Ilovada hozir ochiq test sahifalari soni: test davomida AI ustoz o'chadi (server ham tekshiradi).
final ValueNotifier<int> activeTestPages = ValueNotifier<int>(0);

Color _stateColor(String state) {
  if (state == 'open' || state == 'in_progress') return AppColors.brand;
  if (state == 'finished') return AppColors.success;
  if (state == 'upcoming') return AppColors.warning;
  return AppColors.muted;
}

class MyTestsPage extends StatelessWidget {
  const MyTestsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final api = AppScope.of(context).api;
    return Scaffold(
      appBar: pageBar(context, title: Text(tr('Testlar')), actions: const <Widget>[HelpButton(HelpLinks.myTests)]),
      body: AsyncView<List<Map<String, dynamic>>>(
        load: () async => asList(asMap(await api.get('my/exams'))['exams'], 'exams'),
        cacheKey: 'my_tests',
        decode: (raw) => asList(raw),
        builder: (context, exams, reload) {
          if (exams.isEmpty) {
            return ListView(children: <Widget>[
              EmptyState(text: tr("Hozircha ochiq test yo'q. O'qituvchi test e'lon qilganda shu yerda ko'rinadi."))
            ]);
          }
          return ListView.separated(
            padding: readable(context, const EdgeInsets.all(16)),
            itemCount: exams.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) => _ExamCard(exam: exams[index], onChanged: reload),
          );
        },
      ),
    );
  }
}

class _ExamCard extends StatelessWidget {
  const _ExamCard({required this.exam, required this.onChanged});

  final Map<String, dynamic> exam;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final state = asText(exam['state']);
    final attempt = asMap(exam['attempt']);
    final color = _stateColor(state);
    final canTake = state == 'open' || state == 'in_progress';
    return AppCard(
      onTap: () async {
        if (canTake) {
          await Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => TakeTestPage(examId: asInt(exam['id']), title: asText(exam['title'])),
          ));
          await onChanged();
        } else if (state == 'finished' && attempt['id'] != null) {
          await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AttemptResultPage(attemptId: asInt(attempt['id']))));
        }
      },
      child: Row(children: <Widget>[
        Container(
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: color.withAlpha(26), borderRadius: BorderRadius.circular(12)),
          child: state == 'finished' && attempt.isNotEmpty
              ? Text('${asInt(attempt['correct'])}', style: TextStyle(fontWeight: FontWeight.w800, color: color, fontSize: 17))
              : Icon(canTake ? Icons.play_arrow_rounded : Icons.quiz_outlined, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(asText(exam['title']), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 2),
            Text(
              <String>[
                tr(_stateLabels[state] ?? state),
                if (state == 'finished' && attempt.isNotEmpty)
                  '${asInt(attempt['correct'])}/${asInt(attempt['correct']) + asInt(attempt['wrong']) + asInt(attempt['blank'])} · ${number(asDouble(attempt['score']))} ${tr('ball')}',
                if (canTake && exam['duration_minutes'] != null) tr('{0} daqiqa', <Object?>[asInt(exam['duration_minutes'])]),
                if (state == 'upcoming' && exam['starts_at'] != null) dateTime(exam['starts_at']),
              ].join(', '),
              style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ]),
        ),
        if (canTake || state == 'finished') Icon(Icons.chevron_right, color: AppColors.muted),
      ]),
    );
  }
}

class TakeTestPage extends StatefulWidget {
  const TakeTestPage({super.key, required this.examId, required this.title});

  final int examId;
  final String title;

  @override
  State<TakeTestPage> createState() => _TakeTestPageState();
}

class _TakeTestPageState extends State<TakeTestPage> {
  bool _loading = true;
  String? _error;
  int _attemptId = 0;
  List<Map<String, dynamic>> _all = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _questions = <Map<String, dynamic>>[];
  final Map<int, Set<int>> _selected = <int, Set<int>>{};
  // Ochiq javob (qisqa javob yoki esse): matn darhol yoziladi, serverga biroz kechikib saqlanadi.
  final Map<int, String> _texts = <int, String>{};
  final Map<int, Timer> _textTimers = <int, Timer>{};
  // Mock imtihon bo'limlari: faqat joriy bo'lim savollari ko'rinadi, har bo'limning o'z vaqti bor.
  List<Map<String, dynamic>> _sections = <Map<String, dynamic>>[];
  int? _section;
  bool _advancing = false;
  final Set<int> _unsynced = <int>{};
  final PageController _pages = PageController();
  int _page = 0;
  DateTime? _deadline;
  Duration _offset = Duration.zero;
  Timer? _timer;
  Duration? _left;
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    activeTestPages.value++;
    _start();
  }

  @override
  void dispose() {
    activeTestPages.value = activeTestPages.value > 0 ? activeTestPages.value - 1 : 0;
    _timer?.cancel();
    for (final timer in _textTimers.values) {
      timer.cancel();
    }
    _pages.dispose();
    super.dispose();
  }

  bool get _isMock => _sections.isNotEmpty;

  Map<String, dynamic> get _currentSection =>
      _sections.firstWhere((item) => asInt(item['number']) == _section, orElse: () => <String, dynamic>{});

  bool get _lastSection => !_isMock || _sections.isEmpty || asInt(_sections.last['number']) == _section;

  bool _isAnswered(Map<String, dynamic> question) {
    final id = asInt(question['question_id']);
    if (_isOpen(question)) return (_texts[id] ?? '').trim().isNotEmpty;
    return (_selected[id] ?? <int>{}).isNotEmpty;
  }

  static bool _isOpen(Map<String, dynamic> question) => question['type'] == 'text' || question['type'] == 'essay';

  /// Server javobi (yangi urinish yoki keyingi bo'lim) — holatni shundan quradi.
  void _accept(Map<String, dynamic> data) {
    final serverTime = DateTime.tryParse(asText(data['server_time']));
    _offset = serverTime == null ? Duration.zero : serverTime.difference(DateTime.now());
    final sections = data['sections'] is List ? asList(data['sections'], 'sections') : <Map<String, dynamic>>[];
    final section = data['section'] == null ? null : asInt(data['section']);
    _deadline = DateTime.tryParse(asText(section != null ? (data['section_deadline_at'] ?? data['deadline_at']) : data['deadline_at']));
    final questions = asList(data['questions'], 'questions');
    for (final question in questions) {
      final id = asInt(question['question_id']);
      _selected[id] = asRawList(question['selected_option_ids']).map((v) => asInt(v)).toSet();
      if (question['text_answer'] != null) _texts[id] = asText(question['text_answer']);
    }
    _attemptId = asInt(data['attempt_id']);
    _all = questions;
    _sections = sections;
    _section = sections.isEmpty ? null : (section ?? asInt(sections.first['number']));
    _questions = _isMock ? questions.where((q) => asInt(q['block']) == _section).toList() : questions;
    _page = 0;
    if (_pages.hasClients) _pages.jumpToPage(0);
  }

  void _setText(Map<String, dynamic> question, String value) {
    final id = asInt(question['question_id']);
    _texts[id] = value;
    _unsynced.add(id);
    _textTimers[id]?.cancel();
    _textTimers[id] = Timer(const Duration(milliseconds: 900), () => _sync(id));
    setState(() {});
  }

  /// Bo'lim vaqti tugadi yoki o'quvchi «Keyingi bo'lim» ni bosdi.
  Future<void> _nextSection({bool auto = false}) async {
    if (_advancing) return;
    if (!auto && !await confirm(context, tr("Keyingi bo'limga o'tilsinmi? Bu bo'limga qaytib bo'lmaydi."), action: tr("O'tish"))) return;
    setState(() => _advancing = true);
    for (final id in _unsynced.toList()) {
      await _sync(id);
    }
    if (!mounted) return;
    try {
      final data = asMap(await AppScope.read(context).api.post('attempts/$_attemptId/next-section', <String, Object?>{'section': _section}));
      if (!mounted) return;
      if (data['finished'] == true) {
        _timer?.cancel();
        Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => AttemptResultPage(attemptId: _attemptId)));
        return;
      }
      setState(() {
        _accept(data);
        _advancing = false;
      });
      _restartTimer();
      if (auto) showMessage(context, tr("Bo'lim vaqti tugadi. Keyingi bo'lim boshlandi."));
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _advancing = false);
      showMessage(context, error.message, error: true);
    }
  }

  void _restartTimer() {
    _timer?.cancel();
    if (_deadline != null) {
      _tick();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    }
  }

  Future<void> _start() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = asMap(await AppScope.read(context).api.post('exams/${widget.examId}/attempt'));
      setState(() {
        _accept(data);
        _loading = false;
      });
      _restartTimer();
    } on ApiException catch (error) {
      setState(() {
        _error = error.message;
        _loading = false;
      });
    }
  }

  void _tick() {
    final deadline = _deadline;
    if (deadline == null) return;
    final left = deadline.difference(DateTime.now().add(_offset));
    if (!mounted) return;
    setState(() => _left = left.isNegative ? Duration.zero : left);
    if (left.isNegative || left == Duration.zero) {
      _timer?.cancel();
      if (_isMock && !_lastSection) {
        _nextSection(auto: true);
      } else {
        _finish(auto: true);
      }
    }
  }

  Future<void> _toggle(Map<String, dynamic> question, int optionId) async {
    final id = asInt(question['question_id']);
    final multiple = question['type'] == 'multiple';
    setState(() {
      final current = _selected[id] ?? <int>{};
      if (multiple) {
        if (!current.remove(optionId)) current.add(optionId);
      } else {
        current
          ..clear()
          ..add(optionId);
      }
      _selected[id] = current;
      _unsynced.add(id);
    });
    await _sync(id);
  }

  Future<bool> _sync(int questionId) async {
    try {
      await AppScope.read(context).api.put(
        'attempts/$_attemptId/answers/$questionId',
        <String, Object?>{
          'option_ids': (_selected[questionId] ?? <int>{}).toList(),
          if (_texts.containsKey(questionId)) 'text': _texts[questionId],
        },
      );
      if (mounted) setState(() => _unsynced.remove(questionId));
      return true;
    } on ApiException catch (error) {
      if (mounted && !error.isNetwork) showMessage(context, error.message, error: true);
      return false;
    }
  }

  Future<void> _finish({bool auto = false}) async {
    if (_finishing) return;
    if (!auto) {
      final blank = _all.where((q) => !_isAnswered(q)).length;
      final text = blank > 0
          ? '${tr('{0} ta savolga javob berilmagan.', <Object?>[blank])} ${tr('Test yakunlansinmi?')}'
          : tr('Test yakunlansinmi?');
      if (!await confirm(context, '$text\n${tr("Yakunlagandan keyin javoblarni o'zgartirib bo'lmaydi.")}', action: tr('Yakunlash'))) {
        return;
      }
    }
    setState(() => _finishing = true);
    // Yuborilmay qolgan javoblar
    for (final id in _unsynced.toList()) {
      await _sync(id);
    }
    if (!mounted) return;
    try {
      await AppScope.read(context).api.post('attempts/$_attemptId/finish');
      _timer?.cancel();
      if (!mounted) return;
      if (auto) showMessage(context, tr('Vaqt tugadi. Test yakunlandi.'));
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => AttemptResultPage(attemptId: _attemptId)));
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _finishing = false);
      showMessage(
        context,
        auto ? tr("Vaqt tugadi, lekin testni yakunlab bo'lmadi. Internetni tekshirib, «Yakunlash» tugmasini bosing.") : error.message,
        error: true,
      );
    }
  }

  String _clock(Duration value) {
    final hours = value.inHours;
    final minutes = value.inMinutes % 60;
    final seconds = value.inSeconds % 60;
    return hours > 0 ? '$hours:${two(minutes)}:${two(seconds)}' : '${two(minutes)}:${two(seconds)}';
  }

  void _openGrid() {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List<Widget>.generate(_questions.length, (index) {
              final answered = _isAnswered(_questions[index]);
              return InkWell(
                onTap: () {
                  Navigator.pop(context);
                  _pages.jumpToPage(index);
                },
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: answered ? AppColors.brand : AppColors.card,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: index == _page ? AppColors.ink : AppColors.line, width: index == _page ? 2 : 1),
                  ),
                  child: Text('${index + 1}', style: TextStyle(fontWeight: FontWeight.w700, color: answered ? Colors.white : AppColors.ink)),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final api = AppScope.of(context).api;
    final answered = _questions.where(_isAnswered).length;
    final section = _currentSection;
    final lowTime = _left != null && _left!.inSeconds < 60;
    return PopScope(
      canPop: _loading || _error != null,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await confirm(context, tr('Testdan chiqilsinmi? Javoblaringiz saqlangan, keyin davom ettirishingiz mumkin.'), action: tr('Chiqish'))) {
          if (context.mounted) Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: pageBar(context,
          title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: <Widget>[
            if (_left != null)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Center(
                  child: Pill(_clock(_left!), color: lowTime ? AppColors.danger : AppColors.brand),
                ),
              ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ErrorState(message: _error!, onRetry: _start)
                : Column(children: <Widget>[
                    LinearProgressIndicator(value: _questions.isEmpty ? 0 : answered / _questions.length, minHeight: 3),
                    if (_isMock) _SectionHeader(
                      key: ValueKey<int?>(_section),
                      section: section,
                      index: _sections.indexOf(section) + 1,
                      total: _sections.length,
                      audioUrl: section['audio_url'] == null ? null : api.absolute(asText(section['audio_url'])),
                    ),
                    Expanded(
                      child: PageView.builder(
                        controller: _pages,
                        itemCount: _questions.length,
                        onPageChanged: (page) => setState(() => _page = page),
                        itemBuilder: (context, index) => _QuestionView(
                          question: _questions[index],
                          total: _questions.length,
                          selected: _selected[asInt(_questions[index]['question_id'])] ?? <int>{},
                          text: _texts[asInt(_questions[index]['question_id'])] ?? '',
                          onText: (value) => _setText(_questions[index], value),
                          api: api,
                          unsynced: _unsynced.contains(asInt(_questions[index]['question_id'])),
                          imageUrl: _questions[index]['image_url'] == null ? null : api.absolute(asText(_questions[index]['image_url'])),
                          imageHeaders: api.headers(json: false),
                          onTap: (optionId) => _toggle(_questions[index], optionId),
                        ),
                      ),
                    ),
                  ]),
        bottomNavigationBar: _loading || _error != null
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                  child: Row(children: <Widget>[
                    IconButton.outlined(
                      onPressed: _page > 0 ? () => _pages.previousPage(duration: const Duration(milliseconds: 220), curve: Curves.easeOut) : null,
                      icon: const Icon(Icons.chevron_left),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _openGrid,
                        child: Text('${_page + 1} / ${_questions.length} · ${tr('Javob berilgan')}: $answered'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (_page < _questions.length - 1)
                      IconButton.filled(
                        onPressed: () => _pages.nextPage(duration: const Duration(milliseconds: 220), curve: Curves.easeOut),
                        icon: const Icon(Icons.chevron_right),
                      )
                    else if (!_lastSection)
                      FilledButton(
                        onPressed: _advancing ? null : () => _nextSection(),
                        child: Text(tr("Keyingi bo'lim")),
                      )
                    else
                      FilledButton(
                        onPressed: _finishing ? null : () => _finish(),
                        child: _finishing
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : Text(tr('Yakunlash')),
                      ),
                  ]),
                ),
              ),
      ),
    );
  }
}

class _QuestionView extends StatelessWidget {
  const _QuestionView({
    required this.question,
    required this.total,
    required this.selected,
    required this.unsynced,
    required this.onTap,
    required this.imageHeaders,
    required this.text,
    required this.onText,
    required this.api,
    this.imageUrl,
  });

  final String text;
  final ValueChanged<String> onText;
  final Api api;

  final Map<String, dynamic> question;
  final int total;
  final Set<int> selected;
  final bool unsynced;
  final String? imageUrl;
  final Map<String, String> imageHeaders;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final options = asList(question['options'], 'options');
    final multiple = question['type'] == 'multiple';
    return ListView(
      padding: readable(context, const EdgeInsets.all(16)),
      children: <Widget>[
        Row(children: <Widget>[
          Text(tr('{0}-savol', <Object?>[asInt(question['number'])]),
              style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.brand)),
          const SizedBox(width: 8),
          if (multiple) Pill(tr('bir nechta javob'), color: AppColors.warning),
          const Spacer(),
          if (unsynced) Icon(Icons.cloud_upload_outlined, size: 18, color: AppColors.muted),
        ]),
        const SizedBox(height: 10),
        MathText(asText(question['body']), style: TextStyle(fontSize: 18, height: 1.4, color: AppColors.ink)),
        if (imageUrl != null) ...<Widget>[
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: InteractiveViewer(
              maxScale: 4,
              child: Image.network(imageUrl!, headers: imageHeaders, errorBuilder: (_, __, ___) => const SizedBox()),
            ),
          ),
        ],
        const SizedBox(height: 18),
        if (question['type'] == 'text' || question['type'] == 'essay')
          _OpenAnswer(text: text, essay: question['type'] == 'essay', onChanged: onText),
        for (var i = 0; i < options.length; i++) ...<Widget>[
          _OptionTile(
            letter: 'ABCDE'[i.clamp(0, 4)],
            imageUrl: options[i]['image_url'] == null ? null : api.absolute(asText(options[i]['image_url'])),
            imageHeaders: imageHeaders,
            body: asText(options[i]['body']),
            selected: selected.contains(asInt(options[i]['id'])),
            multiple: multiple,
            onTap: () => onTap(asInt(options[i]['id'])),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.letter,
    required this.body,
    required this.selected,
    required this.multiple,
    required this.onTap,
    this.imageUrl,
    this.imageHeaders = const <String, String>{},
  });

  final String? imageUrl;
  final Map<String, String> imageHeaders;
  final String letter;
  final String body;
  final bool selected;
  final bool multiple;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.soft(AppColors.brand) : AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: selected ? AppColors.brand : AppColors.line, width: selected ? 2 : 1),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: <Widget>[
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? AppColors.brand : AppColors.surface,
                shape: multiple ? BoxShape.rectangle : BoxShape.circle,
                borderRadius: multiple ? BorderRadius.circular(8) : null,
              ),
              child: Text(letter, style: TextStyle(fontWeight: FontWeight.w800, color: selected ? Colors.white : AppColors.ink)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                if (body.isNotEmpty) MathText(body, style: TextStyle(fontSize: 16, color: AppColors.ink)),
                if (imageUrl != null)
                  Padding(
                    padding: EdgeInsets.only(top: body.isNotEmpty ? 8 : 0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(imageUrl!, headers: imageHeaders, height: 120, cacheHeight: 360, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const SizedBox()),
                    ),
                  ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class AttemptResultPage extends StatelessWidget {
  const AttemptResultPage({super.key, required this.attemptId});

  final int attemptId;

  @override
  Widget build(BuildContext context) {
    final api = AppScope.of(context).api;
    return Scaffold(
      appBar: pageBar(context, title: Text(tr('Natija'))),
      body: AsyncView<Map<String, dynamic>>(
        load: () async => asMap(await api.get('attempts/$attemptId')),
        builder: (context, data, reload) {
          final correct = asInt(data['correct']);
          final total = correct + asInt(data['wrong']) + asInt(data['blank']);
          final review = data['review'] is List ? asList(data['review'], 'review') : <Map<String, dynamic>>[];
          final share = total == 0 ? 0.0 : correct / total;
          return ListView(
            padding: readable(context, const EdgeInsets.all(16)),
            children: <Widget>[
              // 3.13: natija bo'yicha ustozga savol (izoh) — o'quvchi, ota-ona va ustoz ko'radi.
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => ChatThreadPage.subject(context, 'attempt', attemptId),
                  icon: const Icon(Icons.comment_outlined, size: 18),
                  label: Text(tr('Ustozga savol')),
                ),
              ),
              AppCard(
                child: Column(children: <Widget>[
                  Text(asText(asMap(data['exam'])['title']), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: 140,
                    height: 140,
                    child: Stack(fit: StackFit.expand, children: <Widget>[
                      CircularProgressIndicator(
                        value: share,
                        strokeWidth: 12,
                        backgroundColor: AppColors.line,
                        color: share >= 0.7 ? AppColors.success : (share >= 0.4 ? AppColors.warning : AppColors.danger),
                      ),
                      Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                          Text('$correct/$total', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                          Text(tr("to'g'ri"), style: TextStyle(color: AppColors.muted)),
                        ]),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 16),
                  KeyValue(tr('Ball'), '${number(asDouble(data['score']))} / ${number(asDouble(data['max_score']))}'),
                  KeyValue(tr("Noto'g'ri"), '${asInt(data['wrong'])}'),
                  KeyValue(tr('Javobsiz'), '${asInt(data['blank'])}'),
                  if (data['finished_at'] != null) KeyValue(tr('Topshirildi'), dateTime(data['finished_at'])),
                ]),
              ),
              if (data['mock_result'] is Map) ...<Widget>[
                const SizedBox(height: 12),
                AppCard(child: MockResultSummary(result: asMap(data['mock_result']))),
              ] else if (asInt(data['pending']) > 0) ...<Widget>[
                const SizedBox(height: 12),
                Text(tr("{0} ta ochiq javobni o'qituvchi baholaydi — ball keyin yangilanadi.", <Object?>[asInt(data['pending'])]),
                    textAlign: TextAlign.center, style: TextStyle(color: AppColors.warning)),
              ],
              if (data['review_later'] == true) ...<Widget>[
                const SizedBox(height: 12),
                Text(tr("To'g'ri javoblar test yopilgandan keyin shu sahifada ko'rinadi."),
                    textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
              ],
              if (review.isNotEmpty) ...<Widget>[
                SectionTitle(tr('Javoblar tahlili')),
                for (final item in review) ...<Widget>[
                  _ReviewCard(item: item, api: api),
                  const SizedBox(height: 10),
                ],
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.item, required this.api});

  final Map<String, dynamic> item;
  final Api api;

  @override
  Widget build(BuildContext context) {
    final ok = item['is_correct'] == true;
    final options = asList(item['options'], 'options');
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Row(children: <Widget>[
          Icon(ok ? Icons.check_circle : Icons.cancel, color: ok ? AppColors.success : AppColors.danger, size: 20),
          const SizedBox(width: 6),
          Text(tr('{0}-savol', <Object?>[asInt(item['number'])]), style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 8),
        if (asText(item['body']).isNotEmpty) MathText(asText(item['body'])),
        if (item['image_url'] != null) ...<Widget>[
          const SizedBox(height: 8),
          Image.network(api.absolute(asText(item['image_url'])), headers: api.headers(json: false), errorBuilder: (_, __, ___) => const SizedBox()),
        ],
        const SizedBox(height: 8),
        if (item['type'] == 'text' || item['type'] == 'essay') ...<Widget>[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(10)),
            child: Text(asText(item['text_answer'], tr('Javob yozilmagan')), style: TextStyle(color: AppColors.ink)),
          ),
          if (item['accepted_answers'] is List && (item['accepted_answers'] as List).isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Text('${tr("To'g'ri javob")}: ${(item['accepted_answers'] as List).join(' / ')}', style: TextStyle(color: AppColors.success)),
          ],
          if (item['type'] == 'essay')
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                item['graded'] == true ? '${tr('Ball')}: ${number(asDouble(item['points']))}' : tr("O'qituvchi hali baholamagan"),
                style: TextStyle(fontWeight: FontWeight.w600, color: item['graded'] == true ? AppColors.brand : AppColors.warning),
              ),
            ),
          if (asText(item['feedback']).isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('${tr("O'qituvchi izohi")}: ${asText(item['feedback'])}', style: TextStyle(color: AppColors.muted)),
            ),
        ],
        for (var i = 0; i < options.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: <Widget>[
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: options[i]['is_correct'] == true
                      ? AppColors.success
                      : (options[i]['selected'] == true ? AppColors.danger : AppColors.surface),
                ),
                child: Text('ABCDE'[i.clamp(0, 4)],
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: options[i]['is_correct'] == true || options[i]['selected'] == true ? Colors.white : AppColors.ink,
                    )),
              ),
              const SizedBox(width: 10),
              Expanded(child: MathText(asText(options[i]['body']))),
              if (options[i]['selected'] == true) Text(tr('sizning javobingiz'), style: TextStyle(color: AppColors.muted, fontSize: 12)),
            ]),
          ),
        if (item['explanation'] != null && asText(item['explanation']).isNotEmpty) ...<Widget>[
          const Divider(height: 18),
          MathText(asText(item['explanation']), style: TextStyle(color: AppColors.muted)),
        ],
      ]),
    );
  }
}


/// Ochiq javob: qisqa (bir qator) yoki esse (ko'p qator, so'zlar soni bilan).
class _OpenAnswer extends StatefulWidget {
  const _OpenAnswer({required this.text, required this.essay, required this.onChanged});

  final String text;
  final bool essay;
  final ValueChanged<String> onChanged;

  @override
  State<_OpenAnswer> createState() => _OpenAnswerState();
}

class _OpenAnswerState extends State<_OpenAnswer> {
  late final TextEditingController _controller = TextEditingController(text: widget.text);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final words = _controller.text.trim().isEmpty ? 0 : _controller.text.trim().split(RegExp(r'\s+')).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.end, children: <Widget>[
      TextField(
        controller: _controller,
        minLines: widget.essay ? 8 : 1,
        maxLines: widget.essay ? 20 : 2,
        maxLength: widget.essay ? 20000 : 500,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(hintText: widget.essay ? tr('Javobingizni shu yerga yozing') : tr('Javob'), counterText: ''),
        onChanged: (value) {
          setState(() {});
          widget.onChanged(value);
        },
      ),
      if (widget.essay) Padding(padding: const EdgeInsets.only(top: 6), child: Text(tr('{0} ta so\'z', <Object?>[words]), style: TextStyle(color: AppColors.muted, fontSize: 12))),
    ]);
  }
}

/// Mock bo'limi sarlavhasi: nomi, ko'rsatma, o'qish matni (Reading) va audio (Listening — bir marta eshittiriladi).
class _SectionHeader extends StatefulWidget {
  const _SectionHeader({super.key, required this.section, required this.index, required this.total, this.audioUrl});

  final Map<String, dynamic> section;
  final int index;
  final int total;
  final String? audioUrl;

  @override
  State<_SectionHeader> createState() => _SectionHeaderState();
}

class _SectionHeaderState extends State<_SectionHeader> {
  final AudioPlayer _player = AudioPlayer();
  bool _played = false;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _player.onPositionChanged.listen((value) {
      if (mounted) setState(() => _position = value);
    });
    _player.onDurationChanged.listen((value) {
      if (mounted) setState(() => _duration = value);
    });
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _play() async {
    final url = widget.audioUrl;
    if (url == null || _played) return;
    setState(() {
      _played = true;
      _playing = true;
    });
    await _player.play(UrlSource(url));
  }

  void _passage() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        builder: (context, controller) => ListView(controller: controller, padding: const EdgeInsets.all(20), children: <Widget>[
          Text(asText(widget.section['name']), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          SelectableText(asText(widget.section['passage']), style: TextStyle(fontSize: 16, height: 1.55, color: AppColors.ink)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final section = widget.section;
    final instructions = asText(section['instructions']);
    final hasPassage = asText(section['passage']).trim().isNotEmpty;
    final progress = _duration.inMilliseconds == 0 ? 0.0 : _position.inMilliseconds / _duration.inMilliseconds;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.soft(AppColors.brand), borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Row(children: <Widget>[
          Expanded(child: Text(asText(section['name']), style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.ink))),
          Text('${widget.index}/${widget.total}', style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600)),
        ]),
        if (instructions.isNotEmpty) ...<Widget>[
          const SizedBox(height: 4),
          Text(instructions, style: TextStyle(color: AppColors.muted, fontSize: 13)),
        ],
        if (hasPassage || widget.audioUrl != null) const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: <Widget>[
          if (hasPassage) OutlinedButton.icon(onPressed: _passage, icon: const Icon(Icons.article_outlined), label: Text(tr('Matnni ochish'))),
          if (widget.audioUrl != null)
            FilledButton.icon(
              onPressed: _played ? null : _play,
              icon: Icon(_playing ? Icons.graphic_eq : Icons.play_arrow),
              label: Text(_played ? (_playing ? tr('Eshittirilmoqda...') : tr('Audio tugadi')) : tr('Audioni boshlash')),
            ),
        ]),
        if (widget.audioUrl != null && _played) ...<Widget>[
          const SizedBox(height: 8),
          LinearProgressIndicator(value: progress.clamp(0.0, 1.0), minHeight: 4, borderRadius: BorderRadius.circular(4)),
          const SizedBox(height: 4),
          Text(tr('Audio faqat bir marta eshittiriladi.'), style: TextStyle(color: AppColors.muted, fontSize: 12)),
        ],
      ]),
    );
  }
}
