// Bosh sahifalar (veb 1.35, docs/design.md «Bosh sahifalar»): «Bugun» kartalari — 3–4 ta asosiy raqam oddiy so'zlar bilan,
// keyin katta tezkor tugmalar. Bu fayl — toza mantiq (server javobidan kartalar ro'yxati), test/home_today_test.dart.
//
// Manba (veb bilan bir xil): direktor/administrator va o'qituvchi — GET overview (+ CRM bo'lsa crm/dashboard, crm/timetable);
// kassir — crm/payments (bugun) va crm/debtors; marketolog — crm/leads?status=new; o'quvchi va ota-ona — my/insights.
import 'api.dart';
import 'design.dart';
import 'format.dart';
import 'i18n.dart';

/// «Bugun» kartasi: katta raqam, izoh, ixtiyoriy qo'shimcha matn, ohang (chap chiziq) va ochiladigan bo'lim (nav kaliti).
class TodayItem {
  const TodayItem({required this.key, required this.value, required this.text, this.hint = '', this.tone = TodayTone.none, this.target, this.icon = ''});

  final String key;
  final String value;
  final String text;
  final String hint;
  final TodayTone tone;

  /// Bosilganda ochiladigan yorliq (lib/core/nav.dart kalitlari, masalan `crm.debtors`).
  final String? target;

  /// Belgi nomi (veb ikonka nomi: warning, banknote, calendar ...).
  final String icon;
}

/// Tezkor harakat: katta tugma.
class QuickAction {
  const QuickAction({required this.key, required this.label, this.hint = '', this.icon = '', this.primary = false});

  final String key;
  final String label;
  final String hint;
  final String icon;
  final bool primary;
}

/// Ko'pi bilan 4 ta karta (veb: `.slice(0, 4)`).
const int todayLimit = 4;

/// Direktor va administrator (veb: ManagerHome.vue).
List<TodayItem> managerToday(Map<String, dynamic> overview, {Map<String, dynamic> dashboard = const <String, dynamic>{}, List<Map<String, dynamic>> lessons = const <Map<String, dynamic>>[]}) {
  final cards = <TodayItem>[];
  final crm = asMap(overview['crm']);
  final counters = asMap(dashboard['counters']);
  if (overview['crm'] is Map) {
    final debtors = asInt(counters['debtors'] ?? crm['debtors']);
    cards.add(TodayItem(
      key: 'debtors',
      value: '$debtors',
      text: tr("o'quvchining qarzi bor"),
      hint: debtors > 0 ? tr('Jami: {0}', <Object?>[money(asInt(counters['debt_total'] ?? crm['debt_total']))]) : tr("Hamma o'z vaqtida to'lagan"),
      tone: debtors > 0 ? TodayTone.danger : TodayTone.success,
      target: 'crm.debtors',
      icon: 'warning',
    ));
    final month = asMap(dashboard['month']);
    cards.add(TodayItem(
      key: 'income',
      value: money(asInt(crm['income_today'])),
      text: tr("bugun to'landi"),
      hint: month.isNotEmpty ? tr('Shu oy: {0}', <Object?>[money(asInt(month['income']))]) : '',
      target: 'crm.payments',
      icon: 'banknote',
    ));
    final first = _firstLesson(lessons);
    cards.add(TodayItem(
      key: 'lessons',
      value: '${lessons.length}',
      text: tr('ta dars bugun'),
      hint: first == null ? '' : tr('Birinchisi: {0}, {1}', <Object?>[asText(first['start']), asText(asMap(first['group'])['name'])]),
      target: 'attendance',
      icon: 'calendar',
    ));
    final leads = asInt(crm['new_leads_today']);
    cards.add(TodayItem(
      key: 'leads',
      value: '$leads',
      text: tr('ta yangi murojaat bugun'),
      hint: tr('Javob kutayotganlar: {0}', <Object?>[asInt(crm['open_leads'])]),
      tone: leads > 0 ? TodayTone.warning : TodayTone.none,
      target: 'crm.leads',
      icon: 'columns',
    ));
    if (asInt(crm['tasks_today']) > 0) {
      cards.add(TodayItem(key: 'tasks', value: '${asInt(crm['tasks_today'])}', text: tr('ta topshiriq bajarilishi kerak'), tone: TodayTone.warning, target: 'crm.tasks', icon: 'list-checks'));
    }
  }
  final school = asMap(overview['school']);
  if (overview['school'] is Map) {
    cards.add(TodayItem(
      key: 'school',
      value: '${asInt(school['lessons_today'])}',
      text: tr('ta maktab darsi bugun'),
      hint: asText(school['year']).isNotEmpty ? asText(school['year']) : tr("O'quv yili belgilanmagan"),
      icon: 'book',
    ));
  }
  _testingCards(cards, asMap(overview['testing']), overview['testing'] is Map, mine: false);
  final lms = asMap(overview['lms']);
  if (overview['lms'] is Map) {
    final grade = asInt(lms['to_grade']);
    cards.add(TodayItem(
      key: 'grade',
      value: '$grade',
      text: tr('ta uy vazifasi baholanmagan'),
      hint: tr('{0} ta kurs', <Object?>[asInt(lms['courses'])]),
      tone: grade > 0 ? TodayTone.warning : TodayTone.none,
      target: 'lms.questions',
      icon: 'pencil',
    ));
  }
  return cards.take(todayLimit).toList();
}

