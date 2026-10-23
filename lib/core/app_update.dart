// Ilova yangilanishi (server: GET /public/apps → mobile.android {version, apk_url, play_url}, mobile.ios {app_store_url}).
// Platforma egasi versiyani «Platforma → Sayt → Ilovalar» da kiritadi; ilova o'z versiyasi bilan solishtiradi.
// Kuniga bir marta (ilova ochilganda) tekshiriladi; «Yana» sahifasida qo'lda tekshirish bor.
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'i18n.dart';
import 'push.dart';
import 'widgets.dart';

/// "3.10.0+12" ni "3.9.1" bilan solishtirish: musbat — a yangiroq. Raqam bo'lmagan qismlar (beta va h.k.) e'tiborsiz.
int compareVersions(String a, String b) {
  List<int> parts(String value) => value.split('+').first.trim().replaceFirst(RegExp('^[vV]'), '').split('.').map((part) {
        final digits = RegExp(r'^\d+').firstMatch(part)?.group(0);
        return digits == null ? 0 : int.parse(digits);
      }).toList();
  final x = parts(a);
  final y = parts(b);
  for (var i = 0; i < (x.length > y.length ? x.length : y.length); i++) {
    final left = i < x.length ? x[i] : 0;
    final right = i < y.length ? y[i] : 0;
    if (left != right) return left.compareTo(right);
  }
  return 0;
}

class AppUpdateInfo {
  const AppUpdateInfo({required this.version, required this.url, required this.store});

  /// Serverdagi so'nggi versiya (iPhone uchun server versiya bermaydi — bo'sh).
  final String version;

  /// Yuklab olish havolasi: Google Play (bo'lsa) yoki APK; iPhone — App Store.
  final String url;

  /// Do'kon havolasi (Google Play / App Store) — o'rnatish do'kon orqali.
  final bool store;
}

/// `public/apps` javobidan shu platforma uchun yangilanish: server versiyasi joriydan yangi bo'lsa.
/// iPhone: App Store versiyani o'zi yangilaydi — server versiya bermaydi, shuning uchun null.
AppUpdateInfo? updateFrom(Map<String, dynamic> apps, {required String platform, required String current}) {
  final mobile = asMap(apps['mobile']);
  if (platform != 'android') return null;
  final android = mobile.isNotEmpty ? asMap(mobile['android']) : asMap(asMap(apps['platforms'])['android']);
  final version = asText(android['version']).trim();
  if (version.isEmpty || compareVersions(version, current) <= 0) return null;
  final play = asText(android['play_url']).trim();
  final apk = asText(android['apk_url']).trim();
  final url = play.startsWith('https://') ? play : apk;
  if (!url.startsWith('https://')) return null;
  return AppUpdateInfo(version: version, url: url, store: play.startsWith('https://'));
}

class AppUpdate {
  AppUpdate._();

  static const String _checkedKey = 'update.checked_at';
  static const String _dismissedKey = 'update.dismissed';

  static String get platform => Platform.isAndroid ? 'android' : (Platform.isIOS ? 'ios' : 'other');

  /// Serverdan tekshirish (xato bo'lsa — null).
  static Future<AppUpdateInfo?> check(Api api) async {
    try {
      return updateFrom(asMap(await api.get('public/apps')), platform: platform, current: PushService.appVersion);
    } catch (_) {
      return null;
    }
  }

  /// Ilova ochilganda: kuniga bir marta; «Keyinroq» bosilgan versiya qayta ko'rsatilmaydi.
  static Future<void> maybeNotify(BuildContext context, Api api) async {
    if (platform != 'android') return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final last = DateTime.tryParse(prefs.getString(_checkedKey) ?? '');
      if (last != null && DateTime.now().difference(last).inHours < 20) return;
      await prefs.setString(_checkedKey, DateTime.now().toIso8601String());
      final info = await check(api);
      if (info == null || prefs.getString(_dismissedKey) == info.version || !context.mounted) return;
      final later = await _ask(context, info);
      if (later) await prefs.setString(_dismissedKey, info.version);
    } catch (_) {
      // Tekshiruv ixtiyoriy — xato ilovani to'xtatmaydi.
    }
  }

  /// true — «Keyinroq».
  static Future<bool> _ask(BuildContext context, AppUpdateInfo info) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.system_update_rounded),
        title: Text(tr('Yangi versiya: {0}', <Object?>[info.version])),
        content: Text(tr('Ilovaning yangi versiyasi chiqdi (sizda {0}). Yangilash tavsiya etiladi.', <Object?>[PushService.appVersion])),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('Keyinroq'))),
          FilledButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Yuklab olish'))),
        ],
      ),
    );
    if (result == false) await open(info);
    return result ?? true;
  }

  static Future<void> open(AppUpdateInfo info) => launchUrl(Uri.parse(info.url), mode: LaunchMode.externalApplication);
}

/// «Yana» sahifasidagi qator: joriy versiya va qo'lda tekshirish.
class AppVersionTile extends StatefulWidget {
  const AppVersionTile({super.key, required this.api});

  final Api api;

  @override
  State<AppVersionTile> createState() => _AppVersionTileState();
}

class _AppVersionTileState extends State<AppVersionTile> {
  bool _busy = false;
  AppUpdateInfo? _info;
  bool _checked = false;

  Future<void> _check() async {
    if (_info != null) {
      await AppUpdate.open(_info!);
      return;
    }
    setState(() => _busy = true);
    final info = await AppUpdate.check(widget.api);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _info = info;
      _checked = true;
    });
    if (info == null) showMessage(context, tr("Sizda so'nggi versiya o'rnatilgan."));
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    return ListTile(
      leading: Icon(info != null ? Icons.system_update_rounded : Icons.verified_outlined),
      title: Text(tr('Ilova versiyasi: {0}', <Object?>[PushService.appVersion])),
      subtitle: Text(info != null
          ? tr('Yangi versiya: {0}', <Object?>[info.version])
          : (_checked ? tr("Sizda so'nggi versiya o'rnatilgan.") : tr('Yangilanishni tekshirish'))),
      trailing: _busy
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : (info != null ? FilledButton(onPressed: () => AppUpdate.open(info), child: Text(tr('Yuklab olish'))) : const Icon(Icons.refresh)),
      onTap: _busy ? null : _check,
    );
  }
}
