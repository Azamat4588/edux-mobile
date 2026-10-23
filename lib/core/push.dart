// Push-bildirishnomalar (2.0): Firebase Cloud Messaging. Ilova Firebase sozlamasisiz yig'ilgan bo'lsa
// (google-services.json yo'q) — jim o'chiq turadi, qolgan hamma narsa odatdagidek ishlaydi.
//
// Oqim: kirgandan keyin token olinadi → POST /devices; token yangilansa — qayta; chiqishda DELETE /devices.
// Xabar bosilganda: kerak bo'lsa tashkilot almashtiriladi va tegishli sahifa ochiladi (PushRouter).
// 3.1: har bir xabar bildirishnomalar markaziga yoziladi (NotificationStore) — ilova yopiq bo'lganda ham (fon handler).
// 3.2: sahifa data.route (veb route nomi: my.attempt, child.tests, crm.leads ...) bo'yicha, eski serverda data.type
// (payment, attendance, arrival, attempt, ...) yoki havola (data.link) bo'yicha tanlanadi; noma'lum bo'lsa — bosh sahifa.
// Ota-onaga child.* — «Farzandim»da shu farzand (student_id) va yorliq.
import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'i18n.dart';
import 'notification_store.dart';
import 'session.dart';
import 'theme.dart';

/// Butun ilova bo'ylab navigator (xabar bosilganda sahifa ochish uchun).
final GlobalKey<NavigatorState> rootNavigator = GlobalKey<NavigatorState>();

/// Xabar turi (server: data.type) → ochiladigan sahifa. Sahifalar shell tomonidan ro'yxatdan o'tkaziladi.
typedef PushRoute = Widget? Function(Map<String, dynamic> data);

/// RemoteMessage → bildirishnomalar markazi yozuvi (bildirishnoma matni bo'lmagan jim xabarlar — null).
AppNotification? notificationOf(RemoteMessage message, {bool read = false}) {
  final notification = message.notification;
  if (notification == null) return null;
  final title = notification.title ?? '';
  final body = notification.body ?? '';
  if (title.isEmpty && body.isEmpty) return null;
  final sent = message.sentTime ?? DateTime.now();
  return AppNotification(
    id: message.messageId ?? '${sent.millisecondsSinceEpoch}-${title.hashCode}',
    title: title,
    body: body,
    data: Map<String, dynamic>.from(message.data),
    receivedAt: sent,
    read: read,
  );
}

/// Ilova fonda yoki yopiq bo'lganda kelgan xabar (alohida isolate): faqat markazga yoziladi.
@pragma('vm:entry-point')
Future<void> pushBackgroundHandler(RemoteMessage message) async {
  final item = notificationOf(message);
  if (item == null) return;
  try {
    await NotificationStore.persist(item);
  } catch (_) {}
}

class PushService {
  PushService._();

  static final PushService instance = PushService._();

  static const String appVersion = '3.4.0';

  bool _ready = false;
  bool _initTried = false;
  String? _token;
  Session? _session;
  StreamSubscription<String>? _refresh;
  final Map<String, PushRoute> routes = <String, PushRoute>{};

  /// Jim (ma'lumot) xabarlari: data.type → ishlov beruvchi (masalan, SMS shlyuzni uyg'otish).
  final Map<String, void Function(Map<String, dynamic>)> dataHandlers = <String, void Function(Map<String, dynamic>)>{};
  Map<String, dynamic>? _pending;

  /// Sahifasi bo'lmagan xabar (to'lov, davomat, keldi) bosilganda — bosh tabga qaytish (shell o'rnatadi;
  /// ota-onada xabardagi farzand va tegishli yorliq tanlanadi).
  void Function(Map<String, dynamic> data)? onHome;

  bool get available => _ready;

  /// Bu turdagi xabar uchun alohida sahifa bormi.
  bool hasRoute(String type) => routes.containsKey(type);

  /// Server 1.29.x: `route` — veb route nomi (App\Support\AppLinks::ROUTES), `link` — veb manzili. Ilova ichidagi tur.
  static const Map<String, String> routeTypes = <String, String>{
    'my.payments': 'payment',
    'child.payments': 'payment',
    'child.diary': 'diary',
    'child': 'child',
    'my.attempt': 'attempt',
    'child.tests': 'attempt',
    'lms.my.assignments': 'assignment',
    'my.certificates': 'certificate',
    'public.certificate': 'certificate',
    'crm.leads': 'lead',
    'crm.tasks': 'task',
  };

  /// Xabar ma'lumoti → ilova ichidagi tur: avval `route` (yangi server), keyin `type` (eski server), oxiri veb manzili
  /// (`link` / `url`) — masalan /my/attempts/15 → attempt (attempt_id 15), /child/payments?student=7 → payment.
  static Map<String, dynamic> normalize(Map<String, dynamic> data) {
    final route = asText(data['route']);
    final mapped = routeTypes[route];
    if (mapped != null) {
      final result = <String, dynamic>{...data, 'type': mapped};
      // Havoladan id lar (attempt_id, lead_id, student_id) — server alohida bermagan bo'lsa.
      final fromLink = _fromLink(asText(data['link'], asText(data['url'])));
      fromLink.forEach((key, value) {
        if (key != 'type' && result[key] == null) result[key] = value;
      });
      return result;
    }
    final type = asText(data['type']);
    const known = <String>['payment', 'attendance', 'arrival', 'attempt', 'assignment', 'certificate', 'lead', 'task', 'diary', 'child', 'sms_gateway'];
    if (known.contains(type)) return data;
    // 1.35: dars savoli/javobi va kurs e'loni — id lar havolada (/learn/courses/{kurs}/lessons/{dars}).
    if (type == 'lesson_question' || type == 'lesson_answer' || type == 'course_announcement') {
      return <String, dynamic>{...data, ...lmsIds(asText(data['link'], asText(data['url'])))};
    }
    final link = route.contains('/') ? route : asText(data['link'], asText(data['url']));
    if (link.isEmpty) return data;
    return <String, dynamic>{...data, ..._fromLink(link)};
  }

