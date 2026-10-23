// O'yinlar (server 1.38, backend docs/games.md): katalog, boshlash so'rovi, server javoblari modellari va klient mantig'i.
// Javob kaliti klientga kelmaydi — har yurish `POST my/games/{id}/answer` da serverda tekshiriladi (protokol `v: 2`).
// Bu fayl Flutter vidjetlarisiz: test/games_test.dart haqiqiy server javoblari (test/fixtures/games) bilan tekshiradi.
import 'api.dart';

/// O'yin manbalari: bank — fan savollari, words — so'z to'plami, math — daraja (sinf).
const List<String> gameSourceOrder = <String>['bank', 'words', 'math'];

const Map<String, String> gameSourceLabels = <String, String>{
  'bank': 'Savollar bankidan',
  'words': "So'z to'plamlaridan",
  'math': 'Matematika',
};

const Map<String, String> gameSourceHintLabels = <String, String>{
  'bank': 'Fanni tanlang — savollar savollar bazasidan olinadi.',
  'words': "O'qituvchingiz tuzgan so'z to'plamlari bilan o'ynaladi.",
  'math': 'Misollar har safar yangidan tuziladi. Sinfingizga mos darajani tanlang.',
};

/// Server tartibidagi 16 ta o'yin (App\Services\Fun\Games::TYPES) va manbasi.
const Map<String, String> gameSources = <String, String>{
  'quiz': 'bank',
  'truefalse': 'bank',
  'millionaire': 'bank',
  'survival': 'bank',
  'duel': 'bank',
  'match': 'words',
  'memory': 'words',
  'scramble': 'words',
  'hangman': 'words',
  'crossword': 'words',
  'typing': 'words',
  'flashcards': 'words',
  'sorting': 'words',
  'mathsprint': 'math',
  'sequence': 'math',
  'numsort': 'math',
};

/// Qisqa tavsif (katalog kartasi, darsdagi o'yin).
const Map<String, String> gameDescriptionLabels = <String, String>{
  'quiz': "90 soniyada 15 ta savol. Hammasiga javob bersangiz, qolgan vaqt ballga qo'shiladi.",
  'truefalse': "Savol va bitta javob chiqadi — to'g'rimi? 60 soniya, ketma-ket to'g'ri javoblarga bonus.",
  'millionaire': '10 bosqich, savollar qiyinlashib boradi. 50/50 va savolni almashtirish yordami bor.',
  'survival': '3 ta jon. Har xato bitta jonni oladi — iloji boricha uzoq chiday oling.',
  'duel': 'Guruhdoshingizning natijasi (yoki bot) bilan bir xil 10 ta savolda bellashing.',
  'match': "Yopiq kartalarni ochib, so'z va ma'nosini juftlang. Kam xato — ko'p ball.",
  'memory': "Hamma kartalar ochiq: chapdagi so'zni o'ngdagi ma'nosi bilan tez juftlang.",
  'scramble': "Ma'nosi berilgan so'zni aralash harflardan yig'ing. 3 daqiqa.",
  'hangman': "Ma'nosiga qarab so'zni harfma-harf toping. Har so'zga 6 ta xato.",
  'crossword': "To'plamdagi so'zlardan avtomatik tuzilgan kichik krossvord.",
  'typing': "Tarjimasi chiqadi — so'zni yozing. 2 daqiqada 15 ta so'z.",
  'flashcards': "O'rganish rejimi: kartani ag'daring, «Bilaman» yoki «Bilmayman». Bilmaganlaringiz qaytadi.",
  'sorting': "Bir nechta to'plam so'zlari aralashgan — har birini o'z to'plamiga ajrating.",
  'mathsprint': "60 soniyada iloji boricha ko'p misol yeching.",
  'sequence': 'Sonlar qatorining qoidasini toping va keyingi sonni yozing.',
  'numsort': 'Sonlarni toifalarga ajrating: juft/toq, tub/murakkab, kasrlar, ishoralar.',
};

/// Matematika darajalari (server MathGen::LEVELS) — eski server `levels` qaytarmasa.
const Map<String, String> gameLevelLabels = <String, String>{
  '1': '1–4-sinf',
  '2': '5–6-sinf',
  '3': '7–9-sinf',
  '4': '10–11-sinf',
};

