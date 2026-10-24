// Mijozlar fikri (server 1.39, docs/feedback.md): ota-ona, o'quvchi yoki xodimning markaz rahbariyatiga shikoyati, taklifi,
// xatolik haqidagi xabari, minnatdorchiligi yoki savoli. Qo'llab-quvvatlash murojaatidan (EduX jamoasiga) alohida — fikr
// tashkilot ichida qoladi. Qaysi band ko'rinadi — `GET context` → `feedback {enabled, submit, manage, new}`.
// Toza mantiq (sahifalarsiz) — test/feedback_test.dart.
import 'api.dart';

/// Kontekstdagi `feedback` bloki. Eski server (1.38 gacha) blok bermaydi — hammasi o'chiq.
class FeedbackFlags {
  const FeedbackFlags({this.enabled = false, this.submit = false, this.manage = false, this.fresh = 0});

  factory FeedbackFlags.fromContext(Map<String, dynamic> context) {
    final raw = asMap(context['feedback']);
    if (raw.isEmpty) return const FeedbackFlags();
    final enabled = raw['enabled'] == true;
    return FeedbackFlags(
      enabled: enabled,
      submit: enabled && raw['submit'] == true,
      // Panel sozlama o'chiq bo'lsa ham ochiladi (eski fikrlar ko'rinsin) — server `manage` ni o'zi hal qiladi.
      manage: raw['manage'] == true,
      fresh: asInt(raw['new']),
    );
  }

  final bool enabled;

  /// «Fikr bildirish» ko'rsatilsin.
  final bool submit;

  /// «Fikrlar» paneli (rahbariyat).
  final bool manage;

  /// «Yangi» holatdagi fikrlar soni (menyu belgisi).
  final int fresh;
}

FeedbackFlags feedbackFlags(Map<String, dynamic> context) => FeedbackFlags.fromContext(context);

/// Menyu belgisi uchun: panel ochiq bo'lsa «Yangi» fikrlar soni.
int feedbackNewCount(Map<String, dynamic> context) {
  final flags = feedbackFlags(context);
  return flags.manage ? flags.fresh : 0;
}

/// Turlar (server `meta.kinds` bo'lmasa — standart ro'yxat). Qiymatlar — o'zbekcha tarjima kaliti.
const Map<String, String> feedbackKindLabels = <String, String>{
  'complaint': 'Shikoyat',
  'suggestion': 'Taklif',
  'bug': 'Xatolik',
  'thanks': 'Minnatdorchilik',
  'question': 'Savol',
};

const Map<String, String> feedbackStatusLabels = <String, String>{
  'new': 'Yangi',
  'in_progress': "Ko'rib chiqilmoqda",
  'resolved': 'Hal qilindi',
  'rejected': 'Rad etildi',
};

/// Panel filtri: holatlar + «Muddati o'tgan».
const Map<String, String> feedbackFilterLabels = <String, String>{
  'new': 'Yangi',
  'in_progress': "Ko'rib chiqilmoqda",
  'overdue': "Muddati o'tgan",
  'resolved': 'Hal qilindi',
  'rejected': 'Rad etildi',
};

/// Muallif roli (panel kartasida).
const Map<String, String> feedbackRoleLabels = <String, String>{
  'guardian': 'Ota-ona',
  'student': "O'quvchi",
  'director': 'Direktor',
  'admin': 'Administrator',
  'teacher': "O'qituvchi",
  'cashier': 'Kassir',
  'marketer': 'Marketolog',
  'guest': 'Mehmon',
};

/// Panel tarixi (events.type).
const Map<String, String> feedbackEventLabels = <String, String>{
  'assign': "Mas'ul tayinlandi",
  'note': 'Ichki izoh',
  'reply': 'Javob yuborildi',
  'status': "Holat o'zgardi",
};

/// Yo'nalishlar (server `meta.categories` bo'lmasa; serverdagi standart ro'yxat — tarjima kalitlari).
const List<String> feedbackCategoryLabels = <String>[
  "O'qituvchi",
  'Guruh',
  "To'lov",
  'Dars sifati',
  'Xizmat',
  'Bino',
  'Boshqa',
];

/// Forma xatolari (tarjima kalitlari).
const Map<String, String> feedbackErrorLabels = <String, String>{
  'short': 'Fikringizni batafsilroq yozing (kamida 5 belgi).',
  'long': 'Matn 3000 belgidan oshmasin.',
};

/// Server lug'ati (`kinds`/`statuses`) yoki standart yorliqlar: kalit → o'zbekcha matn (tarjima kaliti).
Map<String, String> feedbackLabels(Map<String, dynamic> source, String key, Map<String, String> fallback) {
  final raw = asMap(source[key]);
  if (raw.isEmpty) return fallback;
  return raw.map((code, label) => MapEntry(code, asText(label, fallback[code] ?? code)));
}

/// Holat rangi kaliti (sahifa AppColors bilan bog'laydi): new → warning, in_progress → brand, resolved → success, rejected → muted.
String feedbackStatusTone(String status) {
  switch (status) {
    case 'new':
      return 'warning';
    case 'in_progress':
      return 'brand';
    case 'resolved':
      return 'success';
    default:
      return 'muted';
  }
}

