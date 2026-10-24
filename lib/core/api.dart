// EduX API (/api/v1) bilan ishlash: token, tashkilot va til sarlavhalari, xatolarni bir xil ko'rinishga keltirish.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'i18n.dart';

class ApiException implements Exception {
  ApiException(this.status, this.message, {this.errors = const <String, List<String>>{}, this.code});

  /// HTTP holati; 0 — internet yo'q yoki server javob bermadi.
  final int status;
  final String message;
  final Map<String, List<String>> errors;
  final String? code;

  bool get isNetwork => status == 0;
  bool get isUnauthorized => status == 401;
  bool get isForbidden => status == 403;

  /// Maydon xatosi (validatsiya) — birinchisi.
  String? field(String name) {
    final list = errors[name];
    return list == null || list.isEmpty ? null : list.first;
  }

  @override
  String toString() => message;
}

/// Server manzili, token va tashkilot — Session beradi.
abstract class ApiCredentials {
  String get server;
  String? get token;
  int? get organizationId;
  void onUnauthorized();
}

class Api {
  Api(this.credentials, {http.Client? client}) : _client = client ?? http.Client();

  final ApiCredentials credentials;
  final http.Client _client;

  static const Duration timeout = Duration(seconds: 30);
  static const Duration uploadTimeout = Duration(seconds: 90);

  String get base => '${credentials.server.replaceAll(RegExp(r'/+$'), '')}/api/v1';

  /// Server qaytargan nisbiy yo'l (masalan "/storage/logo.png") -> to'liq manzil.
  String absolute(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    final server = credentials.server.replaceAll(RegExp(r'/+$'), '');
    return path.startsWith('/') ? '$server$path' : '$server/$path';
  }

  Uri uri(String path, [Map<String, Object?>? query]) {
    final clean = path.startsWith('/') ? path.substring(1) : path;
    final params = <String, String>{};
    query?.forEach((key, value) {
      if (value != null && '$value' != '') params[key] = '$value';
    });
    final parsed = Uri.parse('$base/$clean');
    return params.isEmpty ? parsed : parsed.replace(queryParameters: <String, String>{...parsed.queryParameters, ...params});
  }

  Map<String, String> headers({bool json = true}) {
    final result = <String, String>{
      'Accept': 'application/json',
      'X-Locale': I18n.locale,
      'X-Requested-With': 'EduXMobile',
    };
    if (json) result['Content-Type'] = 'application/json';
    final token = credentials.token;
    if (token != null && token.isNotEmpty) result['Authorization'] = 'Bearer $token';
    final organization = credentials.organizationId;
    if (organization != null) result['X-Organization'] = '$organization';
    return result;
  }

  Future<dynamic> get(String path, {Map<String, Object?>? query}) =>
      _send(() => _client.get(uri(path, query), headers: headers(json: false)));

  Future<dynamic> post(String path, [Object? body]) =>
      _send(() => _client.post(uri(path), headers: headers(), body: jsonEncode(body ?? <String, Object?>{})));

  Future<dynamic> put(String path, [Object? body]) =>
      _send(() => _client.put(uri(path), headers: headers(), body: jsonEncode(body ?? <String, Object?>{})));

  Future<dynamic> patch(String path, [Object? body]) =>
      _send(() => _client.patch(uri(path), headers: headers(), body: jsonEncode(body ?? <String, Object?>{})));

  Future<dynamic> delete(String path) => _send(() => _client.delete(uri(path), headers: headers(json: false)));

  /// DELETE so'rovi tanasi bilan (masalan, qurilma tokenini o'chirish).
  Future<dynamic> deleteJson(String path, Object body) =>
      _send(() => _client.delete(uri(path), headers: headers(), body: jsonEncode(body)));

  /// Fayl yuklash (multipart/form-data).
  Future<dynamic> multipart(
    String path, {
    Map<String, String> fields = const <String, String>{},
    List<http.MultipartFile> files = const <http.MultipartFile>[],
  }) {
    return _send(() async {
      final request = http.MultipartRequest('POST', uri(path))
        ..headers.addAll(headers(json: false))
        ..fields.addAll(fields)
        ..files.addAll(files);
      final streamed = await _client.send(request);
      return http.Response.fromStream(streamed);
    }, limit: uploadTimeout);
  }

  /// Himoyalangan fayl yoki rasm (masalan, varaqa rasmi).
  Future<Uint8List> bytes(String path) async {
    final response = await _raw(() => _client.get(uri(path), headers: headers(json: false)), timeout);
    if (response.statusCode >= 400) throw _error(response);
    return response.bodyBytes;
  }

