// Onlayn to'lov (Click / Payme): o'quvchi o'zi uchun, ota-ona farzandi uchun. To'lov sahifasi brauzerda ochiladi.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

Future<void> startOnlinePayment(BuildContext context, {int? studentId, int suggested = 0}) async {
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
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _PayForm(studentId: studentId, providers: providers, suggested: suggested, minAmount: asInt(options['min_amount'], 1000)),
    ),
  );
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
      if (mounted) {
        Navigator.pop(context);
        showMessage(context, tr("To'lov tasdiqlangach, kvitansiya «So'nggi to'lovlar» ro'yxatida ko'rinadi."));
      }
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
          Text('${tr('Hozirgi qarz:')} ${money(widget.suggested)}', style: const TextStyle(color: AppColors.muted)),
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
