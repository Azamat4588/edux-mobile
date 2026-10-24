// Dizayn tizimi v2 (veb 1.40 «Daftar 2: hoshiya», docs/design.md): rejim, 12 asosiy rang, 9 shablon, shrift, o'lcham,
// burchaklar, ikonalar, zichlik, karta uslubi, menyu uslubi, fon naqshi va animatsiya darajasi.
//
// Uch qatlam (pastdagisi ustidagini bosadi): platforma standarti (GET /site → theme.defaults) → tashkilot brendi
// (GET /context → theme) → shaxsiy tanlov (GET /me → user.appearance). Server qatlamlarni ruxsatga qarab o'zi tozalaydi
// (Theme::organization / Theme::user), ilova faqat birlashtiradi. Eski qiymatlar: vivid → school, midnight → night.
// «auto» (Shablonga qarab) — shablonning o'z tanlovi (templateDefaults, server: Theme::TEMPLATE_DEFAULTS).
//
// Mobil ilovaga xos: rejim standarti — «Qurilmaga qarab»; asosiy shrift — Golos Text (platforma standarti o'zgartirilmagan,
// ya'ni «onest» bo'lsa ham). Tashkilot yoki foydalanuvchi boshqa shrift tanlagan bo'lsa — o'sha.
//
// Bu fayl toza mantiq (Flutter vidjetlarisiz) — test/design_test.dart shu funksiyalarni tekshiradi.

/// Har maydon uchun ruxsat etilgan qiymatlar (server: Theme::OPTIONS).
const Map<String, List<String>> themeOptions = <String, List<String>>{
  'mode': <String>['light', 'dark', 'system'],
  'accent': <String>['blue', 'indigo', 'violet', 'plum', 'rose', 'sunset', 'amber', 'forest', 'emerald', 'teal', 'sky', 'slate'],
  'template': <String>['classic', 'soft', 'night', 'compact', 'school', 'paper', 'ocean', 'graphite', 'spring'],
  'font': <String>['onest', 'manrope', 'nunito', 'golos'],
  'size': <String>['sm', 'md', 'lg', 'xl'],
  'radius': <String>['sharp', 'rounded', 'pill'],
  'icons': <String>['color', 'mono'],
  'density': <String>['auto', 'comfy', 'normal', 'compact'],
  'cards': <String>['auto', 'bordered', 'shadow', 'flat'],
  'sidebar': <String>['auto', 'full', 'icons', 'floating'],
  'pattern': <String>['auto', 'none', 'dots', 'lines'],
  'motion': <String>['full', 'reduced', 'off'],
};

/// Standart qiymatlar (server: Theme::DEFAULTS). Mobil ilovada rejim standarti — «Qurilmaga qarab», shrift — Golos.
const Map<String, String> themeDefaults = <String, String>{
  'mode': 'system',
  'accent': 'blue',
  'template': 'classic',
  'font': 'golos',
  'size': 'md',
  'radius': 'rounded',
  'icons': 'color',
  'density': 'auto',
  'cards': 'auto',
  'sidebar': 'auto',
  'pattern': 'auto',
  'motion': 'full',
};

/// Shablonning «auto» qiymatlari (server: Theme::TEMPLATE_DEFAULTS, veb: lib/theme.js TEMPLATES[].defaults).
const Map<String, Map<String, String>> templateDefaults = <String, Map<String, String>>{
  'classic': <String, String>{'density': 'normal', 'cards': 'bordered', 'sidebar': 'full', 'pattern': 'none'},
  'soft': <String, String>{'density': 'comfy', 'cards': 'shadow', 'sidebar': 'floating', 'pattern': 'none'},
  'night': <String, String>{'density': 'normal', 'cards': 'bordered', 'sidebar': 'full', 'pattern': 'none'},
  'compact': <String, String>{'density': 'compact', 'cards': 'bordered', 'sidebar': 'full', 'pattern': 'none'},
  'school': <String, String>{'density': 'normal', 'cards': 'bordered', 'sidebar': 'full', 'pattern': 'none'},
  'paper': <String, String>{'density': 'normal', 'cards': 'bordered', 'sidebar': 'full', 'pattern': 'none'},
  'ocean': <String, String>{'density': 'normal', 'cards': 'flat', 'sidebar': 'full', 'pattern': 'none'},
  'graphite': <String, String>{'density': 'normal', 'cards': 'bordered', 'sidebar': 'full', 'pattern': 'none'},
  'spring': <String, String>{'density': 'comfy', 'cards': 'shadow', 'sidebar': 'full', 'pattern': 'dots'},
};

