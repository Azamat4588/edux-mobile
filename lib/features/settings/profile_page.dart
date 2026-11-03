// 3.16 «Profil» (barcha rollar, server 1.50): ism, parol va telefon raqami (kirish logini).
// API: PUT profile {name} → auth payload; PUT profile/password {current_password?, password, password_confirmation,
// logout_others}; POST profile/phone {phone, password} → {verify, phone (+ auth payload, verify=false bo'lsa)};
// POST profile/phone/confirm {code} → auth payload. Xatolar — 422 {message}.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/adaptive.dart';
import '../../core/api.dart';
import '../../core/i18n.dart';
import '../../core/profile.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _phonePassword = TextEditingController();
  final TextEditingController _code = TextEditingController();
  final TextEditingController _current = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirmation = TextEditingController();

  bool _savingName = false;
  bool _savingPhone = false;
  bool _savingPassword = false;
  bool _logoutOthers = true;
  bool _hidden = true;

  /// Kod kutilmoqda: shu raqamga SMS yuborildi.
  String? _pendingPhone;

  @override
  void initState() {
    super.initState();
    _name.text = AppScope.read(context).userName;
  }

  @override
  void dispose() {
    for (final controller in <TextEditingController>[_name, _phone, _phonePassword, _code, _current, _password, _confirmation]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _saveName() async {
    final session = AppScope.read(context);
    final name = _name.text.trim();
    if (name.length < 2) {
      showMessage(context, tr('Ismni kiriting.'), error: true);
      return;
    }
    setState(() => _savingName = true);
    try {
      final data = asMap(await session.api.put('profile', <String, Object?>{'name': name}));
      await session.applyProfile(data);
      if (!mounted) return;
      showMessage(context, tr('Saqlandi.'));
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    } finally {
      if (mounted) setState(() => _savingName = false);
    }
  }

  Future<void> _requestPhone() async {
    final session = AppScope.read(context);
    final phone = _phone.text.trim();
    if (phone.isEmpty || _phonePassword.text.isEmpty) {
      showMessage(context, tr('Yangi raqam va joriy parolni kiriting.'), error: true);
      return;
    }
    setState(() => _savingPhone = true);
    try {
      final result = PhoneChangeResult.fromJson(
          await session.api.post('profile/phone', <String, Object?>{'phone': phone, 'password': _phonePassword.text}));
      if (result.verify) {
        if (!mounted) return;
        setState(() {
          _pendingPhone = result.phone.isEmpty ? phone : result.phone;
          _code.clear();
        });
        showMessage(context, tr('{0} raqamiga tasdiqlash kodi yuborildi.', <Object?>[_pendingPhone]));
      } else {
        final auth = result.auth;
        if (auth != null) await session.applyProfile(auth);
        if (!mounted) return;
        _phoneChanged(result.phone);
      }
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    } finally {
      if (mounted) setState(() => _savingPhone = false);
    }
  }

  Future<void> _confirmPhone() async {
    final session = AppScope.read(context);
    final code = _code.text.trim();
    if (code.isEmpty) return;
    setState(() => _savingPhone = true);
    try {
      final data = asMap(await session.api.post('profile/phone/confirm', <String, Object?>{'code': code}));
      await session.applyProfile(data);
      if (!mounted) return;
      _phoneChanged(session.userPhone);
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    } finally {
      if (mounted) setState(() => _savingPhone = false);
    }
  }

  void _phoneChanged(String phone) {
    setState(() {
      _pendingPhone = null;
      _phone.clear();
      _phonePassword.clear();
      _code.clear();
    });
    showMessage(context, tr('Telefon raqami almashtirildi. Endi tizimga {0} bilan kiring.', <Object?>[phone]));
  }

  Future<void> _savePassword() async {
    final session = AppScope.read(context);
    final hasPassword = session.hasPassword;
    if ((hasPassword && _current.text.isEmpty) || _password.text.isEmpty) {
      showMessage(context, tr('Parolni kiriting.'), error: true);
      return;
    }
    if (_password.text != _confirmation.text) {
      showMessage(context, tr('Parollar bir xil emas.'), error: true);
      return;
    }
    setState(() => _savingPassword = true);
    try {
      final data = asMap(await session.api.put(
        'profile/password',
        passwordChangeBody(
          hasPassword: hasPassword,
          current: _current.text,
          password: _password.text,
          confirmation: _confirmation.text,
          logoutOthers: _logoutOthers,
        ),
      ));
      await session.markPasswordSet();
      if (!mounted) return;
      setState(() {
        _current.clear();
        _password.clear();
        _confirmation.clear();
      });
      showMessage(context, asText(data['message'], tr('Parol yangilandi.')));
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    } finally {
      if (mounted) setState(() => _savingPassword = false);
    }
  }

  Widget _busy(bool busy, String label) => busy
      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
      : Text(label);

  Widget _eye() => IconButton(
        tooltip: _hidden ? tr("Parolni ko'rsatish") : tr('Parolni yashirish'),
        icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
        onPressed: () => setState(() => _hidden = !_hidden),
      );

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context);
    final hasPassword = session.hasPassword;
    final pending = _pendingPhone;
    return Scaffold(
      appBar: pageBar(context, title: Text(tr('Profil'))),
      body: ListView(
        padding: readable(context, const EdgeInsets.fromLTRB(16, 16, 16, 32)),
        children: <Widget>[
          AppCard(
            child: Row(children: <Widget>[
              Avatar(session.userName, size: 52),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  Text(session.userName, style: AppTheme.title(size: 19)),
                  if (session.userPhone.isNotEmpty) Text(session.userPhone, style: TextStyle(color: AppColors.muted)),
                ]),
              ),
            ]),
          ),
          SectionTitle(tr('Ism')),
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: tr('Ism va familiya')),
              ),
              const SizedBox(height: 12),
              FilledButton(onPressed: _savingName ? null : _saveName, child: _busy(_savingName, tr('Saqlash'))),
            ]),
          ),
          SectionTitle(tr('Telefon raqami')),
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
              Row(children: <Widget>[
                Icon(Icons.info_outline, size: 18, color: AppColors.muted),
                const SizedBox(width: 8),
                Expanded(child: Text(tr('Telefon raqami — tizimga kirish logini'), style: TextStyle(color: AppColors.muted))),
              ]),
              const SizedBox(height: 8),
              KeyValue(tr('Hozirgi raqam'), session.userPhone.isEmpty ? '—' : session.userPhone),
              const SizedBox(height: 8),
              if (!hasPassword)
                Text(tr("Raqamni almashtirish uchun avval parol o'rnating (pastdagi «Parol o'rnatish»)."),
                    style: TextStyle(color: AppColors.warning))
              else if (pending == null) ...<Widget>[
                TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ()-]'))],
                  decoration: InputDecoration(labelText: tr('Yangi raqam'), hintText: '+998 90 123 45 67', prefixIcon: const Icon(Icons.phone_outlined)),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _phonePassword,
                  obscureText: _hidden,
                  decoration: InputDecoration(labelText: tr('Joriy parol'), suffixIcon: _eye()),
                ),
                const SizedBox(height: 12),
                FilledButton(onPressed: _savingPhone ? null : _requestPhone, child: _busy(_savingPhone, tr('Raqamni almashtirish'))),
              ] else ...<Widget>[
                Text(tr('{0} raqamiga yuborilgan kodni kiriting.', <Object?>[pending])),
                const SizedBox(height: 10),
                TextField(
                  controller: _code,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  maxLength: 10,
                  inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
                  autofillHints: const <String>[AutofillHints.oneTimeCode],
                  decoration: InputDecoration(labelText: tr('Tasdiqlash kodi')),
                ),
                const SizedBox(height: 6),
                Row(children: <Widget>[
                  TextButton(
                    onPressed: _savingPhone ? null : () => setState(() => _pendingPhone = null),
                    child: Text(tr('Bekor qilish')),
                  ),
                  const Spacer(),
                  FilledButton(onPressed: _savingPhone ? null : _confirmPhone, child: _busy(_savingPhone, tr('Tasdiqlash'))),
                ]),
              ],
            ]),
          ),
          SectionTitle(hasPassword ? tr("Parolni o'zgartirish") : tr("Parol o'rnatish")),
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
              if (hasPassword) ...<Widget>[
                TextField(
                  controller: _current,
                  obscureText: _hidden,
                  autofillHints: const <String>[AutofillHints.password],
                  decoration: InputDecoration(labelText: tr('Joriy parol'), suffixIcon: _eye()),
                ),
                const SizedBox(height: 10),
              ],
              TextField(
                controller: _password,
                obscureText: _hidden,
                autofillHints: const <String>[AutofillHints.newPassword],
                decoration: InputDecoration(labelText: tr('Yangi parol'), suffixIcon: hasPassword ? null : _eye()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _confirmation,
                obscureText: _hidden,
                decoration: InputDecoration(labelText: tr('Yangi parolni takrorlang')),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Boshqa qurilmalardan chiqish')),
                subtitle: Text(tr('Bu telefondan boshqa barcha kirishlar yopiladi')),
                value: _logoutOthers,
                onChanged: (value) => setState(() => _logoutOthers = value),
              ),
              const SizedBox(height: 4),
              FilledButton(onPressed: _savingPassword ? null : _savePassword, child: _busy(_savingPassword, tr('Saqlash'))),
            ]),
          ),
        ],
      ),
    );
  }
}
