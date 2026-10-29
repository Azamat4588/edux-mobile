// EduX ko'rinishi v3 (3.9, veb 1.41 «Koshin», docs/design.md «Rang qiymatlari (mobil ilova uchun)»):
// 9 shablon × yorug'/tungi palitra (aniq hex qiymatlar), 12 asosiy rang shkalasi (50/100/300/500/600/700), holat ranglari
// (fg/bg + to'liq «solid»), koshin ranglari (feruza, lojuvard, anor, pista, shafran, olxo'ri), semantik tokenlar.
//
// G'oya — Registon koshinlari: ish qismi (ro'yxat, forma) oq va sokin, rang ma'noli joyda — bosh sahifadagi koshin
// plitkalar, holat chiplari, faol menyu bandi, muhim lahzalar (to'lov muhri). AppColors joriy mavzuga qarab o'zgaradi:
// AppTheme.apply() ularni MaterialApp qurilishidan oldin yangilaydi.
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'design.dart';

/// Asosiy rang shkalasi (veb: palette.css, docs/design.md jadvali; v3 — oklch, 600 ustida oq matn ≥ 4.6:1).
class Accent {
  const Accent(this.key, this.label, this.c50, this.c100, this.c300, this.c500, this.c600, this.c700);

  final String key;
  final String label;
  final Color c50;
  final Color c100;
  final Color c300;
  final Color c500;
  final Color c600;
  final Color c700;

  /// Asosiy to'liq rang (tugma, faol band) — 600.
  Color get from => c600;
}

/// 12 rang (tartib — veb ACCENTS: standart Feruza birinchi).
const List<Accent> accents = <Accent>[
  Accent('teal', 'Feruza', Color(0xFFEAFBFD), Color(0xFFD2F6FA), Color(0xFF4FDCEB), Color(0xFF00A4B1), Color(0xFF00808B), Color(0xFF006A73)),
  Accent('blue', 'Moviy', Color(0xFFF2F7FF), Color(0xFFE5EEFF), Color(0xFFA7C6FF), Color(0xFF4F8BFF), Color(0xFF256BF7), Color(0xFF1456D8)),
  Accent('indigo', 'Indigo', Color(0xFFF5F6FF), Color(0xFFE9EDFF), Color(0xFFB8C1FF), Color(0xFF797FFF), Color(0xFF635DFD), Color(0xFF5249DE)),
  Accent('violet', 'Binafsha', Color(0xFFF7F5FF), Color(0xFFEFEBFF), Color(0xFFCAB9FF), Color(0xFF9D6EFF), Color(0xFF8D48FD), Color(0xFF7833DE)),
  Accent('plum', "Olxo'ri", Color(0xFFFFF2FE), Color(0xFFFFE4FD), Color(0xFFFF9CFC), Color(0xFFD451D3), Color(0xFFBE3BBE), Color(0xFFA427A4)),
  Accent('rose', 'Anor', Color(0xFFFFF4F4), Color(0xFFFFE7E8), Color(0xFFFFABB2), Color(0xFFF74368), Color(0xFFDE2654), Color(0xFFC10743)),
  Accent('sunset', 'Shafaq', Color(0xFFFFF4F1), Color(0xFFFFE8E1), Color(0xFFFFAF96), Color(0xFFF5510D), Color(0xFFD24100), Color(0xFFB13600)),
  Accent('amber', 'Qahrabo', Color(0xFFFFF5EC), Color(0xFFFFE9D8), Color(0xFFFFB36E), Color(0xFFD07800), Color(0xFFAC6200), Color(0xFF905100)),
  Accent('forest', "O'rmon", Color(0xFFEDFBEE), Color(0xFFD9F7DC), Color(0xFF7AE08C), Color(0xFF00AE45), Color(0xFF008734), Color(0xFF00702A)),
  Accent('emerald', 'Zumrad', Color(0xFFEBFBF4), Color(0xFFD6F7E8), Color(0xFF67E0B3), Color(0xFF00AA7D), Color(0xFF008561), Color(0xFF006E50)),
  Accent('sky', 'Osmon', Color(0xFFEEF8FF), Color(0xFFDCF1FF), Color(0xFF82D0FF), Color(0xFF009CDA), Color(0xFF007CAF), Color(0xFF006792)),
  Accent('slate', 'Grafit', Color(0xFFF6F7F8), Color(0xFFECEEF1), Color(0xFFC0C6D0), Color(0xFF8A919D), Color(0xFF4F5660), Color(0xFF3C434C)),
];

/// Kalit bo'yicha rang (noma'lum — Feruza).
Accent accentOf(String? key) => accents.firstWhere((item) => item.key == key, orElse: () => accents.first);

/// Koshin ranglari (veb: --k-*) — shablon, rejim va asosiy rangdan mustaqil: KPI plitkalar, muhr, holat nuqtalari.
class Koshin {
  Koshin._();

  static const Color sir = Color(0xFFF2F6F9);
  static const Color ink = Color(0xFF111C3A);
  static const Color feruza = Color(0xFF00808B);
  static const Color feruzaBright = Color(0xFF19B4C2);
  static const Color lojuvard = Color(0xFF2D4BD0);
  static const Color anor = Color(0xFFD0284F);
  static const Color pista = Color(0xFF12814A);
  static const Color shafran = Color(0xFFF2A93B);
  static const Color shafranInk = Color(0xFF2A1A00);
  static const Color olxori = Color(0xFF9B3596);

