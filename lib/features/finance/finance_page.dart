// Moliya (3.1): bugungi to'lovlar va kassa, qarzdorlar (qo'ng'iroq, SMS, eslatma, to'lov qabul qilish),
// oddiy hisobotlar — joriy oy kunlari va oxirgi 12 oy bo'yicha tushum. So'rovlar FinanceRepository orqali.
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../staff/payment_sheet.dart';
import '../staff/students_page.dart';
import 'finance_repository.dart';

class FinancePage extends StatefulWidget {
  const FinancePage({super.key, this.initialTab = 0});

  /// 0 — Bugun, 1 — Qarzdorlar, 2 — Hisobot.
  final int initialTab;

  @override
  State<FinancePage> createState() => _FinancePageState();
}

class _FinancePageState extends State<FinancePage> {
  late final FinanceRepository _repository = FinanceRepository(AppScope.read(context));
  final GlobalKey<AsyncViewState<Map<String, dynamic>>> _todayView = GlobalKey<AsyncViewState<Map<String, dynamic>>>();

  Future<void> _acceptPayment() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const StudentsPage(forPayment: true)));
    if (mounted) await _todayView.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      initialIndex: widget.initialTab.clamp(0, 2),
      child: Scaffold(
        appBar: AppBar(
          title: Text(tr('Moliya')),
          bottom: TabBar(tabs: <Widget>[Tab(text: tr('Bugun')), Tab(text: tr('Qarzdorlar')), Tab(text: tr('Hisobot'))]),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _acceptPayment,
          icon: const Icon(Icons.payments),
          label: Text(tr("To'lov qabul qilish")),
        ),
        body: TabBarView(children: <Widget>[
          _TodayTab(viewKey: _todayView, repository: _repository),
          _DebtorsTab(repository: _repository, onPaid: () => _todayView.currentState?.reload()),
          _ReportsTab(repository: _repository),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bugun
// ---------------------------------------------------------------------------

class _TodayTab extends StatelessWidget {
  const _TodayTab({required this.viewKey, required this.repository});

  final GlobalKey<AsyncViewState<Map<String, dynamic>>> viewKey;
  final FinanceRepository repository;

  Future<Map<String, dynamic>> _load() async {
    final today = FinanceRepository.today;
    final results = await Future.wait<dynamic>(<Future<dynamic>>[
      repository.payments(from: today, to: today),
      // Kassa bo'limi bo'lmasa ham to'lovlar ko'rinsin
      repository.cash(from: today, to: today).catchError((Object _) => <String, dynamic>{}),
    ]);
    return <String, dynamic>{'payments': asMap(results[0]), 'cash': asMap(results[1])};
  }

  @override
  Widget build(BuildContext context) {
    return AsyncView<Map<String, dynamic>>(
      key: viewKey,
      load: _load,
      skeleton: const SkeletonList(header: true, count: 4),
      builder: (context, data, reload) {
        final payments = asMap(data['payments']);
        final summary = asMap(payments['summary']);
        final items = asList(payments);
        final accounts = asList(asMap(data['cash'])['accounts'], 'accounts');
        final byMethod = <String, int>{};
        for (final payment in items) {
          if (payment['voided_at'] != null) continue;
          final method = asText(payment['method']);
          byMethod[method] = (byMethod[method] ?? 0) + asInt(payment['amount']);
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.l, AppSpacing.l, AppSpacing.l, 96),
          children: <Widget>[
            StatGrid(children: <Widget>[
              StatCard(
                label: tr('Bugungi tushum'),
                value: groupDigits(asInt(summary['amount'])),
                icon: Icons.payments_outlined,
                color: AppColors.success,
                hint: tr("so'm"),
              ),
              StatCard(
                label: tr("To'lovlar soni"),
                value: '${asInt(summary['count'])}',
                icon: Icons.receipt_long_outlined,
              ),
            ]),
            if (byMethod.isNotEmpty)
              AppCard(
                child: Column(children: <Widget>[
                  for (final entry in byMethod.entries) KeyValue(tr(paymentMethods[entry.key] ?? entry.key), money(entry.value)),
                ]),
              ),
            if (accounts.isNotEmpty) ...<Widget>[
              SectionTitle(tr('Kassalar')),
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(children: <Widget>[
                  for (var i = 0; i < accounts.length; i++) ...<Widget>[
                    if (i > 0) const Divider(),
                    _CashRow(account: accounts[i]),
                  ],
                ]),
              ),
            ],
            SectionTitle(tr("Bugungi to'lovlar")),
            if (items.isEmpty)
              AppCard(child: EmptyState(icon: Icons.receipt_long_outlined, text: tr("Bugun hali to'lov qabul qilinmagan.")))
            else
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(children: <Widget>[
                  for (var i = 0; i < items.length; i++) ...<Widget>[
                    if (i > 0) const Divider(indent: 72),
                    _PaymentRow(payment: items[i]),
                  ],
                ]),
              ),
            if (asInt(payments['total'], items.length) > items.length)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.m),
                child: Text(tr("Yana {0} ta to'lov — to'liq ro'yxat veb-versiyada.", <Object?>[asInt(payments['total']) - items.length]),
                    textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
              ),
          ],
        );
      },
    );
  }
}

