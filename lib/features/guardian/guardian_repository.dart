// Ota-ona («Farzandim») uchun barcha server so'rovlari shu yerda: endpointlar to'plami keyinchalik bitta joyda almashtiriladi.
//
// Hozirgi manbalar (server 1.28):
//   GET my/insights[?student_id]   — farzandlar ro'yxati + bitta farzand haqida umumiy holat (har qanday modul);
//   GET crm/my/children            — balans, hisoblanmalar, to'lovlar, oylik davomat (CRM moduli);
//   GET my/children                — test natijalari (Test moduli);
//   GET school/my/students|diary|progress — maktab kundaligi va baholar (Maktab moduli);
//   pay/*                           — onlayn to'lov (online_pay.dart orqali).
import 'package:flutter/widgets.dart';

import '../../core/api.dart';
import '../../core/session.dart';
import '../student/online_pay.dart';

class GuardianChild {
  const GuardianChild({required this.id, required this.name, this.code, this.groups = const <String>[]});

  factory GuardianChild.fromJson(Map<String, dynamic> json) => GuardianChild(
        id: asInt(json['id']),
        name: asText(json['name']),
        code: json['code']?.toString(),
        groups: ((json['groups'] as List?) ?? const <dynamic>[]).map((value) => '$value').toList(),
      );

  final int id;
  final String name;
  final String? code;
  final List<String> groups;

  /// Internetsiz nusxa uchun.
  Map<String, dynamic> toJson() => <String, dynamic>{'id': id, 'name': name, 'code': code, 'groups': groups};

  String get firstName {
    final parts = name.trim().split(RegExp(r'\s+'));
    return parts.length > 1 ? parts[1] : name;
  }
}

/// CRM bo'yicha farzand ma'lumoti (crm/my/children elementi).
class ChildFinance {
  const ChildFinance(this.raw);

  final Map<String, dynamic> raw;

  int get balance => asInt(raw['balance']);
  List<Map<String, dynamic>> get payments => asList(raw['payments'], 'payments');
  List<Map<String, dynamic>> get charges => asList(raw['charges'], 'charges');
  Map<String, dynamic> get attendance => asMap(raw['attendance']);
  Map<String, int> get attendanceCounts => asMap(attendance['counts']).map((key, value) => MapEntry(key, asInt(value)));
  List<Map<String, dynamic>> get lessons => asList(attendance['lessons'], 'lessons');
  String? get period => attendance['period']?.toString();
}

class GuardianRepository {
  GuardianRepository(this.session);

  final Session session;

  Api get _api => session.api;

  bool get hasCrm => session.hasModule('crm');
  bool get hasSchool => session.hasModule('school');
  bool get hasTesting => session.hasModule('testing');

  // crm/my/children hamma farzandni birdaniga qaytaradi — bir necha soniya keshlanadi (tablar bir vaqtda so'raydi).
  Future<List<Map<String, dynamic>>>? _crm;
  DateTime? _crmAt;
  Future<List<Map<String, dynamic>>>? _results;
  DateTime? _resultsAt;

  static const Duration _ttl = Duration(seconds: 20);

  /// Keyingi so'rovlar serverdan yangidan olinsin (pastga tortib yangilash).
  void invalidate() {
    _crm = null;
    _results = null;
  }

