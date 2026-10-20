// Kirish: telefon (yoki email) va parol, bir martalik kod (Telegram/SMS), «Telegram orqali kirish»;
// o'quvchi — shaxsiy havola orqali. Ota-ona hisobsiz ham to'lov havolasi bilan to'lay oladi. Til va server manzili shu yerda.
import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../settings/language_button.dart';
import '../student/pay_link_page.dart';
import 'passwordless.dart';

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

  /// GET /auth/options: login_code, telegram_login (server sozlamasiga qarab tugmalar).
  Map<String, dynamic> _options = <String, dynamic>{};
  bool _codeMode = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadOptions());
  }

  Future<void> _loadOptions() async {
    try {
      final options = await AppScope.read(context).authOptions();
      if (!mounted) return;
      setState(() {
        _options = options;
        if (options['login_code'] != true) _codeMode = false;
      });
    } catch (_) {
      // Eski server yoki internet yo'q: faqat parol bilan kirish ko'rinadi.
    }
  }

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
              style: TextStyle(color: AppColors.muted)),
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
              style: TextStyle(color: AppColors.muted)),
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
    if (value != null) {
      await session.setServer(value);
      await _loadOptions();
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context);
    final host = Uri.tryParse(session.server)?.host ?? session.server;
    return Scaffold(
      backgroundColor: AppColors.card,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          children: <Widget>[
            const Align(alignment: Alignment.centerRight, child: LanguageButton()),
            const SizedBox(height: 24),
            Row(children: <Widget>[
              GestureDetector(onLongPress: _changeServer, child: Image.asset('assets/brand/mark.png', width: 48, height: 48)),
              const SizedBox(width: 12),
              Text('EduX', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.ink)),
            ]),
            const SizedBox(height: 36),
            Text(tr('Hisobingizga kiring'), style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.ink)),
            const SizedBox(height: 6),
            Text(_codeMode ? tr('Telefon raqamingizga bir martalik kod yuboramiz.') : tr('Telefon raqamingiz va parolingizni kiriting.'),
                style: TextStyle(color: AppColors.muted, fontSize: 15)),
            const SizedBox(height: 22),
            if (_options['login_code'] == true) ...<Widget>[
              SegmentedButton<bool>(
                segments: <ButtonSegment<bool>>[
                  ButtonSegment<bool>(value: false, icon: const Icon(Icons.password_rounded), label: Text(tr('Parol'))),
                  ButtonSegment<bool>(value: true, icon: const Icon(Icons.sms_outlined), label: Text(tr('Kod bilan'))),
                ],
                selected: <bool>{_codeMode},
                onSelectionChanged: _busy
                    ? null
                    : (value) => setState(() {
                          _codeMode = value.first;
                          _error = null;
                        }),
              ),
              const SizedBox(height: 18),
            ],
            if (_error != null) ...<Widget>[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.danger.withAlpha(20), borderRadius: BorderRadius.circular(12)),
                child: Text(_error!, style: const TextStyle(color: AppColors.danger)),
              ),
              const SizedBox(height: 16),
            ],
            if (_codeMode)
              CodeLoginForm(
                busy: _busy,
                onBusy: (value) => setState(() => _busy = value),
                onError: (message) => setState(() => _error = message),
              )
            else ...<Widget>[
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
            ],
            if (_options['telegram_login'] == true) ...<Widget>[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => loginWithTelegram(context),
                icon: const Icon(Icons.send_rounded, color: Color(0xFF229ED9)),
                label: Text(tr('Telegram orqali kirish')),
              ),
            ],
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _busy ? null : _inviteLogin,
              icon: const Icon(Icons.link_rounded),
              label: Text(tr('Havola orqali kirish')),
            ),
            const SizedBox(height: 18),
            Text(
                _options['login_code'] == true
                    ? tr("Parolni unutgan bo'lsangiz, «Kod bilan» kiring yoki tashkilot direktoriga murojaat qiling.")
                    : tr("Parolni unutgan bo'lsangiz, tashkilot direktoriga murojaat qiling."),
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted, fontSize: 13)),
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PayLinkPage())),
                icon: const Icon(Icons.payments_outlined, size: 18),
                label: Text(tr("To'lov havolasi orqali to'lash")),
              ),
            ),
            // Server manzili so'ralmaydi: ilova standart serverga ulanadi. O'z serveri bo'lgan tashkilot uchun —
            // logotipni uzoq bosib manzilni o'zgartirish mumkin; standartdan farqli bo'lsa, manzil shu yerda ko'rinadi.
            if (session.server != defaultServer) ...<Widget>[
              const SizedBox(height: 28),
              Center(
                child: TextButton.icon(
                  onPressed: _changeServer,
                  icon: const Icon(Icons.dns_outlined, size: 18),
                  label: Text(host, style: TextStyle(color: AppColors.muted)),
                ),
              ),
            ],
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