/// O'qituvchi (veb: TeacherHome.vue).
List<TodayItem> teacherToday(Map<String, dynamic> overview, {List<Map<String, dynamic>> lessons = const <Map<String, dynamic>>[]}) {
  final cards = <TodayItem>[];
  final crm = asMap(overview['crm']);
  final school = asMap(overview['school']);
  if (overview['crm'] is Map || overview['school'] is Map) {
    final first = _firstLesson(lessons, plannedOnly: true);
    cards.add(TodayItem(
      key: 'lessons',
      value: '${lessons.length + asInt(school['lessons_today'])}',
      text: tr('ta darsingiz bor bugun'),
      hint: first == null ? '' : tr('Birinchisi: {0}, {1}', <Object?>[asText(first['start']), asText(asMap(first['group'])['name'])]),
      target: 'attendance',
      icon: 'calendar',
    ));
  }
  if (overview['crm'] is Map) {
    cards.add(TodayItem(
      key: 'students',
      value: '${asInt(crm['active_students'])}',
      text: tr("faol o'quvchingiz"),
      hint: asInt(crm['trial']) > 0 ? tr('{0} ta sinov darsida', <Object?>[asInt(crm['trial'])]) : '',
      target: 'students',
      icon: 'academic-cap',
    ));
    if (asInt(crm['tasks_today']) > 0) {
      cards.add(TodayItem(key: 'tasks', value: '${asInt(crm['tasks_today'])}', text: tr('ta topshiriq bajarilishi kerak'), tone: TodayTone.warning, target: 'crm.tasks', icon: 'list-checks'));
    }
  }
  if (overview['lms'] is Map) {
    final grade = asInt(asMap(overview['lms'])['to_grade']);
    cards.add(TodayItem(
      key: 'grade',
      value: '$grade',
      text: tr('ta uy vazifasini baholash kerak'),
      tone: grade > 0 ? TodayTone.warning : TodayTone.none,
      target: 'lms.questions',
      icon: 'pencil',
    ));
  }
  _testingCards(cards, asMap(overview['testing']), overview['testing'] is Map, mine: true);
  return cards.take(todayLimit).toList();
}

/// Kassir (veb: CashierHome.vue): `payments` — crm/payments?from=bugun&to=bugun, `debtors` — crm/debtors.
List<TodayItem> cashierToday(Map<String, dynamic> payments, Map<String, dynamic> debtors) {
  final summary = asMap(payments['summary']);
  final count = asInt(summary['count']);
  final debtorCount = asInt(debtors['count']);
  return <TodayItem>[
    TodayItem(
      key: 'income',
      value: money(asInt(summary['amount'])),
      text: tr('bugun qabul qilindi'),
      hint: tr("{0} ta to'lov", <Object?>[count]),
      tone: count > 0 ? TodayTone.success : TodayTone.none,
      target: 'crm.payments',
      icon: 'banknote',
    ),
    TodayItem(
      key: 'debtors',
      value: '$debtorCount',
      text: tr("o'quvchining qarzi bor"),
      hint: debtorCount > 0 ? tr('Jami: {0}', <Object?>[money(asInt(debtors['total_debt']))]) : tr("Hamma o'z vaqtida to'lagan"),
      tone: debtorCount > 0 ? TodayTone.danger : TodayTone.success,
      target: 'crm.debtors',
      icon: 'warning',
    ),
  ];
}