/// Eski qiymat → yangi (1.35 gacha).
const Map<String, Map<String, String>> themeLegacy = <String, Map<String, String>>{
  'template': <String, String>{'vivid': 'school', 'midnight': 'night'},
};

/// Shablon va boshqa variantlar nomlari (tanlash panelida, tarjima kaliti — o'zbekcha matn).
const Map<String, String> templateLabels = <String, String>{
  'classic': 'Klassik',
  'soft': 'Yumshoq',
  'night': "Qorong'i panel",
  'compact': 'Ixcham',
  'school': 'Maktab',
  'paper': "Qog'oz",
  'ocean': 'Okean',
  'graphite': 'Grafit',
  'spring': 'Bahor',
};

/// Shablon kimga mos (Ko'rinish ekranida izoh).
const Map<String, String> templateHints = <String, String>{
  'classic': 'Kundalik ish uchun',
  'soft': "Ota-onalar va o'quvchilar uchun",
  'night': "To'q menyu, uzoq ishlaganda",
  'compact': 'Kassir va administrator uchun',
  'school': "Iliq qog'oz, katak daftar",
  'paper': "Ko'p o'qiladigan darslar uchun",
  'ocean': "Zamonaviy o'quv markazi",
  'graphite': 'Direktor va hisobotlar',
  'spring': 'Bolalar markazi',
};
const Map<String, String> fontLabels = <String, String>{'golos': 'Golos Text', 'onest': 'Onest', 'manrope': 'Manrope', 'nunito': 'Nunito'};
const Map<String, String> sizeLabels = <String, String>{'sm': 'Kichik', 'md': "O'rta", 'lg': 'Katta', 'xl': 'Juda katta'};
const Map<String, String> radiusLabels = <String, String>{'sharp': 'Tik', 'rounded': 'Yumaloq', 'pill': 'Juda yumaloq'};
const Map<String, String> iconsLabels = <String, String>{'color': 'Rangli', 'mono': 'Bir rangli'};
const Map<String, String> densityLabels = <String, String>{'auto': 'Shablonga qarab', 'comfy': 'Qulay', 'normal': 'Odatiy', 'compact': 'Ixcham'};
const Map<String, String> cardsLabels = <String, String>{'auto': 'Shablonga qarab', 'bordered': 'Chegarali', 'shadow': 'Soyali', 'flat': 'Tekis'};
const Map<String, String> patternLabels = <String, String>{'auto': 'Shablonga qarab', 'none': "Yo'q", 'dots': 'Nuqtali', 'lines': 'Chiziqli'};
const Map<String, String> motionLabels = <String, String>{'full': "To'liq", 'reduced': 'Kam', 'off': "O'chiq"};
const Map<String, String> modeLabels = <String, String>{'light': 'Kunduzgi', 'dark': 'Tungi', 'system': 'Qurilmaga qarab'};

/// Har doim shaxsiy maydonlar (server: Theme::PERSONAL_FIELDS) — platforma ruxsatisiz ham o'zgartiriladi.
const List<String> personalThemeFields = <String>['mode', 'size', 'motion'];

/// Qiymatni tekshiradi: eski qiymat yangisiga o'giriladi, noma'lum qiymat — null.
String? normalizeThemeValue(String field, Object? value) {
  if (value == null) return null;
  var text = value.toString().trim();
  if (text.isEmpty) return null;
  text = themeLegacy[field]?[text] ?? text;
  return (themeOptions[field] ?? const <String>[]).contains(text) ? text : null;
}

/// Animatsiya darajasi (qurilmadagi «harakatni kamaytirish» bilan birga hisoblanadi — lib/core/motion.dart).
enum MotionLevel { full, reduced, off }

MotionLevel motionLevelOf(String value, {bool systemReduced = false}) {
  if (value == 'off') return MotionLevel.off;
  // Qurilmada harakat kamaytirilgan: o'tishlar bir zumda, sanash yo'q (veb: motionLevel() → reduced).
  if (systemReduced) return MotionLevel.off;
  return value == 'reduced' ? MotionLevel.reduced : MotionLevel.full;
}

/// Birlashtirilgan ko'rinish.
class ThemeChoice {
  const ThemeChoice({
    this.mode = 'system',
    this.accent = 'blue',
    this.template = 'classic',
    this.font = 'golos',
    this.size = 'md',
    this.radius = 'rounded',
    this.icons = 'color',
    this.density = 'auto',
    this.cards = 'auto',
    this.sidebar = 'auto',
    this.pattern = 'auto',
    this.motion = 'full',
  });

