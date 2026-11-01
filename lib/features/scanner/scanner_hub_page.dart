// Skaner bo'limi: skanerni boshlash (istalgan test yoki tanlangan test), navbat va ko'rib chiqish holati, maslahatlar.
import 'package:flutter/material.dart';

import '../../core/adaptive.dart';
import '../../core/api.dart';
import '../../core/help_links.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'scan_queue.dart';
import 'scanner_page.dart';
import 'scans_page.dart';

class ScannerHubPage extends StatelessWidget {
  const ScannerHubPage({super.key});

  Future<Map<String, dynamic>> _load(Api api) async {
    final results = await Future.wait<dynamic>(<Future<dynamic>>[
      api.get('exams', query: <String, Object?>{'status': 'published', 'per_page': 200}),
      api.get('scans', query: <String, Object?>{'status': 'needs_review'}),
    ]);
    return <String, dynamic>{'exams': asList(results[0]), 'counts': asMap(asMap(results[1])['counts'])};
  }

  void _open(BuildContext context, {int? examId, String? title}) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ScannerPage(examId: examId, examTitle: title)));
  }

  @override
  Widget build(BuildContext context) {
    final api = AppScope.of(context).api;
    return Scaffold(
      appBar: pageBar(context, title: Text(tr('Skaner')), actions: const <Widget>[HelpButton(HelpLinks.scanner)]),
      body: AsyncView<Map<String, dynamic>>(
        load: () => _load(api),
        builder: (context, data, reload) {
          final exams = asList(data['exams'], 'exams');
          final review = asInt(asMap(data['counts'])['needs_review']);
          return ListView(
            padding: readable(context, const EdgeInsets.all(16)),
            children: <Widget>[
              Material(
                color: AppColors.brand,
                borderRadius: BorderRadius.circular(20),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _open(context),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(children: <Widget>[
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(color: Colors.white.withAlpha(40), borderRadius: BorderRadius.circular(16)),
                        child: const Icon(Icons.document_scanner, color: Colors.white, size: 32),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                          Text(tr('Skanerlashni boshlash'),
                              style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          Text(tr("Test va o'quvchi varaqadagi QR kod va kod doirachalaridan o'zi aniqlanadi."),
                              style: TextStyle(color: Colors.white.withAlpha(220))),
                        ]),
                      ),
                    ]),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              AnimatedBuilder(
                animation: ScanQueue.instance,
                builder: (context, _) {
                  final waiting = ScanQueue.instance.waitingCount;
                  return StatGrid(children: <Widget>[
                    StatCard(
                      label: tr('Yuborilishi kutilmoqda'),
                      value: '$waiting',
                      icon: Icons.cloud_upload_outlined,
                      color: waiting > 0 ? AppColors.warning : AppColors.success,
                      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ScansPage())),
                    ),
                    StatCard(
                      label: tr("Ko'rib chiqish kerak"),
                      value: '$review',
                      icon: Icons.rate_review_outlined,
                      color: review > 0 ? AppColors.warning : AppColors.success,
                      onTap: () async {
                        await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ScansPage(initialTab: 1)));
                        await reload();
                      },
                    ),
                  ]);
                },
              ),
              if (exams.isNotEmpty) ...<Widget>[
                SectionTitle(tr('Tanlangan test uchun')),
                Text(tr("Test tanlansa, uning kaliti telefonga oldindan yuklanadi: QR kod o'qilmasa ham varaqa tekshiriladi va natija internetsiz ham darhol chiqadi."),
                    style: TextStyle(color: AppColors.muted, fontSize: 13)),
                const SizedBox(height: 10),
                for (final exam in exams) ...<Widget>[
                  AppCard(
                    onTap: () => _open(context, examId: asInt(exam['id']), title: asText(exam['title'])),
                    child: Row(children: <Widget>[
                      Icon(Icons.assignment_outlined, color: AppColors.brand),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                          Text(asText(exam['title']), style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text(tr('{0} ta natija', <Object?>[asInt(exam['finished_attempts_count'])]),
                              style: TextStyle(color: AppColors.muted, fontSize: 13)),
                        ]),
                      ),
                      Icon(Icons.document_scanner_outlined, color: AppColors.muted),
                    ]),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
              SectionTitle(tr('Yaxshi natija uchun')),
              AppCard(
                child: Column(children: <Widget>[
                  _Tip(Icons.crop_free, tr("Varaqaning to'rt burchagidagi qora kvadrat belgilar ekranda ko'rinsin.")),
                  _Tip(Icons.light_mode_outlined, tr("Yorug' joyda, soya tushirmasdan suratga oling; qorong'ida chiroqni yoqing.")),
                  _Tip(Icons.pan_tool_alt_outlined, tr("Telefonni varaqa ustida tekis ushlang — ilova o'zi suratga oladi.")),
                  _Tip(Icons.repeat, tr('Ketma-ket rejim: tekshirilgan varaqani olib, keyingisini qo\'ying.')),
                  _Tip(Icons.wifi_off, tr("Internet bo'lmasa ham ishlaydi: varaqalar telefonda saqlanadi va keyin yuboriladi.")),
                ]),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Tip extends StatelessWidget {
  const _Tip(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Icon(icon, size: 20, color: AppColors.brand),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
      ]),
    );
  }
}
