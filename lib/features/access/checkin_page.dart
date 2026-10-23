// Kirish nazorati (1.18): o'quvchi yoki xodim kartasidagi QR kodni telefon kamerasi bilan o'qib, kelganini qayd etadi.
// Server: POST checkins/scan {payload} — o'quvchi bugungi darsiga «keldi», ota-onasiga xabar.
// 3.4: Bluetooth / USB-OTG skaner (klaviatura rejimi) — tez ketma-ketlik + Enter = kod (lib/core/scan_keys.dart, veb
// scanner.js bilan bir xil); kamerada QR bilan birga kartadagi shtrix-kod (Code 128, 14 raqam) ham o'qiladi.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/api.dart';
import '../../core/help_links.dart';
import '../../core/i18n.dart';
import '../../core/scan_keys.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/webview_guard.dart';
import '../../core/widgets.dart';
import 'kiosk_page.dart';

class CheckinPage extends StatefulWidget {
  const CheckinPage({super.key});

  @override
  State<CheckinPage> createState() => _CheckinPageState();
}

class _CheckinPageState extends State<CheckinPage> {
  final MobileScannerController _scanner = MobileScannerController(
    formats: const <BarcodeFormat>[BarcodeFormat.qrCode, BarcodeFormat.code128],
    detectionSpeed: DetectionSpeed.normal,
  );
  final Map<String, DateTime> _recent = <String, DateTime>{};
  bool _sending = false;
  Map<String, dynamic>? _result;
  String? _error;
  Timer? _hide;
  int _count = 0;
  final ScanDetector _detector = ScanDetector();
  final Stopwatch _clock = Stopwatch()..start();

