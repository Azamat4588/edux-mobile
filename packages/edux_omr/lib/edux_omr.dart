/// EduX javob varaqasini telefonning o'zida o'qish.
///
/// C++ yadro (`src/edux_omr.cpp`) serverdagi OMR servis bilan bir xil qoidalarda ishlaydi:
/// 4 ta burchak belgisi -> varaqani to'g'rilash -> QR -> doirachalar.
///
/// Barcha chaqiruvlar sinxron va og'ir (kadr ~50–500 ms): ularni asosiy oqimda emas, alohida
/// isolate'da chaqiring (ilovadagi `OmrWorker` shunday qiladi).
library edux_omr;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:ffi/ffi.dart';

const String _libName = 'edux_omr';

final DynamicLibrary _lib = () {
  if (Platform.isIOS || Platform.isMacOS) {
    return DynamicLibrary.open('$_libName.framework/$_libName');
  }
  if (Platform.isAndroid || Platform.isLinux) {
    return DynamicLibrary.open('lib$_libName.so');
  }
  throw UnsupportedError('edux_omr: ${Platform.operatingSystem} qo\'llanmaydi');
}();

typedef _DetectNative = Pointer<Utf8> Function(Pointer<Uint8>, Int32, Int32, Int32, Int32);
typedef _DetectDart = Pointer<Utf8> Function(Pointer<Uint8>, int, int, int, int);

typedef _ReadGrayNative = Pointer<Utf8> Function(Pointer<Uint8>, Int32, Int32, Int32, Int32, Int32,
    Pointer<Pointer<Uint8>>, Pointer<Int32>, Pointer<Pointer<Uint8>>, Pointer<Int32>);
typedef _ReadGrayDart = Pointer<Utf8> Function(Pointer<Uint8>, int, int, int, int, int,
    Pointer<Pointer<Uint8>>, Pointer<Int32>, Pointer<Pointer<Uint8>>, Pointer<Int32>);

typedef _ReadEncodedNative = Pointer<Utf8> Function(Pointer<Uint8>, Int32, Int32, Int32,
    Pointer<Pointer<Uint8>>, Pointer<Int32>, Pointer<Pointer<Uint8>>, Pointer<Int32>);
typedef _ReadEncodedDart = Pointer<Utf8> Function(Pointer<Uint8>, int, int, int,
    Pointer<Pointer<Uint8>>, Pointer<Int32>, Pointer<Pointer<Uint8>>, Pointer<Int32>);

typedef _EncodeNative = Int32 Function(Pointer<Uint8>, Int32, Int32, Int32, Int32, Int32,
    Pointer<Pointer<Uint8>>, Pointer<Int32>);
typedef _EncodeDart = int Function(Pointer<Uint8>, int, int, int, int, int,
    Pointer<Pointer<Uint8>>, Pointer<Int32>);

typedef _FreeNative = Void Function(Pointer<Void>);
typedef _FreeDart = void Function(Pointer<Void>);

typedef _VersionNative = Int32 Function();
typedef _VersionDart = int Function();

/// Jonli kadr tahlili: belgilar, varaqa to'rtburchagi va sifat ko'rsatkichlari.
class OmrDetection {
  OmrDetection(this.raw);

  final Map<String, dynamic> raw;

  /// Topilgan burchak belgilari soni (0..4).
  int get found => (raw['found'] as num?)?.toInt() ?? 0;

  /// Varaqaning 4 burchagi kirish kadrida: yuqori-chap, yuqori-o'ng, pastki-o'ng, pastki-chap.
  List<List<double>>? get quad {
    final value = raw['quad'];
    if (value is! List || value.length != 4) return null;
    return value
        .map((point) => (point as List).map((v) => (v as num).toDouble()).toList())
        .toList();
  }

  /// Varaqa markazida 1 mm necha piksel (kirish kadrida). 4 dan kam — juda uzoq.
  double get pxPerMm => (raw['px_per_mm'] as num?)?.toDouble() ?? 0;

  /// Belgilar chekkasining aniqligi 0..1 (taxminan 0.33 dan yuqori — tiniq).
  double get sharpness => (raw['sharpness'] as num?)?.toDouble() ?? 0;

