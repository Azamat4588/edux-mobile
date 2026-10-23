// Onlayn to'lov: o'quvchi o'zi uchun, ota-ona farzandi uchun. Usullar (Click, Payme, Uzum, Paynet, Oson, Alif, kartaga
// o'tkazma) server bergan ro'yxat va tartibda (GET pay/options → methods). To'lov sahifasi brauzerda ochiladi, ilovaga
// qaytilganda buyurtma holati (GET /pay/orders/{id}) tekshiriladi; kartaga o'tkazmada — P2pTransferPage.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/payments.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

/// To'lov tugagach (yoki bekor qilinganda) chaqiriladi — masalan, balansni yangilash uchun.
typedef PaymentDone = void Function(bool paid);

/// Onlayn to'lov: o'qish to'lovi (summa kiritiladi) yoki pullik kurs ([courseId], summa server hisoblaydi).
Future<void> startOnlinePayment(BuildContext context, {int? studentId, int suggested = 0, int? courseId, int months = 1, int coursePrice = 0, PaymentDone? onDone}) async {
  final api = AppScope.read(context).api;
  Map<String, dynamic> options;
  try {
    options = asMap(await api.get('pay/options'));
  } on ApiException catch (error) {
    if (context.mounted) showMessage(context, error.message, error: true);
    return;
  }
  final methods = payMethods(options);
  if (methods.isEmpty) {
    if (context.mounted) {
      showMessage(context, tr("Tashkilotda onlayn to'lov yoqilmagan. To'lovni markaz ma'muriyatiga topshiring."), error: true);
    }
    return;
  }
  if (!context.mounted) return;
  final result = await showModalBottomSheet<_PayStart>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _PayForm(
        studentId: studentId,
        methods: methods,
        suggested: suggested,
        minAmount: asInt(options['min_amount'], 1000),
        courseId: courseId,
        months: months,
        coursePrice: coursePrice,
      ),
    ),
  );
  if (result == null || !context.mounted) return;
  bool paid;
  if (result.p2p != null) {
    paid = await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(builder: (_) => P2pTransferPage(orderId: result.orderId, initial: result.p2p!))) ?? false;
  } else {
    paid = await showOrderStatus(context, result.orderId);
  }
  onDone?.call(paid);
}

class _PayStart {
  const _PayStart(this.orderId, [this.p2p]);

  final int orderId;

  /// Kartaga o'tkazma tanlangan bo'lsa — buyurtma (noyob summa va karta bilan).
  final Map<String, dynamic>? p2p;
}

/// To'lov sahifasidan qaytgach: buyurtma holati. true — to'landi.
Future<bool> showOrderStatus(BuildContext context, int orderId) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isDismissible: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (_) => _OrderStatus(orderId: orderId),
  );
  return result ?? false;
}

class _OrderStatus extends StatefulWidget {
  const _OrderStatus({required this.orderId});

  final int orderId;

  @override
  State<_OrderStatus> createState() => _OrderStatusState();
}

