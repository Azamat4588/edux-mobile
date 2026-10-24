// Kirish: telefon (yoki email) va parol, bir martalik kod (Telegram/SMS), «Telegram orqali kirish»;
// o'quvchi — shaxsiy havola orqali. Ota-ona hisobsiz ham to'lov havolasi bilan to'lay oladi. Til va server manzili shu yerda.
import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/help_links.dart';
import '../../core/design.dart';
import '../../core/i18n.dart';
import '../../core/motion.dart';
import '../../core/session.dart';
import '../../core/sms_gateway.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../access/sms_gateway_page.dart';
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
            decoration: const InputDecoration(hintText: 'https://edux.kuchkarov.uz'),
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

  /// Forma: sarlavha (hoshiya bilan), kirish usuli, maydonlar va qo'shimcha yo'llar.
  List<Widget> _form(Session session) {
    final host = Uri.tryParse(session.server)?.host ?? session.server;
    return <Widget>[
      HoshiyaBox(
        color: AppColors.accent,
        padding: const EdgeInsets.only(left: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Semantics(header: true, child: Text(tr('Hisobingizga kiring'), style: AppTheme.title(size: 26))),
          const SizedBox(height: 6),
          Text(_codeMode ? tr('Telefon raqamingizga bir martalik kod yuboramiz.') : tr('Telefon raqamingiz va parolingizni kiriting.'),
              style: TextStyle(color: AppColors.muted, fontSize: 15, height: 1.4)),
        ]),
      ),
      const SizedBox(height: 24),
      if (_options['login_code'] == true) ...<Widget>[
        SegmentedButton<bool>(
          expandedInsets: EdgeInsets.zero,
          showSelectedIcon: false,
          segments: <ButtonSegment<bool>>[
            ButtonSegment<bool>(value: false, icon: const Icon(Icons.password_rounded, size: 18), label: Text(tr('Parol'))),
            ButtonSegment<bool>(value: true, icon: const Icon(Icons.sms_outlined, size: 18), label: Text(tr('Kod bilan'))),
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
        HoshiyaBox(
          color: AppColors.toneDanger,
          background: AppColors.dangerBg,
          radius: BorderRadius.circular(AppRadius.control),
          padding: const EdgeInsets.all(12),
          child: Semantics(liveRegion: true, child: Text(_error!, style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w500))),
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
          decoration: InputDecoration(labelText: tr('Telefon raqam yoki email'), hintText: '+998 90 123 45 67', prefixIcon: const Icon(Icons.phone_outlined)),
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
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            suffixIcon: IconButton(
              tooltip: _hidden ? tr("Parolni ko'rsatish") : tr('Parolni yashirish'),
              icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
              onPressed: () => setState(() => _hidden = !_hidden),
            ),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
              : Text(tr('Kirish')),
        ),
      ],
      const SizedBox(height: 14),
      Row(children: <Widget>[
        Expanded(child: Divider(color: AppColors.line)),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text(tr('yoki'), style: TextStyle(color: AppColors.subtle, fontSize: 13))),
        Expanded(child: Divider(color: AppColors.line)),
      ]),
      const SizedBox(height: 14),
      if (_options['telegram_login'] == true) ...<Widget>[
        OutlinedButton.icon(
          onPressed: _busy ? null : () => loginWithTelegram(context),
          icon: const Icon(Icons.send_rounded, color: Color(0xFF229ED9)),
          label: Text(tr('Telegram orqali kirish')),
        ),
        const SizedBox(height: 10),
      ],
      OutlinedButton.icon(
        onPressed: _busy ? null : _inviteLogin,
        icon: const Icon(Icons.link_rounded),
        label: Text(tr('Havola orqali kirish')),
      ),
      const SizedBox(height: 20),
      Text(
          _options['login_code'] == true
              ? tr("Parolni unutgan bo'lsangiz, «Kod bilan» kiring yoki tashkilot direktoriga murojaat qiling.")
              : tr("Parolni unutgan bo'lsangiz, tashkilot direktoriga murojaat qiling."),
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.muted, fontSize: 13, height: 1.4)),
      const SizedBox(height: 4),
      Wrap(alignment: WrapAlignment.center, children: <Widget>[
        TextButton.icon(
          onPressed: () => HelpLinks.show(context, HelpLinks.login),
          icon: const Icon(Icons.help_outline, size: 18),
          label: Text(tr('Kira olmayapman?')),
        ),
        TextButton.icon(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PayLinkPage())),
          icon: const Icon(Icons.payments_outlined, size: 18),
          label: Text(tr("To'lov havolasi orqali to'lash")),
        ),
      ]),
      // Server manzili so'ralmaydi: ilova standart serverga ulanadi. O'z serveri bo'lgan tashkilot uchun —
      // logotipni uzoq bosib manzilni o'zgartirish mumkin; standartdan farqli bo'lsa, manzil shu yerda ko'rinadi.
      if (!session.usesDefaultServer) ...<Widget>[
        const SizedBox(height: 20),
        Center(
          child: TextButton.icon(
            onPressed: _changeServer,
            icon: const Icon(Icons.dns_outlined, size: 18),
            label: Text(host, style: TextStyle(color: AppColors.muted)),
          ),
        ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 840;
    final panel = _NotebookPanel(onLogoLongPress: _changeServer, wide: wide);
    if (wide) {
      return Scaffold(
        backgroundColor: AppColors.canvas,
        body: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          Expanded(flex: 5, child: panel),
          Expanded(
            flex: 6,
            child: SafeArea(
              child: Stack(children: <Widget>[
                Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(40, 56, 40, 32),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _form(session)),
                    ),
                  ),
                ),
                const Positioned(top: 8, right: 12, child: LanguageButton()),
              ]),
            ),
          ),
        ]),
      );
    }
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: ListView(
        padding: EdgeInsets.zero,
        children: <Widget>[
          panel,
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _form(session)),
          ),
        ],
      ),
    );
  }
}