  /// Kirish oynasi va splash paneli — «lojuvard tun» (veb: .auth-panel #0F1D4A).
  static const Color night = Color(0xFF0F1D4A);

  static Color of(KoshinHue hue) {
    switch (hue) {
      case KoshinHue.feruza:
        return feruza;
      case KoshinHue.lojuvard:
        return lojuvard;
      case KoshinHue.anor:
        return anor;
      case KoshinHue.pista:
        return pista;
      case KoshinHue.shafran:
        return shafran;
      case KoshinHue.olxori:
        return olxori;
    }
  }

  /// Plitka ustidagi matn: oq, shafranda — to'q (veb: --k-shafran-ink).
  static Color onTile(KoshinHue hue) => hue == KoshinHue.shafran ? shafranInk : Colors.white;
}

/// Shablon palitrasi (asosiy rang — standart Feruza bo'lganda hisoblangan qiymatlar, docs/design.md).
class TemplatePalette {
  const TemplatePalette({
    required this.canvas,
    required this.surface,
    required this.surface2,
    required this.raised,
    required this.text1,
    required this.text2,
    required this.text3,
    required this.border,
    required this.borderStrong,
    required this.sidebarBg,
    required this.sidebarFg,
    required this.sidebarActiveBg,
    required this.sidebarActiveFg,
    required this.headerBg,
  });

  final Color canvas;
  final Color surface;
  final Color surface2;
  final Color raised;
  final Color text1;
  final Color text2;
  final Color text3;
  final Color border;
  final Color borderStrong;
  final Color sidebarBg;
  final Color sidebarFg;
  final Color sidebarActiveBg;
  final Color sidebarActiveFg;
  final Color headerBg;
}

TemplatePalette _p(List<int> v) => TemplatePalette(
      canvas: Color(0xFF000000 | v[0]),
      surface: Color(0xFF000000 | v[1]),
      surface2: Color(0xFF000000 | v[2]),
      raised: Color(0xFF000000 | v[3]),
      text1: Color(0xFF000000 | v[4]),
      text2: Color(0xFF000000 | v[5]),
      text3: Color(0xFF000000 | v[6]),
      border: Color(0xFF000000 | v[7]),
      borderStrong: Color(0xFF000000 | v[8]),
      sidebarBg: Color(0xFF000000 | v[9]),
      sidebarFg: Color(0xFF000000 | v[10]),
      sidebarActiveBg: Color(0xFF000000 | v[11]),
      sidebarActiveFg: Color(0xFF000000 | v[12]),
      headerBg: Color(0xFF000000 | v[13]),
    );

