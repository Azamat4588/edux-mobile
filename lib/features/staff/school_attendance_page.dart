// 3.19: maktab davomati (veb 2.40): sinf → kun → dars; har o'quvchiga keldi / kechikdi / kelmadi / sababli.
// Kirish nazorati yoqilgan bo'lsa — maktabga kelgan vaqt va «Kirish ma'lumotidan to'ldirish». Mantiq: core/school_attendance.dart.
import 'package:flutter/material.dart';

import '../../core/adaptive.dart';
import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/help_links.dart';
import '../../core/i18n.dart';
import '../../core/school_attendance.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

const Map<String, String> _labels = <String, String>{'present': 'Keldi', 'late': 'Kechikdi', 'absent': 'Kelmadi', 'excused': 'Sababli'};

Color _color(String status) => switch (status) {
      'present' => AppColors.success,
      'late' => AppColors.warning,
      'absent' => AppColors.danger,
      _ => AppColors.brand,
    };

class SchoolAttendancePage extends StatelessWidget {
  const SchoolAttendancePage({super.key});

  @override
  Widget build(BuildContext context) {
    final api = AppScope.of(context).api;
    return Scaffold(
      appBar: pageBar(context, title: Text(tr('Sinf davomati')), actions: const <Widget>[HelpButton(HelpLinks.attendance)]),
      body: AsyncView<Map<String, dynamic>>(
        cacheKey: 'school_journal_options',
        decode: asMap,
        load: () async => asMap(await api.get('school/journal/options')),
        builder: (context, options, reload) {
          final classes = classesFromOptions(options);
          if (options['year'] == null || classes.isEmpty) {
            return ListView(children: <Widget>[EmptyState(icon: Icons.groups_outlined, text: tr("Sizga biriktirilgan sinf yo'q (yuklama rahbar tomonidan beriladi)."))]);
          }
          return ListView(
            padding: readable(context, const EdgeInsets.fromLTRB(16, 12, 16, 24)),
            children: <Widget>[
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(children: <Widget>[
                  for (var i = 0; i < classes.length; i++) ...<Widget>[
                    if (i > 0) const Divider(height: 1),
                    ListTile(
                      selected: isDetailSelected(context, 'school-att-${classes[i].id}'),
                      selectedTileColor: AppColors.soft(AppColors.brand),
                      leading: Icon(Icons.how_to_reg_outlined, color: AppColors.brand),
                      title: Text(classes[i].name),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => openDetail(
                        context,
                        id: 'school-att-${classes[i].id}',
                        builder: (_) => SchoolClassAttendancePage(groupId: classes[i].id, className: classes[i].name),
                      ),
                    ),
                  ],
                ]),
              ),
            ],
          );
        },
      ),
    );
  }
}

class SchoolClassAttendancePage extends StatefulWidget {
  const SchoolClassAttendancePage({super.key, required this.groupId, required this.className});

  final int groupId;
  final String className;

  @override
  State<SchoolClassAttendancePage> createState() => _SchoolClassAttendancePageState();
}