/// Marketolog (veb: MarketerHome.vue): crm/leads javobidagi `counts`.
List<TodayItem> marketerToday(Map<String, dynamic> counts) {
  int count(String key) => asInt(counts[key]);
  return <TodayItem>[
    TodayItem(key: 'new', value: '${count('new')}', text: tr('ta yangi murojaat javob kutmoqda'), tone: count('new') > 0 ? TodayTone.warning : TodayTone.none, target: 'crm.leads', icon: 'columns'),
    TodayItem(key: 'contacted', value: '${count('contacted')}', text: tr("ta murojaat bilan bog'lanildi"), target: 'crm.leads', icon: 'phone'),
    TodayItem(key: 'trial', value: '${count('trial')}', text: tr('kishi sinov darsiga yozilgan'), target: 'crm.leads', icon: 'calendar'),
    TodayItem(key: 'enrolled', value: '${count('enrolled')}', text: tr("kishi o'quvchiga aylandi"), tone: count('enrolled') > 0 ? TodayTone.success : TodayTone.none, target: 'crm.leads', icon: 'academic-cap'),
  ];
}

/// O'quvchi va ota-ona (veb: StudentToday.vue): my/insights javobi; `upcoming` — o'quvchining yaqin darslari (crm/me).
List<TodayItem> studentToday(Map<String, dynamic> insights, {bool guardian = false, List<Map<String, dynamic>> upcoming = const <Map<String, dynamic>>[]}) {
  final cards = <TodayItem>[];
  final crm = asMap(insights['crm']);
  if (insights['crm'] is Map) {
    final balance = asInt(crm['balance']);
    final debt = balance < 0;
    cards.add(TodayItem(
      key: 'balance',
      value: money(balance.abs()),
      text: debt ? tr("to'lash kerak") : (balance > 0 ? tr("oldindan to'langan") : tr("Qarz yo'q")),
      hint: debt ? tr("Onlayn to'lash mumkin") : '',
      tone: debt ? TodayTone.danger : TodayTone.success,
      target: guardian ? 'child.payments' : 'pay',
      icon: 'wallet',
    ));
  }
  final testing = asMap(insights['testing']);
  if (insights['testing'] is Map) {
    final pending = asList(testing['pending'], 'pending').length;
    final average = testing['average_percent'];
    cards.add(TodayItem(
      key: 'tests',
      value: '$pending',
      text: guardian ? tr('ta test hali ishlanmagan') : tr('ta test ishlash kerak'),
      hint: average != null ? tr("O'rtacha natija: {0}%", <Object?>[number(asDouble(average))]) : (pending > 0 ? '' : tr('Hammasi ishlangan')),
      tone: pending > 0 ? TodayTone.warning : TodayTone.none,
      target: guardian ? 'child.tests' : 'my',
      icon: 'clipboard-list',
    ));
  }
  final lms = asMap(insights['lms']);
  if (insights['lms'] is Map) {
    final pending = asList(asMap(lms['assignments'])['pending'], 'pending');
    final overdue = pending.where((item) => item['overdue'] == true).length;
    cards.add(TodayItem(
      key: 'homework',
      value: '${pending.length}',
      text: tr('ta uy vazifasi topshirilmagan'),
      hint: overdue > 0 ? tr("{0} tasining muddati o'tgan", <Object?>[overdue]) : (pending.isEmpty ? tr('Hammasi bajarilgan') : ''),
      tone: overdue > 0 ? TodayTone.danger : (pending.isNotEmpty ? TodayTone.warning : TodayTone.success),
      target: guardian ? 'child.courses' : 'lms.my.assignments',
      icon: 'pencil',
    ));
  }
  final school = asMap(insights['school']);
  if (!guardian && upcoming.isNotEmpty) {
    final next = upcoming.first;
    final day = parseDate(next['date']);
    cards.add(TodayItem(
      key: 'next',
      value: asText(next['start']),
      text: tr('Keyingi dars: {0}', <Object?>[asText(next['group'])]),
      hint: <String>[if (day != null) weekdayName(day.weekday), if (asText(next['room']).isNotEmpty) asText(next['room'])].join(', '),
      icon: 'calendar',
    ));
  } else if (insights['crm'] is Map) {
    final absent = asInt(asMap(crm['attendance_30d'])['absent']);
    cards.add(TodayItem(
      key: 'attendance',
      value: '$absent',
      text: tr('marta darsga kelmagan (30 kun)'),
      tone: absent > 0 ? TodayTone.warning : TodayTone.success,
      icon: 'calendar',
    ));
  } else if (insights['school'] is Map) {
    final absent = asInt(asMap(school['absence_totals'])['absent']);
    cards.add(TodayItem(
      key: 'school',
      value: '$absent',
      text: tr('ta dars qoldirilgan (maktab)'),
      tone: absent > 0 ? TodayTone.warning : TodayTone.success,
      target: guardian ? 'child.diary' : null,
      icon: 'book',
    ));
  }
  return cards.take(todayLimit).toList();
}

