// Kirish holati: server, token, foydalanuvchi, tashkilot va uning konteksti (rol, modullar).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'design.dart';
import 'i18n.dart';
import 'notification_store.dart';
import 'offline_cache.dart';
import 'push.dart';
import 'theme.dart';

/// Ilova yig'ilganda beriladi: flutter build ... --dart-define=EDUX_SERVER=https://edux.kuchkarov.uz
const String defaultServer = String.fromEnvironment('EDUX_SERVER', defaultValue: 'https://edux.kuchkarov.uz');

/// Server manzilini bir xil ko'rinishga keltiradi: bo'shliqlar olinadi, sxema bo'lmasa https:// qo'shiladi,
/// oxiridagi "/" belgilar olib tashlanadi. Bo'sh qiymat — standart server.
String normalizeServer(String value) {
  var clean = value.trim();
  if (clean.isEmpty) clean = defaultServer.trim();
  if (!clean.startsWith('http://') && !clean.startsWith('https://')) clean = 'https://$clean';
  return clean.replaceAll(RegExp(r'/+$'), '');
}

class Membership {
  Membership(this.organizationId, this.organization, this.role);

  factory Membership.fromJson(Map<String, dynamic> json) =>
      Membership(asInt(json['organization_id']), asText(json['organization']), asText(json['role']));

  final int organizationId;
  final String organization;
  final String role;
}

class Session extends ChangeNotifier implements ApiCredentials {
  Session() {
    api = Api(this);
  }

  /// Telefondagi kontekst nusxasi kaliti: server javobi shakli o'zgarganda (1.29) versiya oshiriladi — eski nusxa o'qilmaydi.
  static const String _contextKey = 'offline.context.v2';

  late final Api api;

  static const FlutterSecureStorage _secure = FlutterSecureStorage();

  String _server = defaultServer;
  String? _token;
  int? _organizationId;
  Map<String, dynamic> user = <String, dynamic>{};
  List<Membership> memberships = <Membership>[];
  Map<String, dynamic> context = <String, dynamic>{};
  bool restoring = true;

  /// Platforma dizayn standarti (GET /site → theme.defaults) va oxirgi tanlangan rejim (internetsiz ochilganda ham).
  Map<String, dynamic> siteTheme = <String, dynamic>{};

  /// Platforma ruxsatlari (GET /site → theme): allow_user — foydalanuvchi rang/shablonni o'zi uchun o'zgartira oladi.
  Map<String, dynamic> siteDesign = <String, dynamic>{};
  String _cachedMode = '';

  @override
  String get server => _server;

  /// Joriy server standart serverning o'zi (oxiridagi "/" va h.k. farqlari hisobga olinmaydi).
  bool get usesDefaultServer => normalizeServer(_server) == normalizeServer(defaultServer);

  @override
  String? get token => _token;

  @override
  int? get organizationId => _organizationId;

  /// Ilova internetsiz ochildi: foydalanuvchi va tashkilot konteksti telefondagi nusxadan (3.1).
  bool contextFromCache = false;

  bool get signedIn => _token != null;
  bool get hasContext => context.isNotEmpty;

  String get role => asText(context['role']);
  List<String> get modules => ((context['modules'] as List?) ?? const <dynamic>[]).map((item) => '$item').toList();
  bool hasModule(String module) => modules.contains(module);

  /// Qo'shimcha imkoniyatlar (server 1.28+): ai, callcenter, sms, olympiad, access, fun, branches, telegram.
  List<String> get features => ((context['features'] as List?) ?? const <dynamic>[]).map((item) => '$item').toList();

  /// Eski server `features` qaytarmaydi — unda qo'shimchalar alohida cheklanmagan deb hisoblanadi.
  bool hasFeature(String feature) => context['features'] is! List || features.contains(feature);

  /// Bitta test ishtirokchisi (havola orqali kirgan mehmon): kabinetida faqat o'sha test.
  bool get isGuest => context['guest'] == true;

