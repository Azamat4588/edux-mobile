// To'lov havolasi (/p/<token>): ota-ona hisobsiz, markaz yuborgan havola orqali o'quvchi balansini to'ldiradi.
// GET /public/pay/{token} — o'quvchi, balans, to'lov turlari; POST /public/pay/{token}/checkout — to'lov sahifasi.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/payments.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

/// Havoladan token: "https://edux.kuchkarov.uz/p/AbC..." yoki tokenning o'zi.
String? payLinkToken(String value) {
  final text = value.trim();
  final match = RegExp(r'/p/([A-Za-z0-9]{20,40})').firstMatch(text);
  if (match != null) return match.group(1);
  return RegExp(r'^[A-Za-z0-9]{20,40}$').hasMatch(text) ? text : null;
}

class PayLinkPage extends StatefulWidget {
  const PayLinkPage({super.key, this.initial});

  final String? initial;

  @override
  State<PayLinkPage> createState() => _PayLinkPageState();
}

class _PayLinkPageState extends State<PayLinkPage> {
  late final TextEditingController _link = TextEditingController(text: widget.initial ?? '');
  final _amount = TextEditingController();
  String? _token;
  Map<String, dynamic>? _info;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if ((widget.initial ?? '').isNotEmpty) WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  @override
  void dispose() {
    _link.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    final token = payLinkToken(_link.text);
    if (token == null) {
      setState(() => _error = tr("Havola noto'g'ri. Markaz yuborgan to'liq havolani qo'ying."));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = AppScope.read(context);
      // Havola boshqa serverniki bo'lsa (kirish oynasida), shu serverga o'tamiz — xuddi taklif havolasidagidek.
      final uri = Uri.tryParse(_link.text.trim());
      if (!session.signedIn && uri != null && uri.hasScheme && uri.host.isNotEmpty) {
        await session.setServer('${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}');
      }
      final info = asMap(await session.api.get('public/pay/$token'));
      final balance = asInt(info['balance']);
      if (!mounted) return;
      setState(() {
        _token = token;
        _info = info;
        _amount.text = balance < 0 ? '${-balance}' : '';
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pay(String provider) async {
    final info = _info!;
    final min = asInt(info['min'], 1000);
    final amount = int.tryParse(_amount.text.replaceAll(RegExp(r'\D'), ''));
    if (amount == null || amount < min) {
      setState(() => _error = tr('Eng kam summa: {0}', <Object?>[money(min)]));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = asMap(await AppScope.read(context).api.post('public/pay/$_token/checkout', <String, Object?>{
        'provider': provider,
        'amount': amount,
      }));
      final url = Uri.tryParse(asText(data['url']));
      if (url == null) throw ApiException(500, tr("To'lov sahifasini ochib bo'lmadi. Qayta urinib ko'ring."));
      await launchUrl(url, mode: LaunchMode.externalApplication);
      if (mounted) showMessage(context, tr("To'lov tasdiqlangach, balans shu sahifada yangilanadi — «Yangilash» tugmasini bosing."));
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr("To'lov havolasi")),
        actions: <Widget>[
          if (info != null) IconButton(tooltip: tr('Yangilash'), onPressed: _busy ? null : _open, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          if (info == null) ...<Widget>[
            Text(tr("Markaz SMS yoki Telegram orqali yuborgan to'lov havolasini qo'ying — hisobga kirmasdan to'lash mumkin."),
                style: TextStyle(color: AppColors.muted)),
            const SizedBox(height: 16),
            TextField(
              controller: _link,
              autocorrect: false,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: tr("To'lov havolasi"),
                hintText: 'https://…/p/…',
                suffixIcon: IconButton(
                  tooltip: tr("Qo'yish"),
                  icon: const Icon(Icons.content_paste_rounded),
                  onPressed: () async {
                    final data = await Clipboard.getData(Clipboard.kTextPlain);
                    if (data?.text != null) _link.text = data!.text!;
                  },
                ),
              ),
              onSubmitted: (_) => _open(),
            ),
          ],
          if (_error != null) ...<Widget>[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: AppColors.danger)),
          ],
          if (info == null) ...<Widget>[
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _open,
              child: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                  : Text(tr('Ochish')),
            ),
          ] else
            _PayLinkBody(info: info, amount: _amount, busy: _busy, onPay: _pay),
        ],
      ),
    );
  }
}

class _PayLinkBody extends StatelessWidget {
  const _PayLinkBody({required this.info, required this.amount, required this.busy, required this.onPay});

  final Map<String, dynamic> info;
  final TextEditingController amount;
  final bool busy;
  final ValueChanged<String> onPay;

  @override
  Widget build(BuildContext context) {
    final organization = asMap(info['organization']);
    final student = asMap(info['student']);
    final providers = asMap(info['providers']);
    final balance = asInt(info['balance']);
    // Kartaga o'tkazma (P2P) bu sahifada yo'q — to'lov tizimlari (Click, Payme, Uzum Bank, Paynet, Oson, Alif Pay).
    final ready = readyProviders(providers, withP2p: false);
    final any = ready.isNotEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text(asText(organization['name']), style: TextStyle(color: AppColors.muted)),
          const SizedBox(height: 4),
          Row(children: <Widget>[
            Avatar(asText(student['name']), size: 44),
            const SizedBox(width: 12),
            Expanded(child: Text(asText(student['name']), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
          ]),
          const Divider(height: 24),
          KeyValue(balance < 0 ? tr('Qarz') : tr('Balans'), money(balance.abs()),
              valueColor: balance < 0 ? AppColors.danger : AppColors.success),
        ]),
      ),
      const SizedBox(height: 16),
      if (!any)
        EmptyState(icon: Icons.credit_card_off_outlined, text: tr("Tashkilotda onlayn to'lov yoqilmagan. To'lovni markaz ma'muriyatiga topshiring."))
      else ...<Widget>[
        TextField(
          controller: amount,
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          decoration: InputDecoration(labelText: tr("To'lanadigan summa (so'm)"), suffixText: tr("so'm")),
        ),
        const SizedBox(height: 18),
        for (var i = 0; i < ready.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: 10),
          FilledButton(
            onPressed: busy ? null : () => onPay(ready[i]),
            child: Text(tr("{0} orqali to'lash", <Object?>[providerNames[ready[i]] ?? ready[i]])),
          ),
        ],
      ],
    ]);
  }
}
