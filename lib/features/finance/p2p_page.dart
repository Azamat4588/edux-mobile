// Kartaga o'tkazmalar (kassir, administrator, direktor; backend 1.35 P2pController): kutilayotgan o'tkazmalar
// (qo'lda tasdiqlash / rad etish), noma'lum kirimlar (buyurtmaga yoki o'quvchiga biriktirish, e'tiborsiz qoldirish),
// so'nggi kirimlar va bank xabari matnini qo'lda qo'shish.
// API: GET pay/p2p, POST pay/p2p/orders/{id}/confirm|reject, POST pay/p2p/incomings/{id}/attach|ignore, POST pay/p2p/messages.
import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/help_links.dart';
import '../../core/i18n.dart';
import '../../core/payments.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/web_links.dart';
import '../../core/widgets.dart';

class P2pPage extends StatefulWidget {
  const P2pPage({super.key});

  @override
  State<P2pPage> createState() => _P2pPageState();
}

class _P2pPageState extends State<P2pPage> {
  final GlobalKey<AsyncViewState<Map<String, dynamic>>> _view = GlobalKey<AsyncViewState<Map<String, dynamic>>>();

  Future<void> _run(Future<dynamic> Function(Api api) action, String done) async {
    try {
      await action(AppScope.read(context).api);
      if (mounted) showMessage(context, done);
      _view.currentState?.reload();
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    }
  }

  Future<void> _confirm(Map<String, dynamic> order) async {
    final text = tr("{0} — {1} kelganini tekshirdingizmi? To'lov tasdiqlanadi.", <Object?>[asText(asMap(order['student'])['full_name']), money(asInt(order['p2p_amount']))]);
    if (!await confirm(context, text, action: tr('Tasdiqlash'))) return;
    await _run((api) => api.post('pay/p2p/orders/${asInt(order['id'])}/confirm'), tr("To'lov tasdiqlandi."));
  }

  Future<void> _reject(Map<String, dynamic> order) async {
    if (!await confirm(context, tr('Buyurtma rad etilsinmi?'), action: tr('Rad etish'), danger: true)) return;
    await _run((api) => api.post('pay/p2p/orders/${asInt(order['id'])}/reject'), tr('Rad etildi.'));
  }

  Future<void> _ignore(Map<String, dynamic> incoming) async {
    if (!await confirm(context, tr("Kirim e'tiborsiz qoldirilsinmi? (masalan, boshqa maqsaddagi o'tkazma)"), action: tr("E'tiborsiz qoldirish"))) return;
    await _run((api) => api.post('pay/p2p/incomings/${asInt(incoming['id'])}/ignore'), tr('Saqlandi.'));
  }

