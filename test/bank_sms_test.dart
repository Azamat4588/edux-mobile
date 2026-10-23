import 'package:edux/core/bank_sms.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bank jo\'natuvchisi', () {
    expect(matchesBankSender('UZCARD', defaultBankSenders), isTrue);
    expect(matchesBankSender('Uzcard.uz', defaultBankSenders), isTrue);
    expect(matchesBankSender('HUMO', defaultBankSenders), isTrue);
    expect(matchesBankSender('Kapital Bank', defaultBankSenders), isTrue);
    expect(matchesBankSender('+998901234567', defaultBankSenders), isFalse);
    expect(matchesBankSender('Beeline', defaultBankSenders), isFalse);
    expect(matchesBankSender('', defaultBankSenders), isFalse);
  });

  test('50 tadan bo\'lish va sozlama matni', () {
    final batches = chunked(List<int>.generate(120, (index) => index));
    expect(batches.map((item) => item.length).toList(), <int>[50, 50, 20]);
    expect(parseSenders('UZCARD, HUMO\nNBU;;UZCARD'), <String>['UZCARD', 'HUMO', 'NBU']);
  });

  test('vaqt ISO 8601 offset bilan', () {
    final text = isoWithOffset(DateTime(2026, 10, 15, 14, 25));
    expect(text, startsWith('2026-10-15T14:25:00'));
    expect(RegExp(r'[+-]\d{2}:\d{2}$').hasMatch(text), isTrue);
  });
}
