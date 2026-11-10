// Davomat (CRM guruhlari): guruh va kunni tanlab, har o'quvchini belgilash. Bir bosishda «Hammasi keldi».
// 3.16: bugungi darsda «Kamera bilan» — o'quvchi kartasidagi QR/shtrix-kod (checkins/scan + group_id, «Kirish nazorati»
// qo'shimchasi); qo'shimcha yoqilmagan bo'lsa — tushuntirish oynasi.
// 3.17: «Kamera bilan» — tanlov: QR karta (kamera), Face ID (veb sahifa WebView'da), skaner qurilmasi (kamerasiz CheckinPage).
import 'package:flutter/material.dart';

import '../../core/adaptive.dart';
import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/help_links.dart';
import '../../core/i18n.dart';
import '../../core/motion.dart';
import '../../core/profile.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../access/checkin_page.dart';
import '../family/family_pages.dart' show openProgressPdf;
import '../access/face_checkin_page.dart';
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
        // Internetsiz — oxirgi yuklangan guruhlar ro'yxati ko'rsatiladi.
        cacheKey: 'attendance_groups',
        decode: asMap,
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
        // iPad: varaqa o'ng ustunda (MasterDetail), telefonda — yangi sahifa. Bugun darsi bor guruh — ajratilgan.
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

  /// 3.22 (server 2.54): o'tilgan dars (oilaga hisobot shu darsga yoziladi) va tayyor iboralar.
  Map<String, dynamic>? _lesson;
  List<String> _templates = <String>[];

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
      if (!mounted) return;
      setState(() {
        _students = students;
        _status
          ..clear()
          ..addEntries(students.map((s) => MapEntry<int, String?>(asInt(s['id']), s['status']?.toString())));
        _topic.text = asText(asMap(sheet['lesson'])['topic']);
        _lesson = sheet['lesson'] is Map ? asMap(sheet['lesson']) : null;
        _templates = asRawList(sheet['report_templates']).map((item) => '$item').toList();
        _loading = false;
        _dirty = false;
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
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime.now().subtract(const Duration(days: 120)),
      lastDate: DateTime.now(),
    );
    if (picked == null || !mounted) return;
    if (_dirty && !await confirm(context, tr('Saqlanmagan davomat belgilari bor. Ular saqlanmasdan tashlab yuborilsinmi?'))) return;
    if (!mounted) return;
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
            // Ball va izoh (vebda kiritilgan) qaytarib yuboriladi — aks holda server ularni o'chirib yuboradi.
            .map((student) => <String, Object?>{
                  'student_id': asInt(student['id']),
                  'status': _status[asInt(student['id'])],
                  'score': student['score'] == null ? null : asInt(student['score']),
                  'comment': student['comment'] == null || asText(student['comment']).isEmpty ? null : asText(student['comment']),
                })
            .toList(),
      });
      if (!mounted) return;
      setState(() => _dirty = false);
      showMessage(context, tr('Saqlandi.'));
      // Dars yaratilgan bo'lsa — «Oilaga hisobot» tugmasi ochilsin.
      await _load();
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Kamera bilan belgilangan o'quvchi: varaqada «keldi» (server allaqachon yozgan; «kechikdi» bo'lsa — o'zgarmaydi).
  void _markScanned(int studentId) {
    if (!mounted || !_students.any((student) => asInt(student['id']) == studentId)) return;
    final current = _status[studentId];
    if (current == 'present' || current == 'late') return;
    setState(() => _status[studentId] = 'present');
  }

  Future<void> _openCamera() async {
    final session = AppScope.read(context);
    if (!session.hasFeature('access')) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.qr_code_scanner),
          title: Text(tr('Kamera bilan')),
          content: Text(tr("QR karta va Face ID bilan belgilash «Kirish nazorati» qo'shimchasi bilan ishlaydi. Yoqish uchun direktorga murojaat qiling.")),
          actions: <Widget>[TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Tushunarli')))],
        ),
      );
      return;
    }
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          ListTile(
            leading: const Icon(Icons.qr_code_scanner),
            title: Text(tr('QR karta (kamera)')),
            subtitle: Text(tr("Kartadagi QR yoki shtrix-kodni telefon kamerasi bilan o'qish")),
            onTap: () => Navigator.pop(context, 'qr'),
          ),
          ListTile(
            leading: const Icon(Icons.face_outlined),
            title: const Text('Face ID'),
            subtitle: Text(tr("O'quvchi yuzini telefon kamerasiga ko'rsatadi")),
            onTap: () => Navigator.pop(context, 'face'),
          ),
          ListTile(
            leading: const Icon(Icons.document_scanner_outlined),
            title: Text(tr('Skaner qurilmasi')),
            subtitle: Text(tr('USB yoki Bluetooth QR/shtrix-kod skaneri')),
            onTap: () => Navigator.pop(context, 'device'),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (choice == null || !mounted) return;
    final wasDirty = _dirty;
    final navigator = Navigator.of(context, rootNavigator: true);
    if (choice == 'face') {
      // Veb sahifa o'zi belgilaydi — qaytgach varaqa serverdan yangilanadi.
      await navigator.push(MaterialPageRoute<bool>(
        builder: (_) => FaceCheckinPage(groupId: widget.groupId, groupName: widget.groupName),
      ));
    } else {
      await navigator.push(MaterialPageRoute<void>(
        builder: (_) => CheckinPage(
          groupId: widget.groupId,
          groupName: widget.groupName,
          camera: choice == 'qr',
          onMarked: _markScanned,
        ),
      ));
    }
    if (!mounted) return;
    // Saqlanmagan qo'lda belgilar bo'lmasa — varaqa serverdan qayta olinadi (aniq holat: keldi / kechikdi).
    if (!wasDirty && !_dirty) await _load();
  }

  Future<void> _openReport() async {
    final sent = await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(
      builder: (_) => LessonReportFormPage(
        groupId: widget.groupId,
        groupName: widget.groupName,
        day: isoDay(_day),
        lesson: _lesson ?? <String, dynamic>{},
        students: _students.where((student) => student['enrollment'] != 'frozen').toList(),
        templates: _templates,
      ),
    ));
    if (sent != null && mounted) await _load();
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
            if (sameDay(_day, DateTime.now()) && !AppScope.of(context).readOnly)
              IconButton(
                tooltip: tr('Kamera bilan'),
                icon: const Icon(Icons.qr_code_scanner),
                onPressed: _loading ? null : _openCamera,
              ),
            // 3.22 (server 2.55): oylik hisobot (oilaga).
            IconButton(
              tooltip: tr('Oylik hisobot'),
              icon: const Icon(Icons.insights_outlined),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => MonthlyReportsPage(groupId: widget.groupId, groupName: widget.groupName))),
            ),
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
                      : Row(children: <Widget>[
                          Expanded(
                            child: FilledButton(
                              onPressed: _saving ? null : _save,
                              child: _saving
                                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                                  : Text(tr('Saqlash')),
                            ),
                          ),
                          // 3.22: darsdan keyin oilaga hisobot (mavzu, uy vazifasi, har o'quvchiga izoh).
                          if (_lesson != null && asText(_lesson!['status'], 'held') == 'held') ...<Widget>[
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _saving || _dirty ? null : _openReport,
                                icon: Icon(_lesson!['report_sent_at'] != null ? Icons.mark_email_read_outlined : Icons.outgoing_mail, size: 18),
                                label: Text(tr('Oilaga hisobot'), maxLines: 1, overflow: TextOverflow.ellipsis),
                              ),
                            ),
                          ],
                        ]),
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
                        height: 8,
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