  final String mode;
  final String accent;
  final String template;
  final String font;
  final String size;
  final String radius;
  final String icons;
  final String density;
  final String cards;
  final String sidebar;
  final String pattern;
  final String motion;

  /// Qatlamlarni birlashtirish: [layers] — pastdan yuqoriga (platforma, tashkilot, shaxsiy).
  /// [mode] uchun alohida: shaxsiy → [cachedMode] (telefonda oxirgi tanlangan) → platforma standarti.
  factory ThemeChoice.resolve(List<Map<String, dynamic>> layers, {String? cachedMode}) {
    final values = Map<String, String>.from(themeDefaults);
    for (var i = 0; i < layers.length; i++) {
      final layer = layers[i];
      for (final field in themeOptions.keys) {
        if (field == 'mode') continue;
        final value = normalizeThemeValue(field, layer[field]);
        if (value == null) continue;
        // Platforma standartidagi «onest» — serverning o'zgartirilmagan standarti: mobilda Golos qoladi.
        if (i == 0 && layers.length > 1 && field == 'font' && value == 'onest') continue;
        values[field] = value;
      }
    }
    // Rejim: shaxsiy (oxirgi qatlam) ustun, keyin telefondagi tanlov, keyin platforma.
    String? mode = layers.isEmpty ? null : normalizeThemeValue('mode', layers.last['mode']);
    mode ??= normalizeThemeValue('mode', cachedMode);
    if (mode == null) {
      for (final layer in layers) {
        mode = normalizeThemeValue('mode', layer['mode']) ?? mode;
      }
    }
    return ThemeChoice(
      mode: mode ?? themeDefaults['mode']!,
      accent: values['accent']!,
      template: values['template']!,
      font: values['font']!,
      size: values['size']!,
      radius: values['radius']!,
      icons: values['icons']!,
      density: values['density']!,
      cards: values['cards']!,
      sidebar: values['sidebar']!,
      pattern: values['pattern']!,
      motion: values['motion']!,
    );
  }

  ThemeChoice copyWith(Map<String, String?> values) {
    String pick(String field, String current) => normalizeThemeValue(field, values[field]) ?? current;
    return ThemeChoice(
      mode: pick('mode', mode),
      accent: pick('accent', accent),
      template: pick('template', template),
      font: pick('font', font),
      size: pick('size', size),
      radius: pick('radius', radius),
      icons: pick('icons', icons),
      density: pick('density', density),
      cards: pick('cards', cards),
      sidebar: pick('sidebar', sidebar),
      pattern: pick('pattern', pattern),
      motion: pick('motion', motion),
    );
  }

  String _auto(String field, String value) => value == 'auto' ? (templateDefaults[template]?[field] ?? templateDefaults['classic']![field]!) : value;

  /// Aniq zichlik: comfy / normal / compact.
  String get effectiveDensity => _auto('density', density);

  /// Aniq karta uslubi: bordered / shadow / flat.
  String get effectiveCards => _auto('cards', cards);

  /// Aniq menyu uslubi: full / icons / floating (mobilda floating — pastki menyu suzuvchi).
  String get effectiveSidebar => _auto('sidebar', sidebar);

  /// Aniq fon naqshi: none / dots / lines.
  String get effectivePattern => _auto('pattern', pattern);

  /// Zichlik ko'paytmasi (veb: --density 1.15 / 1 / 0.78).
  double get densityFactor {
    switch (effectiveDensity) {
      case 'comfy':
        return 1.15;
      case 'compact':
        return 0.78;
    }
    return 1;
  }

  /// Burchak ko'paytmasi: foydalanuvchi tanlovi (tik 0.4, yumaloq 1, juda yumaloq 1.45) × shablon.
  double get radiusFactor {
    const user = <String, double>{'sharp': 0.4, 'rounded': 1, 'pill': 1.45};
    const template = <String, double>{'soft': 1.4, 'compact': 0.65, 'spring': 1.3, 'graphite': 0.75};
    return (user[radius] ?? 1) * (template[this.template] ?? 1);
  }

  /// Shrift o'lchami shkalasi (veb: 14.5 / 16 / 17.5 / 19 px).
  double get textScale {
    const scale = <String, double>{'sm': 14.5 / 16, 'md': 1, 'lg': 17.5 / 16, 'xl': 19 / 16};
    return scale[size] ?? 1;
  }

