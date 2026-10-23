// Kiosk rejimi (1.18): telefon yoki planshetni kirishga qo'yib, o'quvchilar QR karta yoki yuz (Face ID) orqali
// o'zlari qayd etiladi. Ilova serverdagi /kiosk/<token> sahifasini to'liq ekranda ochadi (yuzni tanish — brauzerda).
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../core/api.dart';
import '../../core/external_links.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/webview_guard.dart';
import '../../core/widgets.dart';

class KioskPage extends StatefulWidget {
  const KioskPage({super.key});

  @override
  State<KioskPage> createState() => _KioskPageState();
}

class _KioskPageState extends State<KioskPage> {
  String? _url;
  bool _loading = true;
  bool _working = false;
  String _mode = 'both';
  final TextEditingController _link = TextEditingController();

  String _key(Session session) => 'kiosk_url_${session.organizationId ?? 0}';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading) _restore();
  }

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _url = prefs.getString(_key(AppScope.read(context)));
      _loading = false;
    });
  }

  Future<void> _save(String url) async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    await prefs.setString(_key(AppScope.read(context)), url);
    setState(() => _url = url);
  }

  Future<void> _create() async {
    final session = AppScope.read(context);
    setState(() => _working = true);
    try {
      final data = asMap(await session.api.post('kiosks', <String, Object?>{
        'name': tr('Telefon — {0}', <Object?>[session.userName]),
        'mode': _mode,
      }));
      await _save(asText(data['url']));
      await _start();
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _useLink() async {
    final text = _link.text.trim();
    if (!RegExp(r'^https?://.+/kiosk/[A-Za-z0-9]{20,}$').hasMatch(text)) {
      showMessage(context, tr("Havola noto'g'ri. U «…/kiosk/…» ko'rinishida bo'ladi."), error: true);
      return;
    }
    await _save(text);
    await _start();
  }

  /// Kamera ruxsatini oldindan so'raydi (WebView o'zi Android ruxsat oynasini ocha olmaydi).
  Future<bool> _cameraPermission() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return false;
      final front = cameras.firstWhere((camera) => camera.lensDirection == CameraLensDirection.front, orElse: () => cameras.first);
      final controller = CameraController(front, ResolutionPreset.low, enableAudio: false);
      await controller.initialize();
      await controller.dispose();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _start() async {
    final url = _url;
    if (url == null) return;
    if (!await _cameraPermission()) {
      if (mounted) {
        showMessage(context, tr("Kamerani ochib bo'lmadi. Ilovaga kamera ruxsatini bering."),
            error: true, actionLabel: tr('Sozlamalar'), onAction: openAppSettings);
      }
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _KioskView(url: url)));
  }

  Future<void> _forget() async {
    if (!await confirm(context, tr("Bu telefondagi kiosk havolasi o'chirilsinmi? Kioskni veb panelda («Kirish nazorati → Kiosklar») butunlay o'chirishingiz mumkin."),
        action: tr("O'chirish"), danger: true)) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    await prefs.remove(_key(AppScope.read(context)));
    setState(() => _url = null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Kiosk rejimi'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: <Widget>[
              AppCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  Text(tr('Telefonni kirishga qo\'ying'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 6),
                  Text(
                    tr("O'quvchilar kartasini old kameraga ko'rsatadi yoki yuzini tanitadi — kelgani qayd etiladi va ota-onasiga xabar boradi. Telefonni zaryadga ulab, shtativga qo'ying."),
                    style: TextStyle(color: AppColors.muted),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
              if (_url != null) ...<Widget>[
                FilledButton.icon(onPressed: _start, icon: const Icon(Icons.play_arrow), label: Text(tr('Kioskni ochish'))),
                const SizedBox(height: 8),
                TextButton(onPressed: _forget, child: Text(tr('Boshqa kiosk ulash'))),
              ] else ...<Widget>[
                SectionTitle(tr('Qanday qayd etilsin')),
                AppCard(
                  padding: EdgeInsets.zero,
                  child: RadioGroup<String>(
                    groupValue: _mode,
                    onChanged: (value) => setState(() => _mode = value ?? 'both'),
                    child: Column(children: <Widget>[
                      RadioListTile<String>(value: 'both', title: Text(tr('QR karta va Face ID'))),
                      RadioListTile<String>(value: 'qr', title: Text(tr('Faqat QR karta'))),
                      RadioListTile<String>(value: 'face', title: Text(tr('Faqat Face ID'))),
                    ]),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(onPressed: _working ? null : _create, child: Text(_working ? tr('Yaratilmoqda...') : tr('Kiosk yaratish va ochish'))),
                SectionTitle(tr('Yoki mavjud kiosk havolasi')),
                TextField(
                  controller: _link,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(hintText: 'https://…/kiosk/…', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                OutlinedButton(onPressed: _useLink, child: Text(tr('Havola bilan ochish'))),
              ],
            ]),
    );
  }
}

class _KioskView extends StatefulWidget {
  const _KioskView({required this.url});

  final String url;

  @override
  State<_KioskView> createState() => _KioskViewState();
}

class _KioskViewState extends State<_KioskView> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController(onPermissionRequest: (request) => request.grant())
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      // sms:, SMSTO:, tel: havolalari — telefonning o'z ilovasida.
      ..setNavigationDelegate(NavigationDelegate(onNavigationRequest: (request) {
        if (isSystemLink(request.url)) {
          openSystemLink(request.url);
          return NavigationDecision.prevent;
        }
        // Kiosk faqat o'z serverida (xost bir xil; http→https yo'naltirish mumkin): begona havola ochilmaydi.
        final host = Uri.tryParse(request.url)?.host.toLowerCase();
        return (host != null && host.isNotEmpty && host == Uri.tryParse(widget.url)?.host.toLowerCase()) || request.url.startsWith('about:')
            ? NavigationDecision.navigate
            : NavigationDecision.prevent;
      }))
      ..loadRequest(Uri.parse(widget.url));
    final platform = _controller.platform;
    if (platform is AndroidWebViewController) {
      platform.setMediaPlaybackRequiresUserGesture(false);
    }
    WakelockPlus.enable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await confirm(context, tr('Kiosk rejimidan chiqilsinmi?'), action: tr('Chiqish'))) {
          if (context.mounted) Navigator.of(context).pop();
        }
      },
      child: Scaffold(backgroundColor: Colors.black, body: WebViewWidget(controller: _controller)),
    );
  }
}
