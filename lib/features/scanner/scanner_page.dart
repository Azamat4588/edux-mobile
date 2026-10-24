// Skaner: kamera varaqaning 4 burchak belgisini jonli kuzatadi, varaqa to'liq, yaqin va tiniq bo'lib, qimirlamay
// turganda o'zi suratga oladi. Varaqa telefonda o'qiladi (natija darhol), keyin navbat orqali serverga ketadi.
// Ketma-ket rejim: varaqani almashtirish kifoya — tugma bosish shart emas.
import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:edux_omr/edux_omr.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/webview_guard.dart';
import '../../core/widgets.dart';
import '../settings/settings_page.dart';
import 'exam_kit.dart';
import 'omr_worker.dart';
import 'scan_queue.dart';
import 'scan_result_view.dart';
import 'scans_page.dart';

/// Avtomatik suratga olish chegaralari (C++ yadro sinovlarida tanlangan).
class _Thresholds {
  static const double minPxPerMm = 3.6; // bundan uzoqda doirachalar va QR ishonchsiz
  static const double minSharpness = 0.30; // ~1 pikselgacha xiralik
  static const double minBrightness = 55;
  static const double maxMovement = 0.012; // ketma-ket kadrlar orasida burchaklar siljishi (diagonalga nisbatan)
  static const int stableFrames = 3;
}

