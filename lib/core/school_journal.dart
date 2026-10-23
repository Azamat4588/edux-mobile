// Maktab jurnali (server: routes/school.php → JournalController, docs/school.md): sinf + fan + chorak jadvali.
// Javob: students [{id, full_name}], lessons [{id, date, period_number, topic, homework}],
// entries {lesson_id: {student_id: {mark, attendance, note}}} (bo'sh bo'lsa — `{}` yoki `[]`).
// Toza mantiq — test/school_journal_test.dart.
import 'api.dart';

/// Davomat holatlari (server App\Enums\School\Attendance) — tartib: telefonda tugmalar shu tartibda.
const List<String> journalAttendance = <String>['present', 'late', 'absent', 'excused'];

const Map<String, String> journalAttendanceLabels = <String, String>{
  'present': 'Qatnashdi',
  'late': 'Kechikdi',
  'absent': 'Kelmadi',
  'excused': 'Sababli kelmadi',
};

/// Baholar (server: between:2,5).
const List<int> journalMarks = <int>[5, 4, 3, 2];

class JournalEntry {
  const JournalEntry({this.mark, this.attendance, this.note});

  factory JournalEntry.fromJson(Map<String, dynamic> json) {
    final mark = json['mark'] == null ? null : asInt(json['mark']);
    final attendance = json['attendance']?.toString();
    return JournalEntry(
      mark: mark != null && mark >= 2 && mark <= 5 ? mark : null,
      attendance: journalAttendance.contains(attendance) ? attendance : null,
      note: json['note']?.toString(),
    );
  }

  final int? mark;
  final String? attendance;
  final String? note;

  bool get isEmpty => mark == null && attendance == null && (note == null || note!.isEmpty);

  JournalEntry copyWith({int? mark, bool clearMark = false, String? attendance, bool clearAttendance = false}) => JournalEntry(
        mark: clearMark ? null : (mark ?? this.mark),
        attendance: clearAttendance ? null : (attendance ?? this.attendance),
        note: note,
      );

  Map<String, Object?> toJson(int studentId) => <String, Object?>{'student_id': studentId, 'mark': mark, 'attendance': attendance, 'note': note};

  @override
  bool operator ==(Object other) => other is JournalEntry && other.mark == mark && other.attendance == attendance && other.note == note;

  @override
  int get hashCode => Object.hash(mark, attendance, note);
}

class JournalGrid {
  const JournalGrid({
    required this.className,
    required this.subject,
    required this.canWrite,
    required this.students,
    required this.lessons,
    required this.entries,
  });

  factory JournalGrid.fromJson(Map<String, dynamic> json) {
    final entries = <int, Map<int, JournalEntry>>{};
    final raw = json['entries'];
    if (raw is Map) {
      raw.forEach((lesson, row) {
        final cells = <int, JournalEntry>{};
        if (row is Map) {
          row.forEach((student, cell) {
            if (cell is Map) cells[asInt(student)] = JournalEntry.fromJson(Map<String, dynamic>.from(cell));
          });
        }
        entries[asInt(lesson)] = cells;
      });
    }
    // Yangi darslar yuqorida (telefonda odatda bugungi dars kerak).
    final lessons = asList(json['lessons'], 'lessons')
      ..sort((a, b) {
        final byDate = asText(b['date']).compareTo(asText(a['date']));
        return byDate != 0 ? byDate : asInt(b['period_number']).compareTo(asInt(a['period_number']));
      });
    return JournalGrid(
      className: asText(json['class_name']),
      subject: asText(json['subject']),
      canWrite: json['can_write'] == true,
      students: asList(json['students'], 'students'),
      lessons: lessons,
      entries: entries,
    );
  }

  final String className;
  final String subject;
  final bool canWrite;
  final List<Map<String, dynamic>> students;
  final List<Map<String, dynamic>> lessons;
  final Map<int, Map<int, JournalEntry>> entries;

  JournalEntry entry(int lessonId, int studentId) => entries[lessonId]?[studentId] ?? const JournalEntry();

  /// Dars ustunidagi baholar soni va kelmaganlar (ro'yxatda qisqa ko'rsatish uchun).
  ({int marks, int absent}) lessonSummary(int lessonId) {
    final cells = entries[lessonId]?.values ?? const <JournalEntry>[];
    return (
      marks: cells.where((cell) => cell.mark != null).length,
      absent: cells.where((cell) => cell.attendance == 'absent' || cell.attendance == 'excused').length,
    );
  }

  /// O'quvchining chorakdagi o'rtacha bahosi (baho bo'lmasa — null).
  double? average(int studentId) {
    final marks = <int>[
      for (final cells in entries.values)
        if (cells[studentId]?.mark != null) cells[studentId]!.mark!,
    ];
    if (marks.isEmpty) return null;
    return marks.reduce((a, b) => a + b) / marks.length;
  }
}

/// Saqlash uchun faqat o'zgargan kataklar (server: PUT journal/lessons/{id}/entries, 1–200 ta).
List<Map<String, Object?>> changedEntries(Map<int, JournalEntry> before, Map<int, JournalEntry> after) {
  final result = <Map<String, Object?>>[];
  after.forEach((studentId, entry) {
    final old = before[studentId] ?? const JournalEntry();
    if (old != entry) result.add(entry.toJson(studentId));
  });
  return result;
}

/// Jurnallar ro'yxati (journal/options → journals) sinf bo'yicha guruhlangan, tartib serverdagidek.
Map<String, List<Map<String, dynamic>>> journalsByClass(Map<String, dynamic> options) {
  final result = <String, List<Map<String, dynamic>>>{};
  for (final journal in asList(options['journals'], 'journals')) {
    result.putIfAbsent(asText(journal['class_name'], '—'), () => <Map<String, dynamic>>[]).add(journal);
  }
  return result;
}