/// docs/design.md «Rang qiymatlari (mobil ilova uchun)», v3: shablon → [yorug', tungi].
/// Tartib: canvas, surface, surface-2, raised, text-1, text-2, text-3, border, border-strong, sidebar-bg, sidebar-fg,
/// sidebar-active-bg, sidebar-active-fg, header-bg.
final Map<String, List<TemplatePalette>> templatePalettes = <String, List<TemplatePalette>>{
  'classic': <TemplatePalette>[
    _p(<int>[0xf2f6f9, 0xffffff, 0xf6f9fb, 0xffffff, 0x111c3a, 0x49566d, 0x556378, 0xdde5ec, 0xc8d2dc, 0xffffff, 0x33415c, 0x00808b, 0xffffff, 0xffffff]),
    _p(<int>[0x0b1424, 0x111c2f, 0x15223a, 0x1a2842, 0xedf2f6, 0xaab5c4, 0x9ba7b8, 0x22304a, 0x33435f, 0x0e1828, 0xc5cfd9, 0x00808b, 0xffffff, 0x0e1828]),
  ],
  'soft': <TemplatePalette>[
    _p(<int>[0xe9f8fb, 0xffffff, 0xf2fdfe, 0xffffff, 0x111c3a, 0x49566d, 0x556378, 0xdde5ec, 0xc8d2dc, 0xf4fdfe, 0x33415c, 0x00808b, 0xffffff, 0xf0fafc]),
    _p(<int>[0x0d1528, 0x111c2f, 0x172239, 0x1a2842, 0xedf2f6, 0xaab5c4, 0x9ba7b8, 0x22304a, 0x33435f, 0x121c32, 0xc5cfd9, 0x00808b, 0xffffff, 0x0d1528]),
  ],
  'night': <TemplatePalette>[
    _p(<int>[0xf2f6f9, 0xffffff, 0xf6f9fb, 0xffffff, 0x111c3a, 0x49566d, 0x556378, 0xdde5ec, 0xc8d2dc, 0x12225a, 0xdbe3f7, 0x00808b, 0xffffff, 0xffffff]),
    _p(<int>[0x0b1424, 0x111c2f, 0x15223a, 0x1a2842, 0xedf2f6, 0xaab5c4, 0x9ba7b8, 0x22304a, 0x33435f, 0x0a1640, 0xdbe3f7, 0x00808b, 0xffffff, 0x0e1828]),
  ],
  'compact': <TemplatePalette>[
    _p(<int>[0xf2f6f9, 0xffffff, 0xf6f9fb, 0xffffff, 0x111c3a, 0x49566d, 0x556378, 0xdde5ec, 0xc8d2dc, 0xffffff, 0x33415c, 0x00808b, 0xffffff, 0xffffff]),
    _p(<int>[0x0b1424, 0x111c2f, 0x15223a, 0x1a2842, 0xedf2f6, 0xaab5c4, 0x9ba7b8, 0x22304a, 0x33435f, 0x0e1828, 0xc5cfd9, 0x00808b, 0xffffff, 0x0e1828]),
  ],
  'school': <TemplatePalette>[
    _p(<int>[0xf3f7ff, 0xffffff, 0xf7f9ff, 0xffffff, 0x111c3a, 0x49566d, 0x556378, 0xdbe3f3, 0xc3cfe6, 0xffffff, 0x33415c, 0xe1edee, 0x111c3a, 0xffffff]),
    _p(<int>[0x0b1424, 0x111c2f, 0x15223a, 0x1a2842, 0xedf2f6, 0xaab5c4, 0x9ba7b8, 0x22304a, 0x33435f, 0x0e1828, 0xc5cfd9, 0x153244, 0xeef3fd, 0x0e1828]),
  ],
  'atlas': <TemplatePalette>[
    _p(<int>[0xfaf4f8, 0xffffff, 0xfdf8fb, 0xffffff, 0x2d112f, 0x664b60, 0x72596c, 0xeedde8, 0xdcc4d4, 0x3a1342, 0xf6e8f3, 0xf2a93b, 0x2a1a00, 0xffffff]),
    _p(<int>[0x150c17, 0x1d1220, 0x241828, 0x2a1c2f, 0xf5eff3, 0xbeafba, 0xb2a0ad, 0x3a2840, 0x4f3956, 0x12081a, 0xf6e8f3, 0xf2a93b, 0x2a1a00, 0x1a101c]),
  ],
  'ocean': <TemplatePalette>[
    _p(<int>[0xeaf5f7, 0xffffff, 0xf3f9fa, 0xffffff, 0x002030, 0x395b69, 0x476774, 0xd0e4ea, 0xb1ccd5, 0xf6fbfc, 0x214656, 0x00808b, 0xffffff, 0xf6fbfc]),
    _p(<int>[0x07151b, 0x0e2029, 0x122731, 0x152c37, 0xeaf3f5, 0xa1b7bd, 0x90aab0, 0x1d3641, 0x2a4856, 0x0a1a21, 0xc0d2d5, 0x00808b, 0xffffff, 0x0a1a21]),
  ],
  'graphite': <TemplatePalette>[
    _p(<int>[0xffffff, 0xffffff, 0xf4f5f7, 0xffffff, 0x111418, 0x33353b, 0x45484d, 0xb9c0cc, 0x8a93a3, 0x16191f, 0xe8eaee, 0x00808b, 0xffffff, 0xffffff]),
    _p(<int>[0x0e1014, 0x15181e, 0x1b1f26, 0x1d2128, 0xf4f5f8, 0xd2d4d8, 0xb4b7bd, 0x3a404c, 0x59616f, 0x0a0c0f, 0xe8eaee, 0x00808b, 0xffffff, 0x111318]),
  ],
  'spring': <TemplatePalette>[
    _p(<int>[0xeef8e8, 0xffffff, 0xf6fbf2, 0xffffff, 0x141f11, 0x4b5a48, 0x576554, 0xd8e8cb, 0xbcd3a8, 0xffffff, 0x374634, 0xdceaec, 0x1f2a1a, 0xffffff]),
    _p(<int>[0x0d150a, 0x151e11, 0x1a2415, 0x1c2717, 0xeef3ec, 0xadb6a8, 0x9ea899, 0x293622, 0x3b4b32, 0x11190e, 0xc9d1c5, 0x19342c, 0xeef6e6, 0x10180d]),
  ],
};

/// Holat ranglari: [fg, bg] (matn va yumshoq fon).
class StatusColors {
  const StatusColors(this.fg, this.bg);

  final Color fg;
  final Color bg;
}

class AppColors {
  AppColors._();

  static const Color sun = Koshin.shafran;

  // Ma'no ranglari (matn, ikonka): docs/design.md «Holat» jadvali — yorug'da to'q, tungi rejimda och.
  static Color success = const Color(0xFF007A55);
  static Color warning = const Color(0xFFBB4D00);
  static Color danger = const Color(0xFFC70036);
  static Color info = const Color(0xFF0069A8);
  static Color successBg = const Color(0xFFECFDF5);
  static Color warningBg = const Color(0xFFFFFBEB);
  static Color dangerBg = const Color(0xFFFFF1F2);
  static Color infoBg = const Color(0xFFF0F9FF);

  /// Oq matnli to'liq fon (nishon, xato xabari, «Jonli» belgisi, xavfli tugma) — koshin ranglari, ikkala rejimda bir xil.
  static const Color successFill = Koshin.pista;
  static const Color warningFill = Color(0xFFB45F00);
  static const Color dangerFill = Koshin.anor;

  /// Asosiy rang ustidagi matn (tugma): oq.
  static Color onBrand = Colors.white;

  /// Matn va ikonka uchun asosiy rang (yorug'da 600, tungi rejimda 300 — sirtda ≥ 4.5:1).
  static Color brand = Koshin.feruza;

  /// To'liq asosiy rang (tugma, faol band) — 600.
  static Color accent = Koshin.feruza;

  /// Bezak uchun yorqin tus (veb: --accent-bright, 500): grafik chizig'i, nuqta.
  static Color accentBright = const Color(0xFF00A4B1);

  /// Asosiy rangning matn tusi (`--accent-strong`): yorug'da 700, tungi rejimda 300.
  static Color accentStrong = const Color(0xFF006A73);

  /// Asosiy rangning yumshoq foni (`--accent-soft`, `--accent-soft-2`).
  static Color accentSoft = const Color(0xFFEAFBFD);
  static Color accentSoft2 = const Color(0xFFD2F6FA);

