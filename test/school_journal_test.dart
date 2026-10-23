// 3.4.1: maktab jurnali — haqiqiy server javobi (test/fixtures/school_teacher_journal*.json) va saqlash mantiqi.
import 'dart:convert';
import 'dart:io';

import 'package:edux/core/api.dart';
import 'package:edux/core/home_today.dart';
import 'package:edux/core/nav.dart';
import 'package:edux/core/school_journal.dart';
import 'package:edux/core/session.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> fixture(String name) => asMap(jsonDecode(File('test/fixtures/$name.json').readAsStringSync()));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('journal/options: sinf bo\'yicha jurnallar, chorak', () {
    final options = fixture('school_teacher_journal_options');
    final byClass = journalsByClass(options);
    expect(byClass, isNotEmpty);
    final first = byClass.values.first.first;
    expect(asInt(first['group_id']), greaterThan(0));
    expect(asInt(first['subject_id']), greaterThan(0));
    expect(first['can_write'], isA<bool>());
    expect(asInt(options['current_term_id']), greaterThan(0));
    expect(asList(options['terms']), isNotEmpty);
  });

  test('journal: o\'quvchilar, darslar (yangisi yuqorida), kataklar', () {
    final grid = JournalGrid.fromJson(fixture('school_teacher_journal'));
    expect(grid.students, isNotEmpty);
    expect(grid.lessons, isNotEmpty);
    expect(asText(grid.lessons.first['date']).compareTo(asText(grid.lessons.last['date'])), greaterThanOrEqualTo(0));
    expect(grid.entries, isNotEmpty);
    // Har katak — tanish baho va davomat qiymatlari.
    for (final cells in grid.entries.values) {
      for (final cell in cells.values) {
        if (cell.mark != null) expect(journalMarks, contains(cell.mark));
        if (cell.attendance != null) expect(journalAttendance, contains(cell.attendance));
      }
    }
    final lessonId = grid.entries.keys.first;
    final summary = grid.lessonSummary(lessonId);
    expect(summary.marks, greaterThanOrEqualTo(0));
    final withMarks = grid.students.map((s) => asInt(s['id'])).firstWhere((id) => grid.average(id) != null);
    expect(grid.average(withMarks), inInclusiveRange(2, 5));
  });

  test('bo\'sh jurnal: entries `[]` yoki yo\'q', () {
    final grid = JournalGrid.fromJson(<String, dynamic>{'students': <dynamic>[], 'lessons': <dynamic>[], 'entries': <dynamic>[]});
    expect(grid.entries, isEmpty);
    expect(grid.entry(1, 1).isEmpty, isTrue);
    expect(grid.canWrite, isFalse);
  });

  test('changedEntries: faqat o\'zgarganlar yuboriladi', () {
    final before = <int, JournalEntry>{1: const JournalEntry(mark: 4, attendance: 'present'), 2: const JournalEntry()};
    final after = Map<int, JournalEntry>.from(before)
      ..[2] = const JournalEntry(attendance: 'absent')
      ..[1] = before[1]!.copyWith(mark: 4);
    final changes = changedEntries(before, after);
    expect(changes, hasLength(1));
    expect(changes.single, <String, Object?>{'student_id': 2, 'mark': null, 'attendance': 'absent', 'note': null});
    expect(before[1]!.copyWith(clearMark: true).mark, isNull);
    // Serverdan noma'lum qiymat kelsa — e'tiborsiz.
    expect(JournalEntry.fromJson(<String, dynamic>{'mark': 7, 'attendance': 'sick'}).isEmpty, isTrue);
  });

  test('menyu: maktab o\'qituvchisida «Jurnal», o\'quvchida «To\'lovlarim» (CRM bo\'lsa)', () {
    final teacher = Session()..context = fixture('school_teacher_context');
    final tabs = buildNav(NavContext(role: teacher.role, can: teacher.can, groupsLabel: 'Sinflar')).expand((s) => s.tabs).map((t) => t.key);
    expect(tabs, contains('school.journal'));
    expect(quickActions('teacher', teacher.can).map((a) => a.key), contains('school.journal'));

    final student = Session()..context = fixture('center_student_context');
    final studentTabs = buildNav(NavContext(role: student.role, can: student.can)).expand((s) => s.tabs).map((t) => t.key);
    expect(studentTabs, contains('my.payments'));

    final schoolStudent = Session()..context = fixture('school_student_context');
    final schoolTabs = buildNav(NavContext(role: schoolStudent.role, can: schoolStudent.can)).expand((s) => s.tabs).map((t) => t.key);
    expect(schoolTabs, isNot(contains('my.payments')));

    final cashier = Session()..context = fixture('school_cashier_context');
    final actions = quickActions('cashier', cashier.can).map((a) => a.key);
    expect(actions, isNot(contains('payment.take')), reason: 'CRMsiz kassirga to\'lov qabul qilish yo\'q');
    expect(actions, contains('pay.p2p'));
  });
}