class _OrderStatusState extends State<_OrderStatus> with WidgetsBindingObserver {
  Map<String, dynamic> _order = <String, dynamic>{};
  bool _checking = false;
  String? _error;
  Timer? _timer;
  int _checks = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
    // To'lov tizimi tasdig'i bir necha soniyada keladi: 2 daqiqa davomida o'zi tekshirib turadi.
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_checks > 24 || (_order.isNotEmpty && asText(_order['status']) != 'open')) {
        _timer?.cancel();
        return;
      }
      _check();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  /// Ilova fonda (to'lov ilovasi yoki brauzerda) — so'ralmaydi; qaytilganda darhol tekshiriladi.
  bool _foreground = true;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) _check();
  }

  Future<void> _check() async {
    if (_checking || !mounted || !_foreground) return;
    setState(() => _checking = true);
    _checks++;
    try {
      final order = asMap(await AppScope.read(context).api.get('pay/orders/${widget.orderId}'));
      if (!mounted) return;
      setState(() {
        _order = order;
        _error = null;
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = asText(_order['status']);
    final paid = status == 'paid';
    final voided = status == 'void';
    final color = paid ? AppColors.success : (voided ? AppColors.danger : AppColors.warning);
    final icon = paid ? Icons.check_circle_rounded : (voided ? Icons.cancel_rounded : Icons.hourglass_top_rounded);
    final title = _order.isEmpty
        ? tr('Tekshirilmoqda...')
        : paid
            ? tr("To'lov qabul qilindi")
            : voided
                ? tr("To'lov bekor qilindi")
                : tr("To'lov kutilmoqda");
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        Icon(icon, size: 56, color: color),
        const SizedBox(height: 10),
        Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        if (_order.isNotEmpty) ...<Widget>[
          KeyValue(tr('Summa'), money(asInt(_order['amount']))),
          if (asMap(_order['student'])['full_name'] != null) KeyValue(tr("O'quvchi"), asText(asMap(_order['student'])['full_name'])),
          if (_order['receipt'] != null) KeyValue(tr('Kvitansiya'), asText(_order['receipt'])),
          if (_order['paid_at'] != null) KeyValue(tr('Sana'), dateTime(_order['paid_at'])),
        ],
        if (!paid && !voided && _order.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(tr("To'lov sahifasida to'lovni yakunlang. Tasdiq kelishi bir necha daqiqa olishi mumkin."),
                textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: AppColors.danger)),
          ),
        const SizedBox(height: 18),
        if (!paid && !voided)
          OutlinedButton.icon(
            onPressed: _checking ? null : _check,
            icon: _checking
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
            label: Text(tr('Holatni tekshirish')),
          ),
        const SizedBox(height: 10),
        FilledButton(onPressed: () => Navigator.pop(context, paid), child: Text(paid ? tr('Tayyor') : tr('Yopish'))),
      ]),
    );
  }
}

class _PayForm extends StatefulWidget {
  const _PayForm({
    required this.studentId,
    required this.methods,
    required this.suggested,
    required this.minAmount,
    this.courseId,
    this.months = 1,
    this.coursePrice = 0,
  });

  final int? studentId;
  final List<PayMethod> methods;
  final int suggested;
  final int minAmount;
  final int? courseId;
  final int months;
  final int coursePrice;

  @override
  State<_PayForm> createState() => _PayFormState();
}

class _PayFormState extends State<_PayForm> {
  late final TextEditingController _amount =
      TextEditingController(text: widget.suggested > 0 ? '${widget.suggested}' : '');
  bool _busy = false;
  String? _error;

  bool get _course => widget.courseId != null;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  int? get _value => _course ? widget.coursePrice * widget.months : int.tryParse(digitsOnly(_amount.text));

