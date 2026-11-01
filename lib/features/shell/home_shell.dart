// Asosiy oyna (3.4): menyu veb menyusi tartibida (lib/core/nav.dart ← resources/js/nav/build.js), pastki navigatsiya —
// vebdagi `bottomNav()`: menyuning birinchi 4 bo'limi + «Yana» (qolgan bo'limlar, til, rejim, chiqish). Bo'lim ichida bir
// nechta yorliq bo'lsa — tepada yorliqlar (veb: SectionTabs). Ota-onada bitta bo'lim — pastki menyuda uning yorliqlari.
import 'package:flutter/material.dart';

import '../chat/chat_pages.dart';
import '../documents/documents_pages.dart';
import '../../core/adaptive.dart';
import '../../core/api.dart';
import '../../core/app_update.dart';
import '../../core/feedback.dart';
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
import '../auth/organization_picker.dart';
import '../access/checkin_page.dart';
import '../access/kiosk_page.dart';
import '../access/sms_gateway_page.dart';
import '../billing/billing_page.dart';
import '../callcenter/callcenter_page.dart';
import '../crm/device_sms_page.dart';
import '../crm/leads_page.dart';
import '../crm/tasks_page.dart';
import '../feedback/feedback_pages.dart';
import '../finance/finance_page.dart';
import '../finance/p2p_page.dart';
import '../fun/achievements_page.dart';
import '../fun/games_page.dart';
import '../fun/labs_page.dart';
import '../guardian/guardian_home_page.dart';
import '../lms/lms_staff_pages.dart';
import '../notifications/notifications_page.dart';
import '../olympiad/olympiads_page.dart';
import '../platform/platform_pages.dart';
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

