// Yordam havolalari: manzillar, maqola ichidagi havoladan slug va ilovadagi har slug serverda borligi
// (test/fixtures/help_slugs.json — backend resources/help/articles papka nomlari, 3.5 da olingan).
import 'dart:convert';
import 'dart:io';

import 'package:edux/core/help_links.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('yordam markazi manzillari', () {
    expect(HelpLinks.url('https://app.edux.uz/').toString(), 'https://app.edux.uz/help?lang=uz');
    expect(HelpLinks.url('https://app.edux.uz', HelpLinks.scanner).toString(), 'https://app.edux.uz/yordam/varaqani-skanerlash?lang=uz');
    expect(HelpLinks.url('http://192.168.1.5:8000', 'farzandim').toString(), 'http://192.168.1.5:8000/yordam/farzandim?lang=uz');
  });

  test('ilovadagi barcha slug lar serverda bor', () {
    final server = (jsonDecode(File('test/fixtures/help_slugs.json').readAsStringSync()) as List).map((item) => '$item').toSet();
    expect(server.length, greaterThan(90));
    for (final slug in HelpLinks.all) {
      expect(server, contains(slug), reason: 'serverda «$slug» maqolasi yo\'q');
    }
    expect(HelpLinks.all.toSet().length, HelpLinks.all.length);
    // Jadval (help-slugs.md): har ekran o'z maqolasiga.
    expect(HelpLinks.checkin, 'qr-karta-bilan-davomat');
    expect(HelpLinks.kiosk, 'kirish-nazorati');
    expect(HelpLinks.login, 'tizimga-kirish');
    expect(HelpLinks.problems, 'muammolar-va-yechimlar');
  });

  test('maqola ichidagi havola → slug', () {
    expect(HelpLinks.slugOf('/help/tizimga-kirish'), 'tizimga-kirish');
    expect(HelpLinks.slugOf('/yordam/kartaga-otkazma#qadamlar'), 'kartaga-otkazma');
    expect(HelpLinks.slugOf('https://edux.uz/yordam/farzandim?lang=ru'), 'farzandim');
    expect(HelpLinks.slugOf('/help'), isNull);
    expect(HelpLinks.slugOf('/crm/payments'), isNull);
    expect(HelpLinks.slugOf('#bolim'), isNull);
    expect(HelpLinks.slugOf('/help/Bad_Slug'), isNull);
  });
}
