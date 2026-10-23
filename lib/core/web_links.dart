// Veb-versiyadagi sozlamalar sahifalari (server 1.38: yorliq manzilda — `?tab=`). Ilovada yo'q sozlamalar uchun
// «Brauzerda ochish»: kerakli yorliq darhol ochiladi; brauzerda kirilmagan bo'lsa veb kirishdan keyin shu manzilga qaytaradi.
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'i18n.dart';
import 'session.dart';

class WebPages {
  WebPages._();

  /// Onlayn to'lov → «Kartaga o'tkazma» (karta, SMS manbasi, Telegram akkaunt).
  static const String paymentsP2p = '/settings/payments?tab=p2p';

  /// Onlayn to'lov → «To'lov usullari».
  static const String paymentMethods = '/settings/payments?tab=methods';

  /// Modullar va obuna.
  static const String modules = '/settings/modules';

  /// Ta'lim sozlamalari (kurs e'lonlari va b.).
  static const String lmsSettings = '/settings/lms';

  /// Kirish nazorati → Kiosklar.
  static const String kiosks = '/access?tab=kiosks';

  /// Barcha manzillar (test/web_links_test.dart veb route'lar bilan solishtiradi).
  static const List<String> all = <String>[paymentsP2p, paymentMethods, modules, lmsSettings, kiosks];
}

/// Serverdagi to'liq manzil (so'rov qismi `?tab=` saqlanadi).
Uri webPageUri(Api api, String path) => Uri.parse(api.absolute(path));

Future<bool> openWebPage(Api api, String path) => launchUrl(webPageUri(api, path), mode: LaunchMode.externalApplication);

/// «Brauzerda ochish» tugmasi — veb sozlamalarning kerakli yorlig'iga.
class OpenWebButton extends StatelessWidget {
  const OpenWebButton(this.path, {super.key, this.label});

  final String path;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(0, 36)),
      onPressed: () => openWebPage(AppScope.read(context).api, path),
      icon: const Icon(Icons.open_in_new, size: 18),
      label: Text(label ?? tr('Brauzerda ochish')),
    );
  }
}