  Future<dynamic> _send(Future<http.Response> Function() request, {Duration limit = timeout}) async {
    final response = await _raw(request, limit);
    if (response.statusCode == 204 || response.bodyBytes.isEmpty) {
      if (response.statusCode >= 400) throw _error(response);
      return null;
    }
    if (response.statusCode >= 400) throw _error(response);
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      throw ApiException(response.statusCode, tr("Serverda xatolik yuz berdi. Birozdan keyin qayta urinib ko'ring."));
    }
  }

  Future<http.Response> _raw(Future<http.Response> Function() request, Duration limit) async {
    try {
      return await request().timeout(limit);
    } on TimeoutException {
      throw ApiException(0, tr("Server javob bermadi. Internetni tekshirib, qayta urinib ko'ring."));
    } on SocketException {
      throw ApiException(0, tr("Internetni tekshirib, qayta urinib ko'ring."));
    } on HandshakeException {
      throw ApiException(0, tr('Server bilan xavfsiz ulanib bo\'lmadi (sertifikat).'));
    } on http.ClientException {
      throw ApiException(0, tr("Internetni tekshirib, qayta urinib ko'ring."));
    }
  }

  ApiException _error(http.Response response) {
    var message = '';
    final errors = <String, List<String>>{};
    String? code;
    try {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is Map) {
        message = (data['message'] ?? '').toString();
        code = data['code']?.toString();
        final raw = data['errors'];
        if (raw is Map) {
          raw.forEach((key, value) {
            final list = value is List ? value.map((item) => tr(item.toString())).toList() : <String>[tr(value.toString())];
            errors[key.toString()] = list;
          });
        }
      }
    } catch (_) {
      // HTML yoki bo'sh javob
    }
    if (response.statusCode == 401) {
      credentials.onUnauthorized();
      message = message.isEmpty || message == 'Unauthenticated.' ? 'Kirish talab qilinadi. Qaytadan kiring.' : message;
    }
    if (message.isEmpty || message.startsWith('SQLSTATE') || message == 'Server Error') {
      message = switchStatus(response.statusCode);
    }
    // Validatsiyada umumiy xabar "... (and 1 more error)" ko'rinishida bo'ladi — birinchi maydon xatosi aniqroq.
    if (response.statusCode == 422 && errors.isNotEmpty) {
      message = errors.values.first.first;
    }
    return ApiException(response.statusCode, tr(message), errors: errors, code: code);
  }

  static String switchStatus(int status) {
    if (status == 403) return 'Bu amal uchun ruxsatingiz yo\'q.';
    if (status == 404) return 'Topilmadi.';
    if (status == 413) return 'Yuborilgan fayl juda katta.';
    if (status == 419) return 'Sahifa eskirgan. Sahifani yangilab, qayta urinib ko\'ring.';
    if (status == 429) return "Juda ko'p urinish. Birozdan keyin qayta urinib ko'ring.";
    if (status == 503) return "Tizimda texnik ishlar olib borilmoqda. Birozdan keyin qayta urinib ko'ring.";
    return "Serverda xatolik yuz berdi. Birozdan keyin qayta urinib ko'ring.";
  }
}

/// Javobdan ro'yxat: `[...]` yoki `{data: [...]}` (sahifalangan).
List<Map<String, dynamic>> asList(dynamic value, [String key = 'data']) {
  final list = value is List ? value : (value is Map ? value[key] : null);
  if (list is! List) return <Map<String, dynamic>>[];
  return list.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
}

Map<String, dynamic> asMap(dynamic value) => value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

int asInt(dynamic value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('${value ?? ''}') ?? fallback;
}

double asDouble(dynamic value, [double fallback = 0]) {
  if (value is num) return value.toDouble();
  return double.tryParse('${value ?? ''}') ?? fallback;
}

String asText(dynamic value, [String fallback = '']) => value == null ? fallback : value.toString();

/// Javobdagi xom ro'yxat (elementlar istalgan turda); ro'yxat bo'lmasa — bo'sh (`as List` crash bermasin).
List<dynamic> asRawList(dynamic value) => value is List ? value : const <dynamic>[];

/// Son yoki null: server raqamni matn ("12.5") ko'rinishida yuborsa ham o'qiladi.
num? asNumOrNull(dynamic value) {
  if (value is num) return value;
  if (value == null) return null;
  return num.tryParse(value.toString());
}
