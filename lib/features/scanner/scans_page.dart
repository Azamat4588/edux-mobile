// Tekshirilgan varaqalar: telefondagi navbat (yuborilmagan, yuborilgan) va serverdagi ko'rib chiqish ro'yxati.
import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'exam_kit.dart';
import 'scan_queue.dart';
import 'scan_result_view.dart';
import 'scan_review_page.dart';

class ScansPage extends StatelessWidget {
  const ScansPage({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      initialIndex: initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: Text(tr('Varaqalar')),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: <Widget>[
              Tab(text: tr('Telefonda')),
              Tab(text: tr("Ko'rib chiqish")),
              Tab(text: tr('Serverda')),
            ],
          ),
        ),
        body: const TabBarView(children: <Widget>[
          _QueueTab(),
          _ServerTab(status: 'needs_review'),
          _ServerTab(status: null),
        ]),
      ),
    );
  }
}

class _QueueTab extends StatelessWidget {
  const _QueueTab();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ScanQueue.instance,
      builder: (context, _) {
        final queue = ScanQueue.instance;
        final session = AppScope.of(context);
        final items = queue.items.where((item) => item.organizationId == session.organizationId).toList();
        if (items.isEmpty) {
          return EmptyState(icon: Icons.document_scanner_outlined, text: tr("Hali varaqa tekshirilmagan."));
        }
        final waiting = items.where((item) => item.pending).length;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            Row(children: <Widget>[
              Expanded(
                child: Text(
                  waiting > 0 ? tr('Yuborilishi kutilmoqda: {0}', <Object?>[waiting]) : tr("Hammasi serverga yuborilgan."),
                  style: TextStyle(color: AppColors.muted),
                ),
              ),
              if (waiting > 0)
                TextButton.icon(onPressed: queue.kick, icon: const Icon(Icons.cloud_upload_outlined), label: Text(tr('Yuborish')))
              else
                TextButton(
                  onPressed: () async {
                    if (await confirm(context, tr("Yuborilgan varaqalar telefondan o'chirilsinmi? Serverdagi natijalar saqlanadi."))) {
                      await queue.clearDone();
                    }
                  },
                  child: Text(tr('Tozalash')),
                ),
            ]),
            const SizedBox(height: 8),
            for (final item in items) ...<Widget>[
              Container(
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.line)),
                child: ScanResultCard(
                  item: item,
                  onTap: () {
                    final kit = item.examId == null ? null : KitStore.instance.cached(session.api, item.examId!);
                    showScanDetails(context, item, key: kit?.keyFor(item.variant));
                  },
                ),
              ),
              const SizedBox(height: 10),
            ],
          ],
        );
      },
    );
  }
}

class _ServerTab extends StatelessWidget {
  const _ServerTab({required this.status});

  final String? status;

  @override
  Widget build(BuildContext context) {
    final api = AppScope.read(context).api;
    return AsyncView<List<Map<String, dynamic>>>(
      load: () async => asList(await api.get('scans', query: <String, Object?>{'status': status})),
      builder: (context, scans, reload) {
        if (scans.isEmpty) {
          return ListView(children: <Widget>[
            EmptyState(
              icon: status == null ? Icons.inbox_outlined : Icons.task_alt,
              text: status == null ? tr("Hali varaqa tekshirilmagan.") : tr("Ko'rib chiqiladigan varaqa yo'q."),
            ),
          ]);
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: scans.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) => _ServerScanTile(scan: scans[index], onChanged: reload),
        );
      },
    );
  }
}

class _ServerScanTile extends StatelessWidget {
  const _ServerScanTile({required this.scan, required this.onChanged});

  final Map<String, dynamic> scan;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final status = asText(scan['status']);
    final style = scanStatusStyle(status == 'pending' ? ScanStatus.waiting : status);
    final attempt = asMap(scan['attempt']);
    final student = asMap(attempt['student']);
    final exam = asMap(scan['exam']);
    final result = asMap(scan['result']);
    final flags = ((result['flags'] as List?) ?? const <dynamic>[]).length;
    final name = student['full_name'] != null
        ? asText(student['full_name'])
        : (result['student_code'] != null ? '#${result['student_code']}' : tr("O'quvchi aniqlanmagan"));
    final subtitle = <String>[
      if (exam['title'] != null) asText(exam['title']),
      if (attempt.isNotEmpty) '${asInt(attempt['correct_count'])} ${tr("to'g'ri")} · ${number(asInt(attempt['score_x100']) / 100)} ${tr('ball')}',
      if (status == 'needs_review' && flags > 0) tr('{0} ta shubhali joy', <Object?>[flags]),
      if (scan['error'] != null) tr(asText(scan['error'])),
    ];
    return AppCard(
      onTap: status == 'needs_review' || status == 'processed'
          ? () async {
              await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ScanReviewPage(scanId: asInt(scan['id']))));
              await onChanged();
            }
          : null,
      child: Row(children: <Widget>[
        Icon(style.icon, color: style.color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(subtitle.join(' · '), style: TextStyle(color: AppColors.muted, fontSize: 13)),
            const SizedBox(height: 2),
            Text(dateTime(scan['created_at']), style: TextStyle(color: AppColors.muted, fontSize: 12)),
          ]),
        ),
        Pill(style.label, color: style.color),
      ]),
    );
  }
}
