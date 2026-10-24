// EduX ko'rinishi v2 (3.8, veb 1.40 «Daftar 2: hoshiya», docs/design.md «Rang qiymatlari (mobil ilova uchun)»):
// 9 shablon × yorug'/tungi palitra (aniq hex qiymatlar), 12 asosiy rang shkalasi (50/100/300/500/600/700), holat ranglari,
// semantik tokenlar (canvas/surface/surface2/raised, ink/muted/subtle, line/lineStrong, focus), menyu paneli ranglari.
//
// AppColors dagi ranglar joriy mavzuga qarab o'zgaradi: AppTheme.apply() ularni MaterialApp qurilishidan oldin yangilaydi,
// ilova esa yangi kalit bilan to'liq qayta chiziladi. Rang faqat ma'no uchun: asosiy rang — harakat, qizil — qarz/xato,
// sariq — kutilmoqda, yashil — bajarildi. Esda qoladigan yagona narsa — hoshiya (chap chetdagi rangli chiziq, [AppSpacing.hoshiya]).
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'design.dart';

/// Asosiy rang shkalasi (veb: palette.css, docs/design.md jadvali).
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

  /// Asosiy to'liq rang (tugma, faol band) — 600 (oq matn bilan ≥ 4.5:1).
  Color get from => c600;
}

const List<Accent> accents = <Accent>[
  Accent('blue', 'Moviy', Color(0xFFEEF4FF), Color(0xFFDCE8FF), Color(0xFF8DB4FF), Color(0xFF3478FF), Color(0xFF1F63F5), Color(0xFF1650D4)),
  Accent('indigo', 'Indigo', Color(0xFFEEF2FF), Color(0xFFE0E7FF), Color(0xFFA3B3FF), Color(0xFF615FFF), Color(0xFF4F39F6), Color(0xFF432DD7)),
  Accent('violet', 'Binafsha', Color(0xFFF5F3FF), Color(0xFFEDE9FE), Color(0xFFC4B4FF), Color(0xFF8E51FF), Color(0xFF7F22FE), Color(0xFF7008E7)),
  Accent('plum', "Olxo'ri", Color(0xFFFDF4FF), Color(0xFFFAE8FF), Color(0xFFF4A8FF), Color(0xFFC800DE), Color(0xFFA800B7), Color(0xFF8A0194)),
  Accent('rose', 'Anor', Color(0xFFFFF1F2), Color(0xFFFFE4E6), Color(0xFFFFA1AD), Color(0xFFFF2056), Color(0xFFEC003F), Color(0xFFC70036)),
  Accent('sunset', 'Shafaq', Color(0xFFFFF7ED), Color(0xFFFFEDD4), Color(0xFFFFB86A), Color(0xFFF54A00), Color(0xFFCA3500), Color(0xFF9F2D00)),
  Accent('amber', 'Qahrabo', Color(0xFFFFFBEB), Color(0xFFFEF3C6), Color(0xFFFFD230), Color(0xFFE17100), Color(0xFFBB4D00), Color(0xFF973C00)),
  Accent('forest', "O'rmon", Color(0xFFF0FDF4), Color(0xFFDBFCE7), Color(0xFF7BF1A8), Color(0xFF00A63E), Color(0xFF008236), Color(0xFF016630)),
  Accent('emerald', 'Zumrad', Color(0xFFECFDF5), Color(0xFFD0FAE5), Color(0xFF5EE9B5), Color(0xFF009966), Color(0xFF007A55), Color(0xFF006045)),
  Accent('teal', 'Feruza', Color(0xFFECFEFF), Color(0xFFCEFAFE), Color(0xFF53EAFD), Color(0xFF0092B8), Color(0xFF007595), Color(0xFF005F78)),
  Accent('sky', 'Osmon', Color(0xFFF0F9FF), Color(0xFFDFF2FE), Color(0xFF74D4FF), Color(0xFF0084D1), Color(0xFF0069A8), Color(0xFF00598A)),
  Accent('slate', 'Grafit', Color(0xFFF8FAFC), Color(0xFFF1F5F9), Color(0xFFCAD5E2), Color(0xFF62748E), Color(0xFF45556C), Color(0xFF314158)),
];

Accent accentOf(String? key) => accents.firstWhere((item) => item.key == key, orElse: () => accents.first);

/// Shablon palitrasi (asosiy rang — Moviy bo'lganda hisoblangan qiymatlar, docs/design.md).
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
    );