  /// Kirish paneli, sertifikat va yutuqlar banneri — «lojuvard tun».
  static Color panel = Koshin.night;
  static Color brandDark = const Color(0xFF006A73);

  // Sirtlar va matn (semantik tokenlar).
  static Color canvas = const Color(0xFFF2F6F9);
  static Color surface = const Color(0xFFF2F6F9); // = canvas (eski nom: sahifa foni)
  static Color card = Colors.white; // = surface (karta)
  static Color surface2 = const Color(0xFFF6F9FB);
  static Color raised = Colors.white;
  static Color sunken = const Color(0xFFE9EFF4);
  static Color ink = const Color(0xFF111C3A);
  static Color muted = const Color(0xFF49566D);
  static Color subtle = const Color(0xFF556378);
  static Color line = const Color(0xFFDDE5EC);
  static Color lineStrong = const Color(0xFFC8D2DC);
  static Color focus = Koshin.feruza;
  static bool dark = false;

  /// Karta chegarasi (Soyali/Tekis kartada — shaffof) va soyasi (v3 standarti — soyasiz).
  static Color cardBorder = const Color(0xFFDDE5EC);
  static List<BoxShadow> cardShadow = const <BoxShadow>[];

  /// Bosiladigan karta/plitka ko'tarilganda va menyu, oyna soyasi (veb: --shadow-2/3, lojuvard tusli).
  static List<BoxShadow> shadow2 = const <BoxShadow>[];
  static List<BoxShadow> shadow3 = const <BoxShadow>[];

  /// Sarlavha paneli (AppBar, pastki menyu — veb: --header-bg, tekis) va uning matni.
  static Color chrome = Colors.white;
  static Color onChrome = const Color(0xFF111C3A);

  /// iPad yon menyusi (veb: sidebar): fon, matn, faol band (to'liq rangli tabletka).
  static Color navBg = Colors.white;
  static Color navFg = const Color(0xFF33415C);
  static Color navActiveBg = Koshin.feruza;
  static Color navActiveFg = Colors.white;
  static Color navLine = const Color(0xFFDDE5EC);
  static bool navDark = false;

  /// Holatning to'liq rangi (veb: --success-solid ...): chip nuqtasi, son plitkasi, toast belgisi.
  static Color toneDanger = Koshin.anor;
  static Color toneWarning = Koshin.shafran;
  static Color toneSuccess = Koshin.pista;
  static Color toneInfo = Koshin.lojuvard;

  /// Joriy ko'rinish (shablon, shrift, burchak ...).
  static ThemeChoice choice = const ThemeChoice();

  /// Avatar va belgi plitkalari (koshin oilasi): [fg, bg].
  static List<StatusColors> tiles = const <StatusColors>[];

  /// Ma'no rangining yumshoq foni (ogohlantirish, xato, faol band ...): holat ranglari uchun — jadvaldagi aniq fon.
  static Color soft(Color color) {
    if (color == success || color == toneSuccess) return successBg;
    if (color == warning || color == toneWarning) return warningBg;
    if (color == danger || color == toneDanger) return dangerBg;
    if (color == info || color == toneInfo) return infoBg;
    if (color == brand || color == accent) return accentSoft;
    return Color.alphaBlend(color.withAlpha(dark ? 66 : 38), card);
  }

  /// Ismdan barqaror plitka rangi (Avatar).
  static StatusColors tileFor(String name) => tiles.isEmpty ? StatusColors(brand, accentSoft) : tiles[stableIndex(name, tiles.length)];
}

/// Bir xil oraliqlar (4px qadam).
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

  /// Burchaklar shablon va foydalanuvchi tanloviga ko'paytiriladi (veb: --r-* × --rk; AppTheme.apply).
  static double card = 14;
  static double control = 10;
  static double chip = 6;

  /// KPI plitka (veb: --kpi-r = --r-xl, Ixcham/Grafit — --r-lg).
  static double kpi = 20;
  static const double sheet = 22;
}

/// Harakat (veb: --dur-1/2/3, --ease-out, --ease-spring, --stagger, --press-scale).
class AppDurations {
  AppDurations._();

  static const Duration d1 = Duration(milliseconds: 110);
  static const Duration d2 = Duration(milliseconds: 200);
  static const Duration d3 = Duration(milliseconds: 280);

  /// Plitkalar orasidagi navbat.
  static const Duration stagger = Duration(milliseconds: 45);
}

class AppCurves {
  AppCurves._();

  /// cubic-bezier(.22, .8, .24, 1)
  static const Curve out = Cubic(0.22, 0.8, 0.24, 1);

  /// Prujina: cubic-bezier(.34, 1.5, .64, 1) — biroz oshib, joyiga qaytadi.
  static const Curve spring = Cubic(0.34, 1.5, 0.64, 1);
}

class AppTheme {
  AppTheme._();

