// Xodimning bosh sahifasi (3.4, veb 1.35 «Bugun»): direktor, administrator, o'qituvchi, kassir va marketolog uchun
// bir xil tartib — salomlashish, «Bugun» kartalari (3–4 ta raqam oddiy so'zlar bilan), katta tezkor tugmalar, keyin ro'yxatlar.
import 'package:flutter/material.dart';

import '../../core/adaptive.dart';
import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/help_links.dart';
import '../../core/home_today.dart';
import '../../core/home_widgets.dart';
import '../../core/i18n.dart';
import '../../core/illustrations.dart';
import '../../core/motion.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../notifications/notifications_page.dart';
import 'attendance_page.dart';

class StaffHomePage extends StatelessWidget {
  const StaffHomePage({super.key, required this.onOpen});

  /// Bo'lim yoki yorliqni ochish (nav kaliti: `crm.debtors`, `attendance`, `payment.take` ...).
  final void Function(String key) onOpen;

  String get _today => isoDay(DateTime.now());

  /// Veb bosh sahifalari bilan bir xil manbalar (docs/design.md «Bosh sahifalar»).
  Future<Map<String, dynamic>> _load(Session session) async {
    final api = session.api;
    final crm = session.hasModule('crm');
    Future<dynamic> soft(Future<dynamic> request) => request.catchError((Object _) => null);
    switch (session.role) {
      case 'cashier':
        if (!crm) return <String, dynamic>{};
        final results = await Future.wait<dynamic>(<Future<dynamic>>[
          api.get('crm/payments', query: <String, Object?>{'from': _today, 'to': _today, 'state': 'active'}),
          api.get('crm/debtors'),
        ]);
        return <String, dynamic>{'payments': asMap(results[0]), 'debtors': asMap(results[1])};
      case 'marketer':
        if (!crm) return <String, dynamic>{};
        return <String, dynamic>{'leads': asMap(await api.get('crm/leads', query: <String, Object?>{'status': 'new', 'archived': 0}))};
    }
    if (!session.canSeeOverview) return <String, dynamic>{};
    final results = await Future.wait<dynamic>(<Future<dynamic>>[
      api.get('overview'),
      if (crm) soft(api.get('crm/timetable', query: <String, Object?>{'date': _today})),
      if (crm && session.isManager) soft(api.get('crm/dashboard')),
    ]);
    return <String, dynamic>{
      'overview': asMap(results[0]),
      'timetable': results.length > 1 ? asMap(results[1]) : <String, dynamic>{},
      'dashboard': results.length > 2 ? asMap(results[2]) : <String, dynamic>{},
    };
  }

  String _lead(Session session) {
    switch (session.role) {
      case 'teacher':
        return tr("Bugungi darslaringiz va tekshirilishi kerak bo'lgan ishlar.");
      case 'cashier':
        return tr("Bugungi to'lovlar va qarzdorlar. To'lov qabul qilish — pastdagi katta tugma.");
      case 'marketer':
        return tr("Yangi murojaatlarga tezroq javob bering — har bir qo'ng'iroq yangi o'quvchi bo'lishi mumkin.");
    }
    return tr('Bugun nima qilish kerak — birinchi: qarzdorlar, tushum, darslar va murojaatlar.');
  }

  /// Hero asosiy harakati (veb: heroAction): rahbar va kassir — to'lov qabul qilish, qolganlar — birinchi asosiy tezkor tugma.
  QuickAction? _heroAction(Session session, List<QuickAction> actions) {
    for (final action in actions) {
      if (action.primary) return action;
    }
    return null;
  }

