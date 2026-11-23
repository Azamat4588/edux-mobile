// 3.38 (server 2.99): «Telefon orqali» call markaz — SMS shlyuz kabi, lekin qo'ng'iroqlar uchun. Operator telefoni o'z
// SIM kartasidan qo'ng'iroq qiladi va qabul qiladi; Android fon xizmati (CallGatewayService.kt, doimiy bildirishnoma):
//  - qo'ng'iroq holatini kuzatadi (jiringlash → ko'tarildi → tugadi) va telefon jurnalidagi raqam, davomiylik, natijani
//    serverga yuboradi: POST crm/callcenter/phone/events (internet bo'lmasa saqlab turadi);
//  - vebdagi «Qo'ng'iroq» tugmasi bosilganda raqamni teradi: GET crm/callcenter/phone/next (oraliq — server aytadi:
//    operator «Qabul qilyapti» bo'lsa 4 s, aks holda 30 s; ilova ochiq bo'lsa jim push `call_dial` darhol uyg'otadi).
// Faqat Android va do'kondan tashqari nusxa: Google Play qo'ng'iroqlar jurnalini faqat standart telefon ilovasiga beradi.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'i18n.dart';
import 'push.dart';
import 'session.dart';
import 'sms_gateway.dart';
import 'store_build.dart';

class CallPhoneService extends ChangeNotifier {
  CallPhoneService._();

  static final CallPhoneService instance = CallPhoneService._();

  static const String base = 'crm/callcenter/phone';
  static const MethodChannel _channel = MethodChannel('edux/sms');

  Session? _session;
  Timer? _statusTimer;

  bool enabled = false;

  /// Ruxsatlar: call_log (jurnal), phone_state (jiringlash), call_phone (avtomatik terish).
  Map<String, bool> permissions = <String, bool>{'call_log': false, 'phone_state': false, 'call_phone': false};

  /// Fon xizmati holati.
  int logged = 0;
  int pending = 0;
  int dialed = 0;
  String? lastError;
  DateTime? lastPoll;
  String log = 'all';

  /// Xizmat server javobi bilan to'xtagan (401/403/404) — sabab ekranda ko'rinadi.
  bool stopped = false;

  bool get supported => Platform.isAndroid && !kStoreBuild;

  bool allowed(Session session) => session.canCallCenter && !session.readOnly;

  String get _prefKey => 'call_phone_${_session?.organizationId ?? 0}_${asInt(_session?.user['id'])}';

  bool get ready => permissions['call_log'] == true && permissions['phone_state'] == true;

  static Future<Object?> _invoke(String method, [Map<String, Object?>? arguments]) async {
    try {
      return await _channel.invokeMethod<Object?>(method, arguments);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, bool>> checkPermissions() async {
    if (!supported) return permissions;
    final result = await _invoke('callPermissions');
    if (result is Map) {
      permissions = <String, bool>{for (final entry in result.entries) entry.key.toString(): entry.value == true};
      notifyListeners();
    }
    return permissions;
  }

  /// Uchala ruxsatni so'raydi (Android oynasi). Natija — joriy holat.
  Future<Map<String, bool>> requestPermissions() async {
    if (!supported) return permissions;
    await _invoke('requestCallPermissions');
    return checkPermissions();
  }

  Future<void> openAppSettings() async => _invoke('openAppSettings');

  /// Ilova ochilganda: bu telefon avval yoqilgan bo'lsa — xizmat davom etadi.
  Future<void> resume(Session session) async {
    _session = session;
    if (!supported || !allowed(session)) {
      enabled = false;
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    enabled = prefs.getBool(_prefKey) ?? false;
    await checkPermissions();
    if (enabled) await _startNative();
    notifyListeners();
  }

  Future<void> enable(Session session) async {
    _session = session;
    await requestPermissions();
    if (!ready) throw ApiException(0, tr("Qo'ng'iroqlar jurnali va telefon holati ruxsatlarisiz telefon orqali ishlab bo'lmaydi."));
    final model = asText(await _invoke('deviceModel'), 'Android');
    final data = asMap(await session.api.post('$base/register', <String, Object?>{
      'device_id': await SmsGatewayService.deviceId(),
      'name': model,
      'device_model': model,
      'permissions': permissions,
    }));
    log = asText(data['log'], 'all');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, true);
    enabled = true;
    stopped = false;
    lastError = null;
    await _startNative();
    // Batareya tejash fon xizmatini uxlatmasin.
    if ((await _invoke('batteryOptimized')) == true) await _invoke('requestBatteryExemption');
    notifyListeners();
  }

  Future<void> disable() async {
    final session = _session;
    enabled = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, false);
    _statusTimer?.cancel();
    await _invoke('callsStop');
    notifyListeners();
    if (session != null) {
      try {
        await session.api.post('$base/unregister', <String, Object?>{'device_id': await SmsGatewayService.deviceId()});
      } catch (_) {}
    }
  }

  /// Chiqishda (token bekor bo'ladi).
  static Future<void> stopAll() async {
    instance._statusTimer?.cancel();
    instance.enabled = false;
    if (Platform.isAndroid) await _invoke('callsStop');
  }

  /// Vebdan «Qo'ng'iroq» bosildi (jim push) — xizmat darhol tekshiradi.
  void poke() {
    if (enabled) unawaited(_invoke('callsPoke'));
  }

  Future<bool> _startNative() async {
    final session = _session;
    if (!supported || session == null || session.token == null) return false;
    final config = <String, Object?>{
      'server': session.server,
      'token': session.token,
      'organization': session.organizationId,
      'device_id': await SmsGatewayService.deviceId(),
      'locale': I18n.locale,
      'app_version': PushService.appVersion,
      'texts': <String, String>{
        'title': tr("EduX: qo'ng'iroqlar yozilmoqda"),
        'body': tr('Yozildi: {0}'),
        'dial_title': tr("EduX: qo'ng'iroq qiling"),
        'dial_body': tr('{0} raqamini terish uchun bosing'),
      },
    };
    final ok = (await _invoke('callsStart', <String, Object?>{'config': jsonEncode(config)})) == true;
    _statusTimer?.cancel();
    if (ok) {
      _statusTimer = Timer.periodic(const Duration(seconds: 3), (_) => refreshStatus());
      unawaited(refreshStatus());
    }
    return ok;
  }

  Future<void> refreshStatus() async {
    final raw = await _invoke('callsStatus');
    if (raw is! String || raw.isEmpty) return;
    final status = asMap(jsonDecode(raw));
    logged = asInt(status['logged']);
    pending = asInt(status['pending']);
    dialed = asInt(status['dialed']);
    final error = asText(status['last_error']);
    lastError = error.isEmpty ? null : error;
    final poll = asInt(status['last_poll']);
    lastPoll = poll > 0 ? DateTime.fromMillisecondsSinceEpoch(poll) : null;
    log = asText(status['log'], log);
    if (status['stopped'] != null && enabled) {
      stopped = true;
      enabled = false;
      _statusTimer?.cancel();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, false);
    }
    notifyListeners();
  }
}