  Future<void> _pay(PayMethod method) async {
    final amount = _value;
    if (!_course && (amount == null || amount < widget.minAmount)) {
      setState(() => _error = tr('Summani kiriting.'));
      return;
    }
    if (amount != null && amount > 0 && !methodAllows(method, amount)) {
      setState(() => _error = tr('{0} orqali eng kam summa: {1}', <Object?>[method.name, money(method.min)]));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = AppScope.read(context).api;
      final order = asMap(await api.post('pay/orders', <String, Object?>{
        'purpose': _course ? 'course' : 'tuition',
        if (!_course) 'amount': amount,
        if (_course) 'course_id': widget.courseId,
        if (_course) 'months': widget.months,
        'student_id': widget.studentId,
      }));
      final id = asInt(order['id']);
      if (method.isP2p) {
        // Kartaga o'tkazma: noyob summa va karta rekvizitlari — alohida sahifada.
        final reserved = asMap(await api.post('pay/orders/$id/p2p'));
        if (mounted) Navigator.pop(context, _PayStart(id, reserved));
        return;
      }
      final checkout = asMap(await api.post('pay/orders/$id/checkout', <String, Object?>{'provider': method.key}));
      final url = Uri.tryParse(asText(checkout['url']));
      if (url == null) throw ApiException(500, tr("To'lov sahifasini ochib bo'lmadi. Qayta urinib ko'ring."));
      await launchUrl(url, mode: LaunchMode.externalApplication);
      // Varaq yopiladi va buyurtma holati ko'rsatiladi (startOnlinePayment davomi).
      if (mounted) Navigator.pop(context, _PayStart(id));
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          Text(tr('Onlayn to\'lov'), style: AppTheme.title(size: 20)),
          const SizedBox(height: 14),
          if (_error != null) ...<Widget>[
            Text(_error!, style: TextStyle(color: AppColors.danger)),
            const SizedBox(height: 8),
          ],
          if (_course)
            KeyValue(tr('Summa'), money(widget.coursePrice * widget.months))
          else
            TextField(
              controller: _amount,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              decoration: InputDecoration(labelText: tr("To'lanadigan summa (so'm)"), suffixText: tr("so'm")),
            ),
          if (!_course && widget.suggested > 0) ...<Widget>[
            const SizedBox(height: 6),
            Text('${tr('Hozirgi qarz:')} ${money(widget.suggested)}', style: TextStyle(color: AppColors.muted)),
          ],
          const SizedBox(height: 14),
          Text(tr("To'lov usulini tanlang"), style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          // Usullar server bergan tartibda (direktor «Sozlamalar → Onlayn to'lov» da tartiblaydi).
          for (final method in widget.methods) ...<Widget>[
            FilledButton(
              onPressed: _busy ? null : () => _pay(method),
              style: FilledButton.styleFrom(backgroundColor: Color(providerColor(method.key))),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
                if (method.isP2p) ...<Widget>[const Icon(Icons.credit_card, size: 20), const SizedBox(width: 8)],
                Flexible(
                  child: Text(
                    method.isP2p ? tr("Kartaga o'tkazma") : tr('{0} orqali to\'lash', <Object?>[method.name]),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (method.fee > 0) Text('  +${number(method.fee)}%', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              ]),
            ),
            const SizedBox(height: 10),
          ],
          if (widget.methods.any((method) => method.fee > 0))
            Text(tr("Foiz — to'lov tizimi komissiyasi (ma'lumot uchun)."), style: TextStyle(color: AppColors.muted, fontSize: 12)),
        ]),
      ),
    );
  }
}

/// Kartaga o'tkazma (P2P): karta raqami, egasi, noyob summa (aynan shu summa yoziladi), muddat taymeri va holat.
/// Bank xabari kelib server buyurtmani tasdiqlaganda muvaffaqiyat ekrani chiqadi (GET pay/orders/{id} har 5 soniyada).
class P2pTransferPage extends StatefulWidget {
  const P2pTransferPage({super.key, required this.orderId, required this.initial});

  final int orderId;
  final Map<String, dynamic> initial;

  @override
  State<P2pTransferPage> createState() => _P2pTransferPageState();
}

