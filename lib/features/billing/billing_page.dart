// «Modullar va obuna» (3.2; direktor va administrator, ko'p tashkilotli platformada) — veb Billing sahifasi bilan bir xil
// mantiq (server 1.28+ tariflar, docs/tariffs.md):
//   GET  billing                              — holat, limitlar (usage), modullar (module_states), qo'shimchalar (addon_states),
//                                               paketlar (plans), to'lov davrlari (cycles: {monthly: 0, quarterly: 5, ...}),
//                                               hisoblar (invoices), to'lov usullari (providers)
//   POST billing/quote                        — {plan_code | modules, addons, cycle} → {items, total}
//   POST billing/invoices                     — keyingi davr hisobi
//   POST billing/addons                       — to'langan davr o'rtasida qo'shimcha (qolgan kunlar uchun hisob)
//   POST billing/invoices/{id}/pay/{provider} — click | payme → {redirect_url}; manual → {message, bank_details}
// Sinov davrida modullarni tanlash va hisobni chop etish — veb-versiyada.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

/// To'lov davrlari (veb: CYCLE_LABELS).
const Map<String, String> cycleLabels = <String, String>{
  'monthly': 'Oylik',
  'quarterly': '3 oylik',
  'semiannual': '6 oylik',
  'yearly': 'Yillik',
};

/// Obuna holati (veb: SUBSCRIPTION_STATUS).
const Map<String, String> subscriptionLabels = <String, String>{
  'trial': 'Sinov muddati',
  'active': 'Faol',
  'past_due': "Muddati o'tgan",
  'read_only': "Faqat o'qish",
};

/// Hisob holati (veb: INVOICE_STATUS).
const Map<String, String> invoiceLabels = <String, String>{
  'open': "To'lanmagan",
  'paid': "To'langan",
  'void': 'Bekor qilingan',
};

/// Qo'shimcha qayerdan ochiq (server: addon_states[].source).
const Map<String, String> addonSourceLabels = <String, String>{
  'included': 'Tarifga kiritilgan',
  'plan': 'Paketda',
  'bought': 'Sotib olingan',
  'free': 'Bepul berilgan',
  'trial': 'Sinov davrida',
  'none': "Yo'q",
};

/// Limitlar (server: usage.{key} = {used, limit}).
const Map<String, String> usageLabels = <String, String>{
  'students': "O'quvchilar",
  'staff': 'Xodimlar',
  'branches': 'Filiallar',
  'ai_monthly': 'AI javoblari (shu oy)',
  'sms_monthly': 'SMS (shu oy)',
};

Color subscriptionColor(String status) {
  if (status == 'active') return AppColors.success;
  if (status == 'past_due') return AppColors.warning;
  if (status == 'read_only') return AppColors.danger;
  return AppColors.brand;
}

/// Hisob qatori serverda o'zbekcha saqlanadi ("O'quvchilar: 50 gacha", "CRM (12 kun)") — tanish andozalar tarjima qilinadi
/// (veb: lib/billingLines.js).
String billingLine(String text) {
  RegExpMatch? match = RegExp(r"^O'quvchilar: (.+)$").firstMatch(text);
  if (match != null) return tr("O'quvchilar: {0}", <Object?>[billingTier(match.group(1)!)]);
  match = RegExp(r"^Yillik to'lov chegirmasi \((\d+)%\)$").firstMatch(text);
  if (match != null) return tr("Yillik to'lov chegirmasi ({0}%)", <Object?>[match.group(1)]);
  match = RegExp(r"^(3 oylik|6 oylik) to'lov chegirmasi \((\d+)%\)$").firstMatch(text);
  if (match != null) return tr("{0} to'lov chegirmasi ({1}%)", <Object?>[tr(match.group(1)!), match.group(2)]);
  match = RegExp(r'^Paket: (.+)$').firstMatch(text);
  if (match != null) return tr('Paket: {0}', <Object?>[match.group(1)]);
  match = RegExp(r"^Qo'shimcha o'quvchilar: (\d+) ta$").firstMatch(text);
  if (match != null) return tr("Qo'shimcha o'quvchilar: {0} ta", <Object?>[match.group(1)]);
  match = RegExp(r'^Shaxsiy chegirma \((\d+)%\)$').firstMatch(text);
  if (match != null) return tr('Shaxsiy chegirma ({0}%)', <Object?>[match.group(1)]);
  match = RegExp(r'^(.+) — bepul$').firstMatch(text);
  if (match != null) return tr('{0} — bepul', <Object?>[tr(match.group(1)!)]);
  match = RegExp(r'^(.+) \((\d+) kun\)$').firstMatch(text);
  if (match != null) return tr('{0} ({1} kun)', <Object?>[tr(match.group(1)!), match.group(2)]);
  return tr(text);
}

