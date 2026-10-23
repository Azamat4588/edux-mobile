// Xodimning bosh sahifasi (3.4, veb 1.35 «Bugun»): direktor, administrator, o'qituvchi, kassir va marketolog uchun
// bir xil tartib — salomlashish, «Bugun» kartalari (3–4 ta raqam oddiy so'zlar bilan), katta tezkor tugmalar, keyin ro'yxatlar.
import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/home_today.dart';
import '../../core/home_widgets.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../notifications/notifications_page.dart';

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

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(children: <Widget>[
          _OrgLogo(url: session.organizationLogo, name: session.organizationName),
          const SizedBox(width: 10),
          Expanded(child: Text(session.organizationName, maxLines: 1, overflow: TextOverflow.ellipsis)),
        ]),
        actions: const <Widget>[NotificationBell()],
      ),
      body: AsyncView<Map<String, dynamic>>(
        load: () => _load(session),
        cacheKey: 'staff_home_v2_${session.role}',
        decode: asMap,
        skeleton: const SkeletonList(header: true, count: 3),
        builder: (context, data, reload) {
          final lessons = asList(asMap(data['timetable'])['items'], 'items');
          final overview = asMap(data['overview']);
          List<TodayItem> cards;
          switch (session.role) {
            case 'cashier':
              cards = data.isEmpty ? <TodayItem>[] : cashierToday(asMap(data['payments']), asMap(data['debtors']));
            case 'marketer':
              cards = data.isEmpty ? <TodayItem>[] : marketerToday(asMap(asMap(data['leads'])['counts']));
            case 'teacher':
              cards = teacherToday(overview, lessons: lessons);
            default:
              cards = managerToday(overview, dashboard: asMap(data['dashboard']), lessons: lessons);
          }
          final actions = quickActions(session.role, session.can);
          final payments = asList(asMap(data['payments'])['data']);
          final leads = asList(asMap(data['leads'])['data']);
          final crmMissing = (session.role == 'cashier' || session.role == 'marketer') && !session.hasModule('crm');
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: <Widget>[
              HomeHeader(name: session.userName, lead: _lead(session)),
              if (crmMissing && session.role == 'cashier' && session.can('p2p'))
                AppCard(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.credit_card),
                    title: Text(tr("Kartaga o'tkazmalar")),
                    subtitle: Text(tr("Kelgan o'tkazmalarni buyurtmalar bilan tasdiqlang.")),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => onOpen('pay.p2p'),
                  ),
                )
              else if (crmMissing)
                EmptyState(
                  icon: Icons.lock_outline,
                  text: tr("Bu sahifalar CRM moduli bilan ishlaydi. Tashkilot rahbaridan modulni yoqishni so'rang."),
                ),
              if (cards.isNotEmpty) ...<Widget>[
                SectionTitle(session.role == 'marketer' ? tr('Murojaatlar') : tr('Bugun')),
                TodayGrid(items: cards, onOpen: onOpen),
              ],
              if (actions.isNotEmpty) ...<Widget>[
                SectionTitle(tr('Tezkor harakatlar')),
                ActionGrid(actions: actions, onTap: (action) => onOpen(action.key)),
              ],
              if (lessons.isNotEmpty) ...<Widget>[
                SectionTitle(tr('Bugungi darslar')),
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(children: <Widget>[
                    for (var i = 0; i < lessons.length; i++) ...<Widget>[
                      if (i > 0) const Divider(),
                      _LessonRow(lesson: lessons[i]),
                    ],
                  ]),
                ),
              ],
              if (session.role == 'cashier' && data.isNotEmpty) ...<Widget>[
                SectionTitle(tr("Bugungi to'lovlar"), trailing: TextButton(onPressed: () => onOpen('crm.payments'), child: Text(tr('Hammasi')))),
                if (payments.isEmpty)
                  AppCard(child: Text(tr("Bugun hali to'lov yo'q"), style: TextStyle(color: AppColors.muted)))
                else
                  AppCard(
                    padding: EdgeInsets.zero,
                    child: Column(children: <Widget>[
                      for (var i = 0; i < payments.length && i < 8; i++) ...<Widget>[
                        if (i > 0) const Divider(),
                        ListTile(
                          dense: true,
                          title: Text(asText(asMap(payments[i]['student'])['full_name']), style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(dateTime(payments[i]['paid_at'])),
                          trailing: Text(money(asInt(payments[i]['amount'])), style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.success)),
                        ),
                      ],
                    ]),
                  ),
              ],
              if (session.role == 'marketer' && data.isNotEmpty) ...<Widget>[
                SectionTitle(tr('Javob kutayotganlar'), trailing: TextButton(onPressed: () => onOpen('crm.leads'), child: Text(tr('Hammasi')))),
                if (leads.isEmpty)
                  AppCard(child: Text(tr("Yangi murojaat yo'q"), style: TextStyle(color: AppColors.muted)))
                else
                  AppCard(
                    padding: EdgeInsets.zero,
                    child: Column(children: <Widget>[
                      for (var i = 0; i < leads.length && i < 8; i++) ...<Widget>[
                        if (i > 0) const Divider(),
                        ListTile(
                          dense: true,
                          title: Text(asText(leads[i]['name'], asText(leads[i]['full_name'])), style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(<String>[asText(leads[i]['phone']), dateTime(leads[i]['created_at'])].where((item) => item.isNotEmpty).join(' · ')),
                          onTap: () => onOpen('crm.leads'),
                        ),
                      ],
                    ]),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _LessonRow extends StatelessWidget {
  const _LessonRow({required this.lesson});

  final Map<String, dynamic> lesson;

  @override
  Widget build(BuildContext context) {
    final group = asMap(lesson['group']);
    final cancelled = lesson['status'] == 'cancelled';
    return ListTile(
      leading: SizedBox(
        width: 56,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
          Text(asText(lesson['start']), style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(asText(lesson['end']), style: TextStyle(color: AppColors.muted, fontSize: 12)),
        ]),
      ),
      title: Text(
        <String>[asText(group['name']), if (lesson['course'] != null) asText(lesson['course'])].join(' · '),
        style: TextStyle(fontWeight: FontWeight.w600, decoration: cancelled ? TextDecoration.lineThrough : null),
      ),
      subtitle: Text(<String>[
        if (lesson['teacher'] != null) asText(lesson['teacher']),
        if (lesson['room'] != null) asText(lesson['room']),
      ].join(' · ')),
      trailing: lesson['kind'] == 'school' ? Pill(tr('Maktab'), color: AppColors.muted) : null,
    );
  }
}

class _OrgLogo extends StatelessWidget {
  const _OrgLogo({required this.url, required this.name});

  final String? url;
  final String name;

  @override
  Widget build(BuildContext context) {
    if (url == null) return Avatar(name, size: 32);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(url!, width: 32, height: 32, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Avatar(name, size: 32)),
    );
  }
}
