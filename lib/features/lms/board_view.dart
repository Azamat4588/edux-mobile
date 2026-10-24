// Virtual doskani ko'rish (o'quvchi, 1.35): backend JSON sahifalari CustomPainter bilan chiziladi; jonli rejimda
// GET lms/my/boards/{id}?version=N har 2,5 soniyada (o'zgarmagan bo'lsa — qisqa javob), aks holda 20 soniyada.
// Kattalashtirish — ikki barmoq (InteractiveViewer). Chizish — vebda (mobilda faqat ko'rish).
import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/board.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

/// data:image rasmlar keshi (src → ui.Image).
class _BoardImages {
  _BoardImages._();

  static final Map<String, ui.Image> _ready = <String, ui.Image>{};
  static final Set<String> _loading = <String>{};

  static ui.Image? get(String src, VoidCallback onLoad) {
    final image = _ready[src];
    if (image != null) return image;
    if (_loading.add(src)) {
      try {
        final bytes = base64Decode(src.substring(src.indexOf(',') + 1));
        ui.decodeImageFromList(bytes, (image) {
          _ready[src] = image;
          _loading.remove(src);
          onLoad();
        });
      } catch (_) {
        // buzilgan rasm — chizilmaydi
      }
    }
    return null;
  }
}

class BoardPainter extends CustomPainter {
  BoardPainter(this.shapes, {required this.onImage}) : super(repaint: null);

  final List<BoardShape> shapes;
  final VoidCallback onImage;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / boardWidth;
    canvas.save();
    canvas.scale(scale);
    canvas.drawRect(const Rect.fromLTWH(0, 0, boardWidth, boardHeight), Paint()..color = Colors.white);
    canvas.clipRect(const Rect.fromLTWH(0, 0, boardWidth, boardHeight));
    for (final shape in shapes) {
      final color = Color(shape.color);
      final stroke = Paint()
        ..color = color
        ..strokeWidth = shape.width
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final p = shape.points;
      switch (shape.type) {
        case 'pen':
          final path = Path()..moveTo(p.first.x, p.first.y);
          if (p.length <= 2) {
            path.lineTo(p.last.x, p.last.y);
          } else {
            // Silliq chiziq: o'rta nuqtalar orqali kvadratik egri (veb bilan bir xil).
            for (var i = 1; i < p.length - 1; i++) {
              path.quadraticBezierTo(p[i].x, p[i].y, (p[i].x + p[i + 1].x) / 2, (p[i].y + p[i + 1].y) / 2);
            }
            path.lineTo(p.last.x, p.last.y);
          }
          canvas.drawPath(path, stroke);
        case 'line':
        case 'arrow':
          canvas.drawLine(Offset(p[0].x, p[0].y), Offset(p[1].x, p[1].y), stroke);
          final head = shape.arrowHead;
          if (head.length == 3) {
            final path = Path()
              ..moveTo(head[0].x, head[0].y)
              ..lineTo(head[1].x, head[1].y)
              ..lineTo(head[2].x, head[2].y)
              ..close();
            canvas.drawPath(path, Paint()..color = color);
          }
        case 'rect':
          canvas.drawRect(Rect.fromLTRB(p[0].x, p[0].y, p[1].x, p[1].y), stroke);
        case 'ellipse':
          canvas.drawOval(Rect.fromLTRB(p[0].x, p[0].y, p[1].x, p[1].y), stroke);
        case 'text':
          for (final line in shape.textLines) {
            final painter = TextPainter(
              text: TextSpan(text: line.key, style: TextStyle(color: color, fontSize: shape.fontSize, height: 1.0)),
              textDirection: TextDirection.ltr,
            )..layout();
            painter.paint(canvas, Offset(p[0].x, line.value));
          }
        case 'image':
          final image = _BoardImages.get(shape.src, onImage);
          if (image != null) {
            canvas.drawImageRect(
              image,
              Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
              Rect.fromLTRB(p[0].x, p[0].y, p[1].x, p[1].y),
              Paint()..filterQuality = FilterQuality.medium,
            );
          }
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(BoardPainter oldDelegate) => !identical(oldDelegate.shapes, shapes);
}

/// Bitta sahifa (1600×1000 nisbatida).
class BoardCanvas extends StatefulWidget {
  const BoardCanvas({super.key, required this.shapes});

  final List<BoardShape> shapes;

  @override
  State<BoardCanvas> createState() => _BoardCanvasState();
}

class _BoardCanvasState extends State<BoardCanvas> {
  int _images = 0;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: boardWidth / boardHeight,
      child: CustomPaint(
        key: ValueKey<int>(_images),
        painter: BoardPainter(widget.shapes, onImage: () {
          if (mounted) setState(() => _images++);
        }),
      ),
    );
  }
}

