// 3.34 (server 2.82): hisobni o'chirish — App Store (5.1.1(v)) va Google Play talabi: hisob ochiladigan ilovada uni
// o'chirish yo'li ham bo'lishi kerak.
// API: GET profile/delete → {can_delete, reason, needs_password}; DELETE profile {confirm, password?} → {ok, message}.
import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

class DeleteAccountPage extends StatefulWidget {
  const DeleteAccountPage({super.key});

  @override
  State<DeleteAccountPage> createState() => _DeleteAccountPageState();
}

class _DeleteAccountPageState extends State<DeleteAccountPage> {
  final TextEditingController _confirm = TextEditingController();
  final TextEditingController _password = TextEditingController();
  Map<String, dynamic>? _status;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _confirm.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = asMap(await AppScope.read(context).api.get('profile/delete'));
      if (mounted) setState(() => _status = data);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Future<void> _delete() async {
    final session = AppScope.read(context);
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr("Hisobni o'chirasizmi?")),
        content: Text(tr("Bu amalni ortga qaytarib bo'lmaydi.")),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Bekor qilish'))),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: Text(tr("O'chirish")),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final message = await session.deleteAccount(confirm: _confirm.text.trim(), password: _password.text);
      if (!mounted) return;
      showMessage(context, message);
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    return Scaffold(
      appBar: pageBar(context, title: Text(tr("Hisobni o'chirish"))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text(tr("Hisobni o'chirsangiz, ismingiz, telefon raqamingiz, emailingiz, Telegram bog'lanishi va parolingiz o'chiriladi. Barcha qurilmalardagi kirishlar yopiladi. Hisobni qayta tiklab bo'lmaydi.")),
              const SizedBox(height: 8),
              Text(
                tr("O'quv markazi yoki maktabga tegishli yozuvlar (baholar, davomat, to'lovlar) tashkilotda qoladi va «O'chirilgan foydalanuvchi» nomi bilan ko'rinadi — ularni tashkilot qonunga ko'ra saqlaydi. To'liq o'chirishni tashkilotingizdan so'rashingiz mumkin."),
                style: TextStyle(color: AppColors.muted),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          if (_error != null)
            AppCard(child: Text(_error!, style: TextStyle(color: AppColors.danger)))
          else if (status == null)
            const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
          else if (status['can_delete'] != true)
            AppCard(child: Text(asText(status['reason']), style: TextStyle(color: AppColors.warning)))
          else
            AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
                TextField(
                  controller: _confirm,
                  autocorrect: false,
                  decoration: InputDecoration(labelText: tr("Tasdiqlash uchun O'CHIRISH deb yozing")),
                  onChanged: (_) => setState(() {}),
                ),
                if (status['needs_password'] == true) ...<Widget>[
                  const SizedBox(height: 10),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    autofillHints: const <String>[AutofillHints.password],
                    decoration: InputDecoration(labelText: tr('Joriy parol')),
                  ),
                ],
                const SizedBox(height: 14),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
                  onPressed: _busy || _confirm.text.trim().isEmpty ? null : _delete,
                  child: _busy
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                      : Text(tr("Hisobni butunlay o'chirish")),
                ),
              ]),
            ),
        ],
      ),
    );
  }
}
