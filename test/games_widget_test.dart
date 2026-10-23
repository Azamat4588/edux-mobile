// O'yin ekranlari: har o'yin haqiqiy server payloadi bilan chiziladi, birinchi yurish yuboriladi
// (soxta host — fixture'dagi javoblarni qaytaradi), natija ekrani xatosiz chiziladi.
import 'dart:convert';
import 'dart:io';

import 'package:edux/core/api.dart';
import 'package:edux/core/games.dart';
import 'package:edux/features/fun/games/game_host.dart';
import 'package:edux/features/fun/games/result_view.dart';
import 'package:edux/features/fun/play_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> fixture(String name) => asMap(jsonDecode(File('test/fixtures/games/$name.json').readAsStringSync()));

class FakeGame {
  FakeGame(String name) : data = fixture(name) {
    host = GameHost(session: asMap(data['start']), send: _send, finish: _finish);
  }

  final Map<String, dynamic> data;
  late final GameHost host;
  final List<Map<String, Object?>> sent = <Map<String, Object?>>[];
  Map<String, Object?>? finished;
  int _next = 0;

  Future<Map<String, dynamic>?> _send(Map<String, Object?> body) async {
    sent.add(body);
    final answers = asList(data['answers'], 'answers');
    if (_next >= answers.length) return null;
    return asMap(answers[_next++]['response']);
  }

  Future<void> _finish([Map<String, Object?> extra = const <String, Object?>{}]) async => finished = extra;
}

