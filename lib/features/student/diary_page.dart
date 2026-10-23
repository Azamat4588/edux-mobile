// Kundalik (maktab): haftalik dars jadvali — mavzu, uy vazifasi, baho, davomat. Ota-ona farzandini tanlaydi.
import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../guardian/guardian_repository.dart';
import '../staff/students_page.dart';

class DiaryPage extends StatefulWidget {
  const DiaryPage({super.key, this.studentId});

  /// Ota-ona uchun: qaysi farzand (berilmasa — ro'yxatdan tanlanadi).
  final int? studentId;

  @override
  State<DiaryPage> createState() => _DiaryPageState();
}

class _DiaryPageState extends State<DiaryPage> {
  int? _studentId;
  List<GuardianChild> _children = <GuardianChild>[];

  @override
  void initState() {
    super.initState();
    _studentId = widget.studentId;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadChildren());
  }

  Future<void> _loadChildren() async {
    final session = AppScope.read(context);
    if (!session.isGuardian) return;
    try {
      final children = await GuardianRepository(session).children();
      if (!mounted) return;
      setState(() {
        _children = children;
        _studentId ??= children.isNotEmpty ? children.first.id : null;
      });
    } catch (_) {
      // Ro'yxatsiz ham ishlaydi: server birinchi farzandni ko'rsatadi.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Kundalik')),
        actions: <Widget>[
          if (_children.length > 1)
            PopupMenuButton<int>(
              icon: const Icon(Icons.switch_account_outlined),
              onSelected: (id) => setState(() => _studentId = id),
              itemBuilder: (context) =>
                  _children.map((child) => PopupMenuItem<int>(value: child.id, child: Text(child.name))).toList(),
            ),
        ],
      ),
      body: DiaryWeekView(key: ValueKey<int?>(_studentId), studentId: _studentId),
    );
  }
}

/// Haftalik kundalik (sahifa tanasi): o'quvchi o'zi uchun (studentId: null) yoki ota-ona farzandi uchun.
class DiaryWeekView extends StatefulWidget {
  const DiaryWeekView({super.key, this.studentId});

  final int? studentId;

  @override
  State<DiaryWeekView> createState() => _DiaryWeekViewState();
}

class _DiaryWeekViewState extends State<DiaryWeekView> {
  String? _date;
  int _version = 0;

  void _go(String? date) {
    if (date == null) return;
    setState(() {
      _date = date;
      _version++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final repository = GuardianRepository(AppScope.of(context));
    return AsyncView<Map<String, dynamic>>(
      key: ValueKey<String>('${widget.studentId}-$_date-$_version'),
      load: () => repository.diaryWeek(widget.studentId, date: _date),
      // Joriy hafta internetsiz ham ko'rinsin
      cacheKey: _date == null ? 'diary_${widget.studentId ?? 'me'}' : null,
      decode: asMap,
      builder: (context, data, reload) {
        if (data['has_year'] == false) {
          return ListView(children: <Widget>[
            EmptyState(text: tr("Maktabda o'quv yili hali ochilmagan. Dars jadvali va baholar shu yerda paydo bo'ladi.")),
          ]);
        }
        final days = asList(data['days'], 'days');
        final today = asText(data['today']);
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: <Widget>[
            Row(children: <Widget>[
              IconButton(onPressed: () => _go(data['previous']?.toString()), icon: const Icon(Icons.chevron_left)),
              Expanded(
                child: Column(children: <Widget>[
                  Text('${date(data['week_start'])} – ${date(data['week_end'])}',
                      textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
                  if (asMap(data['student'])['full_name'] != null)
                    Text(asText(asMap(data['student'])['full_name']), style: TextStyle(color: AppColors.muted, fontSize: 13)),
                ]),
              ),
              IconButton(onPressed: () => _go(data['next']?.toString()), icon: const Icon(Icons.chevron_right)),
            ]),
            if (days.isEmpty) EmptyState(text: tr('Dars yo\'q')),
            for (final day in days) ...<Widget>[
              const SizedBox(height: 10),
              _DayCard(day: day, isToday: asText(day['date']) == today),
            ],
          ],
        );
      },
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({required this.day, required this.isToday});

  final Map<String, dynamic> day;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final items = asList(day['items'], 'items');
    final parsed = parseDate(day['date']) ?? DateTime.now();
    return AppCard(
      padding: EdgeInsets.zero,
      color: isToday ? AppColors.soft(AppColors.brand) : AppColors.card,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(children: <Widget>[
            Text(dayTitle(parsed), style: TextStyle(fontWeight: FontWeight.w800, color: isToday ? AppColors.brand : AppColors.ink)),
            if (isToday) ...<Widget>[const SizedBox(width: 8), Pill(tr('Bugun'))],
          ]),
        ),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
            child: Text(day['in_term'] == false ? tr("Ta'til yoki dars bo'lmaydigan kun.") : tr('Dars yo\'q'),
                style: TextStyle(color: AppColors.muted)),
          ),
        for (final item in items) ...<Widget>[
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              SizedBox(
                width: 46,
                child: Column(children: <Widget>[
                  Text('${asInt(item['period_number'])}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  Text(asText(item['starts_at']), style: TextStyle(color: AppColors.muted, fontSize: 11)),
                ]),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  Text(asText(item['subject']), style: const TextStyle(fontWeight: FontWeight.w700)),
                  if (item['topic'] != null) Text(asText(item['topic']), style: TextStyle(color: AppColors.muted)),
                  if (item['homework'] != null && asText(item['homework']).isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('🏠 ${asText(item['homework'])}', style: const TextStyle(fontSize: 13)),
                    ),
                  if (item['note'] != null && asText(item['note']).isNotEmpty)
                    Text(asText(item['note']), style: TextStyle(fontSize: 12, color: AppColors.muted)),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: <Widget>[
                if (item['mark'] != null)
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: _markColor(asInt(item['mark'])).withAlpha(30), borderRadius: BorderRadius.circular(10)),
                    child: Text('${asInt(item['mark'])}',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: _markColor(asInt(item['mark'])))),
                  ),
                if (item['attendance'] != null && item['attendance'] != 'present')
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Pill(tr(attendanceLabels[item['attendance']] ?? asText(item['attendance'])),
                        color: attendanceColors[item['attendance']] ?? AppColors.muted),
                  ),
              ]),
            ]),
          ),
        ],
      ]),
    );
  }

  static Color _markColor(int mark) {
    if (mark >= 5) return AppColors.success;
    if (mark == 4) return AppColors.brand;
    if (mark == 3) return AppColors.warning;
    return AppColors.danger;
  }
}
