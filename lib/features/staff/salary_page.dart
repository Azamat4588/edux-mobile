// «Maoshim» (3.15, o'qituvchi, CRM moduli): oy bo'yicha hisoblangan maosh, berilgani va qoldig'i, guruhlar kesimi va
// berilgan pullar. API: GET crm/my/salary?period=YYYY-MM → {period, salary: {total, base_salary, paid_out, remaining,
// groups: [...]}|null, payouts: [{amount, paid_on, note}]} (server: SalaryController@mine, organization:teacher).
import 'package:flutter/material.dart';

import '../../core/adaptive.dart';
import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

/// "2026-10" — oy kaliti (server Period formati).
String salaryPeriod(DateTime month) => '${month.year}-${two(month.month)}';

/// So'nggi [count] oy, joriysidan boshlab.
List<DateTime> salaryMonths(DateTime now, {int count = 12}) =>
    <DateTime>[for (var i = 0; i < count; i++) DateTime(now.year, now.month - i)];

class MySalaryPage extends StatefulWidget {
  const MySalaryPage({super.key});

  @override
  State<MySalaryPage> createState() => _MySalaryPageState();
}

class _MySalaryPageState extends State<MySalaryPage> {
  late final List<DateTime> _months = salaryMonths(DateTime.now());
  late DateTime _month = _months.first;

  @override
  Widget build(BuildContext context) {
    final api = AppScope.of(context).api;
    final period = salaryPeriod(_month);
    return Scaffold(
      appBar: pageBar(context, title: Text(tr('Maoshim'))),
      body: Column(children: <Widget>[
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            children: <Widget>[
              for (final month in _months)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(month.year == DateTime.now().year ? monthName(month.month) : '${monthName(month.month)} ${month.year}'),
                    selected: month == _month,
                    onSelected: (_) => setState(() => _month = month),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: AsyncView<Map<String, dynamic>>(
            key: ValueKey<String>(period),
            cacheKey: 'crm_my_salary_$period',
            decode: asMap,
            load: () async => asMap(await api.get('crm/my/salary', query: <String, Object?>{'period': period})),
            builder: (context, data, reload) {
              final salary = asMap(data['salary']);
              final payouts = asList(data['payouts'], 'payouts');
              final groups = asList(salary['groups'], 'groups');
              final total = asInt(salary['total']);
              final paid = asInt(salary['paid_out']);
              final remaining = salary.containsKey('remaining') ? asInt(salary['remaining']) : total - paid;
              final base = asInt(salary['base_salary']);
              if (salary.isEmpty && payouts.isEmpty) {
                return ListView(children: <Widget>[
                  EmptyState(icon: Icons.account_balance_wallet_outlined, text: tr('Bu oy uchun maosh hisoblanmagan.')),
                ]);
              }
              return ListView(
                padding: readable(context, const EdgeInsets.fromLTRB(16, 8, 16, 32)),
                children: <Widget>[
                  AppCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                      Text('${monthName(_month.month)} ${_month.year}', style: TextStyle(color: AppColors.muted)),
                      const SizedBox(height: 4),
                      Text(money(total), style: AppTheme.title(size: 26)),
                      const SizedBox(height: 8),
                      KeyValue(tr('Hisoblangan'), money(total)),
                      KeyValue(tr('Berilgan'), money(paid), valueColor: AppColors.success),
                      KeyValue(tr('Qoldiq'), money(remaining), valueColor: remaining > 0 ? AppColors.warning : AppColors.ink),
                    ]),
                  ),
                  if (groups.isNotEmpty || base > 0) ...<Widget>[
                    SectionTitle(tr('Hisob-kitob')),
                    AppCard(
                      padding: EdgeInsets.zero,
                      child: Column(children: <Widget>[
                        if (base > 0)
                          ListTile(
                            dense: true,
                            leading: Icon(Icons.badge_outlined, color: AppColors.muted),
                            title: Text(tr('Belgilangan oylik'), style: const TextStyle(fontWeight: FontWeight.w600)),
                            trailing: Text(money(base), style: const TextStyle(fontWeight: FontWeight.w700)),
                          ),
                        for (var i = 0; i < groups.length; i++) ...<Widget>[
                          if (i > 0 || base > 0) const Divider(height: 1),
                          ListTile(
                            dense: true,
                            leading: Icon(Icons.groups_2_outlined, color: AppColors.muted),
                            title: Text(asText(groups[i]['name']), style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text(<String>[
                              tr("{0} ta o'quvchi", <Object?>[asInt(groups[i]['students'])]),
                              tr('{0} ta dars', <Object?>[asInt(groups[i]['lessons'])]),
                              if (groups[i]['recorded_elsewhere'] == true) tr('boshqa oyda yozilgan'),
                            ].join(', ')),
                            trailing: Text(money(asInt(groups[i]['amount'])), style: const TextStyle(fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ]),
                    ),
                  ],
                  SectionTitle(tr('Berilgan pullar')),
                  if (payouts.isEmpty)
                    EmptyState(icon: Icons.payments_outlined, text: tr('Bu oy hali pul berilmagan.'))
                  else
                    AppCard(
                      padding: EdgeInsets.zero,
                      child: Column(children: <Widget>[
                        for (var i = 0; i < payouts.length; i++) ...<Widget>[
                          if (i > 0) const Divider(height: 1),
                          ListTile(
                            dense: true,
                            leading: Icon(Icons.payments_outlined, color: AppColors.success),
                            title: Text(money(asInt(payouts[i]['amount'])), style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text(<String>[
                              date(payouts[i]['paid_on']),
                              if (asText(payouts[i]['note']).isNotEmpty) asText(payouts[i]['note']),
                            ].join(' · ')),
                          ),
                        ],
                      ]),
                    ),
                ],
              );
            },
          ),
        ),
      ]),
    );
  }
}