/// docs/design.md «Rang qiymatlari (mobil ilova uchun)»: shablon → [yorug', tungi].
/// Tartib: canvas, surface, surface-2, raised, text-1, text-2, text-3, border, border-strong, sidebar-bg, sidebar-fg,
/// sidebar-active-bg, sidebar-active-fg.
final Map<String, List<TemplatePalette>> templatePalettes = <String, List<TemplatePalette>>{
  'classic': <TemplatePalette>[
    _p(<int>[0xf5f7fb, 0xffffff, 0xf8f9fc, 0xffffff, 0x131c36, 0x4f5a73, 0x586379, 0xe2e8f2, 0xcbd3e1, 0xffffff, 0x3b4560, 0xeef4ff, 0x1650d4]),
    _p(<int>[0x0b1222, 0x121a2c, 0x162036, 0x182238, 0xeef1f6, 0xa6afc3, 0x98a2b8, 0x243049, 0x334160, 0x0f1727, 0xc4cbd9, 0x162545, 0x8db4ff]),
  ],
  'soft': <TemplatePalette>[
    _p(<int>[0xeef3fd, 0xffffff, 0xf6f9ff, 0xffffff, 0x131c36, 0x4f5a73, 0x586379, 0xe2e8f2, 0xcbd3e1, 0xf6f9ff, 0x3b4560, 0x1f63f5, 0xffffff]),
    _p(<int>[0x0d1426, 0x121a2c, 0x172138, 0x182238, 0xeef1f6, 0xa6afc3, 0x98a2b8, 0x243049, 0x334160, 0x111a2e, 0xc4cbd9, 0x1f63f5, 0xffffff]),
  ],
  'night': <TemplatePalette>[
    _p(<int>[0xf5f7fb, 0xffffff, 0xf8f9fc, 0xffffff, 0x131c36, 0x4f5a73, 0x586379, 0xe2e8f2, 0xcbd3e1, 0x111a2e, 0xc9d1e0, 0x1f63f5, 0xffffff]),
    _p(<int>[0x0b1222, 0x121a2c, 0x162036, 0x182238, 0xeef1f6, 0xa6afc3, 0x98a2b8, 0x243049, 0x334160, 0x070c18, 0xc9d1e0, 0x1f63f5, 0xffffff]),
  ],
  'compact': <TemplatePalette>[
    _p(<int>[0xf5f7fb, 0xffffff, 0xf8f9fc, 0xffffff, 0x131c36, 0x4f5a73, 0x586379, 0xe2e8f2, 0xcbd3e1, 0xffffff, 0x3b4560, 0xeef4ff, 0x1650d4]),
    _p(<int>[0x0b1222, 0x121a2c, 0x162036, 0x182238, 0xeef1f6, 0xa6afc3, 0x98a2b8, 0x243049, 0x334160, 0x0f1727, 0xc4cbd9, 0x162545, 0x8db4ff]),
  ],
  'school': <TemplatePalette>[
    _p(<int>[0xfbf7f1, 0xffffff, 0xfdfaf5, 0xffffff, 0x131c36, 0x4f5a73, 0x586379, 0xe9e1d4, 0xd8ccb9, 0xfffdf9, 0x3b4560, 0xdfebff, 0x2a2216]),
    _p(<int>[0x13110e, 0x1b1814, 0x211d18, 0x221e19, 0xeef1f6, 0xa6afc3, 0x98a2b8, 0x322c24, 0x463e33, 0x17140f, 0xc4cbd9, 0x1f2a40, 0xf4efe6]),
  ],
  'paper': <TemplatePalette>[
    _p(<int>[0xeeece4, 0xfbfaf6, 0xf4f2eb, 0xfbfaf6, 0x1f1b16, 0x5d5952, 0x68645d, 0xddd8cb, 0xc7c0ae, 0xf5f3ec, 0x47433d, 0xe5ecf8, 0x1650d4]),
    _p(<int>[0x15130f, 0x1e1b16, 0x24211b, 0x26231d, 0xf3eee6, 0xb3afa7, 0xa5a199, 0x36322a, 0x4a453a, 0x1a1813, 0xcfcac2, 0x212b3e, 0xf1ece1]),
  ],
  'ocean': <TemplatePalette>[
    _p(<int>[0xedf3f6, 0xffffff, 0xf4f8fa, 0xffffff, 0x0b1e27, 0x485d67, 0x536872, 0xd3e1e9, 0xb5c8d4, 0xf6fafc, 0x334750, 0xeef4ff, 0x1650d4]),
    _p(<int>[0x08151c, 0x0f2029, 0x132731, 0x152b36, 0xe8f2f7, 0x9eb3be, 0x8fa6b0, 0x1e3540, 0x2b4755, 0x0b1a22, 0xbbced7, 0x162545, 0x8db4ff]),
  ],
  'graphite': <TemplatePalette>[
    _p(<int>[0xffffff, 0xffffff, 0xf4f5f7, 0xffffff, 0x111418, 0x33353b, 0x45484d, 0xb9c0cc, 0x8a93a3, 0x1f232b, 0xe6e8ec, 0x1f63f5, 0xffffff]),
    _p(<int>[0x0e1014, 0x15181e, 0x1b1f26, 0x1d2128, 0xf4f5f8, 0xd2d4d8, 0xb4b7bd, 0x3a404c, 0x59616f, 0x0a0c0f, 0xe6e8ec, 0x1f63f5, 0xffffff]),
  ],
  'spring': <TemplatePalette>[
    _p(<int>[0xf2f7ea, 0xffffff, 0xf7fbf2, 0xffffff, 0x171e14, 0x545c50, 0x5f685b, 0xdce7cf, 0xbfd0ad, 0xffffff, 0x3f463b, 0xdbe8ff, 0x1f2a1a]),
    _p(<int>[0x0e140b, 0x161e12, 0x1b2416, 0x1d2718, 0xedf2eb, 0xaab3a6, 0x9ca597, 0x2a3623, 0x3c4b33, 0x12190f, 0xc6cdc2, 0x182f3f, 0xeef5e6]),
  ],
};