/// O'quvchi qatori: belgilangan holat kartani shu rangga moyil qiladi (keldi — pista, kelmadi — anor ...).
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


/// 3.22 (server 2.54): darsdan keyingi hisobot — dars mazmuni, uy vazifasi va har o'quvchiga oilaga izoh. «Saqlash» —
/// qoralama, «Oilaga yuborish» — ota-ona va o'quvchiga push (ilovada «Dars hisobotlari»).
class LessonReportFormPage extends StatefulWidget {
  const LessonReportFormPage({super.key, required this.groupId, required this.groupName, required this.day, required this.lesson, required this.students, required this.templates});

  final int groupId;
  final String groupName;
  final String day;
  final Map<String, dynamic> lesson;
  final List<Map<String, dynamic>> students;
  final List<String> templates;

  @override
  State<LessonReportFormPage> createState() => _LessonReportFormPageState();
}

class _LessonReportFormPageState extends State<LessonReportFormPage> {
  late final TextEditingController _summary = TextEditingController(text: asText(widget.lesson['summary']));
  late final TextEditingController _homework = TextEditingController(text: asText(widget.lesson['homework']));
  late final Map<int, TextEditingController> _notes = <int, TextEditingController>{
    for (final student in widget.students) asInt(student['id']): TextEditingController(text: asText(student['family_note'])),
  };
  int? _focused;
  bool _busy = false;

