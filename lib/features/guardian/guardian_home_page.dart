// «Farzandim» (ota-ona): bir nechta farzand bo'lsa — tepada almashtirgich; tablar: Umumiy, Kundalik (maktab),
// Testlar, To'lov (CRM). Barcha so'rovlar GuardianRepository orqali.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/offline_cache.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../staff/students_page.dart';
import '../notifications/notifications_page.dart';
import '../student/diary_page.dart';
import 'guardian_repository.dart';

/// Push xabari bosilganda (ota-ona): qaysi farzand (`student_id`) va yorliq (xabar turi) ochilsin — shell yozadi.
class GuardianFocus {
  GuardianFocus._();

  static final ValueNotifier<Map<String, dynamic>?> request = ValueNotifier<Map<String, dynamic>?>(null);
}

class GuardianHomePage extends StatefulWidget {
  const GuardianHomePage({super.key});

  @override
  State<GuardianHomePage> createState() => _GuardianHomePageState();
}

class _GuardianHomePageState extends State<GuardianHomePage> {
  late final GuardianRepository _repository = GuardianRepository(AppScope.read(context));
  List<GuardianChild>? _children;
  Object? _error;
  int? _selected;

  static const String _prefsKey = 'guardian.child';

  /// Push orqali tanlangan yorliq (kalit) va DefaultTabController ni qayta qurish uchun hisoblagich.
  String? _focusTab;
  int _focusSeq = 0;