  static void apply({required bool dark, required Accent accent, ThemeChoice choice = const ThemeChoice()}) {
    AppColors.dark = dark;
    AppColors.choice = choice;
    final template = templatePalettes.containsKey(choice.template) ? choice.template : 'classic';
    final palette = templatePalettes[template]![dark ? 1 : 0];
    final teal = accent.key == 'teal';

    // Sirt va matn — jadvaldagi aniq qiymatlar.
    AppColors.canvas = palette.canvas;
    AppColors.card = palette.surface;
    AppColors.surface2 = palette.surface2;
    AppColors.raised = palette.raised;
    AppColors.ink = palette.text1;
    AppColors.muted = palette.text2;
    AppColors.subtle = palette.text3;
    AppColors.line = palette.border;
    AppColors.lineStrong = palette.borderStrong;
    AppColors.navBg = palette.sidebarBg;
    AppColors.navFg = palette.sidebarFg;
    AppColors.chrome = palette.headerBg;
    // Yumshoq shablon: pastel kanvas asosiy rangdan (veb: color-mix(indigo-100 38%, #f7f9fc)).
    if (template == 'soft' && !dark && !teal) {
      AppColors.canvas = Color.lerp(const Color(0xFFF7F9FC), accent.c100, 0.38)!;
      AppColors.surface2 = Color.lerp(Colors.white, accent.c50, 0.6)!;
      AppColors.navBg = Color.lerp(Colors.white, accent.c50, 0.55)!;
      AppColors.chrome = Color.lerp(Colors.white, AppColors.canvas, 0.7)!;
    }
    AppColors.surface = AppColors.canvas;
    AppColors.sunken = Color.lerp(AppColors.canvas, dark ? Colors.black : AppColors.lineStrong, dark ? 0.25 : 0.22)!;

    // Asosiy rang.
    AppColors.accent = accent.c600;
    AppColors.accentBright = accent.c500;
    AppColors.accentStrong = dark ? accent.c300 : accent.c700;
    AppColors.brand = readableOn(dark ? accent.c300 : accent.c600, palette.surface);
    AppColors.brandDark = accent.c700;
    AppColors.accentSoft = dark ? Color.lerp(palette.surface, accent.c500, 0.16)! : accent.c50;
    AppColors.accentSoft2 = dark ? Color.lerp(palette.surface, accent.c500, 0.26)! : accent.c100;
    AppColors.focus = dark ? accent.c300 : accent.c600;
    AppColors.onBrand = contrastRatio(Colors.white, AppColors.accent) >= 4.5 ? Colors.white : Koshin.ink;

    // iPad yon menyusi: faol band — to'liq rangli tabletka (Atlas — shafran; Maktab/Bahor — bo'lim rangining och tusi,
    // [sectionActive] har band uchun hisoblaydi; jadvaldagi qiymat Feruza uchun).
    switch (template) {
      case 'atlas':
        AppColors.navActiveBg = palette.sidebarActiveBg;
        AppColors.navActiveFg = palette.sidebarActiveFg;
      case 'school':
      case 'spring':
        AppColors.navActiveBg = teal ? palette.sidebarActiveBg : sectionActive(accent.c600);
        AppColors.navActiveFg = palette.sidebarActiveFg;
      default:
        AppColors.navActiveBg = accent.c600;
        AppColors.navActiveFg = Colors.white;
    }
    AppColors.navDark = palette.sidebarBg.computeLuminance() < 0.2;
    AppColors.navLine = AppColors.navDark && !dark ? palette.sidebarBg : palette.border;

    // Holat ranglari (jadval) va to'liq ranglar (koshin).
    if (dark) {
      AppColors.success = const Color(0xFF5EE9B5);
      AppColors.successBg = const Color(0xFF132F3A);
      AppColors.warning = const Color(0xFFFFD230);
      AppColors.warningBg = const Color(0xFF2C2C33);
      AppColors.danger = const Color(0xFFFFA1AD);
      AppColors.dangerBg = const Color(0xFF302436);
      AppColors.info = const Color(0xFF74D4FF);
      AppColors.infoBg = const Color(0xFF142C45);
    } else {
      AppColors.success = const Color(0xFF007A55);
      AppColors.successBg = const Color(0xFFECFDF5);
      AppColors.warning = const Color(0xFFBB4D00);
      AppColors.warningBg = const Color(0xFFFFFBEB);
      AppColors.danger = const Color(0xFFC70036);
      AppColors.dangerBg = const Color(0xFFFFF1F2);
      AppColors.info = const Color(0xFF0069A8);
      AppColors.infoBg = const Color(0xFFF0F9FF);
    }
    AppColors.toneDanger = Koshin.anor;
    AppColors.toneWarning = Koshin.shafran;
    AppColors.toneSuccess = Koshin.pista;
    AppColors.toneInfo = Koshin.lojuvard;
    // Ba'zi shablonlarda karta foni boshqacha — o'qilishini kafolatlaymiz.
    AppColors.success = readableOn(AppColors.success, AppColors.card);
    AppColors.warning = readableOn(AppColors.warning, AppColors.card);
    AppColors.danger = readableOn(AppColors.danger, AppColors.card);

    // Avatar/belgi plitkalari — koshin oilasi (birinchisi asosiy rang).
    StatusColors tile(Color base) {
      if (dark) {
        final fg = readableOn(Color.lerp(base, Colors.white, 0.42)!, palette.surface);
        return StatusColors(fg, Color.alphaBlend(base.withAlpha(56), palette.surface));
      }
      return StatusColors(readableOn(base, Color.lerp(Colors.white, base, 0.12)!), Color.lerp(Colors.white, base, 0.12)!);
    }

    AppColors.tiles = <StatusColors>[
      tile(accent.c600),
      tile(Koshin.lojuvard),
      tile(Koshin.olxori),
      tile(Koshin.pista),
      tile(const Color(0xFFB45F00)),
      tile(Koshin.anor),
    ];

    // Burchaklar (veb: --r-lg kartalar, --r-md boshqaruv, --r-xl KPI).
    final k = choice.radiusFactor;
    AppRadius.card = (14 * k).clamp(4, 28).toDouble();
    AppRadius.control = (10 * k).clamp(3, 22).toDouble();
    AppRadius.chip = (6 * k).clamp(2, 14).toDouble();
    AppRadius.kpi = ((choice.quietTiles ? 14 : 20) * k).clamp(6, 32).toDouble();

    // Soyalar (lojuvard tusli; Grafit — chiziq).
    final shadowInk = dark ? const Color(0xFF000000) : Koshin.ink;
    AppColors.shadow2 = template == 'graphite'
        ? <BoxShadow>[BoxShadow(color: palette.borderStrong, spreadRadius: 1)]
        : <BoxShadow>[
            BoxShadow(color: shadowInk.withAlpha(dark ? 60 : 13), blurRadius: 4, offset: const Offset(0, 2)),
            BoxShadow(color: shadowInk.withAlpha(dark ? 120 : 51), blurRadius: 28, offset: const Offset(0, 14), spreadRadius: -12),
          ];
    AppColors.shadow3 = <BoxShadow>[
      BoxShadow(color: shadowInk.withAlpha(dark ? 70 : 15), blurRadius: 10, offset: const Offset(0, 4)),
      BoxShadow(color: shadowInk.withAlpha(dark ? 150 : 82), blurRadius: 56, offset: const Offset(0, 28), spreadRadius: -16),
    ];

    // Karta uslubi: chegarali (v3 — soyasiz), soyali (chegarasiz), tekis (fon bilan ajraladi).
    switch (choice.effectiveCards) {
      case 'shadow':
        AppColors.cardBorder = dark ? palette.border : Colors.transparent;
        if (dark) {
          AppColors.cardShadow = const <BoxShadow>[BoxShadow(color: Color(0x99000000), blurRadius: 24, offset: Offset(0, 10), spreadRadius: -14)];
        } else if (template == 'spring') {
          // «Stiker»: qattiq pastki soya va nozik halqa.
          AppColors.cardShadow = const <BoxShadow>[
            BoxShadow(color: Color(0x1F3C6028), offset: Offset(0, 2)),
            BoxShadow(color: Color(0x123C6028), spreadRadius: 1),
          ];
        } else {
          AppColors.cardShadow = <BoxShadow>[
            const BoxShadow(color: Color(0x08111C3A), blurRadius: 2, offset: Offset(0, 1)),
            BoxShadow(color: accent.c600.withAlpha(56), blurRadius: 28, offset: const Offset(0, 10), spreadRadius: -16),
          ];
        }
      case 'flat':
        AppColors.cardBorder = dark ? palette.border.withAlpha(140) : Colors.transparent;
        AppColors.cardShadow = dark || template != 'ocean'
            ? const <BoxShadow>[]
            : const <BoxShadow>[
                BoxShadow(color: Color(0x0D0A323C), blurRadius: 2, offset: Offset(0, 1)),
                BoxShadow(color: Color(0x330A323C), blurRadius: 24, offset: Offset(0, 8), spreadRadius: -16),
              ];
      default:
        AppColors.cardBorder = palette.border;
        AppColors.cardShadow = const <BoxShadow>[];
    }

    AppColors.onChrome = palette.text1;
  }

