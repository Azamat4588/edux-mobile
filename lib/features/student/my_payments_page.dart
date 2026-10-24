// «To'lovlarim» (3.4.1, veb: my.payments): o'quvchining CRM kabineti — balans, hisoblangan oylik to'lovlar va to'langanlar,
// onlayn to'lash tugmasi. Manba: GET crm/me (balance, charges, payments) — internetsiz oxirgi nusxa ko'rinadi.
import 'package:flutter/material.dart';

import '../../core/adaptive.dart';
import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/help_links.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../staff/students_page.dart' show paymentMethods;
import 'online_pay.dart';

class MyPaymentsPage extends StatelessWidget {
  const MyPaymentsPage({super.key});

  /// Hisob nomi: guruh nomi, bo'lmasa izoh yoki «O'qish to'lovi».
  static String chargeTitle(Map<String, dynamic> charge) {
    final group = asText(asMap(charge['group'])['name']);
    if (group.isNotEmpty) return group;
    final description = asText(charge['description']);
    return description.isNotEmpty ? description : tr("O'qish to'lovi");
  }

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context);
    return Scaffold(
      appBar: pageBar(context, title: Text(tr("To'lovlarim")), actions: const <Widget>[HelpButton(HelpLinks.myPayments)]),
      body: AsyncView<Map<String, dynamic>>(
        cacheKey: 'crm_me',
        decode: asMap,
        load: () async => asMap(await session.api.get('crm/me')),
        builder: (context, data, reload) {
          final balance = asInt(data['balance']);
          final charges = asList(data['charges'], 'charges');
          final payments = asList(data['payments'], 'payments');
          final debt = balance < 0;
          return ListView(
            padding: readable(context, const EdgeInsets.fromLTRB(16, 14, 16, 32)),
            children: <Widget>[
              AppCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  Text(debt ? tr("To'lash kerak") : (balance > 0 ? tr("Oldindan to'langan") : tr("Qarz yo'q")), style: TextStyle(color: AppColors.muted)),
                  const SizedBox(height: 4),
                  Text(money(balance.abs()), style: AppTheme.title(size: 26, color: debt ? AppColors.danger : AppColors.success)),
                  if (!session.readOnly) ...<Widget>[
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => startOnlinePayment(context, suggested: debt ? -balance : 0, onDone: (paid) {
                        if (paid) reload();
                      }),
                      icon: const Icon(Icons.credit_card),
                      label: Text(tr("Onlayn to'lash")),
                    ),
                  ],
                ]),
              ),
              SectionTitle(tr('Hisoblangan')),
              if (charges.isEmpty)
                EmptyState(icon: Icons.receipt_outlined, text: tr("Hisoblangan to'lov yo'q."))
              else
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(children: <Widget>[
                    for (var i = 0; i < charges.length; i++) ...<Widget>[
                      if (i > 0) const Divider(),
                      ListTile(
                        dense: true,
                        leading: Icon(Icons.receipt_outlined, color: AppColors.muted),
                        title: Text(chargeTitle(charges[i]), style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(<String>[
                          asText(charges[i]['period']),
                          if (asText(charges[i]['due_on']).isNotEmpty) tr('muddat: {0}', <Object?>[date(charges[i]['due_on'])]),
                        ].where((item) => item.isNotEmpty).join(' · ')),
                        trailing: Text(money(asInt(charges[i]['amount'])), style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ]),
                ),
              SectionTitle(tr("So'nggi to'lovlar")),
              if (payments.isEmpty)
                EmptyState(icon: Icons.payments_outlined, text: tr("Hali to'lov qilinmagan."))
              else
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(children: <Widget>[
                    for (var i = 0; i < payments.length; i++) ...<Widget>[
                      if (i > 0) const Divider(),
                      ListTile(
                        dense: true,
                        leading: Icon(Icons.check_circle_outline, color: AppColors.success),
                        title: Text(money(asInt(payments[i]['amount'])), style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(<String>[
                          dateTime(payments[i]['paid_at']),
                          tr(paymentMethods[payments[i]['method']] ?? asText(payments[i]['method'])),
                        ].join(' · ')),
                        trailing: payments[i]['receipt'] != null
                            ? Text(asText(payments[i]['receipt']), style: TextStyle(color: AppColors.muted, fontSize: 12))
                            : null,
                      ),
                    ],
                  ]),
                ),
            ],
          );
        },
      ),
    );
  }
}
