// O'quvchi testlari: ro'yxat, ilovada ishlash (taymer, javoblar darhol saqlanadi) va natija tahlili.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

const Map<String, String> _stateLabels = <String, String>{
  'open': 'Topshirish mumkin',
  'in_progress': 'Davom ettirish',
  'finished': 'Topshirilgan',
  'upcoming': 'Hali boshlanmagan',
  'closed': 'Yopilgan',
};

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
      appBar: AppBar(title: Text(tr('Testlar'))),
      body: AsyncView<List<Map<String, dynamic>>>(
        load: () async => asList(asMap(await api.get('my/exams'))['exams'], 'exams'),
        builder: (context, exams, reload) {
          if (exams.isEmpty) {
            return ListView(children: <Widget>[
              EmptyState(text: tr("Hozircha ochiq test yo'q. O'qituvchi test e'lon qilganda shu yerda ko'rinadi."))
            ]);
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
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
              ].join(' · '),
              style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ]),
        ),
        if (canTake || state == 'finished') const Icon(Icons.chevron_right, color: AppColors.muted),
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
  List<Map<String, dynamic>> _questions = <Map<String, dynamic>>[];
  final Map<int, Set<int>> _selected = <int, Set<int>>{};
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
    _start();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pages.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = asMap(await AppScope.read(context).api.post('exams/${widget.examId}/attempt'));
      final serverTime = DateTime.tryParse(asText(data['server_time']));
      _offset = serverTime == null ? Duration.zero : serverTime.difference(DateTime.now());
      _deadline = DateTime.tryParse(asText(data['deadline_at']));
      final questions = asList(data['questions'], 'questions');
      for (final question in questions) {
        _selected[asInt(question['question_id'])] =
            ((question['selected_option_ids'] as List?) ?? const <dynamic>[]).map((v) => asInt(v)).toSet();
      }
      setState(() {
        _attemptId = asInt(data['attempt_id']);
        _questions = questions;
        _loading = false;
      });
      if (_deadline != null) {
        _tick();
        _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
      }
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
      _finish(auto: true);
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
        <String, Object?>{'option_ids': (_selected[questionId] ?? <int>{}).toList()},
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
      final blank = _questions.where((q) => (_selected[asInt(q['question_id'])] ?? <int>{}).isEmpty).length;
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
              final answered = (_selected[asInt(_questions[index]['question_id'])] ?? <int>{}).isNotEmpty;
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
                    color: answered ? AppColors.brand : Colors.white,
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
    final answered = _questions.where((q) => (_selected[asInt(q['question_id'])] ?? <int>{}).isNotEmpty).length;
    final lowTime = _left != null && _left!.inSeconds < 60;
    return PopScope(
      canPop: _loading || _error != null,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await confirm(context, tr("Testdan chiqilsinmi? Javoblaringiz saqlangan, keyin davom ettirishingiz mumkin."), action: tr('Chiqish'))) {
          if (context.mounted) Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
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
                    Expanded(
                      child: PageView.builder(
                        controller: _pages,
                        itemCount: _questions.length,
                        onPageChanged: (page) => setState(() => _page = page),
                        itemBuilder: (context, index) => _QuestionView(
                          question: _questions[index],
                          total: _questions.length,
                          selected: _selected[asInt(_questions[index]['question_id'])] ?? <int>{},
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
    this.imageUrl,
  });

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
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Row(children: <Widget>[
          Text(tr('{0}-savol', <Object?>[asInt(question['number'])]),
              style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.brand)),
          const SizedBox(width: 8),
          if (multiple) Pill(tr('bir nechta javob'), color: AppColors.warning),
          const Spacer(),
          if (unsynced) const Icon(Icons.cloud_upload_outlined, size: 18, color: AppColors.muted),
        ]),
        const SizedBox(height: 10),
        MathText(asText(question['body']), style: const TextStyle(fontSize: 18, height: 1.4, color: AppColors.ink)),
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
        for (var i = 0; i < options.length; i++) ...<Widget>[
          _OptionTile(
            letter: 'ABCDE'[i.clamp(0, 4)],
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
  const _OptionTile({required this.letter, required this.body, required this.selected, required this.multiple, required this.onTap});

  final String letter;
  final String body;
  final bool selected;
  final bool multiple;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.brand.withAlpha(20) : Colors.white,
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
            Expanded(child: MathText(body, style: const TextStyle(fontSize: 16, color: AppColors.ink))),
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
      appBar: AppBar(title: Text(tr('Natija'))),
      body: AsyncView<Map<String, dynamic>>(
        load: () async => asMap(await api.get('attempts/$attemptId')),
        builder: (context, data, reload) {
          final correct = asInt(data['correct']);
          final total = correct + asInt(data['wrong']) + asInt(data['blank']);
          final review = data['review'] is List ? asList(data['review'], 'review') : <Map<String, dynamic>>[];
          final share = total == 0 ? 0.0 : correct / total;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
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
                          Text(tr("to'g'ri"), style: const TextStyle(color: AppColors.muted)),
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
              if (data['review_later'] == true) ...<Widget>[
                const SizedBox(height: 12),
                Text(tr("To'g'ri javoblar test yopilgandan keyin shu sahifada ko'rinadi."),
                    textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
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
              if (options[i]['selected'] == true) Text(tr('sizning javobingiz'), style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            ]),
          ),
        if (item['explanation'] != null && asText(item['explanation']).isNotEmpty) ...<Widget>[
          const Divider(height: 18),
          MathText(asText(item['explanation']), style: const TextStyle(color: AppColors.muted)),
        ],
      ]),
    );
  }
}
