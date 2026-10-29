// 3.9 (dizayn v3 «Koshin»): ko'rinish qatlamlari, eski qiymatlar (LEGACY) va shablon tanlovlari — toza mantiq.
import 'package:edux/core/design.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("eski shablon qiymatlari yangisiga o'giriladi (paper → atlas)", () {
    expect(normalizeThemeValue('template', 'vivid'), 'school');
    expect(normalizeThemeValue('template', 'midnight'), 'night');
    expect(normalizeThemeValue('template', 'paper'), 'atlas');
    expect(normalizeThemeValue('template', 'atlas'), 'atlas');
    expect(normalizeThemeValue('template', 'soft'), 'soft');
    expect(normalizeThemeValue('template', 'neon'), isNull);
    expect(normalizeThemeValue('accent', ''), isNull);
    expect(normalizeThemeValue('pattern', 'grid'), 'grid');
    expect(normalizeThemeValue('font', 'commissioner'), 'commissioner');
  });

  test('9 shablon (veb bilan bir xil kalitlar) va standartlar', () {
    expect(themeOptions['template'], <String>['classic', 'soft', 'night', 'compact', 'school', 'atlas', 'ocean', 'graphite', 'spring']);
    expect(templateLabels['classic'], 'Koshin');
    expect(templateLabels['night'], 'Lojuvard');
    expect(templateLabels['atlas'], 'Atlas');
    for (final key in themeOptions['template']!) {
      expect(templateDefaults[key], isNotNull, reason: key);
      expect(templateHints[key], isNotNull, reason: key);
    }
    const choice = ThemeChoice();
    expect(choice.accent, 'teal');
    expect(choice.template, 'classic');
    expect(choice.fontFamily, 'Onest');
    expect(choice.titleFamily, 'Commissioner');
  });

  test('qatlamlar: platforma → tashkilot → shaxsiy', () {
    final choice = ThemeChoice.resolve(<Map<String, dynamic>>[
      <String, dynamic>{'accent': 'blue', 'template': 'classic', 'mode': 'light', 'font': 'onest'},
      <String, dynamic>{'accent': 'emerald', 'template': 'vivid'},
      <String, dynamic>{'size': 'lg', 'radius': 'pill'},
    ]);
    expect(choice.accent, 'emerald');
    expect(choice.template, 'school');
    expect(choice.mode, 'light');
    expect(choice.size, 'lg');
    expect(choice.effectivePattern, 'grid'); // Maktab — katak daftar
    expect(choice.titleFamily, 'Commissioner');
    expect(choice.sectionTinted, isTrue);
    expect(choice.radiusFactor, closeTo(1.45, 1e-9));
    expect(choice.textScale, closeTo(17.5 / 16, 1e-9));
    // Eski serverdagi «Qog'oz» — Atlas.
    expect(ThemeChoice.resolve(<Map<String, dynamic>>[<String, dynamic>{}, <String, dynamic>{'template': 'paper'}, <String, dynamic>{}]).template, 'atlas');
  });

  test('rejim: shaxsiy → telefondagi tanlov → platforma', () {
    final site = <String, dynamic>{'mode': 'light'};
    expect(ThemeChoice.resolve(<Map<String, dynamic>>[site, <String, dynamic>{}, <String, dynamic>{'mode': 'dark'}]).mode, 'dark');
    expect(ThemeChoice.resolve(<Map<String, dynamic>>[site, <String, dynamic>{}, <String, dynamic>{}], cachedMode: 'system').mode, 'system');
    expect(ThemeChoice.resolve(<Map<String, dynamic>>[site, <String, dynamic>{}, <String, dynamic>{}]).mode, 'light');
  });

  test('shablon tokenlari', () {
    const soft = ThemeChoice(template: 'soft');
    expect(soft.borderlessCards, isTrue);
    expect(soft.radiusFactor, closeTo(1.35, 1e-9));
    expect(soft.titleFamily, 'Nunito');
    expect(soft.floatingNav, isTrue);
    const compact = ThemeChoice(template: 'compact', radius: 'sharp');
    expect(compact.dense, isTrue);
    expect(compact.quietTiles, isTrue);
    expect(compact.radiusFactor, closeTo(0.26, 1e-9));
    expect(const ThemeChoice(template: 'graphite').quietTiles, isTrue);
    expect(const ThemeChoice().quietTiles, isFalse);
    expect(const ThemeChoice(template: 'night').darkChrome, isTrue);
    expect(const ThemeChoice(template: 'atlas').darkChrome, isTrue);
    expect(const ThemeChoice(template: 'atlas').radiusFactor, closeTo(1.1, 1e-9));
    expect(const ThemeChoice(font: 'nunito').fontFamily, 'Nunito');
    expect(const ThemeChoice(font: 'commissioner').fontFamily, 'Commissioner');
    expect(const ThemeChoice(font: 'golos').fontFamily, 'Onest'); // Golos fayllari ilovada yo'q
    expect(toneOf('danger'), TodayTone.danger);
    expect(toneOf('x'), TodayTone.none);
  });

  test("koshin plitka rangi: holatdan, aks holda belgi ma'nosidan (veb TodayCard)", () {
    expect(hueOf(tone: TodayTone.danger, icon: 'banknote'), KoshinHue.anor);
    expect(hueOf(tone: TodayTone.warning), KoshinHue.shafran);
    expect(hueOf(tone: TodayTone.success), KoshinHue.pista);
    expect(hueOf(icon: 'banknote'), KoshinHue.feruza);
    expect(hueOf(icon: 'calendar'), KoshinHue.lojuvard);
    expect(hueOf(icon: 'clipboard-list'), KoshinHue.olxori);
    expect(hueOf(icon: 'users'), KoshinHue.shafran);
    expect(hueOf(icon: 'noma\'lum'), KoshinHue.feruza);
    expect(hueOf(hue: 'pista', tone: TodayTone.danger), KoshinHue.pista);
  });
}