  bool get isStaff => <String>['director', 'admin', 'teacher', 'cashier', 'marketer'].contains(role);
  bool get isStudent => role == 'student';
  bool get isGuardian => role == 'guardian';
  bool get isManager => role == 'director' || role == 'admin';
  bool get isTeacher => role == 'teacher';

  /// Direktor, administrator va o'qituvchi (server: overview, students, groups, exams yo'llari shu rollarga ochiq).
  bool get isAcademicStaff => isManager || isTeacher;
  bool get canScan => isAcademicStaff && hasModule('testing');
  bool get canTakePayments => <String>['director', 'admin', 'cashier'].contains(role) && hasModule('crm');
  bool get canMarkAttendance => isAcademicStaff && hasModule('crm');

  /// Kirish nazorati (QR / Face ID): `access` qo'shimchasi (server: feature:access).
  bool get canCheckIn => isAcademicStaff && hasFeature('access');
  bool get canUseKiosk => isManager && hasFeature('access');

  /// SMS shlyuz: CRM + `sms` qo'shimchasi (server SMS ni shu qo'shimchasiz yubormaydi), direktor va administrator.
  bool get canUseSmsGateway => isManager && hasModule('crm') && hasFeature('sms');

  /// O'quvchilar ro'yxati (1.29 yagona sahifa): rahbar va o'qituvchi — umumiy `students`, kassir — faqat CRM bilan.
  bool get canSeeStudents => isAcademicStaff || (role == 'cashier' && hasModule('crm'));

  /// CRM ro'yxati va kartasi (balans, holatlar) — rahbar va kassirga; o'qituvchi CRM bo'lsa ham umumiy ro'yxatni ko'radi.
  bool get usesCrmStudents => hasModule('crm') && <String>['director', 'admin', 'cashier'].contains(role);

  /// Bosh sahifa ko'rsatkichlari (GET overview) — direktor, administrator, o'qituvchi.
  bool get canSeeOverview => isAcademicStaff;
  bool get canSeeLeads => hasModule('crm') && <String>['director', 'admin', 'marketer'].contains(role);
  bool get canSeeTasks => isStaff && hasModule('crm');

  /// Obuna «faqat o'qish» holatida (yoki platforma to'xtatgan): yozuvlar 402 bilan rad etiladi.
  bool get readOnly => asMap(context['subscription'])['can_write'] == false;
  bool get suspended => asMap(context['subscription'])['suspended'] == true;

  /// single — bitta tashkilot o'zi uchun o'rnatgan (obuna yo'q).
  bool get singleMode => asText(context['mode']) == 'single';

  /// «Modullar va obuna» (GET billing) — direktor va administrator, ko'p tashkilotli platformada.
  bool get canManageBilling => isManager && !singleMode;

  /// Coin (CRM sozlamasi): o'chirilsa coin bloklari yashiriladi. Server bermasa — yoqilgan deb olinadi (veb bilan bir xil).
  bool get coinsEnabled => hasModule('crm') && context['coins_enabled'] != false;

  /// Rag'bat: XP (`fun`) yoki coin.
  bool get hasRewards => hasFeature('fun') || coinsEnabled;

  // 3.1: xodim bo'limlari (modul, imkoniyat va rolga qarab).
  bool get canCallCenter =>
      <String>['director', 'admin', 'marketer', 'cashier'].contains(role) && hasModule('crm') && hasFeature('callcenter');
  bool get canSeeFinance => <String>['director', 'admin', 'cashier'].contains(role) && hasModule('crm');
  bool get canBuildTopicTests => isAcademicStaff && hasModule('testing');

  /// Kartaga o'tkazmalar (1.35): direktor, administrator, kassir; CRM yoki LMS moduli (server: pay/p2p).
  bool get canSeeP2p => <String>['director', 'admin', 'cashier'].contains(role) && (hasModule('crm') || hasModule('lms'));

