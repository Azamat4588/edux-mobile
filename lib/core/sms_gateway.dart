// Shaxsiy telefon orqali SMS (1.18): markaz telefoni EduX serveridagi navbatdan SMS'larni olib,
// o'z SIM kartasidan yuboradi va natijani qaytaradi. Faqat Android (iOS ilovaga SMS yuborishga ruxsat bermaydi).
//
// Oqim: POST <prefix>/register → har 20 soniyada (yoki serverdan jim push kelganda) GET <prefix>/next
// → har bir SMS native SmsManager orqali → POST <prefix>/report.
// 3.4: ikki navbat — tashkilot (`crm/sms/gateway/*`, direktor/administrator) va platforma (`platform/sms/gateway/*`,
// platforma egasi: kirish va parol tiklash kodlari). Push `type=sms_gateway, scope=platform` — platforma navbati.
// 3.10 (server 1.44): bir hisob bilan bir nechta telefon — har telefon o'z `device_id` si bilan ro'yxatdan o'tadi; server
// telefonning 30 daqiqalik va kunlik chegarasini hisoblab beradi, SMS orasidagi tanaffusni (`pause_ms`) aytadi,
// yubora olmagan xabarni boshqa telefonga o'tkazadi va ketma-ket xatoda telefonni pauzaga qo'yadi (`paused_until`).
import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'push.dart';
import 'session.dart';

/// Navbat yo'llari: tashkilot — crm/sms/gateway, platforma — platform/sms/gateway.
String gatewayPrefix(String scope) => scope == 'platform' ? 'platform/sms/gateway' : 'crm/sms/gateway';

class SmsGatewayService extends ChangeNotifier {
  SmsGatewayService._(this.scope);

  /// Tashkilot navbati (markaz SMS'lari).
  static final SmsGatewayService organization = SmsGatewayService._('organization');

  /// Platforma navbati (kirish/tiklash kodlari) — platforma egasi hisobi bilan.
  static final SmsGatewayService platform = SmsGatewayService._('platform');

  /// Eski nom (3.3 gacha) — tashkilot navbati.
  static SmsGatewayService get instance => organization;

  final String scope;

  bool get isPlatform => scope == 'platform';

  /// API yo'llari prefiksi.
  String get prefix => gatewayPrefix(scope);

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

  /// Server aytgan chegaralar (eski server yubormasa — 0 / null).
  int dailyLimit = 0;
  int leftWindow = 0;
  int windowLimit = 0;
  int windowMinutes = 30;

  /// Chegara to'lgan bo'lsa — qachon davom etadi; telefon pauzada bo'lsa — qachongacha.
  DateTime? nextAt;
  DateTime? pausedUntil;

  /// SMS orasidagi tanaffus (server sozlamasi; eski serverda 1,5 s).
  Duration pause = const Duration(milliseconds: 1500);

  static const String _deviceKey = 'sms_gateway_device_id';
  static String? _deviceId;

  /// Shu o'rnatishning doimiy ID si: bir hisob bilan bir nechta telefon ulanganda server ularni ajratadi.
  static Future<String> deviceId() async {
    final cached = _deviceId;
    if (cached != null) return cached;
    final prefs = await SharedPreferences.getInstance();
    var value = prefs.getString(_deviceKey);
    if (value == null || value.isEmpty) {
      final random = Random.secure();
      value = 'a-${List<String>.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
      await prefs.setString(_deviceKey, value);
    }
    return _deviceId = value;
  }

  void _limits(Map<String, dynamic> data) {
    if (data.containsKey('daily_limit')) dailyLimit = asInt(data['daily_limit']);
    if (data.containsKey('left_window')) leftWindow = asInt(data['left_window']);
    if (data.containsKey('window_limit')) windowLimit = asInt(data['window_limit']);
    if (data.containsKey('window_minutes')) windowMinutes = asInt(data['window_minutes']);
    if (data.containsKey('pause_ms')) {
      final ms = asInt(data['pause_ms']);
      if (ms > 0) pause = Duration(milliseconds: ms.clamp(500, 120000).toInt());
    }
    if (data.containsKey('next_at')) nextAt = DateTime.tryParse(asText(data['next_at']))?.toLocal();
    if (data.containsKey('paused_until')) pausedUntil = DateTime.tryParse(asText(data['paused_until']))?.toLocal();
    final serverError = asText(data['last_error']);
    if (serverError.isNotEmpty && pausedUntil != null) lastError = serverError;
  }

  bool get supported => Platform.isAndroid;

  String get _prefKey => isPlatform ? 'sms_gateway_platform_${asInt(_session?.user['id'])}' : 'sms_gateway_${_session?.organizationId ?? 0}';

  /// Shu navbatni ishlatishga ruxsat (platforma — egasi; tashkilot — SMS qo'shimchasi va yozish holati).
  bool allowed(Session session) => isPlatform ? session.isPlatformAdmin : session.canUseSmsGateway && !session.readOnly;

  /// Ilova ochilganda: bu telefon avval shlyuz qilib yoqilgan bo'lsa — ishni davom ettiradi.
  Future<void> resume(Session session) async {
    _session = session;
    // SMS qo'shimchasi o'chirilgan yoki obuna «faqat o'qish»da — navbatdan SMS olinmaydi (hisobot 402 bo'lardi).
    if (!supported || !allowed(session)) {
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
    final registered = asMap(await session.api.post('$prefix/register', <String, Object?>{
      'name': session.userName,
      'device_model': model,
      'device_id': await deviceId(),
    }));
    _limits(registered);
    // Platforma telefoni: tashkilotsiz hisobda ham jim push kelsin (qurilma ro'yxatdan o'tadi).
    if (isPlatform) unawaited(PushService.instance.attach(session));
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
        await session.api.post('$prefix/unregister', <String, Object?>{'device_id': await deviceId()});
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
        final device = await deviceId();
        final data = asMap(await session.api.get('$prefix/next', query: <String, Object?>{'limit': 10, 'device_id': device}));
        lastPoll = DateTime.now();
        leftToday = asInt(data['left_today']);
        _limits(data);
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
          // Operator spam deb bloklamasligi uchun SMS'lar orasida tanaffus (server sozlamasi).
          await Future<void>.delayed(pause);
        }
        final report = asMap(await session.api.post('$prefix/report', <String, Object?>{'device_id': device, 'results': results}));
        if (report.containsKey('paused_until')) {
          pausedUntil = DateTime.tryParse(asText(report['paused_until']))?.toLocal();
        }
        // Server yana beradi (to'liq to'plam keldi va chegara bor) — darhol so'raymiz.
        if (messages.length >= 10 && pausedUntil == null && (windowLimit == 0 || leftWindow > 0)) _again = true;
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