  /// Farzandlar: my/insights (modulga bog'liq emas), bo'lmasa maktab yoki test moduli ro'yxati. Guruhlar CRM dan qo'shiladi.
  Future<List<GuardianChild>> children() async {
    List<GuardianChild> list = <GuardianChild>[];
    try {
      final data = asMap(await _api.get('my/insights'));
      list = asList(data['children'], 'children')
          .map((item) => GuardianChild(id: asInt(item['id']), name: asText(item['full_name']), code: item['code']?.toString()))
          .toList();
    } on ApiException catch (error) {
      // 404 — farzand biriktirilmagan; boshqa xatolarda zaxira manbalar sinab ko'riladi.
      if (error.status == 404) return <GuardianChild>[];
      if (error.isNetwork) rethrow;
    }
    if (list.isEmpty && hasSchool) {
      try {
        list = asList(asMap(await _api.get('school/my/students'))['students'], 'students')
            .map((item) => GuardianChild(
                  id: asInt(item['id']),
                  name: asText(item['full_name']),
                  groups: ((item['classes'] as List?) ?? const <dynamic>[]).map((value) => '$value').toList(),
                ))
            .toList();
      } on ApiException catch (error) {
        if (error.isNetwork) rethrow;
      }
    }
    if (list.isEmpty && hasTesting) {
      list = asList(asMap(await _api.get('my/children'))['children'], 'children')
          .map((item) => GuardianChild(
                id: asInt(item['id']),
                name: asText(item['full_name']),
                groups: ((item['groups'] as List?) ?? const <dynamic>[]).map((value) => '$value').toList(),
              ))
          .toList();
    }
    if (hasCrm && list.isNotEmpty) {
      try {
        final crm = await _crmChildren();
        list = list.map((child) {
          final row = crm.firstWhere((item) => asInt(item['id']) == child.id, orElse: () => <String, dynamic>{});
          final groups = ((row['groups'] as List?) ?? const <dynamic>[]).map((value) => '$value').toList();
          return groups.isEmpty ? child : GuardianChild(id: child.id, name: child.name, code: child.code, groups: groups);
        }).toList();
      } catch (_) {
        // guruh nomlari majburiy emas
      }
    }
    return list;
  }

  /// Bitta farzand bo'yicha umumiy holat (testing / lms / school / crm bo'limlari — yoqilgan modullarga qarab).
  Future<Map<String, dynamic>> insights(int childId) async =>
      asMap(await _api.get('my/insights', query: <String, Object?>{'student_id': childId}));

  Future<List<Map<String, dynamic>>> _crmChildren() {
    final fresh = _crmAt != null && DateTime.now().difference(_crmAt!) < _ttl;
    if (_crm == null || !fresh) {
      _crmAt = DateTime.now();
      _crm = _api.get('crm/my/children').then((value) => asList(asMap(value)['children'], 'children'));
      // Xato keshda qolmasin
      _crm!.catchError((Object _) {
        _crm = null;
        return <Map<String, dynamic>>[];
      });
    }
    return _crm!;
  }

  /// To'lov va davomat (CRM moduli bo'lmasa — null).
  Future<ChildFinance?> finance(int childId) async {
    if (!hasCrm) return null;
    final rows = await _crmChildren();
    final row = rows.firstWhere((item) => asInt(item['id']) == childId, orElse: () => <String, dynamic>{});
    return row.isEmpty ? null : ChildFinance(row);
  }

  /// Test natijalari (Test moduli): so'nggi 20 ta topshirilgan test.
  Future<List<Map<String, dynamic>>> testResults(int childId) async {
    if (!hasTesting) return <Map<String, dynamic>>[];
    final fresh = _resultsAt != null && DateTime.now().difference(_resultsAt!) < _ttl;
    if (_results == null || !fresh) {
      _resultsAt = DateTime.now();
      _results = _api.get('my/children').then((value) => asList(asMap(value)['children'], 'children'));
    }
    try {
      final rows = await _results!;
      final row = rows.firstWhere((item) => asInt(item['id']) == childId, orElse: () => <String, dynamic>{});
      return asList(row['attempts'], 'attempts');
    } catch (_) {
      _results = null;
      rethrow;
    }
  }

  /// Maktab kundaligi: haftalik jadval (date — hafta ichidagi istalgan kun, YYYY-MM-DD).
  Future<Map<String, dynamic>> diaryWeek(int? childId, {String? date}) async =>
      asMap(await _api.get('school/my/diary', query: <String, Object?>{'student_id': childId, 'date': date}));

  /// Maktab: so'nggi baholar, qoldirilgan darslar, chorak baholari.
  Future<Map<String, dynamic>> schoolProgress(int childId) async =>
      asMap(await _api.get('school/my/progress', query: <String, Object?>{'student_id': childId}));

  /// Onlayn to'lov (Click/Payme) shu farzand uchun. Tugagach CRM keshi tozalanadi.
  Future<void> pay(BuildContext context, int childId, {int suggested = 0, VoidCallback? onDone}) {
    return startOnlinePayment(context, studentId: childId, suggested: suggested, onDone: (paid) {
      invalidate();
      onDone?.call();
    });
  }
}
