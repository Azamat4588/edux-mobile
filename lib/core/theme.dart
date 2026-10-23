// EduX ko'rinishi: kunduzgi va tungi rejim, asosiy rang (veb-tizimdagi 7 ta rang) va 3.4 dan veb 1.35 dizayn tizimi —
// 5 shablon (Klassik, Yumshoq, Qorong'i panel, Ixcham, Maktab), shrift (Onest, Manrope, Nunito), o'lcham va burchaklar.
//
// AppColors dagi «sirt» ranglari (brand, ink, muted, line, surface, card ...) joriy mavzuga qarab o'zgaradi:
// AppTheme.apply() ularni MaterialApp qurilishidan oldin yangilaydi, ilova esa yangi kalit bilan to'liq qayta chiziladi.
// Rang faqat ma'no uchun (docs/design.md): asosiy rang — harakat, qizil — qarz/xato, sariq — kutilmoqda, yashil — bajarildi.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'design.dart';

/// Asosiy rang varianti: gradient uch nuqtasi (veb: resources/js/lib/theme.js ACCENTS).
class Accent {
  const Accent(this.key, this.label, this.from, this.via, this.to);

  final String key;
  final String label;
  final Color from;
  final Color via;
  final Color to;

  LinearGradient get gradient => LinearGradient(colors: <Color>[from, via, to], begin: Alignment.topLeft, end: Alignment.bottomRight);
}

const List<Accent> accents = <Accent>[
  Accent('blue', 'Moviy', Color(0xFF1F63F5), Color(0xFF4F5BFF), Color(0xFF7B5CFF)),
  Accent('violet', 'Binafsha', Color(0xFF7C3AED), Color(0xFFA855F7), Color(0xFFEC4899)),
  Accent('emerald', 'Zumrad', Color(0xFF059669), Color(0xFF10B981), Color(0xFF14B8A6)),
  Accent('teal', 'Feruza', Color(0xFF0891B2), Color(0xFF06B6D4), Color(0xFF3B82F6)),
  Accent('sunset', 'Shafaq', Color(0xFFEA580C), Color(0xFFF97316), Color(0xFFF43F5E)),
  Accent('rose', 'Anor', Color(0xFFBE123C), Color(0xFFE11D48), Color(0xFFFB7185)),
  Accent('slate', 'Grafit', Color(0xFF1E293B), Color(0xFF334155), Color(0xFF64748B)),
];

Accent accentOf(String? key) => accents.firstWhere((item) => item.key == key, orElse: () => accents.first);

class AppColors {
  AppColors._();

  static const Color sun = Color(0xFFFFC233);

  // Ma'no ranglari (matn, ikonka, yumshoq fon): rejimga qarab (AppTheme.apply). Yorug'da — 700 ton (oq fonda AA ≥ 4.5),
  // tungi rejimda — 400 ton (to'q kartada o'qiladi). Avval bir xil o'rta ton edi: oq fonda ogohlantirish matni 3.2:1.
  static Color success = const Color(0xFF047857);
  static Color warning = const Color(0xFFB45309);
  static Color danger = const Color(0xFFBE123C);

  /// Oq matnli to'liq fon (nishon, xato xabari, «Jonli» belgisi, xavfli tugma) — ikkala rejimda bir xil, oq bilan ≥ 4.5.
  static const Color successFill = Color(0xFF047857);
  static const Color warningFill = Color(0xFFB45309);
  static const Color dangerFill = Color(0xFFBE123C);

  /// Asosiy rang ustidagi matn (tugma): odatda oq; och asosiy rangda (tungi «Grafit») — to'q.
  static Color onBrand = Colors.white;

  // Mavzuga bog'liq ranglar (AppTheme.apply yangilaydi).
  static Color brand = const Color(0xFF1F63F5);
  static Color brandDark = const Color(0xFF1849C6);
  static Color muted = const Color(0xFF6B7280);
  static Color surface = const Color(0xFFF5F7FB);
  static Color card = Colors.white;
  static Color line = const Color(0xFFE5E7EB);
  static Color ink = const Color(0xFF111827);
  static LinearGradient gradient = accents.first.gradient;
  static bool dark = false;

  /// 3.4 (veb 1.35 tokenlari): karta chegarasi (Yumshoq — yo'q), ikkinchi sirt, yuqori panel foni va matni.
  static Color cardBorder = const Color(0xFFE5E7EB);
  static Color surface2 = const Color(0xFFF8F9FC);
  static Color chrome = Colors.white;
  static Color onChrome = const Color(0xFF111827);
  static List<BoxShadow> cardShadow = const <BoxShadow>[];

  /// «Bugun» kartasidagi chap chiziq ranglari (veb: rose-500, amber-500, emerald-500).
  static const Color toneDanger = Color(0xFFF43F5E);
  static const Color toneWarning = Color(0xFFF59E0B);
  static const Color toneSuccess = Color(0xFF10B981);

  /// Joriy ko'rinish (shablon, shrift, burchak ...).
  static ThemeChoice choice = const ThemeChoice();

