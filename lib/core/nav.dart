// Mobil menyu (3.4): veb menyusi (resources/js/nav/build.js, docs/navigation.md) tartibi va kalitlari bilan, lekin faqat
// ilovada sahifasi bor yorliqlar. Pastki navigatsiya — vebdagi `bottomNav()`: menyuning birinchi 4 bo'limi + «Yana»;
// bitta bo'limli rolda (ota-ona) — shu bo'lim yorliqlari. Toza mantiq: test/nav_test.dart.
//
// Ruxsatlar Session'dan keladi (`NavContext.can`): modul, qo'shimcha (context.features) va rol shartlari bir joyda qoladi.
import 'i18n.dart';

/// Ikkinchi daraja: bo'lim ichidagi yorliq (ilova sahifasi).
class NavTab {
  const NavTab(this.key, this.label, {this.icon = '', this.short});

  final String key;
  final String label;
  final String icon;

  /// Pastki menyu uchun qisqa nom (uzun nom tor telefonda ikki qatorga tushib, ikonkani siljitmasin).
  final String? short;
}

/// Yuqori daraja: bo'lim (pastki navigatsiya yoki «Yana» menyusi).
class NavSection {
  const NavSection(this.key, this.label, this.icon, this.tabs);

  final String key;
  final String label;
  final String icon;
  final List<NavTab> tabs;
}

/// Pastki navigatsiya bandi.
class NavItem {
  const NavItem({required this.key, required this.label, required this.icon, required this.kind, required this.section});

  final String key;
  final String label;
  final String icon;

  /// `section` — bo'lim (ichida yorliqlar), `tab` — bitta yorliq (ota-ona).
  final String kind;
  final String section;
}

class NavContext {
  const NavContext({required this.role, required this.can, this.studentsLabel = "O'quvchilar", this.groupsLabel = 'Guruhlar'});

  final String role;

  /// Ruxsat nomi → ko'rinadimi (masalan `students`, `p2p`, `lms_staff`, `platform_sms`).
  final bool Function(String permission) can;
  final String studentsLabel;
  final String groupsLabel;
}

const List<String> _managers = <String>['director', 'admin'];

/// Ko'rinadigan yorliqlari bo'lmasa — null.
NavSection? _section(String key, String label, String icon, List<NavTab?> tabs) {
  final visible = tabs.whereType<NavTab>().toList();
  return visible.isEmpty ? null : NavSection(key, label, icon, visible);
}

NavTab? _when(bool condition, NavTab tab) => condition ? tab : null;