  @override
  void dispose() {
    _summary.dispose();
    _homework.dispose();
    for (final controller in _notes.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit(bool send) async {
    final sentBefore = widget.lesson['report_sent_at'] != null;
    if (send && sentBefore && !await confirm(context, tr('Hisobot oilaga qayta yuborilsinmi?'))) return;
    if (!mounted) return;
    final api = AppScope.read(context).api;
    setState(() => _busy = true);
    try {
      await api.put('crm/attendance/report', <String, Object?>{
        'group_id': widget.groupId,
        'date': widget.day,
        'summary': _summary.text.trim().isEmpty ? null : _summary.text.trim(),
        'homework': _homework.text.trim().isEmpty ? null : _homework.text.trim(),
        'notes': _notes.entries.map((entry) => <String, Object?>{'student_id': entry.key, 'note': entry.value.text.trim().isEmpty ? null : entry.value.text.trim()}).toList(),
        'send': send,
      });
      if (!mounted) return;
      showMessage(context, send ? tr('Hisobot oilalarga yuborildi.') : tr('Saqlandi.'));
      Navigator.of(context).pop(send);
    } catch (error) {
      if (mounted) showMessage(context, errorText(error), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _addPhrase(String phrase) {
    final id = _focused;
    if (id == null) return;
    final controller = _notes[id]!;
    final text = controller.text.trim();
    controller.text = text.isEmpty ? tr(phrase) : '$text ${tr(phrase)}';
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final sentAt = widget.lesson['report_sent_at'];
    return Scaffold(
      appBar: pageBar(context, title: Text(tr('Oilaga hisobot'))),
      body: ListView(
        padding: readable(context, const EdgeInsets.fromLTRB(16, 12, 16, 100)),
        children: <Widget>[
          Text('${widget.groupName} · ${date(widget.day)}', style: TextStyle(color: AppColors.muted)),
          if (sentAt != null) ...<Widget>[
            const SizedBox(height: 6),
            Pill(tr('Yuborilgan: {0}', <Object>[dateTime(sentAt)]), color: AppColors.success),
          ],
          const SizedBox(height: 12),
          TextField(controller: _summary, maxLines: 3, maxLength: 2000, decoration: InputDecoration(labelText: tr("Darsda nima o'tildi"))),
          TextField(controller: _homework, maxLines: 3, maxLength: 2000, decoration: InputDecoration(labelText: tr('Uy vazifasi'))),
          SectionTitle(tr("O'quvchilarga izoh (ixtiyoriy)")),
          for (final student in widget.students) ...<Widget>[
            Focus(
              onFocusChange: (focused) {
                if (focused) setState(() => _focused = asInt(student['id']));
              },
              child: TextField(
                controller: _notes[asInt(student['id'])],
                maxLength: 500,
                decoration: InputDecoration(labelText: asText(student['full_name'])),
              ),
            ),
            // Tayyor iboralar — faqat tanlangan o'quvchi ostida.
            if (_focused == asInt(student['id']) && widget.templates.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Wrap(spacing: 6, runSpacing: 6, children: <Widget>[
                  for (final phrase in widget.templates) ActionChip(label: Text(tr(phrase), style: const TextStyle(fontSize: 12)), onPressed: () => _addPhrase(phrase)),
                ]),
              ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(children: <Widget>[
            Expanded(child: OutlinedButton(onPressed: _busy ? null : () => _submit(false), child: Text(tr('Saqlash')))),
            const SizedBox(width: 8),
            Expanded(child: FilledButton(onPressed: _busy ? null : () => _submit(true), child: Text(sentAt != null ? tr('Qayta yuborish') : tr('Oilaga yuborish')))),
          ]),
        ),
      ),
    );
  }
}


/// 3.22 (server 2.55): oylik hisobot — har o'quvchi bo'yicha tizim ko'rsatkichlari (davomat, baho, mashq) va matn
/// (o'zi yozadi yoki AI qoralama), «Oilaga yuborish».
class MonthlyReportsPage extends StatefulWidget {
  const MonthlyReportsPage({super.key, required this.groupId, required this.groupName});

  final int groupId;
  final String groupName;

  @override
  State<MonthlyReportsPage> createState() => _MonthlyReportsPageState();
}

class _MonthlyReportsPageState extends State<MonthlyReportsPage> {
  // Oy oxiri yaqin bo'lmasa — o'tgan oy (hisobot odatda oy tugagach yoziladi).
  late DateTime _month = DateTime.now().day >= 25 ? DateTime(DateTime.now().year, DateTime.now().month) : DateTime(DateTime.now().year, DateTime.now().month - 1);
  Key _view = UniqueKey();

  String get _period => '${_month.year}-${two(_month.month)}';

  void _shift(int months) => setState(() {
        _month = DateTime(_month.year, _month.month + months);
        _view = UniqueKey();
      });

  @override
  Widget build(BuildContext context) {
    final api = AppScope.of(context).api;
    final now = DateTime.now();
    return Scaffold(
      appBar: pageBar(context, title: Text(tr('Oylik hisobot')), actions: <Widget>[
        // 3.29 (server 2.66): rahbar nazorati — guruhlar bo'yicha yozilgan va yuborilgan hisobotlar.
        if (AppScope.of(context).isManager)
          IconButton(
            tooltip: tr('Nazorat'),
            icon: const Icon(Icons.fact_check_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ProgressOverviewPage(period: _period))),
          ),
      ]),
      body: Column(children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
          child: Row(children: <Widget>[
            IconButton(tooltip: tr('Oldingi oy'), icon: const Icon(Icons.chevron_left), onPressed: () => _shift(-1)),
            Expanded(child: Text('${widget.groupName} · ${monthName(_month.month)} ${_month.year}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700))),
            IconButton(
              tooltip: tr('Keyingi oy'),
              icon: const Icon(Icons.chevron_right),
              onPressed: _month.year == now.year && _month.month == now.month ? null : () => _shift(1),
            ),
          ]),
        ),
        Expanded(
          child: AsyncView<Map<String, dynamic>>(
            key: _view,
            load: () async => asMap(await api.get('crm/progress', query: <String, Object?>{'group_id': widget.groupId, 'period': _period})),
            builder: (context, data, reload) {
              final rows = asList(data['data']);
              if (rows.isEmpty) return ListView(children: <Widget>[EmptyState(text: tr("Bu oyda o'quvchi yo'q"))]);
              return ListView.separated(
                padding: readable(context, const EdgeInsets.fromLTRB(16, 8, 16, 32)),
                itemCount: rows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) => _MonthlyRow(groupId: widget.groupId, period: _period, row: rows[i], ai: data['ai'] == true),
              );
            },
          ),
        ),
      ]),
    );
  }
}

class _MonthlyRow extends StatefulWidget {
  const _MonthlyRow({required this.groupId, required this.period, required this.row, required this.ai});

  final int groupId;
  final String period;
  final Map<String, dynamic> row;
  final bool ai;

  @override
  State<_MonthlyRow> createState() => _MonthlyRowState();
}

class _MonthlyRowState extends State<_MonthlyRow> {
  late final TextEditingController _text = TextEditingController(text: asText(widget.row['text']));
  late Object? _sentAt = widget.row['sent_at'];
  bool _busy = false;

  int get _studentId => asInt(asMap(widget.row['student'])['id']);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _draft() async {
    final api = AppScope.read(context).api;
    setState(() => _busy = true);
    try {
      final res = asMap(await api.post('crm/progress/draft', <String, Object?>{'group_id': widget.groupId, 'period': widget.period, 'student_id': _studentId}));
      _text.text = asText(res['text']);
    } catch (error) {
      if (mounted) showMessage(context, errorText(error), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save(bool send) async {
    if (send && _sentAt != null && !await confirm(context, tr('Hisobot oilaga qayta yuborilsinmi?'))) return;
    if (!mounted) return;
    final api = AppScope.read(context).api;
    setState(() => _busy = true);
    try {
      final res = asMap(await api.put('crm/progress', <String, Object?>{
        'group_id': widget.groupId,
        'period': widget.period,
        'student_id': _studentId,
        'text': _text.text.trim().isEmpty ? null : _text.text.trim(),
        'send': send,
      }));
      if (!mounted) return;
      setState(() => _sentAt = res['sent_at']);
      showMessage(context, send ? tr('{0}: hisobot oilaga yuborildi.', <Object>[asText(asMap(widget.row['student'])['full_name'])]) : tr('Saqlandi.'));
    } catch (error) {
      if (mounted) showMessage(context, errorText(error), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stats = asMap(widget.row['stats']);
    final lessons = asInt(stats['lessons']);
    final facts = <String>[
      if (lessons > 0) tr('Davomat: {0}% ({1}/{2})', <Object>[asInt(stats['attendance_percent']), asInt(stats['present']), lessons]),
      if (stats['avg_score'] != null) tr("O'rtacha baho: {0}/{1}", <Object>[stats['avg_score'], stats['score_max'] ?? '']),
      if (asInt(stats['practice_days']) > 0) tr('Uyda mashq: {0} kun, {1} daqiqa', <Object>[asInt(stats['practice_days']), asInt(stats['practice_minutes'])]),
      for (final exam in asList(stats['exams'], 'exams')) '${asText(exam['title'])}: ${asText(exam['score'])}/${asText(exam['max'])}',
    ];
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        Row(children: <Widget>[
          Expanded(child: Text(asText(asMap(widget.row['student'])['full_name']), style: const TextStyle(fontWeight: FontWeight.w700))),
          if (_sentAt != null) Pill(tr('Yuborilgan'), color: AppColors.success),
        ]),
        if (facts.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(facts.join(' · '), style: TextStyle(color: AppColors.muted, fontSize: 13))),
        const SizedBox(height: 8),
        TextField(
          controller: _text,
          maxLines: 5,
          minLines: 3,
          maxLength: 4000,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(hintText: tr("Oilaga: yutuqlar, nimaga e'tibor berish kerak, keyingi oy uchun tavsiya.")),
        ),
        Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: <Widget>[
          OutlinedButton.icon(
            onPressed: _busy
                ? null
                : () => openProgressPdf(context, 'crm/progress/pdf?group_id=${widget.groupId}&student_id=$_studentId&period=${widget.period}',
                    '${asText(asMap(widget.row['student'])['full_name'])}-${widget.period}.pdf'),
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
            label: const Text('PDF'),
          ),
          if (widget.ai) OutlinedButton(onPressed: _busy ? null : _draft, child: Text(tr('AI qoralama'))),
          OutlinedButton(onPressed: _busy ? null : () => _save(false), child: Text(tr('Saqlash'))),
          FilledButton(onPressed: _busy || _text.text.trim().isEmpty ? null : () => _save(true), child: Text(_sentAt != null ? tr('Qayta yuborish') : tr('Oilaga yuborish'))),
        ]),
      ]),
    );
  }
}


/// 3.29 (server 2.66): rahbar nazorati — oy bo'yicha har guruh: o'qituvchi, yozilgan va oilaga yuborilgan hisobotlar;
/// hisobot yubormagan o'qituvchiga eslatma.
class ProgressOverviewPage extends StatefulWidget {
  const ProgressOverviewPage({super.key, required this.period});

  final String period;

  @override
  State<ProgressOverviewPage> createState() => _ProgressOverviewPageState();
}

class _ProgressOverviewPageState extends State<ProgressOverviewPage> {
  bool _busy = false;

  Future<void> _remind(int? groupId) async {
    setState(() => _busy = true);
    try {
      final res = asMap(await AppScope.read(context).api.post('crm/progress/remind', <String, Object?>{'period': widget.period, if (groupId != null) 'group_id': groupId}));
      if (!mounted) return;
      final teachers = asInt(res['teachers']);
      showMessage(context, teachers > 0 ? tr("{0} ta o'qituvchiga eslatma yuborildi.", <Object>[teachers]) : tr("Eslatma kerak emas: hammasi yuborilgan yoki o'qituvchi biriktirilmagan."));
    } catch (error) {
      if (mounted) showMessage(context, errorText(error), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = AppScope.of(context).api;
    final parts = widget.period.split('-');
    final title = parts.length == 2 ? '${monthName(int.tryParse(parts[1]) ?? 1)} ${parts[0]}' : widget.period;
    return Scaffold(
      appBar: pageBar(context, title: Text('${tr('Nazorat')} · $title')),
      body: AsyncView<Map<String, dynamic>>(
        load: () async => asMap(await api.get('crm/progress/overview', query: <String, Object?>{'period': widget.period})),
        builder: (context, data, reload) {
          final rows = asList(data['data']);
          final totals = asMap(data['totals']);
          if (rows.isEmpty) return ListView(children: <Widget>[EmptyState(text: tr("Bu oyda o'quvchi yo'q"))]);
          return ListView(
            padding: readable(context, const EdgeInsets.fromLTRB(16, 16, 16, 32)),
            children: <Widget>[
              Text(tr('{0} / {1} guruh tayyor · {2} / {3} hisobot yuborilgan',
                  <Object>[asInt(totals['done']), asInt(totals['groups']), asInt(totals['sent']), asInt(totals['students'])])),
              if (asInt(totals['done']) < asInt(totals['groups']))
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton(onPressed: _busy ? null : () => _remind(null), child: Text(tr('Hammasiga eslatma'))),
                ),
              const SizedBox(height: 8),
              for (final row in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AppCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
                      Row(children: <Widget>[
                        Expanded(child: Text(asText(asMap(row['group'])['name']), style: const TextStyle(fontWeight: FontWeight.w700))),
                        Text('${asInt(row['sent'])} / ${asInt(row['students'])}', style: TextStyle(color: row['done'] == true ? AppColors.success : AppColors.muted)),
                      ]),
                      if (row['teacher'] != null) Text(asText(asMap(row['teacher'])['name']), style: TextStyle(color: AppColors.muted, fontSize: 13)),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: asInt(row['students']) == 0 ? 0 : asInt(row['sent']) / asInt(row['students']),
                          minHeight: 6,
                          color: row['done'] == true ? AppColors.success : AppColors.accent,
                          backgroundColor: AppColors.sunken,
                        ),
                      ),
                      if (row['done'] != true && row['teacher'] != null)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(onPressed: _busy ? null : () => _remind(asInt(asMap(row['group'])['id'])), child: Text(tr('Eslatma'))),
                        ),
                    ]),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
