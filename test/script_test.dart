// 3.30: o'zbekcha kirill (oz) va yangi lotin (yl) — veb (resources/js/i18n/script.js) bilan aynan bir xil natija.
// test/fixtures/script_samples.json veb skripti bilan yaratilgan (ilova lug'atidan ~500 kalit + maxsus holatlar).
import 'dart:convert';
import 'dart:io';

import 'package:edux/core/script.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('asosiy qoidalar', () {
    expect(Script.convert("O'quvchilar", 'oz'), 'Ўқувчилар');
    expect(Script.convert("O'quvchilar", 'yl'), 'Óquvçilar');
    expect(Script.convert("Telegram'ga xabar", 'oz'), "Telegram'га хабар");
    expect(Script.convert('{0} ta SMS', 'oz'), '{0} та SMS');
    expect(Script.convert('Operatsiya, pensiya', 'oz'), 'Операция, пенсия');
    expect(Script.convert("O'quvchilar", 'ru'), "O'quvchilar");
  });

  test('veb bilan bir xil (namunalar)', () {
    final rows = jsonDecode(File('test/fixtures/script_samples.json').readAsStringSync()) as List<dynamic>;
    var bad = 0;
    for (final row in rows.cast<List<dynamic>>()) {
      final source = row[0] as String;
      if (Script.convert(source, 'oz') != row[1] || Script.convert(source, 'yl') != row[2]) {
        bad++;
        // ignore: avoid_print
        print('farq: $source → ${Script.convert(source, 'oz')} / ${row[1]}');
      }
    }
    expect(bad, 0);
    expect(rows.length, greaterThan(400));
  });
}
