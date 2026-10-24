// Davomat (CRM guruhlari): guruh va kunni tanlab, har o'quvchini belgilash. Bir bosishda «Hammasi keldi».
import 'package:flutter/material.dart';

import '../../core/adaptive.dart';
import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/help_links.dart';
import '../../core/i18n.dart';
import '../../core/motion.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'students_page.dart';

class AttendancePage extends StatelessWidget {
  const AttendancePage({super.key});

  Future<Map<String, dynamic>> _load(Session session) async {
    // crm/groups — o'qituvchiga faqat o'z guruhlari (server GroupAccess); faol guruhlar so'raladi.
    final results = await Future.wait<dynamic>(<Future<dynamic>>[
      session.api.get('crm/groups', query: <String, Object?>{'active': 1}),
      session.api.get('crm/timetable', query: <String, Object?>{'date': isoDay(DateTime.now())}).catchError((_) => null),
    ]);
    return <String, dynamic>{'groups': asList(results[0]), 'timetable': asMap(results[1])};
  }

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context);
    return Scaffold(
      appBar: pageBar(context, title: Text(tr('Davomat')), actions: const <Widget>[HelpButton(HelpLinks.attendance)]),
      body: AsyncView<Map<String, dynamic>>(
        load: () => _load(session),
        builder: (context, data, reload) {
          final groups = asList(data['groups'], 'groups').where((group) => group['is_active'] != false).toList();
          final todayIds = asList(asMap(data['timetable'])['items'], 'items')
              .where((item) => item['kind'] != 'school')
              .map((item) => asInt(asMap(item['group'])['id']))
              .toSet();
          final today = groups.where((group) => todayIds.contains(asInt(group['id']))).toList();
          final others = groups.where((group) => !todayIds.contains(asInt(group['id']))).toList();
          if (groups.isEmpty) {
            return ListView(children: <Widget>[EmptyState(text: tr("Guruh yo'q."))]);
          }
          return ListView(
            padding: readable(context, const EdgeInsets.all(16)),
            children: <Widget>[
              if (today.isNotEmpty) ...<Widget>[
                SectionTitle(tr('Bugungi darslar')),
                for (final group in today) _GroupTile(group: group, highlight: true),
              ],
              // Hamma guruhda bugun dars bo'lsa — bo'sh «Boshqa guruhlar» sarlavhasi chiqmaydi.
              if (others.isNotEmpty) ...<Widget>[
                SectionTitle(today.isEmpty ? session.term('groups', 'Guruhlar') : tr('Boshqa guruhlar')),
                for (final group in others) _GroupTile(group: group),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({required this.group, this.highlight = false});

  final Map<String, dynamic> group;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final teacher = asMap(group['teacher']);
    final key = 'attendance-${asInt(group['id'])}';
    final selected = isDetailSelected(context, key);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        // iPad: varaqa o'ng ustunda (MasterDetail), telefonda — yangi sahifa. Bugun darsi bor guruh — hoshiya bilan.
        color: selected ? AppColors.accentSoft : null,
        tone: highlight || selected ? AppColors.accent : null,
        onTap: () => openDetail(
          context,
          id: key,
          builder: (_) => AttendanceSheetPage(groupId: asInt(group['id']), groupName: asText(group['name'])),
        ),
        child: Row(children: <Widget>[
          IconTile(icon: Icons.groups_2_outlined, colors: highlight ? AppColors.tileFor(asText(group['name'])) : StatusColors(AppColors.muted, AppColors.sunken), size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text(asText(group['name']), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              Text(<String>[
                if (teacher['name'] != null) asText(teacher['name']),
                tr('{0} ta o\'quvchi', <Object?>[asInt(group['students_count'])]),
              ].join(', '), style: TextStyle(color: AppColors.muted)),
            ]),
          ),
          Icon(Icons.chevron_right, color: AppColors.subtle),
        ]),
      ),
    );
  }
}

class AttendanceSheetPage extends StatefulWidget {
  const AttendanceSheetPage({super.key, required this.groupId, required this.groupName});

  final int groupId;
  final String groupName;

  @override
  State<AttendanceSheetPage> createState() => _AttendanceSheetPageState();
}

class _AttendanceSheetPageState extends State<AttendanceSheetPage> {
  DateTime _day = DateTime.now();
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  String? _error;
  List<Map<String, dynamic>> _students = <Map<String, dynamic>>[];
  final Map<int, String?> _status = <int, String?>{};
  final TextEditingController _topic = TextEditingController();
  MasterDetailState? _owner;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // iPad ikki ustunli rejim: boshqa guruh tanlanganda saqlanmagan belgilar so'raladi.
    final owner = detailOwner(context);
    if (owner != null && owner != _owner) {
      _owner = owner;
      owner.guard = _allowLeave;
    }
  }

  @override
  void dispose() {
    if (_owner?.guard == _allowLeave) _owner?.guard = null;
    _topic.dispose();
    super.dispose();
  }

  Future<bool> _allowLeave() async {
    if (!_dirty) return true;
    return confirm(context, tr("Saqlanmagan o'zgarishlar bor. Sahifadan chiqilsa, ular yo'qoladi. Davom etilsinmi?"));
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sheet = asMap(await AppScope.read(context).api.get('crm/attendance', query: <String, Object?>{
        'group_id': widget.groupId,
        'date': isoDay(_day),
      }));
      final students = asList(sheet['students'], 'students');
      setState(() {
        _students = students;
        _status
          ..clear()
          ..addEntries(students.map((s) => MapEntry<int, String?>(asInt(s['id']), s['status']?.toString())));
        _topic.text = asText(asMap(sheet['lesson'])['topic']);
        _loading = false;
        _dirty = false;
      });
    } on ApiException catch (error) {
      setState(() {
        _error = error.message;
        _loading = false;
      });
    }
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime.now().subtract(const Duration(days: 120)),
      lastDate: DateTime.now(),
    );
    if (picked == null || !mounted) return;
    if (_dirty && !await confirm(context, tr('Saqlanmagan davomat belgilari bor. Ular saqlanmasdan tashlab yuborilsinmi?'))) return;
    setState(() => _day = picked);
    await _load();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await AppScope.read(context).api.put('crm/attendance', <String, Object?>{
        'group_id': widget.groupId,
        'date': isoDay(_day),
        'topic': _topic.text.trim().isEmpty ? null : _topic.text.trim(),
        'marks': _students
            .map((student) => <String, Object?>{'student_id': asInt(student['id']), 'status': _status[asInt(student['id'])]})
            .toList(),
      });
      if (!mounted) return;
      setState(() => _dirty = false);
      showMessage(context, tr('Saqlandi.'));
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _setAll(String status) {
    setState(() {
      for (final student in _students) {
        if (student['enrollment'] == 'frozen') continue;
        _status[asInt(student['id'])] = status;
      }
      _dirty = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final marked = _status.values.where((value) => value != null).length;
    // O'ng ustunda (iPad) sahifa yopilmaydi — saqlanmagan belgilarni [_allowLeave] himoya qiladi.
    final embedded = isEmbeddedDetail(context);
    return PopScope(
      canPop: !_dirty || embedded,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await confirm(context, tr("Saqlanmagan o'zgarishlar bor. Sahifadan chiqilsa, ular yo'qoladi. Davom etilsinmi?"))) {
          if (context.mounted) Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: pageBar(context,
          automaticallyImplyLeading: !isEmbeddedDetail(context),
          title: Text(widget.groupName),
          actions: <Widget>[
            TextButton.icon(
              onPressed: _pickDay,
              icon: const Icon(Icons.calendar_today, size: 18),
              label: Text(date(_day.toIso8601String())),
            ),
          ],
        ),
        body: _loading
            ? const SkeletonList(count: 6)
            : _error != null
                ? ErrorState(message: _error!, onRetry: _load)
                : ListView(
                    padding: readable(context, const EdgeInsets.fromLTRB(16, 12, 16, 100)),
                    children: <Widget>[
                      TextField(controller: _topic, decoration: InputDecoration(labelText: tr('Mavzu (ixtiyoriy)')), onChanged: (_) => _dirty = true),
                      const SizedBox(height: 12),
                      _MarkSummary(status: _status, total: _students.length, onAll: () => _setAll('present')),
                      const SizedBox(height: 10),
                      if (_students.isEmpty) EmptyState(text: tr("Guruhda o'quvchi yo'q.")),
                      for (final student in _students) ...<Widget>[
                        _StudentMark(
                          name: asText(student['full_name']),
                          frozen: student['enrollment'] == 'frozen',
                          trial: student['enrollment'] == 'trial',
                          value: _status[asInt(student['id'])],
                          onChanged: (value) => setState(() {
                            _status[asInt(student['id'])] = value;
                            _dirty = true;
                          }),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ),
        bottomNavigationBar: _loading || _error != null
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  // Obuna «faqat o'qish»da saqlash 402 bilan rad etiladi — tugma o'chiq, sabab yozilgan.
                  child: AppScope.of(context).readOnly
                      ? Text(tr("Obuna muddati tugagan: ma'lumotlar ko'rinadi, lekin yangi yozuv kiritib bo'lmaydi."),
                          textAlign: TextAlign.center, style: TextStyle(color: AppColors.warning))
                      : FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                        : Text(tr('Saqlash')),
                  ),
                ),
              ),
      ),
    );
  }
}

