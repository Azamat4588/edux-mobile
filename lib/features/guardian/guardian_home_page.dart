// Ota-ona: farzandlar — har biri bo'yicha balans va to'lov, davomat, test natijalari, baholar.
import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../staff/students_page.dart';
import '../student/student_home_page.dart';

class GuardianHomePage extends StatelessWidget {
  const GuardianHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Farzandlarim'))),
      body: AsyncView<List<Map<String, dynamic>>>(
        load: () async => asList(asMap(await session.api.get('my/children'))['children'], 'children'),
        builder: (context, children, reload) {
          if (children.isEmpty) {
            return ListView(children: <Widget>[
              EmptyState(text: tr("Hisobingizga hali farzand biriktirilmagan. O'quv markazi yoki maktab administratoridan taklif havolasini so'rang.")),
            ]);
          }
          if (children.length == 1) {
            return _ChildView(childId: asInt(children.first['id']), name: asText(children.first['full_name']));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: children.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final child = children[index];
              final groups = ((child['groups'] as List?) ?? const <dynamic>[]).join(', ');
              return AppCard(
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: Text(asText(child['full_name']))),
                    body: _ChildView(childId: asInt(child['id']), name: asText(child['full_name'])),
                  ),
                )),
                child: Row(children: <Widget>[
                  Avatar(asText(child['full_name']), size: 48),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                      Text(asText(child['full_name']), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      if (groups.isNotEmpty) Text(groups, style: TextStyle(color: AppColors.muted)),
                    ]),
                  ),
                  Icon(Icons.chevron_right, color: AppColors.muted),
                ]),
              );
            },
          );
        },
      ),
    );
  }
}

class _ChildView extends StatelessWidget {
  const _ChildView({required this.childId, required this.name});

  final int childId;
  final String name;

  Future<Map<String, dynamic>> _load(Session session) async {
    final results = await Future.wait<dynamic>(<Future<dynamic>>[
      session.api.get('my/insights', query: <String, Object?>{'student_id': childId}),
      if (session.hasModule('crm')) session.api.get('crm/my/children').catchError((_) => null),
    ]);
    Map<String, dynamic> crm = <String, dynamic>{};
    if (results.length > 1) {
      for (final child in asList(asMap(results[1])['children'], 'children')) {
        if (asInt(child['id']) == childId) crm = child;
      }
    }
    return <String, dynamic>{'insights': asMap(results[0]), 'crm': crm};
  }

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context);
    return AsyncView<Map<String, dynamic>>(
      load: () => _load(session),
      builder: (context, data, reload) {
        final crm = asMap(data['crm']);
        final attendance = asMap(crm['attendance']);
        final lessons = asList(attendance['lessons'], 'lessons');
        final payments = asList(crm['payments'], 'payments');
        return ListView(
          padding: EdgeInsets.zero,
          children: <Widget>[
            StudentOverviewBody(insights: asMap(data['insights']), crm: crm, studentId: childId, showGreeting: false),
            if (lessons.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
                  SectionTitle(tr('Davomat')),
                  AppCard(
                    padding: EdgeInsets.zero,
                    child: Column(children: <Widget>[
                      for (final lesson in lessons.take(10))
                        ListTile(
                          dense: true,
                          title: Text(<String>[date(lesson['date']), asText(lesson['group'])].where((s) => s.isNotEmpty).join(' · ')),
                          subtitle: lesson['topic'] != null ? Text(asText(lesson['topic'])) : null,
                          trailing: Pill(tr(attendanceLabels[lesson['status']] ?? '—'), color: attendanceColors[lesson['status']] ?? AppColors.muted),
                        ),
                    ]),
                  ),
                ]),
              ),
            if (payments.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
                  SectionTitle(tr("So'nggi to'lovlar")),
                  AppCard(
                    padding: EdgeInsets.zero,
                    child: Column(children: <Widget>[
                      for (final payment in payments)
                        ListTile(
                          title: Text(money(asInt(payment['amount'])), style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(<String>[
                            dateTime(payment['paid_at']),
                            tr(paymentMethods[payment['method']] ?? asText(payment['method'])),
                          ].join(' · ')),
                          trailing: payment['receipt'] != null ? Text(asText(payment['receipt']), style: TextStyle(color: AppColors.muted)) : null,
                        ),
                    ]),
                  ),
                ]),
              ),
          ],
        );
      },
    );
  }
}
