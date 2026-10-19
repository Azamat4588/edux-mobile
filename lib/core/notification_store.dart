// Bildirishnomalar markazi (3.1): kelgan push xabarlar telefonda saqlanadi — o'qilgan/o'qilmagan belgisi bilan,
// oxirgi 100 tasi. Fon (background) isolate ham shu faylga yozadi, shuning uchun o'qishdan oldin prefs.reload().
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppNotification {
  AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.data,
    required this.receivedAt,
    this.read = false,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
        id: '${json['id'] ?? ''}',
        title: '${json['title'] ?? ''}',
        body: '${json['body'] ?? ''}',
        data: json['data'] is Map ? Map<String, dynamic>.from(json['data'] as Map) : <String, dynamic>{},
        receivedAt: DateTime.tryParse('${json['received_at']}') ?? DateTime.now(),
        read: json['read'] == true,
      );

  final String id;
  final String title;
  final String body;
  final Map<String, dynamic> data;
  final DateTime receivedAt;
  bool read;

  /// Server: data.type (payment, attendance, arrival, attempt, assignment, certificate, lead, task ...).
  String get type => '${data['type'] ?? ''}';

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'body': body,
        'data': data,
        'received_at': receivedAt.toIso8601String(),
        'read': read,
      };
}

class NotificationStore extends ChangeNotifier {
  NotificationStore._();

  static final NotificationStore instance = NotificationStore._();

  static const String _key = 'notifications.items';
  static const int limit = 100;

  List<AppNotification> _items = <AppNotification>[];

  List<AppNotification> get items => List<AppNotification>.unmodifiable(_items);
  int get unread => _items.where((item) => !item.read).length;

  static List<AppNotification> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return <AppNotification>[];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return <AppNotification>[];
      return list.whereType<Map>().map((item) => AppNotification.fromJson(Map<String, dynamic>.from(item))).toList();
    } catch (_) {
      return <AppNotification>[];
    }
  }

  static String _encode(List<AppNotification> items) => jsonEncode(items.map((item) => item.toJson()).toList());

  /// Telefondagi ro'yxatni qayta o'qish (ilova ochilganda va oldingi planga qaytganda).
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      _items = _decode(prefs.getString(_key));
      notifyListeners();
    } catch (_) {}
  }

  /// Yangi xabarni yozish. Fon isolate'idan ham chaqiriladi (ChangeNotifier'siz).
  /// Bir xil id ikkinchi marta kelsa (fon + bosilganda) — takrorlanmaydi, faqat o'qilgan belgisi yangilanadi.
  static Future<void> persist(AppNotification item) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final list = _decode(prefs.getString(_key));
    final index = list.indexWhere((existing) => existing.id == item.id);
    if (index >= 0) {
      if (item.read) list[index].read = true;
    } else {
      list.insert(0, item);
    }
    if (list.length > limit) list.removeRange(limit, list.length);
    await prefs.setString(_key, _encode(list));
  }

  Future<void> add(AppNotification item) async {
    try {
      await persist(item);
    } catch (_) {}
    await load();
  }

  Future<void> _save() async {
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, _encode(_items));
    } catch (_) {}
  }

  Future<void> markRead(String id) async {
    final index = _items.indexWhere((item) => item.id == id);
    if (index < 0 || _items[index].read) return;
    _items[index].read = true;
    await _save();
  }

  Future<void> markAllRead() async {
    if (unread == 0) return;
    for (final item in _items) {
      item.read = true;
    }
    await _save();
  }

  Future<void> remove(String id) async {
    _items.removeWhere((item) => item.id == id);
    await _save();
  }

  /// Hammasini o'chirish (chiqishda ham — boshqa foydalanuvchi ko'rmasin).
  Future<void> clear() async {
    _items = <AppNotification>[];
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }
}