  /// Ta'lim (LMS) xodim sahifalari: savol-javob, kurs e'lonlari (server: organization:director,admin,teacher + module:lms).
  bool get canTeachLms => isAcademicStaff && hasModule('lms');

  /// Menyu va bosh sahifa ruxsatlari bir joyda (lib/core/nav.dart, home_today.dart).
  bool can(String permission) {
    final full = isStudent && !isGuest;
    switch (permission) {
      case 'crm':
        return hasModule('crm');
      case 'school':
        return hasModule('school') && !isGuest;
      case 'lms':
        return (isStudent ? full : true) && hasModule('lms');
      case 'testing':
        return hasModule('testing') && (isStudent || isGuardian || isAcademicStaff);
      case 'guest':
        return isGuest;
      case 'students':
        return canSeeStudents;
      case 'leads':
        return canSeeLeads;
      case 'attendance':
        return canMarkAttendance;
      case 'checkin':
        return canCheckIn;
      case 'kiosk':
        return canUseKiosk;
      case 'scan':
        return canScan;
      case 'topic_tests':
        return canBuildTopicTests;
      case 'finance':
        return canSeeFinance;
      case 'take_payments':
        return canTakePayments && !readOnly;
      case 'p2p':
        return canSeeP2p;
      case 'callcenter':
        return canCallCenter;
      case 'tasks':
        return canSeeTasks;
      case 'sms_gateway':
        return canUseSmsGateway && defaultTargetPlatform == TargetPlatform.android;
      case 'platform_sms':
        return isPlatformAdmin && defaultTargetPlatform == TargetPlatform.android;
      case 'billing':
        return canManageBilling;
      case 'staff_ai':
        return canUseStaffAi;
      case 'lms_staff':
        return canTeachLms;
      case 'fun':
        return full && hasFeature('fun');
      case 'olympiad':
        return full && hasModule('testing') && hasFeature('olympiad');
      case 'tutor':
        return canUseTutor;
      case 'rewards':
        return full && hasRewards;
      case 'certificates':
        return full && (hasModule('testing') || hasModule('lms'));
    }
    return false;
  }

  /// AI holati (GET ai/status: staff, tutor, remaining) — kontekstdan keyin bir marta olinadi; null — hali noma'lum.
  Map<String, dynamic>? aiStatus;
  bool get canUseStaffAi => isStaff && hasFeature('ai') && aiStatus?['staff'] != false;
  bool get canUseTutor => isStudent && !isGuest && hasFeature('ai') && aiStatus?['tutor'] != false;

  String get userName => asText(user['name']);
  String get organizationName => asText(asMap(context['organization'])['name']);
  String? get organizationLogo {
    final logo = asMap(context['organization'])['logo_url'];
    return logo == null ? null : api.absolute(logo.toString());
  }

  /// Ko'rinish: shaxsiy tanlov → tashkilot brendi → platforma standarti (veb bilan bir xil qoida, docs/design.md).
  Map<String, dynamic> get appearance => asMap(user['appearance']);

  /// 3.4: birlashtirilgan ko'rinish — rejim, rang, shablon (eski vivid/midnight → school/night), shrift, o'lcham, burchak.
  ThemeChoice get themeChoice =>
      ThemeChoice.resolve(<Map<String, dynamic>>[siteTheme, asMap(context['theme']), appearance], cachedMode: _cachedMode);

  String get themeMode => themeChoice.mode;

  Accent get accent => accentOf(themeChoice.accent);

  /// Rang, shablon, shrift va burchakni foydalanuvchi o'zi tanlay oladimi (platforma ruxsati). Rejim va o'lcham — har doim.
  bool get canCustomizeTheme => siteDesign['allow_user'] == true;

