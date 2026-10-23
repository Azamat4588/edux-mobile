// Test to'plami: variant kalitlari, ballar va o'quvchilar (kod -> ism). Telefonda internetsiz ham darhol
// baholash va o'quvchi ismini ko'rsatish uchun. Yakuniy natijani baribir server yozadi.
import 'dart:convert';
import 'dart:io';

import 'package:edux_omr/edux_omr.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/api.dart';

class KitGrade {
  KitGrade({required this.correct, required this.total, required this.score, required this.maxScore, required this.perQuestion});

  final int correct;
  final int total;
  final double score;
  final double maxScore;

  /// Har savol: true — to'g'ri, false — xato, null — javob yo'q.
  final List<bool?> perQuestion;
}

class ExamKit {
  ExamKit({
    required this.examId,
    required this.title,
    required this.questions,
    required this.options,
    required this.keys,
    required this.points,
    required this.students,
  });

  factory ExamKit.fromJson(Map<String, dynamic> json) {
    final exam = asMap(json['exam']);
    final keys = <int, List<List<int>>>{};
    final points = <int, List<int>>{};
    for (final variant in asList(json['variants'])) {
      final number = asInt(variant['number']);
      keys[number] = asRawList(variant['key'])
          .map((row) => asRawList(row).map((value) => asInt(value)).toList())
          .toList();
      points[number] = asRawList(variant['points_x100']).map((value) => asInt(value, 100)).toList();
    }
    final students = <String, String>{};
    for (final student in asList(json['students'])) {
      students[asText(student['code'])] = asText(student['name']);
    }
    return ExamKit(
      examId: asInt(exam['id']),
      title: asText(exam['title']),
      questions: asInt(exam['questions']),
      options: asInt(exam['options'], 4),
      keys: keys,
      points: points,
      students: students,
    );
  }

  final int examId;
  final String title;
  final int questions;
  final int options;
  final Map<int, List<List<int>>> keys;
  final Map<int, List<int>> points;
  final Map<String, String> students;

  String? studentName(String? code) => code == null ? null : students[code];

  /// Varaqani kalit bilan solishtiradi (to'g'ri — belgilar to'plami kalit bilan aynan bir xil bo'lsa).
  KitGrade? grade(int? variant, List<List<int>> answers) {
    final key = keys[variant];
    if (key == null || key.isEmpty) return null;
    final weights = points[variant] ?? const <int>[];
    var correct = 0;
    var score = 0.0;
    var max = 0.0;
    final perQuestion = <bool?>[];
    for (var i = 0; i < key.length; i++) {
      final weight = (i < weights.length ? weights[i] : 100) / 100;
      max += weight;
      final marks = i < answers.length ? (List<int>.of(answers[i])..sort()) : <int>[];
      final expected = List<int>.of(key[i])..sort();
      if (marks.isEmpty) {
        perQuestion.add(null);
        continue;
      }
      final ok = marks.length == expected.length && _same(marks, expected);
      perQuestion.add(ok);
      if (ok) {
        correct++;
        score += weight;
      }
    }
    return KitGrade(correct: correct, total: key.length, score: score, maxScore: max, perQuestion: perQuestion);
  }

  /// Variantdagi to'g'ri javoblar (ekranda belgilash uchun).
  List<List<int>>? keyFor(int? variant) => keys[variant];

  static bool _same(List<int> a, List<int> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// To'plamlar keshi: xotirada va diskda (internet yo'qolganda ham ishlaydi).
class KitStore {
  KitStore._();

  static final KitStore instance = KitStore._();

  final Map<String, ExamKit> _memory = <String, ExamKit>{};
  final Map<String, DateTime> _fetchedAt = <String, DateTime>{};

  String _key(Api api, int examId) => '${api.credentials.organizationId ?? 0}-$examId';

  Future<File> _file(String key) async {
    final dir = Directory('${(await getApplicationSupportDirectory()).path}/kits');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return File('${dir.path}/$key.json');
  }

  ExamKit? cached(Api api, int examId) => _memory[_key(api, examId)];

  /// To'plamni oladi. Yaqinda (5 daqiqa ichida) olingan bo'lsa — xotiradan; internet bo'lmasa — diskdan.
  Future<ExamKit?> get(Api api, int examId, {bool refresh = false}) async {
    final key = _key(api, examId);
    final fetched = _fetchedAt[key];
    if (!refresh && _memory[key] != null && fetched != null && DateTime.now().difference(fetched).inMinutes < 5) {
      return _memory[key];
    }
    try {
      final data = asMap(await api.get('scans/kit/$examId'));
      final kit = ExamKit.fromJson(data);
      _memory[key] = kit;
      _fetchedAt[key] = DateTime.now();
      try {
        await (await _file(key)).writeAsString(jsonEncode(data));
      } catch (_) {}
      return kit;
    } on ApiException catch (error) {
      if (!error.isNetwork) {
        if (error.status == 404 || error.status == 403) return null;
      }
    }
    if (_memory[key] != null) return _memory[key];
    try {
      final file = await _file(key);
      if (file.existsSync()) {
        final kit = ExamKit.fromJson(asMap(jsonDecode(await file.readAsString())));
        _memory[key] = kit;
        return kit;
      }
    } catch (_) {}
    return null;
  }

  /// O'qilgan varaqa uchun: QR dagi test to'plami.
  Future<ExamKit?> forReading(Api api, OmrReading reading) async {
    final examId = reading.examId;
    if (examId == null) return null;
    return get(api, examId);
  }
}
