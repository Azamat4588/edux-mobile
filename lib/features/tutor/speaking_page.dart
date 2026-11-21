// 3.35: «AI speaking» (o'quvchi, server 2.90): IELTS Speaking, CEFR (Multilevel) yoki erkin suhbat mashqi.
// Javob — matn (telefon klaviaturasidagi mikrofon bilan diktovka qilish mumkin); har javobga AI izohi va keyingi savol,
// yakunda taxminiy ball. API: ai/speaking, ai/speaking/{id}, .../answer, .../finish.
import 'package:flutter/material.dart';

import '../../core/adaptive.dart';
import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

const Map<String, String> speakingCriteriaLabels = <String, String>{
  'fluency': 'Ravonlik va izchillik',
  'lexical': "So'z boyligi",
  'grammar': 'Grammatika',
};

class SpeakingPage extends StatefulWidget {
  const SpeakingPage({super.key});

  @override
  State<SpeakingPage> createState() => _SpeakingPageState();
}

class _SpeakingPageState extends State<SpeakingPage> {
  Map<String, dynamic>? _info;
  Map<String, dynamic>? _session;
  Object? _error;
  String _exam = 'ielts';
  int _part = 1;
  String _busy = '';
  String _feedback = '';
  final _topic = TextEditingController();
  final _answer = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _topic.dispose();
    _answer.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final info = asMap(await AppScope.read(context).api.get('ai/speaking'));
      if (mounted) setState(() => _info = info);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _run(String busy, Future<void> Function() action) async {
    setState(() => _busy = busy);
    try {
      await action();
    } catch (error) {
      if (mounted) showMessage(context, errorText(error), error: true);
    } finally {
      if (mounted) setState(() => _busy = '');
    }
  }

  Future<void> _start() => _run('start', () async {
        final api = AppScope.read(context).api;
        final topic = _topic.text.trim();
        final session = asMap(await api.post('ai/speaking', <String, Object?>{'exam': _exam, 'part': _part, 'topic': topic.isEmpty ? null : topic}));
        if (mounted) {
          setState(() {
            _session = session;
            _feedback = '';
          });
        }
      });

  Future<void> _open(int id) => _run('open', () async {
        final session = asMap(await AppScope.read(context).api.get('ai/speaking/$id'));
        if (mounted) {
          setState(() {
            _session = session;
            _feedback = '';
          });
        }
      });

  Future<void> _send() async {
    final text = _answer.text.trim();
    if (text.length < 2 || _session == null) return;
    await _run('answer', () async {
      final data = asMap(await AppScope.read(context).api.post('ai/speaking/${asInt(_session!['id'])}/answer', <String, Object?>{'text': text}));
      if (mounted) {
        setState(() {
          _session = asMap(data['session']);
          _feedback = asText(data['feedback']);
          _answer.clear();
        });
      }
    });
  }

  Future<void> _finish() => _run('finish', () async {
        final session = asMap(await AppScope.read(context).api.post('ai/speaking/${asInt(_session!['id'])}/finish'));
        if (mounted) setState(() => _session = session);
        await _load();
      });

  @override
  Widget build(BuildContext context) {
    final info = _info;
    final session = _session;
    Widget body;
    if (_error != null && info == null) {
      body = ErrorState(message: errorText(_error), onRetry: _load);
    } else if (info == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (info['available'] != true) {
      body = Center(
        child: EmptyState(
          icon: Icons.mic_none_outlined,
          text: tr('AI speaking hozir yoqilmagan. Markazingiz administratoriga murojaat qiling.'),
        ),
      );
    } else if (session == null) {
      body = _chooser(info);
    } else if (session['result'] != null) {
      body = _result(session);
    } else {
      body = _practice(session);
    }
    return Scaffold(
      appBar: pageBar(
        context,
        title: Text(tr('AI speaking')),
        actions: session == null
            ? null
            : <Widget>[
                IconButton(
                  tooltip: tr('Ortga'),
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    setState(() => _session = null);
                    _load();
                  },
                ),
              ],
      ),
      body: body,
    );
  }

