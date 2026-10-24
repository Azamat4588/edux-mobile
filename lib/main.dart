import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'core/session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Skaner va jadvallar tik holatda qulay: ilova faqat tik holatda ishlaydi.
  // 3.8: birinchi kadr kutmasin — platforma chaqiruvlari fonda.
  unawaited(SystemChrome.setPreferredOrientations(<DeviceOrientation>[DeviceOrientation.portraitUp]));
  // Rasm keshi: kartadagi kichik rasmlar (logo, avatar) uchun yetarli, xotira chegaralangan.
  PaintingBinding.instance.imageCache
    ..maximumSize = 300
    ..maximumSizeBytes = 64 << 20;
  final session = Session();
  runApp(AppScope(session: session, child: const EduxApp()));
  await session.restore();
}