void _testingCards(List<TodayItem> cards, Map<String, dynamic> testing, bool present, {required bool mine}) {
  if (!present) return;
  final review = asInt(testing['needs_review']);
  if (review > 0) {
    cards.add(TodayItem(key: 'review', value: '$review', text: tr('ta varaqa tekshirishni kutmoqda'), tone: TodayTone.warning, target: 'scans', icon: 'camera'));
  }
  cards.add(TodayItem(
    key: 'exams',
    value: '${asInt(testing['open_exams'])}',
    text: mine ? tr('ta testingiz ochiq') : tr('ta test hozir ochiq'),
    hint: tr('7 kunda {0} ta natija', <Object?>[asInt(testing['finished_week'])]),
    target: 'exams',
    icon: 'clipboard-list',
  ));
}

Map<String, dynamic>? _firstLesson(List<Map<String, dynamic>> lessons, {bool plannedOnly = false}) {
  for (final lesson in lessons) {
    if (lesson['status'] == 'planned') return lesson;
  }
  return plannedOnly || lessons.isEmpty ? null : lessons.first;
}

/// Tezkor harakatlar (veb bosh sahifalari bilan bir xil tartib), ko'pi bilan 6 ta. Kalit — nav yorlig'i yoki maxsus amal
/// (`payment.take` — to'lov qabul qilish, `pay` — onlayn to'lash).
List<QuickAction> quickActions(String role, bool Function(String permission) can, {bool debt = false, int pendingTests = 0}) {
  final list = <QuickAction>[];
  switch (role) {
    case 'director':
    case 'admin':
      if (can('crm')) {
        if (can('take_payments')) list.add(QuickAction(key: 'payment.take', label: tr("To'lov qabul qilish"), hint: tr('Naqd, karta yoki Click/Payme'), icon: 'banknote', primary: true));
        if (can('students')) list.add(QuickAction(key: 'students', label: tr("O'quvchilar"), hint: tr('Qidirish va karta'), icon: 'academic-cap'));
        if (can('attendance')) list.add(QuickAction(key: 'attendance', label: tr('Davomat qilish'), hint: tr("Bugungi darslar bo'yicha"), icon: 'check-circle'));
        if (can('leads')) list.add(QuickAction(key: 'crm.leads', label: tr('Murojaatlar'), hint: tr('Yangi lidlarga javob berish'), icon: 'columns'));
      } else if (can('students')) {
        list.add(QuickAction(key: 'students', label: tr("O'quvchilar"), icon: 'academic-cap', primary: true));
      }
      if (can('testing')) list.add(QuickAction(key: 'exams', label: tr('Test yaratish'), hint: tr("Onlayn yoki qog'oz"), icon: 'clipboard-list'));
      if (can('scan')) list.add(QuickAction(key: 'scanner', label: tr('Varaqa tekshirish'), hint: tr('Kamera bilan'), icon: 'camera'));
      if (can('lms_staff')) list.add(QuickAction(key: 'lms.questions', label: tr("O'quvchi savollari"), icon: 'question'));
    case 'teacher':
      if (can('attendance')) list.add(QuickAction(key: 'attendance', label: tr('Davomat qilish'), hint: tr('Kim keldi, kim kelmadi'), icon: 'check-circle', primary: true));
      if (can('lms_staff')) list.add(QuickAction(key: 'lms.questions', label: tr('Savollarga javob berish'), icon: 'question'));
      if (can('lms_staff')) list.add(QuickAction(key: 'lms.announcements', label: tr("E'lon yozish"), hint: tr("Kurs o'quvchilariga"), icon: 'megaphone'));
      if (can('testing')) list.add(QuickAction(key: 'exams', label: tr('Test yaratish'), hint: tr("Onlayn yoki qog'oz"), icon: 'clipboard-list'));
      if (can('scan')) list.add(QuickAction(key: 'scanner', label: tr('Varaqa tekshirish'), icon: 'camera'));
      if (list.isEmpty && can('students')) list.add(QuickAction(key: 'students', label: tr("O'quvchilarim"), icon: 'academic-cap', primary: true));
    case 'cashier':
      list.add(QuickAction(key: 'payment.take', label: tr("To'lov qabul qilish"), hint: tr("O'quvchini toping va summani yozing"), icon: 'banknote', primary: true));
      list.add(QuickAction(key: 'crm.debtors', label: tr('Qarzdorlar'), hint: tr('Eslatma yuborish'), icon: 'warning'));
      if (can('p2p')) list.add(QuickAction(key: 'pay.p2p', label: tr("Kartaga o'tkazmalar"), hint: tr('Tasdiqlash va biriktirish'), icon: 'card'));
      list.add(QuickAction(key: 'crm.payments', label: tr('Kassa'), hint: tr("Bugungi to'lovlar"), icon: 'wallet'));
    case 'marketer':
      list.add(QuickAction(key: 'crm.leads', label: tr('Murojaatlarga javob berish'), hint: tr("Yangi lidlar ro'yxati"), icon: 'columns', primary: true));
      if (can('callcenter')) list.add(QuickAction(key: 'crm.callcenter', label: tr('Call markazi'), icon: 'headphones'));
      if (can('tasks')) list.add(QuickAction(key: 'crm.tasks', label: tr('Topshiriqlar'), icon: 'list-checks'));
    case 'student':
      if (can('testing')) list.add(QuickAction(key: 'my', label: pendingTests > 0 ? tr('Testni boshlash') : tr('Testlarim'), icon: 'clipboard-list', primary: pendingTests > 0));
      if (can('lms')) list.add(QuickAction(key: 'lms.my.courses', label: tr('Kurslarim'), hint: tr('Darslarni davom ettirish'), icon: 'book'));
      if (can('lms')) list.add(QuickAction(key: 'lms.my.assignments', label: tr('Uy vazifalari'), icon: 'pencil'));
      if (can('school')) list.add(QuickAction(key: 'school.diary', label: tr('Kundalik'), hint: tr('Baholar va dars jadvali'), icon: 'pen-line'));
      if (can('crm')) list.add(QuickAction(key: 'pay', label: debt ? tr("To'lash") : tr("Onlayn to'lov"), icon: 'wallet', primary: debt && !list.any((item) => item.primary)));
      if (can('fun')) list.add(QuickAction(key: 'fun.labs', label: tr('Laboratoriya'), hint: tr('Virtual tajribalar'), icon: 'science'));
    case 'guardian':
      if (can('crm')) list.add(QuickAction(key: 'pay', label: debt ? tr("To'lov qilish") : tr("To'lov va davomat"), hint: debt ? tr("Onlayn to'lov") : '', icon: 'wallet', primary: debt));
      if (can('school')) list.add(QuickAction(key: 'child.diary', label: tr('Kundalik'), hint: tr('Baholar va uy vazifasi'), icon: 'pen-line'));
      if (can('testing')) list.add(QuickAction(key: 'child.tests', label: tr('Test natijalari'), icon: 'clipboard-list'));
      if (can('lms')) list.add(QuickAction(key: 'child.courses', label: tr('Kurslar'), hint: tr("O'zlashtirish"), icon: 'book'));
  }
  return list.take(6).toList();
}