/// Belgilanganlar xulosasi: son va holatlar bo'yicha bitta chiziq (yashil — keldi, qizil — kelmadi, sariq — kechikdi).
class _MarkSummary extends StatelessWidget {
  const _MarkSummary({required this.status, required this.total, required this.onAll});

  final Map<int, String?> status;
  final int total;
  final VoidCallback onAll;

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{for (final key in attendanceLabels.keys) key: status.values.where((value) => value == key).length};
    final marked = counts.values.fold<int>(0, (sum, value) => sum + value);
    final duration = Motion.duration(context, AppDurations.d3);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        Row(children: <Widget>[
          Expanded(
            child: Text(tr('Belgilangan: {0} / {1}', <Object?>[marked, total]),
                style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600, fontFeatures: AppTheme.tabular)),
          ),
          TextButton.icon(onPressed: onAll, icon: const Icon(Icons.done_all, size: 20), label: Text(tr('Hammasi keldi'))),
        ]),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 8,
              child: LayoutBuilder(builder: (context, box) {
                final width = box.maxWidth;
                return Stack(children: <Widget>[
                  Container(color: AppColors.sunken),
                  Row(children: <Widget>[
                    for (final key in attendanceLabels.keys)
                      AnimatedContainer(
                        duration: duration,
                        curve: Curves.easeOutCubic,
                        width: total == 0 ? 0 : width * (counts[key] ?? 0) / total,
                        color: key == 'excused' ? AppColors.lineStrong : (key == 'present' ? AppColors.toneSuccess : (key == 'absent' ? AppColors.toneDanger : AppColors.toneWarning)),
                      ),
                  ]),
                ]);
              }),
            ),
          ),
        ),
      ]),
    );
  }
}