class _CashRow extends StatelessWidget {
  const _CashRow({required this.account});

  final Map<String, dynamic> account;

  @override
  Widget build(BuildContext context) {
    final shift = asMap(account['open_shift']);
    return ListTile(
      leading: Icon(asText(account['kind']) == 'cash' ? Icons.point_of_sale_outlined : Icons.account_balance_outlined),
      title: Text(asText(account['name']), style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(<String>[
        '+${groupDigits(asInt(account['in']))}',
        '−${groupDigits(asInt(account['out']))}',
        if (shift.isNotEmpty) tr('smena ochiq'),
      ].join(' · ')),
      trailing: Text(money(asInt(account['balance'])), style: const TextStyle(fontWeight: FontWeight.w800)),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({required this.payment});

  final Map<String, dynamic> payment;

  @override
  Widget build(BuildContext context) {
    final student = asMap(payment['student']);
    final voided = payment['voided_at'] != null;
    final paid = parseDate(payment['paid_at']);
    final session = AppScope.of(context);
    return ListTile(
      onTap: student['id'] == null || !session.canSeeStudents
          ? null
          : () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => StudentCardPage(studentId: asInt(student['id']), name: asText(student['full_name'])),
              )),
      leading: Avatar(asText(student['full_name'], '?')),
      title: Text(asText(student['full_name'], '—'),
          style: TextStyle(fontWeight: FontWeight.w600, decoration: voided ? TextDecoration.lineThrough : null)),
      subtitle: Text(<String>[
        if (paid != null) '${two(paid.hour)}:${two(paid.minute)}',
        tr(paymentMethods[asText(payment['method'])] ?? asText(payment['method'])),
        if (asText(payment['receipt']).isNotEmpty) '№${asText(payment['receipt'])}',
        if (asText(asMap(payment['receiver'])['name']).isNotEmpty) asText(asMap(payment['receiver'])['name']),
      ].join(' · ')),
      trailing: Text(
        voided ? tr('Bekor qilingan') : money(asInt(payment['amount'])),
        style: TextStyle(fontWeight: FontWeight.w700, color: voided ? AppColors.muted : AppColors.success),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Qarzdorlar
// ---------------------------------------------------------------------------

class _DebtorsTab extends StatefulWidget {
  const _DebtorsTab({required this.repository, required this.onPaid});

  final FinanceRepository repository;
  final VoidCallback onPaid;

  @override
  State<_DebtorsTab> createState() => _DebtorsTabState();
}

class _DebtorsTabState extends State<_DebtorsTab> with AutomaticKeepAliveClientMixin {
  final List<Map<String, dynamic>> _items = <Map<String, dynamic>>[];
  int _page = 1;
  int _lastPage = 1;
  int _count = 0;
  int _totalDebt = 0;
  bool _loading = true;
  bool _more = false;
  Object? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    setState(() {
      if (more) {
        _more = true;
      } else {
        _loading = true;
      }
      _error = null;
    });
    try {
      final page = more ? _page + 1 : 1;
      final data = await widget.repository.debtors(page: page);
      if (!mounted) return;
      setState(() {
        if (!more) _items.clear();
        _items.addAll(asList(data));
        _page = asInt(data['current_page'], page);
        _lastPage = asInt(data['last_page'], page);
        _count = asInt(data['count'], _items.length);
        _totalDebt = asInt(data['total_debt']);
      });
    } catch (error) {
      if (!mounted) return;
      if (more) {
        showMessage(context, errorText(error), error: true);
      } else {
        setState(() => _error = error);
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _more = false;
        });
      }
    }
  }

  Future<void> _remind(Map<String, dynamic> debtor) async {
    try {
      final result = await widget.repository.remind(<int>[asInt(debtor['id'])]);
      if (!mounted) return;
      final telegram = asInt(result['queued']);
      final sms = asInt(result['sms']);
      if (telegram + sms > 0) {
        showMessage(context, tr('Eslatma yuborildi: Telegram — {0}, SMS — {1}', <Object?>[telegram, sms]));
      } else if (asInt(result['recently_reminded']) > 0) {
        showMessage(context, tr('Bu ota-onaga yaqinda eslatma yuborilgan.'), error: true);
      } else {
        showMessage(context, tr('Eslatma yuborilmadi: ota-ona Telegram botga ulanmagan va SMS shabloni yoqilmagan.'), error: true);
      }
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    }
  }

  Future<void> _pay(Map<String, dynamic> debtor) async {
    final paid = await showPaymentSheet(context, studentId: asInt(debtor['id']), studentName: asText(debtor['full_name']));
    if (paid == true && mounted) {
      widget.onPaid();
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final error = _error;
    if (_loading && _items.isEmpty) return const SkeletonList();
    if (error != null && _items.isEmpty) {
      if (error is ApiException && error.isForbidden) return ForbiddenState(details: error.message, onRetry: _load);
      return ErrorState(message: errorText(error), onRetry: _load);
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.l, AppSpacing.l, AppSpacing.l, 96),
        children: <Widget>[
          StatGrid(children: <Widget>[
            StatCard(label: tr('Qarzdorlar'), value: '$_count', icon: Icons.warning_amber_rounded, color: AppColors.danger),
            StatCard(label: tr('Umumiy qarz'), value: groupDigits(_totalDebt), icon: Icons.account_balance_wallet_outlined, color: AppColors.danger, hint: tr("so'm")),
          ]),
          if (_items.isEmpty)
            EmptyState(icon: Icons.verified_outlined, text: tr("Qarzdor yo'q. Hamma to'lovlar o'z vaqtida.")),
          for (final debtor in _items) ...<Widget>[
            _DebtorCard(debtor: debtor, onRemind: () => _remind(debtor), onPay: () => _pay(debtor)),
            const SizedBox(height: AppSpacing.s),
          ],
          if (_page < _lastPage)
            Center(
              child: _more
                  ? const Padding(padding: EdgeInsets.all(AppSpacing.l), child: CircularProgressIndicator())
                  : OutlinedButton(onPressed: () => _load(more: true), child: Text(tr('Yana yuklash'))),
            ),
        ],
      ),
    );
  }
}

class _DebtorCard extends StatelessWidget {
  const _DebtorCard({required this.debtor, required this.onRemind, required this.onPay});

