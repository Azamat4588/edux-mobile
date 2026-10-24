// Bo'sh holat illyustratsiyalari (veb 1.40 bilan bir xil: resources/css/app.css --art-*): o'zimizniki, chiziqli,
// asosiy rangda. SVG manbalari shu yerda — kichik yo'l (path) tahlilchisi bilan chiziladi (qo'shimcha paketsiz).
// notebook (standart), people, calendar, wallet, checklist, search.
import 'package:flutter/material.dart';

import 'theme.dart';

enum EmptyArt { notebook, people, calendar, wallet, checklist, search }

/// SVG elementlari: viewBox 0 0 96 72, chiziq 2.4, uchlari yumaloq.
const Map<EmptyArt, List<String>> emptyArtSvg = <EmptyArt, List<String>>{
  EmptyArt.notebook: <String>[
    'rect 22 10 50 54 4',
    'M31 10v54M39 24h25M39 32h25M39 40h16',
    'M22 18h-4M22 28h-4M22 38h-4M22 48h-4M22 58h-4',
    'M66 60l14-14 5 5-14 14-7 2z',
  ],
  EmptyArt.people: <String>[
    'circle 38 26 9',
    'M21 60c0-11 7-18 17-18s17 7 17 18',
    'circle 63 30 7',
    'M58 44c1.5-.6 3.2-1 5-1 8 0 13 6 13 16',
  ],
  EmptyArt.calendar: <String>[
    'rect 16 15 62 49 5',
    'M16 27h62M31 9v12M63 9v12',
    'M27 39h6M43 39h6M59 39h6M27 51h6M43 51h6',
    'M57 51l4 4 8-8',
  ],
  EmptyArt.wallet: <String>[
    'M18 22a6 6 0 0 1 6-6h40v10',
    'M18 22v36a6 6 0 0 0 6 6h48a6 6 0 0 0 6-6V32a6 6 0 0 0-6-6H24a6 6 0 0 1-6-6',
    'M78 37H66a5 5 0 0 0 0 10h12z',
    'M30 44h18',
  ],
  EmptyArt.checklist: <String>[
    'rect 24 13 48 53 5',
    'rect 38 8 20 10 3',
    'M32 32l3.5 3.5L42 29M48 32h16M32 46l3.5 3.5L42 43M48 46h16M48 58h10',
  ],
  EmptyArt.search: <String>[
    'rect 16 11 44 53 4',
    'M25 25h26M25 33h18M25 41h12',
    'circle 60 46 12',
    'M69 55l11 11',
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
  final parts = element.split(' ');
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
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final element in emptyArtSvg[art]!) {
      canvas.drawPath(artElementPath(element), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(EmptyArtPainter oldDelegate) => oldDelegate.art != art || oldDelegate.color != color;
}

/// Illyustratsiya (asosiy rangda). Kenglik/balandlik nisbati 4:3.
class EmptyIllustration extends StatelessWidget {
  const EmptyIllustration(this.art, {super.key, this.width = 112, this.color});

  final EmptyArt art;
  final double width;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        width: width,
        height: width * 0.75,
        child: CustomPaint(painter: EmptyArtPainter(art, color ?? AppColors.brand)),
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
