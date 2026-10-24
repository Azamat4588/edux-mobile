// Laboratoriyalar katalogi (server 1.39: 462 lab, 15 fan, darslik mavzulari). Toza mantiq — test/labs_test.dart.
// Ro'yxat: GET my/labs (o'quvchi: + passed), har lab: code, name, subject (o'zgarmas kalit), subject_label (tarjima),
// grades ("7", "7–9"), description, topics [{grade, book, chapter, topic}]. Darslik daraxti: GET fun/labs/topics?subject=&grade=.
import 'api.dart';

/// Lablar katalogidagi fanlar (server tartibida, takrorsiz) — `subject` kaliti.
List<String> labSubjects(List<Map<String, dynamic>> labs) {
  final result = <String>[];
  for (final lab in labs) {
    final subject = asText(lab['subject']);
    if (subject.isNotEmpty && !result.contains(subject)) result.add(subject);
  }
  return result;
}

/// Fan nomi foydalanuvchi tilida (`subject_label`; eski serverda — kalitning o'zi).
String labSubjectLabel(Map<String, dynamic> lab) => asText(lab['subject_label'], asText(lab['subject']));

/// Sinf oralig'ining birinchi soni ("7–9" → 7, "10" → 10); topilmasa — 99 (oxirida).
int labFirstGrade(String grades) {
  final match = RegExp(r'\d+').firstMatch(grades);
  return match == null ? 99 : int.parse(match.group(0)!);
}

/// Sinf (yoki oraliq) bo'yicha guruhlar, kichik sinfdan kattasiga; guruh ichida — server tartibi.
Map<String, List<Map<String, dynamic>>> labsByGrade(List<Map<String, dynamic>> labs) {
  final groups = <String, List<Map<String, dynamic>>>{};
  for (final lab in labs) {
    groups.putIfAbsent(asText(lab['grades'], '—'), () => <Map<String, dynamic>>[]).add(lab);
  }
  final keys = groups.keys.toList()
    ..sort((a, b) {
      final byFirst = labFirstGrade(a).compareTo(labFirstGrade(b));
      return byFirst != 0 ? byFirst : a.length.compareTo(b.length);
    });
  return <String, List<Map<String, dynamic>>>{for (final key in keys) key: groups[key]!};
}

String _fold(String text) => text
    .toLowerCase()
    .replaceAll(RegExp('[ʻʼ‘’`´]'), "'")
    .replaceAll('ё', 'е');

/// Qidiruv: nom, tavsif, fan va darslik mavzulari (bob, mavzu, kitob) bo'yicha; har so'z topilishi kerak.
bool labMatches(Map<String, dynamic> lab, String query) {
  final words = _fold(query).split(RegExp(r'\s+')).where((word) => word.isNotEmpty).toList();
  if (words.isEmpty) return true;
  final haystack = StringBuffer()
    ..write(asText(lab['name']))
    ..write(' ')
    ..write(asText(lab['description']))
    ..write(' ')
    ..write(labSubjectLabel(lab))
    ..write(' ')
    ..write(asText(lab['code']));
  for (final topic in asList(lab['topics'], 'topics')) {
    haystack
      ..write(' ')
      ..write(asText(topic['topic']))
      ..write(' ')
      ..write(asText(topic['chapter']))
      ..write(' ')
      ..write(asText(topic['book']));
  }
  final text = _fold(haystack.toString());
  return words.every(text.contains);
}

/// Labning birinchi darslik mavzusi (kartada qisqa ko'rsatish): "Fizika 7 · §5. …".
String labTopicLine(Map<String, dynamic> lab) {
  final topics = asList(lab['topics'], 'topics');
  if (topics.isEmpty) return '';
  final first = topics.first;
  return <String>[asText(first['book']), asText(first['topic'])].where((part) => part.isNotEmpty).join(', ');
}

/// Darslik daraxtidagi sinflar (`books[].grade`, takrorsiz, o'sish tartibida).
List<int> textbookGrades(Map<String, dynamic> tree) {
  final grades = asList(tree['books'], 'books').map((book) => asInt(book['grade'])).where((grade) => grade > 0).toSet().toList()..sort();
  return grades;
}

/// Mavzudagi lab kodlari → katalogdagi lablar (katalogda yo'q kodlar tushiriladi).
List<Map<String, dynamic>> topicLabs(Map<String, dynamic> topic, Map<String, Map<String, dynamic>> byCode) {
  return asRawList(topic['labs']).map((code) => byCode['$code']).whereType<Map<String, dynamic>>().toList();
}

/// Daraxtdagi lab'li mavzular soni (bob sarlavhasida).
int chapterLabCount(Map<String, dynamic> chapter) =>
    asList(chapter['topics'], 'topics').where((topic) => asRawList(topic['labs']).isNotEmpty).length;