  final Map<String, dynamic> debtor;
  final VoidCallback onRemind;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    final phone = asText(debtor['phone']).replaceAll(RegExp(r'[^+\d]'), '');
    final groups = ((debtor['groups'] as List?) ?? const <dynamic>[]).join(', ');
    final session = AppScope.of(context);
    return AppCard(
      onTap: session.canSeeStudents
          ? () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => StudentCardPage(studentId: asInt(debtor['id']), name: asText(debtor['full_name'])),
              ))
          : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Row(children: <Widget>[
          Avatar(asText(debtor['full_name'], '?'), color: AppColors.danger),
          const SizedBox(width: AppSpacing.m),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text(asText(debtor['full_name']), style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(
                <String>[
                  if (groups.isNotEmpty) groups,
                  debtor['last_paid_at'] != null ? tr("Oxirgi to'lov: {0}", <Object?>[date(debtor['last_paid_at'])]) : tr("To'lov qilmagan"),
                ].join(' · '),
                style: TextStyle(color: AppColors.muted, fontSize: 13),
              ),
            ]),
          ),
          Text(money(-asInt(debtor['debt'])), style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.danger)),
        ]),
        const SizedBox(height: AppSpacing.m),
        Row(children: <Widget>[
          IconButton.outlined(
            tooltip: tr("Qo'ng'iroq"),
            onPressed: phone.isEmpty ? null : () => launchUrl(Uri.parse('tel:$phone')),
            icon: const Icon(Icons.call_outlined),
          ),
          const SizedBox(width: AppSpacing.xs),
          IconButton.outlined(
            tooltip: tr('SMS'),
            onPressed: phone.isEmpty ? null : () => launchUrl(Uri.parse('sms:$phone')),
            icon: const Icon(Icons.sms_outlined),
          ),
          const SizedBox(width: AppSpacing.xs),
          IconButton.outlined(
            tooltip: tr('Eslatma yuborish (Telegram/SMS)'),
            onPressed: onRemind,
            icon: const Icon(Icons.notifications_active_outlined),
          ),
          const Spacer(),
          FilledButton(onPressed: session.readOnly ? null : onPay, child: Text(tr("To'lov"))),
        ]),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Hisobot