  /// Oxirgi marta tashqi skanerdan kod kelgan vaqt (ekranda «Skaner ulangan» belgisi).
  DateTime? _keyboardSeen;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _hide?.cancel();
    _scanner.dispose();
    super.dispose();
  }

  /// Tashqi skaner (klaviatura) tugmalari. Oyna (masalan, «Kod bilan») ochiq bo'lsa — aralashmaydi.
  bool _onKey(KeyEvent event) {
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return false;
    if (event is! KeyDownEvent) return false;
    final keyboard = HardwareKeyboard.instance;
    final code = _detector.feed(
      ScanKey(
        key: event.logicalKey.keyLabel,
        character: event.character,
        control: keyboard.isControlPressed,
        alt: keyboard.isAltPressed,
        meta: keyboard.isMetaPressed,
      ),
      _clock.elapsedMilliseconds,
    );
    if (code != null) {
      _keyboardSeen = DateTime.now();
      _submit(normalizeScanPayload(code));
      return true;
    }
    return _detector.pending;
  }

  Future<void> _submit(String payload) async {
    final now = DateTime.now();
    final last = _recent[payload];
    if (_sending || (last != null && now.difference(last).inSeconds < 6)) return;
    _recent[payload] = now;
    setState(() => _sending = true);
    try {
      final data = asMap(await AppScope.read(context).api.post('checkins/scan', <String, Object?>{'payload': payload}));
      HapticFeedback.mediumImpact();
      if (data['status'] == 'ok') _count++;
      _show(data, null);
    } catch (e) {
      HapticFeedback.heavyImpact();
      _show(null, errorText(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _show(Map<String, dynamic>? result, String? error) {
    if (!mounted) return;
    _hide?.cancel();
    setState(() {
      _result = result;
      _error = error;
    });
    _hide = Timer(const Duration(milliseconds: 2600), () {
      if (mounted) setState(() => _result = _error = null);
    });
  }

  Future<void> _enterCode() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Kod bilan')),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          maxLength: 14,
          inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(hintText: tr('Kartadagi 6 xonali kod yoki 14 raqamli shtrix-kod')),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Bekor qilish'))),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: Text(tr('Qayd etish'))),
        ],
      ),
    );
    if (code != null && isManualCode(code)) await _submit(code);
  }

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context);
    final result = _result;
    final ok = result != null && result['status'] == 'ok';
    final repeat = result != null && result['status'] == 'repeat';
    final marked = result == null ? const <dynamic>[] : (result['marked'] is List ? result['marked'] as List : const <dynamic>[]);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(tr('Kirish nazorati')),
        actions: <Widget>[
          if (session.canUseKiosk)
            IconButton(
              tooltip: tr('Kiosk rejimi'),
              icon: const Icon(Icons.face_retouching_natural),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const KioskPage())),
            ),
          IconButton(tooltip: tr('Chiroq'), icon: const Icon(Icons.flashlight_on_outlined), onPressed: () => _scanner.toggleTorch()),
          IconButton(tooltip: tr('Kamerani almashtirish'), icon: const Icon(Icons.cameraswitch_outlined), onPressed: () => _scanner.switchCamera()),
          const HelpButton(HelpLinks.checkin, color: Colors.white),
        ],
      ),
      body: Stack(children: <Widget>[
        Positioned.fill(
          child: MobileScanner(
            controller: _scanner,
            onDetect: (capture) {
              for (final barcode in capture.barcodes) {
                final value = barcode.rawValue;
                if (value != null && value.isNotEmpty) {
                  _submit(value.trim());
                  break;
                }
              }
            },
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                  Text(tr("Kamerani ochib bo'lmadi. Ilovaga kamera ruxsatini bering."),
                      textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
                  const SizedBox(height: 12),
                  // Kod yoki skaner qurilmasi bilan ishlash davom etadi; ruxsat — sozlamalardan.
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: Colors.white70),
                    onPressed: openAppSettings,
                    icon: const Icon(Icons.settings_outlined),
                    label: Text(tr('Sozlamalar')),
                  ),
                ]),
              ),
            ),
          ),
        ),
        Center(
          child: Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(border: Border.all(color: Colors.white70, width: 3), borderRadius: BorderRadius.circular(24)),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          top: 16,
          child: Column(children: <Widget>[
            Text(tr('QR yoki shtrix-kodni ramka ichiga, 15–25 sm masofada tuting'),
                textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 15, shadows: <Shadow>[Shadow(blurRadius: 6)])),
            const SizedBox(height: 6),
            Text(
              _keyboardSeen != null ? tr('Tashqi skaner ishlayapti') : tr('Bluetooth yoki USB skaner ulansa — kartani skanerlang, kod o\'zi yuboriladi'),
              textAlign: TextAlign.center,
              style: TextStyle(color: _keyboardSeen != null ? const Color(0xFF86EFAC) : Colors.white70, fontSize: 12.5),
            ),
          ]),
        ),
        if (_sending) const Center(child: CircularProgressIndicator(color: Colors.white)),
        if (result != null || _error != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: 96,
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: _error != null ? AppColors.danger : (repeat ? AppColors.warning : AppColors.success),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(children: <Widget>[
                Icon(_error != null ? Icons.error_outline : (ok ? Icons.check_circle : Icons.history), color: Colors.white, size: 40),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: <Widget>[
                    Text(_error ?? asText(result!['name']),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
                    if (result != null)
                      Text(
                        repeat
                            ? tr('Allaqachon qayd etilgan · {0}', <Object?>[asText(result['time'])])
                            : <String>[
                                tr('Qayd etildi · {0}', <Object?>[asText(result['time'])]),
                                if (marked.isNotEmpty) tr('Davomatga belgilandi: {0}', <Object?>[marked.join(', ')]),
                              ].join('\n'),
                        style: const TextStyle(color: Colors.white),
                      ),
                  ]),
                ),
              ]),
            ),
          ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 24,
          child: Row(children: <Widget>[
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54)),
                onPressed: _enterCode,
                icon: const Icon(Icons.dialpad),
                label: Text(tr('Kod bilan')),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(12)),
              child: Text(tr('Bugun: {0}', <Object?>[_count]), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
      ]),
    );
  }
}