/// Dars ichidagi doska kartasi: birinchi sahifa ko'rinishi, «Jonli» belgisi, bosilsa — to'liq ekran.
class BoardPreview extends StatelessWidget {
  const BoardPreview({super.key, required this.board});

  final Map<String, dynamic> board;

  @override
  Widget build(BuildContext context) {
    final pages = parseBoardPages(board['pages']);
    final live = board['is_live'] == true;
    return Material(
      color: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card), side: BorderSide(color: AppColors.cardBorder)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => BoardPage(board: board))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          IgnorePointer(child: BoardCanvas(shapes: pages.first)),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(children: <Widget>[
              Icon(Icons.draw_outlined, color: AppColors.brand),
              const SizedBox(width: 8),
              Expanded(child: Text(asText(board['title'], tr('Doska')), style: const TextStyle(fontWeight: FontWeight.w600))),
              if (live) const _LiveBadge(),
              if (pages.length > 1) Text('  ${tr('{0} sahifa', <Object?>[pages.length])}', style: TextStyle(color: AppColors.muted, fontSize: 12)),
              const SizedBox(width: 4),
              Icon(Icons.open_in_full, size: 18, color: AppColors.muted),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: AppColors.dangerFill, borderRadius: BorderRadius.circular(99)),
      child: Text(tr('Jonli'), style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700)),
    );
  }
}

/// To'liq ekran: sahifalar, kattalashtirish, jonli rejimda avtomatik yangilanish.
class BoardPage extends StatefulWidget {
  const BoardPage({super.key, required this.board});

  final Map<String, dynamic> board;

  @override
  State<BoardPage> createState() => _BoardPageState();
}

class _BoardPageState extends State<BoardPage> with WidgetsBindingObserver {
  late Map<String, dynamic> _board = widget.board;
  late List<List<BoardShape>> _pages = parseBoardPages(widget.board['pages']);
  int _page = 0;
  Timer? _timer;
  bool _busy = false;
  bool _foreground = true;
  final TransformationController _zoom = TransformationController();

  bool get _live => _board['is_live'] == true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _schedule();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _zoom.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(boardPollInterval(_live), () async {
      await _poll();
      if (mounted) _schedule();
    });
  }

  Future<void> _poll() async {
    if (_busy || !_foreground || !mounted) return;
    _busy = true;
    try {
      final id = asInt(_board['id']);
      final data = asMap(await AppScope.read(context).api.get('lms/my/boards/$id', query: <String, Object?>{'version': asInt(_board['version'])}));
      if (!mounted) return;
      if (data['changed'] == false) {
        if ((data['is_live'] == true) != _live) setState(() => _board = <String, dynamic>{..._board, 'is_live': data['is_live'] == true});
        return;
      }
      final pages = parseBoardPages(data['pages']);
      setState(() {
        _board = data;
        _pages = pages;
        // Jonli darsda o'qituvchi yangi sahifa ochsa — o'quvchi oxirgi sahifani ko'radi.
        if (_live && pages.length > _page + 1 && _page == 0) _page = pages.length - 1;
        _page = _page.clamp(0, pages.length - 1);
      });
    } catch (_) {
      // tarmoq xatosi — keyingi so'rovda
    } finally {
      _busy = false;
    }
  }

  void _go(int page) => setState(() {
        _page = page.clamp(0, _pages.length - 1);
        _zoom.value = Matrix4.identity();
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1F2937),
      appBar: pageBar(context,
        title: Text(asText(_board['title'], tr('Doska')), maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: <Widget>[
          if (_live) const Padding(padding: EdgeInsets.only(right: 8), child: Center(child: _LiveBadge())),
          IconButton(tooltip: tr("Asl o'lcham"), onPressed: () => _zoom.value = Matrix4.identity(), icon: const Icon(Icons.fit_screen_outlined)),
        ],
      ),
      body: Column(children: <Widget>[
        Expanded(
          child: InteractiveViewer(
            transformationController: _zoom,
            minScale: 1,
            maxScale: 6,
            child: Center(child: BoardCanvas(shapes: _pages[_page.clamp(0, _pages.length - 1)])),
          ),
        ),
        SafeArea(
          top: false,
          child: Container(
            color: AppColors.card,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(children: <Widget>[
              IconButton(tooltip: tr('Oldingi sahifa'), onPressed: _page > 0 ? () => _go(_page - 1) : null, icon: const Icon(Icons.chevron_left)),
              Expanded(child: Text('${_page + 1} / ${_pages.length}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600))),
              IconButton(tooltip: tr('Keyingi sahifa'), onPressed: _page < _pages.length - 1 ? () => _go(_page + 1) : null, icon: const Icon(Icons.chevron_right)),
            ]),
          ),
        ),
      ]),
    );
  }
}
