// 3.19: maktab davomati (veb 2.40 «Sinf davomati»): sinf va kun tanlanadi, darslar (jurnaldagi va jadvaldagi) ro'yxati,
// har o'quvchiga keldi / kechikdi / kelmadi / sababli. Kirish nazorati (2.40) bo'lsa — maktabga kelgan vaqt ko'rinadi va
// «Kirish ma'lumotidan to'ldirish» (qo'ng'iroqdan 5 daqiqadan keyin kelgan — kechikdi). Toza mantiq: test/school_attendance_test.dart.
// API: GET school/journal/options (sinflar), GET school/attendance?group_id&date, PUT school/attendance.
import 'api.dart';

const List<String> schoolAttendanceStatuses = <String>['present', 'late', 'absent', 'excused'];

/// Serverdagi SchoolGate::GRACE_MINUTES bilan bir xil.
const int gateGraceMinutes = 5;

/// Jurnallar ro'yxatidan sinflar (takrorsiz, server tartibida).
List<({int id, String name})> classesFromOptions(Map<String, dynamic> options) {
  final seen = <int>{};
  final result = <({int id, String name})>[];
  for (final journal in asList(options['journals'], 'journals')) {
    final id = asInt(journal['group_id']);
    if (id > 0 && seen.add(id)) result.add((id: id, name: asText(journal['class_name'], '—')));
  }
  return result;
}

class SchoolLesson {
  SchoolLesson(this.raw);

  final Map<String, dynamic> raw;

  int? get lessonId => raw['lesson_id'] == null ? null : asInt(raw['lesson_id']);
  int get subjectId => asInt(raw['subject_id']);
  String get subject => asText(raw['subject'], '—');
  int? get period => raw['period_number'] == null ? null : asInt(raw['period_number']);
  String? get startsAt => raw['starts_at'] == null ? null : asText(raw['starts_at']);
  bool get canWrite => raw['can_write'] == true;

  /// Dars kaliti (tanlash uchun): jurnaldagi dars — ID, jadvaldagisi — fan va soat.
  String get key => lessonId != null ? 'l$lessonId' : 's$subjectId-${period ?? 0}';

  String get title => period != null ? '$period · $subject' : subject;

  /// Saqlangan belgilar: o'quvchi ID → holat.
  Map<int, String> get saved {
    final entries = raw['entries'];
    if (entries is! Map) return <int, String>{};
    return <int, String>{
      for (final entry in entries.entries) int.tryParse('${entry.key}') ?? 0: asText(asMap(entry.value)['attendance'], 'present'),
    }..remove(0);
  }
}

class SchoolAttendanceDay {
  SchoolAttendanceDay(this.raw);

  factory SchoolAttendanceDay.fromJson(Map<String, dynamic> json) => SchoolAttendanceDay(json);

  final Map<String, dynamic> raw;

  String get className => asText(raw['class_name']);
  bool get gate => raw['gate'] == true;
  bool get canDecide => raw['can_decide'] == true;
  List<Map<String, dynamic>> get students => asList(raw['students'], 'students');
  List<SchoolLesson> get lessons => asList(raw['lessons'], 'lessons').map(SchoolLesson.new).toList();

  /// Ochilganda tanlanadigan dars: yozish mumkin bo'lgan, hali belgilanmagan birinchisi; bo'lmasa — yozish mumkin bo'lgan birinchisi.
  SchoolLesson? get defaultLesson {
    final writable = lessons.where((lesson) => lesson.canWrite).toList();
    if (writable.isEmpty) return lessons.isEmpty ? null : lessons.first;
    return writable.firstWhere((lesson) => lesson.saved.isEmpty, orElse: () => writable.first);
  }
}

/// Kirish vaqti va dars boshlanishi bo'yicha tavsiya (server SchoolGate::suggest bilan bir xil).
String gateSuggestion(String? arrivedAt, String? startsAt) {
  if (arrivedAt == null || arrivedAt.isEmpty) return 'absent';
  if (startsAt == null || startsAt.isEmpty) return 'present';
  return _minutes(arrivedAt) > _minutes(startsAt) + gateGraceMinutes ? 'late' : 'present';
}

int _minutes(String hhmm) {
  final parts = hhmm.split(':');
  return (int.tryParse(parts.first) ?? 0) * 60 + (parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0);
}

/// Varaqaning boshlang'ich holati: saqlangan belgilar, qolganlar — «keldi» (veb ham shunday ochadi).
Map<int, String> initialMarks(SchoolAttendanceDay day, SchoolLesson lesson) {
  final saved = lesson.saved;
  return <int, String>{for (final student in day.students) asInt(student['id']): saved[asInt(student['id'])] ?? 'present'};
}

/// «Kirish ma'lumotidan to'ldirish»: sababli belgilar o'zgarmaydi.
Map<int, String> fillFromGate(SchoolAttendanceDay day, SchoolLesson lesson, Map<int, String> current) {
  return <int, String>{
    for (final student in day.students)
      asInt(student['id']): current[asInt(student['id'])] == 'excused'
          ? 'excused'
          : gateSuggestion(student['arrived_at']?.toString(), lesson.startsAt),
  };
}

/// PUT school/attendance tanasi.
Map<String, Object?> attendancePayload({required int groupId, required String date, required SchoolLesson lesson, required Map<int, String> marks}) =>
    <String, Object?>{
      'group_id': groupId,
      'subject_id': lesson.subjectId,
      'date': date,
      'period_number': lesson.period,
      'lesson_id': lesson.lessonId,
      'marks': <Map<String, Object?>>[
        for (final entry in marks.entries) <String, Object?>{'student_id': entry.key, 'attendance': entry.value},
      ],
    };