  void _attendance(BuildContext context, Map<String, dynamic> lesson) {
    final group = asMap(lesson['group']);
    if (lesson['kind'] == 'school' || asInt(group['id']) == 0) {
      onOpen(lesson['kind'] == 'school' ? 'school.journal' : 'attendance');
      return;
    }
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => AttendanceSheetPage(groupId: asInt(group['id']), groupName: asText(group['name'])),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context);
    return Scaffold(
      appBar: pageBar(context,
        titleSpacing: 16,
        title: Row(children: <Widget>[
          OrgMark(url: session.organizationLogo, name: session.organizationName, size: 32),
          const SizedBox(width: 10),
          Expanded(child: Text(session.organizationName, maxLines: 1, overflow: TextOverflow.ellipsis)),
        ]),
        actions: <Widget>[if (session.isTeacher) const HelpButton(HelpLinks.teacherHome), const NotificationBell()],
      ),
      body: AsyncView<Map<String, dynamic>>(
        load: () => _load(session),
        cacheKey: 'staff_home_v2_${session.role}',
        decode: asMap,
        skeleton: const SkeletonList(header: true, count: 3),
        builder: (context, data, reload) {
          final lessons = asList(asMap(data['timetable'])['items'], 'items');
          final overview = asMap(data['overview']);
          final dashboard = asMap(data['dashboard']);
          List<TodayItem> cards;
          List<HeroFact> facts;
          var attention = <AttentionItem>[];
          switch (session.role) {
            case 'cashier':
              cards = data.isEmpty ? <TodayItem>[] : cashierToday(asMap(data['payments']), asMap(data['debtors']));
              facts = data.isEmpty ? <HeroFact>[] : cashierFacts(asMap(data['payments']), asMap(data['debtors']));
            case 'marketer':
              cards = data.isEmpty ? <TodayItem>[] : marketerToday(asMap(asMap(data['leads'])['counts']));
              facts = const <HeroFact>[];
            case 'teacher':
              cards = teacherToday(overview, lessons: lessons);
              facts = teacherFacts(overview, lessons: lessons);
              attention = teacherAttention(overview);
            default:
              cards = managerToday(overview, dashboard: dashboard, lessons: lessons);
              facts = managerFacts(overview, dashboard: dashboard, lessons: lessons);
              attention = managerAttention(overview, dashboard: dashboard);
          }
          final all = quickActions(session.role, session.can);
          final hero = _heroAction(session, all);
          final actions = all.where((item) => item != hero).toList();
          final payments = asList(asMap(data['payments'])['data']);
          final leads = asList(asMap(data['leads'])['data']);
          final crmMissing = (session.role == 'cashier' || session.role == 'marketer') && !session.hasModule('crm');
          final showAttention = session.role != 'cashier' && session.role != 'marketer' && data.isNotEmpty;
          var order = 0;
          Widget item(Widget child, {bool shiftOnly = false}) => IntroItem(index: order++, shiftOnly: shiftOnly, child: child);
          return IntroScope(
            id: 'home-${session.role}',
            child: CanvasPattern(
              child: ListView(
                padding: readable(context, const EdgeInsets.fromLTRB(16, 14, 16, 28), max: kGridWidth),
                children: <Widget>[
                  item(
                    HomeHeader(
                      name: session.userName,
                      lead: _lead(session),
                      facts: facts,
                      action: hero == null
                          ? null
                          : FilledButton.icon(
                              onPressed: () => onOpen(hero.key),
                              icon: Icon(navIcon(hero.icon), size: 20),
                              label: Text(hero.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                            ),
                    ),
                    shiftOnly: true,
                  ),
                  if (crmMissing && session.role == 'cashier' && session.can('p2p'))
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: AppCard(
                        onTap: () => onOpen('pay.p2p'),
                        child: Row(children: <Widget>[
                          IconTile(icon: Icons.credit_card, colors: tileOf(AppColors.brand)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                              Text(tr("Kartaga o'tkazmalar"), style: const TextStyle(fontWeight: FontWeight.w600)),
                              Text(tr("Kelgan o'tkazmalarni buyurtmalar bilan tasdiqlang."), style: TextStyle(color: AppColors.muted, fontSize: 13)),
                            ]),
                          ),
                          Icon(Icons.chevron_right, color: AppColors.subtle),
                        ]),
                      ),
                    )
                  else if (crmMissing)
                    EmptyState(
                      icon: Icons.lock_outline,
                      text: tr("Bu sahifalar CRM moduli bilan ishlaydi. Tashkilot rahbaridan modulni yoqishni so'rang."),
                    ),
                  if (cards.isNotEmpty)
                    item(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
                      SectionTitle(session.role == 'marketer' ? tr('Murojaatlar') : tr('Bugun')),
                      TodayGrid(items: cards, onOpen: onOpen),
                    ])),
                  if (lessons.isNotEmpty || showAttention)
                    item(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
                      if (lessons.isNotEmpty) ...<Widget>[
                        SectionTitle(session.isTeacher ? tr('Bugungi darslarim') : tr('Bugungi darslar')),
                        AppCard(
                          padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
                          child: LessonTimeline(
                            lessons: lessons,
                            primary: session.isTeacher,
                            onAttendance: session.can('attendance') ? (lesson) => _attendance(context, lesson) : null,
                          ),
                        ),
                      ],
                      if (showAttention) ...<Widget>[
                        SectionTitle(tr('Diqqat talab qiladi')),
                        AttentionList(items: attention, onOpen: onOpen),
                      ],
                    ])),
                  if (actions.isNotEmpty)
                    item(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
                      SectionTitle(tr('Tezkor harakatlar')),
                      ActionGrid(actions: actions, onTap: (action) => onOpen(action.key)),
                    ])),
                  if (session.role == 'cashier' && data.isNotEmpty) ...<Widget>[
                    SectionTitle(tr("Bugungi to'lovlar"), trailing: TextButton(onPressed: () => onOpen('crm.payments'), child: Text(tr('Hammasi')))),
                    if (payments.isEmpty)
                      AppCard(child: EmptyState(art: EmptyArt.wallet, text: tr("Bugun hali to'lov yo'q")))
                    else
                      AppCard(
                        padding: EdgeInsets.zero,
                        child: Column(children: <Widget>[
                          for (var i = 0; i < payments.length && i < 8; i++) ...<Widget>[
                            if (i > 0) const Divider(indent: 64),
                            ListTile(
                              leading: Avatar(asText(asMap(payments[i]['student'])['full_name']), size: 36),
                              title: Text(asText(asMap(payments[i]['student'])['full_name']), style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text(dateTime(payments[i]['paid_at'])),
                              trailing: Text(money(asInt(payments[i]['amount'])),
                                  style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.success, fontFeatures: AppTheme.tabular)),
                            ),
                          ],
                        ]),
                      ),
                  ],
                  if (session.role == 'marketer' && data.isNotEmpty) ...<Widget>[
                    SectionTitle(tr('Javob kutayotganlar'), trailing: TextButton(onPressed: () => onOpen('crm.leads'), child: Text(tr('Hammasi')))),
                    if (leads.isEmpty)
                      AppCard(child: EmptyState(art: EmptyArt.people, text: tr("Yangi murojaat yo'q")))
                    else
                      AppCard(
                        padding: EdgeInsets.zero,
                        child: Column(children: <Widget>[
                          for (var i = 0; i < leads.length && i < 8; i++) ...<Widget>[
                            if (i > 0) const Divider(indent: 64),
                            ListTile(
                              leading: Avatar(asText(leads[i]['name'], asText(leads[i]['full_name'])), size: 36),
                              title: Text(asText(leads[i]['name'], asText(leads[i]['full_name'])), style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text(<String>[asText(leads[i]['phone']), dateTime(leads[i]['created_at'])].where((item) => item.isNotEmpty).join(', ')),
                              trailing: Icon(Icons.chevron_right, color: AppColors.subtle),
                              onTap: () => onOpen('crm.leads'),
                            ),
                          ],
                        ]),
                      ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
