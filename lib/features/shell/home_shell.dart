// Asosiy oyna: pastki menyu rol va yoqilgan modullarga qarab tuziladi (xodim / o'quvchi / ota-ona).
import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/i18n.dart';
import '../../core/push.dart';
import '../crm/leads_page.dart';
import '../crm/tasks_page.dart';
import '../student/certificates_page.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../guardian/guardian_home_page.dart';
import '../scanner/scan_queue.dart';
import '../scanner/scanner_hub_page.dart';
import '../scanner/scans_page.dart';
import '../settings/settings_page.dart';
import '../staff/attendance_page.dart';
import '../staff/exams_page.dart';
import '../staff/staff_home_page.dart';
import '../staff/students_page.dart';
import '../student/assignments_page.dart';
import '../student/courses_page.dart';
import '../student/diary_page.dart';
import '../student/my_tests_page.dart';
import '../student/student_home_page.dart';

class _Tab {
  const _Tab(this.label, this.icon, this.selectedIcon, this.page);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget page;
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    ScanQueue.instance.kick();
    // Push xabari bosilganda ochiladigan sahifalar.
    final routes = PushService.instance.routes;
    routes['attempt'] = (data) => asInt(data['attempt_id']) > 0 ? AttemptResultPage(attemptId: asInt(data['attempt_id'])) : null;
    routes['certificate'] = (_) => const CertificatesPage();
    routes['task'] = (_) => const TasksPage();
    routes['lead'] = (data) => asInt(data['lead_id']) > 0 ? LeadPage(leadId: asInt(data['lead_id'])) : const LeadsPage();
    routes['assignment'] = (_) => const AssignmentsPage();
  }

  void _go(int index) => setState(() => _index = index);

  List<_Tab> _tabs(Session session) {
    if (session.isStudent) return _studentTabs(session);
    if (session.isGuardian) return _guardianTabs(session);
    return _staffTabs(session);
  }

  List<_Tab> _staffTabs(Session session) {
    final testing = session.hasModule('testing') && <String>['director', 'admin', 'teacher'].contains(session.role);
    final crm = session.hasModule('crm');
    final extra = <Widget>[
      if (crm && <String>['director', 'admin', 'marketer'].contains(session.role))
        _MenuTile(icon: Icons.person_search_outlined, label: tr('Lidlar'), page: const LeadsPage()),
      if (crm) _MenuTile(icon: Icons.task_alt, label: tr('Vazifalar'), page: const TasksPage()),
      if (session.canMarkAttendance)
        _MenuTile(icon: Icons.fact_check_outlined, label: tr('Davomat'), page: const AttendancePage()),
      if (session.canScan)
        _MenuTile(icon: Icons.rate_review_outlined, label: tr('Tekshirilgan varaqalar'), page: const ScansPage()),
    ];
    return <_Tab>[
      _Tab(tr('Bosh sahifa'), Icons.home_outlined, Icons.home, StaffHomePage(onOpenTab: (key) => _openStaffTab(session, key))),
      if (testing) _Tab(tr('Testlar'), Icons.assignment_outlined, Icons.assignment, const ExamsPage()),
      if (session.canScan) _Tab(tr('Skaner'), Icons.document_scanner_outlined, Icons.document_scanner, const ScannerHubPage()),
      if (session.canSeeStudents) _Tab(session.term('students', "O'quvchilar"), Icons.people_outline, Icons.people, const StudentsPage()),
      _Tab(tr("Ko'proq"), Icons.menu, Icons.menu, SettingsPage(extra: extra)),
    ];
  }

  void _openStaffTab(Session session, String key) {
    final tabs = _staffTabs(session);
    final labels = <String, String>{
      'exams': tr('Testlar'),
      'scanner': tr('Skaner'),
      'students': session.term('students', "O'quvchilar"),
    };
    final index = tabs.indexWhere((tab) => tab.label == labels[key]);
    if (index >= 0) _go(index);
  }

  List<_Tab> _studentTabs(Session session) {
    final extra = <Widget>[
      if (session.hasModule('testing'))
        _MenuTile(icon: Icons.emoji_events_outlined, label: tr('Mock natijalarim'), page: const MockProgressPage()),
      if (session.hasModule('testing') || session.hasModule('lms'))
        _MenuTile(icon: Icons.workspace_premium_outlined, label: tr('Sertifikatlarim'), page: const CertificatesPage()),
      if (session.hasModule('lms'))
        _MenuTile(icon: Icons.task_outlined, label: tr('Uy vazifalari'), page: const AssignmentsPage()),
    ];
    return <_Tab>[
      _Tab(tr('Bosh sahifa'), Icons.home_outlined, Icons.home, const StudentHomePage()),
      if (session.hasModule('testing')) _Tab(tr('Testlar'), Icons.quiz_outlined, Icons.quiz, const MyTestsPage()),
      if (session.hasModule('lms')) _Tab(tr('Kurslar'), Icons.menu_book_outlined, Icons.menu_book, const CoursesPage()),
      if (session.hasModule('school')) _Tab(tr('Kundalik'), Icons.event_note_outlined, Icons.event_note, const DiaryPage()),
      _Tab(tr("Ko'proq"), Icons.menu, Icons.menu, SettingsPage(extra: extra)),
    ];
  }

  List<_Tab> _guardianTabs(Session session) {
    return <_Tab>[
      _Tab(tr('Farzandlarim'), Icons.family_restroom_outlined, Icons.family_restroom, const GuardianHomePage()),
      if (session.hasModule('school')) _Tab(tr('Kundalik'), Icons.event_note_outlined, Icons.event_note, const DiaryPage()),
      _Tab(tr("Ko'proq"), Icons.menu, Icons.menu, const SettingsPage()),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context);
    final tabs = _tabs(session);
    final index = _index.clamp(0, tabs.length - 1);
    return Scaffold(
      body: Column(children: <Widget>[
        if (session.readOnly) const _ReadOnlyBanner(),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: session.readOnly,
            child: IndexedStack(index: index, children: tabs.map((tab) => tab.page).toList()),
          ),
        ),
      ]),
      bottomNavigationBar: tabs.length < 2
          ? null
          : NavigationBar(
              selectedIndex: index,
              onDestinationSelected: _go,
              destinations: tabs
                  .map((tab) => NavigationDestination(icon: Icon(tab.icon), selectedIcon: Icon(tab.selectedIcon), label: tab.label))
                  .toList(),
            ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({required this.icon, required this.label, required this.page});

  final IconData icon;
  final String label;
  final Widget page;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page)),
    );
  }
}

class _ReadOnlyBanner extends StatelessWidget {
  const _ReadOnlyBanner();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.soft(AppColors.warning),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(children: <Widget>[
            const Icon(Icons.lock_clock_outlined, color: AppColors.warning, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                tr("Obuna muddati tugagan: ma'lumotlar ko'rinadi, lekin yangi yozuv kiritib bo'lmaydi."),
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
