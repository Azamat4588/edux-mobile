import 'package:edux/core/board.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('doska JSON → primitivlar', () {
    final pages = parseBoardPages(<dynamic>[
      <String, dynamic>{
        'items': <dynamic>[
          <String, dynamic>{'t': 'pen', 'c': '#2563eb', 'w': 4, 'p': <dynamic>[10, 20, 30, 40, 50]},
          <String, dynamic>{'t': 'rect', 'c': '#dc2626', 'x': 300, 'y': 200, 'x2': 100, 'y2': 50},
          <String, dynamic>{'t': 'text', 's': 'a\nb', 'f': 20, 'x': 5, 'y': 10},
          <String, dynamic>{'t': 'image', 'src': 'https://evil.example/x.png', 'x': 0, 'y': 0, 'x2': 1, 'y2': 1},
          <String, dynamic>{'t': 'unknown'},
        ],
      },
      <String, dynamic>{'items': <dynamic>[]},
    ]);
    expect(pages, hasLength(2));
    final shapes = pages.first;
    expect(shapes.map((item) => item.type).toList(), <String>['pen', 'rect', 'text']);
    expect(shapes[0].color, 0xFF2563EB);
    expect(shapes[0].points, const <BoardPoint>[BoardPoint(10, 20), BoardPoint(30, 40)]);
    expect(shapes[1].points, const <BoardPoint>[BoardPoint(100, 50), BoardPoint(300, 200)]);
    expect(shapes[2].textLines.map((line) => line.value).toList(), <double>[10, 35]);
  });

  test('strelka uchi va rang', () {
    final arrow = parseBoardItem(<String, dynamic>{'t': 'arrow', 'c': 'red', 'w': 2, 'x': 0, 'y': 0, 'x2': 100, 'y2': 0})!;
    expect(arrow.color, 0xFF111827);
    final head = arrow.arrowHead;
    expect(head.first, const BoardPoint(100, 0));
    expect(head[1].x, lessThan(100));
    expect(head[1].y, closeTo(-head[2].y, 1e-9));
    expect(parseBoardPages(null), hasLength(1));
    expect(boardPollInterval(true), const Duration(milliseconds: 2500));
    expect(boardPollInterval(false), const Duration(seconds: 20));
  });
}
