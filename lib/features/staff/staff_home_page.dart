// Xodimning bosh sahifasi: tezkor amallar, kun ko'rsatkichlari va bugungi darslar.
import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../scanner/scanner_page.dart';
import '../scanner/scans_page.dart';
import 'attendance_page.dart';
import 'students_page.dart';

class StaffHomePage extends StatelessWidget {
  const StaffHomePage({super.key, required this.onOpenTab});

  /// Pastki menyudagi bo'limga o'tish: 'exams', 'scanner', 'students'.
  final void Function(String key) onOpenTab;

  Future<Map<String, dynamic>> _load(Session session) async {
    final api = session.api;
    final today = isoDay(DateTime.now());
    final results = await Future.wait<dynamic>(<Future<dynamic>>[
      api.get('overview'),
      if (session.hasModule('crm') && session.role != 'marketer')
        api.get('crm/timetable', query: <String, Object?>{'from': today, 'to': today}).catchError((_) => null),
    ]);
    return <String, dynamic>{
      'overview': asMap(results[0]),
      'timetable': results.length > 1 ? asMap(results[1]) : <String, dynamic>{},
    };
  }

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context);
    final firstName = session.userName.split(' ').length > 1 ? session.userName.split(' ')[1] : session.userName;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(children: <Widget>[
          _OrgLogo(url: session.organizationLogo, name: session.organizationName),
          const SizedBox(width: 10),
          Expanded(child: Text(session.organizationName, maxLines: 1, overflow: TextOverflow.ellipsis)),
        ]),
      ),
      body: AsyncView<Map<String, dynamic>>(
        load: () => _load(session),
        builder: (context, data, reload) {
          final overview = asMap(data['overview']);
          final testing = asMap(overview['testing']);
          final crm = asMap(overview['crm']);
          final lms = asMap(overview['lms']);
          final school = asMap(overview['school']);
          final lessons = asList(asMap(data['timetable'])['items'], 'items');
          final cards = <Widget>[
            if (testing.isNotEmpty) ...<Widget>[
              StatCard(
                label: tr("Ko'rib chiqish kerak"),
                value: '${asInt(testing['needs_review'])}',
                icon: Icons.rate_review_outlined,
                color: asInt(testing['needs_review']) > 0 ? AppColors.warning : AppColors.success,
                onTap: session.canScan
                    ? () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ScansPage(initialTab: 1)))
                    : null,
              ),
              StatCard(
                label: tr('Ochiq testlar'),
                value: '${asInt(testing['open_exams'])}',
                icon: Icons.assignment_outlined,
                hint: testing['finished_week'] != null ? tr('{0} ta natija (7 kun)', <Object?>[asInt(testing['finished_week'])]) : null,
                onTap: () => onOpenTab('exams'),
              ),
            ],
            if (crm.isNotEmpty) ...<Widget>[
              StatCard(
                label: tr("Faol o'quvchilar"),
                value: '${asInt(crm['active_students'])}',
                icon: Icons.school_outlined,
                hint: asInt(crm['trial']) > 0 ? tr('{0} ta sinov darsida', <Object?>[asInt(crm['trial'])]) : null,
                onTap: session.canSeeStudents ? () => onOpenTab('students') : null,
              ),
              StatCard(
                label: tr('Qarzdorlar'),
                value: '${asInt(crm['debtors'])}',
                icon: Icons.warning_amber_rounded,
                color: AppColors.danger,
                hint: asInt(crm['debt_total']) > 0 ? money(asInt(crm['debt_total'])) : null,
              ),
              if (crm['income_today'] != null)
                StatCard(
                  label: tr('Bugungi tushum'),
                  value: groupDigits(asInt(crm['income_today'])),
                  icon: Icons.payments_outlined,
                  color: AppColors.success,
                ),
              if (crm['new_leads_today'] != null)
                StatCard(
                  label: tr('Yangi lidlar (bugun)'),
                  value: '${asInt(crm['new_leads_today'])}',
                  icon: Icons.person_add_alt,
                  hint: crm['open_leads'] != null ? tr('{0} ta faol lid', <Object?>[asInt(crm['open_leads'])]) : null,
                ),
            ],
            if (lms.isNotEmpty && lms['to_grade'] != null)
              StatCard(label: tr('Tekshirilmagan vazifalar'), value: '${asInt(lms['to_grade'])}', icon: Icons.task_outlined),
            if (school.isNotEmpty && school['lessons_today'] != null)
              StatCard(
                label: tr('Bugungi darslar (maktab)'),
                value: '${asInt(school['lessons_today'])}',
                icon: Icons.event_note_outlined,
                hint: school['year'] != null ? asText(school['year']) : null,
              ),
          ];
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: <Widget>[
              Text(tr('Assalomu alaykum, {0}', <Object?>[firstName]),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.ink)),
              const SizedBox(height: 4),
              Text(dayTitle(DateTime.now()), style: const TextStyle(color: AppColors.muted)),
              const SizedBox(height: 16),
              _QuickActions(session: session, onOpenTab: onOpenTab),
              if (cards.isNotEmpty) ...<Widget>[
                SectionTitle(tr('Bugun')),
                StatGrid(children: cards),
              ],
              if (lessons.isNotEmpty) ...<Widget>[
                SectionTitle(tr('Bugungi darslar')),
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(children: <Widget>[
                    for (var i = 0; i < lessons.length; i++) ...<Widget>[
                      if (i > 0) const Divider(),
                      _LessonRow(lesson: lessons[i]),
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

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.session, required this.onOpenTab});

  final Session session;
  final void Function(String key) onOpenTab;

  @override
  Widget build(BuildContext context) {
    final actions = <Widget>[
      if (session.canScan)
        _Action(
          icon: Icons.document_scanner,
          label: tr('Skaner'),
          color: AppColors.brand,
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ScannerPage())),
        ),
      if (session.canMarkAttendance)
        _Action(
          icon: Icons.fact_check,
          label: tr('Davomat'),
          color: AppColors.success,
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AttendancePage())),
        ),
      if (session.canTakePayments)
        _Action(
          icon: Icons.payments,
          label: tr("To'lov"),
          color: const Color(0xFF7C3AED),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const StudentsPage(forPayment: true))),
        ),
      if (session.canSeeStudents)
        _Action(icon: Icons.search, label: tr('Qidirish'), color: AppColors.warning, onTap: () => onOpenTab('students')),
    ];
    if (actions.isEmpty) return const SizedBox();
    return Row(
      children: actions
          .map((action) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: action)))
          .toList(),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.color, required this.onTap});

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
      child: Column(children: <Widget>[
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(14)),
          child: Icon(icon, color: Colors.white),
        ),
        const SizedBox(height: 8),
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      ]),
    );
  }
}

