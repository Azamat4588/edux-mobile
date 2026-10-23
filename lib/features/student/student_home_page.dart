// O'quvchining bosh sahifasi: balans va to'lov, yaqin darslar, test natijalari, maktab baholari, coinlar.
import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/home_today.dart';
import '../../core/home_widgets.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../fun/games_page.dart';
import '../notifications/notifications_page.dart';
import '../olympiad/olympiads_page.dart';
import '../tutor/tutor_page.dart';
import 'online_pay.dart';

class StudentHomePage extends StatelessWidget {
  const StudentHomePage({super.key, this.onOpen});

  /// Bo'lim ochish (nav kaliti: `my`, `lms.my.courses`, `pay` ...). Berilmasa — tezkor tugmalar yashiriladi.
  final void Function(String key)? onOpen;

  Future<Map<String, dynamic>> _load(Session session) async {
    final results = await Future.wait<dynamic>(<Future<dynamic>>[
      session.api.get('my/insights'),
      if (session.hasModule('crm')) session.api.get('crm/me').catchError((_) => null),
    ]);
    return <String, dynamic>{'insights': asMap(results[0]), 'crm': results.length > 1 ? asMap(results[1]) : <String, dynamic>{}};
  }

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(session.organizationName), actions: const <Widget>[NotificationBell()]),
      body: AsyncView<Map<String, dynamic>>(
        load: () => _load(session),
        cacheKey: 'student_home',
        decode: asMap,
        skeleton: const SkeletonList(header: true, count: 3),
        builder: (context, data, reload) {
          // 3.4 (veb 1.35 StudentToday): «Bugun» kartalari va tezkor harakatlar — birinchi.
          final insights = asMap(data['insights']);
          final crm = asMap(data['crm']);
          final upcoming = asList(crm['upcoming'], 'upcoming');
          final cards = session.isGuest ? <TodayItem>[] : studentToday(insights, upcoming: upcoming);
          final balance = asInt(crm['balance'] ?? asMap(insights['crm'])['balance']);
          final actions = session.isGuest || onOpen == null
              ? <QuickAction>[]
              : quickActions('student', session.can, debt: balance < 0, pendingTests: asList(asMap(insights['testing'])['pending'], 'pending').length);
          return ListView(children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
                HomeHeader(name: asText(asMap(insights['student'])['full_name'], session.userName), lead: tr('Bugun nima qilish kerak: testlar, uy vazifalari va to\'lov.')),
                if (cards.isNotEmpty) ...<Widget>[
                  SectionTitle(tr('Bugun')),
                  TodayGrid(items: cards, onOpen: onOpen),
                ],
                if (actions.isNotEmpty) ...<Widget>[
                  SectionTitle(tr('Tezkor harakatlar')),
                  ActionGrid(actions: actions, onTap: (action) => onOpen!(action.key)),
                ],
              ]),
            ),
            StudentOverviewBody(insights: insights, crm: crm, onPaid: reload, showGreeting: false, showIdentity: false),
            const _QuickActions(),
          ]);
        },
      ),
    );
  }
}

/// O'quvchi haqida umumiy ko'rinish (o'quvchi va ota-ona sahifalarida) — ro'yxat ichiga qo'yiladi.
class StudentOverviewBody extends StatelessWidget {
  const StudentOverviewBody({super.key, required this.insights, required this.crm, this.studentId, this.showGreeting = true, this.showIdentity = true, this.onPaid});

  /// Ism va kod bloki (ota-ona sahifasida); bosh sahifada sarlavha alohida (HomeHeader).
  final bool showIdentity;

  final Map<String, dynamic> insights;
  final Map<String, dynamic> crm;
  final int? studentId;
  final bool showGreeting;

  /// To'lov oynasi yopilgach (balansni yangilash uchun).
  final VoidCallback? onPaid;

