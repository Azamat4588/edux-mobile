// Asosiy oyna (3.4): menyu veb menyusi tartibida (lib/core/nav.dart ← resources/js/nav/build.js), pastki navigatsiya —
// vebdagi `bottomNav()`: menyuning birinchi 4 bo'limi + «Yana» (qolgan bo'limlar, til, rejim, chiqish). Bo'lim ichida bir
// nechta yorliq bo'lsa — tepada yorliqlar (veb: SectionTabs). Ota-onada bitta bo'lim — pastki menyuda uning yorliqlari.
import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/bank_sms.dart';
import '../../core/home_widgets.dart';
import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/notification_store.dart';
import '../../core/push.dart';
import '../../core/session.dart';
import '../../core/sms_gateway.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../access/checkin_page.dart';
import '../access/kiosk_page.dart';
import '../access/sms_gateway_page.dart';
import '../billing/billing_page.dart';
import '../callcenter/callcenter_page.dart';
import '../crm/device_sms_page.dart';
import '../crm/leads_page.dart';
import '../crm/tasks_page.dart';
import '../finance/finance_page.dart';
import '../finance/p2p_page.dart';
import '../fun/achievements_page.dart';
import '../fun/games_page.dart';
import '../fun/labs_page.dart';
import '../guardian/guardian_home_page.dart';
import '../lms/lms_staff_pages.dart';
import '../notifications/notifications_page.dart';
import '../olympiad/olympiads_page.dart';
import '../scanner/scan_queue.dart';
import '../scanner/scanner_hub_page.dart';
import '../scanner/scans_page.dart';
import '../settings/settings_page.dart';
import '../staff/attendance_page.dart';
import '../staff/exams_page.dart';
import '../staff/journal_page.dart';
import '../staff/staff_home_page.dart';
import '../staff/students_page.dart';
import '../student/assignments_page.dart';
import '../student/certificates_page.dart';
import '../student/courses_page.dart';
import '../student/diary_page.dart';
import '../student/my_payments_page.dart';
import '../student/my_tests_page.dart';
import '../student/online_pay.dart';
import '../student/student_home_page.dart';
import '../support/support_page.dart';
import '../testing/topic_tests_page.dart';
import '../tutor/tutor_page.dart';

