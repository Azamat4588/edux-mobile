import 'package:edux/core/lms.dart';
import 'package:edux/core/push.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bloklar konstruktor tartibida, mavjud bo\'lmagani tashlanadi', () {
    final blocks = lessonBlocks(<String, dynamic>{
      'content': 'Matn',
      'video_url': 'https://youtu.be/x',
      'materials': <dynamic>[<String, dynamic>{'id': 5}],
      'assignments': <dynamic>[<String, dynamic>{'id': 7}],
      'boards': <dynamic>[<String, dynamic>{'id': 9}],
      'exam': <String, dynamic>{'id': 1},
      'blocks': <dynamic>[
        <String, dynamic>{'type': 'board', 'ref': 9},
        <String, dynamic>{'type': 'text', 'text': 'Eslatma'},
        <String, dynamic>{'type': 'content'},
        <String, dynamic>{'type': 'file', 'ref': 99},
        <String, dynamic>{'type': 'file', 'ref': 5},
        <String, dynamic>{'type': 'video'},
        <String, dynamic>{'type': 'assignment', 'ref': 7},
        <String, dynamic>{'type': 'exam'},
        <String, dynamic>{'type': 'activity'},
      ],
    });
    expect(blocks.map((item) => '$item').toList(), <String>['board:9', 'text', 'content', 'file:5', 'video', 'assignment:7', 'exam']);
    expect(blocks[4].url, 'https://youtu.be/x');
  });

  test('eski server: bloklarsiz avvalgi tartib', () {
    final blocks = lessonBlocks(<String, dynamic>{'content': 'x', 'video_url': 'v', 'materials': <dynamic>[<String, dynamic>{'id': 1}]});
    expect(blocks.map((item) => '$item').toList(), <String>['video', 'content', 'file:1']);
  });

  test('jonli dars holati', () {
    final start = DateTime(2026, 10, 23, 15);
    final live = <String, dynamic>{'starts_at': start.toIso8601String(), 'ends_at': start.add(const Duration(minutes: 90)).toIso8601String(), 'state': 'soon'};
    expect(liveState(live, start.subtract(const Duration(minutes: 30))), 'soon');
    expect(liveState(live, start.subtract(const Duration(minutes: 10))), 'open');
    expect(liveState(live, start.add(const Duration(minutes: 91))), 'ended');
    expect(liveProviderLabel('meet'), 'Google Meet');
  });

  test('LMS push havolasidan id lar', () {
    expect(PushService.lmsIds('/learn/courses/5/lessons/9'), <String, dynamic>{'course_id': 5, 'lesson_id': 9});
    expect(PushService.lmsIds('https://x.uz/learn/courses/3'), <String, dynamic>{'course_id': 3});
    final data = PushService.normalize(<String, dynamic>{'type': 'lesson_answer', 'link': '/learn/courses/2/lessons/4'});
    expect(data['lesson_id'], 4);
  });
}
