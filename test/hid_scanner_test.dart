import 'package:edux/core/hid_scanner.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

String? typeInto(HidScanBuffer buffer, String text, {int start = 0, int gap = 10, int? enterAt}) {
  var time = start;
  for (final char in text.split('')) {
    buffer.addCharacter(char, time);
    time += gap;
  }
  return buffer.terminate(enterAt ?? time);
}

const Map<String, LogicalKeyboardKey> _keys = <String, LogicalKeyboardKey>{
  '0': LogicalKeyboardKey.digit0,
  '1': LogicalKeyboardKey.digit1,
  '2': LogicalKeyboardKey.digit2,
  '3': LogicalKeyboardKey.digit3,
  '4': LogicalKeyboardKey.digit4,
  '5': LogicalKeyboardKey.digit5,
  '6': LogicalKeyboardKey.digit6,
  '7': LogicalKeyboardKey.digit7,
  '8': LogicalKeyboardKey.digit8,
  '9': LogicalKeyboardKey.digit9,
};

Future<void> scan(WidgetTester tester, String text, {LogicalKeyboardKey end = LogicalKeyboardKey.enter}) async {
  for (final char in text.split('')) {
    await simulateKeyDownEvent(_keys[char]!, character: char);
    await simulateKeyUpEvent(_keys[char]!);
  }
  await simulateKeyDownEvent(end);
  await simulateKeyUpEvent(end);
  await tester.pump();
}

void main() {
  group('HidScanBuffer', () {
    test('tez ketma-ketlik + Enter = kod', () {
      final buffer = HidScanBuffer();
      expect(typeInto(buffer, 'EDUX:S:123456'), 'EDUX:S:123456');
      expect(typeInto(buffer, '00000012345678'), '00000012345678');
      expect(typeInto(buffer, '1234'), '1234');
    });

    test('4 belgidan qisqa — kod emas', () {
      final buffer = HidScanBuffer();
      expect(typeInto(buffer, '123'), isNull);
      expect(buffer.value, isEmpty);
    });

    test('300 ms dan uzun tanaffus buferni tozalaydi', () {
      final buffer = HidScanBuffer();
      buffer.addCharacter('9', 0);
      buffer.addCharacter('9', 10);
      // Tanaffus: oldingi «99» tashlanadi, yangi kod boshlanadi.
      expect(typeInto(buffer, '123456', start: 400), '123456');
      expect(typeInto(buffer, '123456', gap: 350), isNull);
      // Enter kech keldi.
      expect(typeInto(buffer, '123456', enterAt: 2000), isNull);
    });

    test('boshqaruv belgisi buferni tozalaydi', () {
      final buffer = HidScanBuffer();
      buffer.addCharacter('1', 0);
      buffer.addCharacter('2', 5);
      buffer.addCharacter(null, 8);
      expect(buffer.value, isEmpty);
      buffer.addCharacter('\u0007', 9);
      expect(buffer.value, isEmpty);
    });

    test('normalizeHidCode faqat bo\'shliqlarni oladi', () {
      expect(normalizeHidCode('  EDUX:S:12 \n'), 'EDUX:S:12');
      expect(normalizeHidCode('123456'), '123456');
    });
  });

  group('HidScannerListener', () {
    testWidgets('skaner kodini Enter va Tab bilan beradi', (tester) async {
      final codes = <String>[];
      await tester.pumpWidget(MaterialApp(home: HidScannerListener(onCode: codes.add, child: const SizedBox())));
      await scan(tester, '123456');
      await scan(tester, '00000012345678', end: LogicalKeyboardKey.tab);
      await scan(tester, '12');
      expect(codes, <String>['123456', '00000012345678']);
    });

    testWidgets('matn maydoni fokusda bo\'lsa — aralashmaydi', (tester) async {
      final codes = <String>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: HidScannerListener(onCode: codes.add, child: const TextField(autofocus: true))),
      ));
      await tester.pump();
      await scan(tester, '123456');
      expect(codes, isEmpty);
    });

    testWidgets('o\'chirilgan yoki olib tashlangan — tinglamaydi', (tester) async {
      final codes = <String>[];
      await tester.pumpWidget(MaterialApp(home: HidScannerListener(enabled: false, onCode: codes.add, child: const SizedBox())));
      await scan(tester, '123456');
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await scan(tester, '654321');
      expect(codes, isEmpty);
    });
  });
}