enum _Hint { starting, noSheet, corners, closer, dark, blurry, hold, reading, ready, removeSheet, error }

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key, this.examId, this.examTitle});

  /// Tanlangan test (QR o'qilmasa ham savollar soni ma'lum bo'ladi va to'plam oldindan yuklanadi).
  final int? examId;
  final String? examTitle;

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> with WidgetsBindingObserver {
  CameraController? _camera;
  OmrWorker? _worker;
  String? _cameraError;
  bool _torch = false;

  // Jonli tahlil
  bool _analyzing = false;
  bool _reading = false;
  OmrDetection? _detection;
  int _frameWidth = 0;
  int _frameHeight = 0;
  int _rotation = 90;
  int _stable = 0;
  List<List<double>>? _previousQuad;
  GrayFrame? _lastFrame;
  _Hint _hint = _Hint.starting;
  String? _errorText;
  DateTime _lastAnalysis = DateTime.fromMillisecondsSinceEpoch(0);
  // O'qib bo'lmagandan keyin qisqa tanaffus: xabar ko'rinib tursin va tebranish takrorlanmasin
  DateTime _cooldownUntil = DateTime.fromMillisecondsSinceEpoch(0);

  // Ketma-ket rejim: o'qilgan varaqa olib qo'yilmaguncha qayta o'qilmaydi
  bool _waitRemoval = false;
  int _emptyFrames = 0;
  String? _lastSignature;

  ExamKit? _kit;
  QueuedScan? _lastItem;
  Uint8List? _lastPreview;
  int _sessionCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();
    ScannerPrefs.load();
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable();
    _stopCamera();
    _worker?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Orqa fonda kamera o'chiriladi (batareya va maxfiylik), qaytganda yana yoqiladi
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _stopCamera();
    } else if (state == AppLifecycleState.resumed && _camera == null) {
      _startCamera();
    }
  }

  Future<void> _start() async {
    final session = AppScope.read(context);
    if (widget.examId != null) {
      KitStore.instance.get(session.api, widget.examId!).then((kit) {
        if (mounted) setState(() => _kit = kit);
      });
    }
    try {
      _worker = await OmrWorker.spawn();
    } catch (error) {
      setState(() => _cameraError = tr("Skaner yadrosini yuklab bo'lmadi: {0}", <Object?>[error]));
      return;
    }
    await _startCamera();
  }

  Future<void> _startCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw CameraException('none', 'no camera');
      final back = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => cameras.first);
      final controller = CameraController(
        back,
        ResolutionPreset.veryHigh,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      try {
        await controller.setFocusMode(FocusMode.auto);
        await controller.setFlashMode(_torch ? FlashMode.torch : FlashMode.off);
      } catch (_) {}
      _rotation = back.sensorOrientation;
      setState(() {
        _camera = controller;
        _cameraError = null;
        _hint = _Hint.noSheet;
      });
      await controller.startImageStream(_onFrame);
    } on CameraException catch (error) {
      if (!mounted) return;
      setState(() => _cameraError = error.code == 'CameraAccessDenied' || error.code == 'CameraAccessDeniedWithoutPrompt'
          ? tr('Kameraga ruxsat berilmagan. Telefon sozlamalarida EduX ga kamera ruxsatini bering.')
          : tr('Kamera ochilmadi'));
    }
  }

  Future<void> _stopCamera() async {
    final camera = _camera;
    _camera = null;
    if (camera == null) return;
    try {
      if (camera.value.isStreamingImages) await camera.stopImageStream();
    } catch (_) {}
    await camera.dispose();
  }

  // ------------------------------------------------------------------ kadrlar
  void _onFrame(CameraImage image) {
    if (_analyzing || _reading || _worker == null) return;
    // ~8 kadr/soniya yetarli (batareya tejaladi)
    final now = DateTime.now();
    if (now.difference(_lastAnalysis).inMilliseconds < 110) return;
    _lastAnalysis = now;
    _analyzing = true;
    final plane = image.planes.first;
    final frame = GrayFrame(Uint8List.fromList(plane.bytes), image.width, image.height, plane.bytesPerRow);
    _analyze(frame).whenComplete(() => _analyzing = false);
  }

  Future<void> _analyze(GrayFrame frame) async {
    final worker = _worker;
    if (worker == null) return;
    OmrDetection detection;
    try {
      detection = await worker.detect(frame, workMaxSide: 800);
    } catch (_) {
      return;
    }
    if (!mounted || _reading) return;
    _frameWidth = frame.width;
    _frameHeight = frame.height;
    _lastFrame = frame;

    final quad = detection.quad;
    final moved = _movement(quad);
    _previousQuad = quad;

    if (_waitRemoval) {
      // Avvalgi varaqa hali kamerada: yangisi qo'yilishini kutamiz
      if (detection.found == 0) {
        _emptyFrames++;
        if (_emptyFrames >= 2) {
          _waitRemoval = false;
          _emptyFrames = 0;
        }
      } else {
        _emptyFrames = 0;
        if (moved > 0.25) _waitRemoval = false; // boshqa varaqa (keskin o'zgardi)
      }
      setState(() {
        _detection = detection;
        _hint = _waitRemoval ? _Hint.removeSheet : _Hint.noSheet;
      });
      return;
    }

    _Hint hint;
    if (detection.found == 0) {
      hint = _Hint.noSheet;
    } else if (quad == null || detection.found < 4) {
      hint = _Hint.corners;
    } else if (detection.pxPerMm < _Thresholds.minPxPerMm) {
      hint = _Hint.closer;
    } else if (detection.brightness > 0 && detection.brightness < _Thresholds.minBrightness) {
      hint = _Hint.dark;
    } else if (detection.sharpness < _Thresholds.minSharpness) {
      hint = _Hint.blurry;
    } else if (moved > _Thresholds.maxMovement) {
      hint = _Hint.hold;
    } else {
      hint = _Hint.ready;
    }
    if (DateTime.now().isBefore(_cooldownUntil)) {
      _stable = 0;
      setState(() => _detection = detection);
      return;
    }
    _stable = hint == _Hint.ready ? _stable + 1 : 0;
    setState(() {
      _detection = detection;
      _hint = hint == _Hint.ready && _stable < _Thresholds.stableFrames ? _Hint.hold : hint;
      if (hint != _Hint.ready) _errorText = null;
    });
    if (ScannerPrefs.autoCapture && _stable >= _Thresholds.stableFrames) {
      _stable = 0;
      await _capture(frame);
    }
  }

  /// Burchaklarning oldingi kadrga nisbatan siljishi (varaqa diagonaliga nisbatan).
  double _movement(List<List<double>>? quad) {
    final previous = _previousQuad;
    if (quad == null || previous == null) return 1;
    final diagonal = math.sqrt(math.pow(quad[2][0] - quad[0][0], 2) + math.pow(quad[2][1] - quad[0][1], 2));
    if (diagonal < 1) return 1;
    var total = 0.0;
    for (var i = 0; i < 4; i++) {
      total += math.sqrt(math.pow(quad[i][0] - previous[i][0], 2) + math.pow(quad[i][1] - previous[i][1], 2));
    }
    return total / 4 / diagonal;
  }

  // ------------------------------------------------------------------ o'qish
  Future<void> _capture(GrayFrame frame) async {
    final worker = _worker;
    if (worker == null || _reading) return;
    setState(() {
      _reading = true;
      _hint = _Hint.reading;
    });
    try {
      final reading = await worker.read(frame, questions: _kit?.questions ?? 0, options: _kit?.options ?? 0);
      if (!reading.ok) {
        _fail(reading.error);
        return;
      }
      final upload = await worker.encode(frame);
      await _accept(reading, upload);
    } catch (error) {
      _fail('$error');
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  Future<void> _accept(OmrReading reading, Uint8List? upload) async {
    if (upload == null) {
      _fail('encode');
      return;
    }
    final signature = '${reading.examId}|${reading.variant}|${reading.studentCode}|${reading.answers}';
    if (signature == _lastSignature) {
      // Xuddi shu varaqa qayta suratga olindi
      _waitRemoval = true;
      if (mounted) showMessage(context, tr('Bu varaqa hozirgina tekshirildi. Keyingisini qo\'ying.'));
      return;
    }
    final session = AppScope.read(context);
    ExamKit? kit = _kit;
    if (reading.examId != null && (kit == null || kit.examId != reading.examId)) {
      kit = await KitStore.instance.get(session.api, reading.examId!);
      if (kit != null && widget.examId == null) _kit = kit;
    }
    final grade = kit?.grade(reading.variant, reading.answers);
    final item = await ScanQueue.instance.add(
      image: upload,
      preview: reading.preview,
      reading: reading,
      kit: kit,
      grade: grade,
    );
    _lastSignature = signature;
    _feedback(reading.needsReview ? 'review' : 'ok');
    if (!mounted) return;
    setState(() {
      _lastItem = item;
      _lastPreview = reading.preview;
      _sessionCount++;
      _waitRemoval = ScannerPrefs.continuous;
      _errorText = null;
    });
  }

  void _fail(String? code) {
    _feedback('error');
    if (!mounted) return;
    String text;
    if (code == 'markers_not_found') {
      text = tr("Varaqaning burchak belgilari topilmadi. To'rt burchak ham ko'rinadigan qilib qayta rasmga oling.");
    } else if (code == 'qr_not_read') {
      text = tr("QR kod o'qilmadi. Rasmni yaqinroq va aniqroq oling yoki testni tanlab skanerlang.");
    } else if (code == 'bad_image') {
      text = tr("Rasm o'qilmadi. JPG yoki PNG fayl yuboring.");
    } else {
      text = tr('Varaqani qayta suratga oling.');
    }
    _cooldownUntil = DateTime.now().add(const Duration(milliseconds: 1800));
    setState(() {
      _hint = _Hint.error;
      _errorText = text;
    });
  }

  void _feedback(String kind) {
    if (!ScannerPrefs.sound) return;
    if (kind == 'ok') {
      HapticFeedback.mediumImpact();
      SystemSound.play(SystemSoundType.click);
    } else if (kind == 'review') {
      HapticFeedback.heavyImpact();
      SystemSound.play(SystemSoundType.click);
    } else {
      HapticFeedback.vibrate();
    }
  }

  Future<void> _shoot() async {
    final frame = _lastFrame;
    if (frame == null || _reading) return;
    _waitRemoval = false;
    await _capture(frame);
  }

  Future<void> _pickFromGallery() async {
    final worker = _worker;
    if (worker == null) return;
    final files = await ImagePicker().pickMultiImage(imageQuality: 95);
    if (files.isEmpty || !mounted) return;
    setState(() {
      _reading = true;
      _hint = _Hint.reading;
    });
    try {
      for (final file in files) {
        final reading = await worker.readEncoded(await file.readAsBytes(),
            questions: _kit?.questions ?? 0, options: _kit?.options ?? 0);
        if (!reading.ok) {
          _fail(reading.error);
          continue;
        }
        _lastSignature = null;
        await _accept(reading, reading.upload);
      }
    } finally {
      if (mounted) {
        setState(() {
          _reading = false;
          _waitRemoval = false;
        });
      }
    }
  }

  Future<void> _toggleTorch() async {
    final camera = _camera;
    if (camera == null) return;
    try {
      await camera.setFlashMode(_torch ? FlashMode.off : FlashMode.torch);
      setState(() => _torch = !_torch);
    } catch (_) {
      if (mounted) showMessage(context, tr("Chiroqni yoqib bo'lmadi."), error: true);
    }
  }

  // ------------------------------------------------------------------ ko'rinish
  String _hintText() {
    switch (_hint) {
      case _Hint.starting:
        return tr('Kamera ochilmoqda...');
      case _Hint.noSheet:
        return tr("Javob varaqasini kameraga ko'rsating");
      case _Hint.corners:
        return tr("To'rt burchakdagi belgi ham ko'rinsin");
      case _Hint.closer:
        return tr('Yaqinroq keling');
      case _Hint.dark:
        return tr("Qorong'i — chiroqni yoqing");
      case _Hint.blurry:
        return tr('Telefonni qimirlatmang');
      case _Hint.hold:
        return ScannerPrefs.autoCapture ? tr('Ushlab turing...') : tr('Tayyor — suratga oling');
      case _Hint.reading:
        return tr("O'qilmoqda...");
      case _Hint.ready:
        return tr('Tayyor');
      case _Hint.removeSheet:
        return tr('Tekshirildi — keyingi varaqani qo\'ying');
      case _Hint.error:
        return _errorText ?? tr('Varaqani qayta suratga oling.');
    }
  }

  Color _hintColor() {
    switch (_hint) {
      case _Hint.hold:
      case _Hint.ready:
      case _Hint.reading:
        return AppColors.success;
      case _Hint.removeSheet:
        return AppColors.brand;
      case _Hint.error:
        return AppColors.danger;
      case _Hint.dark:
      case _Hint.blurry:
      case _Hint.closer:
      case _Hint.corners:
        return AppColors.warning;
      default:
        return Colors.black87;
    }
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    final title = widget.examTitle ?? _kit?.title ?? tr('Skaner');
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: pageBar(context,
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        titleTextStyle: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: <Widget>[
          IconButton(
            tooltip: tr('Chiroq'),
            icon: Icon(_torch ? Icons.flash_on : Icons.flash_off),
            onPressed: camera == null ? null : _toggleTorch,
          ),
          IconButton(
            tooltip: tr('Galereyadan rasm tanlash'),
            icon: const Icon(Icons.photo_library_outlined),
            onPressed: _reading ? null : _pickFromGallery,
          ),
        ],
      ),
      body: Column(children: <Widget>[
        Expanded(
          child: _cameraError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                      const Icon(Icons.no_photography_outlined, color: Colors.white54, size: 52),
                      const SizedBox(height: 12),
                      Text(_cameraError!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                        onPressed: _pickFromGallery,
                        icon: const Icon(Icons.photo_library_outlined),
                        label: Text(tr('Galereyadan rasm tanlash')),
                      ),
                      // Ruxsat rad etilgan: sozlamalardan yoqib, shu yerga qaytib qayta urinadi.
                      const SizedBox(height: 8),
                      Wrap(alignment: WrapAlignment.center, spacing: 8, children: <Widget>[
                        TextButton.icon(
                          style: TextButton.styleFrom(foregroundColor: Colors.white70),
                          onPressed: openAppSettings,
                          icon: const Icon(Icons.settings_outlined),
                          label: Text(tr('Sozlamalar')),
                        ),
                        TextButton.icon(
                          style: TextButton.styleFrom(foregroundColor: Colors.white70),
                          onPressed: _startCamera,
                          icon: const Icon(Icons.refresh),
                          label: Text(tr('Qayta urinish')),
                        ),
                      ]),
                    ]),
                  ),
                )
              : camera == null || !camera.value.isInitialized
                  ? const Center(child: CircularProgressIndicator(color: Colors.white))
                  : _preview(camera),
        ),
        _bottomPanel(),
      ]),
    );
  }

  Widget _preview(CameraController camera) {
    final detection = _detection;
    final ready = _hint == _Hint.hold || _hint == _Hint.ready || _hint == _Hint.reading;
    return Stack(alignment: Alignment.center, children: <Widget>[
      Center(
        child: AspectRatio(
          aspectRatio: 1 / camera.value.aspectRatio,
          child: Stack(fit: StackFit.expand, children: <Widget>[
            CameraPreview(camera),
            CustomPaint(
              painter: _OverlayPainter(
                quad: detection?.quad,
                frameWidth: _frameWidth,
                frameHeight: _frameHeight,
                rotation: _rotation,
                color: _waitRemoval ? AppColors.brand : (ready ? AppColors.success : Colors.white),
              ),
            ),
          ]),
        ),
      ),
      Positioned(
        top: 14,
        left: 16,
        right: 16,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(color: _hintColor().withAlpha(225), borderRadius: BorderRadius.circular(99)),
            child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
              if (_hint == _Hint.reading)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                ),
              Flexible(
                child: Text(_hintText(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ]),
          ),
        ),
      ),
      Positioned(
        bottom: 18,
        child: GestureDetector(
          onTap: _reading ? null : _shoot,
          child: Container(
            width: 74,
            height: 74,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 4),
              color: _reading ? Colors.white24 : Colors.white.withAlpha(60),
            ),
            child: Icon(Icons.document_scanner_outlined, color: Colors.white.withAlpha(_reading ? 120 : 255), size: 32),
          ),
        ),
      ),
    ]);
  }

  Widget _bottomPanel() {
    return AnimatedBuilder(
      animation: ScanQueue.instance,
      builder: (context, _) {
        final queue = ScanQueue.instance;
        final last = _lastItem;
        return Container(
          color: Colors.black,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: SafeArea(
            top: false,
            child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
              if (last != null)
                ScanResultCard(
                  item: last,
                  onTap: () => showScanDetails(context, last, preview: _lastPreview, key: _kit?.keyFor(last.variant)),
                ),
              const SizedBox(height: 8),
              Row(children: <Widget>[
                Text(tr('Shu seansda: {0}', <Object?>[_sessionCount]), style: const TextStyle(color: Colors.white70)),
                const Spacer(),
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ScansPage())),
                  icon: const Icon(Icons.list_alt, size: 18),
                  label: Text(queue.waitingCount > 0
                      ? tr('Navbat: {0}', <Object?>[queue.waitingCount])
                      : tr('Tekshirilgan varaqalar')),
                ),
              ]),
            ]),
          ),
        );
      },
    );
  }
}