  /// Shaxsiy ko'rinish maydonlari (size, accent, template ...): darhol qo'llanadi va hisobga saqlanadi (null — standart).
  Future<void> setAppearance(Map<String, String?> values) async {
    final next = <String, dynamic>{...appearance};
    for (final entry in values.entries) {
      if (entry.value == null) {
        next.remove(entry.key);
      } else {
        next[entry.key] = entry.value;
      }
    }
    user = <String, dynamic>{...user, 'appearance': next};
    notifyListeners();
    try {
      final data = asMap(await api.put('profile/appearance', values));
      user = <String, dynamic>{...user, 'appearance': asMap(data['appearance'])};
      final prefs = await SharedPreferences.getInstance();
      unawaited(prefs.setString('offline.me', jsonEncode(<String, Object?>{'user': user, 'memberships': _membershipsJson()})));
      notifyListeners();
    } catch (_) {
      // internet yo'q: shu ochilishda qo'llangan, keyingi safar server bilan tenglashadi
    }
  }

  List<Map<String, Object?>> _membershipsJson() => memberships
      .map((item) => <String, Object?>{'organization_id': item.organizationId, 'organization': item.organization, 'role': item.role})
      .toList();

  /// Platforma egasi (sotuv paneli vebda; ilovada — platforma SMS shlyuzi).
  bool get isPlatformAdmin => user['is_platform_admin'] == true;

  /// Kunduzgi/tungi/qurilmaga qarab: darhol qo'llanadi, hisobga saqlanadi (veb bilan umumiy).
  Future<void> setThemeMode(String mode) async {
    _cachedMode = mode;
    user = <String, dynamic>{...user, 'appearance': <String, dynamic>{...appearance, 'mode': mode}};
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme.mode', mode);
    notifyListeners();
    try {
      final data = asMap(await api.put('profile/appearance', <String, Object?>{'mode': mode}));
      user = <String, dynamic>{...user, 'appearance': asMap(data['appearance'])};
    } catch (_) {
      // internet yo'q: telefonda saqlangan, keyingi safar server bilan tenglashadi
    }
  }

  /// Tashkilot turiga qarab atamalar (Guruh/Sinf, O'quvchi/Talaba).
  String term(String key, String fallback) {
    final value = asMap(context['terms'])[key];
    return value == null ? tr(fallback) : tr(value.toString());
  }

  Membership? get membership {
    for (final item in memberships) {
      if (item.organizationId == _organizationId) return item;
    }
    return null;
  }

  @override
  void onUnauthorized() {
    if (_token == null) return;
    // Token bekor qilingan yoki muddati tugagan: qaytadan kirish kerak.
    Future<void>.microtask(signOut);
  }