List<NavSection> buildNav(NavContext ctx) {
  final can = ctx.can;
  final role = ctx.role;
  final sections = <NavSection?>[];
  if (_managers.contains(role)) {
    sections.addAll(<NavSection?>[
      _section('home', tr('Bosh sahifa'), 'home', <NavTab?>[NavTab('home', tr('Bosh sahifa'))]),
      _section('students', ctx.studentsLabel, 'academic-cap', <NavTab?>[
        _when(can('students'), NavTab('students', tr("Ro'yxat"))),
        _when(can('leads'), NavTab('crm.leads', tr('Lidlar'))),
        _when(can('attendance'), NavTab('attendance', tr('Davomat'))),
        _when(can('checkin'), NavTab('access.checkin', tr('Kirish nazorati'))),
      ]),
      _education(ctx),
      _testing(ctx),
      _section('finance', tr('Moliya'), 'banknote', <NavTab?>[
        _when(can('finance'), NavTab('crm.payments', tr("To'lovlar"))),
        _when(can('p2p'), NavTab('pay.p2p', tr("Kartaga o'tkazmalar"))),
        _when(can('finance'), NavTab('crm.debtors', tr('Qarzdorlar'))),
      ]),
      _section('comms', tr('Aloqa'), 'chat', <NavTab?>[
        _when(can('callcenter'), NavTab('crm.callcenter', tr('Call markazi'))),
        _when(can('sms_gateway'), NavTab('sms.gateway', tr('SMS shlyuz'))),
        _when(can('device_sms'), NavTab('sms.device', tr("Kutilayotgan SMS'lar"))),
        _when(can('tasks'), NavTab('crm.tasks', tr('Topshiriqlar'))),
      ]),
      _section('settings', tr('Sozlamalar'), 'cog', <NavTab?>[
        _when(can('kiosk'), NavTab('access.kiosk', tr('Kiosk rejimi'))),
        _when(can('billing'), NavTab('billing', tr('Modullar va obuna'))),
        _when(can('staff_ai'), NavTab('ai.staff', tr('AI yordamchi'))),
      ]),
    ]);
  } else if (role == 'teacher') {
    final school = ctx.groupsLabel == 'Sinflar';
    sections.addAll(<NavSection?>[
      _section('home', tr('Bosh sahifa'), 'home', <NavTab?>[NavTab('home', tr('Bosh sahifa'))]),
      _section('groups', school ? tr('Sinflarim') : tr('Guruhlarim'), 'users', <NavTab?>[
        _when(can('students'), NavTab('students', ctx.studentsLabel)),
        _when(can('attendance'), NavTab('attendance', tr('Davomat'))),
        _when(can('journal'), NavTab('school.journal', tr('Jurnal'))),
        _when(can('checkin'), NavTab('access.checkin', tr('Kirish nazorati'))),
      ]),
      _education(ctx),
      _testing(ctx),
      _section('tasks', tr('Topshiriqlar'), 'list-checks', <NavTab?>[_when(can('tasks'), NavTab('crm.tasks', tr('Topshiriqlar')))]),
      _section('assistant', tr('AI yordamchi'), 'sparkle', <NavTab?>[_when(can('staff_ai'), NavTab('ai.staff', tr('AI yordamchi')))]),
    ]);
  } else if (role == 'cashier') {
    if (can('crm')) {
      sections.addAll(<NavSection?>[
        _section('home', tr('Bosh sahifa'), 'home', <NavTab?>[NavTab('home', tr('Bosh sahifa'))]),
        _section('payments', tr("To'lovlar"), 'banknote', <NavTab?>[
          NavTab('crm.payments', tr("To'lovlar")),
          _when(can('p2p'), NavTab('pay.p2p', tr("Kartaga o'tkazmalar"))),
        ]),
        _section('debtors', tr('Qarzdorlar'), 'warning', <NavTab?>[NavTab('crm.debtors', tr('Qarzdorlar'))]),
        _section('students', tr("O'quvchilar"), 'academic-cap', <NavTab?>[_when(can('students'), NavTab('students', tr("O'quvchilar")))]),
        _section('callcenter', tr('Call markazi'), 'headphones', <NavTab?>[_when(can('callcenter'), NavTab('crm.callcenter', tr('Call markazi')))]),
        _section('tasks', tr('Topshiriqlar'), 'list-checks', <NavTab?>[_when(can('tasks'), NavTab('crm.tasks', tr('Topshiriqlar')))]),
      ]);
    } else if (can('p2p')) {
      // CRMsiz (masalan, maktab + LMS): kassir kartaga o'tkazmalarni tasdiqlaydi (server: pay/p2p — crm|lms).
      sections.addAll(<NavSection?>[
        _section('home', tr('Bosh sahifa'), 'home', <NavTab?>[NavTab('home', tr('Bosh sahifa'))]),
        _section('payments', tr("To'lovlar"), 'banknote', <NavTab?>[NavTab('pay.p2p', tr("Kartaga o'tkazmalar"))]),
      ]);
    }
  } else if (role == 'marketer') {
    if (can('crm')) {
      sections.addAll(<NavSection?>[
        _section('home', tr('Bosh sahifa'), 'home', <NavTab?>[NavTab('home', tr('Bosh sahifa'))]),
        _section('leads', tr('Lidlar'), 'columns', <NavTab?>[_when(can('leads'), NavTab('crm.leads', tr('Lidlar')))]),
        _section('callcenter', tr('Call markazi'), 'headphones', <NavTab?>[_when(can('callcenter'), NavTab('crm.callcenter', tr('Call markazi')))]),
        _section('tasks', tr('Topshiriqlar'), 'list-checks', <NavTab?>[_when(can('tasks'), NavTab('crm.tasks', tr('Topshiriqlar')))]),
      ]);
    }
  } else if (role == 'student') {
    if (can('guest')) {
      sections.add(_section('my', tr('Mening testim'), 'clipboard-list', <NavTab?>[NavTab('my', tr('Mening testim'))]));
    } else {
      sections.addAll(<NavSection?>[
        _section('home', tr('Bosh sahifa'), 'home', <NavTab?>[NavTab('home', tr('Bosh sahifa'))]),
        _section('tests', tr('Testlarim'), 'clipboard-list', <NavTab?>[
          _when(can('testing'), NavTab('my', tr('Testlar'))),
          _when(can('testing'), NavTab('my.progress', tr('Mock natijalari'))),
          _when(can('olympiad'), NavTab('olympiads', tr('Olimpiadalar'))),
        ]),
        _section('courses', tr("Ta'lim"), 'book', <NavTab?>[
          _when(can('lms'), NavTab('lms.my.courses', tr('Kurslar'))),
          _when(can('lms'), NavTab('lms.my.assignments', tr('Uy vazifalari'))),
          _when(can('fun'), NavTab('fun.labs', tr('Laboratoriya'))),
          _when(can('fun'), NavTab('fun.games', tr("O'yinlar"))),
        ]),
        _section('diary', tr('Kundalik'), 'pen-line', <NavTab?>[_when(can('school'), NavTab('school.diary', tr('Kundalik')))]),
        _section('achievements', tr('Yutuqlarim'), 'trophy', <NavTab?>[
          _when(can('rewards'), NavTab('fun.achievements', can('fun') ? tr('XP va coin') : tr('Coin'))),
          _when(can('certificates'), NavTab('my.certificates', tr('Sertifikatlar'))),
        ]),
        _section('payments', tr("To'lovlarim"), 'wallet', <NavTab?>[_when(can('my_payments'), NavTab('my.payments', tr("To'lovlarim")))]),
        _section('tutor', tr('AI ustoz'), 'sparkle', <NavTab?>[_when(can('tutor'), NavTab('my.tutor', tr('AI ustoz')))]),
      ]);
    }
  } else if (role == 'guardian') {
    sections.add(_section('child', tr('Farzandim'), 'users', <NavTab?>[
      NavTab('child', tr('Umumiy'), icon: 'home'),
      _when(can('school'), NavTab('child.diary', tr('Kundalik'), icon: 'pen-line')),
      _when(can('testing'), NavTab('child.tests', tr('Testlar'), icon: 'clipboard-list')),
      _when(can('crm'), NavTab('child.payments', tr("To'lov va davomat"), icon: 'wallet', short: tr("To'lovlar"))),
      // Kurslar (1.35) oxirida: pastki menyuga 4 ta sig'adi — to'lov ota-ona uchun muhimroq.
      _when(can('lms'), NavTab('child.courses', tr('Kurslar'), icon: 'book')),
    ]));
  }
  // Platforma egasi: ilovada — platforma SMS shlyuzi (kirish va tiklash kodlari shu telefondan).
  if (can('platform_sms')) {
    sections.add(_section('platform', tr('Platforma'), 'server', <NavTab?>[NavTab('platform.sms', tr('SMS shlyuz (platforma)'))]));
  }
  return sections.whereType<NavSection>().toList();
}

