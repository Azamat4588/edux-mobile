// Maktab jurnali (3.4.1, veb: school.journal): o'qituvchi o'z sinf+fan jurnallarini ochadi, darsni tanlab har o'quvchiga
// baho (2–5) va davomat qo'yadi; yangi dars (sana, soat, mavzu, uy vazifasi) qo'shadi. Yozish huquqi — server `can_write`.
// API: GET school/journal/options, GET school/journal, POST school/journal/lessons, PUT school/journal/lessons/{id}/entries.
import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/help_links.dart';
import '../../core/i18n.dart';
import '../../core/school_journal.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

class JournalPage extends StatelessWidget {
  const JournalPage({super.key});

  @override
  Widget build(BuildContext context) {
    final api = AppScope.of(context).api;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Jurnal')), actions: const <Widget>[HelpButton(HelpLinks.journal)]),
      body: AsyncView<Map<String, dynamic>>(
        cacheKey: 'school_journal_options',
        decode: asMap,
        load: () async => asMap(await api.get('school/journal/options')),
        builder: (context, options, reload) {
          if (options['year'] == null) {
            return ListView(children: <Widget>[EmptyState(icon: Icons.event_busy_outlined, text: tr("O'quv yili belgilanmagan. Rahbar «Maktab yili» sahifasida yil va choraklarni kiritadi."))]);
          }
          final byClass = journalsByClass(options);
          if (byClass.isEmpty) {
            return ListView(children: <Widget>[EmptyState(icon: Icons.menu_book_outlined, text: tr("Sizga biriktirilgan jurnal yo'q (yuklama rahbar tomonidan beriladi)."))]);
          }
          final terms = asList(options['terms'], 'terms');
          final termId = asInt(options['current_term_id'], terms.isEmpty ? 0 : asInt(terms.first['id']));
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: <Widget>[
              Text(asText(asMap(options['year'])['name']), style: TextStyle(color: AppColors.muted)),
              for (final entry in byClass.entries) ...<Widget>[
                SectionTitle(entry.key),
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(children: <Widget>[
                    for (var i = 0; i < entry.value.length; i++) ...<Widget>[
                      if (i > 0) const Divider(height: 1),
                      ListTile(
                        leading: Icon(entry.value[i]['can_write'] == true ? Icons.edit_note : Icons.visibility_outlined, color: AppColors.brand),
                        title: Text(asText(entry.value[i]['subject'])),
                        subtitle: Text(asText(entry.value[i]['teacher'])),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                          builder: (_) => JournalGridPage(journal: entry.value[i], terms: terms, termId: termId),
                        )),
                      ),
                    ],
                  ]),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class JournalGridPage extends StatefulWidget {
  const JournalGridPage({super.key, required this.journal, required this.terms, required this.termId});

  final Map<String, dynamic> journal;
  final List<Map<String, dynamic>> terms;
  final int termId;

  @override
  State<JournalGridPage> createState() => _JournalGridPageState();
}

class _JournalGridPageState extends State<JournalGridPage> {
  late int _termId = widget.termId;
  // Chorak o'zgarsa — yangi kalit (sahifa qaytadan yuklanadi).
  GlobalKey<AsyncViewState<JournalGrid>> _view = GlobalKey<AsyncViewState<JournalGrid>>();

  int get _groupId => asInt(widget.journal['group_id']);
  int get _subjectId => asInt(widget.journal['subject_id']);

  Future<JournalGrid> _load(Api api) async => JournalGrid.fromJson(asMap(await api.get('school/journal', query: <String, Object?>{
        'group_id': _groupId,
        'subject_id': _subjectId,
        'term_id': _termId,
      })));

  Future<void> _addLesson() async {
    final api = AppScope.read(context).api;
    final created = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _LessonForm(groupId: _groupId, subjectId: _subjectId),
    );
    if (created == null || !mounted) return;
    // Yangi dars bilan jadval qayta olinadi va baholash sahifasi darhol ochiladi.
    JournalGrid? grid;
    try {
      grid = await _load(api);
    } catch (_) {
      grid = null;
    }
    if (!mounted) return;
    _reloadView();
    await _openLesson(created, grid);
  }

  void _reloadView() => _view.currentState?.reload();

  Future<void> _openLesson(Map<String, dynamic> lesson, JournalGrid? grid) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(builder: (_) => LessonEntriesPage(grid: grid, lesson: lesson)));
    if (saved == true) await _view.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final api = AppScope.of(context).api;
    final title = '${asText(widget.journal['class_name'])} · ${asText(widget.journal['subject'])}';
    return Scaffold(
      appBar: AppBar(title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: Column(children: <Widget>[
        if (widget.terms.length > 1)
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              children: <Widget>[
                for (final term in widget.terms)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(asText(term['name'])),
                      selected: asInt(term['id']) == _termId,
                      onSelected: (_) => setState(() {
                        _termId = asInt(term['id']);
                        _view = GlobalKey<AsyncViewState<JournalGrid>>();
                      }),
                    ),
                  ),
              ],
            ),
          ),
        Expanded(
          child: AsyncView<JournalGrid>(
            key: _view,
            load: () => _load(api),
            builder: (context, grid, reload) {
              final lessons = grid.lessons;
              return Stack(children: <Widget>[
                ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  children: <Widget>[
                    if (!grid.canWrite)
                      AppCard(child: Text(tr("Bu jurnalni faqat ko'rasiz: baho qo'yish — fan o'qituvchisi va rahbarda."), style: TextStyle(color: AppColors.muted))),
                    if (lessons.isEmpty)
                      EmptyState(icon: Icons.event_note_outlined, text: tr('Bu chorakda hali dars yozilmagan.'))
                    else
                      AppCard(
                        padding: EdgeInsets.zero,
                        child: Column(children: <Widget>[
                          for (var i = 0; i < lessons.length; i++) ...<Widget>[
                            if (i > 0) const Divider(height: 1),
                            _LessonTile(lesson: lessons[i], grid: grid, onTap: () => _openLesson(lessons[i], grid)),
                          ],
                        ]),
                      ),
                  ],
                ),
                if (grid.canWrite)
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: FloatingActionButton.extended(
                      onPressed: _addLesson,
                      icon: const Icon(Icons.add),
                      label: Text(tr("Dars qo'shish")),
                    ),
                  ),
              ]);
            },
          ),
        ),
      ]),
    );
  }
}