  Widget _chooser(Map<String, dynamic> info) {
    final exams = asList(info['exams'], 'exams');
    final exam = exams.firstWhere((e) => e['key'] == _exam, orElse: () => exams.isEmpty ? <String, dynamic>{} : exams.first);
    final parts = asList(exam['parts'], 'parts');
    final sessions = asList(info['sessions'], 'sessions');
    return ListView(padding: readable(context, const EdgeInsets.all(16)), children: <Widget>[
      Text(tr("Og'zaki imtihonga tayyorlaning: AI imtihonchi savol beradi, siz gapirasiz — har javobga izoh va oxirida taxminiy ball."),
          style: TextStyle(color: AppColors.muted)),
      const SizedBox(height: 12),
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          DropdownButtonFormField<String>(
            initialValue: _exam,
            decoration: InputDecoration(labelText: tr('Imtihon')),
            items: <DropdownMenuItem<String>>[
              for (final e in exams) DropdownMenuItem<String>(value: asText(e['key']), child: Text(tr(asText(e['label'])))),
            ],
            onChanged: (value) => setState(() {
              _exam = value ?? 'ielts';
              _part = 1;
            }),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            key: ValueKey<String>('part-$_exam'),
            initialValue: _part,
            isExpanded: true,
            decoration: InputDecoration(labelText: tr('Qism')),
            items: <DropdownMenuItem<int>>[
              for (final p in parts) DropdownMenuItem<int>(value: asInt(p['part']), child: Text(tr(asText(p['label'])), overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (value) => setState(() => _part = value ?? 1),
          ),
          const SizedBox(height: 12),
          TextField(controller: _topic, maxLength: 120, decoration: InputDecoration(labelText: tr('Mavzu (ixtiyoriy)'), hintText: tr('Masalan: Travel'))),
          const SizedBox(height: 4),
          Text(tr('Javobni yozing yoki klaviaturadagi mikrofon bilan aytib yozing (diktovka).'), style: TextStyle(color: AppColors.muted, fontSize: 13)),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy.isEmpty ? _start : null,
            icon: const Icon(Icons.mic_none_outlined),
            label: Text(tr('Boshlash')),
          ),
        ]),
      ),
      if (sessions.isNotEmpty) ...<Widget>[
        const SizedBox(height: 16),
        Text(tr('Oldingi mashqlar'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 8),
        for (final s in sessions)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppCard(
              onTap: _busy.isEmpty ? () => _open(asInt(s['id'])) : null,
              child: Row(children: <Widget>[
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                    Text(asText(s['title']), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text('${dateTime(s['created_at'])} · ${tr('{0} ta javob', <Object?>[asInt(s['answers'])])}', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                  ]),
                ),
                if (s['overall'] != null) Pill(number(asDouble(s['overall'])), color: AppColors.success),
              ]),
            ),
          ),
      ],
    ]);
  }

  Widget _practice(Map<String, dynamic> session) {
    final messages = asList(session['messages'], 'messages');
    final last = messages.isEmpty ? <String, dynamic>{} : messages.last;
    final question = last['role'] == 'assistant' ? asText(last['content']) : '';
    final turns = asList(session['turns'], 'turns').length;
    final limit = asInt(session['limit'], 5);
    final done = turns >= limit;
    return ListView(padding: readable(context, const EdgeInsets.all(16)), children: <Widget>[
      Text(asText(session['title']), style: TextStyle(color: AppColors.muted, fontSize: 13)),
      const SizedBox(height: 4),
      Text(tr('Savol {0} / {1}', <Object?>[turns + 1 > limit ? limit : turns + 1, limit]), style: TextStyle(color: AppColors.muted, fontSize: 13)),
      const SizedBox(height: 10),
      if (question.isNotEmpty)
        AppCard(tone: AppColors.info, child: SelectableText(question, style: const TextStyle(fontSize: 16, height: 1.4))),
      if (_feedback.isNotEmpty) ...<Widget>[
        const SizedBox(height: 10),
        AppCard(
          tone: AppColors.success,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(tr('Oldingi javobingizga izoh'), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(_feedback),
          ]),
        ),
      ],
      if (!done) ...<Widget>[
        const SizedBox(height: 12),
        TextField(
          controller: _answer,
          minLines: 3,
          maxLines: 8,
          maxLength: 4000,
          keyboardType: TextInputType.multiline,
          decoration: InputDecoration(labelText: tr('Javobingiz'), hintText: tr('Javobni ingliz tilida yozing yoki diktovka qiling')),
        ),
        FilledButton.icon(
          onPressed: _busy.isEmpty ? _send : null,
          icon: _busy == 'answer' ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send_outlined),
          label: Text(tr('Yuborish')),
        ),
      ],
      const SizedBox(height: 16),
      OutlinedButton.icon(
        onPressed: _busy.isEmpty && turns > 0 ? _finish : null,
        icon: const Icon(Icons.insights_outlined),
        label: Text(tr('Yakunlash va baholash')),
      ),
    ]);
  }

  Widget _result(Map<String, dynamic> session) {
    final result = asMap(session['result']);
    final cefr = result['scale'] == 'cefr';
    final criteria = asMap(result['criteria']);
    final tips = (result['tips'] is List ? result['tips'] as List : const <Object?>[]).map(asText).toList();
    final turns = asList(session['turns'], 'turns');
    return ListView(padding: readable(context, const EdgeInsets.all(16)), children: <Widget>[
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Row(children: <Widget>[
            Container(
              width: 72,
              height: 72,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.success.withAlpha(30), borderRadius: BorderRadius.circular(18)),
              child: Text(number(asDouble(result['overall'])), style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.success)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text(cefr ? tr('CEFR taxminiy ball (0–75)') : tr('IELTS taxminiy band (0–9)'), style: const TextStyle(fontWeight: FontWeight.w700)),
                if (asText(result['level']).isNotEmpty) Text('${tr('Daraja')}: ${asText(result['level'])}', style: TextStyle(color: AppColors.muted)),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          for (final entry in speakingCriteriaLabels.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(children: <Widget>[
                Expanded(child: Text(tr(entry.value))),
                Text(criteria[entry.key] == null ? '—' : '${number(asDouble(criteria[entry.key]))} / ${cefr ? 75 : 9}', style: const TextStyle(fontWeight: FontWeight.w600)),
              ]),
            ),
          if (asText(result['summary']).isNotEmpty) ...<Widget>[const SizedBox(height: 8), Text(asText(result['summary']))],
          for (final tip in tips) Padding(padding: const EdgeInsets.only(top: 4), child: Text('• $tip')),
          const SizedBox(height: 8),
          Text(tr("Baho javoblaringiz matni bo'yicha taxminiy. Talaffuz baholanmaydi — rasmiy imtihon natijasidan farq qilishi mumkin."),
              style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
        ]),
      ),
      const SizedBox(height: 12),
      Text(tr('Javoblar va izohlar'), style: const TextStyle(fontWeight: FontWeight.w700)),
      for (var i = 0; i < turns.length; i++)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text('${i + 1}. ${asText(turns[i]['answer'])}'),
              const SizedBox(height: 4),
              Text(asText(turns[i]['feedback']), style: TextStyle(color: AppColors.info)),
            ]),
          ),
        ),
    ]);
  }
}