String gameSourceOf(String game) => gameSources[game] ?? 'words';

/// Katalogda ko'rsatiladigan o'yinlar: server `sources` bergan bo'lsa — o'sha ro'yxat (bizning tartibda);
/// eski server (1.37 va undan oldin) `sources` bermaydi — faqat protokoli o'zgarmagan viktorina.
List<String> availableGames(Map<String, dynamic> catalog) {
  final sources = asMap(catalog['sources']);
  if (sources.isEmpty) return const <String>['quiz'];
  return gameSources.keys.where(sources.containsKey).toList();
}

/// O'yinni boshlash so'rovi (`POST my/games`). Darsdagi o'yinda manba darsdan olinadi.
Map<String, Object?> gameStartBody(String game, {int? id, int? lessonId}) {
  final body = <String, Object?>{'game': game, 'v': 2};
  if (lessonId != null) return body..['lesson_id'] = lessonId;
  switch (gameSourceOf(game)) {
    case 'bank':
      body['subject_id'] = id;
    case 'math':
      body['level'] = (id ?? 1).clamp(1, 4);
    default:
      body['word_set_id'] = id;
  }
  return body;
}

/// Katalogdagi manba (fan / to'plam / daraja) — tanlash ro'yxati uchun.
class GameSourceItem {
  const GameSourceItem({required this.id, required this.title, this.subtitle = '', this.record});

  final int id;
  final String title;
  final String subtitle;
  final int? record;
}

int? _recordOf(dynamic value) => value == null ? null : asInt(value);

/// O'yin uchun tanlanadigan manbalar va rekordlar (`GET my/games`).
List<GameSourceItem> gameSourceItems(Map<String, dynamic> catalog, String game) {
  switch (gameSourceOf(game)) {
    case 'bank':
      return asList(catalog['subjects'], 'subjects').map((subject) {
        final records = asMap(subject['records']);
        return GameSourceItem(
          id: asInt(subject['id']),
          title: asText(subject['name']),
          subtitle: '${asInt(subject['count'])}',
          record: _recordOf(records.isEmpty && game == 'quiz' ? subject['best'] : records[game]),
        );
      }).toList();
    case 'math':
      final levels = asList(catalog['levels'], 'levels');
      if (levels.isEmpty) {
        return gameLevelLabels.entries.map((entry) => GameSourceItem(id: int.parse(entry.key), title: entry.value)).toList();
      }
      return levels
          .map((level) => GameSourceItem(id: asInt(level['id']), title: asText(level['name']), record: _recordOf(asMap(level['records'])[game])))
          .toList();
    default:
      return asList(catalog['sets'], 'sets').map((set) {
        final parts = <String>[if (asText(set['subject']).isNotEmpty) asText(set['subject'])];
        return GameSourceItem(
          id: asInt(set['id']),
          title: asText(set['title']),
          subtitle: <String>[...parts, '${asInt(set['count'])}'].join(' · '),
          record: _recordOf(asMap(set['best'])[game]),
        );
      }).toList();
  }
}

/// Nima uchun o'yinni boshlab bo'lmaydi (manba yo'q): null — o'ynasa bo'ladi.
/// Qaytgan matn — lug'at kaliti (tr() bilan ko'rsatiladi).
String? gameBlockedReason(Map<String, dynamic> catalog, String game) {
  final source = gameSourceOf(game);
  if (source == 'math') return null;
  if (source == 'bank') {
    return asList(catalog['subjects'], 'subjects').isEmpty ? "Savollar bazasida o'yin uchun yetarli savol yo'q." : null;
  }
  final sets = asList(catalog['sets'], 'sets').length;
  if (game == 'sorting' && sets < 2) return "Kamida 2 ta so'z to'plami kerak — o'qituvchidan so'rang.";
  return sets == 0 ? "So'z to'plami kerak — o'qituvchidan so'rang." : null;
}

