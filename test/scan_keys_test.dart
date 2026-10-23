import 'package:edux/core/scan_keys.dart';
import 'package:flutter_test/flutter_test.dart';

List<String?> type(ScanDetector detector, String text, {int start = 0, int gap = 10, int enterAfter = 10, String end = 'Enter'}) {
  final results = <String?>[];
  var time = start;
  for (final char in text.split('')) {
    results.add(detector.feed(ScanKey(key: char, character: char), time));
    time += gap;
  }
  results.add(detector.feed(ScanKey(key: end), time - gap + enterAfter));
  return results;
}

void main() {
  test('tez ketma-ketlik + Enter = kod', () {
    final detector = ScanDetector();
    expect(type(detector, 'EDUX:S:123456').last, 'EDUX:S:123456');
    expect(type(detector, '00000012345678', end: 'Tab').last, '00000012345678');
  });

  test('odam yozuvi, qisqa kod va kech Enter — kod emas', () {
    final detector = ScanDetector();
    expect(type(detector, '123456', gap: 150).last, isNull);
    expect(type(detector, '12345').last, isNull);
    expect(type(detector, '123456', enterAfter: 400).last, isNull);
  });

  test('modifikatorlar e\'tiborsiz, Ctrl — tozalaydi', () {
    final detector = ScanDetector();
    detector.feed(const ScanKey(key: 'A', character: 'A'), 0);
    detector.feed(const ScanKey(key: 'Shift Left'), 5);
    detector.feed(const ScanKey(key: 'B', character: 'B'), 10);
    expect(detector.pending, isTrue);
    detector.feed(const ScanKey(key: 'C', character: 'c', control: true), 15);
    expect(detector.pending, isFalse);
  });

  test('kirill joylashuvi va qo\'lda kod', () {
    expect(fromCyrillicLayout('УВГЧЖЫЖ'), 'EDUX:S:');
    expect(normalizeScanPayload('  УВГЧЖЫЖ12\n'), 'EDUX:S:12');
    expect(normalizeScanPayload('123456'), '123456');
    expect(isManualCode('123456'), isTrue);
    expect(isManualCode('12345678901234'), isTrue);
    expect(isManualCode('1234567'), isFalse);
  });
}
