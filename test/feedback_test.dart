// 1.39 mijozlar fikri: kontekst bloki, meta, yuborish maydonlari, panel so'rovi, push yo'nalishi va ekranlar.
// Fixture'lar — demo serverdan (backend 1.39) olingan haqiqiy javoblar (test/fixtures/feedback_*.json).
import 'dart:convert';
import 'dart:io';

import 'package:edux/core/api.dart';
import 'package:edux/core/feedback.dart';
import 'package:edux/core/nav.dart';
import 'package:edux/core/push.dart';
import 'package:edux/core/session.dart';
import 'package:edux/core/support.dart';
import 'package:edux/features/feedback/feedback_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> fixture(String name) => asMap(jsonDecode(File('test/fixtures/$name.json').readAsStringSync()));

/// Soxta server: GET — fixture, PATCH/POST — yozib olinadi.
Session sessionFor(String role, List<http.Request> sent) {
  final session = Session(client: MockClient((request) async {
    sent.add(request);
    final path = request.url.path.replaceFirst(RegExp(r'^/api/v1/'), '');
    Object? body;
    if (request.method == 'GET' && path == 'feedback') body = fixture('feedback_admin_list');
    if (request.method == 'GET' && RegExp(r'^feedback/\d+$').hasMatch(path)) body = fixture('feedback_admin_show');
    if (request.method == 'PATCH' && RegExp(r'^feedback/\d+$').hasMatch(path)) body = fixture('feedback_admin_show');
    if (request.method == 'POST' && RegExp(r'^feedback/\d+/(reply|notes)$').hasMatch(path)) body = <String, dynamic>{'ok': true};
    if (request.method == 'GET' && path == 'feedback/meta') body = fixture('feedback_meta');
    if (request.method == 'GET' && path == 'my/feedback') body = fixture('feedback_mine');
    if (request.method == 'POST' && path == 'feedback') {
      body = <String, dynamic>{'id': 7, 'token': 'x' * 40, 'message': "Fikringiz markaz rahbariyatiga yuborildi. Javob shu yerda ko'rinadi."};
      return http.Response(jsonEncode(body), 201, headers: <String, String>{'content-type': 'application/json; charset=utf-8'});
    }
    if (body == null) return http.Response('{"message":"topilmadi"}', 404);
    return http.Response.bytes(utf8.encode(jsonEncode(body)), 200, headers: <String, String>{'content-type': 'application/json; charset=utf-8'});
  }));
  session.debugSignIn(
    server: 'https://edux.test',
    token: 'demo',
    user: <String, dynamic>{'id': 1, 'name': 'Demo'},
    memberships: <Membership>[Membership(1, 'Ilm yo\'li', role)],
    organizationId: 1,
    context: fixture(role == 'director' ? 'feedback_director_context' : 'feedback_guardian_context'),
  );
  return session;
}

