// "SMS shlyuz": shu telefonni markazning SMS yuboruvchisi qilish (faqat Android, direktor/administrator).
// 3.4: platforma egasi hisobida — platforma navbati (kirish va tiklash kodlari); tashkilotda — bank SMS'larini serverga
// yuborish (kartaga o'tkazmani avtomatik tasdiqlash), yoqish/o'chirish, jo'natuvchilar ro'yxati va oxirgi yuborilganlar.
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/bank_sms.dart';
import '../../core/format.dart';

import '../../core/help_links.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/sms_gateway.dart';
import '../../core/theme.dart';
import '../../core/webview_guard.dart';
import '../../core/widgets.dart';

class SmsGatewayPage extends StatefulWidget {
  const SmsGatewayPage({super.key, this.platform = false});

  /// Platforma navbati (platforma egasi).
  final bool platform;

  @override
  State<SmsGatewayPage> createState() => _SmsGatewayPageState();
}

class _SmsGatewayPageState extends State<SmsGatewayPage> {
  late final SmsGatewayService gateway = widget.platform ? SmsGatewayService.platform : SmsGatewayService.organization;
  final BankSmsForwarder bank = BankSmsForwarder.instance;
  bool _working = false;
  bool _awake = false;
  bool _bankWorking = false;

  @override
  void initState() {
    super.initState();
    gateway.addListener(_changed);
    bank.addListener(_changed);
  }