String billingTier(String label) {
  RegExpMatch? match = RegExp(r'^(\d+) gacha$').firstMatch(label);
  if (match != null) return tr('{0} gacha', <Object?>[match.group(1)]);
  match = RegExp(r"^(\d+) dan ko'p$").firstMatch(label);
  if (match != null) return tr("{0} dan ko'p", <Object?>[match.group(1)]);
  return tr(label);
}

int daysLeft(Object? value) {
  final day = parseDate(value);
  if (day == null) return 0;
  final now = DateTime.now();
  final diff = DateTime(day.year, day.month, day.day).difference(DateTime(now.year, now.month, now.day)).inDays;
  return diff < 0 ? 0 : diff;
}

class BillingRepository {
  BillingRepository(this.session);

  final Session session;

  Api get _api => session.api;

  Future<Map<String, dynamic>> show() async => asMap(await _api.get('billing'));

  Future<Map<String, dynamic>> quote(Map<String, Object?> body) async => asMap(await _api.post('billing/quote', body));

  Future<Map<String, dynamic>> issue(Map<String, Object?> body) async => asMap(await _api.post('billing/invoices', body));

  Future<Map<String, dynamic>> addAddon(String addon) async =>
      asMap(await _api.post('billing/addons', <String, Object?>{'addons': <String>[addon]}));

  Future<Map<String, dynamic>> pay(int invoiceId, String provider) async =>
      asMap(await _api.post('billing/invoices/$invoiceId/pay/$provider'));
}

class BillingPage extends StatefulWidget {
  const BillingPage({super.key});

  @override
  State<BillingPage> createState() => _BillingPageState();
}

class _BillingPageState extends State<BillingPage> with WidgetsBindingObserver {
  late final BillingRepository _repository = BillingRepository(AppScope.read(context));
  Map<String, dynamic>? _billing;
  Object? _error;
  bool _loading = true;

  // Keyingi davr tanlovi (veb bilan bir xil boshlang'ich qiymatlar).
  String _mode = 'modules';
  String? _planCode;
  final Set<String> _modules = <String>{};
  final Set<String> _addons = <String>{};
  String _cycle = 'monthly';

  Map<String, dynamic>? _quote;
  String? _quoteError;
  bool _quoting = false;
  int _quoteRequest = 0;
  Timer? _quoteTimer;

  bool _issuing = false;
  String? _busy;
  Map<String, dynamic>? _bankNote;