/// O'yinning eng yaxshi natijasi (barcha manbalar bo'yicha) — katalog kartasida.
int? gameBestRecord(Map<String, dynamic> catalog, String game) {
  int? best;
  for (final item in gameSourceItems(catalog, game)) {
    if (item.record != null && (best == null || item.record! > best)) best = item.record;
  }
  return best;
}

// ---------------------------------------------------------------------------
// Savollar bankidan

class GameOption {
  const GameOption({required this.id, required this.body, this.imageUrl});

  factory GameOption.fromJson(Map<String, dynamic> json) =>
      GameOption(id: asInt(json['id']), body: asText(json['body']), imageUrl: _url(json['image_url']));

  final int id;
  final String body;
  final String? imageUrl;
}

String? _url(dynamic value) => asText(value).isEmpty ? null : asText(value);

class GameQuestion {
  const GameQuestion({required this.id, required this.body, this.imageUrl, required this.options});

  factory GameQuestion.fromJson(Map<String, dynamic> json) => GameQuestion(
        id: asInt(json['id']),
        body: asText(json['body']),
        imageUrl: _url(json['image_url']),
        options: asList(json['options'], 'options').map(GameOption.fromJson).toList(),
      );

  static GameQuestion? maybe(dynamic json) => json is Map ? GameQuestion.fromJson(asMap(json)) : null;

  final int id;
  final String body;
  final String? imageUrl;
  final List<GameOption> options;
}

List<GameQuestion> _questions(dynamic value) => asList(value, 'questions').map(GameQuestion.fromJson).toList();

int? _seconds(Map<String, dynamic> json) => json['seconds'] == null ? null : asInt(json['seconds']);

class QuizStart {
  QuizStart.fromJson(Map<String, dynamic> json)
      : seconds = _seconds(json) ?? 90,
        questions = _questions(json['questions']);

  final int seconds;
  final List<GameQuestion> questions;
}

class TrueFalseItem {
  TrueFalseItem.fromJson(Map<String, dynamic> json)
      : id = asInt(json['id']),
        body = asText(json['body']),
        imageUrl = _url(json['image_url']),
        text = asText(json['text']),
        optionImageUrl = _url(json['option_image_url']);

  final int id;
  final String body;
  final String? imageUrl;

  /// Ko'rsatilgan javob (to'g'ri yoki noto'g'ri bo'lishi mumkin).
  final String text;
  final String? optionImageUrl;
}

class TrueFalseStart {
  TrueFalseStart.fromJson(Map<String, dynamic> json)
      : seconds = _seconds(json) ?? 60,
        items = asList(json['items'], 'items').map(TrueFalseItem.fromJson).toList();

  final int seconds;
  final List<TrueFalseItem> items;
}

class MillionaireStart {
  MillionaireStart.fromJson(Map<String, dynamic> json)
      : ladder = asRawList(json['ladder']).map(asInt).toList(),
        safe = asRawList(json['safe']).map(asInt).toList(),
        perQuestion = asInt(json['seconds_per_question'], 30),
        fifty = asMap(json['lifelines'])['fifty'] == true,
        swap = asMap(json['lifelines'])['swap'] == true,
        question = GameQuestion.maybe(json['question']);

  final List<int> ladder;

  /// Kafolatlangan bosqichlar (0 dan sanaladi).
  final List<int> safe;
  final int perQuestion;
  final bool fifty;
  final bool swap;
  final GameQuestion? question;
}

/// Millioner/omon qol/duel/viktorina javobi: to'g'rimi va to'g'ri variant.
class ChoiceResult {
  ChoiceResult.fromJson(Map<String, dynamic> json)
      : correct = json['correct'] == true,
        correctOptionId = asInt(json['correct_option_id']),
        late = json['late'] == true,
        level = asInt(json['level']),
        prize = asInt(json['prize']),
        lives = json['lives'] == null ? null : asInt(json['lives']),
        over = json['over'] == true,
        next = GameQuestion.maybe(json['question']),
        points = asInt(json['points']),
        opponentCorrect = asMap(json['opponent'])['correct'] == true,
        opponentPoints = asInt(asMap(json['opponent'])['points']);

  final bool correct;
  final int correctOptionId;
  final bool late;

  /// Millioner: o'tilgan bosqichlar va joriy yutuq.
  final int level;
  final int prize;

