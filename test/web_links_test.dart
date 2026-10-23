// 3.6.0: veb sozlamalar yorliqlari (server 1.38, `?tab=`) — «Brauzerda ochish» manzillari.
import 'package:edux/core/session.dart';
import 'package:edux/core/web_links.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('yorliq manzili saqlanadi', () {
    final api = Session().api;
    final uri = webPageUri(api, WebPages.paymentsP2p);
    expect(uri.path, '/settings/payments');
    expect(uri.queryParameters['tab'], 'p2p');
    expect(uri.hasScheme, isTrue);
    expect(webPageUri(api, WebPages.kiosks).queryParameters['tab'], 'kiosks');
    expect(webPageUri(api, WebPages.paymentMethods).queryParameters['tab'], 'methods');
  });

  test('veb route ro\'yxatidagi sahifalar', () {
    // Veb: resources/js/router/routes.js (1.38) va yorliq kalitlari (PaymentSettings TABS, Access TABS).
    const known = <String>{'/settings/payments', '/settings/modules', '/settings/lms', '/access'};
    for (final path in WebPages.all) {
      expect(path.startsWith('/'), isTrue, reason: path);
      expect(known, contains(Uri.parse(path).path), reason: path);
    }
  });
}
