import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'core/session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Skaner va jadvallar tik holatda qulay: ilova faqat tik holatda ishlaydi.
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[DeviceOrientation.portraitUp]);
  final session = Session();
  runApp(AppScope(session: session, child: const EduxApp()));
  await session.restore();
}
