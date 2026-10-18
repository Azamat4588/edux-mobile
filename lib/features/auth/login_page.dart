// Kirish: telefon (yoki email) va parol; o'quvchi — shaxsiy havola orqali. Til va server manzili shu yerda.
import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../settings/language_button.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _login = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _hidden = true;
  String? _error;

  @override
  void dispose() {
    _login.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_login.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = tr('Telefon raqamingiz va parolingizni kiriting.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AppScope.read(context).login(_login.text, _password.text);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _inviteLogin() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Havola orqali kirish')),
        content: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Text(tr("O'quvchi shu havola orqali parolsiz kiradi: testlar, kurslar, jadval, to'lov va baholar bitta kabinetda."),
              style: const TextStyle(color: AppColors.muted)),
          const SizedBox(height: 14),
          TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(hintText: tr("O'qituvchi bergan havolani shu yerga qo'ying")),
          ),
        ]),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Bekor qilish'))),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: Text(tr('Kirish'))),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.trim().isEmpty || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = AppScope.read(context);
      // Havola boshqa serverniki bo'lsa (masalan, maktabning o'z manzili), shu serverga o'tamiz
      final uri = Uri.tryParse(value.trim());
      if (uri != null && uri.hasScheme && uri.host.isNotEmpty && value.contains('/join/')) {
        await session.setServer('${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}');
      }
      await session.loginWithInvite(value);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changeServer() async {
    final session = AppScope.read(context);
    final controller = TextEditingController(text: session.server);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Tizim manzili')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text(tr("Tashkilotingiz o'z serverida ishlasa yoki alohida manzil berilgan bo'lsa, shu yerga yozing."),
              style: const TextStyle(color: AppColors.muted)),
          const SizedBox(height: 14),
          TextField(
            controller: controller,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(hintText: 'https://app.edux.uz'),
          ),
        ]),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, defaultServer), child: Text(tr('Standart'))),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: Text(tr('Saqlash'))),
        ],
      ),
    );
    controller.dispose();
    if (value != null) await session.setServer(value);
  }

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context);
    final host = Uri.tryParse(session.server)?.host ?? session.server;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          children: <Widget>[
            const Align(alignment: Alignment.centerRight, child: LanguageButton()),
            const SizedBox(height: 24),
            Row(children: <Widget>[
              Image.asset('assets/brand/mark.png', width: 48, height: 48),
              const SizedBox(width: 12),
              const Text('EduX', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.ink)),
            ]),
            const SizedBox(height: 36),
            Text(tr('Hisobingizga kiring'), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.ink)),
            const SizedBox(height: 6),
            Text(tr('Telefon raqamingiz va parolingizni kiriting.'), style: const TextStyle(color: AppColors.muted, fontSize: 15)),
            const SizedBox(height: 28),
            if (_error != null) ...<Widget>[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.danger.withAlpha(20), borderRadius: BorderRadius.circular(12)),
                child: Text(_error!, style: const TextStyle(color: AppColors.danger)),
              ),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: _login,
              keyboardType: TextInputType.phone,
              autocorrect: false,
              textInputAction: TextInputAction.next,
              autofillHints: const <String>[AutofillHints.telephoneNumber, AutofillHints.email],
              decoration: InputDecoration(labelText: tr('Telefon raqam yoki email'), hintText: '+998 90 123 45 67'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _password,
              obscureText: _hidden,
              textInputAction: TextInputAction.done,
              autofillHints: const <String>[AutofillHints.password],
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: tr('Parol'),
                suffixIcon: IconButton(
                  icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _hidden = !_hidden),
                ),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                  : Text(tr('Kirish')),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _busy ? null : _inviteLogin,
              icon: const Icon(Icons.link_rounded),
              label: Text(tr('Havola orqali kirish')),
            ),
            const SizedBox(height: 18),
            Text(tr("Parolni unutgan bo'lsangiz, tashkilot direktoriga murojaat qiling."),
                textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
            const SizedBox(height: 28),
            Center(
              child: TextButton.icon(
                onPressed: _changeServer,
                icon: const Icon(Icons.dns_outlined, size: 18),
                label: Text(host, style: const TextStyle(color: AppColors.muted)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Hisob hech qaysi tashkilotga bog'lanmagan (masalan, platforma egasi — u veb-paneldan ishlaydi).
class NoOrganizationPage extends StatelessWidget {
  const NoOrganizationPage({super.key});

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context);
    final owner = session.user['is_platform_admin'] == true;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: EmptyState(
            icon: Icons.domain_disabled_outlined,
            text: owner
                ? tr('Platforma egasi paneli veb-versiyada ishlaydi. Ilovada tashkilot xodimi, o\'quvchi yoki ota-ona sifatida kiring.')
                : tr("Hisobingiz hali hech qaysi tashkilotga bog'lanmagan. O'quvchi yoki ota-ona bo'lsangiz, o'qituvchi bergan shaxsiy havolani oching. Xodim bo'lsangiz, direktordan sizni qo'shishni so'rang."),
            action: OutlinedButton(onPressed: session.signOut, child: Text(tr('Chiqish'))),
          ),
        ),
      ),
    );
  }
}