/// Kamera ustida varaqa chegarasi. Kadr koordinatalari ekranga kamera burilishi bilan o'tkaziladi.
class _OverlayPainter extends CustomPainter {
  _OverlayPainter({
    required this.quad,
    required this.frameWidth,
    required this.frameHeight,
    required this.rotation,
    required this.color,
  });

  final List<List<double>>? quad;
  final int frameWidth;
  final int frameHeight;
  final int rotation;
  final Color color;

  Offset _map(List<double> point, Size size) {
    var x = point[0];
    var y = point[1];
    var width = frameWidth.toDouble();
    var height = frameHeight.toDouble();
    // Android kadri sensor holatida (yotiq); iOS kadri allaqachon tik bo'lishi mumkin
    if (frameWidth > frameHeight) {
      if (rotation == 270) {
        final nx = y;
        final ny = width - x;
        x = nx;
        y = ny;
      } else {
        final nx = height - y;
        final ny = x;
        x = nx;
        y = ny;
      }
      final swap = width;
      width = height;
      height = swap;
    }
    return Offset(x / width * size.width, y / height * size.height);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final points = quad;
    if (points == null || frameWidth == 0) {
      // Yo'naltiruvchi ramka (A4 nisbatida)
      final w = size.width * 0.78;
      final h = math.min(size.height * 0.86, w * 297 / 210);
      final rect = Rect.fromCenter(center: size.center(Offset.zero), width: h * 210 / 297, height: h);
      final guide = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white70;
      const corner = 26.0;
      for (final c in <List<Offset>>[
        <Offset>[rect.topLeft, const Offset(corner, 0), const Offset(0, corner)],
        <Offset>[rect.topRight, const Offset(-corner, 0), const Offset(0, corner)],
        <Offset>[rect.bottomRight, const Offset(-corner, 0), const Offset(0, -corner)],
        <Offset>[rect.bottomLeft, const Offset(corner, 0), const Offset(0, -corner)],
      ]) {
        canvas.drawLine(c[0], c[0] + c[1], guide);
        canvas.drawLine(c[0], c[0] + c[2], guide);
      }
      return;
    }
    final mapped = points.map((p) => _map(p, size)).toList();
    final path = Path()..addPolygon(mapped, true);
    final shade = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addPath(path, Offset.zero);
    canvas.drawPath(shade, Paint()..color = Colors.black.withAlpha(90));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = color,
    );
    final dot = Paint()..color = color;
    for (final point in mapped) {
      canvas.drawCircle(point, 6, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _OverlayPainter oldDelegate) =>
      oldDelegate.quad != quad || oldDelegate.color != color || oldDelegate.frameWidth != frameWidth;
}