class _SchoolClassAttendancePageState extends State<SchoolClassAttendancePage> {
  DateTime _day = DateTime.now();
  SchoolAttendanceDay? _data;
  SchoolLesson? _lesson;
  Map<int, String> _marks = <int, String>{};
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({String? keepLesson}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final day = SchoolAttendanceDay.fromJson(asMap(await AppScope.read(context).api.get('school/attendance', query: <String, Object?>{
        'group_id': widget.groupId,
        'date': isoDay(_day),
      })));
      if (!mounted) return;
      final lessons = day.lessons;
      final lesson = lessons.where((item) => item.key == keepLesson).firstOrNull ?? day.defaultLesson;
      setState(() {
        _data = day;
        _lesson = lesson;
        _marks = lesson == null ? <int, String>{} : initialMarks(day, lesson);
        _dirty = false;
        _loading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    }
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(context: context, initialDate: _day, firstDate: DateTime.now().subtract(const Duration(days: 120)), lastDate: DateTime.now());
    if (picked == null || !mounted) return;
    if (_dirty && !await confirm(context, tr('Saqlanmagan davomat belgilari bor. Ular saqlanmasdan tashlab yuborilsinmi?'))) return;
    setState(() => _day = picked);
    await _load();
  }

  Future<void> _pickLesson(SchoolLesson lesson) async {
    if (lesson.key == _lesson?.key) return;
    if (_dirty && !await confirm(context, tr('Saqlanmagan davomat belgilari bor. Ular saqlanmasdan tashlab yuborilsinmi?'))) return;
    setState(() {
      _lesson = lesson;
      _marks = initialMarks(_data!, lesson);
      _dirty = false;
    });
  }

  Future<void> _save() async {
    final lesson = _lesson;
    if (lesson == null) return;
    setState(() => _saving = true);
    try {
      await AppScope.read(context).api.put('school/attendance', attendancePayload(groupId: widget.groupId, date: isoDay(_day), lesson: lesson, marks: _marks));
      if (!mounted) return;
      showMessage(context, tr('Saqlandi.'));
      await _load(keepLesson: lesson.key);
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final lesson = _lesson;
    final writable = lesson?.canWrite == true;
    return PopScope(
      canPop: !_dirty || isEmbeddedDetail(context),
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await confirm(context, tr("Saqlanmagan o'zgarishlar bor. Sahifadan chiqilsa, ular yo'qoladi. Davom etilsinmi?"))) {
          if (context.mounted) Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: pageBar(context, title: Text(widget.className), actions: <Widget>[
          IconButton(tooltip: tr('Kun'), icon: const Icon(Icons.event_outlined), onPressed: _pickDay),
        ]),
        bottomNavigationBar: writable && data != null && data.students.isNotEmpty
            ? SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check),
                    label: Text(tr('Saqlash')),
                  ),
                ),
              )
            : null,
        body: _loading
            ? const SkeletonList()
            : _error != null
                ? ErrorState(message: _error!, onRetry: () => _load())
                : RefreshIndicator(
                    onRefresh: () => _load(keepLesson: _lesson?.key),
                    child: ListView(
                      padding: readable(context, const EdgeInsets.fromLTRB(16, 12, 16, 24)),
                      children: <Widget>[
                        Text(date(isoDay(_day)), style: TextStyle(color: AppColors.muted)),
                        const SizedBox(height: 8),
                        if (data!.lessons.isEmpty)
                          EmptyState(icon: Icons.event_busy_outlined, text: tr("Bu kunda dars yo'q. Boshqa kunni tanlang."))
                        else ...<Widget>[
                          Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
                            for (final item in data.lessons)
                              ChoiceChip(
                                label: Text(item.startsAt != null ? '${item.title} · ${item.startsAt}' : item.title),
                                avatar: item.saved.isNotEmpty ? const Icon(Icons.check_circle, size: 18) : null,
                                selected: item.key == lesson?.key,
                                onSelected: (_) => _pickLesson(item),
                              ),
                          ]),
                          const SizedBox(height: 12),
                          if (!writable)
                            ToneBox(
                              color: AppColors.brand,
                              padding: const EdgeInsets.all(12),
                              child: Text(tr("Bu darsni faqat fan o'qituvchisi belgilaydi — siz ko'rib turibsiz.")),
                            )
                          else
                            Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
                              OutlinedButton.icon(
                                onPressed: () => setState(() {
                                  _marks = <int, String>{for (final id in _marks.keys) id: _marks[id] == 'excused' ? 'excused' : 'present'};
                                  _dirty = true;
                                }),
                                icon: const Icon(Icons.done_all),
                                label: Text(tr('Hammasi keldi')),
                              ),
                              if (data.gate && lesson != null)
                                OutlinedButton.icon(
                                  onPressed: () => setState(() {
                                    _marks = fillFromGate(data, lesson, _marks);
                                    _dirty = true;
                                  }),
                                  icon: const Icon(Icons.badge_outlined),
                                  label: Text(tr("Kirish ma'lumotidan to'ldirish")),
                                ),
                            ]),
                          const SizedBox(height: 8),
                          AppCard(
                            padding: EdgeInsets.zero,
                            child: Column(children: <Widget>[
                              for (var i = 0; i < data.students.length; i++) ...<Widget>[
                                if (i > 0) const Divider(height: 1),
                                _StudentRow(
                                  student: data.students[i],
                                  status: _marks[asInt(data.students[i]['id'])] ?? 'present',
                                  enabled: writable,
                                  onChanged: (value) => setState(() {
                                    _marks[asInt(data.students[i]['id'])] = value;
                                    _dirty = true;
                                  }),
                                ),
                              ],
                            ]),
                          ),
                        ],
                      ],
                    ),
                  ),
      ),
    );
  }
}

class _StudentRow extends StatelessWidget {
  const _StudentRow({required this.student, required this.status, required this.enabled, required this.onChanged});

  final Map<String, dynamic> student;
  final String status;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final arrived = student['arrived_at']?.toString();
    final notice = asMap(student['notice']);
    final hints = <String>[
      if (arrived != null && arrived.isNotEmpty) tr('Keldi: {0}', <Object?>[arrived]),
      if (notice.isNotEmpty) tr("Ota-ona xabari: {0}", <Object?>[asText(notice['reason'], '—')]),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Text(asText(student['full_name']), style: const TextStyle(fontWeight: FontWeight.w600)),
        if (hints.isNotEmpty) Text(hints.join(' · '), style: TextStyle(color: AppColors.muted, fontSize: 13)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: <Widget>[
          for (final value in schoolAttendanceStatuses)
            ChoiceChip(
              label: Text(tr(_labels[value]!)),
              selected: status == value,
              selectedColor: AppColors.soft(_color(value)),
              side: BorderSide(color: status == value ? _color(value) : AppColors.line),
              onSelected: enabled ? (_) => onChanged(value) : null,
            ),
        ]),
      ]),
    );
  }
}
