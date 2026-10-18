// Varaqa o'quvchisi alohida isolate'da: kamera kadri tahlili interfeysni sekinlashtirmaydi.
import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:edux_omr/edux_omr.dart';

/// Kulrang kadr (kameraning Y tekisligi).
class GrayFrame {
  GrayFrame(this.bytes, this.width, this.height, this.stride);

  final Uint8List bytes;
  final int width;
  final int height;
  final int stride;
}

class OmrWorker {
  OmrWorker._(this._isolate, this._commands, this._responses, this._pending);

  final Isolate _isolate;
  final SendPort _commands;
  final ReceivePort _responses;
  final Map<int, Completer<dynamic>> _pending;
  int _next = 0;
  bool _closed = false;

  static Future<OmrWorker> spawn() async {
    final responses = ReceivePort();
    final pending = <int, Completer<dynamic>>{};
    final ready = Completer<SendPort>();
    responses.listen((dynamic message) {
      if (message is SendPort) {
        if (!ready.isCompleted) ready.complete(message);
        return;
      }
      if (message is List && message.length == 3) {
        final completer = pending.remove(message[0] as int);
        if (completer == null) return;
        if (message[1] == true) {
          completer.complete(message[2]);
        } else {
          completer.completeError(StateError('${message[2]}'));
        }
      }
    });
    final isolate = await Isolate.spawn<SendPort>(_workerMain, responses.sendPort, debugName: 'edux-omr');
    final commands = await ready.future;
    return OmrWorker._(isolate, commands, responses, pending);
  }

  Future<dynamic> _call(String op, Map<String, Object?> args) {
    if (_closed) return Future<dynamic>.error(StateError('closed'));
    final id = _next++;
    final completer = Completer<dynamic>();
    _pending[id] = completer;
    _commands.send(<Object?>[id, op, args]);
    return completer.future;
  }

  Map<String, Object?> _frameArgs(GrayFrame frame) => <String, Object?>{
        'data': TransferableTypedData.fromList(<TypedData>[frame.bytes]),
        'w': frame.width,
        'h': frame.height,
        'stride': frame.stride,
      };

  /// Jonli tahlil (tez): belgilar, varaqa to'rtburchagi, aniqlik.
  Future<OmrDetection> detect(GrayFrame frame, {int workMaxSide = 800}) async {
    final result = await _call('detect', <String, Object?>{..._frameArgs(frame), 'work': workMaxSide});
    return OmrDetection(Map<String, dynamic>.from(result as Map));
  }

  /// To'liq o'qish (~0.3–1 s).
  Future<OmrReading> read(GrayFrame frame, {int questions = 0, int options = 0}) async {
    final result = await _call('read', <String, Object?>{..._frameArgs(frame), 'questions': questions, 'options': options});
    return _reading(result as Map);
  }

  /// Galereyadagi rasm (JPEG/PNG).
  Future<OmrReading> readEncoded(Uint8List bytes, {int questions = 0, int options = 0}) async {
    final result = await _call('readEncoded', <String, Object?>{
      'data': TransferableTypedData.fromList(<TypedData>[bytes]),
      'questions': questions,
      'options': options,
    });
    return _reading(result as Map);
  }

  /// Serverga yuboriladigan JPEG.
  Future<Uint8List?> encode(GrayFrame frame, {int maxSide = 2000, int quality = 88}) async {
    final result = await _call('encode', <String, Object?>{..._frameArgs(frame), 'max': maxSide, 'quality': quality});
    return result is TransferableTypedData ? result.materialize().asUint8List() : null;
  }

  OmrReading _reading(Map result) {
    final preview = result['preview'];
    final upload = result['upload'];
    return OmrReading(
      Map<String, dynamic>.from(result['raw'] as Map),
      preview: preview is TransferableTypedData ? preview.materialize().asUint8List() : null,
      upload: upload is TransferableTypedData ? upload.materialize().asUint8List() : null,
    );
  }

  void dispose() {
    if (_closed) return;
    _closed = true;
    for (final completer in _pending.values) {
      completer.completeError(StateError('closed'));
    }
    _pending.clear();
    _responses.close();
    _isolate.kill(priority: Isolate.immediate);
  }
}

TransferableTypedData? _transfer(Uint8List? bytes) =>
    bytes == null ? null : TransferableTypedData.fromList(<TypedData>[bytes]);

void _workerMain(SendPort replies) {
  final commands = ReceivePort();
  replies.send(commands.sendPort);
  OmrEngine? engine;
  commands.listen((dynamic message) {
    final list = message as List;
    final id = list[0] as int;
    final op = list[1] as String;
    final args = list[2] as Map;
    try {
      final omr = engine ??= OmrEngine();
      final data = (args['data'] as TransferableTypedData).materialize().asUint8List();
      Object? result;
      if (op == 'detect') {
        result = omr
            .detect(data, args['w'] as int, args['h'] as int, args['stride'] as int, workMaxSide: args['work'] as int)
            .raw;
      } else if (op == 'read') {
        final reading = omr.read(data, args['w'] as int, args['h'] as int, args['stride'] as int,
            questions: args['questions'] as int, options: args['options'] as int);
        result = <String, Object?>{'raw': reading.raw, 'preview': _transfer(reading.preview)};
      } else if (op == 'readEncoded') {
        final reading = omr.readEncoded(data, questions: args['questions'] as int, options: args['options'] as int);
        result = <String, Object?>{
          'raw': reading.raw,
          'preview': _transfer(reading.preview),
          'upload': _transfer(reading.upload),
        };
      } else if (op == 'encode') {
        result = _transfer(omr.encodeJpeg(data, args['w'] as int, args['h'] as int, args['stride'] as int,
            maxSide: args['max'] as int, quality: args['quality'] as int));
      } else {
        throw ArgumentError('unknown op $op');
      }
      replies.send(<Object?>[id, true, result]);
    } catch (error) {
      replies.send(<Object?>[id, false, '$error']);
    }
  });
}
