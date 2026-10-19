// Kirish holati: server, token, foydalanuvchi, tashkilot va uning konteksti (rol, modullar).
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'i18n.dart';
import 'push.dart';
import 'theme.dart';

/// Ilova yig'ilganda beriladi: flutter build ... --dart-define=EDUX_SERVER=https://app.edux.uz
const String defaultServer = String.fromEnvironment('EDUX_SERVER', defaultValue: 'https://app.edux.uz');

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
  String _cachedMode = 'system';

  @override
  String get server => _server;

  @override
  String? get token => _token;

  @override
  int? get organizationId => _organizationId;

  bool get signedIn => _token != null;
  bool get hasContext => context.isNotEmpty;

  String get role => asText(context['role']);
  List<String> get modules => ((context['modules'] as List?) ?? const <dynamic>[]).map((item) => '$item').toList();
  bool hasModule(String module) => modules.contains(module);

  bool get isStaff => <String>['director', 'admin', 'teacher', 'cashier', 'marketer'].contains(role);
  bool get isStudent => role == 'student';
  bool get isGuardian => role == 'guardian';
  bool get isManager => role == 'director' || role == 'admin';
  bool get canScan => <String>['director', 'admin', 'teacher'].contains(role) && hasModule('testing');
  bool get canTakePayments => <String>['director', 'admin', 'cashier'].contains(role) && hasModule('crm');
  bool get canMarkAttendance => <String>['director', 'admin', 'teacher'].contains(role) && hasModule('crm');
  bool get canSeeStudents => <String>['director', 'admin', 'teacher', 'cashier'].contains(role);
  bool get readOnly => asMap(context['subscription'])['can_write'] == false;

  String get userName => asText(user['name']);
  String get organizationName => asText(asMap(context['organization'])['name']);
  String? get organizationLogo {
    final logo = asMap(context['organization'])['logo_url'];
    return logo == null ? null : api.absolute(logo.toString());
  }

  /// Ko'rinish: shaxsiy tanlov → tashkilot brendi → platforma standarti (veb bilan bir xil qoida).
  Map<String, dynamic> get appearance => asMap(user['appearance']);
  String get themeMode {
    final mode = asText(appearance['mode']);
    return mode.isNotEmpty ? mode : (_cachedMode.isNotEmpty ? _cachedMode : asText(siteTheme['mode'], 'system'));
  }

  Accent get accent {
    for (final candidate in <Object?>[appearance['accent'], asMap(context['theme'])['accent'], siteTheme['accent']]) {
      if (candidate != null && '$candidate'.isNotEmpty) return accentOf('$candidate');
    }
    return accents.first;
  }

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
    _cachedMode = prefs.getString('theme.mode') ?? 'system';
    unawaited(_loadSite());
    try {
      _token = await _secure.read(key: 'token');
    } catch (_) {
      _token = null;
    }
    if (_token != null) {
      try {
        _apply(asMap(await api.get('me')));
        await _chooseOrganization(prefs);
      } on ApiException catch (error) {
        if (error.isUnauthorized) {
          await _forget();
        }
        // Internet yo'q: token saqlanadi, kontekst keyin yuklanadi (Bosh sahifa qayta urinadi).
      }
    }
    restoring = false;
    notifyListeners();
  }

  Future<void> _loadSite() async {
    try {
      siteTheme = asMap(asMap(asMap(await api.get('site'))['theme'])['defaults']);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> setServer(String value) async {
    var clean = value.trim();
    if (clean.isEmpty) clean = defaultServer;
    if (!clean.startsWith('http://') && !clean.startsWith('https://')) clean = 'https://$clean';
    _server = clean.replaceAll(RegExp(r'/+$'), '');
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
    await _chooseOrganization(await SharedPreferences.getInstance());
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
    notifyListeners();
    await loadContext();
    notifyListeners();
  }

  Future<void> loadContext() async {
    context = asMap(await api.get('context'));
    notifyListeners();
    // Push: qurilma ro'yxatdan o'tadi (Firebase sozlangan bo'lsa).
    unawaited(PushService.instance.attach(this));
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
    user = <String, dynamic>{};
    memberships = <Membership>[];
    context = <String, dynamic>{};
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