  /// Ilovaga qo'shilgan shrift oilasi (assets/fonts).
  String get fontFamily => familyOf(font);

  /// Sarlavha shrifti (veb: --font-title): Klassik va Qog'oz — Literata (serif), Yumshoq va Bahor — Nunito,
  /// Maktab — Manrope, Okean — Golos Text, qolganlari — asosiy shrift.
  String get titleFamily {
    switch (template) {
      case 'classic':
      case 'paper':
        return 'Literata';
      case 'soft':
      case 'spring':
        return 'Nunito';
      case 'school':
        return 'Manrope';
      case 'ocean':
        return 'GolosText';
    }
    return fontFamily;
  }

  /// Sarlavha qalinligi (veb: --title-weight; Flutter qadamlariga yaxlitlangan).
  int get titleWeight {
    switch (template) {
      case 'classic':
      case 'paper':
        return 600;
      case 'compact':
      case 'ocean':
        return 700;
    }
    return 800;
  }

  /// Serif sarlavha (Literata): harflar orasi biroz qisiladi, qator balandligi kattaroq.
  bool get serifTitles => titleFamily == 'Literata';

  /// Zich ko'rinish (kassir/administrator): kichikroq boshqaruv balandligi, zich ro'yxatlar.
  bool get dense => effectiveDensity == 'compact';

  /// Qulay (keng) ko'rinish.
  bool get comfy => effectiveDensity == 'comfy';

  /// Kartalar chegarasiz (soyali yoki tekis).
  bool get borderlessCards => effectiveCards != 'bordered';

  /// To'q menyu paneli (Qorong'i panel, Grafit — mobilda yuqori va pastki panel).
  bool get darkChrome => template == 'night' || template == 'graphite';

  /// Katak daftar foni (Maktab).
  bool get notebook => template == 'school';

  /// Pastki menyu suzuvchi (Yumshoq yoki «Suzuvchi» menyu).
  bool get floatingNav => effectiveSidebar == 'floating';

  /// Menyu ikonalari har bo'lim o'z rangida.
  bool get coloredIcons => icons != 'mono';

  /// MaterialApp ni qayta qurish kaliti.
  String get key => '$accent-$template-$font-$size-$radius-$icons-$density-$cards-$sidebar-$pattern-$motion';

  static String familyOf(String font) {
    switch (font) {
      case 'manrope':
        return 'Manrope';
      case 'nunito':
        return 'Nunito';
      case 'onest':
        return 'Onest';
    }
    return 'GolosText';
  }

  Map<String, String> toJson() => <String, String>{
        'mode': mode,
        'accent': accent,
        'template': template,
        'font': font,
        'size': size,
        'radius': radius,
        'icons': icons,
        'density': density,
        'cards': cards,
        'sidebar': sidebar,
        'pattern': pattern,
        'motion': motion,
      };
}

/// «Bugun» kartasi ohangi (chap chetdagi rangli chiziq): danger — qizil, warning — sariq, success — yashil.
enum TodayTone { none, danger, warning, success }

TodayTone toneOf(String? value) {
  switch (value) {
    case 'danger':
      return TodayTone.danger;
    case 'warning':
      return TodayTone.warning;
    case 'success':
      return TodayTone.success;
    default:
      return TodayTone.none;
  }
}

/// Oy tushumining o'tgan oyga nisbatan o'zgarishi (veb: ManagerHome monthDelta): foiz, o'tgan oy 0 bo'lsa — null.
int? monthDeltaPercent(List<num> values) {
  if (values.length < 2) return null;
  final previous = values[values.length - 2];
  final current = values[values.length - 1];
  if (previous == 0) return null;
  return ((current - previous) / previous * 100).round();
}

/// Ismdan barqaror indeks (veb: Avatar.vue — hash*31 + kod, 32-bit) — bir odam har doim bir rangda.
int stableIndex(String name, int count) {
  var hash = 0;
  for (final unit in name.codeUnits) {
    hash = (hash * 31 + unit) & 0xFFFFFFFF;
  }
  return count <= 0 ? 0 : hash % count;
}

/// «Familiya Ism» → ikki bosh harf (veb: Avatar.vue).
String initialsOf(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  final first = parts[0].substring(0, 1);
  final second = parts.length > 1 ? parts[1].substring(0, 1) : '';
  return (first + second).toUpperCase();
}
