// Bo'sh holat illyustratsiyalari (veb 1.41 bilan bir xil: resources/css/app.css --art-*): o'zimizniki, chiziqli,
// asosiy rangda, orqasida girih yulduzi. SVG manbalari shu yerda — kichik yo'l (path) tahlilchisi bilan chiziladi (qo'shimcha paketsiz).
// notebook (standart), people, calendar, wallet, checklist, search.
import 'package:flutter/material.dart';

import 'koshin.dart';
import 'theme.dart';

enum EmptyArt { notebook, people, calendar, wallet, checklist, search }

/// SVG elementlari (veb 1.41 --art-*): viewBox 0 0 96 72, chiziq 2.6, uchlari yumaloq. `fill ` bilan boshlangani — to'liq.
const Map<EmptyArt, List<String>> emptyArtSvg = <EmptyArt, List<String>>{
  EmptyArt.notebook: <String>[
    'M20 22c9-4 18-4 27 1v36c-9-5-18-5-27-1z',
    'M76 22c-9-4-18-4-27 1v36c9-5 18-5 27-1z',
    'M26 31c5-1.5 10-1.5 15 .5M26 39c5-1.5 10-1.5 15 .5M55 31c5-2 10-2 15-.5',
    'M62 52l14-14 4 4-14 14-6 2z',
    'fill circle 30 48 2.4',
  ],
  EmptyArt.people: <String>[
    'circle 48 27 8',
    'M33 58c0-9 6.5-15 15-15s15 6 15 15',
    'circle 26 33 5.5',
    'M15 56c0-6.5 4.5-11 11-11 2 0 4 .5 5.5 1.3',
    'circle 70 33 5.5',
    'M81 56c0-6.5-4.5-11-11-11-2 0-4 .5-5.5 1.3',
  ],
  EmptyArt.calendar: <String>[
    'rect 19 17 58 45 7',
    'M19 29h58M33 11v11M63 11v11',
    'M29 40h5M45 40h5M61 40h5M29 51h5M45 51h5',
    'fill rect 58 46 11 10 3',
  ],
  EmptyArt.wallet: <String>[
    'M18 27a7 7 0 0 1 7-7h38v8',
    'M18 27v28a7 7 0 0 0 7 7h44a7 7 0 0 0 7-7V35a7 7 0 0 0-7-7H25a7 7 0 0 1-7-7',
    'M76 39H65a5 5 0 0 0 0 10h11z',
    'circle 70 14 7',
    'M70 11v6',
  ],
  EmptyArt.checklist: <String>[
    'rect 23 14 50 52 7',
    'rect 38 9 20 10 4',
    'M32 33l3.5 3.5L42 30M49 33h15M32 48l3.5 3.5L42 45M49 48h15',
    'fill circle 36.5 60 2.2',
    'M49 60h9',
  ],
  EmptyArt.search: <String>[
    'rect 16 12 44 52 6',
    'M25 25h26M25 33h18M25 41h11',
    'circle 60 47 12',
    'M69 56l10 10',
    'fill circle 60 47 4.5',
  ],
};

final RegExp _token = RegExp(r'[MmLlHhVvCcSsAaZz]|-?(?:\d+\.?\d*|\.\d+)');

/// SVG `d` satridan Flutter yo'li (M, L, H, V, C, S, A, Z — katta va kichik harflar).
Path parseSvgPath(String data) {
  final tokens = _token.allMatches(data).map((match) => match.group(0)!).toList();
  final path = Path();
  var i = 0;
  var command = 'M';
  var current = Offset.zero;
  var start = Offset.zero;
  Offset? lastControl;
  bool isCommand(String token) => RegExp(r'^[A-Za-z]$').hasMatch(token);
  double next() => double.parse(tokens[i++]);
  while (i < tokens.length) {
    if (isCommand(tokens[i])) command = tokens[i++];
    final relative = command == command.toLowerCase();
    final base = relative ? current : Offset.zero;
    switch (command.toUpperCase()) {
      case 'M':
        current = base + Offset(next(), next());
        start = current;
        path.moveTo(current.dx, current.dy);
        // Keyingi juftliklar — chiziq (SVG qoidasi).
        command = relative ? 'l' : 'L';
        lastControl = null;
      case 'L':
        current = base + Offset(next(), next());
        path.lineTo(current.dx, current.dy);
        lastControl = null;
      case 'H':
        current = Offset((relative ? current.dx : 0) + next(), current.dy);
        path.lineTo(current.dx, current.dy);
        lastControl = null;
      case 'V':
        current = Offset(current.dx, (relative ? current.dy : 0) + next());
        path.lineTo(current.dx, current.dy);
        lastControl = null;
      case 'C':
        final c1 = base + Offset(next(), next());
        final c2 = base + Offset(next(), next());
        final end = base + Offset(next(), next());
        path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, end.dx, end.dy);
        lastControl = c2;
        current = end;
      case 'S':
        final c1 = lastControl == null ? current : current * 2 - lastControl;
        final c2 = base + Offset(next(), next());
        final end = base + Offset(next(), next());
        path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, end.dx, end.dy);
        lastControl = c2;
        current = end;
      case 'A':
        final rx = next();
        final ry = next();
        final rotation = next();
        final large = next() != 0;
        final sweep = next() != 0;
        final end = base + Offset(next(), next());
        path.arcToPoint(end, radius: Radius.elliptical(rx, ry), rotation: rotation, largeArc: large, clockwise: sweep);
        current = end;
        lastControl = null;
      case 'Z':
        path.close();
        current = start;
        lastControl = null;
      default:
        i++;
    }
  }
  return path;
}

