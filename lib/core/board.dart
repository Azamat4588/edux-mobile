// Virtual doska (backend 1.35 BoardPages, veb Components/Lms/Board/draw.js): sahifa 1600×1000 birlik, shakllar —
// pen (p: [x, y, x, y ...]), line, arrow, rect, ellipse (x, y, x2, y2), text (s, f), image (src: data:image/...),
// umumiy c (#rrggbb) va w (qalinlik). Bu fayl JSON → chizish primitivlari (toza mantiq, test/board_test.dart).
import 'dart:math' as math;

const double boardWidth = 1600;
const double boardHeight = 1000;

class BoardPoint {
  const BoardPoint(this.x, this.y);

  final double x;
  final double y;

  @override
  bool operator ==(Object other) => other is BoardPoint && (other.x - x).abs() < 1e-6 && (other.y - y).abs() < 1e-6;

  @override
  int get hashCode => Object.hash(x.toStringAsFixed(3), y.toStringAsFixed(3));

  @override
  String toString() => '($x, $y)';
}

/// Chizish primitivi.
class BoardShape {
  const BoardShape({
    required this.type,
    required this.color,
    required this.width,
    this.points = const <BoardPoint>[],
    this.text = '',
    this.fontSize = 28,
    this.src = '',
  });

  /// pen | line | arrow | rect | ellipse | text | image
  final String type;

  /// ARGB rang.
  final int color;
  final double width;

  /// pen — barcha nuqtalar; line/arrow — [boshi, oxiri]; rect/ellipse/image — [chap-yuqori, o'ng-past] (normallashtirilgan);
  /// text — [chap-yuqori].
  final List<BoardPoint> points;
  final String text;
  final double fontSize;
  final String src;

  /// Strelka uchi: [uch, chap qanot, o'ng qanot] (veb: size = 12 + w × 2.5, burchak π/7).
  List<BoardPoint> get arrowHead {
    if (type != 'arrow' || points.length < 2) return const <BoardPoint>[];
    final a = points[0];
    final b = points[1];
    final angle = math.atan2(b.y - a.y, b.x - a.x);
    final size = 12 + width * 2.5;
    return <BoardPoint>[
      b,
      BoardPoint(b.x - size * math.cos(angle - math.pi / 7), b.y - size * math.sin(angle - math.pi / 7)),
      BoardPoint(b.x - size * math.cos(angle + math.pi / 7), b.y - size * math.sin(angle + math.pi / 7)),
    ];
  }

  /// Matn qatorlari va har birining y koordinatasi (qator balandligi — f × 1.25).
  List<MapEntry<String, double>> get textLines {
    if (type != 'text' || points.isEmpty) return const <MapEntry<String, double>>[];
    final lines = text.split('\n');
    return <MapEntry<String, double>>[
      for (var i = 0; i < lines.length; i++) MapEntry<String, double>(lines[i], points[0].y + i * fontSize * 1.25),
    ];
  }
}

/// "#2563eb" → 0xFF2563EB; noto'g'ri qiymat — #111827.
int parseBoardColor(Object? value) {
  final text = '${value ?? ''}'.trim();
  final match = RegExp(r'^#([0-9a-fA-F]{6})$').firstMatch(text);
  return 0xFF000000 | int.parse(match?.group(1) ?? '111827', radix: 16);
}

double _num(Object? value, [double fallback = 0]) {
  if (value is num) return value.toDouble();
  return double.tryParse('${value ?? ''}') ?? fallback;
}

/// Bitta shakl (noma'lum yoki buzilgan bo'lsa — null).
BoardShape? parseBoardItem(Object? raw) {
  if (raw is! Map) return null;
  final type = '${raw['t'] ?? ''}';
  final color = parseBoardColor(raw['c']);
  final width = _num(raw['w'], 3).clamp(1, 60).toDouble();
  switch (type) {
    case 'pen':
      final values = (raw['p'] is List ? raw['p'] as List : const <dynamic>[]).whereType<num>().map((item) => item.toDouble()).toList();
      if (values.length < 2) return null;
      final points = <BoardPoint>[for (var i = 0; i + 1 < values.length; i += 2) BoardPoint(values[i], values[i + 1])];
      return BoardShape(type: type, color: color, width: width, points: points);
    case 'line':
    case 'arrow':
      return BoardShape(type: type, color: color, width: width, points: <BoardPoint>[
        BoardPoint(_num(raw['x']), _num(raw['y'])),
        BoardPoint(_num(raw['x2']), _num(raw['y2'])),
      ]);
    case 'rect':
    case 'ellipse':
    case 'image':
      final x = _num(raw['x']);
      final y = _num(raw['y']);
      final x2 = _num(raw['x2']);
      final y2 = _num(raw['y2']);
      final src = '${raw['src'] ?? ''}';
      if (type == 'image' && !RegExp(r'^data:image/(png|jpeg|webp);base64,').hasMatch(src)) return null;
      return BoardShape(
        type: type,
        color: color,
        width: width,
        points: <BoardPoint>[BoardPoint(math.min(x, x2), math.min(y, y2)), BoardPoint(math.max(x, x2), math.max(y, y2))],
        src: type == 'image' ? src : '',
      );
    case 'text':
      final text = '${raw['s'] ?? ''}';
      if (text.trim().isEmpty) return null;
      return BoardShape(
        type: type,
        color: color,
        width: width,
        points: <BoardPoint>[BoardPoint(_num(raw['x']), _num(raw['y']))],
        text: text,
        fontSize: _num(raw['f'], 28).clamp(10, 160).toDouble(),
      );
  }
  return null;
}

/// Doska sahifalari: `[{items: [...]}, ...]` → har sahifa shakllari.
List<List<BoardShape>> parseBoardPages(Object? pages) {
  final list = pages is List ? pages : const <dynamic>[];
  final result = <List<BoardShape>>[
    for (final page in list)
      (page is Map && page['items'] is List ? page['items'] as List : const <dynamic>[]).map(parseBoardItem).whereType<BoardShape>().toList(),
  ];
  return result.isEmpty ? <List<BoardShape>>[<BoardShape>[]] : result;
}

/// Jonli doska so'rovi oralig'i (backend: jonli — 2,5 s, aks holda 20 s).
Duration boardPollInterval(bool live) => live ? const Duration(milliseconds: 2500) : const Duration(seconds: 20);