/// O'quvchi qatori: belgilangan holat chap chetda hoshiya bo'lib ko'rinadi (keldi — yashil, kelmadi — qizil ...).
class _StudentMark extends StatelessWidget {
  const _StudentMark({required this.name, required this.value, required this.onChanged, this.frozen = false, this.trial = false});

  final String name;
  final String? value;
  final bool frozen;
  final bool trial;
  final ValueChanged<String?> onChanged;

  static Color? _tone(String? value) => switch (value) {
        'present' => AppColors.toneSuccess,
        'absent' => AppColors.toneDanger,
        'late' => AppColors.toneWarning,
        'excused' => AppColors.lineStrong,
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    return AppCard(
      tone: _tone(value) ?? Colors.transparent,
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Row(children: <Widget>[
          Avatar(name, size: 32),
          const SizedBox(width: 10),
          Expanded(child: Text(name, style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink))),
          if (frozen) Pill(tr('Muzlatilgan'), color: AppColors.muted),
          if (trial) Pill(tr('Sinov darsida'), color: AppColors.brand),
        ]),
        const SizedBox(height: 8),
        // 4 holat bitta qatorda (tor telefonda ham ikki qatorga tushmaydi).
        Row(children: <Widget>[
          for (final entry in attendanceLabels.entries) ...<Widget>[
            if (entry.key != attendanceLabels.keys.first) const SizedBox(width: 6),
            Expanded(child: _StatusChoice(
              label: tr(entry.value),
              selected: value == entry.key,
              color: attendanceColors[entry.key] ?? AppColors.brand,
              onTap: () => onChanged(value == entry.key ? null : entry.key),
            )),
          ],
        ]),
      ]),
    );
  }
}

class _StatusChoice extends StatelessWidget {
  const _StatusChoice({required this.label, required this.selected, required this.color, required this.onTap});

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final duration = Motion.duration(context, AppDurations.d1);
    return Semantics(
      button: true,
      selected: selected,
      child: Pressable(
        child: AnimatedContainer(
          duration: duration,
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: selected ? AppColors.soft(color) : AppColors.card,
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(color: selected ? color : AppColors.line, width: selected ? 1.6 : 1),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.control),
              onTap: onTap,
              child: Container(
                height: 42,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(label, maxLines: 1, style: TextStyle(color: selected ? color : AppColors.ink, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, fontSize: 14)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
