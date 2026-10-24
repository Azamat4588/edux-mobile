// Mavzular bo'yicha test (3.1, direktor/administrator/o'qituvchi, Test moduli): fan → bo'lim → mavzu daraxti
// (savollar soni bilan), mavzular va har biridan nechta savol tanlanadi, umumiy bazadan qoralama test tuziladi.
// Test vebda tekshirilib e'lon qilinadi.
import 'package:flutter/material.dart';

import '../../core/adaptive.dart';
import '../../core/api.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../staff/exams_page.dart';

/// Mavzulashtirilgan baza so'rovlari (server 1.27+: bank/topics).
class TopicBankApi {
  TopicBankApi(this.api);

  final Api api;

  /// Bitta testdagi eng ko'p savol (server: QuestionBank::MAX_EXAM).
  static const int maxQuestions = 120;

  /// {subjects: [{code, subject, topics, questions}], tree: {subject, sections: [{code, title, topics: [{code, title, count}]}], languages, language}}
  Future<Map<String, dynamic>> topics({String? subject, String? language}) async =>
      asMap(await api.get('bank/topics', query: <String, Object?>{'subject': subject, 'language': language}));

  /// {topic: {...}, questions: [{id, difficulty, body, options, answer, explanation, year}]}
  Future<Map<String, dynamic>> questions(String code, {String? language}) async =>
      asMap(await api.get('bank/topics/$code/questions', query: <String, Object?>{'language': language}));

  /// Qoralama test: {exam_id}.
  Future<int> createExam(Map<String, int> selection, {String? language, String? title, int? duration, bool random = true}) async {
    final data = asMap(await api.post('bank/topics/exam', <String, Object?>{
      'topics': selection.entries.map((entry) => <String, Object?>{'code': entry.key, 'count': entry.value}).toList(),
      'language': language,
      'title': title,
      'duration_minutes': duration,
      'random': random,
    }));
    return asInt(data['exam_id']);
  }

  Future<Map<String, dynamic>> exam(int id) async => asMap(await api.get('exams/$id'));
}

const Map<String, String> _languageLabels = <String, String>{
  'uz': "O'zbekcha",
  'ru': 'Русский',
  'en': 'English',
  'all': 'Barcha tillar',
};

const Map<int, String> _difficultyLabels = <int, String>{1: 'Oson', 2: "O'rta", 3: 'Qiyin'};

class TopicTestsPage extends StatefulWidget {
  const TopicTestsPage({super.key});

  @override
  State<TopicTestsPage> createState() => _TopicTestsPageState();
}

class _TopicTestsPageState extends State<TopicTestsPage> {
  late final TopicBankApi _bank = TopicBankApi(AppScope.read(context).api);

  List<Map<String, dynamic>> _subjects = <Map<String, dynamic>>[];
  Map<String, dynamic>? _tree;
  String? _subject;
  String? _language;
  bool _loading = true;
  Object? _error;

