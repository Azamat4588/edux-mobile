// "SMS shlyuz": shu telefonni markazning SMS yuboruvchisi qilish (faqat Android, direktor/administrator).
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/api.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/sms_gateway.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

class SmsGatewayPage extends StatefulWidget {
  const SmsGatewayPage({super.key});

  @override
  State<SmsGatewayPage> createState() => _SmsGatewayPageState();
}

class _SmsGatewayPageState extends State<SmsGatewayPage> {
  final SmsGatewayService gateway = SmsGatewayService.instance;
  bool _working = false;
  bool _awake = false;

  @override
  void initState() {
    super.initState();
    gateway.addListener(_changed);
  }

  @override
  void dispose() {
    gateway.removeListener(_changed);
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
        if (mounted) showMessage(context, tr("SMS yuborishga ruxsat berilmadi. Telefon sozlamalaridan EduX ilovasiga SMS ruxsatini bering."), error: true);
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

  String _time(DateTime? time) {
    if (time == null) return '—';
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  }

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(tr('SMS shlyuz'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          if (!gateway.supported)
            AppCard(child: Text(tr("SMS shlyuz faqat Android telefonda ishlaydi: iPhone ilovalarga SMS yuborishga ruxsat bermaydi.")))
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
                      Text(session.organizationName, style: TextStyle(color: AppColors.muted)),
                    ]),
                  ),
                ]),
                const SizedBox(height: 12),
                Text(
                  tr("Markaz SMS'lari (to'lov, qarzdorlik, eslatmalar) shu telefondagi SIM kartadan yuboriladi. Narx — operatoringiz tarifi bo'yicha."),
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
                    title: Text(tr("Oxirgi tekshiruv")),
                    trailing: Text(_time(gateway.lastPoll)),
                    onTap: () => gateway.poll(),
                  ),
                  if (gateway.lastError != null) ...<Widget>[
                    const Divider(),
                    ListTile(title: Text(tr('Oxirgi xato')), subtitle: Text(gateway.lastError!, style: const TextStyle(color: AppColors.danger))),
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
          ],
        ],
      ),
    );
  }
}