  Future<void> _attach(Map<String, dynamic> incoming, List<Map<String, dynamic>> pending) async {
    final target = await showModalBottomSheet<Map<String, Object?>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet))),
      builder: (_) => _AttachSheet(incoming: incoming, pending: pending),
    );
    if (target == null) return;
    await _run((api) => api.post('pay/p2p/incomings/${asInt(incoming['id'])}/attach', target), tr('Kirim biriktirildi.'));
  }

  Future<void> _message() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Bank xabarini qo\'shish')),
        content: TextField(controller: controller, autofocus: true, minLines: 4, maxLines: 10, decoration: InputDecoration(hintText: tr('Bank SMS yoki bot xabari matnini to\'liq qo\'ying'))),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Bekor qilish'))),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: Text(tr('Yuborish'))),
        ],
      ),
    );
    controller.dispose();
    if (text == null || text.isEmpty || !mounted) return;
    try {
      final data = asMap(await AppScope.read(context).api.post('pay/p2p/messages', <String, Object?>{'text': text}));
      if (mounted) showMessage(context, asText(data['message'], tr('Qabul qilindi.')));
      _view.currentState?.reload();
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = AppScope.of(context).api;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: pageBar(context,
          title: Text(tr("Kartaga o'tkazmalar")),
          actions: const <Widget>[HelpButton(HelpLinks.p2p)],
          bottom: TabBar(tabs: <Widget>[Tab(text: tr('Kutilmoqda')), Tab(text: tr("Noma'lum")), Tab(text: tr("So'nggi"))]),
        ),
        body: AsyncView<Map<String, dynamic>>(
          key: _view,
          refreshable: false,
          load: () async => asMap(await api.get('pay/p2p')),
          builder: (context, data, reload) {
            final manual = data['manual'] == true;
            final p2p = asMap(data['p2p']);
            final pending = asList(data['pending'], 'pending');
            final unknown = asList(data['unknown'], 'unknown');
            final recent = asList(data['recent'], 'recent');
            Widget list(List<Widget> children, String empty) => RefreshIndicator(
                  onRefresh: reload,
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: <Widget>[
                    if (p2p['enabled'] == false)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: AppCard(
                          color: AppColors.soft(AppColors.warning),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                            Text(tr("Kartaga o'tkazma sozlamada o'chirilgan (Sozlamalar → Onlayn to'lov → Kartaga o'tkazma).")),
                            const OpenWebButton(WebPages.paymentsP2p),
                          ]),
                        ),
                      ),
                    if (!manual)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(tr("Qo'lda tasdiqlash sozlamada o'chirilgan — faqat ko'rish."), style: TextStyle(color: AppColors.muted)),
                      ),
                    if (children.isEmpty) EmptyState(icon: Icons.credit_card, text: empty) else ...children,
                  ]),
                );
            return Stack(children: <Widget>[
              TabBarView(children: <Widget>[
                list(<Widget>[
                  for (final order in pending) ...<Widget>[
                    AppCard(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                        Row(children: <Widget>[
                          Expanded(child: Text(asText(asMap(order['student'])['full_name']), style: const TextStyle(fontWeight: FontWeight.w700))),
                          Pill(order['expired'] == true ? tr("Muddati o'tgan") : tr('Kutilmoqda'), color: order['expired'] == true ? AppColors.danger : AppColors.warning),
                        ]),
                        if (asMap(order['course'])['title'] != null) Text(asText(asMap(order['course'])['title']), style: TextStyle(color: AppColors.muted)),
                        const SizedBox(height: 6),
                        Text('${p2pAmountText(asInt(order['p2p_amount']))} ${tr("so'm")}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                        Text(tr('Muddat: {0}', <Object?>[dateTime(order['expires_at'])]), style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
                        if (manual) ...<Widget>[
                          const SizedBox(height: 10),
                          Row(children: <Widget>[
                            Expanded(child: FilledButton(onPressed: () => _confirm(order), child: Text(tr('Tasdiqlash')))),
                            const SizedBox(width: 8),
                            OutlinedButton(onPressed: () => _reject(order), child: Text(tr('Rad etish'))),
                          ]),
                        ],
                      ]),
                    ),
                    const SizedBox(height: 10),
                  ],
                ], tr("Kutilayotgan o'tkazma yo'q.")),
                list(<Widget>[
                  for (final incoming in unknown) ...<Widget>[
                    _IncomingCard(
                      incoming: incoming,
                      actions: manual
                          ? Row(children: <Widget>[
                              Expanded(child: FilledButton.tonal(onPressed: () => _attach(incoming, pending), child: Text(tr('Biriktirish')))),
                              const SizedBox(width: 8),
                              OutlinedButton(onPressed: () => _ignore(incoming), child: Text(tr("E'tiborsiz"))),
                            ])
                          : null,
                    ),
                    const SizedBox(height: 10),
                  ],
                ], tr("Noma'lum kirim yo'q: hamma o'tkazmalar buyurtmaga mos keldi.")),
                list(<Widget>[
                  for (final incoming in recent) ...<Widget>[
                    _IncomingCard(incoming: incoming),
                    const SizedBox(height: 10),
                  ],
                ], tr("Hali kirim yo'q.")),
              ]),
              if (manual)
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: FloatingActionButton.extended(onPressed: _message, icon: const Icon(Icons.add_comment_outlined), label: Text(tr('Bank xabari'))),
                ),
            ]);
          },
        ),
      ),
    );
  }
}

class _IncomingCard extends StatelessWidget {
  const _IncomingCard({required this.incoming, this.actions});

  final Map<String, dynamic> incoming;
  final Widget? actions;

  static const Map<String, String> _status = <String, String>{'matched': 'Tasdiqlandi', 'unmatched': "Noma'lum", 'ignored': "E'tiborsiz"};
  static const Map<String, String> _source = <String, String>{'telegram': 'Telegram', 'sms': 'SMS', 'manual': "Qo'lda"};