Future<FakeGame> pumpGame(WidgetTester tester, String name) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final fake = FakeGame(name);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: gameBoard(name, fake.host))));
  await tester.pump();
  return fake;
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  for (final name in <String>['quiz', 'millionaire', 'survival', 'duel']) {
    testWidgets('$name: variant tanlanadi, javob yuboriladi', (tester) async {
      final fake = await pumpGame(tester, name);
      final question = GameQuestion.fromJson(asMap(asMap(fake.data['start'])[name == 'quiz' || name == 'duel' ? 'questions' : 'question'] is List
          ? asList(asMap(fake.data['start'])['questions'], 'questions').first
          : asMap(fake.data['start'])['question']));
      expect(find.byType(OptionButton), findsWidgets);
      // millionerda birinchi yozuv — 50/50; boshqalarida birinchi javob
      if (name == 'millionaire') {
        await tester.tap(find.text('50/50'));
        await tester.pump();
        expect(fake.sent.first, <String, Object?>{'action': 'fifty'});
        await settle(tester);
        return;
      }
      await tester.tap(find.byType(OptionButton).first);
      await tester.pump();
      expect(fake.sent.first['question_id'], question.id);
      await settle(tester);
    });
  }

  testWidgets("truefalse: «To'g'ri» tugmasi", (tester) async {
    final fake = await pumpGame(tester, 'truefalse');
    await tester.tap(find.byIcon(Icons.check_rounded));
    await tester.pump();
    expect(fake.sent.first, <String, Object?>{'item': 0, 'value': true});
    await settle(tester);
  });

  testWidgets('match: ikki karta ochiladi', (tester) async {
    final fake = await pumpGame(tester, 'match');
    final cards = find.byType(InkWell);
    await tester.tap(cards.at(0));
    await tester.pump();
    await tester.tap(cards.at(1));
    await tester.pump();
    expect(fake.sent.single.keys, containsAll(<String>['a', 'b']));
    await settle(tester);
  });

  testWidgets('memory: so\'z va ma\'no tanlanadi', (tester) async {
    final fake = await pumpGame(tester, 'memory');
    final start = MemoryStart.fromJson(asMap(fake.data['start']));
    await tester.tap(find.text(start.terms.first.text));
    await tester.pump();
    await tester.tap(find.text(start.definitions.first.text));
    await tester.pump();
    expect(fake.sent.single, <String, Object?>{'term': start.terms.first.id, 'definition': start.definitions.first.id});
    await settle(tester);
  });

  testWidgets('scramble: harflardan so\'z', (tester) async {
    final fake = await pumpGame(tester, 'scramble');
    final word = ScrambleStart.fromJson(asMap(fake.data['start'])).words.first;
    for (var i = 0; i < word.letters.length; i++) {
      await tester.tap(find.byType(FilledButton).at(i));
      await tester.pump();
    }
    await tester.tap(find.text('Tekshirish'));
    await tester.pump();
    expect(fake.sent.single['index'], 0);
    expect((fake.sent.single['value']! as String).length, word.letters.length);
    await settle(tester);
    expect(find.text('Keyingisi'), findsOneWidget);
  });

  testWidgets('hangman: harf yuboriladi', (tester) async {
    final fake = await pumpGame(tester, 'hangman');
    final letter = HangmanStart.fromJson(asMap(fake.data['start'])).alphabet.first;
    await tester.tap(find.text(letter).first);
    await tester.pump();
    expect(fake.sent.single, <String, Object?>{'index': 0, 'letter': letter});
    await settle(tester);
  });

  testWidgets('typing: yozib tekshirish', (tester) async {
    final fake = await pumpGame(tester, 'typing');
    await tester.enterText(find.byType(TextField), 'brauzer');
    await tester.tap(find.text('Tekshirish'));
    await tester.pump();
    expect(fake.sent.single, <String, Object?>{'index': 0, 'value': 'brauzer'});
    await settle(tester);
  });

  testWidgets('flashcards: bilaman', (tester) async {
    final fake = await pumpGame(tester, 'flashcards');
    await tester.tap(find.text('Bilaman'));
    await tester.pump();
    expect(fake.sent.single, <String, Object?>{'id': 0, 'known': true});
    await settle(tester);
  });

  for (final name in <String>['sorting', 'numsort']) {
    testWidgets('$name: toifa tanlanadi', (tester) async {
      final fake = await pumpGame(tester, name);
      await tester.tap(find.byType(OptionButton).first);
      await tester.pump();
      expect(fake.sent.single['item'], 0);
      await settle(tester);
    });
  }

  testWidgets('crossword: katak, harf, yakunda javoblar', (tester) async {
    final fake = await pumpGame(tester, 'crossword');
    final start = CrosswordStart.fromJson(asMap(fake.data['start']));
    expect(fake.host.timeoutPayload, isNotNull);
    await tester.enterText(find.byType(TextField), '​AB');
    await tester.pump();
    final answers = asRawList(fake.host.timeoutPayload!()['answers']);
    expect(answers.length, start.entries.length);
    expect(answers.first, 'AB');
    await tester.scrollUntilVisible(find.text('Yakunlash va tekshirish'), 300);
    await tester.tap(find.text('Yakunlash va tekshirish'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yakunlash').last);
    await tester.pumpAndSettle();
    expect(asRawList(fake.finished!['answers']).first, 'AB');
  });

  testWidgets('mathsprint: raqam klaviaturasi', (tester) async {
    final fake = await pumpGame(tester, 'mathsprint');
    await tester.tap(find.widgetWithText(OutlinedButton, '1'));
    await tester.tap(find.widgetWithText(OutlinedButton, '2'));
    await tester.pump();
    await tester.tap(find.text('Javob berish'));
    await tester.pump();
    expect(fake.sent.single, <String, Object?>{'id': 0, 'value': '12'});
    await settle(tester);
  });

  testWidgets('sequence: javob va qoida', (tester) async {
    final fake = await pumpGame(tester, 'sequence');
    await tester.tap(find.widgetWithText(OutlinedButton, '3'));
    await tester.pump();
    await tester.tap(find.text('Javob berish'));
    await tester.pump();
    expect(fake.sent.single, <String, Object?>{'id': 0, 'value': '3'});
    await settle(tester);
    expect(find.text('Keyingisi'), findsOneWidget);
  });

  for (final name in gameSources.keys) {
    testWidgets('$name: natija ekrani', (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      var again = 0;
      final result = GameResult.fromJson(asMap(fixture(name)['finish']));
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: GameResultView(result: result, onAgain: () => again++))));
      expect(find.text('${result.score}'), findsWidgets);
      await tester.tap(find.text("Yana o'ynash"));
      expect(again, 1);
      if (result.duel != null) expect(find.textContaining(result.duel!.opponent), findsWidgets);
    });
  }
}