  @override
  void dispose() {
    gateway.removeListener(_changed);
    bank.removeListener(_changed);
    if (_awake) WakelockPlus.disable();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _turnOn(Session session) async {
    setState(() => _working = true);
    try {
      if (!await gateway.hasPermission() && !await gateway.requestPermission()) {
        if (mounted) {
          showMessage(context, tr('SMS yuborishga ruxsat berilmadi. Telefon sozlamalaridan EduX ilovasiga SMS ruxsatini bering.'),
              error: true, actionLabel: tr('Sozlamalar'), onAction: openAppSettings);
        }
        return;
      }
      await gateway.enable(session);
      if (mounted) showMessage(context, tr('Telefon SMS shlyuz sifatida ulandi.'));
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _turnOff() async {
    if (!await confirm(context, tr("Bu telefon SMS yuborishni to'xtatsinmi?"), action: tr("To'xtatish"), danger: true)) return;
    await gateway.disable();
  }

  Future<void> _bankOn(Session session) async {
    setState(() => _bankWorking = true);
    try {
      if (!await bank.hasPermission() && !await bank.requestPermission()) {
        if (mounted) {
          showMessage(context, tr('SMS qabul qilishga ruxsat berilmadi. Telefon sozlamalaridan EduX ilovasiga SMS ruxsatini bering.'),
              error: true, actionLabel: tr('Sozlamalar'), onAction: openAppSettings);
        }
        return;
      }
      await bank.enable(session, deviceModel: await gateway.deviceModel());
      if (mounted) showMessage(context, tr("Bank SMS'lari serverga yuboriladi."));
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _bankWorking = false);
    }
  }

  Future<void> _editSenders() async {
    final controller = TextEditingController(text: bank.senders.join(', '));
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr("Bank jo'natuvchilari")),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text(tr("SMS «kimdan» maydonidagi nomlar, vergul bilan. Faqat shu jo'natuvchilarning SMS'lari serverga yuboriladi."),
              style: TextStyle(color: AppColors.muted, fontSize: 13)),
          const SizedBox(height: 10),
          TextField(controller: controller, minLines: 3, maxLines: 8),
        ]),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, ''), child: Text(tr('Standart'))),
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Bekor qilish'))),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: Text(tr('Saqlash'))),
        ],
      ),
    );
    controller.dispose();
    if (value != null) await bank.setSenders(parseSenders(value));
  }

  static const Map<String, String> _bankStatus = <String, String>{
    'queued': 'Navbatda',
    'matched': 'Tasdiqlandi',
    'unmatched': "Noma'lum kirim",
    'duplicate': 'Takror',
    'not_credit': 'Kirim emas',
    'disabled': "O'chirilgan",
  };

  Color _bankColor(String status) {
    switch (status) {
      case 'matched':
        return AppColors.success;
      case 'unmatched':
        return AppColors.warning;
      case 'queued':
        return AppColors.brand;
    }
    return AppColors.muted;
  }

  List<Widget> _bankSection(Session session) {
    final items = <BankSmsRecord>[...bank.pending.reversed, ...bank.recent];
    return <Widget>[
      SectionTitle(tr("Bank SMS'lari (kartaga o'tkazma)")),
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text(
            tr("Kartaga o'tkazma kelganda bank yuborgan SMS serverga jo'natiladi va to'lov avtomatik tasdiqlanadi. Faqat bank jo'natuvchilarining SMS'lari yuboriladi."),
            style: TextStyle(color: AppColors.muted),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: bank.enabled,
            title: Text(tr("Bank SMS'larini yuborish")),
            subtitle: bank.serverDisabled ? Text(tr("Sozlamada SMS manbasi o'chirilgan (Sozlamalar → Onlayn to'lov)."), style: TextStyle(color: AppColors.warning)) : null,
            onChanged: _bankWorking ? null : (value) => value ? _bankOn(session) : bank.disable(),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.account_balance_outlined),
            title: Text(tr("Bank jo'natuvchilari")),
            subtitle: Text(bank.senders.take(6).join(', ') + (bank.senders.length > 6 ? ' …' : ''), maxLines: 2, overflow: TextOverflow.ellipsis),
            trailing: const Icon(Icons.edit_outlined),
            onTap: _editSenders,
          ),
          if (bank.pending.isNotEmpty)
            Text(tr('Yuborilmagan: {0} (internet kelganda ketadi)', <Object?>[bank.pending.length]), style: TextStyle(color: AppColors.warning)),
          if (bank.lastError != null) Text(bank.lastError!, style: TextStyle(color: AppColors.danger)),
          if (bank.enabled)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(onPressed: bank.drain, icon: const Icon(Icons.sync), label: Text(tr('Hozir yuborish'))),
            ),
        ]),
      ),
      if (items.isNotEmpty) ...<Widget>[
        SectionTitle(tr('Oxirgi yuborilganlar')),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(children: <Widget>[
            for (var i = 0; i < items.length && i < 20; i++) ...<Widget>[
              if (i > 0) const Divider(),
              ListTile(
                dense: true,
                title: Text(items[i].sender, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('${dateTime(items[i].receivedAt)}\n${items[i].body}', maxLines: 3, overflow: TextOverflow.ellipsis),
                isThreeLine: true,
                trailing: Pill(tr(_bankStatus[items[i].status] ?? items[i].status), color: _bankColor(items[i].status)),
              ),
            ],
          ]),
        ),
      ],
    ];
  }

  String _time(DateTime? time) {
    if (time == null) return '—';
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  }

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.platform ? tr('SMS shlyuz (platforma)') : tr('SMS shlyuz')),
        actions: <Widget>[HelpButton(widget.platform ? HelpLinks.platformSms : HelpLinks.deviceSms)],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          if (!gateway.supported)
            AppCard(child: Text(tr('SMS shlyuz faqat Android telefonda ishlaydi: iPhone ilovalarga SMS yuborishga ruxsat bermaydi.')))
          else ...<Widget>[
            AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Row(children: <Widget>[
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: (gateway.enabled ? AppColors.success : AppColors.muted).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.sms_outlined, color: gateway.enabled ? AppColors.success : AppColors.muted),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                      Text(gateway.enabled ? tr('Yoqilgan') : tr("O'chirilgan"), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      Text(widget.platform ? tr('Platforma kodlari') : session.organizationName, style: TextStyle(color: AppColors.muted)),
                    ]),
                  ),
                ]),
                const SizedBox(height: 12),
                Text(
                  widget.platform
                      ? tr("Platformaning kirish va parol tiklash kodlari shu telefondagi SIM kartadan yuboriladi. Kod 15 daqiqada yuborilmasa bekor bo'ladi.")
                      : tr("Markaz SMS'lari (to'lov, qarzdorlik, eslatmalar) shu telefondagi SIM kartadan yuboriladi. Narx — operatoringiz tarifi bo'yicha."),
                  style: TextStyle(color: AppColors.muted),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: gateway.enabled
                      ? OutlinedButton(onPressed: _turnOff, child: Text(tr("To'xtatish")))
                      : FilledButton(
                          onPressed: _working ? null : () => _turnOn(session),
                          child: Text(_working ? tr('Ulanmoqda...') : tr('Shu telefondan SMS yuborish')),
                        ),
                ),
              ]),
            ),
            if (gateway.enabled) ...<Widget>[
              SectionTitle(tr('Holat')),
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(children: <Widget>[
                  ListTile(title: Text(tr('Yuborildi (shu ochilishda)')), trailing: Text('${gateway.sentSession}', style: const TextStyle(fontWeight: FontWeight.w700))),
                  const Divider(),
                  ListTile(title: Text(tr('Yuborilmadi')), trailing: Text('${gateway.failedSession}', style: TextStyle(fontWeight: FontWeight.w700, color: gateway.failedSession > 0 ? AppColors.danger : null))),
                  const Divider(),
                  ListTile(title: Text(tr('Bugun yana yuborish mumkin')), trailing: Text('${gateway.leftToday}')),
                  const Divider(),
                  ListTile(
                    title: Text(tr('Oxirgi tekshiruv')),
                    trailing: Text(_time(gateway.lastPoll)),
                    onTap: () => gateway.poll(),
                  ),
                  if (gateway.lastError != null) ...<Widget>[
                    const Divider(),
                    ListTile(title: Text(tr('Oxirgi xato')), subtitle: Text(gateway.lastError!, style: TextStyle(color: AppColors.danger))),
                  ],
                ]),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                value: _awake,
                title: Text(tr("Ekran o'chmasin")),
                subtitle: Text(tr("Telefon zaryadda turgan bo'lsa yoqing — SMS'lar uzilishsiz ketadi")),
                onChanged: (value) {
                  setState(() => _awake = value);
                  value ? WakelockPlus.enable() : WakelockPlus.disable();
                },
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Text(
                  tr("Ilova ochiq tursin: navbat har 20 soniyada tekshiriladi. Ilova yopilsa, SMS'lar navbatda kutib turadi va keyingi ochilishda ketadi."),
                  style: TextStyle(color: AppColors.muted, fontSize: 13),
                ),
              ),
            ],
            if (!widget.platform && session.canUseSmsGateway) ..._bankSection(session),
          ],
        ],
      ),
    );
  }
}