  /// Omon qol: qolgan jonlar.
  final int? lives;
  final bool over;
  final GameQuestion? next;

  /// Duel: shu savol uchun ball va raqib natijasi.
  final int points;
  final bool opponentCorrect;
  final int opponentPoints;
}

class SurvivalStart {
  SurvivalStart.fromJson(Map<String, dynamic> json)
      : lives = asInt(json['lives'], 3),
        perQuestion = asInt(json['seconds_per_question'], 20),
        question = GameQuestion.maybe(json['question']);

  final int lives;
  final int perQuestion;
  final GameQuestion? question;
}

class DuelStart {
  DuelStart.fromJson(Map<String, dynamic> json)
      : perQuestion = asInt(json['seconds_per_question'], 20),
        opponent = asText(asMap(json['opponent'])['name'], '—'),
        bot = asText(asMap(json['opponent'])['kind']) == 'bot',
        questions = _questions(json['questions']);

  final int perQuestion;
  final String opponent;
  final bool bot;
  final List<GameQuestion> questions;
}

/// Savol uchun qolgan soniyalar (savol berilgan paytdan).
int questionSecondsLeft(int perQuestion, DateTime askedAt, DateTime now) =>
    (perQuestion - now.difference(askedAt).inMilliseconds ~/ 1000).clamp(0, perQuestion);

/// Millioner: o'yinni to'xtatsa olinadigan ball (o'tilgan bosqich yutug'i).
int millionaireWalkPrize(List<int> ladder, int level) => level <= 0 || ladder.isEmpty ? 0 : ladder[(level - 1).clamp(0, ladder.length - 1)];

// ---------------------------------------------------------------------------
// So'z to'plamlaridan

class WordCard {
  WordCard.fromJson(Map<String, dynamic> json)
      : id = asText(json['id']),
        text = asText(json['text']),
        side = asText(json['side']);

  /// Taxmin qilib bo'lmaydigan token (juftlik raqami emas).
  final String id;
  final String text;

  /// match: term | definition
  final String side;
}

class MatchStart {
  MatchStart.fromJson(Map<String, dynamic> json) : cards = asList(json['cards'], 'cards').map(WordCard.fromJson).toList();

  final List<WordCard> cards;

  int get pairs => cards.length ~/ 2;
}

class MemoryStart {
  MemoryStart.fromJson(Map<String, dynamic> json)
      : terms = asList(json['terms'], 'terms').map(WordCard.fromJson).toList(),
        definitions = asList(json['definitions'], 'definitions').map(WordCard.fromJson).toList();

  final List<WordCard> terms;
  final List<WordCard> definitions;
}

class ScrambleWord {
  ScrambleWord.fromJson(Map<String, dynamic> json)
      : text = asText(json['text'], asText(json['hint'])),
        letters = asRawList(json['letters']).map((item) => '$item').toList(),
        length = asInt(json['length']);

  /// Ma'nosi.
  final String text;
  final List<String> letters;
  final int length;
}

class ScrambleStart {
  ScrambleStart.fromJson(Map<String, dynamic> json)
      : seconds = _seconds(json) ?? 180,
        words = asList(json['words'], 'words').map(ScrambleWord.fromJson).toList();

  final int seconds;
  final List<ScrambleWord> words;
}

/// So'z javobi (scramble, typing): to'g'rimi va to'g'ri so'z.
class WordResult {
  WordResult.fromJson(Map<String, dynamic> json)
      : correct = json['correct'] == true,
        answer = asText(json['answer']),
        late = json['late'] == true,
        explanation = asText(json['explanation']);

  final bool correct;
  final String answer;
  final bool late;

  /// Ketma-ketlik: qoida.
  final String explanation;
}

class HangmanWord {
  HangmanWord.fromJson(Map<String, dynamic> json)
      : text = asText(json['text']),
        mask = asRawList(json['mask']).map((item) => '${item ?? ''}').toList();

  /// Ma'nosi.
  final String text;

  /// Ochilgan harflar; '' — yopiq harf.
  final List<String> mask;
}

