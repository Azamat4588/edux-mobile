// EduX ko'rinishi (2.0): kunduzgi va tungi rejim, tashkilot tanlagan asosiy rang (veb-tizimdagi 7 ta rang bilan bir xil).
//
// AppColors dagi «sirt» ranglari (brand, ink, muted, line, surface, card ...) joriy mavzuga qarab o'zgaradi:
// AppTheme.apply() ularni MaterialApp qurilishidan oldin yangilaydi, ilova esa yangi kalit bilan to'liq qayta chiziladi.
import 'package:flutter/material.dart';

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

  // Ma'no ranglari: ikkala rejimda bir xil.
  static const Color sun = Color(0xFFFFC233);
  static const Color success = Color(0xFF059669);
  static const Color warning = Color(0xFFD97706);
  static const Color danger = Color(0xFFE11D48);

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

  /// Ma'no rangining yumshoq foni (ogohlantirish, xato, faol band ...).
  static Color soft(Color color) => Color.alphaBlend(color.withAlpha(dark ? 46 : 22), card);
}

class AppTheme {
  AppTheme._();

  static void apply({required bool dark, required Accent accent}) {
    AppColors.dark = dark;
    AppColors.brand = dark && accent.key == 'slate' ? const Color(0xFF94A3B8) : accent.from;
    AppColors.brandDark = Color.lerp(accent.from, Colors.black, 0.18)!;
    AppColors.gradient = accent.gradient;
    if (dark) {
      AppColors.surface = const Color(0xFF0A1020);
      AppColors.card = const Color(0xFF111A2D);
      AppColors.line = const Color(0xFF232C43);
      AppColors.ink = const Color(0xFFEEF1F6);
      AppColors.muted = const Color(0xFF8A94AB);
    } else {
      AppColors.surface = const Color(0xFFF5F7FB);
      AppColors.card = Colors.white;
      AppColors.line = const Color(0xFFE5E7EB);
      AppColors.ink = const Color(0xFF111827);
      AppColors.muted = const Color(0xFF6B7280);
    }
  }
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
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: brightness, scaffoldBackgroundColor: AppColors.surface);
  return base.copyWith(
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.card,
      foregroundColor: AppColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: false,
      titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink),
    ),
    cardTheme: CardThemeData(color: AppColors.card, surfaceTintColor: Colors.transparent),
    dialogTheme: DialogThemeData(backgroundColor: AppColors.card, surfaceTintColor: Colors.transparent),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: AppColors.card, surfaceTintColor: Colors.transparent),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.line)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.brand, width: 2)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.brand,
        foregroundColor: Colors.white,
        minimumSize: const Size(48, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: BorderSide(color: AppColors.line),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.card,
      surfaceTintColor: Colors.transparent,
      indicatorColor: AppColors.brand.withAlpha(AppColors.dark ? 70 : 30),
      labelTextStyle: WidgetStateProperty.all(const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    ),
    chipTheme: base.chipTheme.copyWith(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
    dividerTheme: DividerThemeData(color: AppColors.line, space: 1, thickness: 1),
    listTileTheme: ListTileThemeData(iconColor: AppColors.muted),
  );
}
