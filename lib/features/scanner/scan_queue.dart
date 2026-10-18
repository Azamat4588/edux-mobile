// Tekshirilgan varaqalar navbati: rasm va telefon o'qishi diskda saqlanadi va serverga ketma-ket yuboriladi.
// Internet yo'q bo'lsa — kutadi va o'zi qayta urinadi; ilova yopilsa ham yo'qolmaydi.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:edux_omr/edux_omr.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../core/api.dart';
import '../../core/session.dart';
import 'exam_kit.dart';

class ScanStatus {
  static const String waiting = 'waiting';
  static const String uploading = 'uploading';
  static const String processed = 'processed';
  static const String needsReview = 'needs_review';
  static const String failed = 'failed';
  static const String offline = 'offline';
}

class QueuedScan {
  QueuedScan({
    required this.id,
    required this.organizationId,
    required this.createdAt,
    required this.device,
    this.examId,
    this.examTitle,
    this.variant,
    this.studentCode,
    this.studentName,
    this.localCorrect,
    this.localTotal,
    this.localScore,
    this.localMax,
    this.status = ScanStatus.waiting,
    this.message,
    this.scanId,
    this.serverCorrect,
    this.serverTotal,
    this.serverScore,
    this.serverMax,
    this.serverStudent,
    this.attempts = 0,
  });

  factory QueuedScan.fromJson(Map<String, dynamic> json) => QueuedScan(
        id: asText(json['id']),
        organizationId: asInt(json['organization_id']),
        createdAt: DateTime.tryParse(asText(json['created_at'])) ?? DateTime.now(),
        device: asMap(json['device']),
        examId: json['exam_id'] == null ? null : asInt(json['exam_id']),
        examTitle: json['exam_title'] as String?,
        variant: json['variant'] == null ? null : asInt(json['variant']),
        studentCode: json['student_code'] as String?,
        studentName: json['student_name'] as String?,
        localCorrect: json['local_correct'] == null ? null : asInt(json['local_correct']),
        localTotal: json['local_total'] == null ? null : asInt(json['local_total']),
        localScore: json['local_score'] == null ? null : asDouble(json['local_score']),
        localMax: json['local_max'] == null ? null : asDouble(json['local_max']),
        status: asText(json['status'], ScanStatus.waiting),
        message: json['message'] as String?,
        scanId: json['scan_id'] == null ? null : asInt(json['scan_id']),
        serverCorrect: json['server_correct'] == null ? null : asInt(json['server_correct']),
        serverTotal: json['server_total'] == null ? null : asInt(json['server_total']),
        serverScore: json['server_score'] == null ? null : asDouble(json['server_score']),
        serverMax: json['server_max'] == null ? null : asDouble(json['server_max']),
        serverStudent: json['server_student'] as String?,
        attempts: asInt(json['attempts']),
      );

  final String id;
  final int organizationId;
  final DateTime createdAt;

  /// Telefon o'qishi (serverga `device_result` sifatida yuboriladi).
  final Map<String, dynamic> device;
  final int? examId;
  final String? examTitle;
  final int? variant;
  final String? studentCode;
  final String? studentName;
  final int? localCorrect;
  final int? localTotal;
  final double? localScore;
  final double? localMax;
  String status;
  String? message;
  int? scanId;
  int? serverCorrect;
  int? serverTotal;
  double? serverScore;
  double? serverMax;
  String? serverStudent;
  int attempts;

  bool get done => status == ScanStatus.processed || status == ScanStatus.needsReview || status == ScanStatus.failed;
  bool get pending => !done;
  String get displayName => serverStudent ?? studentName ?? (studentCode != null ? '#$studentCode' : '—');

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'organization_id': organizationId,
        'created_at': createdAt.toIso8601String(),
        'device': device,
        'exam_id': examId,
        'exam_title': examTitle,
        'variant': variant,
        'student_code': studentCode,
        'student_name': studentName,
        'local_correct': localCorrect,
        'local_total': localTotal,
        'local_score': localScore,
        'local_max': localMax,
        'status': status,
        'message': message,
        'scan_id': scanId,
        'server_correct': serverCorrect,
        'server_total': serverTotal,
        'server_score': serverScore,
        'server_max': serverMax,
        'server_student': serverStudent,
        'attempts': attempts,
      };
}

class ScanQueue extends ChangeNotifier {
  ScanQueue._();

  static final ScanQueue instance = ScanQueue._();

  Session? _session;
  final List<QueuedScan> items = <QueuedScan>[];
  Directory? _dir;
  bool _loaded = false;
  bool _running = false;
  Timer? _retry;

  int get waitingCount => items.where((item) => item.pending).length;

  void attach(Session session) {
    if (identical(_session, session)) {
      return;
    }
    _session = session;
    _load().then((_) => kick());
  }