/// Faol menyu bandi foni boshqa asosiy ranglarda: menyu foni va asosiy rang aralashmasi (Moviy jadvalidan olingan ulush).
const Map<String, List<double>> _activeMix = <String, List<double>>{
  'classic': <double>[0.07, 0.15],
  'compact': <double>[0.07, 0.15],
  'school': <double>[0.13, 0.22],
  'paper': <double>[0.07, 0.20],
  'ocean': <double>[0.04, 0.17],
  'spring': <double>[0.16, 0.22],
};

/// Holat ranglari (docs/design.md): [fg, bg] yorug' va tungi rejimda.
class StatusColors {
  const StatusColors(this.fg, this.bg);

  final Color fg;
  final Color bg;
}

class AppColors {
  AppColors._();

  static const Color sun = Color(0xFFFFC233);

  /// Daftar hoshiyasi (kirish paneli, «daftar varag'i»): qizil chiziq — veb landing `--lp-margin`.
  static const Color margin = Color(0xFFD7414A);

  // Ma'no ranglari (matn, ikonka): docs/design.md «Holat» jadvali — yorug'da to'q, tungi rejimda och.
  static Color success = const Color(0xFF007A55);
  static Color warning = const Color(0xFFBB4D00);
  static Color danger = const Color(0xFFC70036);
  static Color info = const Color(0xFF0069A8);
  static Color successBg = const Color(0xFFECFDF5);
  static Color warningBg = const Color(0xFFFFFBEB);
  static Color dangerBg = const Color(0xFFFFF1F2);
  static Color infoBg = const Color(0xFFF0F9FF);

  /// Oq matnli to'liq fon (nishon, xato xabari, «Jonli» belgisi, xavfli tugma) — ikkala rejimda bir xil, oq bilan ≥ 4.5.
  static const Color successFill = Color(0xFF007A55);
  static const Color warningFill = Color(0xFFBB4D00);
  static const Color dangerFill = Color(0xFFC70036);

  /// Asosiy rang ustidagi matn (tugma): odatda oq.
  static Color onBrand = Colors.white;

  /// Matn va ikonka uchun asosiy rang (yorug'da 600, tungi rejimda 300 — sirtda ≥ 4.5:1).
  static Color brand = const Color(0xFF1F63F5);

  /// To'liq asosiy rang (tugma, faol band, hoshiya) — 600.
  static Color accent = const Color(0xFF1F63F5);

  /// Asosiy rangning matn tusi (`--accent-strong`): yorug'da 700, tungi rejimda 300.
  static Color accentStrong = const Color(0xFF1650D4);

