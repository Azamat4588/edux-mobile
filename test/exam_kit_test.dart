// Telefonda baholash (ExamKit.grade) server qoidasi bilan bir xil: belgilar to'plami kalit bilan aynan teng bo'lsa — to'g'ri.
import 'package:edux/features/scanner/exam_kit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final kit = ExamKit.fromJson(<String, dynamic>{
    'exam': <String, dynamic>{'id': 7, 'title': 'Matematika', 'questions': 4, 'options': 4},
    'variants': <dynamic>[
      <String, dynamic>{
        'number': 1,
        'key': <dynamic>[
          <int>[1],
          <int>[0, 2],
          <int>[3],
          <int>[2],
        ],
        'points_x100': <int>[100, 200, 100, 150],
      },
    ],
    'students': <dynamic>[
      <String, dynamic>{'id': 1, 'code': '429756', 'name': 'Aliyeva Dilnoza'},
    ],
  });

  test('to\'g\'ri, xato va javobsiz savollar', () {
    final grade = kit.grade(1, <List<int>>[
      <int>[1], // to'g'ri
      <int>[2, 0], // to'g'ri (tartib muhim emas)
      <int>[], // javobsiz
      <int>[1, 2], // ortiqcha belgi — xato
    ])!;
    expect(grade.correct, 2);
    expect(grade.total, 4);
    expect(grade.score, 3.0);
    expect(grade.maxScore, 5.5);
    expect(grade.perQuestion, <bool?>[true, true, null, false]);
  });

  test('noma\'lum variant — baholanmaydi', () {
    expect(kit.grade(9, <List<int>>[]), isNull);
    expect(kit.grade(null, <List<int>>[]), isNull);
  });

  test('o\'quvchi kodi bo\'yicha ism', () {
    expect(kit.studentName('429756'), 'Aliyeva Dilnoza');
    expect(kit.studentName('000000'), isNull);
    expect(kit.studentName(null), isNull);
  });
}