  @override
  Widget build(BuildContext context) {
    final student = asMap(insights['student']);
    final testing = asMap(insights['testing']);
    final school = asMap(insights['school']);
    final lmsData = asMap(insights['lms']);
    final crmInsights = asMap(insights['crm']);
    final upcoming = asList(crm['upcoming'], 'upcoming');
    final hasBalance = crm['balance'] != null || crmInsights['balance'] != null;
    final balance = asInt(crm['balance'] ?? crmInsights['balance']);
    final attempts = asList(testing['attempts'], 'attempts');
    final subjects = asList(school['subjects'], 'subjects');
    final absence = asMap(school['absence_totals']);
    final name = asText(student['full_name']);
    final firstName = name.split(' ').length > 1 ? name.split(' ')[1] : name;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        if (!showGreeting && showIdentity && name.isNotEmpty) ...<Widget>[
          Row(children: <Widget>[
            Avatar(name, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text(name, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                if (student['code'] != null)
                  Text('${tr("O'quvchi kodi")}: ${asText(student['code'])}', style: TextStyle(color: AppColors.muted)),
              ]),
            ),
          ]),
          const SizedBox(height: 14),
        ],
        if (showGreeting) ...<Widget>[
          Text(tr('Assalomu alaykum, {0}', <Object?>[firstName]),
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.ink)),
          const SizedBox(height: 4),
          Text(<String>[
            if (student['code'] != null) '${tr("O'quvchi kodi")}: ${asText(student['code'])}',
            dayTitle(DateTime.now()),
          ].join(' · '), style: TextStyle(color: AppColors.muted)),
          const SizedBox(height: 14),
        ],
        if (hasBalance)
          AppCard(
            color: balance < 0 ? AppColors.soft(AppColors.danger) : AppColors.card,
            child: Row(children: <Widget>[
              Icon(Icons.account_balance_wallet_outlined, color: balance < 0 ? AppColors.danger : AppColors.success, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  Text(balance < 0 ? tr('Qarz') : tr('Balans'), style: TextStyle(color: AppColors.muted)),
                  Text(money(balance.abs()),
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: balance < 0 ? AppColors.danger : AppColors.ink)),
                ]),
              ),
              FilledButton.tonal(
                onPressed: () => startOnlinePayment(
                  context,
                  studentId: studentId,
                  suggested: balance < 0 ? -balance : 0,
                  onDone: (_) => onPaid?.call(),
                ),
                child: Text(tr("To'lash")),
              ),
            ]),
          ),
        if (upcoming.isNotEmpty) ...<Widget>[
          SectionTitle(tr('Yaqin darslar')),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(children: <Widget>[
              for (var i = 0; i < upcoming.length && i < 5; i++) ...<Widget>[
                if (i > 0) const Divider(),
                ListTile(
                  leading: Icon(Icons.event_outlined, color: AppColors.brand),
                  title: Text('${dayTitle(parseDate(upcoming[i]['date']) ?? DateTime.now())}, ${asText(upcoming[i]['start'])}'),
                  subtitle: Text(<String>[asText(upcoming[i]['group']), if (upcoming[i]['room'] != null) asText(upcoming[i]['room'])].join(' · ')),
                ),
              ],
            ]),
          ),
        ],
        if (testing.isNotEmpty) ...<Widget>[
          SectionTitle(tr('Test natijalari')),
          StatGrid(children: <Widget>[
            StatCard(label: tr('Topshirilgan testlar'), value: '${asInt(testing['count'])}', icon: Icons.quiz_outlined),
            StatCard(
              label: tr("O'rtacha natija"),
              value: percent(asNumOrNull(testing['average_percent'])),
              icon: Icons.insights_outlined,
              color: AppColors.success,
            ),
          ]),
          for (final attempt in attempts.take(5)) ...<Widget>[
            AppCard(
              child: Row(children: <Widget>[
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                    Text(asText(attempt['exam']), style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(date(attempt['finished_at']), style: TextStyle(color: AppColors.muted, fontSize: 13)),
                  ]),
                ),
                Text('${asInt(attempt['correct'])}/${asInt(attempt['total'])}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ]),
            ),
            const SizedBox(height: 8),
          ],
        ],
        if (subjects.isNotEmpty) ...<Widget>[
          SectionTitle(<String>[tr('Fanlar bo\'yicha baholar'), if (asMap(school['current_term'])['name'] != null) asText(asMap(school['current_term'])['name'])].join(' · ')),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(children: <Widget>[
              for (var i = 0; i < subjects.length; i++) ...<Widget>[
                if (i > 0) const Divider(),
                ListTile(
                  title: Text(asText(subjects[i]['name'])),
                  subtitle: Text(tr('{0} ta baho', <Object?>[asInt(subjects[i]['current_marks'])])),
                  trailing: _MarkBadge(value: asNumOrNull(subjects[i]['current_average'])),
                ),
              ],
            ]),
          ),
          if (absence.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            AppCard(
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: <Widget>[
                _Count(tr('Kelmadi'), asInt(absence['absent']), AppColors.danger),
                _Count(tr('Sababli'), asInt(absence['excused']), AppColors.muted),
                _Count(tr('Kechikdi'), asInt(absence['late']), AppColors.warning),
              ]),
            ),
          ],
        ],
        if (asList(lmsData['courses'], 'courses').isNotEmpty) ...<Widget>[
          SectionTitle(tr('Kurslar')),
          for (final course in asList(lmsData['courses'], 'courses')) ...<Widget>[
            AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text(asText(course['title']), style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(value: asDouble(course['percent']) / 100, minHeight: 8),
                ),
                const SizedBox(height: 4),
                Text('${asInt(course['done'])} / ${asInt(course['total'])} ${tr('dars')}', style: TextStyle(color: AppColors.muted, fontSize: 12)),
              ]),
            ),
            const SizedBox(height: 8),
          ],
        ],
        // Coin CRM sozlamasida o'chirilgan bo'lsa (context.coins_enabled = false) — ko'rsatilmaydi (veb bilan bir xil).
        if (AppScope.of(context).coinsEnabled && (crm['coins'] != null || crmInsights['coins'] != null)) ...<Widget>[
          const SizedBox(height: 8),
          AppCard(
            child: Row(children: <Widget>[
              const Icon(Icons.stars_rounded, color: AppColors.sun, size: 30),
              const SizedBox(width: 12),
              Expanded(child: Text(tr('Coin'), style: const TextStyle(fontWeight: FontWeight.w600))),
              Text('${asInt(crm['coins'] ?? crmInsights['coins'])}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            ]),
          ),
        ],
      ]),
    );
  }
}