  @override
  Widget build(BuildContext context) {
    final status = asText(incoming['status']);
    final order = asMap(incoming['order']);
    final color = status == 'matched' ? AppColors.success : (status == 'unmatched' ? AppColors.warning : AppColors.muted);
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Row(children: <Widget>[
          Expanded(child: Text(money(asInt(incoming['amount'])), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800))),
          Pill(tr(_status[status] ?? status), color: color),
        ]),
        Text(
          <String>[
            tr(_source[asText(incoming['source'])] ?? asText(incoming['source'])),
            if (asText(incoming['origin']).isNotEmpty) asText(incoming['origin']),
            dateTime(incoming['occurred_at'] ?? incoming['created_at']),
          ].join(', '),
          style: TextStyle(color: AppColors.muted, fontSize: 12.5),
        ),
        if (asText(incoming['card_last4']).isNotEmpty || asText(incoming['sender_name']).isNotEmpty)
          Text(
            <String>[
              if (asText(incoming['card_last4']).isNotEmpty) '${tr('Karta')}: *${asText(incoming['card_last4'])}',
              if (asText(incoming['sender_name']).isNotEmpty) asText(incoming['sender_name']),
              if (asText(incoming['sender_last4']).isNotEmpty) '*${asText(incoming['sender_last4'])}',
            ].join(', '),
          ),
        if (order.isNotEmpty) Text('${tr("O'quvchi")}: ${asText(order['student'])}', style: const TextStyle(fontWeight: FontWeight.w600)),
        if (asText(incoming['note']).isNotEmpty) Text(asText(incoming['note']), style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
        if (asText(incoming['text']).isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(asText(incoming['text']), maxLines: 4, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: AppColors.muted)),
          ),
        if (actions != null) ...<Widget>[const SizedBox(height: 10), actions!],
      ]),
    );
  }
}

/// Noma'lum kirimni biriktirish: kutilayotgan buyurtma yoki o'quvchi (o'qish to'lovi).
class _AttachSheet extends StatefulWidget {
  const _AttachSheet({required this.incoming, required this.pending});

  final Map<String, dynamic> incoming;
  final List<Map<String, dynamic>> pending;

  @override
  State<_AttachSheet> createState() => _AttachSheetState();
}

class _AttachSheetState extends State<_AttachSheet> {
  final TextEditingController _search = TextEditingController();
  List<Map<String, dynamic>> _students = <Map<String, dynamic>>[];
  bool _loading = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _find() async {
    final query = _search.text.trim();
    if (query.length < 2) return;
    setState(() => _loading = true);
    try {
      final session = AppScope.read(context);
      // O'quvchiga biriktirish faqat CRM bilan (server: P2pController::attach); qidiruv ham CRM ro'yxatidan.
      final data = await session.api.get('crm/students', query: <String, Object?>{'search': query});
      if (mounted) setState(() => _students = asList(data));
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final amount = asInt(widget.incoming['amount']);
    // Summasi yaqin buyurtmalar oldinda.
    final orders = List<Map<String, dynamic>>.from(widget.pending)
      ..sort((a, b) => (asInt(a['p2p_amount']) - amount).abs().compareTo((asInt(b['p2p_amount']) - amount).abs()));
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: ListView(shrinkWrap: true, children: <Widget>[
        Text(tr('{0} kimga tegishli?', <Object?>[money(amount)]), style: AppTheme.title(size: 19)),
        if (orders.isNotEmpty) ...<Widget>[
          SectionTitle(tr('Kutilayotgan buyurtmalar')),
          for (final order in orders.take(8))
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(asText(asMap(order['student'])['full_name'])),
              subtitle: Text(money(asInt(order['p2p_amount']))),
              trailing: const Icon(Icons.link),
              onTap: () => Navigator.pop(context, <String, Object?>{'order_id': asInt(order['id'])}),
            ),
        ],
        SectionTitle(tr("O'quvchiga (o'qish to'lovi)")),
        if (!AppScope.read(context).hasModule('crm'))
          Text(tr("O'quvchiga to'g'ridan-to'g'ri biriktirish CRM moduli bilan ishlaydi. Hozircha kutilayotgan buyurtmani tanlang."),
              style: TextStyle(color: AppColors.muted))
        else ...<Widget>[
        TextField(
          controller: _search,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _find(),
          decoration: InputDecoration(
            hintText: tr('Ism, telefon yoki kod'),
            suffixIcon: IconButton(onPressed: _find, icon: _loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.search)),
          ),
        ),
        for (final student in _students.take(10))
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(asText(student['full_name'])),
            subtitle: Text(<String>[asText(student['code']), asText(student['phone'])].where((item) => item.isNotEmpty).join(', ')),
            trailing: const Icon(Icons.person_add_alt),
            onTap: () => Navigator.pop(context, <String, Object?>{'student_id': asInt(student['id'])}),
          ),
        ],
      ]),
    );
  }
}