  /// Click/Payme sahifasi ochilgan: ilovaga qaytilganda holat yangilanadi.
  bool _awaitingPayment = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(initial: true));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _quoteTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _awaitingPayment) {
      _awaitingPayment = false;
      _load();
      // Obuna holati (faqat o'qish → faol) butun ilovada yangilansin.
      AppScope.read(context).loadContext().catchError((Object _) {});
    }
  }

  Future<void> _load({bool initial = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _repository.show();
      if (!mounted) return;
      setState(() {
        _billing = data;
        _loading = false;
        if (initial) _initSelection(data);
      });
      if (initial) _refreshQuote();
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _loading = false;
        });
      }
    }
  }

  /// Boshlang'ich tanlov: obuna rejasidagi modullar, bo'lmasa to'langanlari, bo'lmasa birinchi modul; paket rejimi — sozlamaga qarab.
  void _initSelection(Map<String, dynamic> data) {
    final available = asList(data['available_modules']).map((item) => asText(item['module'])).toList();
    final plan = _strings(data['plan_modules']).where(available.contains).toList();
    final paid = _strings(data['paid_modules']).where(available.contains).toList();
    _modules
      ..clear()
      ..addAll(plan.isNotEmpty ? plan : (paid.isNotEmpty ? paid : available.take(1)));
    final cycles = asMap(data['cycles']);
    _cycle = cycles.containsKey(asText(data['cycle'])) ? asText(data['cycle']) : 'monthly';
    final plans = asList(data['plans']);
    if (asText(data['pricing_mode']) != 'modules' && plans.isNotEmpty) {
      _mode = 'plan';
      final current = asText(data['plan_code']);
      final featured = plans.firstWhere((plan) => plan['featured'] == true, orElse: () => plans.first);
      _planCode = current.isNotEmpty && plans.any((plan) => asText(plan['code']) == current) ? current : asText(featured['code']);
    }
    _addons
      ..clear()
      ..addAll(_strings(data['bought_addons']));
  }

  static List<String> _strings(dynamic value) => asRawList(value).map((item) => '$item').toList();

  Map<String, dynamic>? get _currentPlan {
    for (final plan in asList(_billing?['plans'])) {
      if (asText(plan['code']) == _planCode) return plan;
    }
    return null;
  }

  /// Sotib olinadigan qo'shimchalar: pullik va tanlangan paketga kirmaganlar.
  List<Map<String, dynamic>> get _paidAddons {
    final planAddons = asList(_currentPlan?['addons']).map((item) => asText(item['code'])).toSet();
    return asList(_billing?['addon_states'])
        .where((item) => asText(item['mode']) == 'paid' && !(_mode == 'plan' && planAddons.contains(asText(item['addon']))))
        .toList();
  }

  bool get _canPick => _mode == 'plan' ? (_planCode ?? '').isNotEmpty : _modules.isNotEmpty;

  Map<String, Object?> _body() {
    final paid = _paidAddons.map((item) => asText(item['addon'])).toSet();
    final addons = _addons.where(paid.contains).toList();
    return _mode == 'plan'
        ? <String, Object?>{'plan_code': _planCode, 'addons': addons, 'cycle': _cycle}
        : <String, Object?>{'modules': _modules.toList(), 'addons': addons, 'cycle': _cycle};
  }

  /// Tanlov o'zgarganda narx qayta hisoblanadi (ketma-ket bosishlarda bitta so'rov).
  void _changed(VoidCallback change) {
    setState(change);
    _quoteTimer?.cancel();
    _quoteTimer = Timer(const Duration(milliseconds: 300), _refreshQuote);
  }

  Future<void> _refreshQuote() async {
    if (!_canPick) {
      setState(() {
        _quote = null;
        _quoteError = null;
      });
      return;
    }
    final request = ++_quoteRequest;
    setState(() {
      _quoting = true;
      _quoteError = null;
    });
    try {
      final quote = await _repository.quote(_body());
      if (mounted && request == _quoteRequest) setState(() => _quote = quote);
    } on ApiException catch (error) {
      if (mounted && request == _quoteRequest) {
        setState(() {
          _quote = null;
          _quoteError = error.message;
        });
      }
    } finally {
      if (mounted && request == _quoteRequest) setState(() => _quoting = false);
    }
  }

  Future<void> _issue() async {
    setState(() => _issuing = true);
    try {
      final invoice = await _repository.issue(_body());
      if (!mounted) return;
      showMessage(
        context,
        asText(invoice['status']) == 'paid'
            ? tr('Obuna faollashtirildi.')
            : tr("{0} raqamli hisob chiqarildi. Endi uni to'lashingiz mumkin.", <Object?>[asText(invoice['number'])]),
      );
      await _load();
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    } finally {
      if (mounted) setState(() => _issuing = false);
    }
  }

  Future<void> _buyAddon(Map<String, dynamic> addon) async {
    final name = asText(addon['name']);
    if (!await confirm(context, tr("«{0}» qo'shilsinmi? Qolgan kunlar uchun hisob chiqariladi.", <Object?>[name]), action: tr("Hozir qo'shish"))) {
      return;
    }
    setState(() => _busy = 'addon:${asText(addon['addon'])}');
    try {
      final invoice = await _repository.addAddon(asText(addon['addon']));
      if (!mounted) return;
      showMessage(
        context,
        asText(invoice['status']) == 'paid'
            ? tr('«{0}» yoqildi.', <Object?>[name])
            : tr("{0} raqamli hisob chiqarildi: to'lagach «{1}» yoqiladi.", <Object?>[asText(invoice['number']), name]),
      );
      await _load();
      if (mounted) unawaited(AppScope.read(context).loadContext().catchError((Object _) {}));
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  /// Click va Payme — tashqi to'lov sahifasi (brauzer); bank o'tkazmasi — rekvizitlar shu sahifada.
  Future<void> _pay(Map<String, dynamic> invoice, String provider) async {
    final id = asInt(invoice['id']);
    setState(() => _busy = '$id:$provider');
    try {
      final data = await _repository.pay(id, provider);
      if (!mounted) return;
      final url = Uri.tryParse(asText(data['redirect_url']));
      if (url != null && url.hasScheme) {
        _awaitingPayment = true;
        await launchUrl(url, mode: LaunchMode.externalApplication);
        return;
      }
      setState(() => _bankNote = <String, dynamic>{'invoice': id, 'message': data['message'], 'details': data['bank_details']});
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final billing = _billing;
    Widget body;
    if (billing == null) {
      final error = _error;
      if (_loading) {
        body = const SkeletonList(header: true, count: 4);
      } else if (error is ApiException && error.isForbidden) {
        body = ForbiddenState(details: error.message, onRetry: _load);
      } else {
        body = ErrorState(message: errorText(error), onRetry: _load);
      }
    } else {
      body = RefreshIndicator(onRefresh: _load, child: _content(billing));
    }
    return Scaffold(appBar: AppBar(title: Text(tr('Modullar va obuna'))), body: body);
  }

  Widget _content(Map<String, dynamic> billing) {
    final status = asText(billing['status']);
    final invoices = asList(billing['invoices']);
    final open = invoices.where((item) => asText(item['status']) == 'open').toList();
    final history = invoices.where((item) => asText(item['status']) != 'open').toList();
    final usage = asMap(billing['usage']);
    final usageRows = usageLabels.keys.where((key) => asMap(usage[key])['limit'] != null).toList();
    final modules = asList(billing['module_states']).where((item) => item['is_active'] != false || item['enabled'] == true).toList();
    final addons = asList(billing['addon_states']);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: <Widget>[
        _StatusCard(billing: billing),
        if (usageRows.isNotEmpty) ...<Widget>[
          SectionTitle(tr('Limitlar')),
          AppCard(
            child: Column(children: <Widget>[
              for (final key in usageRows) _UsageRow(label: tr(usageLabels[key]!), row: asMap(usage[key]), warning: asInt(usage['warning_percent'], 80)),
            ]),
          ),
        ],
        if (modules.isNotEmpty) ...<Widget>[
          SectionTitle(tr('Modullar')),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(children: <Widget>[
              for (var i = 0; i < modules.length; i++) ...<Widget>[
                if (i > 0) const Divider(),
                _ModuleTile(state: modules[i], status: status),
              ],
            ]),
          ),
          if (billing['can_choose_trial_modules'] == true)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(tr('Sinov davrida modullarni veb-versiyadagi «Modullar va obuna» sahifasida yoqasiz.'),
                  style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
            ),
        ],
        if (addons.isNotEmpty) ...<Widget>[
          SectionTitle(tr("Qo'shimcha imkoniyatlar")),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(children: <Widget>[
              for (var i = 0; i < addons.length; i++) ...<Widget>[
                if (i > 0) const Divider(),
                _AddonTile(
                  addon: addons[i],
                  canBuy: status == 'active' && asText(addons[i]['mode']) == 'paid' && addons[i]['enabled'] != true,
                  busy: _busy != null,
                  onBuy: () => _buyAddon(addons[i]),
                ),
              ],
            ]),
          ),
        ],
        for (final invoice in open) ...<Widget>[
          const SizedBox(height: 16),
          _OpenInvoice(
            invoice: invoice,
            providers: asMap(billing['providers']),
            busy: _busy,
            bankNote: asInt(_bankNote?['invoice']) == asInt(invoice['id']) ? _bankNote : null,
            onPay: (provider) => _pay(invoice, provider),
          ),
        ],
        SectionTitle(billing['period_ends_at'] != null ? tr('Keyingi davr') : tr('Obunani rasmiylashtirish')),
        _nextPeriod(billing),
        SectionTitle(tr('Hisoblar tarixi')),
        if (history.isEmpty)
          EmptyState(icon: Icons.receipt_long_outlined, text: tr("Hali to'langan hisob yo'q."))
        else
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(children: <Widget>[
              for (var i = 0; i < history.length; i++) ...<Widget>[
                if (i > 0) const Divider(),
                ListTile(
                  dense: true,
                  title: Text(asText(history[i]['number']), style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${date(history[i]['period_from'])} – ${date(history[i]['period_to'])}'),
                  trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: <Widget>[
                    Text(money(asInt(history[i]['amount'])), style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(tr(invoiceLabels[asText(history[i]['status'])] ?? asText(history[i]['status'])),
                        style: TextStyle(
                          fontSize: 12,
                          color: asText(history[i]['status']) == 'paid' ? AppColors.success : AppColors.muted,
                        )),
                  ]),
                ),
              ],
            ]),
          ),
      ],
    );
  }

  Widget _nextPeriod(Map<String, dynamic> billing) {
    final plans = asList(billing['plans']);
    final available = asList(billing['available_modules']);
    final free = _strings(billing['free_modules']);
    final cycles = asMap(billing['cycles']);
    final paidAddons = _paidAddons;
    final quote = _quote;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        if (asText(billing['pricing_mode']) == 'both' && plans.isNotEmpty) ...<Widget>[
          SegmentedButton<String>(
            segments: <ButtonSegment<String>>[
              ButtonSegment<String>(value: 'plan', label: Text(tr('Tayyor paket'))),
              ButtonSegment<String>(value: 'modules', label: Text(tr("Modullarni o'zim tanlayman"))),
            ],
            selected: <String>{_mode},
            showSelectedIcon: false,
            onSelectionChanged: (value) => _changed(() {
              _mode = value.first;
              if (_mode == 'plan' && (_planCode ?? '').isEmpty && plans.isNotEmpty) _planCode = asText(plans.first['code']);
            }),
          ),
          const SizedBox(height: 12),
        ],
        if (_mode == 'plan') ...<Widget>[
          Text(tr("Paketni tanlang. Kerak bo'lsa, unga kirmagan qo'shimchalarni ham belgilang."), style: TextStyle(color: AppColors.muted, fontSize: 13)),
          const SizedBox(height: 8),
          for (final plan in plans) _PlanOption(plan: plan, selected: asText(plan['code']) == _planCode, onTap: () => _changed(() => _planCode = asText(plan['code']))),
        ] else ...<Widget>[
          Text(tr("Kerakli modullarni tanlang. Narx modullar va faol o'quvchilar soniga qarab hisoblanadi."),
              style: TextStyle(color: AppColors.muted, fontSize: 13)),
          const SizedBox(height: 4),
          for (final module in available)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _modules.contains(asText(module['module'])),
              onChanged: (on) => _changed(() {
                if (on == true) {
                  _modules.add(asText(module['module']));
                } else {
                  _modules.remove(asText(module['module']));
                }
              }),
              title: Row(children: <Widget>[
                Flexible(child: Text(asText(module['name']), style: const TextStyle(fontWeight: FontWeight.w600))),
                if (free.contains(asText(module['module']))) ...<Widget>[const SizedBox(width: 6), Pill(tr('Bepul'), color: AppColors.success)],
              ]),
              subtitle: Text(free.contains(asText(module['module']))
                  ? '${money(0)} / ${tr('oy')}'
                  : '${money(asInt(module['monthly_price']))} / ${tr('oy')}'),
            ),
        ],
        if (paidAddons.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Text(tr("Qo'shimcha imkoniyatlar"), style: const TextStyle(fontWeight: FontWeight.w700)),
          for (final addon in paidAddons)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _addons.contains(asText(addon['addon'])),
              onChanged: (on) => _changed(() {
                if (on == true) {
                  _addons.add(asText(addon['addon']));
                } else {
                  _addons.remove(asText(addon['addon']));
                }
              }),
              title: Text(asText(addon['name']), style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(asText(addon['source']) == 'free' ? tr('Bepul') : '${money(asInt(addon['monthly_price']))} / ${tr('oy')}'),
            ),
        ],
        const SizedBox(height: 8),
        Text(tr("To'lov davri"), style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
          for (final key in cycles.keys)
            ChoiceChip(
              label: Text(asInt(cycles[key]) > 0
                  ? '${tr(cycleLabels[key] ?? key)} −${asInt(cycles[key])}%'
                  : tr(cycleLabels[key] ?? key)),
              selected: _cycle == key,
              onSelected: (_) => _changed(() => _cycle = key),
            ),
        ]),
        const SizedBox(height: 12),
        if (_quoteError != null)
          Text(_quoteError!, style: const TextStyle(color: AppColors.warning))
        else if (!_canPick)
          Text(_mode == 'plan' ? tr('Paketni tanlang.') : tr('Kamida bitta modul tanlang.'), style: TextStyle(color: AppColors.muted))
        else if (quote != null)
          Opacity(
            opacity: _quoting ? 0.6 : 1,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.soft(AppColors.brand), borderRadius: BorderRadius.circular(AppRadius.control)),
              child: Column(children: <Widget>[
                for (final item in asList(quote['items']))
                  KeyValue(billingLine(asText(item['description'])), money(asInt(item['amount']))),
                const Divider(),
                KeyValue(
                  tr('Jami, {0} uchun', <Object?>[tr(cycleLabels[_cycle] ?? _cycle).toLowerCase()]),
                  money(asInt(quote['total'])),
                  valueColor: AppColors.ink,
                ),
              ]),
            ),
          )
        else if (_quoting)
          const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(strokeWidth: 2.4))),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _issuing || _quoting || quote == null || !_canPick ? null : _issue,
          child: Text(_issuing ? tr('Chiqarilmoqda...') : tr('Hisob chiqarish')),
        ),
      ]),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.billing});

  final Map<String, dynamic> billing;

  @override
  Widget build(BuildContext context) {
    final status = asText(billing['status']);
    final suspended = billing['suspended'] == true;
    final limit = billing['student_limit'] == null ? null : asInt(billing['student_limit']);
    final students = asInt(billing['students_count'], asInt(billing['active_students']));
    final planCode = asText(billing['plan_code']);
    final plan = asList(billing['plans']).firstWhere((item) => asText(item['code']) == planCode, orElse: () => <String, dynamic>{});
    String text = '';
    if (!suspended) {
      if (status == 'trial') {
        text = tr('Sinov muddati {0} gacha, {1} kun qoldi.', <Object?>[date(billing['trial_ends_at']), daysLeft(billing['trial_ends_at'])]);
      } else if (status == 'active') {
        text = tr("To'langan davr {0} gacha, {1} kun qoldi.", <Object?>[date(billing['period_ends_at']), daysLeft(billing['period_ends_at'])]);
      } else if (status == 'past_due') {
        text = tr("To'langan davr {0} da tugagan. Tizim hozircha to'liq ishlayapti, obunani to'lang.", <Object?>[date(billing['period_ends_at'])]);
      } else {
        text = tr("Obuna muddati tugagan. Ma'lumotlaringiz saqlangan va ko'rinadi, lekin yangi yozuv kiritib bo'lmaydi.");
      }
    }
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Row(children: <Widget>[
          Pill(tr(subscriptionLabels[status] ?? asText(billing['status_label'], status)), color: subscriptionColor(status)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              <String>[
                tr("Faol o'quvchilar: {0}", <Object?>[asInt(billing['active_students'])]),
                if (planCode.isEmpty && asText(billing['student_tier']).isNotEmpty) billingTier(asText(billing['student_tier'])),
                if (plan.isNotEmpty) tr('Paket: {0}', <Object?>[asText(plan['name'])]),
              ].join(' · '),
              style: TextStyle(color: AppColors.muted, fontSize: 13),
            ),
          ),
        ]),
        if (suspended) ...<Widget>[
          const SizedBox(height: 10),
          Text(
            tr("Obuna to'xtatilgan. Platforma ma'muriyati obunangizni vaqtincha to'xtatdi: ma'lumotlar ko'rinadi, lekin yangi yozuv kiritib bo'lmaydi."),
            style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600),
          ),
        ],
        if (text.isNotEmpty) ...<Widget>[const SizedBox(height: 10), Text(text)],
        if (limit != null) KeyValue(tr("O'quvchilar chegarasi"), '$students / $limit', valueColor: students >= limit ? AppColors.danger : null),
        if (asInt(billing['discount_percent']) > 0)
          KeyValue(tr('Shaxsiy chegirma'), '${asInt(billing['discount_percent'])}%', valueColor: AppColors.success),
        if (billing['tier_exceeded'] == true)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              tr("Faol o'quvchilar soni to'langan pog'onadan oshdi. Joriy davrda hech narsa cheklanmaydi; keyingi davr hisobi yangi pog'ona ({0}) narxida chiqadi.",
                  <Object?>[billingTier(asText(billing['student_tier']))]),
              style: const TextStyle(color: AppColors.warning, fontSize: 13),
            ),
          ),
      ]),
    );
  }
}