/// Kirish oynasining «daftar varag'i» (veb: AuthShell 1.40): asosiy rangning eng to'q tusi, nozik katak, chapda qizil
/// hoshiya chizig'i va tizimdan uchta lahza (haqiqiy «Bugun» kartasi uslubida). Lahzalar bir marta ketma-ket paydo bo'ladi.
class _NotebookPanel extends StatelessWidget {
  const _NotebookPanel({required this.onLogoLongPress, required this.wide});

  final VoidCallback onLogoLongPress;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final moments = <(String, String, TodayTone)>[
      ('3', tr("o'quvchining qarzi bor"), TodayTone.danger),
      ('8 / 12', tr('test natijasi ota-onaga yuborildi'), TodayTone.success),
      ('16:00', tr('ING-5, davomat bir bosishda'), TodayTone.none),
    ];
    final content = Padding(
      padding: EdgeInsets.fromLTRB(wide ? 72 : 52, top + (wide ? 40 : 18), wide ? 48 : 20, wide ? 40 : 26),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: wide ? MainAxisAlignment.spaceBetween : MainAxisAlignment.start, children: <Widget>[
        Row(children: <Widget>[
          GestureDetector(onLongPress: onLogoLongPress, child: Image.asset('assets/brand/mark.png', width: 40, height: 40)),
          const SizedBox(width: 10),
          const Text('EduX', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.3)),
          const Spacer(),
          if (!wide) const LanguageButton(color: Colors.white),
        ]),
        if (!wide) const SizedBox(height: 22),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text(
            tr("Testlar, to'lovlar, davomat va jurnal — bitta oynada."),
            style: AppTheme.title(size: wide ? 34 : 25, color: Colors.white).copyWith(fontFamily: 'Literata', fontWeight: FontWeight.w600),
          ),
          SizedBox(height: wide ? 28 : 18),
          IntroScope(
            id: 'login-moments',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
              for (var i = 0; i < moments.length; i++)
                IntroItem(
                  index: i,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _Moment(value: moments[i].$1, text: moments[i].$2, tone: moments[i].$3, compact: !wide),
                  ),
                ),
            ]),
          ),
        ]),
        if (wide)
          Text('© ${DateTime.now().year} EduX', style: TextStyle(color: Colors.white.withAlpha(170), fontSize: 13)),
      ]),
    );
    return Container(
      color: AppColors.panel,
      child: CustomPaint(painter: _PanelPainter(), child: wide ? SizedBox.expand(child: content) : content),
    );
  }
}

