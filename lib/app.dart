// Ilova ildizi: til, mavzu va kirish holatiga qarab birinchi sahifa.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/api.dart';
import 'core/i18n.dart';
import 'core/session.dart';
import 'core/theme.dart';
import 'core/widgets.dart';
import 'features/auth/login_page.dart';
import 'features/auth/organization_picker.dart';
import 'features/scanner/scan_queue.dart';
import 'features/shell/home_shell.dart';

class EduxApp extends StatelessWidget {
  const EduxApp({super.key});

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context);
    return MaterialApp(
      // Til almashganda butun daraxt yangi tilda qayta quriladi
      key: ValueKey<String>(I18n.locale),
      title: 'EduX',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      locale: Locale(I18n.locale),
      supportedLocales: const <Locale>[Locale('uz'), Locale('ru'), Locale('en')],
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: _Gate(session: session),
    );
  }
}

class _Gate extends StatelessWidget {
  const _Gate({required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    if (session.restoring) return const _Splash();
    if (!session.signedIn) return const LoginPage();
    // Kirgan foydalanuvchining navbatdagi varaqalari (internet bo'lmaganda saqlanganlar) yuborilsin
    ScanQueue.instance.attach(session);
    if (session.memberships.isEmpty) {
      if (session.user.isEmpty) return const _ContextLoader();
      return const NoOrganizationPage();
    }
    if (session.organizationId == null) return const OrganizationPicker();
    if (!session.hasContext) return const _ContextLoader();
    return HomeShell(key: ValueKey<String>('${session.organizationId}-${session.role}'));
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.brand,
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Image.asset('assets/brand/mark.png', width: 84, height: 84),
          const SizedBox(height: 18),
          const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.6, color: Colors.white)),
        ]),
      ),
    );
  }
}

/// Token bor, lekin tashkilot konteksti hali yuklanmagan (masalan, ilova internetsiz ochilgan).
class _ContextLoader extends StatefulWidget {
  const _ContextLoader();

  @override
  State<_ContextLoader> createState() => _ContextLoaderState();
}

class _ContextLoaderState extends State<_ContextLoader> {
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final session = AppScope.read(context);
    setState(() => _error = null);
    try {
      if (session.user.isEmpty || session.memberships.isEmpty) {
        // Ilova internetsiz ochilgan: foydalanuvchi va a'zoliklarni qayta olamiz
        await session.restore();
        return;
      }
      await session.loadContext();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _error == null
          ? const Center(child: CircularProgressIndicator())
          : ErrorState(message: _error!, onRetry: _load),
      bottomNavigationBar: _error == null
          ? null
          : SafeArea(
              child: TextButton(
                onPressed: () => AppScope.read(context).signOut(),
                child: Text(tr('Chiqish')),
              ),
            ),
    );
  }
}