  /// Asosiy rangning yumshoq foni (`--accent-soft`, `--accent-soft-2`).
  static Color accentSoft = const Color(0xFFEEF4FF);
  static Color accentSoft2 = const Color(0xFFDCE8FF);

  /// Asosiy rangning eng to'q tusi: kirish paneli, sertifikat va yutuqlar banneri (gradient o'rnida).
  static Color panel = const Color(0xFF0D2C78);
  static Color brandDark = const Color(0xFF1650D4);

  // Sirtlar va matn (semantik tokenlar).
  static Color canvas = const Color(0xFFF5F7FB);
  static Color surface = const Color(0xFFF5F7FB); // = canvas (eski nom: sahifa foni)
  static Color card = Colors.white; // = surface (karta)
  static Color surface2 = const Color(0xFFF8F9FC);
  static Color raised = Colors.white;
  static Color sunken = const Color(0xFFF0F3F8);
  static Color ink = const Color(0xFF131C36);
  static Color muted = const Color(0xFF4F5A73);
  static Color subtle = const Color(0xFF586379);
  static Color line = const Color(0xFFE2E8F2);
  static Color lineStrong = const Color(0xFFCBD3E1);
  static Color focus = const Color(0xFF1F63F5);
  static bool dark = false;

  /// Karta chegarasi (Soyali/Tekis kartada — shaffof) va soyasi.
  static Color cardBorder = const Color(0xFFE2E8F2);
  static List<BoxShadow> cardShadow = const <BoxShadow>[];

  /// Sarlavha paneli (AppBar) va uning matni.
  static Color chrome = Colors.white;
  static Color onChrome = const Color(0xFF131C36);

  /// Menyu paneli (pastki menyu, iPad yon menyusi): fon, matn, faol band.
  static Color navBg = Colors.white;
  static Color navFg = const Color(0xFF3B4560);
  static Color navActiveBg = const Color(0xFFEEF4FF);
  static Color navActiveFg = const Color(0xFF1650D4);
  static Color navLine = const Color(0xFFE2E8F2);
  static bool navDark = false;

  /// Hoshiya ohanglari (veb: danger-fg, amber-500, emerald-500).
  static Color toneDanger = const Color(0xFFC70036);
  static Color toneWarning = const Color(0xFFFE9A00);
  static Color toneSuccess = const Color(0xFF00BC7D);

  /// Joriy ko'rinish (shablon, shrift, burchak ...).
  static ThemeChoice choice = const ThemeChoice();

  /// Plitka ranglari (veb: tile-blue … tile-rose): [fg, bg]. Avatar va belgi plitkalari.
  static List<StatusColors> tiles = const <StatusColors>[];

  /// Ma'no rangining yumshoq foni (ogohlantirish, xato, faol band ...): holat ranglari uchun — jadvaldagi aniq fon.
  static Color soft(Color color) {
    if (color == success) return successBg;
    if (color == warning) return warningBg;
    if (color == danger) return dangerBg;
    if (color == info) return infoBg;
    if (color == brand || color == accent) return accentSoft;
    return Color.alphaBlend(color.withAlpha(dark ? 46 : 22), card);
  }

  /// Ismdan barqaror plitka rangi (Avatar).
  static StatusColors tileFor(String name) => tiles.isEmpty ? StatusColors(brand, accentSoft) : tiles[stableIndex(name, tiles.length)];
}

/// Bir xil oraliqlar (4px qadam) va hoshiya qalinligi.
class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 24;

  /// Daftar hoshiyasi (veb: --hoshiya 4px).
  static const double hoshiya = 4;
}

class AppRadius {
  AppRadius._();

  /// Karta va boshqaruv burchagi shablon va foydalanuvchi tanloviga ko'paytiriladi (AppTheme.apply).
  static double card = 14;
  static double control = 10;
  static double chip = 6;
  static const double sheet = 22;
}

/// Harakat davomiyliklari (veb: --dur-1/2/3).
class AppDurations {
  AppDurations._();

  static const Duration d1 = Duration(milliseconds: 120);
  static const Duration d2 = Duration(milliseconds: 180);
  static const Duration d3 = Duration(milliseconds: 260);
}

class AppTheme {
  AppTheme._();