class _P2pTransferPageState extends State<P2pTransferPage> with WidgetsBindingObserver {
  late Map<String, dynamic> _order = widget.initial;
  Timer? _tick;
  Timer? _poll;
  bool _foreground = true;
  bool _renewing = false;
  bool _checking = false;
  int _expiredChecks = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      // Ekran fonda yoki yakuniy holatda — har soniyada qayta chizish shart emas.
      if (mounted && _foreground && !_final) setState(() {});
    });
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _check());
  }

  bool get _final => _state == 'paid' || _state == 'void';

  /// Yakuniy holatda (to'langan/bekor) ikkala taymer ham to'xtaydi.
  void _stopTimers() {
    _tick?.cancel();
    _poll?.cancel();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tick?.cancel();
    _poll?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) _check();
  }

  String get _state => p2pState(_order, DateTime.now());

  Future<void> _check() async {
    // Oldingi so'rov tugamagan bo'lsa (sekin internet) — ustma-ust so'ramaymiz.
    if (!mounted || !_foreground || _checking || _final) return;
    // Muddati o'tgan: kechikkan o'tkazma tasdiqlanishi mumkin — 30 soniyada bir, 10 daqiqagacha tekshiriladi.
    if (_state == 'expired') {
      _expiredChecks++;
      if (_expiredChecks % 6 != 1) return;
      if (_expiredChecks > 120) {
        _poll?.cancel();
        return;
      }
    } else {
      _expiredChecks = 0;
    }
    _checking = true;
    final api = AppScope.read(context).api;
    try {
      final order = asMap(await api.get('pay/orders/${widget.orderId}'));
      if (!mounted) return;
      // Tasdiqlangandan keyin javobda `p2p` bo'lmaydi — oxirgi rekvizitlar saqlanadi.
      setState(() => _order = <String, dynamic>{...order, if (order['p2p'] == null) 'p2p': _order['p2p']});
      if (_final) _stopTimers();
    } catch (_) {
      // internet yo'q — keyingi urinishda
    } finally {
      _checking = false;
    }
  }

  Future<void> _renew() async {
    setState(() => _renewing = true);
    try {
      final order = asMap(await AppScope.read(context).api.post('pay/orders/${widget.orderId}/p2p'));
      if (!mounted) return;
      setState(() => _order = order);
      // Yangi muddat: kuzatish qaytadan boshlanadi (to'xtagan bo'lsa).
      _expiredChecks = 0;
      if (!(_poll?.isActive ?? false)) _poll = Timer.periodic(const Duration(seconds: 5), (_) => _check());
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    } finally {
      if (mounted) setState(() => _renewing = false);
    }
  }

  void _copy(String text, String what) {
    Clipboard.setData(ClipboardData(text: text));
    showMessage(context, tr('{0} nusxalandi', <Object?>[what]));
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr("Kartaga o'tkazma")),
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context, state == 'paid')),
      ),
      body: state == 'paid' ? _success() : _details(state),
    );
  }

  Widget _success() {
    return ListView(padding: const EdgeInsets.all(24), children: <Widget>[
      const SizedBox(height: 32),
      Center(
        child: Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(color: AppColors.soft(AppColors.success), shape: BoxShape.circle),
          child: Icon(Icons.check_rounded, size: 60, color: AppColors.success),
        ),
      ),
      const SizedBox(height: 18),
      Text(tr("To'lov qabul qilindi"), textAlign: TextAlign.center, style: AppTheme.title(size: 24)),
      const SizedBox(height: 8),
      Text(tr("O'tkazmangiz tasdiqlandi. Rahmat!"), textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
      const SizedBox(height: 20),
      AppCard(
        child: Column(children: <Widget>[
          KeyValue(tr('Summa'), money(asInt(_order['amount']))),
          if (asMap(_order['student'])['full_name'] != null) KeyValue(tr("O'quvchi"), asText(asMap(_order['student'])['full_name'])),
          if (asMap(_order['course'])['title'] != null) KeyValue(tr('Kurs'), asText(asMap(_order['course'])['title'])),
          if (_order['receipt'] != null) KeyValue(tr('Kvitansiya'), asText(_order['receipt'])),
          if (_order['paid_at'] != null) KeyValue(tr('Sana'), dateTime(_order['paid_at'])),
        ]),
      ),
      const SizedBox(height: 20),
      FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('Tayyor'))),
    ]);
  }

  Widget _details(String state) {
    final p2p = asMap(_order['p2p']);
    final card = cardGroups(asText(p2p['card']));
    final amount = asInt(p2p['amount']);
    final base = asInt(p2p['base_amount'], asInt(_order['amount']));
    final expires = DateTime.tryParse(asText(p2p['expires_at']))?.toLocal();
    final left = p2pRemaining(expires, DateTime.now());
    final expired = state == 'expired';
    final voided = state == 'void';
    final bank = asText(p2p['bank']) == 'humo' ? 'Humo' : 'Uzcard';
    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: <Widget>[
      if (voided)
        AppCard(color: AppColors.soft(AppColors.danger), child: Text(tr("Buyurtma bekor qilindi. Yangi to'lov boshlang yoki kassaga murojaat qiling.")))
      else
        AppCard(
          color: AppColors.soft(expired ? AppColors.danger : AppColors.warning),
          child: Row(children: <Widget>[
            Icon(expired ? Icons.timer_off_outlined : Icons.timer_outlined, color: expired ? AppColors.danger : AppColors.warning),
            const SizedBox(width: 10),
            Expanded(
              child: Text(expired
                  ? tr("Muddat tugadi. Agar pulni o'tkazgan bo'lsangiz, kuting — kassir tekshiradi. Aks holda yangi summa oling.")
                  : tr("Shu vaqt ichida o'tkazing: {0}", <Object?>[countdown(left)])),
            ),
          ]),
        ),
      const SizedBox(height: 14),
      Text(tr("Quyidagi kartaga aynan shu summani o'tkazing"), style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      AppCard(
        onTap: amount > 0 ? () => _copy('$amount', tr('Summa')) : null,
        child: Column(children: <Widget>[
          Text(tr("O'tkaziladigan summa"), style: TextStyle(color: AppColors.muted)),
          const SizedBox(height: 4),
          FittedBox(
            child: Text('${p2pAmountText(amount)} ${tr("so'm")}', style: TextStyle(fontSize: 36, fontWeight: FontWeight.w800, color: AppColors.ink, letterSpacing: 0.5)),
          ),
          if (amount != base && base > 0)
            Text(tr("Summa {0} dan biroz farq qiladi — shu farq to'lovingizni aniqlaydi. Yaxlitlamang.", <Object?>[money(base)]),
                textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
          const SizedBox(height: 8),
          TextButton.icon(onPressed: amount > 0 ? () => _copy('$amount', tr('Summa')) : null, icon: const Icon(Icons.copy, size: 18), label: Text(tr('Summani nusxalash'))),
        ]),
      ),
      const SizedBox(height: 10),
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Row(children: <Widget>[
            Text(tr('Karta raqami'), style: TextStyle(color: AppColors.muted)),
            const Spacer(),
            Pill(bank, color: AppColors.brand),
          ]),
          const SizedBox(height: 4),
          Row(children: <Widget>[
            Expanded(child: SelectableText(card, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: 1.2))),
            IconButton(tooltip: tr('Nusxalash'), onPressed: card.isEmpty ? null : () => _copy(digitsOnly(card), tr('Karta raqami')), icon: const Icon(Icons.copy)),
          ]),
          if (asText(p2p['holder']).isNotEmpty) KeyValue(tr('Karta egasi'), asText(p2p['holder'])),
        ]),
      ),
      const SizedBox(height: 14),
      Row(children: <Widget>[
        if (!expired && !voided) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        if (!expired && !voided) const SizedBox(width: 10),
        Expanded(
          child: Text(
            tr("Pul kelgach to'lov o'zi tasdiqlanadi (odatda 1–3 daqiqa). Bu sahifani yopsangiz ham to'lov hisobga olinadi."),
            style: TextStyle(color: AppColors.muted, fontSize: 13),
          ),
        ),
      ]),
      const SizedBox(height: 16),
      if (expired)
        FilledButton.icon(
          onPressed: _renewing ? null : _renew,
          icon: const Icon(Icons.refresh),
          label: Text(_renewing ? tr('Yuklanmoqda...') : tr('Yangi summa olish')),
        )
      else if (!voided)
        OutlinedButton.icon(onPressed: _check, icon: const Icon(Icons.refresh), label: Text(tr('Holatni tekshirish'))),
    ]);
  }
}