// ---------------------------------------------------------------------------

class _ReportsTab extends StatelessWidget {
  const _ReportsTab({required this.repository});

  final FinanceRepository repository;

  Future<Map<String, dynamic>> _load() async {
    final now = DateTime.now();
    final results = await Future.wait<dynamic>(<Future<dynamic>>[
      repository.summary(from: isoDay(DateTime(now.year, now.month, 1)), to: isoDay(now)),
      repository.monthly(),
    ]);
    return <String, dynamic>{'summary': asMap(results[0]), 'monthly': results[1]};
  }

  @override
  Widget build(BuildContext context) {
    return AsyncView<Map<String, dynamic>>(
      load: _load,
      skeleton: const SkeletonList(header: true, count: 3),
      builder: (context, data, reload) {
        final summary = asMap(data['summary']);
        final income = asMap(summary['income']);
        final expenses = asMap(summary['expenses']);
        final debt = asMap(summary['debt']);
        final days = asList(income['by_day'], 'by_day');
        final methods = asList(income['by_method'], 'by_method').where((item) => asInt(item['value']) > 0).toList();
        final months = data['monthly'] is List ? asList(data['monthly']) : <Map<String, dynamic>>[];
        final now = DateTime.now();
        return ListView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.l, AppSpacing.l, AppSpacing.l, 96),
          children: <Widget>[
            Text('${monthName(now.month)} ${now.year}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.ink)),
            const SizedBox(height: AppSpacing.m),
            StatGrid(children: <Widget>[
              StatCard(label: tr('Tushum'), value: groupDigits(asInt(income['total'])), icon: Icons.trending_up_rounded, color: AppColors.success, hint: tr("{0} ta to'lov", <Object?>[asInt(income['count'])])),
              StatCard(label: tr('Xarajat'), value: groupDigits(asInt(expenses['total'])), icon: Icons.trending_down_rounded, color: AppColors.warning),
              StatCard(
                label: tr('Foyda'),
                value: groupDigits(asInt(summary['profit'])),
                icon: Icons.account_balance_outlined,
                color: asInt(summary['profit']) < 0 ? AppColors.danger : AppColors.brand,
              ),
              StatCard(
                label: tr('Qarz'),
                value: groupDigits(asInt(debt['total'])),
                icon: Icons.warning_amber_rounded,
                color: AppColors.danger,
                hint: tr('{0} ta o\'quvchi', <Object?>[asInt(debt['students'])]),
              ),
            ]),
            if (methods.isNotEmpty)
              AppCard(
                child: Column(children: <Widget>[
                  for (final method in methods)
                    KeyValue(tr(paymentMethods[asText(method['key'])] ?? asText(method['label'])), money(asInt(method['value']))),
                ]),
              ),
            SectionTitle(tr('Kunlar bo\'yicha tushum')),
            if (days.isEmpty)
              AppCard(child: Text(tr("Bu oyda hali to'lov yo'q."), style: TextStyle(color: AppColors.muted)))
            else
              AppCard(
                child: _Bars(
                  rows: days.reversed
                      .map((day) => _BarRow(_short(date(day['date']), 5), asInt(day['amount']), AppColors.success))
                      .toList(),
                ),
              ),
            if (months.isNotEmpty) ...<Widget>[
              SectionTitle(tr("Oylar bo'yicha (12 oy)")),
              AppCard(
                child: _Bars(
                  rows: months.reversed.map((month) => _BarRow(_monthLabel(asText(month['period'])), asInt(month['income']), AppColors.brand,
                      secondary: asInt(month['expenses']))).toList(),
                  legend: true,
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  /// "2026-10" → "Oktabr 2026"
  static String _monthLabel(String period) {
    final parts = period.split('-');
    if (parts.length != 2) return period;
    final month = int.tryParse(parts[1]) ?? 0;
    return month < 1 ? period : '${_short(monthName(month), 3)} ${parts[0]}';
  }

  static String _short(String text, int length) => text.length > length ? text.substring(0, length) : text;
}

class _BarRow {
  const _BarRow(this.label, this.value, this.color, {this.secondary});

  final String label;
  final int value;
  final Color color;

  /// Ikkinchi ustun (xarajat) — ixtiyoriy.
  final int? secondary;
}

/// Oddiy gorizontal ustunlar (qo'shimcha kutubxonasiz).
class _Bars extends StatelessWidget {
  const _Bars({required this.rows, this.legend = false});

  final List<_BarRow> rows;
  final bool legend;

  @override
  Widget build(BuildContext context) {
    var max = 1;
    for (final row in rows) {
      if (row.value > max) max = row.value;
      final secondary = row.secondary;
      if (secondary != null && secondary > max) max = secondary;
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      if (legend) ...<Widget>[
        Row(children: <Widget>[
          _Dot(color: AppColors.brand),
          const SizedBox(width: AppSpacing.xs),
          Text(tr('Tushum'), style: TextStyle(fontSize: 12, color: AppColors.muted)),
          const SizedBox(width: AppSpacing.m),
          const _Dot(color: AppColors.warning),
          const SizedBox(width: AppSpacing.xs),
          Text(tr('Xarajat'), style: TextStyle(fontSize: 12, color: AppColors.muted)),
        ]),
        const SizedBox(height: AppSpacing.s),
      ],
      for (final row in rows)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: <Widget>[
            SizedBox(width: 72, child: Text(row.label, style: TextStyle(fontSize: 12.5, color: AppColors.muted))),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                _Bar(fraction: row.value / max, color: row.color),
                if (row.secondary != null) ...<Widget>[
                  const SizedBox(height: 3),
                  _Bar(fraction: row.secondary! / max, color: AppColors.warning),
                ],
              ]),
            ),
            const SizedBox(width: AppSpacing.s),
            SizedBox(
              width: 92,
              child: Text(groupDigits(row.value), textAlign: TextAlign.end, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
    ]);
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.fraction, required this.color});

  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Container(
        height: 10,
        color: AppColors.line.withAlpha(120),
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(widthFactor: fraction.clamp(0.0, 1.0), child: Container(color: color)),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) =>
      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
}