  /// Ilova ochilganda: saqlangan til, server va token.
  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final languageCode = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    await I18n.load(prefs.getString('locale') ?? I18n.fromDevice(languageCode));
    _server = prefs.getString('server') ?? defaultServer;
    _organizationId = prefs.getInt('organization');
    _cachedMode = prefs.getString('theme.mode') ?? '';
    // Platforma dizayni oxirgi nusxadan — ilova internetsiz ham o'z shabloni va shriftida ochilsin.
    try {
      final site = prefs.getString('site.theme');
      if (site != null) _applySite(asMap(jsonDecode(site)));
    } catch (_) {}
    unawaited(_loadSite());
    try {
      _token = await _secure.read(key: 'token');
    } catch (_) {
      _token = null;
    }
    if (_token != null) {
      try {
        final me = asMap(await api.get('me'));
        _apply(me);
        unawaited(prefs.setString('offline.me', jsonEncode(me)));
        await _chooseOrganization(prefs);
      } on ApiException catch (error) {
        if (error.isUnauthorized) {
          await _forget();
        } else {
          // Internet yo'q: token saqlanadi, oxirgi foydalanuvchi va kontekst nusxasi bilan ochiladi.
          _restoreOffline(prefs);
        }
      }
    }
    restoring = false;
    notifyListeners();
  }

  /// Internetsiz ochilish: telefonda saqlangan `me` va tanlangan tashkilot konteksti (bo'lmasa — oddiy kutish oynasi).
  void _restoreOffline(SharedPreferences prefs) {
    try {
      final me = prefs.getString('offline.me');
      final organization = _organizationId;
      final context = organization == null ? null : prefs.getString('$_contextKey.$organization');
      if (me == null || context == null) return;
      _apply(asMap(jsonDecode(me)));
      this.context = asMap(jsonDecode(context));
      contextFromCache = true;
      _setCacheScope();
    } catch (_) {
      // nusxa buzilgan — oddiy yo'l bilan qayta urinadi
    }
  }

  void _setCacheScope() {
    final organization = _organizationId;
    OfflineCache.scope = organization == null ? '' : '${asInt(user['id'])}-$organization';
  }

  Future<void> _loadSite() async {
    try {
      final theme = asMap(asMap(await api.get('site'))['theme']);
      _applySite(theme);
      final prefs = await SharedPreferences.getInstance();
      unawaited(prefs.setString('site.theme', jsonEncode(theme)));
      notifyListeners();
    } catch (_) {}
  }

  void _applySite(Map<String, dynamic> theme) {
    siteDesign = theme;
    siteTheme = asMap(theme['defaults']);
  }

  Future<void> setServer(String value) async {
    _server = normalizeServer(value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server', _server);
    notifyListeners();
    unawaited(_loadSite());
  }

  Future<void> setLocale(String code) async {
    await I18n.load(code);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('locale', I18n.locale);
    if (_token != null && _organizationId != null) {
      // Server yorliqlari (holatlar, modul nomlari) yangi tilda kelsin
      try {
        await loadContext();
      } catch (_) {}
      unawaited(PushService.instance.updateLocale());
    }
    notifyListeners();
  }

  Future<void> login(String login, String password) async {
    final data = asMap(await api.post('auth/login', <String, Object?>{
      'login': login.trim(),
      'password': password,
      'device_name': 'EduX mobil',
    }));
    await _accept(data);
  }

  /// Kirish oynasi uchun: parolsiz kirish yoqilganmi (kod, Telegram), parolni tiklash va h.k.
  Future<Map<String, dynamic>> authOptions() async => asMap(await api.get('auth/options'));

  /// Bir martalik kod: Telegramga (hisob bog'langan bo'lsa) yoki SMS bilan. Javob — server xabari.
  Future<String> requestLoginCode(String phone) async {
    final data = asMap(await api.post('auth/code', <String, Object?>{'phone': phone.trim()}));
    return asText(data['message']);
  }

  Future<void> loginWithCode(String phone, String code) async {
    final data = asMap(await api.post('auth/code/verify', <String, Object?>{'phone': phone.trim(), 'code': code.trim()}));
    await _accept(data);
  }

  /// Telegram orqali kirish: {key, url} — url botni ochadi, key bilan holat so'raladi.
  Future<Map<String, dynamic>> startTelegramLogin() async => asMap(await api.post('auth/telegram-link'));

  /// Holat: pending | need_phone | expired | ok (ok bo'lsa — kirildi).
  Future<String> pollTelegramLogin(String key) async {
    final data = asMap(await api.get('auth/telegram-link/$key'));
    final status = asText(data['status'], 'expired');
    if (status == 'ok') await _accept(data);
    return status;
  }

  /// O'quvchining shaxsiy havolasi: https://.../join/<token> yoki tokenning o'zi.
  Future<void> loginWithInvite(String linkOrToken) async {
    var value = linkOrToken.trim();
    final match = RegExp(r'/join/([A-Za-z0-9]+)').firstMatch(value);
    if (match != null) value = match.group(1)!;
    final data = asMap(await api.post('auth/invite', <String, Object?>{'token': value}));
    await _accept(data);
  }

  Future<void> _accept(Map<String, dynamic> data) async {
    final token = asText(data['token']);
    if (token.isEmpty) throw ApiException(500, tr("Kirib bo'lmadi. Qayta urinib ko'ring."));
    _token = token;
    await _secure.write(key: 'token', value: token);
    _apply(data);
    final prefs = await SharedPreferences.getInstance();
    unawaited(prefs.setString('offline.me', jsonEncode(<String, Object?>{'user': data['user'], 'memberships': data['memberships']})));
    await _chooseOrganization(prefs);
    notifyListeners();
  }

  void _apply(Map<String, dynamic> data) {
    user = asMap(data['user']);
    memberships = asList(data['memberships']).map(Membership.fromJson).toList();
  }

  Future<void> _chooseOrganization(SharedPreferences prefs) async {
    if (memberships.isEmpty) {
      _organizationId = null;
      context = <String, dynamic>{};
      return;
    }
    final saved = memberships.where((item) => item.organizationId == _organizationId);
    if (saved.isEmpty) {
      if (memberships.length > 1) {
        // Bir nechta tashkilot: foydalanuvchi o'zi tanlaydi (OrganizationPicker).
        _organizationId = null;
        context = <String, dynamic>{};
        return;
      }
      _organizationId = memberships.first.organizationId;
    }
    await prefs.setInt('organization', _organizationId!);
    await loadContext();
  }

  Future<void> selectOrganization(int id) async {
    _organizationId = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('organization', id);
    context = <String, dynamic>{};
    aiStatus = null;
    notifyListeners();
    await loadContext();
    notifyListeners();
  }

  Future<void> loadContext() async {
    context = asMap(await api.get('context'));
    contextFromCache = false;
    _setCacheScope();
    final organization = _organizationId;
    if (organization != null) {
      final prefs = await SharedPreferences.getInstance();
      unawaited(prefs.setString('$_contextKey.$organization', jsonEncode(context)));
    }
    aiStatus = null;
    notifyListeners();
    // Push: qurilma ro'yxatdan o'tadi (Firebase sozlangan bo'lsa).
    unawaited(PushService.instance.attach(this));
    unawaited(_loadAiStatus());
  }

  /// AI ustoz / yordamchi menyuda faqat tashkilot sozlamasida yoqilgan bo'lsa ko'rinsin (veb: ai/status).
  Future<void> _loadAiStatus() async {
    if (!hasFeature('ai') || isGuardian) return;
    final organization = _organizationId;
    try {
      final status = asMap(await api.get('ai/status'));
      if (organization != _organizationId) return;
      aiStatus = status;
      notifyListeners();
    } catch (_) {
      // noma'lum — menyu ochiq qoladi, sahifaning o'zi holatni ko'rsatadi
    }
  }

  Future<void> signOut() async {
    if (_token != null) {
      await PushService.instance.detach(this);
      try {
        await api.post('auth/logout');
      } catch (_) {
        // tarmoq yo'q — token baribir unutiladi
      }
    }
    await _forget();
    notifyListeners();
  }

  Future<void> _forget() async {
    _token = null;
    contextFromCache = false;
    OfflineCache.scope = '';
    await OfflineCache.clear();
    await NotificationStore.instance.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys().where((key) => key.startsWith('offline.')).toList()) {
        await prefs.remove(key);
      }
    } catch (_) {}
    user = <String, dynamic>{};
    memberships = <Membership>[];
    context = <String, dynamic>{};
    aiStatus = null;
    try {
      await _secure.delete(key: 'token');
    } catch (_) {}
  }
}

/// Session ga widget daraxtidan kirish: `AppScope.of(context)`.
class AppScope extends InheritedNotifier<Session> {
  const AppScope({super.key, required Session session, required super.child}) : super(notifier: session);

  static Session of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope topilmadi');
    return scope!.notifier!;
  }

  /// Qayta chizishga obuna bo'lmasdan (tugma bosilganda va h.k.).
  static Session read(BuildContext context) {
    final scope = context.getElementForInheritedWidgetOfExactType<AppScope>()?.widget as AppScope?;
    return scope!.notifier!;
  }
}
