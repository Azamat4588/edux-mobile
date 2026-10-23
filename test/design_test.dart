import 'package:edux/core/design.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('eski shablon qiymatlari yangisiga o\'giriladi', () {
    expect(normalizeThemeValue('template', 'vivid'), 'school');
    expect(normalizeThemeValue('template', 'midnight'), 'night');
    expect(normalizeThemeValue('template', 'soft'), 'soft');
    expect(normalizeThemeValue('template', 'neon'), isNull);
    expect(normalizeThemeValue('accent', ''), isNull);
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
    expect(choice.notebook, isTrue);
    expect(choice.titleFamily, 'Manrope');
    expect(choice.radiusFactor, closeTo(1.45, 1e-9));
    expect(choice.textScale, closeTo(17.5 / 16, 1e-9));
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
    expect(soft.radiusFactor, closeTo(1.4, 1e-9));
    expect(soft.titleFamily, 'Nunito');
    const compact = ThemeChoice(template: 'compact', radius: 'sharp');
    expect(compact.dense, isTrue);
    expect(compact.radiusFactor, closeTo(0.26, 1e-9));
    expect(const ThemeChoice(template: 'night').darkChrome, isTrue);
    expect(const ThemeChoice(font: 'nunito').fontFamily, 'Nunito');
    expect(toneOf('danger'), TodayTone.danger);
    expect(toneOf('x'), TodayTone.none);
  });
}
