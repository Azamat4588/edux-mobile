// 3.6.0: o'yinlar (server 1.38, protokol v2). Fixture'lar — demo serverdan olingan haqiqiy start/answer/finish javoblari
// (test/fixtures/games/<o'yin>.json: {start, answers: [{request, status, response}], finish}).
import 'dart:convert';
import 'dart:io';

import 'package:edux/core/api.dart';
import 'package:edux/core/games.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> game(String name) => asMap(jsonDecode(File('test/fixtures/games/$name.json').readAsStringSync()));
Map<String, dynamic> start(String name) => asMap(game(name)['start']);
List<Map<String, dynamic>> responses(String name) => asList(game(name)['answers'], 'answers').map((row) => asMap(row['response'])).toList();
GameResult finish(String name) => GameResult.fromJson(asMap(game(name)['finish']));

void main() {
  group('katalog', () {
    final catalog = game('catalog');

    test('16 ta o\'yin, manbalar va guruhlar', () {
      expect(gameSources.length, 16);
      expect(availableGames(catalog), gameSources.keys.toList());
      for (final code in gameSources.keys) {
        expect(asMap(catalog['sources'])[code], gameSources[code], reason: code);
        expect(asMap(catalog['games'])[code], isNotEmpty, reason: code);
        expect(gameDescriptionLabels[code], isNotNull, reason: code);
      }
      expect(gameSourceOrder.map((s) => gameSources.values.where((v) => v == s).length).toList(), <int>[5, 8, 3]);
    });

    test('eski server (sources yo\'q) — faqat viktorina', () {
      expect(availableGames(<String, dynamic>{'subjects': <dynamic>[], 'sets': <dynamic>[]}), <String>['quiz']);
    });

    test('manba ro\'yxati va rekordlar', () {
      final subjects = gameSourceItems(catalog, 'millionaire');
      expect(subjects, isNotEmpty);
      expect(subjects.first.title, isNotEmpty);
      final sets = gameSourceItems(catalog, 'hangman');
      expect(sets.length, asList(catalog['sets'], 'sets').length);
      expect(sets.first.subtitle, contains(' · '));
      final levels = gameSourceItems(catalog, 'mathsprint');
      expect(levels.map((l) => l.id).toList(), <int>[1, 2, 3, 4]);
      expect(gameSourceItems(<String, dynamic>{}, 'sequence').length, 4);
      final withRecord = <String, dynamic>{
        'sets': <dynamic>[
          <String, dynamic>{'id': 3, 'title': 'A', 'count': 9, 'best': <String, dynamic>{'memory': 450}},
          <String, dynamic>{'id': 4, 'title': 'B', 'count': 9, 'best': <String, dynamic>{'memory': 700}},
        ],
      };
      expect(gameBestRecord(withRecord, 'memory'), 700);
      expect(gameBestRecord(withRecord, 'typing'), isNull);
    });

    test('manba yo\'q bo\'lsa sababi', () {
      expect(gameBlockedReason(catalog, 'quiz'), isNull);
      expect(gameBlockedReason(catalog, 'sorting'), isNull);
      final one = <String, dynamic>{'subjects': <dynamic>[], 'sets': <dynamic>[<String, dynamic>{'id': 1}]};
      expect(gameBlockedReason(one, 'sorting'), contains('2 ta'));
      expect(gameBlockedReason(one, 'match'), isNull);
      expect(gameBlockedReason(one, 'duel'), isNotNull);
      expect(gameBlockedReason(<String, dynamic>{}, 'mathsprint'), isNull);
      expect(gameBlockedReason(<String, dynamic>{}, 'typing'), contains("o'qituvchidan"));
    });

    test('boshlash so\'rovi: v=2, manba yoki dars', () {
      expect(gameStartBody('duel', id: 2), <String, Object?>{'game': 'duel', 'v': 2, 'subject_id': 2});
      expect(gameStartBody('crossword', id: 7), <String, Object?>{'game': 'crossword', 'v': 2, 'word_set_id': 7});
      expect(gameStartBody('numsort', id: 9), <String, Object?>{'game': 'numsort', 'v': 2, 'level': 4});
      expect(gameStartBody('sequence'), <String, Object?>{'game': 'sequence', 'v': 2, 'level': 1});
      expect(gameStartBody('memory', id: 7, lessonId: 15), <String, Object?>{'game': 'memory', 'v': 2, 'lesson_id': 15});
    });
  });

  group('savollar bankidan', () {
    test('viktorina: kalit klientda yo\'q, javobda to\'g\'ri variant', () {
      final quiz = QuizStart.fromJson(start('quiz'));
      expect(quiz.seconds, 90);
      expect(quiz.questions.length, 15);
      expect(quiz.questions.first.options.length, greaterThanOrEqualTo(2));
      expect(jsonEncode(start('quiz')), isNot(contains('is_correct')));
      final first = ChoiceResult.fromJson(responses('quiz').first);
      expect(first.correct, isTrue);
      expect(quiz.questions.first.options.map((o) => o.id), contains(first.correctOptionId));
      expect(ChoiceResult.fromJson(responses('quiz')[1]).correct, isFalse);
      final result = finish('quiz');
      expect(result.correct, 3);
      expect(result.total, 15);
      expect(result.review.length, 15);
      expect(result.review.where((r) => r.ok == null).length, 11);
      expect(result.details, isEmpty, reason: "server bo'sh details uchun [] qaytaradi");
      expect(result.xpDailyLimit, 100);
    });

    test('to\'g\'ri yoki noto\'g\'ri: seriya va tahlilda truth', () {
      final tf = TrueFalseStart.fromJson(start('truefalse'));
      expect(tf.seconds, 60);
      expect(tf.items.length, greaterThanOrEqualTo(8));
      expect(tf.items.first.text, isNotEmpty);
      final answers = responses('truefalse');
      expect(answers.map((a) => a['streak']).toList(), <Object?>[1, 2, 0, 1, 2, 3]);
      final result = finish('truefalse');
      expect(result.bestStreak, 3);
      expect(result.review.every((r) => r.truth != null), isTrue);
      expect(result.score, 5 * 50 - 20 + 3 * 10);
    });

    test('millioner: 50/50, almashtirish, to\'xtash', () {
      final m = MillionaireStart.fromJson(start('millionaire'));
      expect(m.ladder, <int>[100, 200, 300, 500, 1000, 2000, 4000, 8000, 16000, 32000]);
      expect(m.safe, <int>[4]);
      expect(m.perQuestion, 30);
      expect(m.fifty && m.swap, isTrue);
      expect(m.question, isNotNull);
      final rows = responses('millionaire');
      expect(asRawList(rows[0]['remove']).length, 2);
      final step = ChoiceResult.fromJson(rows[1]);
      expect(step.correct && !step.over, isTrue);
      expect(step.level, 1);
      expect(step.prize, 100);
      expect(step.next, isNotNull);
      expect(GameQuestion.maybe(rows[2]['question'])!.options, isNotEmpty);
      expect(rows[4]['over'], isTrue);
      expect(millionaireWalkPrize(m.ladder, 2), 200);
      expect(millionaireWalkPrize(m.ladder, 0), 0);
      final result = finish('millionaire');
      expect(result.level, 2);
      expect(result.won, isFalse);
      expect(result.score, 200);
    });

    test('omon qol: jonlar va keyingi savol', () {
      final s = SurvivalStart.fromJson(start('survival'));
      expect(s.lives, 3);
      expect(s.perQuestion, 20);
      final steps = responses('survival').map(ChoiceResult.fromJson).toList();
      expect(steps.map((r) => r.lives).toList(), <int?>[3, 2, 2, 1, 1, 0]);
      expect(steps.last.over, isTrue);
      expect(steps.last.next, isNull);
      expect(steps.first.next!.id, isNot(s.question!.id));
      final result = finish('survival');
      expect(result.lives, 0);
      expect(result.total, 6);
    });

    test('duel: raqib va natija', () {
      final d = DuelStart.fromJson(start('duel'));
      expect(d.questions.length, 10);
      expect(d.opponent, isNotEmpty);
      final step = ChoiceResult.fromJson(responses('duel').first);
      expect(step.points, greaterThanOrEqualTo(100));
      expect(responses('duel')[2]['points'], 0);
      final duel = finish('duel').duel!;
      expect(<String>['win', 'draw', 'lose'], contains(duel.outcome));
      expect(duel.opponentScore, greaterThan(0));
      expect(questionSecondsLeft(20, DateTime(2026, 1, 1, 10), DateTime(2026, 1, 1, 10, 0, 7, 400)), 13);
      expect(questionSecondsLeft(20, DateTime(2026, 1, 1, 10), DateTime(2026, 1, 1, 10, 1)), 0);
    });
  });

  group("so'z to'plamlaridan", () {
    test('juftini top (v2): kartalarda juftlik raqami yo\'q', () {
      final m = MatchStart.fromJson(start('match'));
      expect(m.cards.length, 16);
      expect(m.pairs, 8);
      expect(jsonEncode(start('match')), isNot(contains('"pair"')));
      expect(m.cards.map((c) => c.id).toSet().length, 16);
      final rows = responses('match');
      expect(rows.first['match'], isTrue);
      // Topilgan juftning kartasi qayta yuborilsa — xato sanalmaydi.
      expect(rows[1]['match'], isFalse);
      expect(rows[1]['repeat'], isTrue);
      expect(rows[1]['mistakes'], 0);
      expect(rows.last['done'], 8);
      final result = finish('match');
      expect(result.correct, 8);
      expect(result.details['mistakes'], 0);
    });

    test('xotira kartalari', () {
      final m = MemoryStart.fromJson(start('memory'));
      expect(m.terms.length, m.definitions.length);
      expect(m.terms.length, greaterThanOrEqualTo(4));
      expect(responses('memory').first['correct'], isFalse);
      expect(finish('memory').correct, 3);
    });

    test("so'z yig'ish (v2): har so'z alohida", () {
      final s = ScrambleStart.fromJson(start('scramble'));
      expect(s.seconds, 180);
      expect(s.words.first.letters.length, s.words.first.length);
      expect(s.words.first.text, isNotEmpty);
      final ok = WordResult.fromJson(responses('scramble').first);
      expect(ok.correct, isTrue);
      final bad = WordResult.fromJson(responses('scramble')[1]);
      expect(bad.correct, isFalse);
      expect(bad.answer, isNotEmpty);
      expect(finish('scramble').solutions.length, s.words.length);
    });

    test('dor: mask va holat', () {
      final h = HangmanStart.fromJson(start('hangman'));
      expect(h.misses, 6);
      expect(h.alphabet, contains('A'));
      expect(h.words.first.mask.every((c) => c.isEmpty || !RegExp(r'\p{L}', unicode: true).hasMatch(c)), isTrue);
      final steps = responses('hangman').map(HangmanStep.fromJson).toList();
      expect(steps.first.hit, isFalse);
      expect(steps.first.misses, 1);
      final solved = steps.firstWhere((s) => s.status == 'solved');
      expect(solved.answer, isNotEmpty);
      expect(solved.mask.join(), solved.answer);
      expect(steps.last.status, 'failed');
      expect(hangmanMaskText(<String>['', 'A', ' ', 'B']), '_ A   B');
      expect(finish('hangman').correct, 1);
      expect(keyLetter('a', h.alphabet), 'A');
      expect(keyLetter('1', h.alphabet), isNull);
      expect(keyLetter('ab', h.alphabet), isNull);
    });

    test('krossvord: to\'r, javoblar id tartibida', () {
      final c = CrosswordStart.fromJson(start('crossword'));
      expect(c.entries.length, start('crossword')['total']);
      final cells = crosswordCells(c.entries);
      for (final entry in c.entries) {
        final keys = entryKeys(entry);
        expect(keys.length, entry.length);
        expect(cells[keys.first]!.n, entry.n);
        for (final key in keys) {
          final cell = cells[key]!;
          expect(cell.x, inInclusiveRange(0, c.width - 1));
          expect(cell.y, inInclusiveRange(0, c.height - 1));
        }
      }
      expect(cells.values.where((cell) => cell.entries.length == 2), isNotEmpty, reason: "so'zlar kesishadi");
      final entry = c.entries.first;
      final keys = entryKeys(entry);
      final letters = <String, String>{keys[0]: 'A', keys[2]: 'C'};
      final answers = crosswordAnswers(c.entries, letters);
      expect(answers.length, c.entries.length);
      expect(answers.first, 'A C');
      expect(nextCell(entry, keys[0]), keys[1]);
      expect(nextCell(entry, keys[0], -1), keys[0]);
      expect(nextCell(entry, keys.last), keys.last);
      final result = finish('crossword');
      expect(result.correct, (c.entries.length + 1) ~/ 2);
    });

    test('tez yozish', () {
      final t = TypingStart.fromJson(start('typing'));
      expect(t.seconds, 120);
      expect(t.items.first.length, greaterThan(0));
      expect(WordResult.fromJson(responses('typing').first).correct, isTrue);
      expect(WordResult.fromJson(responses('typing')[1]).answer, isNotEmpty);
    });

    test('flesh-kartalar: navbat', () {
      final f = FlashcardsStart.fromJson(start('flashcards'));
      expect(f.cards.first.body, isNotEmpty);
      expect(nextQueue(<int>[1, 2, 3], true), <int>[2, 3]);
      expect(nextQueue(<int>[1, 2, 3], false), <int>[2, 3, 1]);
      expect(nextQueue(<int>[], false), <int>[]);
      expect(responses('flashcards').last['known'], 2);
      final result = finish('flashcards');
      expect(result.knownFirst, 1);
      expect(result.xp, lessThanOrEqualTo(6));
    });

    test('guruhlash va sonlarni guruhlash', () {
      for (final name in <String>['sorting', 'numsort']) {
        final s = SortingStart.fromJson(start(name));
        expect(s.categories.length, greaterThanOrEqualTo(2), reason: name);
        expect(s.items.length, 12, reason: name);
        final rows = responses(name).map(SortResult.fromJson).toList();
        expect(rows[1].correct, isFalse, reason: name);
        expect(s.categories.map((c) => c.id), contains(rows[1].category), reason: name);
        expect(finish(name).score, 175, reason: name);
      }
    });
  });

  group('matematika', () {
    test('matematik sprint: jami — javob berilganlar', () {
      final m = MathSprintStart.fromJson(start('mathsprint'));
      expect(m.seconds, 60);
      expect(m.level, 2);
      expect(m.problems.length, 80);
      final result = finish('mathsprint');
      expect(result.total, 3);
      expect(result.review.firstWhere((r) => r.ok == false).value, isNotEmpty);
    });

    test('ketma-ketlik: qoida javobda', () {
      final s = SequenceStart.fromJson(start('sequence'));
      expect(s.items.length, 10);
      expect(s.items.first.terms.length, inInclusiveRange(4, 7));
      final first = WordResult.fromJson(responses('sequence').first);
      expect(first.correct, isTrue);
      expect(first.explanation, isNotEmpty);
      expect(sequenceText(<int>[1, -2, 3]), '1, −2, 3, …');
      expect(finish('sequence').review.first.explanation, isNotEmpty);
    });

    test('son o\'qish', () {
      expect(parseGameNumber('12'), 12);
      expect(parseGameNumber(' −7 '), -7);
      expect(parseGameNumber('1 000'), 1000);
      expect(parseGameNumber('–3'), -3);
      expect(parseGameNumber('1.5'), isNull);
      expect(parseGameNumber(''), isNull);
      expect(parseGameNumber('abc'), isNull);
    });
  });

  test('takroriy yakun XP bermaydi, tugagan o\'yinga javob — 422', () {
    final errors = game('errors');
    expect(asMap(errors['finish_again'])['xp'], 0);
    expect(asMap(errors['answer_after_finish'])['status'], 422);
    final result = GameResult.fromJson(asMap(errors['finish_again']));
    expect(result.xpCapped, isFalse);
    expect(result.leaderboard.first.me, isTrue);
  });

  test('natija: rekord, foiz, XP izohi', () {
    final result = GameResult.fromJson(<String, dynamic>{'score': 500, 'correct': 5, 'total': 8, 'xp': 0, 'best': 500, 'details': <dynamic>[]});
    expect(result.record, isTrue);
    expect(result.percent, 63);
    expect(result.xpCapped, isTrue);
    expect(result.xpDailyLimit, isNull);
    expect(gamePercent(0, 0), 0);
  });
}