Future<void> pumpPage(WidgetTester tester, Session session, Widget page, {Size size = const Size(430, 932)}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(AppScope(session: session, child: MaterialApp(home: page)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  test('kontekst bloki: panel va yuborish', () {
    final director = feedbackFlags(fixture('feedback_director_context'));
    expect(director.enabled, isTrue);
    expect(director.manage, isTrue);
    expect(director.submit, isTrue);
    expect(director.fresh, 3);
    expect(feedbackNewCount(fixture('feedback_director_context')), 3);
    final guardian = feedbackFlags(fixture('feedback_guardian_context'));
    expect(guardian.submit, isTrue);
    expect(guardian.manage, isFalse);
    expect(feedbackNewCount(fixture('feedback_guardian_context')), 0);
    // Eski server (1.38): blok yo'q — hammasi o'chiq; o'chirilgan sozlama — yuborish yo'q.
    expect(feedbackFlags(<String, dynamic>{}).submit, isFalse);
    expect(feedbackFlags(<String, dynamic>{'feedback': <String, dynamic>{'enabled': false, 'submit': true, 'manage': true}}).submit, isFalse);
  });

  test('menyu: «Aloqa → Fikrlar» rahbarda, boshqa xodimda alohida bo\'lim', () {
    final manager = buildNav(NavContext(role: 'director', can: <String>{'feedback_manage', 'callcenter'}.contains));
    expect(sectionOfTab(manager, 'feedback')?.key, 'comms');
    final teacher = buildNav(NavContext(role: 'teacher', can: <String>{'feedback_manage', 'students'}.contains));
    expect(sectionOfTab(teacher, 'feedback')?.key, 'feedback');
    final cashier = buildNav(NavContext(role: 'cashier', can: <String>{'crm'}.contains));
    expect(sectionOfTab(cashier, 'feedback'), isNull);
  });

  test('meta: turlar, yo\'nalishlar, kimga tegishli, rasm cheklovi', () {
    final meta = fixture('feedback_meta');
    final kinds = feedbackLabels(meta, 'kinds', feedbackKindLabels);
    expect(kinds.keys, containsAll(<String>['complaint', 'suggestion', 'bug', 'thanks', 'question']));
    expect(feedbackLabels(<String, dynamic>{}, 'kinds', feedbackKindLabels), feedbackKindLabels);
    final targets = FeedbackTargets.fromMeta(meta);
    expect(targets.students, isNotEmpty);
    expect(targets.groups, isNotEmpty);
    final group = targets.groups.first;
    expect(targets.teacherOfGroup(asInt(group['id'])), asInt(group['teacher_id']));
    expect(targets.teacherOfGroup(-1), 0);
    final rules = SupportAttachmentRules.fromMeta(meta);
    expect(rules.allowed, isTrue);
    expect(rules.maxFiles, 3);
    // Server standart yo'nalishlari ilova lug'atidagi ro'yxat bilan bir xil.
    expect(asRawList(meta['categories']).map((item) => '$item'), feedbackCategoryLabels);
  });

  test("yuborish maydonlari: bo'sh qiymatlar tushadi, guruh tanlansa o'qituvchi yuborilmaydi", () {
    final payload = feedbackPayload(
      kind: 'complaint',
      body: '  Kassada chek berilmadi  ',
      category: "To'lov",
      rating: 2,
      anonymous: true,
      studentId: 12,
      groupId: 2,
      teacherId: 4,
      context: const <String, String>{'app': 'ios', 'app_version': '3.7.0'},
    );
    expect(payload['body'], 'Kassada chek berilmadi');
    expect(payload['study_group_id'], 2);
    expect(payload.containsKey('teacher_id'), isFalse);
    expect(payload['anonymous'], isTrue);
    final minimal = feedbackPayload(kind: 'thanks', body: 'Rahmat katta!', rating: 9, teacherId: 4);
    expect(minimal.keys, unorderedEquals(<String>['kind', 'body', 'teacher_id']));
    final fields = supportFields(feedbackMultipartPayload(payload));
    expect(fields['anonymous'], '1');
    expect(fields['context[app]'], 'ios');
    expect(fields['rating'], '2');
    expect(feedbackBodyError('abc'), isNotNull);
    expect(feedbackBodyError('Yaxshi dars'), isNull);
    expect(feedbackBodyError('a' * 3001), isNotNull);
  });

  test("panel so'rovi va qatorlar", () {
    expect(feedbackListQuery(), isEmpty);
    expect(feedbackListQuery(status: 'overdue', kind: 'bug', mine: true, search: ' #31 ', page: 2),
        <String, Object?>{'status': 'overdue', 'kind': 'bug', 'assigned': 'me', 'q': '#31', 'page': 2});
    final items = asList(fixture('feedback_admin_list'));
    final anonymous = items.firstWhere((item) => item['is_anonymous'] == true);
    expect(feedbackAuthorLine(anonymous, anonymousLabel: 'Anonim'), 'Anonim');
    final named = items.firstWhere((item) => item['is_anonymous'] == false && item['author'] != null);
    expect(feedbackAuthorLine(named, anonymousLabel: 'Anonim'), contains(asText(asMap(named['author'])['name'])));
    final show = fixture('feedback_admin_show');
    expect(feedbackAboutLine(show), contains(asText(asMap(show['group'])['name'])));
    // Muallif javobida guruh va o'qituvchi — matn.
    expect(feedbackAboutLine(<String, dynamic>{'group': 'ING-5', 'teacher': 'Usmonova Dildora'}), 'ING-5 · Usmonova Dildora');
    expect(feedbackStatusTone('new'), 'warning');
    expect(feedbackClosed('resolved'), isTrue);
    expect(feedbackClosed('in_progress'), isFalse);
  });

  test('push: feedback.show → panel, feedback.mine → mening fikrlarim', () {
    final admin = PushService.normalize(<String, dynamic>{'route': 'feedback.show', 'link': '/feedback/31', 'feedback_id': '31'});
    expect(admin['type'], 'feedback');
    expect(asInt(admin['feedback_id']), 31);
    final reply = PushService.normalize(<String, dynamic>{'route': 'feedback.mine', 'link': '/my/feedback?id=31'});
    expect(reply['type'], 'feedback_reply');
    expect(asInt(reply['feedback_id']), 31);
    // Eski ko'rinish: faqat type va havola.
    expect(PushService.normalize(<String, dynamic>{'type': 'feedback_reply', 'feedback_id': 5})['type'], 'feedback_reply');
    expect(PushService.normalize(<String, dynamic>{'link': 'https://edux.uz/feedback/12'})['feedback_id'], '12');
    expect(feedbackIdFromLink('/my/feedback?id=7'), 7);
    expect(feedbackIdFromLink('/feedback/31'), 31);
    expect(feedbackIdFromLink('/feedback'), 0);
  });

  testWidgets('«Fikr bildirish»: turlar, qisqa matn xatosi, yuborilgach «Mening fikrlarim»', (tester) async {
    final sent = <http.Request>[];
    final session = sessionFor('guardian', sent);
    await pumpPage(tester, session, const MyFeedbackPage(), size: const Size(430, 1600));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Shikoyat'), findsWidgets);
    expect(find.text('Minnatdorchilik'), findsOneWidget);
    expect(find.text('Anonim yuborish'), findsOneWidget);
    await tester.tap(find.text('Minnatdorchilik'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, 'abc');
    await tester.ensureVisible(find.text('Yuborish'));
    await tester.tap(find.text('Yuborish'));
    await tester.pump();
    expect(find.text('Fikringizni batafsilroq yozing (kamida 5 belgi).'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, "Ustozga katta rahmat, farzandim darsni yaxshi ko'radi.");
    await tester.ensureVisible(find.text('Yuborish'));
    await tester.tap(find.text('Yuborish'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    final post = sent.lastWhere((request) => request.method == 'POST');
    final body = asMap(jsonDecode(post.body));
    expect(body['kind'], 'thanks');
    expect(body['student_id'], 1); // yagona farzand oldindan tanlangan
    expect(asMap(body['context'])['page'], 'feedback');
    // «Mening fikrlarim» ochildi: serverdagi 4 ta fikr, markaz javobi bilan.
    expect(find.text('1 ta javob'), findsWidgets);
  });

  testWidgets("rahbar paneli: ro'yxat, filtr va tafsilotda javob", (tester) async {
    final sent = <http.Request>[];
    final session = sessionFor('director', sent);
    await pumpPage(tester, session, const FeedbackAdminPage(), size: const Size(430, 1600));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(FeedbackAdminTile), findsWidgets);
    expect(find.text('Anonim'), findsWidgets);
    await tester.tap(find.text('Yangi (3)'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(sent.last.url.queryParameters['status'], 'new');
    await tester.tap(find.byType(FeedbackAdminTile).first);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('Tarix'), findsOneWidget);
    expect(find.text("Mas'ul tayinlandi"), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'Muammo hal qilindi, rahmat!');
    await tester.tap(find.byTooltip('Yuborish'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final reply = sent.lastWhere((request) => request.method == 'POST');
    expect(reply.url.path, endsWith('/reply'));
    expect(asMap(jsonDecode(reply.body))['body'], 'Muammo hal qilindi, rahmat!');
  });
}
