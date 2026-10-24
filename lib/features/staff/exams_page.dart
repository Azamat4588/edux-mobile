// Testlar (xodim): ro'yxat, natijalar reytingi va shu test varaqalarini skanerlash.
import 'package:flutter/material.dart';

import '../../core/adaptive.dart';
import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/help_links.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../scanner/scanner_page.dart';

const Map<String, String> examStatusLabels = <String, String>{
  'draft': 'Qoralama',
  'published': "E'lon qilingan",
  'closed': 'Yopilgan',
};

Color examStatusColor(String status) {
  if (status == 'published') return AppColors.success;
  if (status == 'closed') return AppColors.brand;
  return AppColors.muted;
}

class ExamsPage extends StatelessWidget {
  const ExamsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final api = AppScope.of(context).api;
    return Scaffold(
      appBar: pageBar(context, title: Text(tr('Testlar')), actions: const <Widget>[HelpButton(HelpLinks.examResults)]),
      body: AsyncView<List<Map<String, dynamic>>>(
        cacheKey: 'exams',
        decode: (raw) => asList(raw),
        load: () async => asList(await api.get('exams')),
        builder: (context, exams, reload) {
          if (exams.isEmpty) {
            return ListView(children: <Widget>[EmptyState(text: tr("Hali test yo'q. Birinchisini yarating."))]);
          }
          return ListView.separated(
            padding: readable(context, const EdgeInsets.all(16)),
            itemCount: exams.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) => _ExamTile(exam: exams[index]),
          );
        },
      ),
    );
  }
}

class _ExamTile extends StatelessWidget {
  const _ExamTile({required this.exam});

  final Map<String, dynamic> exam;

  @override
  Widget build(BuildContext context) {
    final status = asText(exam['status']);
    final subject = asMap(exam['subject']);
    return AppCard(
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ExamDetailPage(exam: exam))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Row(children: <Widget>[
          Expanded(child: Text(asText(exam['title']), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
          Pill(tr(examStatusLabels[status] ?? status), color: examStatusColor(status)),
        ]),
        const SizedBox(height: 6),
        Text(
          <String>[
            if (subject['name'] != null) asText(subject['name']),
            if (exam['kind'] == 'key') tr('Tayyor test'),
            if (exam['questions_count'] != null) tr('{0} ta savol', <Object?>[asInt(exam['questions_count'])]),
            tr('{0} ta natija', <Object?>[asInt(exam['finished_attempts_count'])]),
          ].join(' · '),
          style: TextStyle(color: AppColors.muted),
        ),
      ]),
    );
  }
}

class ExamDetailPage extends StatelessWidget {
  const ExamDetailPage({super.key, required this.exam});

  final Map<String, dynamic> exam;

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context);
    final id = asInt(exam['id']);
    final status = asText(exam['status']);
    return Scaffold(
      appBar: pageBar(context, title: Text(asText(exam['title']), maxLines: 1, overflow: TextOverflow.ellipsis)),
      floatingActionButton: session.canScan && status != 'draft'
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => ScannerPage(examId: id, examTitle: asText(exam['title'])),
              )),
              icon: const Icon(Icons.document_scanner),
              label: Text(tr('Varaqalarni tekshirish')),
            )
          : null,
      body: AsyncView<Map<String, dynamic>>(
        cacheKey: 'exam_results_$id',
        decode: asMap,
        load: () async => asMap(await session.api.get('exams/$id/results')),
        builder: (context, data, reload) {
          final table = examResultsTable(data);
          final header = table.header;
          final body = table.rows;
          // Ustunlar tartibi server eksportida o'zgarmas: O'rin, Kod, F.I.Sh., Guruh, Variant, Turi, To'g'ri,
          // Noto'g'ri, Bo'sh, Ball, Maks. ball, Foiz (sarlavhalar tanlangan tilda kelishi mumkin).
          final nameIndex = header.length > 2 ? 2 : 0;
          final correctIndex = header.length > 6 ? 6 : -1;
          final scoreIndex = header.length > 9 ? 9 : -1;
          final percentIndex = header.length > 11 ? 11 : -1;
          return ListView(
            padding: readable(context, const EdgeInsets.fromLTRB(16, 16, 16, 96)),
            children: <Widget>[
              AppCard(
                child: Column(children: <Widget>[
                  KeyValue(tr('Holat'), tr(examStatusLabels[status] ?? status), valueColor: examStatusColor(status)),
                  if (exam['duration_minutes'] != null) KeyValue(tr('Vaqt (daqiqa)'), asText(exam['duration_minutes'])),
                  KeyValue(tr('Variantlar soni'), asText(exam['variants_count'])),
                  KeyValue(tr('Topshirganlar'), '${body.length}'),
                ]),
              ),
              SectionTitle(tr('Reyting')),
              if (body.isEmpty)
                AppCard(child: Text(tr("Hali hech kim topshirmagan. Onlayn topshirilgan yoki varaqadan tekshirilgan natijalar shu yerda darhol ko'rinadi."),
                    style: TextStyle(color: AppColors.muted)))
              else
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(children: <Widget>[
                    for (var i = 0; i < body.length; i++) ...<Widget>[
                      if (i > 0) const Divider(),
                      ListTile(
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: i < 3 ? AppColors.sun.withAlpha(90) : AppColors.surface,
                          child: Text('${i + 1}', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.ink)),
                        ),
                        title: Text(nameIndex < body[i].length ? body[i][nameIndex] : '—'),
                        subtitle: correctIndex >= 0 && correctIndex < body[i].length
                            ? Text('${tr("To'g'ri")}: ${body[i][correctIndex]}')
                            : null,
                        trailing: Text(
                          <String>[
                            if (scoreIndex >= 0 && scoreIndex < body[i].length) body[i][scoreIndex],
                            if (percentIndex >= 0 && percentIndex < body[i].length) '${body[i][percentIndex]}%',
                          ].join(' · '),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ]),
                ),
              const SizedBox(height: 8),
              Text(tr('Batafsil tahlil (savollar va mavzular kesimi) veb-versiyada.'),
                  textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 12)),
              if (exam['published_at'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('${tr("E'lon qilingan")}: ${date(exam['published_at'])}',
                      textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 12)),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// GET exams/{id}/results (server ResultsReport, eksport bilan bir xil): `Natijalar` varag'i — birinchi qator sarlavha.
/// Varaq kaliti har tilda `Natijalar`, sarlavhalar esa tanlangan tilda keladi. Toza mantiq — test/api_fixtures_test.dart.
({List<String> header, List<List<String>> rows}) examResultsTable(Map<String, dynamic> data) {
  final sheet = asRawList(data['Natijalar']).map(asRawList).toList();
  final header = sheet.isEmpty ? <String>[] : sheet.first.map((cell) => '${cell ?? ''}').toList();
  final rows = sheet.length < 2 ? <List<String>>[] : sheet.sublist(1).map((row) => row.map((cell) => '${cell ?? ''}').toList()).toList();
  return (header: header, rows: rows);
}
