// Push-bildirishnomalar (2.0): Firebase Cloud Messaging. Ilova Firebase sozlamasisiz yig'ilgan bo'lsa
// (google-services.json yo'q) — jim o'chiq turadi, qolgan hamma narsa odatdagidek ishlaydi.
//
// Oqim: kirgandan keyin token olinadi → POST /devices; token yangilansa — qayta; chiqishda DELETE /devices.
// Xabar bosilganda: kerak bo'lsa tashkilot almashtiriladi va tegishli sahifa ochiladi (PushRouter).
import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'i18n.dart';
import 'session.dart';
import 'theme.dart';

/// Butun ilova bo'ylab navigator (xabar bosilganda sahifa ochish uchun).
final GlobalKey<NavigatorState> rootNavigator = GlobalKey<NavigatorState>();

/// Xabar turi (server: data.type) → ochiladigan sahifa. Sahifalar shell tomonidan ro'yxatdan o'tkaziladi.
typedef PushRoute = Widget? Function(Map<String, dynamic> data);

class PushService {
  PushService._();

  static final PushService instance = PushService._();

  static const String appVersion = '2.0.0';

  bool _ready = false;
  bool _initTried = false;
  String? _token;
  Session? _session;
  StreamSubscription<String>? _refresh;
  final Map<String, PushRoute> routes = <String, PushRoute>{};
  Map<String, dynamic>? _pending;

  bool get available => _ready;

  Future<void> _init() async {
    if (_initTried) return;
    _initTried = true;
    try {
      await Firebase.initializeApp();
      _ready = true;
    } catch (_) {
      // google-services.json yo'q yoki Firebase sozlanmagan — push o'chiq.
      _ready = false;
      return;
    }
    FirebaseMessaging.onMessage.listen(_foreground);
    FirebaseMessaging.onMessageOpenedApp.listen((message) => _open(message.data));
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) _pending = Map<String, dynamic>.from(initial.data);
  }

  /// Kirgandan keyin (tashkilot konteksti yuklangach) chaqiriladi.
  Future<void> attach(Session session) async {
    _session = session;
    await _init();
    if (!_ready) return;
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      final token = await messaging.getToken();
      if (token != null) await _register(token);
      await _refresh?.cancel();
      _refresh = messaging.onTokenRefresh.listen(_register);
    } catch (_) {
      // ruxsat berilmagan yoki tarmoq yo'q — keyingi ochilishda qayta urinadi
    }
    final pending = _pending;
    if (pending != null) {
      _pending = null;
      Future<void>.delayed(const Duration(milliseconds: 600), () => _open(pending));
    }
  }

  Future<void> _register(String token) async {
    final session = _session;
    if (session == null || !session.signedIn) return;
    _token = token;
    try {
      await session.api.post('devices', <String, Object?>{
        'token': token,
        'platform': Platform.isIOS ? 'ios' : 'android',
        'app_version': appVersion,
        'locale': I18n.locale,
      });
    } catch (_) {}
  }

  /// Chiqishdan oldin: bu telefonga endi xabar kelmasin.
  Future<void> detach(Session session) async {
    final token = _token;
    _token = null;
    await _refresh?.cancel();
    _refresh = null;
    if (token == null || !_ready) return;
    try {
      await session.api.deleteJson('devices', <String, Object?>{'token': token});
    } catch (_) {}
  }

  /// Til almashganda server xabarlarni yangi tilda yuborsin.
  Future<void> updateLocale() async {
    final token = _token;
    if (token != null) await _register(token);
  }

  void _foreground(RemoteMessage message) {
    final context = rootNavigator.currentContext;
    final notification = message.notification;
    if (context == null || notification == null) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.brand,
      duration: const Duration(seconds: 6),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Text(notification.title ?? '', style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
        if ((notification.body ?? '').isNotEmpty) Text(notification.body!, style: const TextStyle(color: Colors.white)),
      ]),
      action: routes.containsKey(asText(message.data['type']))
          ? SnackBarAction(label: tr('Ochish'), textColor: Colors.white, onPressed: () => _open(message.data))
          : null,
    ));
  }

  Future<void> _open(Map<String, dynamic> data) async {
    final session = _session;
    if (session == null || !session.signedIn) {
      _pending = data;
      return;
    }
    final organization = asInt(data['organization_id']);
    if (organization > 0 && organization != session.organizationId && session.memberships.any((item) => item.organizationId == organization)) {
      await session.selectOrganization(organization);
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    final builder = routes[asText(data['type'])];
    final page = builder?.call(data);
    final navigator = rootNavigator.currentState;
    if (page != null && navigator != null) {
      await navigator.push(MaterialPageRoute<void>(builder: (_) => page));
    }
  }
}
