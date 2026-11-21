import 'package:edux/core/brand.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('oddiy EduX ilovasi: markaz yo\'q, saqlangan yoki yagona tashkilot tanlanadi', () {
    expect(isBranded, isFalse);
    expect(brandName, 'EduX');
    expect(preferredOrganization(<int>[3, 7], 7), 7);
    expect(preferredOrganization(<int>[3, 7], 9), isNull);
    expect(preferredOrganization(<int>[5], null), 5);
  });
}