  /// Maktab/Bahor: faol menyu bandi — bo'lim rangining och tusi (veb: color-mix(section 14–16%, #fff), tungi — 24%).
  static Color sectionActive(Color section) {
    final base = AppColors.dark ? AppColors.card : Colors.white;
    return Color.lerp(base, section, AppColors.dark ? 0.24 : (AppColors.choice.template == 'spring' ? 0.16 : 0.14))!;
  }

  /// Sarlavha uslubi (veb: --font-title Commissioner / Nunito, --title-weight, --title-tracking −0.03em).
  static TextStyle title({double size = 22, Color? color, FontWeight? weight}) {
    final choice = AppColors.choice;
    final nunito = choice.titleFamily == 'Nunito';
    return TextStyle(
      fontFamily: choice.titleFamily,
      fontFamilyFallback: const <String>['Commissioner', 'Onest', 'Manrope'],
      fontSize: size,
      height: 1.15,
      fontWeight: weight ?? _weight(choice.titleWeight),
      letterSpacing: size >= 20 ? (nunito ? -0.015 : -0.03) * size : -0.1,
      color: color ?? AppColors.ink,
    );
  }

  /// Raqam uslubi (veb: .today-value — Commissioner 800, −0.035em): KPI plitka, hero faktlari, muhim summalar.
  static TextStyle display({double size = 32, Color? color, FontWeight weight = FontWeight.w800}) => TextStyle(
        fontFamily: 'Commissioner',
        fontFamilyFallback: const <String>['Onest', 'Manrope'],
        fontSize: size,
        height: 1.0,
        fontWeight: weight,
        letterSpacing: -0.035 * size,
        color: color ?? AppColors.ink,
      );

  static FontWeight _weight(int value) {
    if (value >= 800) return FontWeight.w800;
    if (value >= 700) return FontWeight.w700;
    if (value >= 600) return FontWeight.w600;
    return FontWeight.w500;
  }

  /// Raqam uslubi: jadval raqamlari (tabular) — ustunlarda tekis turadi (Onest).
  static const List<FontFeature> tabular = <FontFeature>[FontFeature.tabularFigures()];
}

