// O'quvchi sertifikatlari va mock imtihon natijalari tarixi (o'sish).
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'my_tests_page.dart';

class CertificatesPage extends StatelessWidget {
  const CertificatesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Sertifikatlar'))),
      body: AsyncView<List<Map<String, dynamic>>>(
        cacheKey: 'my_certificates',
        decode: (raw) => asList(raw),
        load: () async => asList(await session.api.get('my/certificates')),
        builder: (context, items, reload) {
          if (items.isEmpty) {
            return ListView(children: <Widget>[
              EmptyState(text: tr("Hali sertifikat yo'q. Imtihon yoki kursni muvaffaqiyatli tugatsangiz, shu yerda paydo bo'ladi."), icon: Icons.workspace_premium_outlined),
            ]);
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final item = items[index];
              final url = session.api.absolute('/c/${asText(item['code'])}');
              return AppCard(
                onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
                child: Row(children: <Widget>[
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(gradient: const LinearGradient(colors: <Color>[Color(0xFFFFD36B), Color(0xFFFFB020)]), borderRadius: BorderRadius.circular(14)),
                    child: const Icon(Icons.workspace_premium, color: Color(0xFF5B3A00), size: 28),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                      Text(asText(item['title']), style: const TextStyle(fontWeight: FontWeight.w700)),
                      if (asText(item['subtitle']).isNotEmpty) Text(asText(item['subtitle']), style: TextStyle(color: AppColors.muted, fontSize: 13)),
                      const SizedBox(height: 4),
                      Text('№ ${asText(item['number'])} · ${date(item['issued_at'])}', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                    ]),
                  ),
                  Icon(Icons.open_in_new, color: AppColors.muted, size: 20),
                ]),
              );
            },
          );
        },
      ),
    );
  }
}

class MockProgressPage extends StatelessWidget {
  const MockProgressPage({super.key});

  @override
  Widget build(BuildContext context) {
    final api = AppScope.of(context).api;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Mock natijalari'))),
      body: AsyncView<List<Map<String, dynamic>>>(
        cacheKey: 'my_mock',
        decode: (raw) => asList(raw),
        load: () async => asList(asMap(await api.get('my/mock'))['items'], 'items'),
        builder: (context, items, reload) {
          if (items.isEmpty) {
            return ListView(children: <Widget>[EmptyState(text: tr('Hali mock imtihon topshirilmagan.'), icon: Icons.emoji_events_outlined)]);
          }
          final list = items.reversed.toList();
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final item = list[index];
              final result = asMap(item['result']);
              final previous = index + 1 < list.length ? asMap(list[index + 1]['result']) : <String, dynamic>{};
              return AppCard(
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AttemptResultPage(attemptId: asInt(item['attempt_id'])))),
                child: MockResultSummary(
                  title: asText(asMap(item['exam'])['title']),
                  subtitle: '${asText(item['format_label'])} · ${date(item['finished_at'])}',
                  result: result,
                  previous: previous,
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Mock natijasi: umumiy ball (band, daraja), bo'limlar va oldingisiga nisbatan o'zgarish.
class MockResultSummary extends StatelessWidget {
  const MockResultSummary({super.key, required this.result, this.title, this.subtitle, this.previous = const <String, dynamic>{}});

  final Map<String, dynamic> result;
  final Map<String, dynamic> previous;
  final String? title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final overall = asMap(result['overall']);
    final label = asText(overall['label'], '—');
    final level = asText(result['level']);
    final sections = asList(result['sections'], 'sections');
    final now = overall['value'];
    final before = asMap(previous['overall'])['value'];
    final delta = now is num && before is num ? now - before : null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      if (title != null) Text(title!, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      if (subtitle != null) Text(subtitle!, style: TextStyle(color: AppColors.muted, fontSize: 12)),
      if (title != null) const SizedBox(height: 10),
      Row(children: <Widget>[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(gradient: AppColors.gradient, borderRadius: BorderRadius.circular(14)),
          child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 20)),
        ),
        const SizedBox(width: 10),
        if (level.isNotEmpty) Pill(tr(level), color: AppColors.success),
        const Spacer(),
        if (delta != null && delta != 0)
          Text('${delta > 0 ? '+' : ''}${number(delta)}',
              style: TextStyle(fontWeight: FontWeight.w700, color: delta > 0 ? AppColors.success : AppColors.danger)),
      ]),
      if (result['pending'] == true) ...<Widget>[
        const SizedBox(height: 8),
        Text(tr("Ba'zi bo'limlarni o'qituvchi hali baholamagan — natija keyin yangilanadi."), style: TextStyle(color: AppColors.warning, fontSize: 13)),
      ],
      if (sections.isNotEmpty) ...<Widget>[
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 6, children: <Widget>[
          for (final section in sections)
            Pill('${tr(asText(section['name']))}: ${section['label'] == null ? tr('baholanmoqda') : asText(section['label'])}', color: AppColors.brand),
        ]),
      ],
    ]);
  }
}