class _LessonTile extends StatelessWidget {
  const _LessonTile({required this.lesson, required this.grid, required this.onTap});

  final Map<String, dynamic> lesson;
  final JournalGrid grid;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final summary = grid.lessonSummary(asInt(lesson['id']));
    final day = parseDate(lesson['date']);
    final period = asInt(lesson['period_number']);
    return ListTile(
      title: Text(<String>[if (day != null) dayTitle(day) else asText(lesson['date']), if (period > 0) tr('{0}-soat', <Object?>[period])].join(' · ')),
      subtitle: Text(asText(lesson['topic'], tr('Mavzu yozilmagan')), maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: <Widget>[
        Text(tr('{0} baho', <Object?>[summary.marks]), style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
        if (summary.absent > 0) Text(tr('{0} kelmagan', <Object?>[summary.absent]), style: TextStyle(color: AppColors.warning, fontSize: 12.5)),
      ]),
      onTap: onTap,
    );
  }
}

/// Bitta dars: har o'quvchiga baho va davomat. «Hammasi keldi» — bo'sh kataklarga «Qatnashdi».
class LessonEntriesPage extends StatefulWidget {
  const LessonEntriesPage({super.key, required this.grid, required this.lesson});

  final JournalGrid? grid;
  final Map<String, dynamic> lesson;

  @override
  State<LessonEntriesPage> createState() => _LessonEntriesPageState();
}

class _LessonEntriesPageState extends State<LessonEntriesPage> {
  late final int _lessonId = asInt(widget.lesson['id']);
  late final Map<int, JournalEntry> _before = <int, JournalEntry>{
    for (final student in widget.grid?.students ?? const <Map<String, dynamic>>[])
      asInt(student['id']): widget.grid!.entry(_lessonId, asInt(student['id'])),
  };
  late final Map<int, JournalEntry> _edited = Map<int, JournalEntry>.from(_before);
  bool _saving = false;

  bool get _canWrite => widget.grid?.canWrite == true;
  List<Map<String, Object?>> get _changes => changedEntries(_before, _edited);

  void _allPresent() {
    setState(() {
      for (final id in _edited.keys.toList()) {
        if (_edited[id]!.attendance == null) _edited[id] = _edited[id]!.copyWith(attendance: 'present');
      }
    });
  }