class HangmanStart {
  HangmanStart.fromJson(Map<String, dynamic> json)
      : misses = asInt(json['misses'], 6),
        alphabet = asRawList(json['alphabet']).map((item) => '$item').toList(),
        words = asList(json['words'], 'words').map(HangmanWord.fromJson).toList();

  final int misses;
  final List<String> alphabet;
  final List<HangmanWord> words;
}

class HangmanStep {
  HangmanStep.fromJson(Map<String, dynamic> json)
      : hit = json['hit'] == true,
        mask = asRawList(json['mask']).map((item) => '${item ?? ''}').toList(),
        misses = asInt(json['misses']),
        status = asText(json['status'], 'play'),
        answer = json['answer'] == null ? null : asText(json['answer']);

  final bool hit;
  final List<String> mask;
  final int misses;

  /// play | solved | failed
  final String status;
  final String? answer;

  bool get over => status != 'play';
}

/// Dor maskasi: «_ A _ _» (bo'shliq — so'zlar orasi).
String hangmanMaskText(List<String> mask) => mask.map((char) => char.isEmpty ? '_' : char).join(' ');

class CrosswordEntry {
  CrosswordEntry.fromJson(Map<String, dynamic> json)
      : id = asInt(json['id']),
        n = asInt(json['n']),
        across = asText(json['dir']) != 'down',
        x = asInt(json['x']),
        y = asInt(json['y']),
        length = asInt(json['length']),
        text = asText(json['text']);

  final int id;
  final int n;
  final bool across;
  final int x;
  final int y;
  final int length;

  /// Savol (atamaning ma'nosi).
  final String text;
}

class CrosswordStart {
  CrosswordStart.fromJson(Map<String, dynamic> json)
      : seconds = _seconds(json) ?? 900,
        width = asInt(json['width']),
        height = asInt(json['height']),
        entries = asList(json['entries'], 'entries').map(CrosswordEntry.fromJson).toList()..sort((a, b) => a.id.compareTo(b.id));

  final int seconds;
  final int width;
  final int height;

  /// `id` tartibida (yakundagi `answers` ham shu tartibda).
  final List<CrosswordEntry> entries;
}

class CrosswordCell {
  CrosswordCell(this.x, this.y);

  final int x;
  final int y;
  int? n;
  final List<int> entries = <int>[];
}

String cellKey(int x, int y) => '$x,$y';

/// So'z kataklari kalitlari tartib bilan: across — (x+i, y), down — (x, y+i).
List<String> entryKeys(CrosswordEntry entry) =>
    List<String>.generate(entry.length, (i) => entry.across ? cellKey(entry.x + i, entry.y) : cellKey(entry.x, entry.y + i));

/// Krossvord to'ri: "x,y" → katak (raqami va unga tegishli so'zlar; kesishmada ikkita).
Map<String, CrosswordCell> crosswordCells(List<CrosswordEntry> entries) {
  final cells = <String, CrosswordCell>{};
  for (final entry in entries) {
    final keys = entryKeys(entry);
    for (var i = 0; i < keys.length; i++) {
      final x = entry.across ? entry.x + i : entry.x;
      final y = entry.across ? entry.y : entry.y + i;
      final cell = cells.putIfAbsent(keys[i], () => CrosswordCell(x, y));
      if (i == 0) cell.n = entry.n;
      cell.entries.add(entry.id);
    }
  }
  return cells;
}

/// Yakundagi javoblar (`finish {answers}`): entry `id` tartibida, bo'sh katak — bo'shliq, oxiridagi bo'shliqlar olib tashlanadi.
List<String> crosswordAnswers(List<CrosswordEntry> entries, Map<String, String> letters) {
  final sorted = List<CrosswordEntry>.of(entries)..sort((a, b) => a.id.compareTo(b.id));
  return sorted.map((entry) => entryKeys(entry).map((key) => (letters[key] ?? '').isEmpty ? ' ' : letters[key]!).join().trimRight()).toList();
}

/// Keyingi (step = -1 — oldingi) katak so'z bo'ylab; chetida — o'zi.
String nextCell(CrosswordEntry entry, String key, [int step = 1]) {
  final keys = entryKeys(entry);
  final index = keys.indexOf(key);
  if (index < 0) return keys.first;
  return keys[(index + step).clamp(0, keys.length - 1)];
}

