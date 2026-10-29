// 3.4.1 → 3.9: tungi rejim va 9 shablonda matn o'qilishi (WCAG AA, oddiy matn ≥ 4.5:1) — har asosiy rang, shablon va rejim uchun.
import 'package:edux/core/design.dart';
import 'package:edux/core/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('contrastRatio va readableOn', () {
    expect(contrastRatio(Colors.white, Colors.black), closeTo(21, 0.01));
    expect(contrastRatio(Colors.white, Colors.white), closeTo(1, 0.01));
    const card = Color(0xFF121A2C);
    final fixed = readableOn(const Color(0xFFBE123C), card);
    expect(contrastRatio(fixed, card), greaterThanOrEqualTo(4.5));
    // Yetarli kontrastli rang o'zgarmaydi.
    expect(readableOn(Colors.black, Colors.white), Colors.black);
  });

  for (final dark in <bool>[false, true]) {
    for (final template in themeOptions['template']!) {
      test('${dark ? 'tungi' : 'kunduzgi'} · $template: barcha asosiy ranglarda matn o\'qiladi', () {
        for (final accent in accents) {
          AppTheme.apply(dark: dark, accent: accent, choice: ThemeChoice(template: template));
          final where = '${accent.key}/$template/${dark ? 'dark' : 'light'}';
          expect(contrastRatio(AppColors.ink, AppColors.card), greaterThanOrEqualTo(7), reason: 'ink $where');
          expect(contrastRatio(AppColors.muted, AppColors.card), greaterThanOrEqualTo(4.5), reason: 'muted $where');
          expect(contrastRatio(AppColors.brand, AppColors.card), greaterThanOrEqualTo(4.5), reason: 'brand $where');
          expect(contrastRatio(AppColors.onBrand, AppColors.accent), greaterThanOrEqualTo(4.5), reason: 'onBrand $where');
          expect(contrastRatio(AppColors.onChrome, AppColors.chrome), greaterThanOrEqualTo(4.5), reason: 'chrome $where');
          for (final semantic in <Color>[AppColors.success, AppColors.warning, AppColors.danger]) {
            expect(contrastRatio(semantic, AppColors.card), greaterThanOrEqualTo(4.5), reason: 'semantic $semantic $where');
            expect(contrastRatio(semantic, AppColors.soft(semantic)), greaterThanOrEqualTo(4.0), reason: 'pill $semantic $where');
          }
          for (final fill in <Color>[AppColors.successFill, AppColors.warningFill, AppColors.dangerFill]) {
            expect(contrastRatio(Colors.white, fill), greaterThanOrEqualTo(4.5), reason: 'fill $fill $where');
          }
        }
      });
    }
  }
}