/// Sahifa o'tishi: iOS — Cupertino (chetdan surish), Android — gorizontal «shared axis» (siljish + so'nish).
/// Animatsiya darajasi «Kam» — faqat so'nish, «O'chiq» yoki qurilmada harakat kamaytirilgan — bir zumda.
class MotionPageTransitionsBuilder extends PageTransitionsBuilder {
  const MotionPageTransitionsBuilder();

  static const CupertinoPageTransitionsBuilder _cupertino = CupertinoPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    final level = motionLevelOf(AppColors.choice.motion, systemReduced: MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    if (level == MotionLevel.off) return child;
    if (level == MotionLevel.reduced) return FadeTransition(opacity: animation, child: child);
    final platform = Theme.of(context).platform;
    if (platform == TargetPlatform.iOS || platform == TargetPlatform.macOS) {
      return _cupertino.buildTransitions<T>(route, context, animation, secondaryAnimation, child);
    }
    return _SharedAxis(animation: animation, secondaryAnimation: secondaryAnimation, child: child);
  }
}

class _SharedAxis extends StatelessWidget {
  const _SharedAxis({required this.animation, required this.secondaryAnimation, required this.child});

  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final Widget child;

  static const Interval _fadeIn = Interval(0.3, 1, curve: Curves.easeOut);
  static const Interval _fadeOut = Interval(0, 0.35, curve: Curves.easeIn);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[animation, secondaryAnimation]),
      child: child,
      builder: (context, child) {
        final enter = Curves.easeOutCubic.transform(animation.value);
        final leave = Curves.easeInCubic.transform(secondaryAnimation.value);
        final dx = (1 - enter) * 30 - leave * 30;
        final opacity = (_fadeIn.transform(animation.value) * (1 - _fadeOut.transform(secondaryAnimation.value))).clamp(0.0, 1.0);
        return Opacity(opacity: opacity, child: Transform.translate(offset: Offset(dx, 0), child: child));
      },
    );
  }
}