class _LessonRow extends StatelessWidget {
  const _LessonRow({required this.lesson});

  final Map<String, dynamic> lesson;

  @override
  Widget build(BuildContext context) {
    final group = asMap(lesson['group']);
    final cancelled = lesson['status'] == 'cancelled';
    return ListTile(
      leading: SizedBox(
        width: 56,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
          Text(asText(lesson['start']), style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(asText(lesson['end']), style: const TextStyle(color: AppColors.muted, fontSize: 12)),
        ]),
      ),
      title: Text(
        <String>[asText(group['name']), if (lesson['course'] != null) asText(lesson['course'])].join(' · '),
        style: TextStyle(fontWeight: FontWeight.w600, decoration: cancelled ? TextDecoration.lineThrough : null),
      ),
      subtitle: Text(<String>[
        if (lesson['teacher'] != null) asText(lesson['teacher']),
        if (lesson['room'] != null) asText(lesson['room']),
      ].join(' · ')),
      trailing: lesson['kind'] == 'school' ? Pill(tr('Maktab'), color: AppColors.muted) : null,
    );
  }
}

class _OrgLogo extends StatelessWidget {
  const _OrgLogo({required this.url, required this.name});

  final String? url;
  final String name;

  @override
  Widget build(BuildContext context) {
    if (url == null) return Avatar(name, size: 32);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(url!, width: 32, height: 32, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Avatar(name, size: 32)),
    );
  }
}