NavSection? _education(NavContext ctx) {
  final can = ctx.can;
  final manager = _managers.contains(ctx.role);
  return _section('education', tr("Ta'lim"), 'book', <NavTab?>[
    // Rahbarda jurnal «Ta'lim» bo'limida (veb bilan bir xil); o'qituvchida — «Sinflarim» ichida.
    _when(manager && can('journal'), NavTab('school.journal', tr('Jurnal'))),
    _when(can('lms_staff'), NavTab('lms.questions', tr('Savol-javob'))),
    _when(can('lms_staff'), NavTab('lms.announcements', tr("E'lonlar"))),
  ]);
}

NavSection? _testing(NavContext ctx) {
  final can = ctx.can;
  if (!can('testing')) return null;
  return _section('testing', tr('Testlar'), 'clipboard-list', <NavTab?>[
    NavTab('exams', tr('Testlar')),
    _when(can('scan'), NavTab('scanner', tr('Skaner'))),
    _when(can('scan'), NavTab('scans', tr('Varaqalar'))),
    _when(can('topic_tests'), NavTab('topics', tr("Mavzular bo'yicha test"))),
  ]);
}

/// Telefondagi pastki navigatsiya: birinchi [limit] bo'lim; bitta bo'limli rolda — uning yorliqlari. «Yana» alohida qo'shiladi.
List<NavItem> bottomNav(List<NavSection> sections, {int limit = 4}) {
  if (sections.length == 1 && sections.first.tabs.length > 1) {
    final only = sections.first;
    return only.tabs
        .take(limit)
        .map((tab) => NavItem(key: tab.key, label: tab.short ?? tab.label, icon: tab.icon.isEmpty ? only.icon : tab.icon, kind: 'tab', section: only.key))
        .toList();
  }
  return sections
      .take(limit)
      .map((section) => NavItem(key: section.key, label: section.label, icon: section.icon, kind: 'section', section: section.key))
      .toList();
}