/// Menyu konteksti Session'dan (rol, atamalar va ruxsatlar).
NavContext navContextOf(Session session) => NavContext(
      role: session.role,
      can: session.can,
      studentsLabel: session.term('students', "O'quvchilar"),
      groupsLabel: asText(asMap(session.context['terms'])['groups'], 'Guruhlar'),
    );

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _index = 0;

  /// Ochilgan tablar: IndexedStack hamma sahifani birdaniga qurmasin.
  final Set<int> _visited = <int>{0};

  /// Bo'lim ichidagi yorliqni tashqaridan tanlash (bosh sahifa kartasi, push).
  final Map<String, ValueNotifier<String?>> _tabRequests = <String, ValueNotifier<String?>>{};

  /// Ota-ona: pastki menyu yorliqlari bitta «Farzandim» sahifasini boshqaradi.
  final ValueNotifier<String> _guardianTab = ValueNotifier<String>('child');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ScanQueue.instance.kick();
    NotificationStore.instance.load();
    PushService.instance.onHome = _home;
    _registerRoutes();
    // Jim xabar: navbatda telefon orqali yuboriladigan SMS bor (scope=platform — platforma navbati).
    PushService.instance.dataHandlers['sms_gateway'] = (data) {
      if (asText(data['scope']) == 'platform') {
        SmsGatewayService.platform.poke();
      } else {
        SmsGatewayService.organization.poke();
      }
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final session = AppScope.read(context);
      SmsGatewayService.organization.resume(session);
      SmsGatewayService.platform.resume(session);
      BankSmsForwarder.instance.resume(session);
    });
  }

  /// Push xabari bosilganda ochiladigan sahifalar (rol, modul va qo'shimcha tekshiriladi).
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
    // 1.35: dars savoli (o'qituvchiga) va javob (o'quvchiga), kurs e'loni.
    routes['lesson_question'] = (_) => session().canTeachLms ? const LmsQuestionsPage() : null;
    routes['lesson_answer'] = (data) {
      final s = session();
      final lesson = asInt(data['lesson_id']);
      return s.isStudent && s.hasModule('lms') && lesson > 0 ? LessonPage(lessonId: lesson) : null;
    };
    routes['course_announcement'] = (data) {
      final s = session();
      final course = asInt(data['course_id']);
      return s.isStudent && s.hasModule('lms') && course > 0 ? CoursePage(courseId: course, title: tr('Kurs')) : null;
    };
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (PushService.instance.onHome == _home) PushService.instance.onHome = null;
    for (final notifier in _tabRequests.values) {
      notifier.dispose();
    }
    _guardianTab.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    NotificationStore.instance.load();
    final session = AppScope.read(context);
    if (session.contextFromCache) {
      session.loadContext().catchError((Object _) {});
    }
    BankSmsForwarder.instance.drain();
  }

  void _go(int index) => setState(() {
        _index = index;
        _visited.add(index);
      });

  void _home(Map<String, dynamic> data) {
    if (!mounted) return;
    _go(0);
    if (AppScope.read(context).isGuardian) GuardianFocus.request.value = data;
  }

  ValueNotifier<String?> _request(String section) => _tabRequests.putIfAbsent(section, () => ValueNotifier<String?>(null));

  /// Yorliq sahifasi (nav kaliti → sahifa). null — mobilda sahifa yo'q.
  Widget? _page(Session session, String key) {
    switch (key) {
      case 'home':
        if (session.isStudent) return StudentHomePage(onOpen: _open);
        return StaffHomePage(onOpen: _open);
      case 'students':
        return const StudentsPage();
      case 'crm.leads':
        return const LeadsPage();
      case 'attendance':
        return const AttendancePage();
      case 'access.checkin':
        return const CheckinPage();
      case 'access.kiosk':
        return const KioskPage();
      case 'lms.questions':
        return const LmsQuestionsPage();
      case 'lms.announcements':
        return const LmsAnnouncementsPage();
      case 'exams':
        return const ExamsPage();
      case 'scanner':
        return const ScannerHubPage();
      case 'scans':
        return const ScansPage();
      case 'topics':
        return const TopicTestsPage();
      case 'crm.payments':
        return const FinancePage();
      case 'crm.debtors':
        return const FinancePage(initialTab: 1);
      case 'pay.p2p':
        return const P2pPage();
      case 'crm.callcenter':
        return const CallCenterPage();
      case 'sms.gateway':
        return const SmsGatewayPage();
      case 'sms.device':
        return const DeviceSmsPage();
      case 'platform.sms':
        return const SmsGatewayPage(platform: true);
      case 'crm.tasks':
        return const TasksPage();
      case 'billing':
        return const BillingPage();
      case 'ai.staff':
        return const StaffAssistantPage();
      case 'my':
        return const MyTestsPage();
      case 'my.progress':
        return const MockProgressPage();
      case 'olympiads':
        return const OlympiadsPage();
      case 'lms.my.courses':
        return const CoursesPage();
      case 'lms.my.assignments':
        return const AssignmentsPage();
      case 'fun.labs':
        return const LabsPage();
      case 'fun.games':
        return const GamesPage();
      case 'school.diary':
        return const DiaryPage();
      case 'fun.achievements':
        return const AchievementsPage();
      case 'my.certificates':
        return const CertificatesPage();
      case 'my.tutor':
        return const TutorPage();
      case 'school.journal':
        return const JournalPage();
      case 'my.payments':
        return const MyPaymentsPage();
    }
    return null;
  }

  /// Bosh sahifa kartasi yoki tezkor tugma bosilganda: pastki menyudagi bo'lim bo'lsa — unga o'tadi, aks holda sahifa ochiladi.
  void _open(String key) {
    final session = AppScope.read(context);
    if (key == 'payment.take') {
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const StudentsPage(forPayment: true)));
      return;
    }
    if (session.isGuardian) {
      _guardianTab.value = key == 'pay' ? 'child.payments' : key;
      _go(0);
      return;
    }
    if (key == 'pay') {
      startOnlinePayment(context);
      return;
    }
    final sections = buildNav(navContextOf(session));
    final bottom = bottomNav(sections);
    final section = sectionOfTab(sections, key);
    final index = section == null ? -1 : bottom.indexWhere((item) => item.section == section.key);
    if (index >= 0) {
      _request(section!.key).value = key;
      _go(index);
      return;
    }
    final page = _page(session, key);
    if (page != null) Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  Widget _sectionPage(Session session, NavSection section) {
    final pages = <NavTab, Widget>{};
    for (final tab in section.tabs) {
      final page = _page(session, tab.key);
      if (page != null) pages[tab] = page;
    }
    if (pages.length == 1) return pages.values.first;
    return SectionTabsPage(key: ValueKey<String>('section-${section.key}'), pages: pages, request: _request(section.key));
  }

  /// «Yana»: pastki menyuga sig'magan bo'limlar, bildirishnomalar, murojaatlar, keyin sozlamalar.
  Widget _more(Session session, List<NavSection> overflow) {
    final colored = AppColors.choice.coloredIcons;
    final extra = <Widget>[
      _MenuTile(icon: Icons.notifications_none_rounded, label: tr('Bildirishnomalar'), page: const NotificationsPage()),
      for (final section in overflow)
        for (final tab in section.tabs)
          if (session.isGuardian)
            ListTile(
              leading: Icon(navIcon(tab.icon.isEmpty ? section.icon : tab.icon), color: colored ? Color(sectionColors[section.key] ?? 0xFF64748B) : null),
              title: Text(tab.label),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _open(tab.key),
            )
          else if (_page(session, tab.key) != null)
            _MenuTile(
              icon: navIcon(section.icon),
              color: colored ? Color(sectionColors[section.key] ?? 0xFF64748B) : null,
              label: section.tabs.length > 1 ? '${section.label} · ${tab.label}' : tab.label,
              page: _page(session, tab.key)!,
            ),
      _MenuTile(icon: Icons.support_agent_outlined, label: tr('Murojaatlar'), page: const SupportPage()),
    ];
    return SettingsPage(extra: extra);
  }

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context);
    final sections = buildNav(navContextOf(session));
    final bottom = bottomNav(sections);
    final overflow = overflowSections(sections, bottom);
    final guardian = bottom.isNotEmpty && bottom.first.kind == 'tab';

    final pages = <Widget>[];
    final destinations = <NavigationDestination>[];
    if (guardian) {
      pages.add(GuardianHomePage(tab: _guardianTab));
      for (final item in bottom) {
        destinations.add(NavigationDestination(icon: Icon(navIcon(item.icon)), label: item.label));
      }
    } else {
      for (final item in bottom) {
        final section = sections.firstWhere((candidate) => candidate.key == item.section);
        pages.add(_sectionPage(session, section));
        destinations.add(NavigationDestination(icon: Icon(navIcon(item.icon)), label: item.label));
      }
    }
    pages.add(_more(session, overflow));
    destinations.add(NavigationDestination(icon: const Icon(Icons.menu), label: tr('Yana')));

    return ValueListenableBuilder<String>(
      valueListenable: _guardianTab,
      builder: (context, guardianTab, _) {
        final stackIndex = _index.clamp(0, pages.length - 1);
        var selected = stackIndex;
        if (guardian) {
          // Ota-ona: tanlangan yorliq pastki menyuda bo'lsa — o'sha band, aks holda «Yana».
          final active = bottomActive(bottom, tab: guardianTab);
          selected = stackIndex == pages.length - 1 ? destinations.length - 1 : (active == null ? destinations.length - 1 : bottom.indexWhere((item) => item.key == active));
        }
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
                child: IndexedStack(index: stackIndex, children: <Widget>[
                  for (var i = 0; i < pages.length; i++)
                    _visited.contains(i) || i == stackIndex ? TabVisibility(visible: i == stackIndex, child: pages[i]) : const SizedBox.shrink(),
                ]),
              ),
            ),
          ]),
          bottomNavigationBar: destinations.length < 2
              ? null
              : NavigationBar(
                  selectedIndex: selected.clamp(0, destinations.length - 1),
                  onDestinationSelected: (i) {
                    if (guardian && i < bottom.length) {
                      _guardianTab.value = bottom[i].key;
                      _go(0);
                    } else {
                      _go(guardian ? pages.length - 1 : i);
                    }
                  },
                  destinations: destinations,
                ),
        );
      },
    );
  }
}