  /// Tanlov: mavzu kodi → savollar soni.
  final Map<String, int> _selection = <String, int>{};
  final Map<String, String> _titles = <String, String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _bank.topics(subject: _subject, language: _language);
      if (!mounted) return;
      final tree = data['tree'] is Map ? asMap(data['tree']) : null;
      setState(() {
        _subjects = asList(data['subjects'], 'subjects');
        _tree = tree;
        _subject = tree == null ? _subject : asText(asMap(tree['subject'])['code']);
        _language = tree == null ? _language : tree['language']?.toString();
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _chooseSubject(String code) {
    if (code == _subject) return;
    setState(() {
      _subject = code;
      _language = null;
      _selection.clear();
    });
    _load();
  }

  void _chooseLanguage(String? language) {
    if (language == null || language == _language) return;
    setState(() {
      _language = language;
      _selection.clear();
    });
    _load();
  }

  int get _total => _selection.values.fold<int>(0, (sum, value) => sum + value);

  void _toggle(Map<String, dynamic> topic, bool selected) {
    final code = asText(topic['code']);
    final available = asInt(topic['count']);
    setState(() {
      if (!selected) {
        _selection.remove(code);
        return;
      }
      final room = TopicBankApi.maxQuestions - _total;
      if (room <= 0 || available <= 0) {
        showMessage(context, tr("Bitta testga ko'pi bilan {0} ta savol qo'shish mumkin.", <Object?>[TopicBankApi.maxQuestions]), error: true);
        return;
      }
      final start = available < 5 ? available : 5;
      _selection[code] = start < room ? start : room;
      _titles[code] = asText(topic['title']);
    });
  }

  void _change(String code, int delta, int available) {
    final current = _selection[code] ?? 0;
    final next = current + delta;
    if (next < 1 || next > available) return;
    if (delta > 0 && _total >= TopicBankApi.maxQuestions) {
      showMessage(context, tr("Bitta testga ko'pi bilan {0} ta savol qo'shish mumkin.", <Object?>[TopicBankApi.maxQuestions]), error: true);
      return;
    }
    setState(() => _selection[code] = next);
  }

  Future<void> _create() async {
    final created = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet))),
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _CreateForm(bank: _bank, selection: Map<String, int>.from(_selection), language: _language, total: _total),
      ),
    );
    if (created == null || !mounted) return;
    Map<String, dynamic> exam = <String, dynamic>{'id': created, 'status': 'draft'};
    try {
      exam = await _bank.exam(created);
    } catch (_) {
      // nomi ko'rinmasa ham test yaratilgan
    }
    if (!mounted) return;
    setState(() => _selection.clear());
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(Icons.check_circle_rounded, color: AppColors.success, size: 40),
        title: Text(tr('Qoralama test yaratildi')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          if (asText(exam['title']).isNotEmpty) Text(asText(exam['title']), style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: AppSpacing.xs),
          Text(tr('Test raqami: #{0}', <Object?>[created]), style: TextStyle(color: AppColors.muted)),
          if (exam['questions'] is List)
            Text(tr('{0} ta savol', <Object?>[asRawList(exam['questions']).length]), style: TextStyle(color: AppColors.muted)),
          const SizedBox(height: AppSpacing.m),
          Text(tr("Testni veb-versiyada (Testlar bo'limi) ko'rib chiqing, guruhlarni belgilang va e'lon qiling — shundan keyin o'quvchilarga ochiladi.")),
        ]),
        actions: <Widget>[
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ExamDetailPage(exam: exam)));
            },
            child: Text(tr('Ochish')),
          ),
          FilledButton(onPressed: () => Navigator.pop(dialogContext), child: Text(tr('Yaxshi'))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tree = _tree;
    final error = _error;
    Widget body;
    if (_loading && tree == null) {
      body = const SkeletonList();
    } else if (error != null && tree == null) {
      body = error is ApiException && error.isForbidden
          ? ForbiddenState(details: error.message, onRetry: _load)
          : ErrorState(message: errorText(error), onRetry: _load);
    } else if (tree == null || _subjects.isEmpty) {
      body = ListView(children: <Widget>[
        EmptyState(icon: Icons.account_tree_outlined, text: tr("Mavzulashtirilgan savollar bazasi hali to'ldirilmagan.")),
      ]);
    } else {
      body = _buildTree(tree);
    }
    final total = _total;
    return Scaffold(
      appBar: pageBar(context,
        title: Text(tr("Mavzular bo'yicha test")),
        bottom: _subjects.isEmpty
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(56),
                child: SizedBox(
                  height: 56,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(AppSpacing.m, AppSpacing.xs, AppSpacing.m, AppSpacing.s),
                    children: <Widget>[
                      for (final subject in _subjects)
                        Padding(
                          padding: const EdgeInsets.only(right: AppSpacing.s),
                          child: ChoiceChip(
                            label: Text('${asText(subject['subject'])} · ${asInt(subject['questions'])}'),
                            selected: asText(subject['code']) == _subject,
                            onSelected: _loading ? null : (_) => _chooseSubject(asText(subject['code'])),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
      ),
      body: Column(children: <Widget>[
        if (_loading && tree != null) const LinearProgressIndicator(minHeight: 2),
        Expanded(child: body),
      ]),
      bottomNavigationBar: total == 0
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(AppSpacing.l, AppSpacing.m, AppSpacing.l, AppSpacing.m),
                decoration: BoxDecoration(color: AppColors.card, border: Border(top: BorderSide(color: AppColors.line))),
                child: Row(children: <Widget>[
                  Expanded(
                    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                      Text(tr('{0} ta savol', <Object?>[total]), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      Text(tr('{0} ta mavzu tanlandi', <Object?>[_selection.length]), style: TextStyle(color: AppColors.muted, fontSize: 13)),
                    ]),
                  ),
                  FilledButton.icon(onPressed: _create, icon: const Icon(Icons.playlist_add_check_rounded), label: Text(tr('Test tuzish'))),
                ]),
              ),
            ),
    );
  }

  Widget _buildTree(Map<String, dynamic> tree) {
    final sections = asList(tree['sections'], 'sections');
    final languages = asMap(tree['languages']);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: readable(context, const EdgeInsets.fromLTRB(AppSpacing.l, AppSpacing.m, AppSpacing.l, AppSpacing.xl)),
        children: <Widget>[
          if (languages.length > 1) ...<Widget>[
            Row(children: <Widget>[
              Icon(Icons.translate_rounded, size: 20, color: AppColors.muted),
              const SizedBox(width: AppSpacing.s),
              Text(tr('Savollar tili'), style: TextStyle(color: AppColors.muted)),
              const Spacer(),
              DropdownButton<String>(
                value: languages.containsKey(_language) ? _language : null,
                underline: const SizedBox(),
                items: languages.entries
                    .map((entry) => DropdownMenuItem<String>(
                          value: entry.key,
                          child: Text('${tr(_languageLabels[entry.key] ?? entry.key)} (${asInt(entry.value)})'),
                        ))
                    .toList(),
                onChanged: _loading ? null : _chooseLanguage,
              ),
            ]),
            const SizedBox(height: AppSpacing.s),
          ],
          Text(tr('Mavzularni belgilang va har biridan nechta savol olinishini tanlang. Savollar tasodifiy tanlanadi.'),
              style: TextStyle(color: AppColors.muted, fontSize: 13)),
          const SizedBox(height: AppSpacing.m),
          for (final section in sections) ...<Widget>[
            _SectionCard(
              section: section,
              selection: _selection,
              onToggle: _toggle,
              onChange: _change,
              onPreview: (topic) => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => TopicQuestionsPage(bank: _bank, code: asText(topic['code']), title: asText(topic['title']), language: _language),
              )),
            ),
            const SizedBox(height: AppSpacing.s),
          ],
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.section,
    required this.selection,
    required this.onToggle,
    required this.onChange,
    required this.onPreview,
  });

  final Map<String, dynamic> section;
  final Map<String, int> selection;
  final void Function(Map<String, dynamic> topic, bool selected) onToggle;
  final void Function(String code, int delta, int available) onChange;
  final ValueChanged<Map<String, dynamic>> onPreview;

  @override
  Widget build(BuildContext context) {
    final topics = asList(section['topics'], 'topics');
    final questions = topics.fold<int>(0, (sum, topic) => sum + asInt(topic['count']));
    final picked = topics.where((topic) => selection.containsKey(asText(topic['code']))).length;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: picked > 0,
          title: Text(asText(section['title']), style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(
            <String>[
              tr('{0} ta mavzu', <Object?>[topics.length]),
              tr('{0} ta savol', <Object?>[questions]),
              if (picked > 0) tr('{0} ta tanlandi', <Object?>[picked]),
            ].join(', '),
            style: TextStyle(color: picked > 0 ? AppColors.brand : AppColors.muted, fontSize: 13),
          ),
          children: <Widget>[
            for (final topic in topics) _TopicRow(topic: topic, count: selection[asText(topic['code'])], onToggle: onToggle, onChange: onChange, onPreview: onPreview),
          ],
        ),
      ),
    );
  }
}