/// Tashkilotda yoqilgan qo'shimcha bo'limlarga tezkor o'tish (olimpiada, AI ustoz, o'yinlar).
class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context);
    if (session.isGuest) return const SizedBox();
    final fun = session.hasFeature('fun');
    final actions = <Widget>[
      if (session.hasModule('testing') && session.hasFeature('olympiad'))
        _QuickAction(icon: Icons.emoji_events_rounded, label: tr('Olimpiadalarim'), color: AppColors.sun, page: const OlympiadsPage()),
      if (session.canUseTutor)
        _QuickAction(icon: Icons.auto_awesome_rounded, label: tr('AI ustoz'), color: const Color(0xFF7C3AED), page: const TutorPage()),
      if (fun) _QuickAction(icon: Icons.sports_esports_rounded, label: tr("O'yinlar"), color: AppColors.success, page: const GamesPage()),
    ];
    if (actions.isEmpty) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Row(children: <Widget>[
        for (var i = 0; i < actions.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: actions[i]),
        ],
      ]),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.label, required this.color, required this.page});

  final IconData icon;
  final String label;
  final Color color;
  final Widget page;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page)),
      child: Column(children: <Widget>[
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: color.withAlpha(36), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: color),
        ),
        const SizedBox(height: 8),
        Text(label, textAlign: TextAlign.center, maxLines: 2, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
      ]),
    );
  }
}

class _MarkBadge extends StatelessWidget {
  const _MarkBadge({required this.value});

  final num? value;

  @override
  Widget build(BuildContext context) {
    if (value == null) return Text('—', style: TextStyle(color: AppColors.muted));
    final v = value!.toDouble();
    final color = v >= 4.5 ? AppColors.success : (v >= 3.5 ? AppColors.brand : (v >= 3 ? AppColors.warning : AppColors.danger));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withAlpha(28), borderRadius: BorderRadius.circular(10)),
      child: Text(number(v, decimals: 2), style: TextStyle(fontWeight: FontWeight.w800, color: color)),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count(this.label, this.value, this.color);

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(children: <Widget>[
      Text('$value', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
      Text(label, style: TextStyle(color: AppColors.muted, fontSize: 12)),
    ]);
  }
}