class TypingItem {
  TypingItem.fromJson(Map<String, dynamic> json)
      : id = asInt(json['id']),
        text = asText(json['text']),
        length = asInt(json['length']);

  final int id;

  /// Tarjimasi (ma'nosi).
  final String text;
  final int length;
}

class TypingStart {
  TypingStart.fromJson(Map<String, dynamic> json)
      : seconds = _seconds(json) ?? 120,
        items = asList(json['items'], 'items').map(TypingItem.fromJson).toList();

  final int seconds;
  final List<TypingItem> items;
}

class FlashCard {
  FlashCard.fromJson(Map<String, dynamic> json)
      : id = asInt(json['id']),
        text = asText(json['text']),
        body = asText(json['body']);

  final int id;

  /// So'z (old tomoni).
  final String text;

  /// Ma'nosi (orqa tomoni).
  final String body;
}

class FlashcardsStart {
  FlashcardsStart.fromJson(Map<String, dynamic> json) : cards = asList(json['cards'], 'cards').map(FlashCard.fromJson).toList();

  final List<FlashCard> cards;
}

/// Flesh-kartalar navbati: «bilaman» — navbatdan chiqadi, «bilmayman» — oxiriga qaytadi.
List<int> nextQueue(List<int> queue, bool known) {
  if (queue.isEmpty) return <int>[];
  final rest = queue.sublist(1);
  return known ? rest : <int>[...rest, queue.first];
}

class SortCategory {
  SortCategory.fromJson(Map<String, dynamic> json)
      : id = asInt(json['id']),
        title = asText(json['title']);

  final int id;
  final String title;
}

class SortItem {
  SortItem.fromJson(Map<String, dynamic> json)
      : id = asInt(json['id']),
        text = asText(json['text']);

  final int id;
  final String text;
}

/// Guruhlash va sonlarni guruhlash.
class SortingStart {
  SortingStart.fromJson(Map<String, dynamic> json)
      : seconds = _seconds(json) ?? 90,
        categories = asList(json['categories'], 'categories').map(SortCategory.fromJson).toList(),
        items = asList(json['items'], 'items').map(SortItem.fromJson).toList();

  final int seconds;
  final List<SortCategory> categories;
  final List<SortItem> items;
}

class SortResult {
  SortResult.fromJson(Map<String, dynamic> json)
      : correct = json['correct'] == true,
        category = asInt(json['category']),
        late = json['late'] == true;

  final bool correct;

  /// To'g'ri toifa id.
  final int category;
  final bool late;
}

// ---------------------------------------------------------------------------
// Matematika

class MathProblem {
  MathProblem.fromJson(Map<String, dynamic> json)
      : id = asInt(json['id']),
        text = asText(json['text']);

  final int id;
  final String text;
}

class MathSprintStart {
  MathSprintStart.fromJson(Map<String, dynamic> json)
      : seconds = _seconds(json) ?? 60,
        level = asInt(json['level'], 1),
        problems = asList(json['problems'], 'problems').map(MathProblem.fromJson).toList();

  final int seconds;
  final int level;
  final List<MathProblem> problems;
}

class SequenceItem {
  SequenceItem.fromJson(Map<String, dynamic> json)
      : id = asInt(json['id']),
        terms = asRawList(json['terms']).map(asInt).toList();

  final int id;
  final List<int> terms;
}

class SequenceStart {
  SequenceStart.fromJson(Map<String, dynamic> json)
      : seconds = _seconds(json) ?? 180,
        level = asInt(json['level'], 1),
        items = asList(json['items'], 'items').map(SequenceItem.fromJson).toList();

  final int seconds;
  final int level;
  final List<SequenceItem> items;
}

/// Sonni o'qish (server MathGen::parse kabi): unicode minus, bo'shliqlar. Noto'g'ri bo'lsa null.
int? parseGameNumber(String? value) {
  final text = (value ?? '').trim().replaceAll(RegExp('[−–]'), '-').replaceAll(RegExp(r'\s+'), '');
  if (!RegExp(r'^-?\d{1,9}$').hasMatch(text)) return null;
  return int.parse(text);
}