class _TopicRow extends StatelessWidget {
  const _TopicRow({required this.topic, required this.count, required this.onToggle, required this.onChange, required this.onPreview});

  final Map<String, dynamic> topic;
  final int? count;
  final void Function(Map<String, dynamic> topic, bool selected) onToggle;
  final void Function(String code, int delta, int available) onChange;
  final ValueChanged<Map<String, dynamic>> onPreview;

  @override
  Widget build(BuildContext context) {
    final available = asInt(topic['count']);
    final code = asText(topic['code']);
    final selected = count != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.s, 0, AppSpacing.s, AppSpacing.xs),
      child: Column(children: <Widget>[
        Row(children: <Widget>[
          Checkbox(value: selected, onChanged: available == 0 ? null : (value) => onToggle(topic, value == true)),
          Expanded(
            child: InkWell(
              onTap: available == 0 ? null : () => onToggle(topic, !selected),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  Text(asText(topic['title']), style: TextStyle(color: available == 0 ? AppColors.muted : AppColors.ink)),
                  Text(tr('{0} ta savol', <Object?>[available]), style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
                ]),
              ),
            ),
          ),
          IconButton(
            tooltip: tr("Savollarni ko'rish"),
            onPressed: available == 0 ? null : () => onPreview(topic),
            icon: const Icon(Icons.visibility_outlined),
          ),
        ]),
        if (selected)
          Padding(
            padding: const EdgeInsets.only(left: 48, bottom: AppSpacing.s),
            child: Row(children: <Widget>[
              Text(tr('Savollar soni'), style: TextStyle(color: AppColors.muted, fontSize: 13)),
              const Spacer(),
              IconButton.outlined(
                tooltip: tr('Kamaytirish'),
                onPressed: count! > 1 ? () => onChange(code, -1, available) : null,
                icon: const Icon(Icons.remove),
              ),
              SizedBox(
                width: 44,
                child: Text('$count', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ),
              IconButton.outlined(
                tooltip: tr("Ko'paytirish"),
                onPressed: count! < available ? () => onChange(code, 1, available) : null,
                icon: const Icon(Icons.add),
              ),
            ]),
          ),
      ]),
    );
  }
}