  /// Varaqaning oq qismi yorug'ligi 0..255.
  double get brightness => (raw['brightness'] as num?)?.toDouble() ?? 0;

  double get ms => (raw['ms'] as num?)?.toDouble() ?? 0;
}

/// To'liq o'qish natijasi.
class OmrReading {
  OmrReading(this.raw, {this.preview, this.upload});

  /// Server javobi bilan bir xil shakl: ok, exam_id, variant, questions, options, student_code, answers, flags...
  final Map<String, dynamic> raw;

  /// To'g'rilangan varaqa (JPEG, `preview_px_per_mm` px/mm).
  final Uint8List? preview;

  /// Serverga yuboriladigan kadr (JPEG) — faqat so'ralganda.
  final Uint8List? upload;

  bool get ok => raw['ok'] == true;
  String? get error => raw['error'] as String?;
  int? get examId => (raw['exam_id'] as num?)?.toInt();
  int? get variant => (raw['variant'] as num?)?.toInt();
  int get questions => (raw['questions'] as num?)?.toInt() ?? 0;
  int get options => (raw['options'] as num?)?.toInt() ?? 4;
  String? get studentCode => raw['student_code'] as String?;
  bool get needsReview => raw['needs_review'] == true;
  double get previewPxPerMm => (raw['preview_px_per_mm'] as num?)?.toDouble() ?? 3;

  List<List<int>> get answers => ((raw['answers'] as List?) ?? const [])
      .map((row) => (row as List).map((v) => (v as num).toInt()).toList())
      .toList();

  List<List<double>> get darkness => ((raw['darkness'] as List?) ?? const [])
      .map((row) => (row as List).map((v) => (v as num).toDouble()).toList())
      .toList();

  List<Map<String, dynamic>> get flags => ((raw['flags'] as List?) ?? const [])
      .map((flag) => Map<String, dynamic>.from(flag as Map))
      .toList();
}

/// Varaqa o'lchamlari (mm) — ekranda natijani chizish uchun (layout.py bilan bir xil).
class OmrLayout {
  static const double sheetWidth = 210;
  static const double sheetHeight = 297;
  static const double bubbleRadius = 2.1;
  static const int rowsPerColumn = 30;
  static const double answerX0 = 36, answerY0 = 112, answerColumnStep = 56, answerPitchX = 7.5, answerPitchY = 5.5;
  static const double idX0 = 24, idY0 = 52, idPitchX = 6, idPitchY = 5.2;

  /// Savol (0 dan) va variant (0 dan) doirachasining markazi, mm.
  static Offset answerCenter(int question, int option) {
    final column = question ~/ rowsPerColumn;
    final row = question % rowsPerColumn;
    return Offset(answerX0 + column * answerColumnStep + option * answerPitchX, answerY0 + row * answerPitchY);
  }

  static Offset idCenter(int column, int digit) => Offset(idX0 + column * idPitchX, idY0 + digit * idPitchY);
}

/// C++ yadroga kirish. Bitta isolate ichida bitta nusxa yetarli.
class OmrEngine {
  OmrEngine()
      : _detect = _lib.lookupFunction<_DetectNative, _DetectDart>('omr_detect'),
        _readGray = _lib.lookupFunction<_ReadGrayNative, _ReadGrayDart>('omr_read_gray'),
        _readEncoded = _lib.lookupFunction<_ReadEncodedNative, _ReadEncodedDart>('omr_read_encoded'),
        _encode = _lib.lookupFunction<_EncodeNative, _EncodeDart>('omr_encode_jpeg'),
        _free = _lib.lookupFunction<_FreeNative, _FreeDart>('omr_free'),
        _version = _lib.lookupFunction<_VersionNative, _VersionDart>('omr_layout_version');

  final _DetectDart _detect;
  final _ReadGrayDart _readGray;
  final _ReadEncodedDart _readEncoded;
  final _EncodeDart _encode;
  final _FreeDart _free;
  final _VersionDart _version;

  int get layoutVersion => _version();