/// Ochiq sahifa pastki navigatsiyaning qaysi bandi (null — «Yana» belgilanadi).
String? bottomActive(List<NavItem> items, {String? section, String? tab}) {
  for (final item in items) {
    if (item.kind == 'tab' ? item.key == tab : item.key == section) return item.key;
  }
  return null;
}

/// Yorliq qaysi bo'limda.
NavSection? sectionOfTab(List<NavSection> sections, String tab) {
  for (final section in sections) {
    if (section.tabs.any((item) => item.key == tab)) return section;
  }
  return null;
}

/// «Yana» menyusi: pastki navigatsiyaga sig'magan bo'limlar (ota-onada — sig'magan yorliqlar).
List<NavSection> overflowSections(List<NavSection> sections, List<NavItem> bottom) {
  if (bottom.isNotEmpty && bottom.first.kind == 'tab') {
    final only = sections.first;
    final shown = bottom.map((item) => item.key).toSet();
    final rest = only.tabs.where((tab) => !shown.contains(tab.key)).toList();
    return <NavSection>[
      if (rest.isNotEmpty) NavSection(only.key, only.label, only.icon, rest),
      ...sections.skip(1),
    ];
  }
  final shown = bottom.map((item) => item.section).toSet();
  return sections.where((section) => !shown.contains(section.key)).toList();
}

/// Bo'lim rangi (veb nav/colors.js — «Rangli» menyu ikonalari): ARGB.
const Map<String, int> sectionColors = <String, int>{
  'home': 0xFF2563EB,
  'students': 0xFF7C3AED,
  'groups': 0xFF7C3AED,
  'schedule': 0xFF0891B2,
  'education': 0xFF059669,
  'courses': 0xFF059669,
  'testing': 0xFFDB2777,
  'tests': 0xFFDB2777,
  'finance': 0xFF16A34A,
  'payments': 0xFF16A34A,
  'debtors': 0xFFDC2626,
  'comms': 0xFFEA580C,
  'callcenter': 0xFFEA580C,
  'leads': 0xFF0EA5E9,
  'tasks': 0xFFD97706,
  'rewards': 0xFFCA8A04,
  'achievements': 0xFFCA8A04,
  'diary': 0xFF0D9488,
  'tutor': 0xFF9333EA,
  'assistant': 0xFF9333EA,
  'settings': 0xFF475569,
  'child': 0xFF2563EB,
  'platform': 0xFF334155,
};