/// Fikr yopilganmi (javob yozish va holat almashtirish baribir mumkin; muallif uchun «yopiq» belgisi).
bool feedbackClosed(String status) => status == 'resolved' || status == 'rejected';

/// «Kimga tegishli» tanlovi (`meta.targets`): o'quvchilar, guruhlar (o'qituvchisi bilan), o'qituvchilar.
class FeedbackTargets {
  const FeedbackTargets({this.students = const <Map<String, dynamic>>[], this.groups = const <Map<String, dynamic>>[], this.teachers = const <Map<String, dynamic>>[]});

  factory FeedbackTargets.fromMeta(Map<String, dynamic> meta) {
    final raw = asMap(meta['targets']);
    return FeedbackTargets(
      students: asList(raw['students'], 'students'),
      groups: asList(raw['groups'], 'groups'),
      teachers: asList(raw['teachers'], 'teachers'),
    );
  }

  final List<Map<String, dynamic>> students;
  final List<Map<String, dynamic>> groups;
  final List<Map<String, dynamic>> teachers;

  bool get isEmpty => students.isEmpty && groups.isEmpty && teachers.isEmpty;

  /// Guruh o'qituvchisi (guruh tanlansa server o'qituvchini o'zi qo'yadi — ilovada ham ko'rsatiladi).
  int teacherOfGroup(int groupId) {
    for (final group in groups) {
      if (asInt(group['id']) == groupId) return asInt(group['teacher_id']);
    }
    return 0;
  }
}

/// Yangi fikr maydonlari (`POST feedback`): bo'sh/0 qiymatlar yuborilmaydi; `context` — ilova, versiya va ekran.
Map<String, Object?> feedbackPayload({
  required String kind,
  required String body,
  String? category,
  int rating = 0,
  bool anonymous = false,
  int studentId = 0,
  int groupId = 0,
  int teacherId = 0,
  Map<String, String> context = const <String, String>{},
}) {
  return <String, Object?>{
    'kind': kind,
    'body': body.trim(),
    if (category != null && category.isNotEmpty) 'category': category,
    if (rating >= 1 && rating <= 5) 'rating': rating,
    if (anonymous) 'anonymous': true,
    if (studentId > 0) 'student_id': studentId,
    if (groupId > 0) 'study_group_id': groupId,
    // Guruh tanlangan bo'lsa o'qituvchi serverda guruhdan olinadi.
    if (teacherId > 0 && groupId <= 0) 'teacher_id': teacherId,
    if (context.isNotEmpty) 'context': context,
  };
}

/// Multipart uchun `anonymous` — 1/0 (Laravel boolean), qolgani [supportFields] bilan tekislanadi.
Map<String, Object?> feedbackMultipartPayload(Map<String, Object?> payload) =>
    payload.map((key, value) => MapEntry(key, value is bool ? (value ? '1' : '0') : value));

/// Matn uzunligi (server: 5–3000).
String? feedbackBodyError(String body) {
  final text = body.trim();
  if (text.length < 5) return feedbackErrorLabels['short'];
  if (text.length > 3000) return feedbackErrorLabels['long'];
  return null;
}

/// Panel ro'yxati so'rovi (`GET feedback`): bo'sh filtrlar tushiriladi.
Map<String, Object?> feedbackListQuery({String status = '', String kind = '', bool mine = false, String search = '', int page = 1}) {
  return <String, Object?>{
    if (status.isNotEmpty) 'status': status,
    if (kind.isNotEmpty) 'kind': kind,
    if (mine) 'assigned': 'me',
    if (search.trim().isNotEmpty) 'q': search.trim(),
    if (page > 1) 'page': page,
  };
}

/// Muallif ko'rinishi: anonim yoki ism (rol bilan).
String feedbackAuthorLine(Map<String, dynamic> item, {required String anonymousLabel, Map<String, String> roles = feedbackRoleLabels, String Function(String)? translate}) {
  String t(String text) => translate == null ? text : translate(text);
  if (item['is_anonymous'] == true) return t(anonymousLabel);
  final author = asMap(item['author']);
  final name = asText(author['name']);
  final role = asText(author['role']);
  final roleLabel = roles[role] == null ? '' : t(roles[role]!);
  if (name.isEmpty) return roleLabel;
  return roleLabel.isEmpty ? name : '$name · $roleLabel';
}

/// Fikr kimga tegishli: guruh, o'qituvchi, farzand (bo'sh qismlar tushadi). Panelda — obyektlar, muallifda — matn.
String feedbackAboutLine(Map<String, dynamic> item) {
  String name(dynamic value) => value is Map ? asText(value['name']) : asText(value);
  return <String>[name(item['student']), name(item['group']), name(item['teacher'])].where((part) => part.isNotEmpty).join(', ');
}

/// Push yoki havoladan fikr raqami: data.feedback_id yoki /feedback/31, /my/feedback?id=31.
int feedbackIdFromLink(String link) {
  final uri = Uri.tryParse(link);
  if (uri == null) return 0;
  final query = int.tryParse(uri.queryParameters['id'] ?? '');
  if (query != null) return query;
  final segments = uri.pathSegments.where((item) => item.isNotEmpty).toList();
  if (segments.length >= 2 && segments[segments.length - 2] == 'feedback') return int.tryParse(segments.last) ?? 0;
  return 0;
}