  @override
  void initState() {
    super.initState();
    GuardianFocus.request.addListener(_onFocus);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
      _onFocus();
    });
  }

  @override
  void dispose() {
    GuardianFocus.request.removeListener(_onFocus);
    super.dispose();
  }

  /// Xabar turi → yorliq: davomat va to'lov — «To'lov va davomat», test — «Testlar», kundalik — «Kundalik».
  void _onFocus() {
    final data = GuardianFocus.request.value;
    if (data == null || !mounted) return;
    GuardianFocus.request.value = null;
    final student = asInt(data['student_id']);
    final type = asText(data['type']);
    const tabs = <String, String>{'payment': 'payments', 'attendance': 'payments', 'attempt': 'tests', 'diary': 'diary'};
    setState(() {
      if (student > 0 && (_children == null || _children!.any((child) => child.id == student))) _selected = student;
      _focusTab = tabs[type] ?? 'overview';
      _focusSeq++;
    });
    if (student > 0 && _children != null && _children!.any((child) => child.id == student)) unawaited(_select(student));
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      _repository.invalidate();
      var children = <GuardianChild>[];
      try {
        children = await _repository.children();
        unawaited(OfflineCache.write('guardian_children', children.map((item) => item.toJson()).toList()));
      } on ApiException catch (error) {
        // Internet yo'q: oxirgi farzandlar ro'yxati (tablar o'z nusxalarini ko'rsatadi)
        if (!error.isNetwork) rethrow;
        final cached = await OfflineCache.read('guardian_children');
        if (cached == null || cached.data is! List) rethrow;
        children = asList(cached.data).map(GuardianChild.fromJson).toList();
      }
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getInt('$_prefsKey.${_repository.session.organizationId}');
      if (!mounted) return;
      setState(() {
        _children = children;
        if (children.isEmpty) {
          _selected = null;
        } else if (_selected == null || !children.any((child) => child.id == _selected)) {
          _selected = children.any((child) => child.id == saved) ? saved : children.first.id;
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _select(int id) async {
    setState(() => _selected = id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('$_prefsKey.${_repository.session.organizationId}', id);
  }

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context);
    final children = _children;
    final error = _error;
    if (children == null) {
      Widget body;
      if (error is ApiException && error.isForbidden) {
        body = ForbiddenState(details: error.message, onRetry: _load);
      } else if (error != null) {
        body = ErrorState(message: errorText(error), onRetry: _load);
      } else {
        body = const SkeletonList(header: true, count: 3);
      }
      return Scaffold(appBar: AppBar(title: Text(tr('Farzandim')), actions: const <Widget>[NotificationBell()]), body: body);
    }
    if (children.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(tr('Farzandim')), actions: const <Widget>[NotificationBell()]),
        body: RefreshIndicator(
          onRefresh: _load,
          child: ListView(children: <Widget>[
            EmptyState(
              icon: Icons.family_restroom_outlined,
              text: tr("Hisobingizga hali farzand biriktirilmagan. O'quv markazi yoki maktab administratoridan taklif havolasini so'rang."),
            ),
          ]),
        ),
      );
    }
    final child = children.firstWhere((item) => item.id == _selected, orElse: () => children.first);
    // Veb «Farzandim» bilan bir xil yorliqlar (1.29): Umumiy · Kundalik (maktab) · Testlar (test) · To'lov va davomat (CRM).
    final tabs = <_ChildTab>[
      _ChildTab('overview', tr('Umumiy'), Icons.dashboard_outlined, (_) => _OverviewTab(repository: _repository, child: child)),
      if (session.hasModule('school'))
        _ChildTab('diary', tr('Kundalik'), Icons.event_note_outlined, (_) => DiaryWeekView(key: ValueKey<int>(child.id), studentId: child.id)),
      if (session.hasModule('testing'))
        _ChildTab('tests', tr('Testlar'), Icons.quiz_outlined, (_) => _TestsTab(repository: _repository, child: child)),
      if (session.hasModule('crm'))
        _ChildTab('payments', tr("To'lov va davomat"), Icons.account_balance_wallet_outlined, (_) => _PaymentsTab(repository: _repository, child: child)),
    ];
    final focus = tabs.indexWhere((tab) => tab.key == _focusTab);
    return DefaultTabController(
      key: ValueKey<String>('tabs-${tabs.length}-$_focusSeq'),
      length: tabs.length,
      initialIndex: focus < 0 ? 0 : focus,
      child: Scaffold(
        appBar: AppBar(
          title: Text(tr('Farzandim')),
          actions: const <Widget>[NotificationBell()],
          bottom: children.length < 2 && tabs.length < 2
              ? null
              : PreferredSize(
            preferredSize: Size.fromHeight((children.length > 1 ? 58.0 : 0.0) + (tabs.length > 1 ? 48.0 : 0.0)),
            child: Column(children: <Widget>[
              if (children.length > 1)
                SizedBox(
                  height: 58,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                    children: <Widget>[
                      for (final item in children)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            avatar: Avatar(item.name, size: 24),
                            label: Text(item.firstName),
                            selected: item.id == child.id,
                            showCheckmark: false,
                            onSelected: (_) => _select(item.id),
                          ),
                        ),
                    ],
                  ),
                ),
              if (tabs.length > 1)
                TabBar(
                  // 3 ta yorliqda ham «To'lov va davomat» kesilmasin — sig'masa suriladi.
                  isScrollable: tabs.length > 2,
                  tabAlignment: tabs.length > 2 ? TabAlignment.start : null,
                  tabs: tabs.map((tab) => Tab(text: tab.label, icon: null)).toList(),
                ),
            ]),
          ),
        ),
        body: TabBarView(
          key: ValueKey<int>(child.id),
          children: tabs.map((tab) => tab.builder(context)).toList(),
        ),
      ),
    );
  }
}

class _ChildTab {
  const _ChildTab(this.key, this.label, this.icon, this.builder);

  final String key;
  final String label;
  final IconData icon;
  final WidgetBuilder builder;
}

/// Balans kartasi: qarz bo'lsa qizil, «To'lash» tugmasi bilan.
class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.balance, required this.onPay});

  final int balance;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    final debt = balance < 0;
    return AppCard(
      color: debt ? AppColors.soft(AppColors.danger) : AppColors.card,
      child: Row(children: <Widget>[
        Icon(Icons.account_balance_wallet_outlined, color: debt ? AppColors.danger : AppColors.success, size: 30),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(debt ? tr('Qarz') : tr('Balans'), style: TextStyle(color: AppColors.muted)),
            Text(money(balance.abs()),
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: debt ? AppColors.danger : AppColors.ink)),
          ]),
        ),
        FilledButton.tonal(onPressed: onPay, child: Text(tr("To'lash"))),
      ]),
    );
  }
}

