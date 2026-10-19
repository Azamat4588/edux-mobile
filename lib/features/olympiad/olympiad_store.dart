// Olimpiadalarim: server o'quvchiga «mening olimpiadalarim» ro'yxatini bermaydi — qatnashilgan olimpiada havolalari
// (token) telefonda saqlanadi va har biri GET /public/olympiads/{token} bilan yangilanadi (token bilan «me» qaytadi).
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api.dart';
import '../../core/session.dart';

class OlympiadStore {
  OlympiadStore._();

  /// Olimpiada tokeni: 12 ta kichik harf/raqam (havoladagi /o/<token>).
  static final RegExp _token = RegExp(r'^[a-z0-9]{12}$');

  /// "https://app.edux.uz/o/abc123def456", "/o/abc..." yoki tokenning o'zi → token.
  static String? parse(String value) {
    final text = value.trim();
    final match = RegExp(r'/o/([a-z0-9]{12})(?:[/?#]|$)').firstMatch(text);
    if (match != null) return match.group(1);
    final lower = text.toLowerCase();
    return _token.hasMatch(lower) ? lower : null;
  }

  static String _key(Session session) =>
      'olympiads.${Uri.tryParse(session.server)?.host ?? session.server}.${session.user['id'] ?? 0}.${session.organizationId ?? 0}';

  static Future<List<String>> tokens(Session session) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key(session)) ?? <String>[];
  }

  /// Yangisi ro'yxat boshiga qo'yiladi.
  static Future<void> remember(Session session, String token) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key(session)) ?? <String>[];
    list
      ..remove(token)
      ..insert(0, token);
    await prefs.setStringList(_key(session), list.take(50).toList());
  }

  static Future<void> forget(Session session, String token) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key(session)) ?? <String>[];
    list.remove(token);
    await prefs.setStringList(_key(session), list);
    await prefs.remove('${_key(session)}.p.$token');
  }

  /// Ishtirokchining shaxsiy kaliti (32 belgi): tashqi ishtirokchi sifatida ro'yxatdan o'tilganda kerak (?p=...).
  static Future<String?> participant(Session session, String token) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('${_key(session)}.p.$token');
  }

  static Future<void> rememberParticipant(Session session, String token, String participant) async {
    if (participant.length != 32) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('${_key(session)}.p.$token', participant);
  }

  /// GET /public/olympiads/{token} (shaxsiy kalit bo'lsa ?p= bilan).
  static Future<Map<String, dynamic>> fetch(Session session, String token) async {
    final p = await participant(session, token);
    return asMap(await session.api.get('public/olympiads/$token', query: <String, Object?>{'p': p}));
  }
}