  /// Ma'no rangining yumshoq foni (ogohlantirish, xato, faol band ...).
  static Color soft(Color color) => Color.alphaBlend(color.withAlpha(dark ? 46 : 22), card);
}

/// Bir xil oraliqlar (3.1 dizayn): 4 / 8 / 12 / 16 / 24.
class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 24;
}

class AppRadius {
  AppRadius._();

  /// Karta va boshqaruv burchagi shablon va foydalanuvchi tanloviga ko'paytiriladi (AppTheme.apply).
  static double card = 16;
  static double control = 12;
  static const double sheet = 22;
}

class AppTheme {
  AppTheme._();

  static void apply({required bool dark, required Accent accent, ThemeChoice choice = const ThemeChoice()}) {
    AppColors.dark = dark;
    AppColors.choice = choice;
    AppColors.brand = dark && accent.key == 'slate' ? const Color(0xFF94A3B8) : accent.from;
    AppColors.success = dark ? const Color(0xFF34D399) : const Color(0xFF047857);
    AppColors.warning = dark ? const Color(0xFFFBBF24) : const Color(0xFFB45309);
    AppColors.danger = dark ? const Color(0xFFFB7185) : const Color(0xFFBE123C);
    AppColors.brandDark = Color.lerp(accent.from, Colors.black, 0.18)!;
    AppColors.gradient = accent.gradient;
    final k = choice.radiusFactor;
    AppRadius.card = (16 * k).clamp(4, 28).toDouble();
    AppRadius.control = (12 * k).clamp(4, 22).toDouble();
    // Yumshoq shablonning pastel foni asosiy rangdan olinadi (veb: indigo-100 34% + #f7f8fc).
    final tint = Color.lerp(Colors.white, accent.from, 0.14)!;
    if (dark) {
      AppColors.surface = const Color(0xFF0B1222);
      AppColors.card = const Color(0xFF121A2C);
      AppColors.surface2 = const Color(0xFF162036);
      AppColors.line = const Color(0xFF243049);
      AppColors.ink = const Color(0xFFEEF1F6);
      AppColors.muted = const Color(0xFF9AA4B8);
      AppColors.chrome = AppColors.card;
      AppColors.onChrome = AppColors.ink;
      AppColors.cardShadow = const <BoxShadow>[];
      switch (choice.template) {
        case 'soft':
          AppColors.surface = const Color(0xFF0D1426);
          AppColors.surface2 = const Color(0xFF172138);
          AppColors.cardShadow = const <BoxShadow>[BoxShadow(color: Color(0xCC000000), blurRadius: 28, offset: Offset(0, 10), spreadRadius: -16)];
        case 'night':
          AppColors.chrome = const Color(0xFF070C18);
        case 'school':
          AppColors.surface = const Color(0xFF13110E);
          AppColors.card = const Color(0xFF1B1814);
          AppColors.surface2 = const Color(0xFF211D18);
          AppColors.line = const Color(0xFF322C24);
          AppColors.ink = const Color(0xFFF1ECE4);
          AppColors.muted = const Color(0xFFA89F92);
          AppColors.chrome = AppColors.card;
          AppColors.onChrome = AppColors.ink;
      }
    } else {
      AppColors.surface = const Color(0xFFF9FAFB);
      AppColors.card = Colors.white;
      AppColors.surface2 = const Color(0xFFF8F9FC);
      AppColors.line = const Color(0xFFE5E7EB);
      AppColors.ink = const Color(0xFF111827);
      // gray-600 (1.35 da to'qlashtirilgan: oq fonda AA kontrast)
      AppColors.muted = const Color(0xFF4B5563);
      AppColors.chrome = Colors.white;
      AppColors.onChrome = AppColors.ink;
      AppColors.cardShadow = const <BoxShadow>[BoxShadow(color: Color(0x0A101828), blurRadius: 2, offset: Offset(0, 1))];
      switch (choice.template) {
        case 'soft':
          AppColors.surface = Color.lerp(const Color(0xFFF7F8FC), tint, 0.34)!;
          AppColors.surface2 = Color.lerp(Colors.white, tint, 0.55)!;
          AppColors.cardShadow = <BoxShadow>[
            const BoxShadow(color: Color(0x08101828), blurRadius: 2, offset: Offset(0, 1)),
            BoxShadow(color: accent.from.withAlpha(60), blurRadius: 28, offset: const Offset(0, 10), spreadRadius: -14),
          ];
        case 'night':
          AppColors.chrome = const Color(0xFF111A2E);
          AppColors.onChrome = Colors.white;
        case 'compact':
          AppColors.cardShadow = const <BoxShadow>[];
        case 'school':
          AppColors.surface = const Color(0xFFFBF7F1);
          AppColors.surface2 = const Color(0xFFFDFAF5);
          AppColors.line = const Color(0xFFE9E1D4);
          AppColors.chrome = const Color(0xFFFFFDF9);
          AppColors.cardShadow = const <BoxShadow>[BoxShadow(color: Color(0x0F785A28), offset: Offset(0, 1))];
      }
    }
    AppColors.cardBorder = choice.borderlessCards ? Colors.transparent : (choice.notebook && !dark ? const Color(0xFFEBE3D6) : AppColors.line);
    // Asosiy rang matn va havola sifatida ham ishlatiladi: kartada kamida 4.5:1 bo'lsin (masalan, tungi rejimda «Anor»
    // 2.8:1 edi). Tugma matni — oq yoki to'q, qaysi biri o'qilsa.
    AppColors.brand = readableOn(AppColors.brand, AppColors.card);
    AppColors.onBrand = contrastRatio(Colors.white, AppColors.brand) >= 4.5 ? Colors.white : const Color(0xFF0B1222);
  }