// ---------------- Umumiy ----------------

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.repository, required this.child});

  final GuardianRepository repository;
  final GuardianChild child;

  Future<Map<String, dynamic>> _load() async {
    final results = await Future.wait<dynamic>(<Future<dynamic>>[
      repository.insights(child.id),
      repository.finance(child.id).catchError((Object _) => null),
    ]);
    // Internetsiz nusxa uchun JSON ko'rinishida (ChildFinance — xom xarita ustidagi qobiq).
    final finance = results[1] is ChildFinance ? (results[1] as ChildFinance).raw : null;
    return <String, dynamic>{'insights': asMap(results[0]), 'finance': finance};
  }

  @override
  Widget build(BuildContext context) {
    return AsyncView<Map<String, dynamic>>(
      key: ValueKey<String>('overview-${child.id}'),
      cacheKey: 'child_overview_${child.id}',
      decode: asMap,
      load: () {
        repository.invalidate();
        return _load();
      },
      builder: (context, data, reload) {
        final insights = asMap(data['insights']);
        final finance = data['finance'] is Map ? ChildFinance(asMap(data['finance'])) : null;
        final testing = asMap(insights['testing']);
        final school = asMap(insights['school']);
        final crm = asMap(insights['crm']);
        final attempts = asList(testing['attempts'], 'attempts');
        final marks = asList(school['marks'], 'marks');
        final absence = asMap(school['absence_totals']);
        final counts = finance?.attendanceCounts ?? asMap(crm['attendance_30d']).map((key, value) => MapEntry(key, asInt(value)));
        final balance = finance?.balance ?? (crm['balance'] == null ? null : asInt(crm['balance']));
        final groups = child.groups.isNotEmpty
            ? child.groups
            : asList(crm['groups'], 'groups').map((item) => asText(item['name'])).where((item) => item.isNotEmpty).toList();
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
          children: <Widget>[
            Row(children: <Widget>[
              Avatar(child.name, size: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  Text(child.name, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                  Text(<String>[
                    if (child.code != null && child.code!.isNotEmpty) '${tr("O'quvchi kodi")}: ${child.code}',
                    if (groups.isNotEmpty) groups.join(', '),
                  ].join(' · '), style: TextStyle(color: AppColors.muted, fontSize: 13)),
                ]),
              ),
            ]),
            const SizedBox(height: 14),
            if (balance != null) ...<Widget>[
              _BalanceCard(
                balance: balance,
                onPay: () => repository.pay(context, child.id, suggested: balance < 0 ? -balance : 0, onDone: reload),
              ),
              const SizedBox(height: 10),
            ],
            if (counts.values.any((value) => value > 0)) ...<Widget>[
              SectionTitle(finance?.period != null ? '${tr('Davomat')} · ${finance!.period}' : tr('Davomat (30 kun)')),
              AppCard(
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: <Widget>[
                  for (final status in <String>['present', 'late', 'absent', 'excused'])
                    _Count(tr(attendanceLabels[status] ?? status), counts[status] ?? 0, attendanceColors[status] ?? AppColors.muted),
                ]),
              ),
            ],
            if (absence.isNotEmpty && absence.values.any((value) => asInt(value) > 0)) ...<Widget>[
              SectionTitle(tr('Maktab davomati')),
              AppCard(
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: <Widget>[
                  _Count(tr('Kelmadi'), asInt(absence['absent']), AppColors.danger),
                  _Count(tr('Sababli'), asInt(absence['excused']), AppColors.muted),
                  _Count(tr('Kechikdi'), asInt(absence['late']), AppColors.warning),
                ]),
              ),
            ],
            if (marks.isNotEmpty) ...<Widget>[
              SectionTitle(tr("So'nggi baholar")),
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(children: <Widget>[
                  for (var i = 0; i < marks.length && i < 6; i++) ...<Widget>[
                    if (i > 0) const Divider(),
                    ListTile(
                      dense: true,
                      title: Text(asText(marks[i]['subject']), style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(<String>[date(marks[i]['date']), if (marks[i]['topic'] != null) asText(marks[i]['topic'])].join(' · '),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: _Mark(value: asInt(marks[i]['mark'])),
                    ),
                  ],
                ]),
              ),
            ],
            if (attempts.isNotEmpty) ...<Widget>[
              SectionTitle(tr("So'nggi test natijalari")),
              for (final attempt in attempts.take(3)) ...<Widget>[
                _AttemptCard(attempt: attempt),
                const SizedBox(height: 8),
              ],
            ],
            if (finance != null && finance.lessons.isNotEmpty) ...<Widget>[
              SectionTitle(tr('Darslar')),
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(children: <Widget>[
                  for (var i = 0; i < finance.lessons.length && i < 8; i++) ...<Widget>[
                    if (i > 0) const Divider(),
                    ListTile(
                      dense: true,
                      title: Text(<String>[date(finance.lessons[i]['date']), asText(finance.lessons[i]['group'])]
                          .where((item) => item.isNotEmpty)
                          .join(' · ')),
                      subtitle: finance.lessons[i]['topic'] != null ? Text(asText(finance.lessons[i]['topic'])) : null,
                      trailing: Pill(tr(attendanceLabels[finance.lessons[i]['status']] ?? '—'),
                          color: attendanceColors[finance.lessons[i]['status']] ?? AppColors.muted),
                    ),
                  ],
                ]),
              ),
            ],
            if (balance == null && marks.isEmpty && attempts.isEmpty && !counts.values.any((value) => value > 0))
              EmptyState(icon: Icons.insights_outlined, text: tr("Hozircha ma'lumot yo'q. Darslar, baholar va natijalar shu yerda ko'rinadi.")),
          ],
        );
      },
    );
  }
}