  Future<void> _save() async {
    final changes = _changes;
    if (changes.isEmpty) {
      Navigator.pop(context, false);
      return;
    }
    setState(() => _saving = true);
    final api = AppScope.read(context).api;
    try {
      await api.put('school/journal/lessons/$_lessonId/entries', <String, Object?>{'entries': changes});
      if (!mounted) return;
      showMessage(context, tr('Saqlandi'));
      Navigator.pop(context, true);
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmLeave() async {
    if (_changes.isEmpty) return true;
    return confirm(context, tr('Saqlanmagan baholar bor. Ular saqlanmasdan chiqilsinmi?'), action: tr('Chiqish'), danger: true);
  }

  @override
  Widget build(BuildContext context) {
    final grid = widget.grid;
    final day = parseDate(widget.lesson['date']);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && context.mounted) Navigator.pop(context, false);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(day == null ? asText(widget.lesson['date']) : dayTitle(day)),
          actions: <Widget>[
            if (_canWrite) TextButton(onPressed: _allPresent, child: Text(tr('Hammasi keldi'))),
          ],
        ),
        body: grid == null
            ? ErrorState(message: tr("Ma'lumotni yuklab bo'lmadi."))
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                children: <Widget>[
                  if (asText(widget.lesson['topic']).isNotEmpty) KeyValue(tr('Mavzu'), asText(widget.lesson['topic'])),
                  if (asText(widget.lesson['homework']).isNotEmpty) KeyValue(tr('Uy vazifasi'), asText(widget.lesson['homework'])),
                  const SizedBox(height: 8),
                  for (final student in grid.students)
                    _StudentRow(
                      name: asText(student['full_name']),
                      average: grid.average(asInt(student['id'])),
                      entry: _edited[asInt(student['id'])] ?? const JournalEntry(),
                      enabled: _canWrite && !_saving,
                      onChanged: (entry) => setState(() => _edited[asInt(student['id'])] = entry),
                    ),
                ],
              ),
        floatingActionButton: _canWrite
            ? FloatingActionButton.extended(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.onBrand))
                    : const Icon(Icons.save_outlined),
                label: Text(_changes.isEmpty ? tr('Saqlash') : tr('Saqlash ({0})', <Object?>[_changes.length])),
              )
            : null,
      ),
    );
  }
}

class _StudentRow extends StatelessWidget {
  const _StudentRow({required this.name, required this.average, required this.entry, required this.enabled, required this.onChanged});

  final String name;
  final double? average;
  final JournalEntry entry;
  final bool enabled;
  final ValueChanged<JournalEntry> onChanged;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Row(children: <Widget>[
          Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w700))),
          if (average != null) Text(tr("O'rtacha: {0}", <Object?>[number(average, decimals: 1)]), style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: <Widget>[
          for (final mark in journalMarks)
            ChoiceChip(
              label: Text('$mark'),
              selected: entry.mark == mark,
              onSelected: enabled ? (on) => onChanged(on ? entry.copyWith(mark: mark) : entry.copyWith(clearMark: true)) : null,
            ),
        ]),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: <Widget>[
          for (final status in journalAttendance)
            ChoiceChip(
              label: Text(tr(journalAttendanceLabels[status]!)),
              selected: entry.attendance == status,
              onSelected: enabled ? (on) => onChanged(on ? entry.copyWith(attendance: status) : entry.copyWith(clearAttendance: true)) : null,
            ),
        ]),
      ]),
    );
  }
}

/// Yangi dars (jurnal ustuni): sana (bugun), soat, mavzu, uy vazifasi.
class _LessonForm extends StatefulWidget {
  const _LessonForm({required this.groupId, required this.subjectId});

  final int groupId;
  final int subjectId;

  @override
  State<_LessonForm> createState() => _LessonFormState();
}

class _LessonFormState extends State<_LessonForm> {
  DateTime _day = DateTime.now();
  int? _period;
  final _topic = TextEditingController();
  final _homework = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _topic.dispose();
    _homework.dispose();
    super.dispose();
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (picked != null && mounted) setState(() => _day = picked);
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final api = AppScope.read(context).api;
    try {
      final lesson = asMap(await api.post('school/journal/lessons', <String, Object?>{
        'group_id': widget.groupId,
        'subject_id': widget.subjectId,
        'date': isoDay(_day),
        'period_number': _period,
        'topic': _topic.text.trim().isEmpty ? null : _topic.text.trim(),
        'homework': _homework.text.trim().isEmpty ? null : _homework.text.trim(),
      }));
      if (mounted) Navigator.pop(context, lesson);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: <Widget>[
          Text(tr("Dars qo'shish"), style: AppTheme.title(size: 19)),
          const SizedBox(height: 12),
          OutlinedButton.icon(onPressed: _pickDay, icon: const Icon(Icons.event), label: Text(dayTitle(_day))),
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: <Widget>[
            for (var period = 1; period <= 8; period++)
              ChoiceChip(label: Text(tr('{0}-soat', <Object?>[period])), selected: _period == period, onSelected: (on) => setState(() => _period = on ? period : null)),
          ]),
          const SizedBox(height: 10),
          TextField(controller: _topic, decoration: InputDecoration(labelText: tr('Mavzu'))),
          const SizedBox(height: 10),
          TextField(controller: _homework, minLines: 1, maxLines: 3, decoration: InputDecoration(labelText: tr('Uy vazifasi (ixtiyoriy)'))),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 10),
            Text(_error!, style: TextStyle(color: AppColors.danger)),
          ],
          const SizedBox(height: 16),
          FilledButton(onPressed: _busy ? null : _submit, child: Text(tr("Qo'shish"))),
        ]),
      ),
    );
  }
}