  /// LMS havolasidan kurs va dars: /learn/courses/5/lessons/9 → {course_id: 5, lesson_id: 9}.
  static Map<String, dynamic> lmsIds(String link) {
    final match = RegExp(r'/(?:learn|lms)/courses/(\d+)(?:/lessons/(\d+))?').firstMatch(link);
    if (match == null) return <String, dynamic>{};
    return <String, dynamic>{
      'course_id': int.parse(match.group(1)!),
      if (match.group(2) != null) 'lesson_id': int.parse(match.group(2)!),
    };
  }

  /// Veb manzili → {type, attempt_id, lead_id, student_id} (topilganlari).
  static Map<String, dynamic> _fromLink(String link) {
    final result = <String, dynamic>{};
    if (link.isEmpty) return result;
    final uri = Uri.tryParse(link);
    if (uri == null) return result;
    final segments = uri.pathSegments.where((item) => item.isNotEmpty).toList();
    final path = '/${segments.join('/')}';
    String? id(int index) => segments.length > index && int.tryParse(segments[index]) != null ? segments[index] : null;
    if (path.startsWith('/my/attempts/') && id(2) != null) {
      result['type'] = 'attempt';
      result['attempt_id'] = id(2);
    } else if (path == '/child/tests' || path == '/my' || path == '/my/progress') {
      result['type'] = 'attempt';
    } else if (path == '/child/payments' || path == '/home/payments' || path.startsWith('/pay/orders')) {
      result['type'] = 'payment';
    } else if (path == '/child/diary' || path == '/school/diary') {
      result['type'] = 'diary';
    } else if (path == '/child') {
      result['type'] = 'child';
    } else if (path == '/my/certificates' || path == '/certificates' || path.startsWith('/c/')) {
      result['type'] = 'certificate';
    } else if (path.startsWith('/learn/assignments') || path.startsWith('/lms/my/assignments')) {
      result['type'] = 'assignment';
    } else if (path.startsWith('/crm/leads')) {
      result['type'] = 'lead';
      final lead = id(2) ?? uri.queryParameters['lead'] ?? uri.queryParameters['lead_id'];
      if (lead != null) result['lead_id'] = lead;
    } else if (path.startsWith('/crm/tasks')) {
      result['type'] = 'task';
    }
    final student = uri.queryParameters['student'] ?? uri.queryParameters['student_id'];
    if (student != null) result['student_id'] = student;
    return result;
  }

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
    FirebaseMessaging.onBackgroundMessage(pushBackgroundHandler);
    FirebaseMessaging.onMessage.listen(_foreground);
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _remember(message, read: true);
      open(Map<String, dynamic>.from(message.data));
    });
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      _remember(initial, read: true);
      _pending = Map<String, dynamic>.from(initial.data);
    }
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
      Future<void>.delayed(const Duration(milliseconds: 600), () => open(pending));
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

  void _remember(RemoteMessage message, {bool read = false}) {
    final item = notificationOf(message, read: read);
    if (item != null) unawaited(NotificationStore.instance.add(item));
  }

  void _foreground(RemoteMessage message) {
    _remember(message);
    final data = normalize(Map<String, dynamic>.from(message.data));
    final handler = dataHandlers[asText(data['type'])];
    if (handler != null) handler(data);
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
      action: routes[asText(data['type'])]?.call(data) != null
          ? SnackBarAction(
              label: tr('Ochish'),
              textColor: Colors.white,
              onPressed: () {
                final item = notificationOf(message);
                if (item != null) unawaited(NotificationStore.instance.markRead(item.id));
                open(data);
              },
            )
          : null,
    ));
  }

  /// Xabar bo'yicha sahifani ochish (push bosilganda va bildirishnomalar markazidan).
  Future<void> open(Map<String, dynamic> raw) async {
    final data = normalize(raw);
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
    // Sahifa quruvchisi rol, modul va qo'shimchani tekshiradi: ruxsat bo'lmasa null (403 sahifasi o'rniga bosh sahifa).
    final builder = routes[asText(data['type'])];
    Widget? page;
    try {
      page = builder?.call(data);
    } catch (_) {
      page = null;
    }
    final navigator = rootNavigator.currentState;
    if (navigator == null) return;
    if (page != null) {
      final target = page;
      await navigator.push(MaterialPageRoute<void>(builder: (_) => target));
    } else {
      // To'lov, davomat va h.k. — bosh sahifada ko'rinadi
      navigator.popUntil((route) => route.isFirst);
      onHome?.call(data);
    }
  }
}