/// Panel foni: oq rangdagi 22px katak (juda nozik) va chapda qizil hoshiya chizig'i.
class _PanelPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const step = 22.0;
    final grid = Paint()
      ..color = const Color(0x14FFFFFF)
      ..strokeWidth = 1;
    for (var x = step; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = step; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final margin = size.width > 600 ? 44.0 : 32.0;
    canvas.drawRect(Rect.fromLTWH(margin, 0, 2, size.height), Paint()..color = AppColors.margin.withAlpha(220));
  }

  @override
  bool shouldRepaint(_PanelPainter oldDelegate) => false;
}

/// Tizimdan lahza: oq karta, chap chetida ohang hoshiyasi, katta raqam va jumla (har doim yorug' ko'rinishda).
class _Moment extends StatelessWidget {
  const _Moment({required this.value, required this.text, required this.tone, required this.compact});

  final String value;
  final String text;
  final TodayTone tone;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    const tones = <TodayTone, Color>{TodayTone.danger: Color(0xFFC70036), TodayTone.success: Color(0xFF007A55)};
    const lines = <TodayTone, Color>{TodayTone.danger: Color(0xFFC70036), TodayTone.success: Color(0xFF00BC7D)};
    return Container(
      padding: EdgeInsets.fromLTRB(14, compact ? 9 : 12, 14, compact ? 9 : 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border(left: BorderSide(color: lines[tone] ?? Colors.white, width: AppSpacing.hoshiya)),
        boxShadow: const <BoxShadow>[BoxShadow(color: Color(0x33000000), blurRadius: 14, offset: Offset(0, 6), spreadRadius: -6)],
      ),
      child: Row(children: <Widget>[
        SizedBox(
          width: compact ? 64 : 76,
          child: Text(value, style: TextStyle(fontSize: compact ? 19 : 22, fontWeight: FontWeight.w700, color: tones[tone] ?? const Color(0xFF131C36), fontFeatures: AppTheme.tabular)),
        ),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF131C36), height: 1.3))),
      ]),
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
                ? (session.can('platform_sms')
                    ? tr("Platforma egasi paneli veb-versiyada ishlaydi. Ilovada — platforma SMS shlyuzi; tashkilot bo'limlari uchun xodim, o'quvchi yoki ota-ona sifatida kiring.")
                    // iPhone/iPad: SMS shlyuz yo'q (iOS ilovalarga SMS yuborishga ruxsat bermaydi).
                    : tr("Platforma egasi paneli veb-versiyada ishlaydi. Platforma SMS shlyuzi faqat Android ilovada; tashkilot bo'limlari uchun xodim, o'quvchi yoki ota-ona sifatida kiring."))
                : tr("Hisobingiz hali hech qaysi tashkilotga bog'lanmagan. O'quvchi yoki ota-ona bo'lsangiz, o'qituvchi bergan shaxsiy havolani oching. Xodim bo'lsangiz, direktordan sizni qo'shishni so'rang."),
            action: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
              // Platforma egasi: ilovada — platforma SMS shlyuzi (kirish va tiklash kodlari shu telefondan).
              if (session.can('platform_sms')) ...<Widget>[
                FilledButton.icon(
                  onPressed: () {
                    SmsGatewayService.platform.resume(session);
                    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SmsGatewayPage(platform: true)));
                  },
                  icon: const Icon(Icons.sms_outlined),
                  label: Text(tr('SMS shlyuz (platforma)')),
                ),
                const SizedBox(height: 10),
              ],
              OutlinedButton(onPressed: session.signOut, child: Text(tr('Chiqish'))),
            ]),
          ),
        ),
      ),
    );
  }
}