  /// Sarlavha uslubi (veb: --font-title, --title-weight).
  static TextStyle title({double size = 22, Color? color}) => TextStyle(
        fontFamily: AppColors.choice.titleFamily,
        fontSize: size,
        fontWeight: AppColors.choice.titleWeight >= 800 ? FontWeight.w800 : FontWeight.w700,
        letterSpacing: AppColors.choice.template == 'night' ? -0.4 : -0.2,
        color: color ?? AppColors.ink,
      );
}

ThemeData buildTheme() {
  final brightness = AppColors.dark ? Brightness.dark : Brightness.light;
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.brand,
    brightness: brightness,
    primary: AppColors.brand,
    surface: AppColors.card,
    onSurface: AppColors.ink,
  );
  final choice = AppColors.choice;
  final dense = choice.dense;
  final onDarkChrome = choice.darkChrome && !AppColors.dark;
  final control = dense ? 40.0 : 48.0;
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
    scaffoldBackgroundColor: AppColors.surface,
    fontFamily: choice.fontFamily,
    visualDensity: dense ? VisualDensity.compact : VisualDensity.standard,
  );
  return base.copyWith(
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.chrome,
      foregroundColor: AppColors.onChrome,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: choice.titleFamily,
        fontSize: dense ? 17 : 18,
        fontWeight: choice.titleWeight >= 800 ? FontWeight.w800 : FontWeight.w700,
        color: AppColors.onChrome,
      ),
    ),
    cardTheme: CardThemeData(color: AppColors.card, surfaceTintColor: Colors.transparent),
    dialogTheme: DialogThemeData(backgroundColor: AppColors.card, surfaceTintColor: Colors.transparent),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: AppColors.card, surfaceTintColor: Colors.transparent),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.card,
      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: dense ? 10 : 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.control), borderSide: BorderSide(color: AppColors.line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.control), borderSide: BorderSide(color: AppColors.line)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.control), borderSide: BorderSide(color: AppColors.brand, width: 2)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.brand,
        foregroundColor: AppColors.onBrand,
        minimumSize: Size(48, control + 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
        // Shrift oilasi aniq: tugma matni aks holda tizim shriftiga (Roboto) tushib qoladi.
        textStyle: TextStyle(fontFamily: choice.fontFamily, fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: Size(48, control),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
        side: BorderSide(color: AppColors.line),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.card,
      height: dense ? 64 : 72,
      surfaceTintColor: Colors.transparent,
      indicatorColor: AppColors.brand.withAlpha(AppColors.dark ? 70 : 30),
      labelTextStyle: WidgetStateProperty.all(TextStyle(fontFamily: choice.fontFamily, fontSize: 12, fontWeight: FontWeight.w600)),
    ),
    chipTheme: base.chipTheme.copyWith(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular((10 * choice.radiusFactor).clamp(4, 99).toDouble()))),
    tabBarTheme: TabBarThemeData(
      // Hamma TabBar sarlavha paneli (AppBar.bottom) ichida: to'q panelda (Qorong'i panel) — oq matn.
      labelColor: onDarkChrome ? Colors.white : AppColors.brand,
      unselectedLabelColor: onDarkChrome ? const Color(0xFFC9D1E0) : AppColors.muted,
      indicatorColor: onDarkChrome ? Colors.white : AppColors.brand,
      labelStyle: TextStyle(fontFamily: choice.fontFamily, fontWeight: FontWeight.w700),
      dividerColor: Colors.transparent,
    ),
    dividerTheme: DividerThemeData(color: AppColors.line, space: 1, thickness: 1),
    listTileTheme: ListTileThemeData(
      iconColor: AppColors.muted,
      minVerticalPadding: dense ? 6 : 10,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.l),
    ),
    // Kattaroq bosish maydoni (kamida 48×48)
    materialTapTargetSize: MaterialTapTargetSize.padded,
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(minimumSize: Size(control, control))),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
    ),
  );
}

/// WCAG kontrast nisbati (1–21).
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// [color] ni [background] ustida o'qiladigan qiladi: kontrast [min] dan past bo'lsa — to'q fonda oqartiriladi,
/// och fonda to'qlashtiriladi (rang tusi saqlanadi). Toza mantiq — test/design_test.dart.
Color readableOn(Color color, Color background, {double min = 4.5}) {
  if (contrastRatio(color, background) >= min) return color;
  final target = background.computeLuminance() < 0.5 ? Colors.white : Colors.black;
  for (var step = 1; step <= 20; step++) {
    final candidate = Color.lerp(color, target, step / 20)!;
    if (contrastRatio(candidate, background) >= min) return candidate;
  }
  return target;
}