  /// Kulrang kadrda varaqani qidiradi (kameraning Y tekisligi).
  OmrDetection detect(Uint8List gray, int width, int height, int stride, {int workMaxSide = 800}) {
    final input = _copyIn(gray);
    try {
      return OmrDetection(_takeJson(_detect(input, width, height, stride, workMaxSide)));
    } finally {
      malloc.free(input);
    }
  }

  /// Kadrni to'liq o'qiydi. [questions]/[options] — QR o'qilmasa ishlatiladigan shakl (0 — noma'lum).
  OmrReading read(Uint8List gray, int width, int height, int stride,
      {int questions = 0, int options = 0, bool withPreview = true, bool withUpload = false}) {
    final input = _copyIn(gray);
    final previewPtr = calloc<Pointer<Uint8>>();
    final previewLen = calloc<Int32>();
    final uploadPtr = calloc<Pointer<Uint8>>();
    final uploadLen = calloc<Int32>();
    try {
      final json = _readGray(input, width, height, stride, questions, options,
          withPreview ? previewPtr : nullptr, withPreview ? previewLen : nullptr,
          withUpload ? uploadPtr : nullptr, withUpload ? uploadLen : nullptr);
      return OmrReading(
        _takeJson(json),
        preview: withPreview ? _takeBytes(previewPtr.value, previewLen.value) : null,
        upload: withUpload ? _takeBytes(uploadPtr.value, uploadLen.value) : null,
      );
    } finally {
      malloc.free(input);
      calloc.free(previewPtr);
      calloc.free(previewLen);
      calloc.free(uploadPtr);
      calloc.free(uploadLen);
    }
  }

  /// JPEG yoki PNG fayldan (galereya) o'qiydi. Serverga yuborish uchun kichraytirilgan JPEG ham qaytadi.
  OmrReading readEncoded(Uint8List bytes, {int questions = 0, int options = 0}) {
    final input = _copyIn(bytes);
    final previewPtr = calloc<Pointer<Uint8>>();
    final previewLen = calloc<Int32>();
    final uploadPtr = calloc<Pointer<Uint8>>();
    final uploadLen = calloc<Int32>();
    try {
      final json = _readEncoded(input, bytes.length, questions, options, previewPtr, previewLen, uploadPtr, uploadLen);
      return OmrReading(
        _takeJson(json),
        preview: _takeBytes(previewPtr.value, previewLen.value),
        upload: _takeBytes(uploadPtr.value, uploadLen.value),
      );
    } finally {
      malloc.free(input);
      calloc.free(previewPtr);
      calloc.free(previewLen);
      calloc.free(uploadPtr);
      calloc.free(uploadLen);
    }
  }

  /// Kulrang kadrni JPEG ga o'giradi (uzun tomoni [maxSide] gacha kichraytiriladi).
  Uint8List? encodeJpeg(Uint8List gray, int width, int height, int stride, {int maxSide = 2000, int quality = 88}) {
    final input = _copyIn(gray);
    final out = calloc<Pointer<Uint8>>();
    final outLen = calloc<Int32>();
    try {
      _encode(input, width, height, stride, maxSide, quality, out, outLen);
      return _takeBytes(out.value, outLen.value);
    } finally {
      malloc.free(input);
      calloc.free(out);
      calloc.free(outLen);
    }
  }

  Pointer<Uint8> _copyIn(Uint8List data) {
    final pointer = malloc<Uint8>(data.isEmpty ? 1 : data.length);
    pointer.asTypedList(data.length).setAll(0, data);
    return pointer;
  }

  Map<String, dynamic> _takeJson(Pointer<Utf8> pointer) {
    if (pointer.address == 0) return <String, dynamic>{'ok': false, 'error': 'no_memory'};
    try {
      return Map<String, dynamic>.from(jsonDecode(pointer.toDartString()) as Map);
    } finally {
      _free(pointer.cast<Void>());
    }
  }

  Uint8List? _takeBytes(Pointer<Uint8> pointer, int length) {
    if (pointer.address == 0) return null;
    try {
      return length > 0 ? Uint8List.fromList(pointer.asTypedList(length)) : null;
    } finally {
      _free(pointer.cast<Void>());
    }
  }
}