// ---------------- Testlar ----------------

class _TestsTab extends StatelessWidget {
  const _TestsTab({required this.repository, required this.child});

  final GuardianRepository repository;
  final GuardianChild child;

  Future<Map<String, dynamic>> _load() async {
    repository.invalidate();
    final results = await Future.wait<dynamic>(<Future<dynamic>>[
      repository.testResults(child.id),
      repository.insights(child.id).catchError((Object _) => <String, dynamic>{}),
    ]);
    return <String, dynamic>{'attempts': results[0], 'testing': asMap(asMap(results[1])['testing'])};
  }

  @override
  Widget build(BuildContext context) {
    return AsyncView<Map<String, dynamic>>(
      key: ValueKey<String>('tests-${child.id}'),
      load: _load,
      builder: (context, data, reload) {
        final attempts = asList(data['attempts'], 'attempts');
        final testing = asMap(data['testing']);
        final pending = asList(testing['pending'], 'pending');
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
          children: <Widget>[
            if (testing.isNotEmpty)
              StatGrid(children: <Widget>[
                StatCard(label: tr('Topshirilgan testlar'), value: '${asInt(testing['count'])}', icon: Icons.quiz_outlined),
                StatCard(
                  label: tr("O'rtacha natija"),
                  value: percent(testing['average_percent'] as num?),
                  icon: Icons.insights_outlined,
                  color: AppColors.success,
                ),
              ]),
            if (pending.isNotEmpty) ...<Widget>[
              SectionTitle(tr('Topshirilishi kerak')),
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(children: <Widget>[
                  for (var i = 0; i < pending.length; i++) ...<Widget>[
                    if (i > 0) const Divider(),
                    ListTile(
                      dense: true,
                      leading: Icon(Icons.pending_actions_outlined, color: AppColors.warning),
                      title: Text(asText(pending[i]['title'])),
                      subtitle: pending[i]['ends_at'] != null ? Text(tr('{0} gacha', <Object?>[dateTime(pending[i]['ends_at'])])) : null,
                    ),
                  ],
                ]),
              ),
            ],
            SectionTitle(tr('Natijalar')),
            if (attempts.isEmpty)
              EmptyState(icon: Icons.quiz_outlined, text: tr("Hali test topshirilmagan."))
            else
              for (final attempt in attempts) ...<Widget>[
                _AttemptCard(attempt: attempt),
                const SizedBox(height: 8),
              ],
          ],
        );
      },
    );
  }
}

class _AttemptCard extends StatelessWidget {
  const _AttemptCard({required this.attempt});

  final Map<String, dynamic> attempt;

