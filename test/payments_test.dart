import 'package:edux/core/payments.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('usullar server tartibida; eski server — click/payme', () {
    final methods = payMethods(<String, dynamic>{
      'methods': <dynamic>[
        <String, dynamic>{'key': 'p2p', 'name': "Kartaga o'tkazma", 'fee': 0, 'min': 0},
        <String, dynamic>{'key': 'uzum', 'name': 'Uzum Bank', 'fee': 1.5, 'min': 5000},
        <String, dynamic>{'key': 'click', 'name': 'Click', 'fee': 0, 'min': 0},
      ],
    });
    expect(methods.map((item) => item.key).toList(), <String>['p2p', 'uzum', 'click']);
    expect(methods.first.isP2p, isTrue);
    expect(methodAllows(methods[1], 4000), isFalse);
    expect(methodAllows(methods[1], 5000), isTrue);
    final legacy = payMethods(<String, dynamic>{'providers': <String, dynamic>{'click': true, 'payme': false}});
    expect(legacy.map((item) => item.key).toList(), <String>['click']);
  });

  test('karta va noyob summa formati', () {
    expect(cardGroups('8600123412345678'), '8600 1234 1234 5678'.replaceFirst('1234 1234', '1234 1234'));
    expect(cardGroups('8600 1234-5678 9012'), '8600 1234 5678 9012');
    expect(p2pAmountText(150037), '150 037');
    expect(p2pAmountText(1000999), '1 000 999');
    expect(p2pDelta(150037, 150000), 37);
    expect(digitsOnly('+998 (90) 123'), '99890123');
  });

  test('taymer va holat', () {
    final now = DateTime(2026, 10, 23, 12);
    expect(countdown(p2pRemaining(now.add(const Duration(minutes: 14, seconds: 5)), now)), '14:05');
    expect(countdown(const Duration(hours: 1, minutes: 2, seconds: 9)), '1:02:09');
    expect(p2pRemaining(now.subtract(const Duration(minutes: 1)), now), Duration.zero);
    expect(p2pState(<String, dynamic>{'status': 'paid'}, now), 'paid');
    expect(p2pState(<String, dynamic>{'status': 'open', 'p2p': <String, dynamic>{'expired': true}}, now), 'expired');
    expect(p2pState(<String, dynamic>{'status': 'open', 'p2p': <String, dynamic>{'expires_at': now.add(const Duration(minutes: 5)).toIso8601String()}}, now), 'waiting');
  });
}
