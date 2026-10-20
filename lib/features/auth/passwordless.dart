// Parolsiz kirish (server 1.22+): telefon raqamga bir martalik kod (Telegram yoki SMS) va «Telegram orqali kirish».
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

/// Kod bilan kirish: avval raqam, keyin 6 xonali kod. Kodni qayta so'rash — 60 soniyadan keyin.
class CodeLoginForm extends StatefulWidget {
  const CodeLoginForm({super.key, required this.onError, this.busy = false, this.onBusy});

  /// Xato matni (null — tozalash) kirish sahifasidagi umumiy xabar maydoniga chiqadi.
  final void Function(String? message) onError;
  final bool busy;
  final ValueChanged<bool>? onBusy;

  @override
  State<CodeLoginForm> createState() => _CodeLoginFormState();
}

class _CodeLoginFormState extends State<CodeLoginForm> {
  static const int _resendSeconds = 60;

  final _phone = TextEditingController();
  final _code = TextEditingController();
  bool _sent = false;
  bool _busy = false;
  String? _info;
  int _left = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  void _setBusy(bool value) {
    setState(() => _busy = value);
    widget.onBusy?.call(value);
  }

  void _countdown() {
    _timer?.cancel();
    setState(() => _left = _resendSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _left = _left > 0 ? _left - 1 : 0);
      if (_left == 0) timer.cancel();
    });
  }

  Future<void> _request() async {
    final digits = _phone.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 9) {
      widget.onError(tr("Telefon raqamini to'liq kiriting, masalan +998 90 123 45 67."));
      return;
    }
    widget.onError(null);
    _setBusy(true);
    try {
      final message = await AppScope.read(context).requestLoginCode(_phone.text);
      if (!mounted) return;
      setState(() {
        _sent = true;
        _info = message.isEmpty ? null : tr(message);
      });
      _countdown();
    } on ApiException catch (error) {
      widget.onError(error.message);
    } finally {
      if (mounted) _setBusy(false);
    }
  }

  Future<void> _verify() async {
    final code = _code.text.trim();
    if (code.length != 6) {
      widget.onError(tr('Kod 6 ta raqamdan iborat.'));
      return;
    }
    widget.onError(null);
    _setBusy(true);
    try {
      await AppScope.read(context).loginWithCode(_phone.text, code);
    } on ApiException catch (error) {
      widget.onError(error.message);
    } finally {
      if (mounted) _setBusy(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _busy || widget.busy;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      TextField(
        controller: _phone,
        enabled: !_sent,
        keyboardType: TextInputType.phone,
        autocorrect: false,
        autofillHints: const <String>[AutofillHints.telephoneNumber],
        inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ()-]'))],
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _sent ? null : _request(),
        decoration: InputDecoration(
          labelText: tr('Telefon raqam'),
          hintText: '+998 90 123 45 67',
          suffixIcon: _sent
              ? IconButton(
                  tooltip: tr("Raqamni o'zgartirish"),
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: busy
                      ? null
                      : () => setState(() {
                            _sent = false;
                            _info = null;
                            _code.clear();
                          }),
                )
              : null,
        ),
      ),
      if (_sent) ...<Widget>[
        const SizedBox(height: 10),
        if (_info != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.soft(AppColors.brand), borderRadius: BorderRadius.circular(12)),
            child: Row(children: <Widget>[
              Icon(Icons.mark_email_read_outlined, color: AppColors.brand, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(_info!, style: TextStyle(color: AppColors.ink, fontSize: 13))),
            ]),
          ),
        const SizedBox(height: 14),
        TextField(
          controller: _code,
          autofocus: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          autofillHints: const <String>[AutofillHints.oneTimeCode],
          inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: 8),
          onChanged: (value) {
            if (value.length == 6 && !busy) _verify();
          },
          decoration: InputDecoration(labelText: tr('6 xonali kod'), counterText: ''),
        ),
      ],
      const SizedBox(height: 20),
      FilledButton(
        onPressed: busy ? null : (_sent ? _verify : _request),
        child: busy
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
            : Text(_sent ? tr('Kirish') : tr('Kod olish')),
      ),
      if (_sent)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: TextButton(
            onPressed: busy || _left > 0 ? null : _request,
            child: Text(_left > 0 ? tr('Kodni qayta yuborish ({0} s)', <Object?>[_left]) : tr('Kodni qayta yuborish')),
          ),
        ),
    ]);
  }
}

