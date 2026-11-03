// 3.17: Face ID bilan davomat — telefon kamerasi orqali. Yuzni tanish (face-api.js, 128 sonli deskriptor) brauzerda
// ishlaydi, shuning uchun ilova serverdagi /attendance/camera?mode=face&embed=1[&group_id=] sahifasini WebView'da ochadi
// (kiosk_page.dart kabi: kamera ruxsati oldindan, WebView so'rovi — grant). Kirish — ilova tokeni (labs_page.dart kabi
// localStorage: edu.token, edu.organization, edu.locale); yopilganda WebView xotirasi tozalanadi.
// Sahifadagi «Kamerani yopish» → /attendance/camera/done: ilova shu manzilni ushlab, sahifani true bilan yopadi.
import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../core/external_links.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/webview_guard.dart';
import '../../core/widgets.dart';

/// Veb sahifa manzili (server ildiziga nisbatan).
String faceCheckinPath({int? groupId}) {
  final query = <String, String>{'mode': 'face', 'embed': '1', if (groupId != null) 'group_id': '$groupId'};
  return Uri(path: '/attendance/camera', queryParameters: query).toString();
}

/// Sahifadagi «Kamerani yopish» bosildi (veb /attendance/camera/done ga o'tadi).
bool isCameraDoneUrl(String url) {
  final path = Uri.tryParse(url)?.path ?? '';
  return path.replaceAll(RegExp(r'/+$'), '') == '/attendance/camera/done';
}

/// Kamera ruxsatini oldindan so'raydi (WebView o'zi Android ruxsat oynasini ocha olmaydi).
Future<bool> ensureCameraPermission() async {
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

class FaceCheckinPage extends StatefulWidget {
  const FaceCheckinPage({super.key, this.groupId, this.groupName});

  /// Davomat varaqasidan — faqat shu guruh o'quvchilari belgilanadi; null — umumiy kirish.
  final int? groupId;
  final String? groupName;

  @override
  State<FaceCheckinPage> createState() => _FaceCheckinPageState();
}

class _FaceCheckinPageState extends State<FaceCheckinPage> {
  WebViewController? _controller;
  bool _denied = false;
  bool _closed = false;
  int _progress = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    // Token WebView xotirasida qolmasin (keyingi ochilishda qayta yoziladi).
    clearWebViewData();
    super.dispose();
  }

  void _done() {
    if (_closed || !mounted) return;
    _closed = true;
    Navigator.of(context).pop(true);
  }

  Future<void> _open() async {
    if (!await ensureCameraPermission()) {
      if (!mounted) return;
      setState(() => _denied = true);
      return;
    }
    if (!mounted) return;
    final session = AppScope.read(context);
    final server = session.server.replaceAll(RegExp(r'/+$'), '');
    final html = '<!doctype html><html><head><meta name="viewport" content="width=device-width"></head><body><script>'
        'try{localStorage.setItem("edu.token",${jsonEncode(session.token ?? '')});'
        'localStorage.setItem("edu.organization",${jsonEncode('${session.organizationId ?? ''}')});'
        'localStorage.setItem("edu.locale",${jsonEncode(I18n.locale)});}catch(e){}'
        'location.replace(${jsonEncode(faceCheckinPath(groupId: widget.groupId))});'
        '</script></body></html>';
    final controller = WebViewController(onPermissionRequest: (request) => request.grant())
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (value) {
          if (mounted) setState(() => _progress = value);
        },
        onNavigationRequest: (request) {
          if (isCameraDoneUrl(request.url)) {
            _done();
            return NavigationDecision.prevent;
          }
          if (isSystemLink(request.url)) {
            openSystemLink(request.url);
            return NavigationDecision.prevent;
          }
          // Faqat shu server (aynan origin): token yozilgan localStorage boshqa saytga ochilmasin.
          return sameOrigin(request.url, server) || request.url.startsWith('about:')
              ? NavigationDecision.navigate
              : NavigationDecision.prevent;
        },
        // Ehtiyot: sahifa manzilni history orqali almashtirsa ham.
        onUrlChange: (change) {
          final url = change.url;
          if (url != null && isCameraDoneUrl(url)) _done();
        },
      ))
      ..loadHtmlString(html, baseUrl: '$server/');
    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      platform.setMediaPlaybackRequiresUserGesture(false);
    }
    WakelockPlus.enable();
    setState(() => _controller = controller);
  }

  void _retry() {
    setState(() => _denied = false);
    _open();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      appBar: pageBar(context,
        title: Text(widget.groupName == null ? 'Face ID' : '${widget.groupName} · Face ID', maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: <Widget>[
          if (controller != null) IconButton(tooltip: tr('Yangilash'), onPressed: controller.reload, icon: const Icon(Icons.refresh)),
        ],
        bottom: _progress > 0 && _progress < 100
            ? PreferredSize(preferredSize: const Size.fromHeight(3), child: LinearProgressIndicator(value: _progress / 100, minHeight: 3))
            : null,
      ),
      body: _denied
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                  const Icon(Icons.no_photography_outlined, size: 48),
                  const SizedBox(height: 12),
                  Text(tr("Kamerani ochib bo'lmadi. Ilovaga kamera ruxsatini bering."), textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton.icon(onPressed: _retry, icon: const Icon(Icons.refresh), label: Text(tr('Qayta urinish'))),
                  const SizedBox(height: 8),
                  TextButton.icon(onPressed: openAppSettings, icon: const Icon(Icons.settings_outlined), label: Text(tr('Sozlamalar'))),
                ]),
              ),
            )
          : controller == null
              ? const Center(child: CircularProgressIndicator())
              : WebViewWidget(controller: controller),
    );
  }
}