/// Ketma-ketlik qatori: «2, 4, 6, 8, …».
String sequenceText(List<int> terms) => '${terms.map((term) => term < 0 ? '−${-term}' : '$term').join(', ')}, …';

// ---------------------------------------------------------------------------
// Yakun

class ReviewRow {
  ReviewRow.fromJson(Map<String, dynamic> json)
      : body = asText(json['body']),
        answer = asText(json['answer']),
        ok = json['ok'] is bool ? json['ok'] as bool : null,
        explanation = asText(json['explanation']),
        value = asText(json['value']),
        truth = json['truth'] is bool ? json['truth'] as bool : null;

  final String body;
  final String answer;

  /// null — javob berilmagan.
  final bool? ok;
  final String explanation;

  /// O'quvchi javobi (matematik sprint).
  final String value;

  /// To'g'ri yoki noto'g'ri: ko'rsatilgan javob haqiqatda to'g'rimi.
  final bool? truth;
}

class LeaderRow {
  LeaderRow.fromJson(Map<String, dynamic> json)
      : name = asText(json['name'], '—'),
        score = asInt(json['score']),
        me = json['me'] == true;

  final String name;
  final int score;
  final bool me;
}

class GameResult {
  GameResult.fromJson(Map<String, dynamic> json)
      : score = asInt(json['score']),
        correct = asInt(json['correct']),
        total = asInt(json['total']),
        durationMs = asInt(json['duration_ms']),
        xp = asInt(json['xp']),
        xpDailyLimit = json['xp_daily_limit'] == null ? null : asInt(json['xp_daily_limit']),
        review = asList(json['review'], 'review').map(ReviewRow.fromJson).toList(),
        // Bo'sh `details` server (PHP) dan `[]` bo'lib keladi — asMap uni bo'sh obyektga aylantiradi.
        details = asMap(json['details']),
        best = asInt(json['best']),
        leaderboard = asList(json['leaderboard'], 'leaderboard').map(LeaderRow.fromJson).toList(),
        solutions = asRawList(json['solutions']).map((item) => '$item').toList();

  final int score;
  final int correct;
  final int total;
  final int durationMs;
  final int xp;

  /// Kunlik o'yin XP chegarasi (0 — cheklanmagan; eski server — null).
  final int? xpDailyLimit;
  final List<ReviewRow> review;
  final Map<String, dynamic> details;
  final int best;
  final List<LeaderRow> leaderboard;
  final List<String> solutions;

  bool get record => score > 0 && score >= best;
  int get mistakes => review.where((row) => row.ok == false).length;
  int get percent => gamePercent(correct, total);

  int? get bestStreak => details['best_streak'] == null ? null : asInt(details['best_streak']);
  int? get level => details['level'] == null ? null : asInt(details['level']);
  bool get won => details['won'] == true;
  int? get lives => details['lives'] == null ? null : asInt(details['lives']);
  int? get knownFirst => details['known_first'] == null ? null : asInt(details['known_first']);
  DuelOutcome? get duel => details['duel'] is Map ? DuelOutcome.fromJson(asMap(details['duel'])) : null;

  /// XP berilmagan sababi (bir marta yoki kunlik chegara) — lug'at kaliti va argument.
  bool get xpCapped => xp == 0 && correct > 0;
}

class DuelOutcome {
  DuelOutcome.fromJson(Map<String, dynamic> json)
      : opponent = asText(json['opponent'], '—'),
        bot = asText(json['kind']) == 'bot',
        opponentScore = asInt(json['opponent_score']),
        outcome = asText(json['outcome'], 'lose');

  final String opponent;
  final bool bot;
  final int opponentScore;

  /// win | draw | lose
  final String outcome;
}

int gamePercent(int correct, int total) => total > 0 ? (correct * 100 / total).round() : 0;

/// Jismoniy klaviatura harfini alifbodagi harfga moslash; mos kelmasa — null.
String? keyLetter(String key, List<String> alphabet) {
  if (key.runes.length != 1) return null;
  final upper = key.toUpperCase();
  return alphabet.contains(upper) ? upper : null;
}
