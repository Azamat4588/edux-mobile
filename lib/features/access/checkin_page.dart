// Kirish nazorati (1.18): o'quvchi yoki xodim kartasidagi QR kodni telefon kamerasi bilan o'qib, kelganini qayd etadi.
// Server: POST checkins/scan {payload} — o'quvchi bugungi darsiga «keldi», ota-onasiga xabar.
// 3.4: Bluetooth / USB-OTG skaner (klaviatura rejimi) — tez ketma-ketlik + Enter = kod (lib/core/scan_keys.dart, veb
// scanner.js bilan bir xil); kamerada QR bilan birga kartadagi shtrix-kod (Code 128, 14 raqam) ham o'qiladi.
// 3.16: davomat varaqasidan «Kamera bilan» — shu sahifa [groupId] bilan: POST checkins/scan {payload, group_id}, faqat shu
// guruh o'quvchisi bugungi darsga belgilanadi ([onMarked] varaqadagi qatorni yangilaydi), boshqasi — 422 other_group (SnackBar).
// 3.17: skaner qurilmasi — [HidScannerListener] (lib/core/hid_scanner.dart); [camera] false — kamera o'chiq, katta «Skanerni
// qurilmaga tuting» holati va oxirgi natijalar ro'yxati (davomatdan «Skaner qurilmasi»); app bar'da kamerani o'chirish/yoqish
// (batareya tejash). Umumiy kirishda «Face ID» — FaceCheckinPage (veb /attendance/camera WebView'da).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/api.dart';
import '../../core/help_links.dart';
import '../../core/hid_scanner.dart';
import '../../core/i18n.dart';
import '../../core/profile.dart';
import '../../core/scan_keys.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/webview_guard.dart';
import '../../core/widgets.dart';
import 'face_checkin_page.dart';
import 'kiosk_page.dart';

class CheckinPage extends StatefulWidget {
  const CheckinPage({super.key, this.groupId, this.groupName, this.onMarked, this.camera = true});

  /// false — kamera o'chiq holda ochiladi (faqat skaner qurilmasi va «Kod bilan»); app bar'dan yoqish mumkin.
  final bool camera;

  /// Davomat varaqasidan ochilganda — guruh (faqat shu guruh o'quvchilari belgilanadi).
  final int? groupId;
  final String? groupName;

  /// Belgilangan o'quvchi (javobdagi student_id) — davomat varaqasi qatorini yangilaydi.
  final ValueChanged<int>? onMarked;

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
  late bool _camera = widget.camera;

  /// Oxirgi natijalar (yangisi tepada): ism yoki xato, vaqt, holat.
  final List<_ScanEntry> _history = <_ScanEntry>[];

  /// Oxirgi marta tashqi skanerdan kod kelgan vaqt (ekranda «Skaner ulangan» belgisi).
  DateTime? _keyboardSeen;

  /// Ketma-ket o'qishlar orasidagi qisqa tanaffus (davomat rejimi): kamera bitta kartani qayta-qayta yubormasin.
  DateTime? _pausedUntil;

  bool get _groupMode => widget.groupId != null;

  @override
  void dispose() {
    _hide?.cancel();
    _scanner.dispose();
    super.dispose();
  }

  /// Tashqi skaner (klaviatura) kodi. Oyna (masalan, «Kod bilan») ochiq bo'lsa — [HidScannerListener] aralashmaydi.
  void _onDeviceCode(String code) {
    final payload = normalizeScanPayload(code);
    if (payload.isEmpty) return;
    setState(() => _keyboardSeen = DateTime.now());
    _submit(payload);
  }

  Future<void> _toggleCamera() async {
    if (_camera) {
      try {
        await _scanner.stop();
      } catch (_) {
        // kamera allaqachon to'xtagan
      }
    }
    if (!mounted) return;
    setState(() => _camera = !_camera);
  }

  void _remember(_ScanEntry entry) {
    _history.insert(0, entry);
    if (_history.length > 20) _history.removeRange(20, _history.length);
  }

  Future<void> _openFace() async {
    await Navigator.of(context).push(MaterialPageRoute<bool>(builder: (_) => const FaceCheckinPage()));
  }

  Future<void> _submit(String payload) async {
    final now = DateTime.now();
    final last = _recent[payload];
    if (_sending || (last != null && now.difference(last).inSeconds < 6)) return;
    final paused = _pausedUntil;
    if (paused != null && now.isBefore(paused)) return;
    _recent[payload] = now;
    setState(() => _sending = true);
    try {
      final data = asMap(await AppScope.read(context).api.post('checkins/scan', <String, Object?>{
        'payload': payload,
        if (_groupMode) 'group_id': widget.groupId,
      }));
      HapticFeedback.mediumImpact();
      if (_groupMode) SystemSound.play(SystemSoundType.click);
      if (data['status'] == 'ok') _count++;
      final student = scannedStudentId(data);
      if (_groupMode && student != null) widget.onMarked?.call(student);
      _show(data, null);
    } on ApiException catch (error) {
      HapticFeedback.heavyImpact();
      if (_groupMode && error.status == 422) {
        // Boshqa guruh o'quvchisi (other_group) yoki xodim kartasi: server xabari — pastda.
        _remember(_ScanEntry(error.message, DateTime.now(), _ScanKind.error));
        if (mounted) showMessage(context, error.message, error: true);
      } else {
        _show(null, error.message);
      }
    } catch (e) {
      HapticFeedback.heavyImpact();
      _show(null, errorText(e));
    } finally {
      if (_groupMode) _pausedUntil = DateTime.now().add(const Duration(milliseconds: 1200));
      if (mounted) setState(() => _sending = false);
    }
  }