class _UsageRow extends StatelessWidget {
  const _UsageRow({required this.label, required this.row, required this.warning});

  final String label;
  final Map<String, dynamic> row;
  final int warning;

  @override
  Widget build(BuildContext context) {
    final used = asInt(row['used']);
    final limit = asInt(row['limit']);
    final percent = limit > 0 ? (used * 100 / limit).clamp(0, 100).round() : 100;
    final color = percent >= 100 ? AppColors.danger : (percent >= warning ? AppColors.warning : AppColors.brand);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        Row(children: <Widget>[
          Expanded(child: Text(label, style: TextStyle(color: AppColors.muted))),
          Text('$used / $limit', style: TextStyle(fontWeight: FontWeight.w700, color: percent >= 100 ? AppColors.danger : AppColors.ink)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(value: percent / 100, minHeight: 7, color: color, backgroundColor: AppColors.line),
        ),
      ]),
    );
  }
}

class _ModuleTile extends StatelessWidget {
  const _ModuleTile({required this.state, required this.status});

  final Map<String, dynamic> state;
  final String status;

  @override
  Widget build(BuildContext context) {
    final enabled = state['enabled'] == true;
    final source = asText(state['source']);
    String label;
    Color color;
    if (source == 'free') {
      label = 'Bepul berilgan';
      color = AppColors.success;
    } else if (enabled && status == 'trial') {
      label = 'Sinov davrida ochiq';
      color = AppColors.brand;
    } else if (enabled) {
      label = 'Ochiq — obuna rejasida';
      color = AppColors.success;
    } else {
      label = 'Yoqilmagan';
      color = AppColors.muted;
    }
    String hint = '';
    if (!enabled && status == 'trial' && state['in_trial'] == false) hint = 'Sinovga kirmaydi';
    if (!enabled && hint.isEmpty && source == 'plan') hint = 'Obuna rejasida bor, lekin hozir ochiq emas';
    return ListTile(
      title: Text(asText(state['name']), style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: hint.isEmpty ? null : Text(tr(hint), style: const TextStyle(color: AppColors.warning, fontSize: 12)),
      trailing: Pill(tr(label), color: color),
    );
  }
}

class _AddonTile extends StatelessWidget {
  const _AddonTile({required this.addon, required this.canBuy, required this.busy, required this.onBuy});

