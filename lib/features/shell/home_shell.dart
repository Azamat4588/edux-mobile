// Asosiy oyna: pastki menyu rol va yoqilgan modullarga qarab tuziladi (xodim / o'quvchi / ota-ona).
// 3.2: bo'lim nomlari va shartlari veb menyusi bilan bir xil (docs/navigation.md, nav/build.js): rol, modul,
// qo'shimcha imkoniyat (context.features) va server yo'lining ruxsati. Tablar birinchi ochilganda quriladi.
import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/i18n.dart';
import '../../core/notification_store.dart';
import '../../core/push.dart';
import '../../core/sms_gateway.dart';
import '../access/checkin_page.dart';
import '../access/kiosk_page.dart';
import '../access/sms_gateway_page.dart';
import '../billing/billing_page.dart';
import '../callcenter/callcenter_page.dart';
import '../crm/leads_page.dart';
import '../crm/tasks_page.dart';
import '../finance/finance_page.dart';
import '../fun/achievements_page.dart';
import '../fun/games_page.dart';
import '../fun/labs_page.dart';
import '../olympiad/olympiads_page.dart';
import '../notifications/notifications_page.dart';
import '../support/support_page.dart';
import '../testing/topic_tests_page.dart';
import '../tutor/tutor_page.dart';
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

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _index = 0;

  /// Ochilgan tablar: IndexedStack hamma sahifani birdaniga qurmasin (ilova ochilganda bir xil so'rovlar
  /// parallel ketmasin — masalan «Testlar» va «Skaner» ikkalasi `exams` so'raydi).
  final Set<int> _visited = <int>{0};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ScanQueue.instance.kick();
    // Bildirishnomalar markazi: telefondagi ro'yxat; sahifasiz xabar bosilganda — bosh tab.
    NotificationStore.instance.load();
    PushService.instance.onHome = _home;
    _registerRoutes();
    // Jim xabar: navbatda telefon orqali yuboriladigan SMS bor.
    PushService.instance.dataHandlers['sms_gateway'] = (_) => SmsGatewayService.instance.poke();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) SmsGatewayService.instance.resume(AppScope.read(context));
    });
  }

  /// Push xabari bosilganda ochiladigan sahifalar. Rol, modul va qo'shimcha tekshiriladi: server yo'li bu rolga
  /// yopiq bo'lsa (masalan, ota-onaga attempts/{id}) sahifa ochilmaydi — bosh sahifa (ota-onada farzand yorlig'i).
  void _registerRoutes() {
    final routes = PushService.instance.routes;
    Session session() => AppScope.read(context);
    routes['attempt'] = (data) {
      final s = session();
      final id = asInt(data['attempt_id']);
      return s.isStudent && s.hasModule('testing') && id > 0 ? AttemptResultPage(attemptId: id) : null;
    };
    routes['certificate'] = (_) {
      final s = session();
      return s.isStudent && !s.isGuest && (s.hasModule('testing') || s.hasModule('lms')) ? const CertificatesPage() : null;
    };
    routes['assignment'] = (_) {
      final s = session();
      return s.isStudent && !s.isGuest && s.hasModule('lms') ? const AssignmentsPage() : null;
    };
    routes['task'] = (_) => session().canSeeTasks ? const TasksPage() : null;
    routes['lead'] = (data) {
      if (!session().canSeeLeads) return null;
      return asInt(data['lead_id']) > 0 ? LeadPage(leadId: asInt(data['lead_id'])) : const LeadsPage();
    };
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (PushService.instance.onHome == _home) PushService.instance.onHome = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // Fonda kelgan xabarlar va (internetsiz ochilgan bo'lsa) tashkilot konteksti yangilansin.
    NotificationStore.instance.load();
    final session = AppScope.read(context);
    if (session.contextFromCache) {
      session.loadContext().catchError((Object _) {});
    }
  }

  void _go(int index) => setState(() {
        _index = index;
        _visited.add(index);
      });

  void _home(Map<String, dynamic> data) {
    if (!mounted) return;
    _go(0);
    // Ota-ona: xabardagi farzand va yorliq (to'lov va davomat, testlar, kundalik).
    if (AppScope.read(context).isGuardian) GuardianFocus.request.value = data;
  }

  List<_Tab> _tabs(Session session) {
    if (session.isStudent) return _studentTabs(session);
    if (session.isGuardian) return _guardianTabs(session);
    return _staffTabs(session);
  }

  List<_Tab> _staffTabs(Session session) {
    final testing = session.hasModule('testing') && session.isAcademicStaff;
    final extra = <Widget>[
      _MenuTile(icon: Icons.notifications_none_rounded, label: tr('Bildirishnomalar'), page: const NotificationsPage()),
      if (session.canCallCenter) _MenuTile(icon: Icons.headset_mic_outlined, label: tr('Call markazi'), page: const CallCenterPage()),
      if (session.canSeeFinance) _MenuTile(icon: Icons.account_balance_wallet_outlined, label: tr('Moliya'), page: const FinancePage()),
      if (session.canBuildTopicTests)
        _MenuTile(icon: Icons.account_tree_outlined, label: tr("Mavzular bo'yicha test"), page: const TopicTestsPage()),
      if (session.canUseStaffAi) _MenuTile(icon: Icons.auto_awesome_outlined, label: tr('AI yordamchi'), page: const StaffAssistantPage()),
      if (session.canSeeLeads) _MenuTile(icon: Icons.person_search_outlined, label: tr('Lidlar'), page: const LeadsPage()),
      if (session.canSeeTasks) _MenuTile(icon: Icons.task_alt, label: tr('Topshiriqlar'), page: const TasksPage()),
      if (session.canMarkAttendance)
        _MenuTile(icon: Icons.fact_check_outlined, label: tr('Davomat'), page: const AttendancePage()),
      if (session.canScan) _MenuTile(icon: Icons.rate_review_outlined, label: tr('Varaqalar'), page: const ScansPage()),
      if (session.canCheckIn) _MenuTile(icon: Icons.qr_code_scanner, label: tr('Kirish nazorati'), page: const CheckinPage()),
      if (session.canUseKiosk) _MenuTile(icon: Icons.face_retouching_natural, label: tr('Kiosk rejimi'), page: const KioskPage()),
      if (session.canUseSmsGateway && Platform.isAndroid)
        _MenuTile(icon: Icons.sms_outlined, label: tr('SMS shlyuz'), page: const SmsGatewayPage()),
      if (session.canManageBilling) _MenuTile(icon: Icons.layers_outlined, label: tr('Modullar va obuna'), page: const BillingPage()),
      _MenuTile(icon: Icons.support_agent_outlined, label: tr('Murojaatlar'), page: const SupportPage()),
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
    // Qo'shimcha imkoniyatlar (server: context.features) — tashkilotda yoqilgan bo'lsagina ko'rinadi.
    // Bitta test ishtirokchisi (mehmon) uchun faqat o'sha test (veb: «Mening testim»).
    final full = !session.isGuest;
    final fun = full && session.hasFeature('fun');
    final extra = <Widget>[
      _MenuTile(icon: Icons.notifications_none_rounded, label: tr('Bildirishnomalar'), page: const NotificationsPage()),
      if (full && session.hasModule('testing') && session.hasFeature('olympiad'))
        _MenuTile(icon: Icons.emoji_events_outlined, label: tr('Olimpiadalarim'), page: const OlympiadsPage()),
      if (session.canUseTutor) _MenuTile(icon: Icons.auto_awesome_outlined, label: tr('AI ustoz'), page: const TutorPage()),
      // Yutuqlarim (1.29): XP (`fun`) va coin (CRM, coin yoqilgan bo'lsa) bitta sahifada.
      if (full && session.hasRewards)
        _MenuTile(icon: Icons.military_tech_outlined, label: tr('Yutuqlarim'), page: const AchievementsPage()),
      if (fun) _MenuTile(icon: Icons.sports_esports_outlined, label: tr("O'yinlar"), page: const GamesPage()),
      if (fun) _MenuTile(icon: Icons.science_outlined, label: tr('Laboratoriya'), page: const LabsPage()),
      if (full && session.hasModule('testing'))
        _MenuTile(icon: Icons.trending_up_rounded, label: tr('Mock natijalari'), page: const MockProgressPage()),
      if (full && (session.hasModule('testing') || session.hasModule('lms')))
        _MenuTile(icon: Icons.workspace_premium_outlined, label: tr('Sertifikatlar'), page: const CertificatesPage()),
      if (full && session.hasModule('lms'))
        _MenuTile(icon: Icons.task_outlined, label: tr('Uy vazifalari'), page: const AssignmentsPage()),
      _MenuTile(icon: Icons.support_agent_outlined, label: tr('Murojaatlar'), page: const SupportPage()),
    ];
    return <_Tab>[
      _Tab(tr('Bosh sahifa'), Icons.home_outlined, Icons.home, const StudentHomePage()),
      if (session.hasModule('testing')) _Tab(tr('Testlar'), Icons.quiz_outlined, Icons.quiz, const MyTestsPage()),
      if (full && session.hasModule('lms')) _Tab(tr('Kurslar'), Icons.menu_book_outlined, Icons.menu_book, const CoursesPage()),
      if (full && session.hasModule('school')) _Tab(tr('Kundalik'), Icons.event_note_outlined, Icons.event_note, const DiaryPage()),
      _Tab(tr("Ko'proq"), Icons.menu, Icons.menu, SettingsPage(extra: extra)),
    ];
  }

  /// Ota-ona: bitta «Farzandim» (farzand almashtirgich + Umumiy / Kundalik / Testlar / To'lov va davomat yorliqlari).
  List<_Tab> _guardianTabs(Session session) {
    final extra = <Widget>[
      _MenuTile(icon: Icons.notifications_none_rounded, label: tr('Bildirishnomalar'), page: const NotificationsPage()),
      _MenuTile(icon: Icons.support_agent_outlined, label: tr('Murojaatlar'), page: const SupportPage()),
    ];
    return <_Tab>[
      _Tab(tr('Farzandim'), Icons.family_restroom_outlined, Icons.family_restroom, const GuardianHomePage()),
      _Tab(tr("Ko'proq"), Icons.menu, Icons.menu, SettingsPage(extra: extra)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context);
    final tabs = _tabs(session);
    final index = _index.clamp(0, tabs.length - 1);
    return Scaffold(
      body: Column(children: <Widget>[
        if (session.readOnly)
          _ReadOnlyBanner(
            suspended: session.suspended,
            onTap: session.canManageBilling && !session.suspended
                ? () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const BillingPage()))
                : null,
          ),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: session.readOnly,
            child: IndexedStack(index: index, children: <Widget>[
              for (var i = 0; i < tabs.length; i++) _visited.contains(i) || i == index ? tabs[i].page : const SizedBox.shrink(),
            ]),
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
  const _ReadOnlyBanner({required this.suspended, this.onTap});

  /// Platforma ma'muriyati obunani to'xtatgan (muddat tugaganidan farqli xabar — veb bilan bir xil).
  final bool suspended;

  /// Rahbar uchun: «Modullar va obuna» sahifasini ochish (to'lov).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.soft(AppColors.warning),
      child: InkWell(
        onTap: onTap,
        child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(children: <Widget>[
            const Icon(Icons.lock_clock_outlined, color: AppColors.warning, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                suspended
                    ? tr("Obuna to'xtatilgan: ma'lumotlar ko'rinadi, lekin yangi yozuv kiritib bo'lmaydi. Platforma ma'muriyatiga murojaat qiling.")
                    : tr("Obuna muddati tugagan: ma'lumotlar ko'rinadi, lekin yangi yozuv kiritib bo'lmaydi."),
                style: const TextStyle(fontSize: 13),
              ),
            ),
            if (onTap != null) const Icon(Icons.chevron_right, color: AppColors.warning),
          ]),
        ),
      ),
      ),
    );
  }
}