ThemeData buildTheme() {
  final brightness = AppColors.dark ? Brightness.dark : Brightness.light;
  final choice = AppColors.choice;
  final scheme = ColorScheme.fromSeed(seedColor: AppColors.accent, brightness: brightness).copyWith(
    primary: AppColors.accent,
    onPrimary: Colors.white,
    secondary: AppColors.accentStrong,
    surface: AppColors.card,
    onSurface: AppColors.ink,
    onSurfaceVariant: AppColors.muted,
    outline: AppColors.lineStrong,
    outlineVariant: AppColors.line,
    error: AppColors.danger,
    surfaceContainerLowest: AppColors.card,
    surfaceContainerLow: AppColors.surface2,
    surfaceContainer: AppColors.surface2,
    surfaceContainerHigh: AppColors.raised,
    surfaceContainerHighest: AppColors.sunken,
    primaryContainer: AppColors.accentSoft,
    onPrimaryContainer: AppColors.accentStrong,
    secondaryContainer: AppColors.accentSoft2,
    onSecondaryContainer: AppColors.accentStrong,
  );
  final density = choice.densityFactor;
  final dense = choice.dense;
  final control = (46 * density).clamp(38, 54).toDouble();
  // Onest'da o'zbek ʻ va kirill Қ Ғ Ҳ yo'q — Commissioner'dan, strelkalar (→ ←) — Manrope'dan olinadi.
  const fallback = <String>['Commissioner', 'Manrope'];
  final family = choice.fontFamily;
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
    scaffoldBackgroundColor: AppColors.canvas,
    canvasColor: AppColors.canvas,
    fontFamily: family,
    fontFamilyFallback: fallback,
    visualDensity: dense ? VisualDensity.compact : VisualDensity.standard,
  );
  final text = base.textTheme;
  TextStyle? titled(TextStyle? style, double size) => style?.merge(AppTheme.title(size: size));
  const transitions = MotionPageTransitionsBuilder();
  return base.copyWith(
    textTheme: text.copyWith(
      headlineMedium: titled(text.headlineMedium, 26),
      headlineSmall: titled(text.headlineSmall, 22),
      titleLarge: titled(text.titleLarge, 19),
      bodyLarge: text.bodyLarge?.copyWith(color: AppColors.ink, height: 1.4),
      bodyMedium: text.bodyMedium?.copyWith(color: AppColors.ink, height: 1.4),
      bodySmall: text.bodySmall?.copyWith(color: AppColors.muted),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: <TargetPlatform, PageTransitionsBuilder>{
      TargetPlatform.android: transitions,
      TargetPlatform.iOS: transitions,
      TargetPlatform.macOS: transitions,
      TargetPlatform.fuchsia: transitions,
      TargetPlatform.linux: transitions,
      TargetPlatform.windows: transitions,
    }),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.chrome,
      foregroundColor: AppColors.onChrome,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      shape: Border(bottom: BorderSide(color: AppColors.line)),
      iconTheme: IconThemeData(color: AppColors.muted),
      actionsIconTheme: IconThemeData(color: AppColors.muted),
      titleTextStyle: AppTheme.title(size: dense ? 17 : 18.5, color: AppColors.onChrome),
    ),
    cardTheme: CardThemeData(color: AppColors.card, surfaceTintColor: Colors.transparent, elevation: 0),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.raised,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card + 4)),
      titleTextStyle: AppTheme.title(size: 20),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: AppColors.raised,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: AppColors.lineStrong,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet))),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: AppColors.accent,
      foregroundColor: Colors.white,
      elevation: 3,
      highlightElevation: 5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control + 6)),
      extendedTextStyle: TextStyle(fontFamily: family, fontFamilyFallback: fallback, fontWeight: FontWeight.w600, fontSize: 15),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.raised,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control), side: BorderSide(color: AppColors.line)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.card,
      isDense: dense,
      labelStyle: TextStyle(color: AppColors.muted),
      floatingLabelStyle: TextStyle(color: AppColors.accentStrong, fontWeight: FontWeight.w600),
      hintStyle: TextStyle(color: AppColors.subtle),
      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: (13 * density).clamp(9, 16).toDouble()),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.control), borderSide: BorderSide(color: AppColors.lineStrong)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.control), borderSide: BorderSide(color: AppColors.lineStrong)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.control), borderSide: BorderSide(color: AppColors.focus, width: 2)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.control), borderSide: BorderSide(color: AppColors.danger)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.line,
        minimumSize: Size(48, control),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
        // Shrift oilasi aniq: tugma matni aks holda tizim shriftiga (Roboto) tushib qoladi.
        textStyle: TextStyle(fontFamily: family, fontFamilyFallback: fallback, fontSize: 15.5, fontWeight: FontWeight.w600),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.card,
        foregroundColor: AppColors.ink,
        elevation: 0,
        minimumSize: Size(48, control),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control), side: BorderSide(color: AppColors.lineStrong)),
        textStyle: TextStyle(fontFamily: family, fontFamilyFallback: fallback, fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink,
        backgroundColor: AppColors.card,
        minimumSize: Size(48, control),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
        side: BorderSide(color: AppColors.lineStrong),
        textStyle: TextStyle(fontFamily: family, fontFamilyFallback: fallback, fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.accentStrong,
        minimumSize: const Size(48, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
        textStyle: TextStyle(fontFamily: family, fontFamilyFallback: fallback, fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: AppColors.card,
        selectedBackgroundColor: AppColors.accentSoft,
        selectedForegroundColor: AppColors.accentStrong,
        foregroundColor: AppColors.muted,
        side: BorderSide(color: AppColors.lineStrong),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
        textStyle: TextStyle(fontFamily: family, fontFamilyFallback: fallback, fontWeight: FontWeight.w600),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.navBg,
      height: dense ? 60 : 68,
      surfaceTintColor: Colors.transparent,
      indicatorColor: AppColors.navActiveBg,
      labelTextStyle: WidgetStateProperty.all(TextStyle(fontFamily: family, fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.navFg)),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: AppColors.navBg,
      indicatorColor: AppColors.navActiveBg,
      selectedIconTheme: IconThemeData(color: AppColors.navActiveFg),
      unselectedIconTheme: IconThemeData(color: AppColors.navFg),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: AppColors.card,
      selectedColor: AppColors.accentSoft,
      side: BorderSide(color: AppColors.line),
      labelStyle: TextStyle(fontFamily: family, fontFamilyFallback: fallback, fontWeight: FontWeight.w600, color: AppColors.ink, fontSize: 13.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.chip + 2)),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: AppColors.accentStrong,
      unselectedLabelColor: AppColors.muted,
      indicatorColor: AppColors.accent,
      indicatorSize: TabBarIndicatorSize.label,
      labelStyle: TextStyle(fontFamily: family, fontFamilyFallback: fallback, fontWeight: FontWeight.w700),
      unselectedLabelStyle: TextStyle(fontFamily: family, fontFamilyFallback: fallback, fontWeight: FontWeight.w600),
      dividerColor: AppColors.line,
    ),
    dividerTheme: DividerThemeData(color: AppColors.line, space: 1, thickness: 1),
    listTileTheme: ListTileThemeData(
      iconColor: AppColors.muted,
      textColor: AppColors.ink,
      minVerticalPadding: (10 * density).clamp(6, 14).toDouble(),
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.l),
      subtitleTextStyle: TextStyle(fontFamily: family, fontFamilyFallback: fallback, color: AppColors.muted, fontSize: 13.5),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? Colors.white : AppColors.lineStrong),
      trackColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? AppColors.accent : AppColors.sunken),
      trackOutlineColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? AppColors.accent : AppColors.lineStrong),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: AppColors.accent,
      linearTrackColor: AppColors.accentSoft2,
      refreshBackgroundColor: AppColors.raised,
    ),
    // Kattaroq bosish maydoni (kamida 48×48)
    materialTapTargetSize: MaterialTapTargetSize.padded,
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(minimumSize: Size(control, control))),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.raised,
      contentTextStyle: TextStyle(fontFamily: family, fontFamilyFallback: fallback, color: AppColors.ink, fontSize: 14.5),
      actionTextColor: AppColors.accentStrong,
      elevation: 6,
      insetPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control), side: BorderSide(color: AppColors.line)),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: AppColors.dark ? AppColors.raised : AppColors.ink, borderRadius: BorderRadius.circular(AppRadius.chip)),
      textStyle: TextStyle(fontFamily: family, color: AppColors.dark ? AppColors.ink : Colors.white, fontSize: 12.5),
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
/// och fonda to'qlashtiriladi (rang tusi saqlanadi). Toza mantiq — test/theme_contrast_test.dart.
Color readableOn(Color color, Color background, {double min = 4.5}) {
  if (contrastRatio(color, background) >= min) return color;
  final target = background.computeLuminance() < 0.5 ? Colors.white : Colors.black;
  for (var step = 1; step <= 20; step++) {
    final candidate = Color.lerp(color, target, step / 20)!;
    if (contrastRatio(candidate, background) >= min) return candidate;
  }
  return target;
}
