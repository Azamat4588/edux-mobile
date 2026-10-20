// Yordam markazi (veb-tizimdagi wiki): «Ko'proq» menyusidagi «Yordam markazi» va ekranlar sarlavhasidagi «?».
// Maqolalar serverda — tashqi brauzerda ochiladi: umumiy ro'yxat `<server>/help` (brauzerda kirilmagan bo'lsa
// o'zi ochiq `/yordam` ga o'tadi), bitta maqola — `<server>/yordam/<slug>`. Til `?lang=` bilan uzatiladi.
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'i18n.dart';
import 'session.dart';
import 'widgets.dart';

class HelpLinks {
  HelpLinks._();

  // Maqola nomlari (slug) — serverdagi resources/help/articles/<slug> bilan bir xil.
  static const String scanner = 'varaqani-skanerlash';
  static const String attendance = 'davomat-belgilash';
  static const String guardian = 'farzandim';
  static const String examResults = 'test-natijalari';

  /// Manzil: slug bo'lmasa — yordam markazi bosh sahifasi.
  static Uri url(String server, [String? slug]) {
    final base = server.replaceAll(RegExp(r'/+$'), '');
    final path = slug == null || slug.isEmpty ? '/help' : '/yordam/${Uri.encodeComponent(slug)}';
    return Uri.parse('$base$path?lang=${I18n.locale}');
  }

  static Future<void> open(BuildContext context, [String? slug]) async {
    final uri = url(AppScope.read(context).server, slug);
    var ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
    if (!ok && context.mounted) {
      showMessage(context, tr("Brauzerni ochib bo'lmadi: {0}", <Object?>[uri.toString()]), error: true);
    }
  }
}

/// Sarlavhadagi «?» tugmasi: shu ekran haqidagi maqola.
class HelpButton extends StatelessWidget {
  const HelpButton(this.slug, {super.key});

  final String slug;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.help_outline),
      tooltip: tr('Sahifa yordami'),
      onPressed: () => HelpLinks.open(context, slug),
    );
  }
}