  Future<Directory> _directory() async {
    if (_dir != null) return _dir!;
    final dir = Directory('${(await getApplicationSupportDirectory()).path}/scan_queue');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    _dir = dir;
    return dir;
  }

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final index = File('${(await _directory()).path}/index.json');
      if (index.existsSync()) {
        final data = jsonDecode(await index.readAsString());
        items
          ..clear()
          ..addAll(asList(data, 'items').map(QueuedScan.fromJson));
        for (final item in items) {
          if (item.status == ScanStatus.uploading) item.status = ScanStatus.waiting;
        }
      }
    } catch (_) {
      // buzilgan indeks — navbat bo'sh boshlanadi
    }
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      final index = File('${(await _directory()).path}/index.json');
      await index.writeAsString(jsonEncode(<String, dynamic>{'items': items.map((item) => item.toJson()).toList()}));
    } catch (_) {}
  }

  File imageFile(QueuedScan item) => File('${_dir?.path ?? ''}/${item.id}.jpg');
  File previewFile(QueuedScan item) => File('${_dir?.path ?? ''}/${item.id}_preview.jpg');

  /// Yangi varaqani navbatga qo'yadi va yuborishni boshlaydi.
  Future<QueuedScan> add({
    required Uint8List image,
    Uint8List? preview,
    required OmrReading reading,
    ExamKit? kit,
    KitGrade? grade,
  }) async {
    final dir = await _directory();
    final session = _session;
    // Serverga keraksiz katta massiv (darkness) yuborilmaydi
    final device = Map<String, dynamic>.from(reading.raw)..remove('darkness');
    final item = QueuedScan(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      organizationId: session?.organizationId ?? 0,
      createdAt: DateTime.now(),
      device: device,
      examId: reading.examId ?? kit?.examId,
      examTitle: kit?.title,
      variant: reading.variant,
      studentCode: reading.studentCode,
      studentName: kit?.studentName(reading.studentCode),
      localCorrect: grade?.correct,
      localTotal: grade?.total,
      localScore: grade?.score,
      localMax: grade?.maxScore,
    );
    await File('${dir.path}/${item.id}.jpg').writeAsBytes(image, flush: true);
    if (preview != null) await File('${dir.path}/${item.id}_preview.jpg').writeAsBytes(preview, flush: true);
    items.insert(0, item);
    _prune();
    await _save();
    notifyListeners();
    kick();
    return item;
  }

  /// Navbatdagilarni ketma-ket yuboradi.
  void kick() {
    if (_running || _session == null) return;
    _running = true;
    _retry?.cancel();
    _process().whenComplete(() => _running = false);
  }

  Future<void> _process() async {
    final session = _session;
    if (session == null || !session.signedIn) return;
    var networkDown = false;
    for (final item in List<QueuedScan>.of(items.reversed)) {
      if (item.done || item.organizationId != session.organizationId) continue;
      final ok = await _upload(session.api, item);
      if (!ok) {
        networkDown = true;
        break;
      }
    }
    await _save();
    if (networkDown) {
      _retry?.cancel();
      _retry = Timer(const Duration(seconds: 20), kick);
    }
  }

  /// false — internet yo'q (keyinroq qayta uriniladi).
  Future<bool> _upload(Api api, QueuedScan item) async {
    final file = imageFile(item);
    if (!file.existsSync()) {
      item.status = ScanStatus.failed;
      item.message = "Rasm topilmadi.";
      notifyListeners();
      return true;
    }
    item.status = ScanStatus.uploading;
    item.attempts++;
    notifyListeners();
    try {
      final response = asMap(await api.multipart(
        'scans',
        fields: <String, String>{'sync': '1', 'device_result': jsonEncode(item.device)},
        files: <http.MultipartFile>[http.MultipartFile.fromBytes('image', await file.readAsBytes(), filename: 'varaqa.jpg')],
      ));
      _applyServer(item, response);
      notifyListeners();
      return true;
    } on ApiException catch (error) {
      if (error.isNetwork) {
        item.status = ScanStatus.offline;
        item.message = error.message;
        notifyListeners();
        return false;
      }
      item.status = ScanStatus.failed;
      item.message = error.message;
      notifyListeners();
      return !error.isUnauthorized;
    }
  }

  void _applyServer(QueuedScan item, Map<String, dynamic> scan) {
    item.scanId = asInt(scan['id']);
    final status = asText(scan['status']);
    final attempt = asMap(scan['attempt']);
    item.message = scan['error'] as String?;
    if (attempt.isNotEmpty) {
      final correct = asInt(attempt['correct_count']);
      item.serverCorrect = correct;
      item.serverTotal = correct + asInt(attempt['wrong_count']) + asInt(attempt['blank_count']);
      item.serverScore = asInt(attempt['score_x100']) / 100;
      if (attempt['max_score_x100'] != null) item.serverMax = asInt(attempt['max_score_x100']) / 100;
      final student = asMap(attempt['student']);
      if (student['full_name'] != null) item.serverStudent = asText(student['full_name']);
    }
    if (status == 'processed') {
      item.status = ScanStatus.processed;
    } else if (status == 'needs_review') {
      item.status = ScanStatus.needsReview;
    } else if (status == 'failed') {
      item.status = ScanStatus.failed;
    } else {
      // Navbatda (server keyinroq o'qiydi)
      item.status = ScanStatus.needsReview;
    }
  }

  void retry(QueuedScan item) {
    if (item.status == ScanStatus.uploading) return;
    item.status = ScanStatus.waiting;
    notifyListeners();
    kick();
  }

  Future<void> remove(QueuedScan item) async {
    items.remove(item);
    try {
      if (imageFile(item).existsSync()) imageFile(item).deleteSync();
      if (previewFile(item).existsSync()) previewFile(item).deleteSync();
    } catch (_) {}
    await _save();
    notifyListeners();
  }

  Future<void> clearDone() async {
    for (final item in items.where((item) => item.done).toList()) {
      await remove(item);
    }
  }

  /// Faqat oxirgi 300 ta yuborilgan varaqa saqlanadi.
  void _prune() {
    final done = items.where((item) => item.done).toList();
    if (done.length <= 300) return;
    for (final item in done.sublist(300)) {
      items.remove(item);
      try {
        if (imageFile(item).existsSync()) imageFile(item).deleteSync();
        if (previewFile(item).existsSync()) previewFile(item).deleteSync();
      } catch (_) {}
    }
  }
}