  static void apply({required bool dark, required Accent accent, ThemeChoice choice = const ThemeChoice()}) {
    AppColors.dark = dark;
    AppColors.choice = choice;
    final template = templatePalettes.containsKey(choice.template) ? choice.template : 'classic';
    final palette = templatePalettes[template]![dark ? 1 : 0];
    final blue = accent.key == 'blue';

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
    // Yumshoq shablon: tuman foni asosiy rangdan (veb: asosiy rang 34% + #F7F8FC).
    if (template == 'soft' && !dark && !blue) {
      AppColors.canvas = Color.lerp(const Color(0xFFF7F8FC), accent.c600, 0.045)!;
      AppColors.surface2 = Color.lerp(Colors.white, accent.c600, 0.035)!;
      AppColors.navBg = AppColors.surface2;
    }
    AppColors.surface = AppColors.canvas;
    AppColors.sunken = Color.lerp(AppColors.canvas, dark ? Colors.black : AppColors.lineStrong, dark ? 0.25 : 0.18)!;

    // Asosiy rang.
    AppColors.accent = accent.c600;
    AppColors.accentStrong = dark ? accent.c300 : accent.c700;
    AppColors.brand = readableOn(dark ? accent.c300 : accent.c600, palette.surface);
    AppColors.brandDark = accent.c700;
    AppColors.accentSoft = dark ? Color.lerp(palette.surface, accent.c500, 0.16)! : accent.c50;
    AppColors.accentSoft2 = dark ? Color.lerp(palette.surface, accent.c500, 0.26)! : accent.c100;
    AppColors.panel = Color.lerp(accent.c700, Colors.black, 0.42)!;
    AppColors.focus = dark ? accent.c300 : accent.c600;
    AppColors.onBrand = contrastRatio(Colors.white, AppColors.brand) >= 4.5 ? Colors.white : palette.canvas;

    // Menyu: faol band (Yumshoq, Qorong'i panel, Grafit — to'liq asosiy rang, oq matn).
    final filledActive = template == 'soft' || template == 'night' || template == 'graphite';
    if (filledActive) {
      AppColors.navActiveBg = accent.c600;
      AppColors.navActiveFg = Colors.white;
    } else {
      AppColors.navActiveBg = blue ? palette.sidebarActiveBg : Color.lerp(palette.sidebarBg, accent.c600, _activeMix[template]![dark ? 1 : 0])!;
      switch (template) {
        case 'school':
        case 'spring':
          AppColors.navActiveFg = palette.sidebarActiveFg;
        case 'paper':
          AppColors.navActiveFg = dark ? palette.sidebarActiveFg : accent.c700;
        default:
          AppColors.navActiveFg = dark ? accent.c300 : accent.c700;
      }
    }
    AppColors.navDark = palette.sidebarBg.computeLuminance() < 0.2;
    AppColors.navLine = AppColors.navDark && !dark ? palette.sidebarBg : palette.border;

    // Holat ranglari (jadval).
    if (dark) {
      AppColors.success = const Color(0xFF5EE9B5);
      AppColors.successBg = const Color(0xFF142D38);
      AppColors.warning = const Color(0xFFFFD230);
      AppColors.warningBg = const Color(0xFF2C2B31);
      AppColors.danger = const Color(0xFFFFA1AD);
      AppColors.dangerBg = const Color(0xFF2F2234);
      AppColors.info = const Color(0xFF74D4FF);
      AppColors.infoBg = const Color(0xFF142A43);
      AppColors.toneDanger = const Color(0xFFFF637E);
      AppColors.toneWarning = const Color(0xFFFFB900);
      AppColors.toneSuccess = const Color(0xFF00D492);
    } else {
      AppColors.success = const Color(0xFF007A55);
      AppColors.successBg = const Color(0xFFECFDF5);
      AppColors.warning = const Color(0xFFBB4D00);
      AppColors.warningBg = const Color(0xFFFFFBEB);
      AppColors.danger = const Color(0xFFC70036);
      AppColors.dangerBg = const Color(0xFFFFF1F2);
      AppColors.info = const Color(0xFF0069A8);
      AppColors.infoBg = const Color(0xFFF0F9FF);
      AppColors.toneDanger = const Color(0xFFC70036);
      AppColors.toneWarning = const Color(0xFFFE9A00);
      AppColors.toneSuccess = const Color(0xFF00BC7D);
    }
    // Tungi sirtda holat foni jadvaldagi qiymat; ba'zi shablonlarda karta foni boshqacha — o'qilishini kafolatlaymiz.
    AppColors.success = readableOn(AppColors.success, AppColors.card);
    AppColors.warning = readableOn(AppColors.warning, AppColors.card);
    AppColors.danger = readableOn(AppColors.danger, AppColors.card);

    // Plitkalar (veb: tile-blue … tile-rose; tile-blue — asosiy rang).
    StatusColors tile(Color light, Color lightBg, Color darkFg) =>
        dark ? StatusColors(darkFg, Color.alphaBlend(darkFg.withAlpha(34), palette.surface)) : StatusColors(light, lightBg);
    AppColors.tiles = <StatusColors>[
      tile(accent.c700, accent.c50, accent.c300),
      tile(const Color(0xFF7008E7), const Color(0xFFF5F3FF), const Color(0xFFC4B4FF)),
      tile(const Color(0xFF007595), const Color(0xFFECFEFF), const Color(0xFF53EAFD)),
      tile(const Color(0xFF007A55), const Color(0xFFECFDF5), const Color(0xFF5EE9B5)),
      tile(const Color(0xFF973C00), const Color(0xFFFFFBEB), const Color(0xFFFFD230)),
      tile(const Color(0xFFC70036), const Color(0xFFFFF1F2), const Color(0xFFFFA1AD)),
    ];

    // Burchaklar.
    final k = choice.radiusFactor;
    AppRadius.card = (14 * k).clamp(4, 26).toDouble();
    AppRadius.control = (10 * k).clamp(4, 22).toDouble();
    AppRadius.chip = (6 * k).clamp(3, 14).toDouble();

    // Karta uslubi: chegarali (yengil soya), soyali (chegarasiz), tekis (fon bilan ajraladi).
    switch (choice.effectiveCards) {
      case 'shadow':
        AppColors.cardBorder = dark ? palette.border : Colors.transparent;
        if (dark) {
          AppColors.cardShadow = const <BoxShadow>[BoxShadow(color: Color(0x99000000), blurRadius: 24, offset: Offset(0, 10), spreadRadius: -14)];
        } else if (template == 'spring') {
          // «Stiker»: qattiq, siljigan soya.
          AppColors.cardShadow = <BoxShadow>[BoxShadow(color: palette.borderStrong, offset: const Offset(0, 3))];
        } else {
          AppColors.cardShadow = <BoxShadow>[
            const BoxShadow(color: Color(0x0A101828), blurRadius: 2, offset: Offset(0, 1)),
            BoxShadow(color: accent.c600.withAlpha(46), blurRadius: 26, offset: const Offset(0, 10), spreadRadius: -14),
          ];
        }
      case 'flat':
        AppColors.cardBorder = dark ? palette.border.withAlpha(140) : Colors.transparent;
        AppColors.cardShadow = const <BoxShadow>[];
      default:
        AppColors.cardBorder = palette.border;
        AppColors.cardShadow = dark || template == 'graphite' || template == 'compact'
            ? const <BoxShadow>[]
            : const <BoxShadow>[BoxShadow(color: Color(0x0A101828), blurRadius: 2, offset: Offset(0, 1))];
    }

    // Sarlavha paneli: karta rangida, matn — siyoh.
    AppColors.chrome = palette.surface;
    AppColors.onChrome = palette.text1;
  }

  /// Sarlavha uslubi (veb: --font-title, --title-weight, --title-tracking).
  static TextStyle title({double size = 22, Color? color, FontWeight? weight}) {
    final choice = AppColors.choice;
    final serif = choice.serifTitles;
    return TextStyle(
      fontFamily: choice.titleFamily,
      fontFamilyFallback: const <String>['GolosText', 'Onest'],
      fontSize: size,
      height: serif ? 1.18 : 1.15,
      fontWeight: weight ?? _weight(choice.titleWeight),
      letterSpacing: size >= 20 ? (serif ? -0.022 * size : -0.012 * size) : (serif ? -0.1 : 0),
      color: color ?? AppColors.ink,
    );
  }

  static FontWeight _weight(int value) {
    if (value >= 800) return FontWeight.w800;
    if (value >= 700) return FontWeight.w700;
    if (value >= 600) return FontWeight.w600;
    return FontWeight.w500;
  }

  /// Raqam uslubi: jadval raqamlari (tabular) — ustunlarda tekis turadi.
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
  const fallback = <String>['Onest'];
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