class _CreateForm extends StatefulWidget {
  const _CreateForm({required this.bank, required this.selection, required this.language, required this.total});

  final TopicBankApi bank;
  final Map<String, int> selection;
  final String? language;
  final int total;

  @override
  State<_CreateForm> createState() => _CreateFormState();
}

class _CreateFormState extends State<_CreateForm> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _duration = TextEditingController();
  bool _random = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _duration.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final duration = int.tryParse(_duration.text.trim());
    if (_duration.text.trim().isNotEmpty && (duration == null || duration < 1 || duration > 600)) {
      setState(() => _error = tr('Vaqt 1 dan 600 daqiqagacha bo\'lishi kerak.'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final id = await widget.bank.createExam(
        widget.selection,
        language: widget.language,
        title: _title.text.trim().isEmpty ? null : _title.text.trim(),
        duration: duration,
        random: _random,
      );
      if (mounted) Navigator.pop(context, id);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: <Widget>[
        Text(tr('Test tuzish'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(tr('{0} ta mavzudan {1} ta savol', <Object?>[widget.selection.length, widget.total]), style: TextStyle(color: AppColors.muted)),
        const SizedBox(height: AppSpacing.l),
        if (_error != null) ...<Widget>[
          Text(_error!, style: TextStyle(color: AppColors.danger)),
          const SizedBox(height: AppSpacing.m),
        ],
        TextField(
          controller: _title,
          maxLength: 255,
          decoration: InputDecoration(labelText: tr('Test nomi (ixtiyoriy)'), counterText: '', helperText: tr("Bo'sh qolsa, fan va mavzu nomidan tuziladi.")),
        ),
        const SizedBox(height: AppSpacing.m),
        TextField(
          controller: _duration,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: tr('Vaqt (daqiqa, ixtiyoriy)')),
        ),
        const SizedBox(height: AppSpacing.s),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _random,
          onChanged: (value) => setState(() => _random = value),
          title: Text(tr('Savollarni tasodifiy tanlash')),
          subtitle: Text(tr("O'chirilsa — osondan qiyinga tartib bilan.")),
        ),
        const SizedBox(height: AppSpacing.l),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
              : Text(tr('Qoralama yaratish')),
        ),
      ]),
    );
  }
}

