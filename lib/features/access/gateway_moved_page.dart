// 3.39 (server 2.101): SMS shlyuz, bank SMS'lari va «Telefon orqali» call markaz asosiy ilovadan alohida «EduX Shlyuz»
// ilovasiga ko'chdi — u faqat shu ish uchun qilingan va telefon qulflanganda ham uzilmaydi. Bu sahifa uni o'rnatishga
// yo'naltiradi; ulash — vebdagi QR kod bilan (SMS sahifasi, Sozlamalar → Call markaz, platforma SMS sozlamalari).
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

/// EduX Shlyuz APK havolasi: server o'zi beradi (yuklangan fayl yoki GitHub «gateway-latest» relizi).
String gatewayApkUrl(Session session) => '${session.server.replaceAll(RegExp(r'/+$'), '')}/download/android/gateway';

class GatewayMovedCard extends StatelessWidget {
  const GatewayMovedCard({super.key, this.calls = false});

  /// Call markaz sahifasida — qo'ng'iroqlar haqida matn.
  final bool calls;

  @override
  Widget build(BuildContext context) {
    final session = AppScope.read(context);
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Text(tr('EduX Shlyuz ilovasi'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: AppSpacing.s),
        Text(
          calls
              ? tr("Qo'ng'iroqlarni telefon orqali yozish, SIP softfon va qayta qo'ng'iroqlar endi alohida EduX Shlyuz ilovasida. U telefon qulflanganda ham uzilmaydi.")
              : tr("SMS'ni telefon orqali yuborish va bank SMS'lari endi alohida EduX Shlyuz ilovasida. U telefon qulflanganda ham uzilmaydi."),
          style: TextStyle(color: AppColors.muted),
        ),
        const SizedBox(height: AppSpacing.s),
        Text(
          tr("1. Ilovani o'rnating. 2. Vebda SMS sahifasi yoki Sozlamalar → Call markazda «Ulash kodini yaratish». 3. Ilovada QR kodni skanerlang."),
          style: TextStyle(color: AppColors.muted, fontSize: 13),
        ),
        const SizedBox(height: AppSpacing.m),
        FilledButton.icon(
          onPressed: () => launchUrl(Uri.parse(gatewayApkUrl(session)), mode: LaunchMode.externalApplication),
          icon: const Icon(Icons.download_outlined),
          label: Text(tr('EduX Shlyuz ilovasini yuklab olish')),
        ),
      ]),
    );
  }
}

class GatewayMovedPage extends StatelessWidget {
  const GatewayMovedPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.l),
      children: const <Widget>[GatewayMovedCard()],
    );
  }
}
