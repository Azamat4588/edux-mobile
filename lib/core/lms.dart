// Dars konstruktori (backend 1.35 LessonBlocks): dars sahifasidagi bloklar tartibi. Toza mantiq — test/lms_test.dart.
//
// Blok turlari: content (dars matni), video (asosiy video yoki o'z `url` i), exam (test), activity (interaktiv blok:
// laboratoriya, o'yin, tekshiruv savollari), file / assignment / board (`ref` — material, vazifa, doska), text (o'z matni).
import 'api.dart';

class LessonBlock {
  const LessonBlock({required this.type, this.ref = 0, this.text = '', this.url = '', this.id = ''});

  final String type;
  final int ref;
  final String text;
  final String url;
  final String id;

  @override
  String toString() => ref > 0 ? '$type:$ref' : type;
}

const List<String> lessonBlockTypes = <String>['content', 'video', 'exam', 'activity', 'file', 'assignment', 'board', 'text'];

/// Dars javobidan bloklar ro'yxati. Server `blocks` bermasa (1.35 gacha) — avvalgi tartib: video, matn, interaktiv,
/// materiallar, vazifalar, test. Mavjud bo'lmagan material/vazifa/doska bloki tashlanadi.
List<LessonBlock> lessonBlocks(Map<String, dynamic> lesson) {
  final materials = asList(lesson['materials'], 'materials').map((item) => asInt(item['id'])).toSet();
  final assignments = asList(lesson['assignments'], 'assignments').map((item) => asInt(item['id'])).toSet();
  final boards = asList(lesson['boards'], 'boards').map((item) => asInt(item['id'])).toSet();
  final hasContent = asText(lesson['content']).trim().isNotEmpty;
  final hasVideo = asText(lesson['video_url']).trim().isNotEmpty;
  final hasExam = lesson['exam'] is Map;
  final hasActivity = lesson['activity'] is Map && asMap(lesson['activity']).isNotEmpty;

  final raw = lesson['blocks'];
  if (raw is List) {
    final result = <LessonBlock>[];
    final seen = <String>{};
    for (final item in raw.whereType<Map>()) {
      final block = Map<String, dynamic>.from(item);
      final type = asText(block['type']);
      final id = asText(block['id']);
      switch (type) {
        case 'file':
        case 'assignment':
        case 'board':
          final ref = asInt(block['ref']);
          final pool = type == 'file' ? materials : (type == 'assignment' ? assignments : boards);
          if (pool.contains(ref) && seen.add('$type:$ref')) result.add(LessonBlock(type: type, ref: ref, id: id));
        case 'text':
          final text = asText(block['text']);
          if (text.trim().isNotEmpty) result.add(LessonBlock(type: type, text: text, id: id));
        case 'video':
          final url = asText(block['url']);
          if (url.trim().isNotEmpty) {
            result.add(LessonBlock(type: type, url: url, id: id));
          } else if (hasVideo && seen.add('video')) {
            result.add(LessonBlock(type: type, url: asText(lesson['video_url']), id: id));
          }
        case 'content':
          if (hasContent && seen.add(type)) result.add(LessonBlock(type: type, id: id));
        case 'exam':
          if (hasExam && seen.add(type)) result.add(LessonBlock(type: type, id: id));
        case 'activity':
          if (hasActivity && seen.add(type)) result.add(LessonBlock(type: type, id: id));
      }
    }
    return result;
  }
  return <LessonBlock>[
    if (hasVideo) LessonBlock(type: 'video', url: asText(lesson['video_url'])),
    if (hasContent) const LessonBlock(type: 'content'),
    if (hasActivity) const LessonBlock(type: 'activity'),
    for (final id in materials) LessonBlock(type: 'file', ref: id),
    for (final id in assignments) LessonBlock(type: 'assignment', ref: id),
    if (hasExam) const LessonBlock(type: 'exam'),
  ];
}

/// Jonli dars holati (backend `live.state`): soon — 15 daqiqadan oldin, open — havola ochiq, ended — tugagan.
/// Server bermasa vaqtdan hisoblanadi.
String liveState(Map<String, dynamic> live, DateTime now) {
  final state = asText(live['state']);
  final starts = DateTime.tryParse(asText(live['starts_at']))?.toLocal();
  final ends = DateTime.tryParse(asText(live['ends_at']))?.toLocal();
  if (starts == null) return state.isEmpty ? 'ended' : state;
  if (now.isBefore(starts.subtract(const Duration(minutes: 15)))) return 'soon';
  if (ends != null && !now.isBefore(ends)) return 'ended';
  return state == 'ended' && ends == null ? 'ended' : 'open';
}

/// «Tushundim» so'rovi qiymatlari: 2 — tushundim, 1 — qisman, 0 — tushunmadim.
const Map<int, String> feedbackLabels = <int, String>{2: 'Tushundim', 1: 'Qisman', 0: 'Tushunmadim'};

/// Jonli dars xizmati nomi.
String liveProviderLabel(String provider) {
  const labels = <String, String>{'zoom': 'Zoom', 'meet': 'Google Meet', 'teams': 'Microsoft Teams', 'jitsi': 'Jitsi', 'telegram': 'Telegram'};
  return labels[provider] ?? '';
}