/// Mavzu savollarini ko'rib chiqish (formulalar LaTeX'da, to'g'ri javob belgilangan).
class TopicQuestionsPage extends StatelessWidget {
  const TopicQuestionsPage({super.key, required this.bank, required this.code, required this.title, this.language});

  final TopicBankApi bank;
  final String code;
  final String title;
  final String? language;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: pageBar(context, title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: AsyncView<List<Map<String, dynamic>>>(
        load: () async => asList(asMap(await bank.questions(code, language: language))['questions'], 'questions'),
        builder: (context, questions, reload) {
          if (questions.isEmpty) {
            return ListView(children: <Widget>[EmptyState(text: tr("Bu mavzuda savol yo'q."))]);
          }
          return ListView.separated(
            padding: readable(context, const EdgeInsets.all(AppSpacing.l)),
            itemCount: questions.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.m),
            itemBuilder: (context, index) => _QuestionCard(number: index + 1, question: questions[index]),
          );
        },
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({required this.number, required this.question});

  final int number;
  final Map<String, dynamic> question;

  @override
  Widget build(BuildContext context) {
    final options = asRawList(question['options']);
    final answer = question['answer'] == null ? -1 : asInt(question['answer'], -1);
    final difficulty = asInt(question['difficulty']);
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Row(children: <Widget>[
          Text('$number.', style: const TextStyle(fontWeight: FontWeight.w800)),
          const Spacer(),
          if (_difficultyLabels[difficulty] != null)
            Pill(tr(_difficultyLabels[difficulty]!), color: difficulty == 3 ? AppColors.danger : (difficulty == 2 ? AppColors.warning : AppColors.success)),
          if (question['year'] != null) ...<Widget>[const SizedBox(width: AppSpacing.s), Pill(asText(question['year']), color: AppColors.muted)],
        ]),
        const SizedBox(height: AppSpacing.s),
        MathText(asText(question['body']), style: TextStyle(color: AppColors.ink, fontSize: 15, height: 1.35)),
        const SizedBox(height: AppSpacing.s),
        for (var i = 0; i < options.length; i++)
          Container(
            margin: const EdgeInsets.only(top: AppSpacing.xs),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m, vertical: AppSpacing.s),
            decoration: BoxDecoration(
              color: i == answer ? AppColors.soft(AppColors.success) : null,
              borderRadius: BorderRadius.circular(AppRadius.control),
              border: Border.all(color: i == answer ? AppColors.success : AppColors.line),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text('${String.fromCharCode(65 + i)}) ', style: const TextStyle(fontWeight: FontWeight.w700)),
              Expanded(child: MathText(_optionText(options[i]), style: TextStyle(color: AppColors.ink))),
            ]),
          ),
        if (asText(question['explanation']).isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.s),
          MathText(asText(question['explanation']), style: TextStyle(color: AppColors.muted, fontSize: 13)),
        ],
      ]),
    );
  }

  /// Variant matn yoki {text: ...} ko'rinishida bo'lishi mumkin.
  static String _optionText(Object? option) {
    if (option is Map) return asText(option['text'] ?? option['body'] ?? option['value']);
    return asText(option);
  }
}