  void _show(Map<String, dynamic>? result, String? error) {
    if (!mounted) return;
    _hide?.cancel();
    _remember(_ScanEntry(
      error ?? asText(result?['name']),
      DateTime.now(),
      error != null ? _ScanKind.error : (result?['status'] == 'repeat' ? _ScanKind.repeat : _ScanKind.ok),
      time: result == null ? '' : asText(result['time']),
    ));
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
      appBar: pageBar(context,
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(_groupMode ? (widget.groupName ?? tr('Kamera bilan')) : tr('Kirish nazorati')),
        actions: <Widget>[
          if (!_groupMode)
            IconButton(tooltip: 'Face ID', icon: const Icon(Icons.face_outlined), onPressed: _openFace),
          if (session.canUseKiosk && !_groupMode)
            IconButton(
              tooltip: tr('Kiosk rejimi'),
              icon: const Icon(Icons.face_retouching_natural),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const KioskPage())),
            ),
          IconButton(
            tooltip: _camera ? tr("Kamerani o'chirish") : tr('Kamerani yoqish'),
            icon: Icon(_camera ? Icons.videocam_off_outlined : Icons.videocam_outlined),
            onPressed: _toggleCamera,
          ),
          if (_camera) ...<Widget>[
            IconButton(tooltip: tr('Chiroq'), icon: const Icon(Icons.flashlight_on_outlined), onPressed: () => _scanner.toggleTorch()),
            IconButton(tooltip: tr('Kamerani almashtirish'), icon: const Icon(Icons.cameraswitch_outlined), onPressed: () => _scanner.switchCamera()),
          ],
          const HelpButton(HelpLinks.checkin, color: Colors.white),
        ],
      ),
      body: HidScannerListener(
        onCode: _onDeviceCode,
        child: Stack(children: <Widget>[
        if (!_camera) Positioned.fill(bottom: 88, child: _deviceView()),
        if (_camera) Positioned.fill(
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
        if (_camera) Center(
          child: Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(border: Border.all(color: Colors.white70, width: 3), borderRadius: BorderRadius.circular(24)),
          ),
        ),
        if (_camera) Positioned(
          left: 16,
          right: 16,
          top: 16,
          child: Column(children: <Widget>[
            if (_groupMode)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(tr("Faqat shu guruh o'quvchilari bugungi darsga «keldi» deb belgilanadi"),
                    textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF86EFAC), fontSize: 13)),
              ),
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
        if (_camera && (result != null || _error != null))
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
              child: Text(_groupMode ? tr('Belgilandi: {0}', <Object?>[_count]) : tr('Bugun: {0}', <Object?>[_count]), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
      ]),
      ),
    );
  }

  /// Kamera o'chiq: skaner qurilmasini kutish va oxirgi natijalar.
  Widget _deviceView() {
    final seen = _keyboardSeen != null;
    return Column(children: <Widget>[
      const SizedBox(height: 28),
      Icon(Icons.qr_code_scanner, size: 88, color: seen ? const Color(0xFF86EFAC) : Colors.white70),
      const SizedBox(height: 14),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Text(tr('Skanerni qurilmaga tuting'),
            textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
      ),
      const SizedBox(height: 8),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Text(
          <String>[
            if (_groupMode) tr("Faqat shu guruh o'quvchilari bugungi darsga «keldi» deb belgilanadi"),
            seen ? tr('Tashqi skaner ishlayapti') : tr("USB yoki Bluetooth skanerni ulang — kartani skanerlang, kod o'zi yuboriladi"),
          ].join('\n'),
          textAlign: TextAlign.center,
          style: TextStyle(color: seen ? const Color(0xFF86EFAC) : Colors.white70, fontSize: 13.5),
        ),
      ),
      if (_sending) const Padding(padding: EdgeInsets.only(top: 16), child: CircularProgressIndicator(color: Colors.white)),
      const SizedBox(height: 16),
      Expanded(
        child: _history.isEmpty
            ? const SizedBox.shrink()
            : ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _history.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) => _ScanTile(entry: _history[index], highlight: index == 0 && (_result != null || _error != null)),
              ),
      ),
    ]);
  }
}

enum _ScanKind { ok, repeat, error }

class _ScanEntry {
  const _ScanEntry(this.title, this.at, this.kind, {this.time = ''});

  final String title;
  final DateTime at;
  final _ScanKind kind;

  /// Server qaytargan qayd vaqti («08:12»).
  final String time;
}

class _ScanTile extends StatelessWidget {
  const _ScanTile({required this.entry, required this.highlight});

  final _ScanEntry entry;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final color = switch (entry.kind) {
      _ScanKind.ok => AppColors.success,
      _ScanKind.repeat => AppColors.warning,
      _ScanKind.error => AppColors.danger,
    };
    final icon = switch (entry.kind) {
      _ScanKind.ok => Icons.check_circle,
      _ScanKind.repeat => Icons.history,
      _ScanKind.error => Icons.error_outline,
    };
    final clock = '${entry.at.hour.toString().padLeft(2, '0')}:${entry.at.minute.toString().padLeft(2, '0')}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: highlight ? color : Colors.white10,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: highlight ? 1 : 0.6)),
      ),
      child: Row(children: <Widget>[
        Icon(icon, color: highlight ? Colors.white : color, size: 26),
        const SizedBox(width: 12),
        Expanded(
          child: Text(entry.title,
              maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
        ),
        const SizedBox(width: 8),
        Text(
          entry.kind == _ScanKind.repeat ? tr('Allaqachon qayd etilgan · {0}', <Object?>[entry.time]) : (entry.time.isEmpty ? clock : entry.time),
          style: const TextStyle(color: Colors.white70, fontSize: 12.5),
        ),
      ]),
    );
  }
}