/// Bitta element (rect / circle / path) → yo'l.
Path artElementPath(String element) {
  final parts = (element.startsWith('fill ') ? element.substring(5) : element).split(' ');
  if (parts.first == 'rect') {
    final v = parts.skip(1).map(double.parse).toList();
    return Path()..addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(v[0], v[1], v[2], v[3]), Radius.circular(v[4])));
  }
  if (parts.first == 'circle') {
    final v = parts.skip(1).map(double.parse).toList();
    return Path()..addOval(Rect.fromCircle(center: Offset(v[0], v[1]), radius: v[2]));
  }
  return parseSvgPath(element);
}

class EmptyArtPainter extends CustomPainter {
  EmptyArtPainter(this.art, this.color);

  final EmptyArt art;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 96;
    canvas.save();
    canvas.scale(scale, size.height / 72);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = color;
    for (final element in emptyArtSvg[art]!) {
      canvas.drawPath(artElementPath(element), element.startsWith('fill ') ? fill : paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(EmptyArtPainter oldDelegate) => oldDelegate.art != art || oldDelegate.color != color;
}

/// Illyustratsiya (veb 1.41 empty-state): orqada girih yulduzi plitkasi (asosiy rangning och tusi), ustida chiziqli rasm
/// (asosiy rangning to'q tusi). [width] — yulduz kengligi (rasm ≈ 0.91 × width).
class EmptyIllustration extends StatelessWidget {
  const EmptyIllustration(this.art, {super.key, this.width = 112, this.color, this.backdrop = true});

  final EmptyArt art;
  final double width;
  final Color? color;

  /// Girih yulduzi foni.
  final bool backdrop;

  @override
  Widget build(BuildContext context) {
    final k = width / 92;
    final ink = color ?? AppColors.accentStrong;
    final soft = color == null ? AppColors.accentSoft2 : Color.alphaBlend(ink.withAlpha(AppColors.dark ? 56 : 36), AppColors.card);
    return ExcludeSemantics(
      child: SizedBox(
        width: width,
        height: width,
        child: Stack(alignment: Alignment.topCenter, children: <Widget>[
          if (backdrop) CustomPaint(size: Size.square(width), painter: GirihStarPainter(color: soft)),
          Positioned(top: 14 * k, child: SizedBox(width: 84 * k, height: 64 * k, child: CustomPaint(painter: EmptyArtPainter(art, ink)))),
        ]),
      ),
    );
  }
}

/// Belgi → illyustratsiya (EmptyState art berilmaganda sahifa turiga qarab).
final Map<int, EmptyArt> _artByIcon = <int, EmptyArt>{
  for (final icon in <IconData>[Icons.groups_outlined, Icons.people_outline, Icons.person_search_outlined, Icons.person_outline, Icons.school_outlined, Icons.family_restroom])
    icon.codePoint: EmptyArt.people,
  for (final icon in <IconData>[Icons.event_outlined, Icons.event_note_outlined, Icons.event_busy_outlined, Icons.calendar_today_outlined, Icons.schedule])
    icon.codePoint: EmptyArt.calendar,
  for (final icon in <IconData>[
    Icons.payments_outlined,
    Icons.receipt_long_outlined,
    Icons.receipt_outlined,
    Icons.credit_card,
    Icons.credit_card_off_outlined,
    Icons.account_balance_wallet_outlined,
  ])
    icon.codePoint: EmptyArt.wallet,
  for (final icon in <IconData>[Icons.task_alt, Icons.quiz_outlined, Icons.assignment_outlined, Icons.fact_check_outlined, Icons.checklist, Icons.document_scanner_outlined])
    icon.codePoint: EmptyArt.checklist,
  for (final icon in <IconData>[Icons.search_off_rounded, Icons.search, Icons.manage_search]) icon.codePoint: EmptyArt.search,
};

EmptyArt artForIcon(IconData icon) => _artByIcon[icon.codePoint] ?? EmptyArt.notebook;