  final Map<String, dynamic> addon;
  final bool canBuy;
  final bool busy;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final source = asText(addon['source'], 'none');
    final enabled = addon['enabled'] == true;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Row(children: <Widget>[
          Expanded(child: Text(asText(addon['name']), style: const TextStyle(fontWeight: FontWeight.w600))),
          Pill(tr(addonSourceLabels[source] ?? "Yo'q"), color: enabled ? AppColors.success : AppColors.muted),
        ]),
        if (asText(addon['description']).isNotEmpty) ...<Widget>[
          const SizedBox(height: 4),
          Text(asText(addon['description']), style: TextStyle(color: AppColors.muted, fontSize: 13)),
        ],
        if (asText(addon['mode']) == 'paid' && !enabled)
          Row(children: <Widget>[
            Expanded(child: Text('${money(asInt(addon['monthly_price']))} / ${tr('oy')}', style: TextStyle(color: AppColors.muted))),
            if (canBuy) OutlinedButton(onPressed: busy ? null : onBuy, child: Text(tr("Hozir qo'shish"))),
          ]),
      ]),
    );
  }
}

class _PlanOption extends StatelessWidget {
  const _PlanOption({required this.plan, required this.selected, required this.onTap});

  final Map<String, dynamic> plan;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final limits = asMap(plan['limits']);
    final modules = asList(plan['modules']).map((item) => asText(item['name'])).join(', ');
    final addons = asList(plan['addons']).map((item) => asText(item['name'])).join(', ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        onTap: onTap,
        color: selected ? AppColors.soft(AppColors.brand) : null,
        padding: const EdgeInsets.all(12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, color: selected ? AppColors.brand : AppColors.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Row(children: <Widget>[
                Expanded(child: Text(asText(plan['name']), style: const TextStyle(fontWeight: FontWeight.w700))),
                if (plan['featured'] == true) Pill(tr('Tavsiya etiladi')),
              ]),
              Text('${money(asInt(plan['monthly_price']))} / ${tr('oy')}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              if (asText(plan['description']).isNotEmpty) Text(asText(plan['description']), style: TextStyle(color: AppColors.muted, fontSize: 13)),
              if (modules.isNotEmpty) Text(modules, style: TextStyle(color: AppColors.muted, fontSize: 12)),
              if (addons.isNotEmpty) Text('+ $addons', style: TextStyle(color: AppColors.muted, fontSize: 12)),
              Text(
                <String>[
                  limits['students'] != null
                      ? tr("{0} tagacha o'quvchi", <Object?>[asInt(limits['students'])])
                      : tr("O'quvchilar cheklanmagan"),
                  if (limits['staff'] != null) tr('{0} ta xodim', <Object?>[asInt(limits['staff'])]),
                ].join(' · '),
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _OpenInvoice extends StatelessWidget {
  const _OpenInvoice({required this.invoice, required this.providers, required this.busy, required this.bankNote, required this.onPay});

  final Map<String, dynamic> invoice;
  final Map<String, dynamic> providers;
  final String? busy;
  final Map<String, dynamic>? bankNote;
  final void Function(String provider) onPay;

  @override
  Widget build(BuildContext context) {
    final id = asInt(invoice['id']);
    Widget button(String provider, String label, {bool primary = true}) {
      final loading = busy == '$id:$provider';
      final child = loading
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2))
          : Text(label);
      return primary
          ? FilledButton(onPressed: busy != null ? null : () => onPay(provider), child: child)
          : OutlinedButton(onPressed: busy != null ? null : () => onPay(provider), child: child);
    }

    return AppCard(
      color: AppColors.soft(AppColors.warning),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        Row(children: <Widget>[
          Expanded(
            child: Text(tr("To'lanmagan hisob {0}", <Object?>[asText(invoice['number'])]), style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          Text(money(asInt(invoice['amount'])), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        ]),
        const SizedBox(height: 6),
        for (final item in asList(invoice['items'])) KeyValue(billingLine(asText(item['description'])), money(asInt(item['amount']))),
        Text(
          '${tr('Davr')}: ${date(invoice['period_from'])} – ${date(invoice['period_to'])} · ${tr(cycleLabels[asText(invoice['cycle'])] ?? asText(invoice['cycle']))}',
          style: TextStyle(color: AppColors.muted, fontSize: 12),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
          if (providers['click'] == true) button('click', tr("Click orqali to'lash")),
          if (providers['payme'] == true) button('payme', tr("Payme orqali to'lash")),
          button('manual', tr("Bank o'tkazmasi"), primary: false),
        ]),
        if (bankNote != null) ...<Widget>[
          const SizedBox(height: 10),
          Text(asText(bankNote!['message'])),
          if (asText(bankNote!['details']).isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            SelectableText(asText(bankNote!['details']), style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ],
      ]),
    );
  }
}
