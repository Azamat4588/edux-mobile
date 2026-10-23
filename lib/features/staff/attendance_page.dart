// Davomat (CRM guruhlari): guruh va kunni tanlab, har o'quvchini belgilash. Bir bosishda «Hammasi keldi».
import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/help_links.dart';
import '../../core/i18n.dart';
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
      appBar: AppBar(title: Text(tr('Davomat')), actions: const <Widget>[HelpButton(HelpLinks.attendance)]),
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
            padding: const EdgeInsets.all(16),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => AttendanceSheetPage(groupId: asInt(group['id']), groupName: asText(group['name'])),
        )),
        child: Row(children: <Widget>[
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: (highlight ? AppColors.success : AppColors.brand).withAlpha(26),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.groups_2_outlined, color: highlight ? AppColors.success : AppColors.brand),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text(asText(group['name']), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              Text(<String>[
                if (teacher['name'] != null) asText(teacher['name']),
                tr('{0} ta o\'quvchi', <Object?>[asInt(group['students_count'])]),
              ].join(' · '), style: TextStyle(color: AppColors.muted)),
            ]),
          ),
          Icon(Icons.chevron_right, color: AppColors.muted),
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _topic.dispose();
    super.dispose();
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
          ..addEntries(students.map((s) => MapEntry<int, String?>(asInt(s['id']), s['status'] as String?)));
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
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await confirm(context, tr("Saqlanmagan o'zgarishlar bor. Sahifadan chiqilsa, ular yo'qoladi. Davom etilsinmi?"))) {
          if (context.mounted) Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
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
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ErrorState(message: _error!, onRetry: _load)
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                    children: <Widget>[
                      TextField(controller: _topic, decoration: InputDecoration(labelText: tr('Mavzu (ixtiyoriy)')), onChanged: (_) => _dirty = true),
                      const SizedBox(height: 12),
                      Row(children: <Widget>[
                        Expanded(
                          child: Text(tr('Belgilangan: {0} / {1}', <Object?>[marked, _students.length]),
                              style: TextStyle(color: AppColors.muted)),
                        ),
                        TextButton.icon(
                          onPressed: () => _setAll('present'),
                          icon: const Icon(Icons.done_all),
                          label: Text(tr('Hammasi keldi')),
                        ),
                      ]),
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
                          textAlign: TextAlign.center, style: const TextStyle(color: AppColors.warning))
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

class _StudentMark extends StatelessWidget {
  const _StudentMark({required this.name, required this.value, required this.onChanged, this.frozen = false, this.trial = false});

  final String name;
  final String? value;
  final bool frozen;
  final bool trial;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Row(children: <Widget>[
          Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600))),
          if (frozen) Pill(tr('Muzlatilgan'), color: AppColors.muted),
          if (trial) Pill(tr('Sinov darsida'), color: AppColors.brand),
        ]),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: attendanceLabels.entries.map((entry) {
            final selected = value == entry.key;
            final color = attendanceColors[entry.key] ?? AppColors.brand;
            return ChoiceChip(
              label: Text(tr(entry.value)),
              selected: selected,
              selectedColor: color.withAlpha(40),
              labelStyle: TextStyle(color: selected ? color : AppColors.ink, fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
              onSelected: (on) => onChanged(on ? entry.key : null),
            );
          }).toList(),
        ),
      ]),
    );
  }
}
