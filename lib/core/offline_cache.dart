// Internetsiz ko'rish (3.1): asosiy sahifalarning oxirgi muvaffaqiyatli javobi telefonda JSON fayl bo'lib saqlanadi.
// Internet bo'lmasa sahifa shu nusxani «Internet yo'q» belgisi bilan ko'rsatadi; pastga tortib yangilash qayta urinadi.
//
// Fayllar foydalanuvchi + tashkilot bo'yicha ajratiladi (scope), chiqishda hammasi o'chiriladi.
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class CachedEntry {
  const CachedEntry(this.data, this.savedAt);

  final dynamic data;
  final DateTime savedAt;
}

class OfflineCache {
  OfflineCache._();

  /// "<foydalanuvchi>-<tashkilot>" — Session o'rnatadi. Bo'sh bo'lsa hech narsa saqlanmaydi.
  static String scope = '';

  /// Bitta javob uchun eng katta hajm (katta ro'yxatlar xotirani to'ldirmasin).
  static const int maxBytes = 2 * 1024 * 1024;

  static Directory? _dir;

  static Future<Directory> _root() async {
    final existing = _dir;
    if (existing != null) return existing;
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/offline');
    if (!dir.existsSync()) await dir.create(recursive: true);
    _dir = dir;
    return dir;
  }

  static String _name(String key) => '${scope}_$key'.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');

  static Future<void> write(String key, Object? data) async {
    if (scope.isEmpty) return;
    try {
      final text = jsonEncode(<String, Object?>{'saved_at': DateTime.now().toIso8601String(), 'data': data});
      if (text.length > maxBytes) return;
      final dir = await _root();
      final file = File('${dir.path}/${_name(key)}.json');
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(text, flush: true);
      await temp.rename(file.path);
    } catch (_) {
      // xotira to'la yoki ma'lumot JSON emas — kesh majburiy emas
    }
  }

  static Future<CachedEntry?> read(String key) async {
    if (scope.isEmpty) return null;
    try {
      final dir = await _root();
      final file = File('${dir.path}/${_name(key)}.json');
      if (!file.existsSync()) return null;
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map) return null;
      final savedAt = DateTime.tryParse('${raw['saved_at']}') ?? DateTime.now();
      return CachedEntry(raw['data'], savedAt);
    } catch (_) {
      return null;
    }
  }

  /// Chiqishda: boshqa foydalanuvchi telefonni olsa, eski ma'lumot ko'rinmasin.
  static Future<void> clear() async {
    try {
      final dir = await _root();
      if (dir.existsSync()) await dir.delete(recursive: true);
    } catch (_) {}
    _dir = null;
  }
}
