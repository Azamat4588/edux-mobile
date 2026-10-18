import 'package:edux/core/format.dart';
import 'package:edux/core/i18n.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pul va raqamlar', () {
    expect(groupDigits(1600000), '1 600 000');
    expect(groupDigits(999), '999');
    expect(money(-25000), "−25 000 so'm");
    expect(tr('{0} ta test', <Object?>[5]), '5 ta test');
  });

  test('sana', () {
    expect(isoDay(DateTime(2026, 3, 7)), '2026-03-07');
    expect(date(DateTime(2026, 10, 16, 12).toIso8601String()), '16.10.2026');
  });
}