/// Bo'lim ichidagi yorliqlar (veb: SectionTabs): tepada yorliqlar, ostida tanlangan sahifa (birinchi ochilganda quriladi).
class SectionTabsPage extends StatefulWidget {
  const SectionTabsPage({super.key, required this.pages, this.request});

  final Map<NavTab, Widget> pages;
  final ValueNotifier<String?>? request;

  @override
  State<SectionTabsPage> createState() => _SectionTabsPageState();
}

class _SectionTabsPageState extends State<SectionTabsPage> {
  int _index = 0;
  final Set<int> _visited = <int>{0};

  @override
  void initState() {
    super.initState();
    widget.request?.addListener(_onRequest);
    _onRequest();
  }

  @override
  void dispose() {
    widget.request?.removeListener(_onRequest);
    super.dispose();
  }

  void _onRequest() {
    final key = widget.request?.value;
    if (key == null) return;
    final index = widget.pages.keys.toList().indexWhere((tab) => tab.key == key);
    widget.request!.value = null;
    if (index >= 0) _select(index);
  }

  void _select(int index) {
    if (!mounted) return;
    setState(() {
      _index = index;
      _visited.add(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Bo'lim o'zi yashirin bo'lsa (tashqi IndexedStack) — ichidagi yorliqlar ham yashirin.
    final outerVisible = TabVisibility.of(context);
    final tabs = widget.pages.keys.toList();
    final pages = widget.pages.values.toList();
    return Column(children: <Widget>[
      Material(
        color: AppColors.chrome,
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: 46,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
              itemCount: tabs.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, i) {
                final active = i == _index;
                final onChrome = AppColors.onChrome;
                return ChoiceChip(
                  label: Text(tabs[i].label),
                  selected: active,
                  showCheckmark: false,
                  labelStyle: TextStyle(fontWeight: FontWeight.w600, color: active ? Colors.white : onChrome),
                  selectedColor: AppColors.brand,
                  backgroundColor: AppColors.chrome,
                  side: BorderSide(color: active ? AppColors.brand : AppColors.line),
                  onSelected: (_) => _select(i),
                );
              },
            ),
          ),
        ),
      ),
      Expanded(
        child: MediaQuery.removePadding(
          context: context,
          removeTop: true,
          child: IndexedStack(index: _index, children: <Widget>[
            for (var i = 0; i < pages.length; i++) _visited.contains(i) ? TabVisibility(visible: i == _index && outerVisible, child: pages[i]) : const SizedBox.shrink(),
          ]),
        ),
      ),
    ]);
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({required this.icon, required this.label, required this.page, this.color});

  final IconData icon;
  final String label;
  final Widget page;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: color),
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
              Icon(Icons.lock_clock_outlined, color: AppColors.warning, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  suspended
                      ? tr("Obuna to'xtatilgan: ma'lumotlar ko'rinadi, lekin yangi yozuv kiritib bo'lmaydi. Platforma ma'muriyatiga murojaat qiling.")
                      : tr("Obuna muddati tugagan: ma'lumotlar ko'rinadi, lekin yangi yozuv kiritib bo'lmaydi."),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              if (onTap != null) Icon(Icons.chevron_right, color: AppColors.warning),
            ]),
          ),
        ),
      ),
    );
  }
}
