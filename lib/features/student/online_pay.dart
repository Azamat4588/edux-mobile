// Onlayn to'lov (Click / Payme): o'quvchi o'zi uchun, ota-ona farzandi uchun. To'lov sahifasi brauzerda ochiladi,
// ilovaga qaytilganda buyurtma holati (GET /pay/orders/{id}) tekshiriladi.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

/// To'lov tugagach (yoki bekor qilinganda) chaqiriladi — masalan, balansni yangilash uchun.
typedef PaymentDone = void Function(bool paid);

Future<void> startOnlinePayment(BuildContext context, {int? studentId, int suggested = 0, PaymentDone? onDone}) async {
  final api = AppScope.read(context).api;
  Map<String, dynamic> options;
  try {
    options = asMap(await api.get('pay/options'));
  } on ApiException catch (error) {
    if (context.mounted) showMessage(context, error.message, error: true);
    return;
  }
  final providers = asMap(options['providers']);
  if (providers['click'] != true && providers['payme'] != true) {
    if (context.mounted) {
      showMessage(context, tr("Tashkilotda onlayn to'lov yoqilmagan. To'lovni markaz ma'muriyatiga topshiring."), error: true);
    }
    return;
  }
  if (!context.mounted) return;
  final orderId = await showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _PayForm(studentId: studentId, providers: providers, suggested: suggested, minAmount: asInt(options['min_amount'], 1000)),
    ),
  );
  if (orderId == null || !context.mounted) return;
  final paid = await showOrderStatus(context, orderId);
  onDone?.call(paid);
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    if (_checking || !mounted) return;
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
            child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.danger)),
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
  const _PayForm({required this.studentId, required this.providers, required this.suggested, required this.minAmount});

  final int? studentId;
  final Map<String, dynamic> providers;
  final int suggested;
  final int minAmount;

  @override
  State<_PayForm> createState() => _PayFormState();
}

class _PayFormState extends State<_PayForm> {
  late final TextEditingController _amount =
      TextEditingController(text: widget.suggested > 0 ? '${widget.suggested}' : '');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _pay(String provider) async {
    final amount = int.tryParse(_amount.text.replaceAll(RegExp(r'\D'), ''));
    if (amount == null || amount < widget.minAmount) {
      setState(() => _error = tr('Summani kiriting.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = AppScope.read(context).api;
      final order = asMap(await api.post('pay/orders', <String, Object?>{
        'purpose': 'tuition',
        'amount': amount,
        'student_id': widget.studentId,
      }));
      final checkout = asMap(await api.post('pay/orders/${asInt(order['id'])}/checkout', <String, Object?>{'provider': provider}));
      final url = Uri.tryParse(asText(checkout['url']));
      if (url == null) throw ApiException(500, tr("To'lov sahifasini ochib bo'lmadi. Qayta urinib ko'ring."));
      await launchUrl(url, mode: LaunchMode.externalApplication);
      // Varaq yopiladi va buyurtma holati ko'rsatiladi (startOnlinePayment davomi).
      if (mounted) Navigator.pop(context, asInt(order['id']));
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
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        Text(tr('Onlayn to\'lov'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 14),
        if (_error != null) ...<Widget>[
          Text(_error!, style: const TextStyle(color: AppColors.danger)),
          const SizedBox(height: 8),
        ],
        TextField(
          controller: _amount,
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          decoration: InputDecoration(labelText: tr("To'lanadigan summa (so'm)"), suffixText: tr("so'm")),
        ),
        if (widget.suggested > 0) ...<Widget>[
          const SizedBox(height: 6),
          Text('${tr('Hozirgi qarz:')} ${money(widget.suggested)}', style: TextStyle(color: AppColors.muted)),
        ],
        const SizedBox(height: 18),
        if (widget.providers['click'] == true)
          FilledButton(
            onPressed: _busy ? null : () => _pay('click'),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0B6CF2)),
            child: Text(tr('Click orqali to\'lash')),
          ),
        if (widget.providers['click'] == true && widget.providers['payme'] == true) const SizedBox(height: 10),
        if (widget.providers['payme'] == true)
          FilledButton(
            onPressed: _busy ? null : () => _pay('payme'),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF00BAC6)),
            child: Text(tr('Payme orqali to\'lash')),
          ),
      ]),
    );
  }
}
