// Shaxsiy telefon orqali SMS (1.18): markaz telefoni EduX serveridagi navbatdan SMS'larni olib,
// o'z SIM kartasidan yuboradi va natijani qaytaradi. Faqat Android (iOS ilovaga SMS yuborishga ruxsat bermaydi).
//
// Oqim: POST crm/sms/gateway/register → har 20 soniyada (yoki serverdan jim push kelganda) GET crm/sms/gateway/next
// → har bir SMS native SmsManager orqali → POST crm/sms/gateway/report.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'session.dart';

class SmsGatewayService extends ChangeNotifier {
  SmsGatewayService._();

  static final SmsGatewayService instance = SmsGatewayService._();

  static const MethodChannel _channel = MethodChannel('edux/sms');
  static const Duration interval = Duration(seconds: 20);

  Session? _session;
  Timer? _timer;
  bool _busy = false;
  bool _again = false;

  bool enabled = false;
  int sentSession = 0;
  int failedSession = 0;
  int leftToday = 0;
  String? lastError;
  DateTime? lastPoll;

  bool get supported => Platform.isAndroid;

  String get _prefKey => 'sms_gateway_${_session?.organizationId ?? 0}';

  /// Ilova ochilganda: bu telefon avval shlyuz qilib yoqilgan bo'lsa — ishni davom ettiradi.
  Future<void> resume(Session session) async {
    _session = session;
    if (!supported || !session.isManager || !session.hasModule('crm')) {
      _stop();
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_prefKey) ?? false) {
      enabled = true;
      _start();
    } else {
      _stop();
    }
  }

  Future<bool> hasPermission() async => supported && (await _channel.invokeMethod<bool>('hasPermission') ?? false);

  Future<bool> requestPermission() async => supported && (await _channel.invokeMethod<bool>('requestPermission') ?? false);

  Future<String> deviceModel() async {
    try {
      return await _channel.invokeMethod<String>('deviceModel') ?? 'Android';
    } catch (_) {
      return 'Android';
    }
  }

  Future<void> enable(Session session) async {
    _session = session;
    final model = await deviceModel();
    await session.api.post('crm/sms/gateway/register', <String, Object?>{'name': session.userName, 'device_model': model});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, true);
    enabled = true;
    lastError = null;
    _start();
  }

  Future<void> disable() async {
    final session = _session;
    _stop();
    enabled = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, false);
    notifyListeners();
    if (session != null) {
      try {
        await session.api.post('crm/sms/gateway/unregister');
      } catch (_) {}
    }
  }

  /// Serverdan "navbatda SMS bor" jim xabari kelganda.
  void poke() {
    if (enabled) unawaited(poll());
  }

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => poll());
    unawaited(poll());
    notifyListeners();
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> poll() async {
    final session = _session;
    if (session == null || !session.signedIn || !enabled) return;
    if (_busy) {
      _again = true;
      return;
    }
    _busy = true;
    try {
      do {
        _again = false;
        final data = asMap(await session.api.get('crm/sms/gateway/next', query: <String, Object?>{'limit': 10}));
        lastPoll = DateTime.now();
        leftToday = asInt(data['left_today']);
        final messages = asList(data['messages'], 'messages');
        if (messages.isEmpty) break;
        final results = <Map<String, Object?>>[];
        for (final message in messages) {
          String? error;
          try {
            final ok = await _channel.invokeMethod<bool>('send', <String, Object?>{
              'phone': asText(message['phone']),
              'body': asText(message['body']),
            });
            if (ok != true) error = 'not sent';
          } on PlatformException catch (e) {
            error = e.message ?? e.code;
          }
          results.add(<String, Object?>{'id': asInt(message['id']), 'ok': error == null, if (error != null) 'error': error});
          if (error == null) {
            sentSession++;
          } else {
            failedSession++;
            lastError = error;
          }
          notifyListeners();
          // Operator spam deb bloklamasligi uchun SMS'lar orasida qisqa tanaffus.
          await Future<void>.delayed(const Duration(milliseconds: 1500));
        }
        await session.api.post('crm/sms/gateway/report', <String, Object?>{'results': results});
        if (messages.length >= 10) _again = true;
      } while (_again && enabled);
    } on ApiException catch (e) {
      lastError = e.message;
      if (e.status == 404) {
        // Shlyuz o'chirilgan (veb panelda) — telefon to'xtaydi.
        enabled = false;
        _stop();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_prefKey, false);
      }
    } catch (e) {
      lastError = e.toString();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
