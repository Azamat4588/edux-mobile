// 3.19: «Maktab hisoboti» (veb 2.43): davr bo'yicha davomat, o'rtacha baho, jurnal to'ldirilishi, sinflar, o'qituvchilar
// intizomi, eng ko'p dars qoldirganlar; xususiy maktabda (moliyaviy hisobot ruxsati bilan) — to'langan va qarz.
// API: GET school/reports/summary?from&to (direktor; administrator — «reports.school» ruxsati bilan).
import 'package:flutter/material.dart';

import '../../core/adaptive.dart';
import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

String _pct(dynamic value) => value == null ? '—' : '$value%';

Color _tone(dynamic value, {num good = 95, num ok = 85}) {
  if (value == null) return AppColors.muted;
  final v = value is num ? value : num.tryParse('$value') ?? 0;
  return v >= good ? AppColors.success : (v >= ok ? AppColors.warning : AppColors.danger);
}

class SchoolReportPage extends StatefulWidget {
  const SchoolReportPage({super.key});

  @override
  State<SchoolReportPage> createState() => _SchoolReportPageState();
}

class _SchoolReportPageState extends State<SchoolReportPage> {
  int _days = 30;
  GlobalKey<AsyncViewState<Map<String, dynamic>>> _view = GlobalKey<AsyncViewState<Map<String, dynamic>>>();

  Map<String, Object?> get _range {
    final now = DateTime.now();
    final from = _days == 0 ? DateTime(now.year, now.month) : now.subtract(Duration(days: _days - 1));
    return <String, Object?>{'from': isoDay(from), 'to': isoDay(now)};
  }

  @override
  Widget build(BuildContext context) {
    final api = AppScope.of(context).api;
    return Scaffold(
      appBar: pageBar(context, title: Text(tr('Maktab hisoboti'))),
      body: AsyncView<Map<String, dynamic>>(
        key: _view,
        cacheKey: 'school_report_$_days',
        decode: asMap,
        load: () async => asMap(await api.get('school/reports/summary', query: _range)),
        builder: (context, data, reload) {
          final totals = asMap(data['totals']);
          final finance = data['finance'] is Map ? asMap(data['finance']) : null;
          final debtById = finance == null ? <int, Map<String, dynamic>>{} : <int, Map<String, dynamic>>{
            for (final row in asList(finance['classes'], 'classes')) asInt(row['id']): row,
          };
          return ListView(
            padding: readable(context, const EdgeInsets.fromLTRB(16, 12, 16, 24)),
            children: <Widget>[
              Wrap(spacing: 8, children: <Widget>[
                for (final option in <(int, String)>[(0, 'Shu oy'), (7, 'Oxirgi 7 kun'), (30, 'Oxirgi 30 kun')])
                  ChoiceChip(
                    label: Text(tr(option.$2)),
                    selected: _days == option.$1,
                    onSelected: (_) => setState(() {
                      _days = option.$1;
                      _view = GlobalKey<AsyncViewState<Map<String, dynamic>>>();
                    }),
                  ),
              ]),
              const SizedBox(height: 12),
              StatGrid(children: <Widget>[
                StatCard(icon: Icons.groups_outlined, label: tr("Sinflar / o'quvchilar"), value: '${asInt(totals['classes'])} / ${asInt(totals['students'])}'),
                StatCard(icon: Icons.how_to_reg_outlined, label: tr('Davomat'), value: _pct(totals['attendance_rate']), color: _tone(totals['attendance_rate'])),
                StatCard(icon: Icons.grade_outlined, label: tr("O'rtacha baho"), value: asText(totals['avg_mark'], '—')),
                StatCard(icon: Icons.menu_book_outlined, label: tr("Jurnal to'ldirilishi"), value: _pct(totals['journal_fill']), color: _tone(totals['journal_fill'], good: 90, ok: 70)),
                if (finance != null)
                  StatCard(icon: Icons.account_balance_wallet_outlined, label: tr('Qarzdorlik'), value: money(asInt(asMap(finance['totals'])['debt'])), color: asInt(asMap(finance['totals'])['debt']) > 0 ? AppColors.danger : AppColors.success),
              ]),
              SectionTitle(tr('Sinflar')),
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(children: <Widget>[
                  for (final (i, row) in asList(data['classes'], 'classes').indexed) ...<Widget>[
                    if (i > 0) const Divider(height: 1),
                    ListTile(
                      title: Text(asText(row['name'])),
                      subtitle: Text(<String>[
                        tr('kelmadi {0} · kechikdi {1}', <Object?>[asInt(row['absent']), asInt(row['late'])]),
                        tr('Jurnal: {0}', <Object?>[_pct(row['journal_fill'])]),
                        if (debtById[asInt(row['id'])] != null) tr('Qarz: {0}', <Object?>[money(asInt(debtById[asInt(row['id'])]!['debt']))]),
                      ].join(' · ')),
                      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: <Widget>[
                        Text(_pct(row['attendance_rate']), style: TextStyle(fontWeight: FontWeight.w700, color: _tone(row['attendance_rate']))),
                        Text(asText(row['avg_mark'], '—'), style: TextStyle(color: AppColors.muted)),
                      ]),
                    ),
                  ],
                ]),
              ),
              SectionTitle(tr("O'qituvchilar: jurnal intizomi")),
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(children: <Widget>[
                  for (final (i, row) in asList(data['teachers'], 'teachers').indexed) ...<Widget>[
                    if (i > 0) const Divider(height: 1),
                    ListTile(
                      dense: true,
                      title: Text(asText(row['name'])),
                      subtitle: Text(tr('{0} dars · mavzusiz {1} · belgisiz {2}', <Object?>[asInt(row['lessons']), asInt(row['without_topic']), asInt(row['without_marks'])])),
                      trailing: Text(_pct(row['journal_fill']), style: TextStyle(fontWeight: FontWeight.w700, color: _tone(row['journal_fill'], good: 90, ok: 70))),
                    ),
                  ],
                ]),
              ),
              SectionTitle(tr("Eng ko'p dars qoldirganlar")),
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(children: <Widget>[
                  for (final (i, row) in asList(data['absentees'], 'absentees').indexed) ...<Widget>[
                    if (i > 0) const Divider(height: 1),
                    ListTile(
                      dense: true,
                      title: Text(asText(row['name'])),
                      subtitle: Text(asText(row['class'])),
                      trailing: Text(tr('{0} kelmadi · {1} kechikdi', <Object?>[asInt(row['absent']), asInt(row['late'])])),
                    ),
                  ],
                  if (asList(data['absentees'], 'absentees').isEmpty) Padding(padding: const EdgeInsets.all(16), child: Text(tr("Dars qoldirganlar yo'q."))),
                ]),
              ),
            ],
          );
        },
      ),
    );
  }
}
