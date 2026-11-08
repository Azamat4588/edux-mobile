// 3.19: maktab davomati — haqiqiy server javobi (test/fixtures/school_attendance.json, demo 11-A, 2026-11-04) va mantiq.
import 'dart:convert';
import 'dart:io';

import 'package:edux/core/api.dart';
import 'package:edux/core/school_attendance.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> fixture(String name) => asMap(jsonDecode(File('test/fixtures/$name.json').readAsStringSync()));

void main() {
  test('kirish vaqti bo\'yicha tavsiya (server SchoolGate::suggest)', () {
    expect(gateSuggestion(null, '08:00'), 'absent');
    expect(gateSuggestion('07:50', null), 'present');
    expect(gateSuggestion('08:05', '08:00'), 'present');
    expect(gateSuggestion('08:06', '08:00'), 'late');
    expect(gateSuggestion('10:00', '09:50'), 'late');
  });

  test('sinflar ro\'yxati jurnallardan takrorsiz', () {
    final classes = classesFromOptions(<String, dynamic>{
      'journals': <Map<String, dynamic>>[
        <String, dynamic>{'group_id': 3, 'class_name': '9-B', 'subject': 'Matematika'},
        <String, dynamic>{'group_id': 4, 'class_name': '10-A', 'subject': 'Fizika'},
        <String, dynamic>{'group_id': 4, 'class_name': '10-A', 'subject': 'Matematika'},
      ],
    });
    expect(classes.map((item) => item.name).toList(), <String>['9-B', '10-A']);
  });

  test('server javobi: darslar, saqlangan belgilar, standart dars va saqlash tanasi', () {
    final day = SchoolAttendanceDay.fromJson(fixture('school_attendance'));
    expect(day.className, '11-A');
    expect(day.gate, isTrue);
    expect(day.students, isNotEmpty);
    final lessons = day.lessons;
    expect(lessons.map((item) => item.subject), containsAll(<String>['Matematika', 'Ingliz tili']));
    final saved = lessons.firstWhere((item) => item.lessonId != null);
    expect(saved.saved.length, day.students.length);
    final first = day.defaultLesson!;
    expect(first.canWrite, isTrue);
    final marks = initialMarks(day, first);
    expect(marks.length, day.students.length);
    expect(marks.values.toSet(), <String>{'present'});
    final body = attendancePayload(groupId: 1, date: '2026-11-04', lesson: first, marks: marks);
    expect(body['subject_id'], first.subjectId);
    expect((body['marks']! as List).length, day.students.length);
  });

  test('kirish ma\'lumotidan to\'ldirish: sababli o\'zgarmaydi', () {
    final day = SchoolAttendanceDay.fromJson(<String, dynamic>{
      'gate': true,
      'students': <Map<String, dynamic>>[
        <String, dynamic>{'id': 1, 'full_name': 'A', 'arrived_at': '07:55'},
        <String, dynamic>{'id': 2, 'full_name': 'B', 'arrived_at': '08:20'},
        <String, dynamic>{'id': 3, 'full_name': 'C', 'arrived_at': null},
        <String, dynamic>{'id': 4, 'full_name': 'D', 'arrived_at': null},
      ],
      'lessons': <Map<String, dynamic>>[
        <String, dynamic>{'lesson_id': null, 'subject_id': 7, 'subject': 'Matematika', 'period_number': 1, 'starts_at': '08:00', 'can_write': true, 'entries': <String, dynamic>{}},
      ],
    });
    final lesson = day.lessons.single;
    final filled = fillFromGate(day, lesson, <int, String>{1: 'present', 2: 'present', 3: 'present', 4: 'excused'});
    expect(filled, <int, String>{1: 'present', 2: 'late', 3: 'absent', 4: 'excused'});
  });
}
