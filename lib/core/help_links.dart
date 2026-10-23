// Yordam markazi (veb-tizimdagi wiki): «Yana» → «Yordam» ekrani va ekranlar sarlavhasidagi «?».
// 3.5: maqola ilova ichida ochiladi (API `help/articles/<slug>`, kirmagan bo'lsa `public/help/articles/<slug>`),
// brauzerda ochish varianti qoladi: umumiy ro'yxat `<server>/help` (brauzerda kirilmagan bo'lsa o'zi ochiq `/yordam`
// ga o'tadi), bitta maqola — `<server>/yordam/<slug>`. Til `?lang=` bilan uzatiladi.
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../features/help/help_pages.dart';
import 'i18n.dart';
import 'session.dart';
import 'widgets.dart';

class HelpLinks {
  HelpLinks._();

  // Maqola nomlari (slug) — serverdagi resources/help/articles/<slug> bilan bir xil (test/help_links_test.dart tekshiradi).
  static const String scanner = 'varaqani-skanerlash';
  static const String attendance = 'davomat-belgilash';
  static const String guardian = 'farzandim';
  static const String examResults = 'test-natijalari';
  static const String journal = 'elektron-jurnal';
  static const String checkin = 'qr-karta-bilan-davomat';
  static const String kiosk = 'kirish-nazorati';
  static const String courseQuestions = 'kurs-elonlari-va-savol-javob';
  static const String lesson = 'darsda-savol-va-jonli-dars';
  static const String myPayments = 'oquvchi-kabineti';
  static const String myTests = 'onlayn-test-topshirish';
  static const String p2p = 'kartaga-otkazma';
  static const String deviceSms = 'sms-oz-telefonimdan';
  static const String platformSms = 'sms-xizmatini-ulash';
  static const String support = 'qollab-quvvatlash';
  static const String login = 'tizimga-kirish';
  static const String problems = 'muammolar-va-yechimlar';
  static const String teacherHome = 'oqituvchi-telefonda';
  static const String faq = 'kop-beriladigan-savollar';
  static const String install = 'mobil-ilova-ornatish';

  /// Ilovada ishlatiladigan barcha slug'lar (test: serverda bor-yo'qligi).
  static const List<String> all = <String>[
    scanner, attendance, guardian, examResults, journal, checkin, kiosk, courseQuestions, lesson, myPayments, myTests,
    p2p, deviceSms, platformSms, support, login, problems, teacherHome, faq, install,
  ];

  /// Manzil: slug bo'lmasa — yordam markazi bosh sahifasi.
  static Uri url(String server, [String? slug]) {
    final base = server.replaceAll(RegExp(r'/+$'), '');
    final path = slug == null || slug.isEmpty ? '/help' : '/yordam/${Uri.encodeComponent(slug)}';
    return Uri.parse('$base$path?lang=${I18n.locale}');
  }

  /// Maqola ichidagi havola → slug: `/help/<slug>`, `/yordam/<slug>` (yoki to'liq manzil, `#bo'lim` bilan). Aks holda null.
  static String? slugOf(String href) {
    final uri = Uri.tryParse(href.trim());
    if (uri == null) return null;
    final segments = uri.pathSegments.where((item) => item.isNotEmpty).toList();
    if (segments.length != 2 || (segments[0] != 'help' && segments[0] != 'yordam')) return null;
    final slug = segments[1];
    return RegExp(r'^[a-z0-9-]+$').hasMatch(slug) ? slug : null;
  }

  /// Brauzerda ochish.
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

  /// Ilova ichida ochish (maqola sahifasi; u yerda «Brauzerda ochish» ham bor).
  static Future<void> show(BuildContext context, String slug) {
    return Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => HelpArticlePage(slug: slug)));
  }
}

/// Sarlavhadagi «?» tugmasi: shu ekran haqidagi maqola (ilova ichida).
class HelpButton extends StatelessWidget {
  const HelpButton(this.slug, {super.key, this.color});

  final String slug;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(Icons.help_outline, color: color),
      tooltip: tr('Sahifa yordami'),
      onPressed: () => HelpLinks.show(context, slug),
    );
  }
}

/// Xato yoki «aloqa yo'q» holatida: «Muammolar va yechimlar» maqolasi.
class ProblemsLink extends StatelessWidget {
  const ProblemsLink({super.key});

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () => HelpLinks.show(context, HelpLinks.problems),
      icon: const Icon(Icons.help_outline, size: 18),
      label: Text(tr('Muammolar va yechimlar')),
    );
  }
}