  @override
  Widget build(BuildContext context) {
    final max = asDouble(attempt['max_score']);
    final score = asDouble(attempt['score']);
    final ratio = max > 0 ? score / max : (attempt['percent'] != null ? asDouble(attempt['percent']) / 100 : null);
    final color = ratio == null
        ? AppColors.brand
        : ratio >= 0.85
            ? AppColors.success
            : ratio >= 0.6
                ? AppColors.brand
                : ratio >= 0.4
                    ? AppColors.warning
                    : AppColors.danger;
    final correct = asInt(attempt['correct']);
    final total = attempt['total'] != null ? asInt(attempt['total']) : correct + asInt(attempt['wrong']) + asInt(attempt['blank']);
    final label = asText(attempt['overall'], asText(attempt['level']));
    return AppCard(
      child: Row(children: <Widget>[
        Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: color.withAlpha(28), borderRadius: BorderRadius.circular(14)),
          child: Text(ratio == null ? '—' : '${(ratio * 100).round()}%',
              style: TextStyle(fontWeight: FontWeight.w800, color: color, fontSize: 15)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(asText(attempt['exam'], tr('Test')), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(<String>[
              date(attempt['finished_at']),
              '$correct/$total',
              if (max > 0) '${number(score)} / ${number(max)} ${tr('ball')}',
              if (label.isNotEmpty) label,
            ].join(' · '), style: TextStyle(color: AppColors.muted, fontSize: 13)),
            if (asInt(attempt['pending']) > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Pill(tr("O'qituvchi tekshirmoqda"), color: AppColors.warning),
              ),
          ]),
        ),
      ]),
    );
  }
}

// ---------------- To'lov ----------------

class _PaymentsTab extends StatelessWidget {
  const _PaymentsTab({required this.repository, required this.child});

  final GuardianRepository repository;
  final GuardianChild child;

  @override
  Widget build(BuildContext context) {
    return AsyncView<ChildFinance?>(
      key: ValueKey<String>('payments-${child.id}'),
      load: () {
        repository.invalidate();
        return repository.finance(child.id);
      },
      builder: (context, finance, reload) {
        if (finance == null) {
          return ListView(children: <Widget>[
            EmptyState(icon: Icons.receipt_long_outlined, text: tr("To'lov ma'lumotlari topilmadi.")),
          ]);
        }
        final charges = finance.charges;
        final payments = finance.payments;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
          children: <Widget>[
            _BalanceCard(
              balance: finance.balance,
              onPay: () => repository.pay(context, child.id, suggested: finance.balance < 0 ? -finance.balance : 0, onDone: reload),
            ),
            SectionTitle(tr('Hisoblangan')),
            if (charges.isEmpty)
              EmptyState(icon: Icons.receipt_outlined, text: tr("Hisoblangan to'lov yo'q."))
            else
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(children: <Widget>[
                  for (var i = 0; i < charges.length; i++) ...<Widget>[
                    if (i > 0) const Divider(),
                    ListTile(
                      dense: true,
                      leading: Icon(Icons.receipt_outlined, color: AppColors.muted),
                      title: Text(asText(charges[i]['title'], tr("O'qish to'lovi")), style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(asText(charges[i]['period'])),
                      trailing: Text(money(asInt(charges[i]['amount'])), style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ],
                ]),
              ),
            SectionTitle(tr("So'nggi to'lovlar")),
            if (payments.isEmpty)
              EmptyState(icon: Icons.payments_outlined, text: tr("Hali to'lov qilinmagan."))
            else
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(children: <Widget>[
                  for (var i = 0; i < payments.length; i++) ...<Widget>[
                    if (i > 0) const Divider(),
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.check_circle_outline, color: AppColors.success),
                      title: Text(money(asInt(payments[i]['amount'])), style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(<String>[
                        dateTime(payments[i]['paid_at']),
                        tr(paymentMethods[payments[i]['method']] ?? asText(payments[i]['method'])),
                      ].join(' · ')),
                      trailing: payments[i]['receipt'] != null
                          ? Text(asText(payments[i]['receipt']), style: TextStyle(color: AppColors.muted, fontSize: 12))
                          : null,
                    ),
                  ],
                ]),
              ),
          ],
        );
      },
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

class _Mark extends StatelessWidget {
  const _Mark({required this.value});

  final int value;

  @override
  Widget build(BuildContext context) {
    final color = value >= 5
        ? AppColors.success
        : value == 4
            ? AppColors.brand
            : value == 3
                ? AppColors.warning
                : AppColors.danger;
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color.withAlpha(30), borderRadius: BorderRadius.circular(10)),
      child: Text('$value', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: color)),
    );
  }
}