/// Menyu bandlari kalitlari: ota-onaning yagona sahifasi va «Yana».
const String _guardianKey = '__guardian';
const String _moreKey = '__more';

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  /// Tanlangan band kaliti (bo'lim kaliti, [_guardianKey] yoki [_moreKey]); bo'sh — birinchi band.
  /// Kalit bo'yicha: iPad burilganda yoki Split View o'lchami o'zgarganda menyu bandlari soni o'zgarsa ham tanlov saqlanadi.
  String _selected = '';

  /// Ochilgan bandlar: IndexedStack hamma sahifani birdaniga qurmasin.
  final Set<String> _visited = <String>{};

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
      // Yangi versiya chiqqan bo'lsa (server «Ilovalar» sozlamasi) — kuniga bir marta taklif.
      AppUpdate.maybeNotify(context, session.api);
      if (session.memberships.isNotEmpty) refreshChatUnread(session.api);
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
    // 3.5: murojaatga javob (server 1.38: type=support, route=info.support.ticket, token).
    routes['support'] = (data) {
      final token = asText(data['token']);
      return RegExp(r'^[A-Za-z0-9]{40}$').hasMatch(token) ? TicketPage(token: token) : const SupportPage();
    };
    // 1.39: mijozlar fikri — yangi fikr / mas'ul (rahbar paneli) va muallifga javob.
    routes['feedback'] = (data) {
      final s = session();
      if (!s.can('feedback_manage')) return null;
      final id = asInt(data['feedback_id']);
      return id > 0 ? FeedbackAdminDetailPage(id: id) : const MasterDetail(master: FeedbackAdminPage());
    };
    routes['feedback_reply'] = (data) {
      final id = asInt(data['feedback_id']);
      return id > 0 ? MyFeedbackDetailPage(id: id) : const MyFeedbackPage(initialTab: 1);
    };
    // 3.13: yangi xabar (server 1.47: type=chat, thread_id).
    routes['chat'] = (data) {
      final id = asInt(data['thread_id']);
      return id > 0 ? ChatThreadPage(threadId: id) : const ChatListPage();
    };
    // 3.13: yangi hujjat (server 1.47: type=document, document_id).
    routes['document'] = (data) {
      final id = asInt(data['document_id']);
      return id > 0 ? MyDocumentPage(id: id) : const MyDocumentsPage();
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

  void _go(String key) => setState(() {
        _selected = key;
        _visited.add(key);
      });

  void _home(Map<String, dynamic> data) {
    if (!mounted) return;
    _go('');
    if (AppScope.read(context).isGuardian) GuardianFocus.request.value = data;
  }

  ValueNotifier<String?> _request(String section) => _tabRequests.putIfAbsent(section, () => ValueNotifier<String?>(null));

  /// Yorliq sahifasi (nav kaliti → sahifa). null — mobilda sahifa yo'q.
  Widget? _page(Session session, String key) {
    switch (key) {
      case 'home':
        if (session.isStudent) return StudentHomePage(onOpen: _open);
        return StaffHomePage(onOpen: _open);
      // 3.7: iPad — ro'yxat va tafsilot ikki ustunda (lib/core/adaptive.dart MasterDetail); telefonda o'zgarishsiz.
      case 'students':
        return MasterDetail(master: const StudentsPage(), hint: tr("O'quvchini tanlang — kartasi shu yerda ochiladi."));
      case 'crm.leads':
        return const LeadsPage();
      case 'attendance':
        return MasterDetail(master: const AttendancePage(), hint: tr('Guruhni tanlang — davomat varaqasi shu yerda ochiladi.'));
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
        return MasterDetail(master: const FinancePage(), hint: tr("To'lov yoki qarzdorni tanlang — o'quvchi kartasi shu yerda ochiladi."));
      case 'crm.debtors':
        return MasterDetail(master: const FinancePage(initialTab: 1), hint: tr("To'lov yoki qarzdorni tanlang — o'quvchi kartasi shu yerda ochiladi."));
      case 'feedback':
        return MasterDetail(master: const FeedbackAdminPage(), hint: tr('Fikrni tanlang — tafsilot va javob shu yerda.'));
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
      // 3.11: platforma egasi paneli.
      case 'platform.dashboard':
        return const PlatformDashboardPage();
      case 'platform.organizations':
        return const PlatformOrganizationsPage();
      case 'platform.invoices':
        return const PlatformInvoicesPage();
      case 'platform.requests':
        return const PlatformRequestsPage();
      case 'platform.support':
        return const PlatformSupportPage();
      case 'platform.sessions':
        return const PlatformSessionsPage();
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
        return MasterDetail(master: const JournalPage(), hint: tr('Jurnalni tanlang — darslar va baholar shu yerda ochiladi.'));
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
      _go(_guardianKey);
      return;
    }
    if (key == 'pay') {
      startOnlinePayment(context);
      return;
    }
    final sections = buildNav(navContextOf(session));
    final bottom = bottomNav(sections, limit: navLimit(isWideScreen(context)));
    final section = sectionOfTab(sections, key);
    if (section != null && bottom.any((item) => item.section == section.key)) {
      _request(section.key).value = key;
      _go(section.key);
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
    final color = Color(sectionColorOf(section.key));
    if (pages.length == 1) {
      // Bosh sahifadan boshqa bo'limda — sahifa sarlavhasi bandi (bo'lim belgisi va yo'li).
      if (section.key == 'home') return pages.values.first;
      return SectionScope(
        section: section.key,
        label: section.label,
        cluster: clusterOf(section.key),
        color: color,
        icon: navIcon(section.icon),
        child: pages.values.first,
      );
    }
    return SectionTabsPage(key: ValueKey<String>('section-${section.key}'), section: section, color: color, pages: pages, request: _request(section.key));
  }

  /// «Yana»: pastki menyuga sig'magan bo'limlar (to'dalar bo'yicha), ilova bandlari, keyin sozlamalar.
  Widget _more(Session session, List<NavSection> overflow) {
    final colored = AppColors.choice.coloredIcons;
    Color? colorOf(String section) => colored ? Color(sectionColorOf(section)) : null;
    final groups = <String, List<Widget>>{};
    String groupOf(String section) => clusterOf(section) ?? tr("Bo'limlar");
    for (final section in overflow) {
      for (final tab in section.tabs) {
        final title = section.tabs.length > 1 ? '${section.label}: ${tab.label}' : tab.label;
        if (session.isGuardian) {
          groups.putIfAbsent(groupOf(section.key), () => <Widget>[]).add(
                MenuTile(icon: navIcon(tab.icon.isEmpty ? section.icon : tab.icon), color: colorOf(section.key), label: tab.label, onTap: () => _open(tab.key)),
              );
        } else if (_page(session, tab.key) != null) {
          final page = _page(session, tab.key)!;
          groups.putIfAbsent(groupOf(section.key), () => <Widget>[]).add(
                MenuTile(
                  icon: navIcon(section.icon),
                  color: colorOf(section.key),
                  label: title,
                  badge: tab.key == 'feedback' ? _feedbackBadge(session) : 0,
                  page: SectionScope.none(child: page),
                ),
              );
        }
      }
    }
    final app = <Widget>[
      // 3.13: suhbatlar (o'quvchi ↔ ustoz, ota-ona ↔ o'qituvchi, guruh kanallari, izohlar).
      if (session.memberships.isNotEmpty)
        ValueListenableBuilder<int>(
          valueListenable: chatUnread,
          builder: (context, unread, _) => MenuTile(icon: Icons.forum_outlined, color: AppColors.brand, label: tr('Suhbatlar'), badge: unread, page: const ChatListPage()),
        ),
      MenuTile(icon: Icons.notifications_none_rounded, color: AppColors.accent, label: tr('Bildirishnomalar'), page: const NotificationsPage()),
      // 1.39: mijozlar fikri — markaz rahbariyatiga (EduX jamoasiga yoziladigan «Murojaatlar» dan alohida).
      if (session.can('feedback_submit'))
        MenuTile(icon: Icons.rate_review_outlined, color: colored ? Color(sectionColorOf('feedback')) : null, label: tr('Fikr bildirish'), page: const MyFeedbackPage()),
      // Platforma egasining o'zi EduX jamoasi — unga «Yordam so'rovlari» (platforma) bo'limi bor.
      if (!session.isPlatformOwnerOnly)
        MenuTile(
          icon: Icons.support_agent_outlined,
          color: colored ? Koshin.feruza : null,
          label: tr('Murojaatlar'),
          page: MasterDetail(master: const SupportPage(), hint: tr('Murojaatni tanlang — yozishma shu yerda ochiladi.')),
        ),
    ];
    return SettingsPage(groups: <MenuGroup>[
      for (final entry in groups.entries) MenuGroup(entry.key, entry.value),
      MenuGroup(tr('Xabarlar va yordam'), app),
    ]);
  }

  /// Fikrlar paneli (1.39): «Yangi» holatdagi fikrlar soni — menyu belgisi.
  int _feedbackBadge(Session session) => session.can('feedback_manage') ? feedbackNewCount(session.context) : 0;

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context);
    final wide = isWideScreen(context);
    final sections = buildNav(navContextOf(session));
    final bottom = bottomNav(sections, limit: navLimit(wide));
    final overflow = overflowSections(sections, bottom);
    final guardian = bottom.isNotEmpty && bottom.first.kind == 'tab';
    final feedbackSection = sectionOfTab(sections, 'feedback')?.key;
    final feedbackBadge = _feedbackBadge(session);

    final keys = <String>[];
    final pages = <Widget>[];
    final destinations = <AdaptiveDestination>[];
    if (guardian) {
      keys.add(_guardianKey);
      pages.add(GuardianHomePage(tab: _guardianTab));
      for (final item in bottom) {
        destinations.add(AdaptiveDestination(icon: navIcon(item.icon), label: item.label, color: Color(sectionColorOf(item.section))));
      }
    } else {
      for (final item in bottom) {
        final section = sections.firstWhere((candidate) => candidate.key == item.section);
        keys.add(section.key);
        pages.add(_sectionPage(session, section));
        destinations.add(AdaptiveDestination(
          icon: navIcon(item.icon),
          label: item.label,
          badge: section.key == feedbackSection ? feedbackBadge : 0,
          color: Color(sectionColorOf(section.key)),
        ));
      }
    }
    keys.add(_moreKey);
    pages.add(_more(session, overflow));
    final feedbackInMore = feedbackSection != null && !keys.contains(feedbackSection);
    destinations.add(AdaptiveDestination(icon: Icons.menu, label: tr('Yana'), badge: feedbackInMore ? feedbackBadge : 0));

    final current = keys.contains(_selected) ? _selected : keys.first;
    _visited.add(current);
    final stackIndex = keys.indexOf(current);

    return ValueListenableBuilder<String>(
      valueListenable: _guardianTab,
      builder: (context, guardianTab, _) {
        var selected = stackIndex;
        if (guardian) {
          // Ota-ona: tanlangan yorliq menyuda bo'lsa — o'sha band, aks holda «Yana».
          final active = bottomActive(bottom, tab: guardianTab);
          selected = current == _moreKey ? destinations.length - 1 : (active == null ? destinations.length - 1 : bottom.indexWhere((item) => item.key == active));
        }
        return AdaptiveNavScaffold(
          wide: wide,
          destinations: destinations,
          selected: selected,
          railHeader: session.isPlatformOwnerOnly
              ? RailOrg(name: tr('EduX platformasi'), logo: null, subtitle: tr('Platforma egasi'))
              : RailOrg(name: session.organizationName, logo: session.organizationLogo, subtitle: session.membership == null ? '' : roleLabel(session.membership!.role)),
          onSelect: (i) {
            if (guardian && i < bottom.length) {
              _guardianTab.value = bottom[i].key;
              _go(_guardianKey);
            } else {
              _go(guardian ? _moreKey : keys[i.clamp(0, keys.length - 1)]);
            }
          },
          top: session.readOnly
              ? _ReadOnlyBanner(
                  suspended: session.suspended,
                  onTap: session.canManageBilling && !session.suspended
                      ? () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const BillingPage()))
                      : null,
                )
              : null,
          body: MediaQuery.removePadding(
            context: context,
            removeTop: session.readOnly,
            child: IndexedStack(index: stackIndex, children: <Widget>[
              for (var i = 0; i < pages.length; i++)
                KeyedSubtree(
                  key: ValueKey<String>('shell-${keys[i]}'),
                  child: _visited.contains(keys[i]) ? TabVisibility(visible: i == stackIndex, child: pages[i]) : const SizedBox.shrink(),
                ),
            ]),
          ),
        );
      },
    );
  }
}

/// Bo'lim ichidagi yorliqlar (veb: SectionTabs, 1.40 — sahifa sarlavhasi bandida): har sahifa o'z sarlavha panelida bo'lim
/// yo'li va yorliqlarni ko'rsatadi ([SectionScope], [pageBar]); tanlangan sahifa birinchi ochilganda quriladi.
class SectionTabsPage extends StatefulWidget {
  const SectionTabsPage({super.key, required this.section, required this.color, required this.pages, this.request});

  final NavSection section;
  final Color color;
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
    final meta = <SectionTab>[for (final tab in tabs) SectionTab(tab.key, tab.label)];
    final cluster = clusterOf(widget.section.key);
    return IndexedStack(index: _index, children: <Widget>[
      for (var i = 0; i < pages.length; i++)
        _visited.contains(i)
            ? SectionScope(
                section: widget.section.key,
                label: widget.section.label,
                cluster: cluster,
                color: widget.color,
                icon: navIcon(widget.section.icon),
                tabs: meta,
                selected: i,
                onSelect: _select,
                child: TabVisibility(visible: i == _index && outerVisible, child: pages[i]),
              )
            : const SizedBox.shrink(),
    ]);
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

