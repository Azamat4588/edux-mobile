// Ilova ildizi: til, mavzu va kirish holatiga qarab birinchi sahifa.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/api.dart';
import 'core/i18n.dart';
import 'core/koshin.dart';
import 'core/push.dart';
import 'core/session.dart';
import 'core/theme.dart';
import 'core/widgets.dart';
import 'features/auth/login_page.dart';
import 'features/auth/organization_picker.dart';
import 'features/scanner/scan_queue.dart';
import 'features/shell/home_shell.dart';

/// Tizim shrift o'lchami chegaralari (Dynamic Type).
const double textScaleMin = 0.85;
const double textScaleMax = 1.6;

class EduxApp extends StatefulWidget {
  const EduxApp({super.key});

  @override
  State<EduxApp> createState() => _EduxAppState();
}

class _EduxAppState extends State<EduxApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // «Qurilmaga qarab» rejimida telefon mavzusi o'zgarsa — darhol ergashadi.
  @override
  void didChangePlatformBrightness() => setState(() {});

  /// Oxirgi qo'llangan ko'rinish kaliti: o'zgarsa — butun daraxt qayta chiziladi (navigatsiya holati saqlanadi).
  String? _themeKey;

  /// 3.8: ko'rinish almashganda MaterialApp qayta yaratilmaydi (ochiq sahifalar, masalan «Ko'rinish», joyida qoladi) —
  /// AppColors statik tokenlarini o'qiydigan barcha elementlar keyingi kadrda qayta quriladi.
  void _rebuildAll() {
    if (!mounted) return;
    void visit(Element element) {
      element.markNeedsBuild();
      element.visitChildren(visit);
    }

    (context as Element).visitChildren(visit);
  }

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context);
    final mode = session.themeMode;
    final platformDark = WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
    final dark = mode == 'dark' || (mode == 'system' && platformDark);
    final accent = session.accent;
    final choice = session.themeChoice;
    AppTheme.apply(dark: dark, accent: accent, choice: choice);
    final themeKey = '$dark-${choice.key}';
    if (_themeKey != null && _themeKey != themeKey) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _rebuildAll());
    }
    _themeKey = themeKey;
    return MaterialApp(
      // Til almashganda butun daraxt yangi tilda qayta quriladi (server yorliqlari ham qayta yuklanadi).
      key: ValueKey<String>(I18n.locale),
      themeAnimationDuration: Duration.zero,
      navigatorKey: rootNavigator,
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
      // Shrift o'lchami (Kichik … Juda katta): butun interfeys mutanosib kattalashadi, telefon sozlamasi ham hisobga olinadi.
      // 3.7: iOS Dynamic Type / Android shrift o'lchami 0.85–1.6 oralig'ida cheklanadi (eng katta «Accessibility» o'lchamlarida
      // ham tugma va kartalar sig'sin); ilova ichidagi tanlov shu ustiga qo'llanadi.
      builder: (context, child) {
        final media = MediaQuery.of(context);
        final scale = choice.textScale;
        final system = media.textScaler.clamp(minScaleFactor: textScaleMin, maxScaleFactor: textScaleMax);
        return MediaQuery(
          data: media.copyWith(textScaler: scale == 1 ? system : TextScaler.linear(system.scale(16) / 16 * scale)),
          child: child ?? const SizedBox(),
        );
      },
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
      // 3.11: platforma egasi (tashkilotsiz) — ilova platforma paneli sifatida ochiladi (oldin faqat SMS shlyuz edi).
      if (session.isPlatformAdmin) return const HomeShell(key: ValueKey<String>('platform-owner'));
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
    // Kirish paneli bilan bir xil: «lojuvard tun» va oq girih yulduzlari naqshi (gradient yo'q).
    return Scaffold(
      backgroundColor: Koshin.night,
      body: Stack(children: <Widget>[
        Positioned.fill(child: CustomPaint(painter: GirihPatternPainter(step: 96))),
        Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            Image.asset('assets/brand/mark.png', width: 76, height: 76),
            const SizedBox(height: 20),
            const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white)),
          ]),
        ),
      ]),
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
        // 3.9.1: server javob bermasa — cheksiz aylanish emas, sabab va «Qayta urinish» / «Chiqish».
        if (mounted && session.user.isEmpty) {
          setState(() => _error = session.restoreError ?? tr("Server javob bermadi. Internetni tekshirib, qayta urinib ko'ring."));
        }
        return;
      }
      await session.loadContext();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = tr("Serverda xatolik yuz berdi. Birozdan keyin qayta urinib ko'ring."));
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