/// «Telegram orqali kirish»: botni ochadi va tasdiqni kutadi (har 2 soniyada holat so'raladi, 5 daqiqagacha).
Future<void> loginWithTelegram(BuildContext context) async {
  final session = AppScope.read(context);
  Map<String, dynamic> link;
  try {
    link = await session.startTelegramLogin();
  } on ApiException catch (error) {
    if (context.mounted) showMessage(context, error.message, error: true);
    return;
  }
  final key = asText(link['key']);
  final url = Uri.tryParse(asText(link['url']));
  if (key.isEmpty || url == null) {
    if (context.mounted) showMessage(context, tr("Telegram orqali kirib bo'lmadi. Qayta urinib ko'ring."), error: true);
    return;
  }
  // Telegram ilovasi (yoki brauzer) ochiladi; foydalanuvchi qaytguncha holat so'rab turiladi.
  unawaited(launchUrl(url, mode: LaunchMode.externalApplication));
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _TelegramWaitDialog(session: session, linkKey: key, url: url),
  );
}

class _TelegramWaitDialog extends StatefulWidget {
  const _TelegramWaitDialog({required this.session, required this.linkKey, required this.url});

  final Session session;
  final String linkKey;
  final Uri url;

  @override
  State<_TelegramWaitDialog> createState() => _TelegramWaitDialogState();
}

class _TelegramWaitDialogState extends State<_TelegramWaitDialog> with WidgetsBindingObserver {
  static const Duration _interval = Duration(seconds: 2);
  static const Duration _limit = Duration(minutes: 5);

  Timer? _timer;
  final DateTime _started = DateTime.now();
  String _status = 'pending';
  String? _error;
  bool _polling = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(_interval, (_) => _poll());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  /// Ilova fonda (foydalanuvchi Telegramda) — so'ralmaydi; qaytilganda kutmasdan darhol tekshiriladi.
  bool _foreground = true;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) _poll();
  }

  Future<void> _poll() async {
    if (_polling || !mounted || !_foreground) return;
    if (DateTime.now().difference(_started) > _limit) {
      _timer?.cancel();
      setState(() => _status = 'expired');
      return;
    }
    _polling = true;
    try {
      final status = await widget.session.pollTelegramLogin(widget.linkKey);
      if (!mounted) return;
      if (status == 'ok') {
        _timer?.cancel();
        Navigator.of(context).pop();
        return;
      }
      if (status == 'expired') _timer?.cancel();
      setState(() {
        _status = status;
        _error = null;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error.isNetwork) {
        setState(() => _error = error.message);
      } else {
        _timer?.cancel();
        setState(() {
          _status = 'expired';
          _error = error.message;
        });
      }
    } finally {
      _polling = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final expired = _status == 'expired';
    final String text;
    if (_status == 'need_phone') {
      text = tr("Bot telefon raqamingizni so'radi: Telegramda «Telefon raqamni yuborish» tugmasini bosing. Raqam tizimdagi hisobingizniki bo'lishi kerak.");
    } else if (expired) {
      text = tr("Kirish havolasi eskirdi. Qaytadan «Telegram orqali kirish» tugmasini bosing.");
    } else {
      text = tr("Telegramda EduX botida «Start» tugmasini bosing. Tasdiqlangach, ilova o'zi ochiladi.");
    }
    return AlertDialog(
      title: Row(children: <Widget>[
        const Icon(Icons.send_rounded, color: Color(0xFF229ED9)),
        const SizedBox(width: 10),
        Expanded(child: Text(tr('Telegram orqali kirish'))),
      ]),
      content: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        if (!expired) ...<Widget>[
          const SizedBox(height: 4),
          const SizedBox(width: 30, height: 30, child: CircularProgressIndicator(strokeWidth: 3)),
          const SizedBox(height: 16),
        ],
        Text(text, textAlign: TextAlign.center, style: TextStyle(color: AppColors.ink)),
        if (_error != null) ...<Widget>[
          const SizedBox(height: 10),
          Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
        ],
      ]),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(expired ? tr('Yopish') : tr('Bekor qilish'))),
        if (!expired)
          FilledButton.tonal(
            onPressed: () => launchUrl(widget.url, mode: LaunchMode.externalApplication),
            child: Text(tr('Telegramni ochish')),
          ),
      ],
    );
  }
}
