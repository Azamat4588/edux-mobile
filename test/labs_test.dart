// 1.39 laboratoriyalar katalogi: 462 lab, 15 fan, darslik mavzulari (fixture — demo serverdan: GET my/labs, fun/labs/topics).
import 'dart:convert';
import 'dart:io';

import 'package:edux/core/api.dart';
import 'package:edux/core/labs.dart';
import 'package:edux/features/fun/labs_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

List<Map<String, dynamic>> labs() => asList(asMap(jsonDecode(File('test/fixtures/labs_my.json').readAsStringSync()))['labs'], 'labs');

Map<String, dynamic> physicsTree() => asMap(jsonDecode(File('test/fixtures/labs_topics_fizika.json').readAsStringSync()));

void main() {
  test('katalog: 462 lab, 15 fan (yangi gumanitar fanlar bilan)', () {
    final all = labs();
    expect(all.length, greaterThanOrEqualTo(462));
    final subjects = labSubjects(all);
    expect(subjects.length, greaterThanOrEqualTo(15));
    expect(subjects, containsAll(<String>['Tarix', 'Ona tili', 'Ingliz tili', 'Texnologiya', 'Chizmachilik', 'Iqtisodiyot', 'Musiqa', "Tasviriy san'at"]));
    // Har fanning o'z ikonkasi bor (umumiy «chaqmoq» faqat Fizikada).
    for (final subject in subjects.where((item) => item != 'Fizika')) {
      expect(labIcon(subject), isNot(Icons.bolt_rounded), reason: subject);
    }
    expect(labSubjectLabel(all.first), isNotEmpty);
  });

  test("sinf bo'yicha guruhlar kichikdan kattaga", () {
    final physics = labs().where((lab) => lab['subject'] == 'Fizika').toList();
    final groups = labsByGrade(physics);
    final firsts = groups.keys.map(labFirstGrade).toList();
    final sorted = List<int>.from(firsts)..sort();
    expect(firsts, sorted);
    expect(groups.values.fold<int>(0, (sum, list) => sum + list.length), physics.length);
    expect(labFirstGrade('7–9'), 7);
    expect(labFirstGrade('10'), 10);
    expect(labFirstGrade(''), 99);
  });

  test('qidiruv: nom, darslik mavzusi va bir nechta so\'z', () {
    final all = labs();
    final byName = all.where((lab) => labMatches(lab, 'mayatnik')).toList();
    expect(byName.map((lab) => lab['code']), contains('pendulum'));
    // Darslik mavzusi bo'yicha (nomida yo'q so'z).
    final pendulum = all.firstWhere((lab) => lab['code'] == 'pendulum');
    final topic = asText(asList(pendulum['topics'], 'topics').first['topic']);
    expect(labMatches(pendulum, topic.split(' ').last), isTrue);
    expect(labMatches(pendulum, 'mayatnik  tebranish'), isTrue);
    expect(labMatches(pendulum, 'mayatnik molekula'), isFalse);
    expect(labMatches(pendulum, '   '), isTrue);
    expect(labTopicLine(pendulum), contains(asText(asList(pendulum['topics'], 'topics').first['book'])));
  });

  test('darslik daraxti: sinflar va mavzudagi lablar', () {
    final tree = physicsTree();
    final grades = textbookGrades(tree);
    expect(grades, isNotEmpty);
    expect(grades, List<int>.from(grades)..sort());
    final byCode = <String, Map<String, dynamic>>{for (final lab in labs()) asText(lab['code']): lab};
    final chapter = asList(asList(tree['books'], 'books').first['chapters'], 'chapters').first;
    final topic = asList(chapter['topics'], 'topics').first;
    expect(topicLabs(topic, byCode), isNotEmpty);
    expect(topicLabs(<String, dynamic>{'labs': <String>['yoq_lab']}, byCode), isEmpty);
    expect(chapterLabCount(chapter), greaterThan(0));
  });

  testWidgets("«Fanlar bo'yicha»: fan tanlanadi, sinf guruhlari, qidiruv", (tester) async {
    tester.view.physicalSize = const Size(1024, 1366) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: LabsCatalogView(labs: labs(), onChanged: () async {}))));
    await tester.pump();
    expect(find.byType(LabCard), findsWidgets);
    expect(find.textContaining('Hammasi ('), findsWidgets); // fan bo'limida «Hammasi (N)» tugmasi (6 tadan ko'p)
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: LabsCatalogView(key: const ValueKey<String>('tarix'), labs: labs(), onChanged: () async {}, initialSubject: 'Tarix'))));
    await tester.pump();
    expect(find.textContaining('-sinf'), findsWidgets);
    await tester.enterText(find.byType(TextField), 'mayatnik');
    await tester.pump();
    expect(find.textContaining('Topildi'), findsOneWidget);
  });

  testWidgets("«Darslik bo'yicha»: bob va mavzular, lab tugmalari", (tester) async {
    tester.view.physicalSize = const Size(1024, 1366) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: LabsTextbookView(labs: labs(), onChanged: () async {}, initialSubject: 'Fizika', tree: physicsTree())),
    ));
    await tester.pump();
    expect(find.byType(ExpansionTile), findsWidgets);
    expect(find.textContaining('Fizika'), findsWidgets);
  });
}
