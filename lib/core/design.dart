// Dizayn tizimi (veb 1.35 «Daftar», docs/design.md): rejim, asosiy rang, shablon, shrift, o'lcham, burchaklar, ikonalar.
//
// Uch qatlam (pastdagisi ustidagini bosadi): platforma standarti (GET /site → theme.defaults) → tashkilot brendi
// (GET /context → theme) → shaxsiy tanlov (GET /me → user.appearance). Server qatlamlarni ruxsatga qarab o'zi tozalaydi
// (Theme::organization / Theme::user), ilova faqat birlashtiradi. Eski qiymatlar: vivid → school, midnight → night.
//
// Bu fayl toza mantiq (Flutter vidjetlarisiz) — test/design_test.dart shu funksiyalarni tekshiradi.

/// Har maydon uchun ruxsat etilgan qiymatlar (server: Theme::OPTIONS).
const Map<String, List<String>> themeOptions = <String, List<String>>{
  'mode': <String>['light', 'dark', 'system'],
  'accent': <String>['blue', 'violet', 'emerald', 'teal', 'sunset', 'rose', 'slate'],
  'template': <String>['classic', 'soft', 'night', 'compact', 'school'],
  'font': <String>['onest', 'manrope', 'nunito'],
  'size': <String>['sm', 'md', 'lg', 'xl'],
  'radius': <String>['sharp', 'rounded', 'pill'],
  'icons': <String>['color', 'mono'],
};

/// Standart qiymatlar (server: Theme::DEFAULTS). Mobil ilovada rejim standarti — «Qurilmaga qarab».
const Map<String, String> themeDefaults = <String, String>{
  'mode': 'system',
  'accent': 'blue',
  'template': 'classic',
  'font': 'onest',
  'size': 'md',
  'radius': 'rounded',
  'icons': 'color',
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
};
const Map<String, String> fontLabels = <String, String>{'onest': 'Onest', 'manrope': 'Manrope', 'nunito': 'Nunito'};
const Map<String, String> sizeLabels = <String, String>{'sm': 'Kichik', 'md': "O'rta", 'lg': 'Katta', 'xl': 'Juda katta'};
const Map<String, String> radiusLabels = <String, String>{'sharp': 'Tik', 'rounded': 'Yumaloq', 'pill': 'Juda yumaloq'};
const Map<String, String> iconsLabels = <String, String>{'color': 'Rangli', 'mono': 'Bir rangli'};

/// Qiymatni tekshiradi: eski qiymat yangisiga o'giriladi, noma'lum qiymat — null.
String? normalizeThemeValue(String field, Object? value) {
  if (value == null) return null;
  var text = value.toString().trim();
  if (text.isEmpty) return null;
  text = themeLegacy[field]?[text] ?? text;
  return (themeOptions[field] ?? const <String>[]).contains(text) ? text : null;
}

/// Birlashtirilgan ko'rinish.
class ThemeChoice {
  const ThemeChoice({
    this.mode = 'system',
    this.accent = 'blue',
    this.template = 'classic',
    this.font = 'onest',
    this.size = 'md',
    this.radius = 'rounded',
    this.icons = 'color',
  });

  final String mode;
  final String accent;
  final String template;
  final String font;
  final String size;
  final String radius;
  final String icons;

  /// Qatlamlarni birlashtirish: [layers] — pastdan yuqoriga (platforma, tashkilot, shaxsiy).
  /// [mode] uchun alohida: shaxsiy → [cachedMode] (telefonda oxirgi tanlangan) → platforma standarti.
  factory ThemeChoice.resolve(List<Map<String, dynamic>> layers, {String? cachedMode}) {
    final values = Map<String, String>.from(themeDefaults);
    for (final layer in layers) {
      for (final field in themeOptions.keys) {
        if (field == 'mode') continue;
        final value = normalizeThemeValue(field, layer[field]);
        if (value != null) values[field] = value;
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
    );
  }

  /// Burchak ko'paytmasi: foydalanuvchi tanlovi (tik 0.4, yumaloq 1, juda yumaloq 1.45) × shablon (yumshoq 1.4, ixcham 0.65).
  double get radiusFactor {
    const user = <String, double>{'sharp': 0.4, 'rounded': 1, 'pill': 1.45};
    const template = <String, double>{'soft': 1.4, 'compact': 0.65};
    return (user[radius] ?? 1) * (template[this.template] ?? 1);
  }

  /// Shrift o'lchami shkalasi (veb: 14.5 / 16 / 17.5 / 19 px).
  double get textScale {
    const scale = <String, double>{'sm': 14.5 / 16, 'md': 1, 'lg': 17.5 / 16, 'xl': 19 / 16};
    return scale[size] ?? 1;
  }

  /// Ilovaga qo'shilgan shrift oilasi (assets/fonts).
  String get fontFamily => _family(font);

  /// Sarlavha shrifti: Yumshoq — Nunito, Maktab — Manrope, qolganlari — asosiy shrift.
  String get titleFamily => template == 'soft' ? 'Nunito' : (template == 'school' ? 'Manrope' : fontFamily);

  /// Sarlavha qalinligi (veb: --title-weight). 750 → 700 (Flutter qadamlari).
  int get titleWeight => template == 'classic' || template == 'compact' ? 700 : 800;

  /// Zich shablon (kassir/administrator): kichikroq boshqaruv balandligi, zich ro'yxatlar.
  bool get dense => template == 'compact';

  /// Kartalar chegarasiz va rangli yumshoq soya bilan (Yumshoq).
  bool get borderlessCards => template == 'soft';

  /// To'q yuqori panel (Qorong'i panel shabloni — mobilda yon menyu o'rniga sarlavha paneli).
  bool get darkChrome => template == 'night';

  /// Katak daftar foni (Maktab).
  bool get notebook => template == 'school';

  /// Menyu ikonalari har bo'lim o'z rangida.
  bool get coloredIcons => icons != 'mono';

  /// MaterialApp ni qayta qurish kaliti.
  String get key => '$accent-$template-$font-$size-$radius-$icons';

  static String _family(String font) => font == 'manrope' ? 'Manrope' : (font == 'nunito' ? 'Nunito' : 'Onest');

  Map<String, String> toJson() => <String, String>{
        'mode': mode,
        'accent': accent,
        'template': template,
        'font': font,
        'size': size,
        'radius': radius,
        'icons': icons,
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
