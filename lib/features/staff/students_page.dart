// O'quvchilar: qidiruv (ism, kod, telefon) va o'quvchi kartasi — balans, guruhlar, davomat, natijalar, to'lovlar.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'payment_sheet.dart';

class StudentsPage extends StatefulWidget {
  const StudentsPage({super.key, this.forPayment = false});

  /// To'lov qabul qilish uchun o'quvchi tanlash rejimi.
  final bool forPayment;

  @override
  State<StudentsPage> createState() => _StudentsPageState();
}

class _StudentsPageState extends State<StudentsPage> {
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _items = <Map<String, dynamic>>[];
  int _total = 0;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _load);
  }

  Future<void> _load() async {
    final session = AppScope.read(context);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final crm = session.hasModule('crm');
      final data = await session.api.get(crm ? 'crm/students' : 'students', query: <String, Object?>{'search': _search.text.trim()});
      if (!mounted) return;
      setState(() {
        _items = asList(data);
        _total = data is Map ? asInt(data['total'], _items.length) : _items.length;
        _loading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    }
  }

  void _open(Map<String, dynamic> student) {
    final id = asInt(student['id']);
    final name = asText(student['full_name']);
    if (widget.forPayment) {
      showPaymentSheet(context, studentId: id, studentName: name, groups: asList(student['groups'], 'groups')).then((paid) {
        if (paid == true && mounted) Navigator.pop(context);
      });
      return;
    }
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => StudentCardPage(studentId: id, name: name)));
  }

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context);
    final title = widget.forPayment ? tr("To'lov qabul qilish") : session.term('students', "O'quvchilar");
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              controller: _search,
              onChanged: _onSearch,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: tr('Ism, kod yoki telefon'),
                isDense: true,
                fillColor: AppColors.surface,
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _search.clear();
                          _load();
                        }),
              ),
            ),
          ),
        ),
      ),
      body: _loading && _items.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _items.isEmpty
              ? ErrorState(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _items.isEmpty
                      ? ListView(children: <Widget>[EmptyState(text: tr("Hech narsa topilmadi. Qidiruv so'zini yoki filtrni o'zgartirib ko'ring."))])
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: _items.length + (_total > _items.length ? 1 : 0),
                          separatorBuilder: (_, __) => const Divider(indent: 72),
                          itemBuilder: (context, index) {
                            if (index >= _items.length) {
                              return Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(tr('Yana {0} ta — qidiruvni aniqlashtiring', <Object?>[_total - _items.length]),
                                    textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
                              );
                            }
                            return _StudentTile(student: _items[index], onTap: () => _open(_items[index]));
                          },
                        ),
                ),
    );
  }
}

class _StudentTile extends StatelessWidget {
  const _StudentTile({required this.student, required this.onTap});

  final Map<String, dynamic> student;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final groups = asList(student['groups'], 'groups').map((group) => asText(group['name'])).join(', ');
    final balance = student['balance'];
    final debt = balance is num && balance < 0;
    return ListTile(
      onTap: onTap,
      leading: Avatar(asText(student['full_name'])),
      title: Text(asText(student['full_name']), style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(<String>['#${asText(student['code'])}', if (groups.isNotEmpty) groups].join(' · '),
          maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: balance is num
          ? Text(money(balance),
              style: TextStyle(fontWeight: FontWeight.w700, color: debt ? AppColors.danger : AppColors.success, fontSize: 13))
          : null,
    );
  }
}

const Map<String, String> attendanceLabels = <String, String>{
  'present': 'Keldi',
  'absent': 'Kelmadi',
  'late': 'Kechikdi',
  'excused': 'Sababli',
};

const Map<String, Color> attendanceColors = <String, Color>{
  'present': AppColors.success,
  'absent': AppColors.danger,
  'late': AppColors.warning,
  'excused': AppColors.muted,
};

const Map<String, String> paymentMethods = <String, String>{
  'cash': 'Naqd',
  'card': 'Karta',
  'click': 'Click',
  'payme': 'Payme',
  'transfer': "Bank o'tkazmasi",
};

class StudentCardPage extends StatefulWidget {
  const StudentCardPage({super.key, required this.studentId, required this.name});

  final int studentId;
  final String name;

  @override
  State<StudentCardPage> createState() => _StudentCardPageState();
}

class _StudentCardPageState extends State<StudentCardPage> {
  final GlobalKey<AsyncViewState<Map<String, dynamic>>> _view = GlobalKey<AsyncViewState<Map<String, dynamic>>>();

  Future<Map<String, dynamic>> _load(Session session) async {
    if (session.hasModule('crm')) {
      return asMap(await session.api.get('crm/students/${widget.studentId}'));
    }
    final insights = asMap(await session.api.get('students/${widget.studentId}/insights'));
    return <String, dynamic>{'student': insights['student'], 'insights': insights};
  }

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.name)),
      floatingActionButton: session.canTakePayments
          ? FloatingActionButton.extended(
              onPressed: () async {
                final paid = await showPaymentSheet(context, studentId: widget.studentId, studentName: widget.name);
                if (paid == true) _view.currentState?.reload();
              },
              icon: const Icon(Icons.add_card),
              label: Text(tr("To'lov qabul qilish")),
            )
          : null,
      body: AsyncView<Map<String, dynamic>>(
        key: _view,
        load: () => _load(session),
        builder: (context, data, reload) => _Card(data: data),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final student = asMap(data['student']);
    final groups = asList(data['groups'], 'groups');
    final attendance = asMap(data['attendance']);
    final counts = asMap(attendance['counts']);
    final attempts = data['attempts'] != null ? asList(data['attempts'], 'attempts') : asList(asMap(asMap(data['insights'])['testing'])['attempts'], 'attempts');
    final payments = asList(data['payments'], 'payments');
    final phone = asText(student['phone']);
    final hasBalance = data['balance'] != null;
    final balance = asInt(data['balance']);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: <Widget>[
        AppCard(
          child: Row(children: <Widget>[
            Avatar(asText(student['full_name']), size: 52),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text(asText(student['full_name']), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text('${tr("O'quvchi kodi")}: ${asText(student['code'])}', style: const TextStyle(color: AppColors.muted)),
                if (student['archived'] == true) ...<Widget>[const SizedBox(height: 4), Pill(tr('Arxivda'), color: AppColors.muted)],
              ]),
            ),
            if (phone.isNotEmpty)
              IconButton.filledTonal(
                icon: const Icon(Icons.call),
                onPressed: () => launchUrl(Uri.parse('tel:$phone')),
              ),
          ]),
        ),
        if (hasBalance) ...<Widget>[
          const SizedBox(height: 12),
          StatGrid(children: <Widget>[
            StatCard(
              label: tr('Balans'),
              value: groupDigits(balance) == '0' ? '0' : '${balance < 0 ? '−' : ''}${groupDigits(balance)}',
              icon: Icons.account_balance_wallet_outlined,
              color: balance < 0 ? AppColors.danger : AppColors.success,
              hint: balance < 0 ? tr('Qarz') : tr("so'm"),
            ),
            StatCard(
              label: tr('Davomat'),
              value: '${asInt(counts['present'])}/${asInt(counts['present']) + asInt(counts['absent']) + asInt(counts['late']) + asInt(counts['excused'])}',
              icon: Icons.fact_check_outlined,
              hint: asInt(counts['absent']) > 0 ? tr('{0} ta qoldirilgan', <Object?>[asInt(counts['absent'])]) : null,
            ),
          ]),
        ],
        if (groups.isNotEmpty) ...<Widget>[
          SectionTitle(tr('Guruhlar')),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(children: <Widget>[
              for (var i = 0; i < groups.length; i++) ...<Widget>[
                if (i > 0) const Divider(),
                ListTile(
                  title: Text(asText(groups[i]['name']), style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(asText(groups[i]['teacher'])),
                  trailing: groups[i]['monthly_fee'] != null ? Text(money(asInt(groups[i]['monthly_fee']))) : null,
                ),
              ],
            ]),
          ),
        ],
        if (attempts.isNotEmpty) ...<Widget>[
          SectionTitle(tr('Test natijalari')),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(children: <Widget>[
              for (var i = 0; i < attempts.length; i++) ...<Widget>[
                if (i > 0) const Divider(),
                ListTile(
                  title: Text(asText(attempts[i]['exam'])),
                  subtitle: Text(date(attempts[i]['finished_at'])),
                  trailing: Text('${asInt(attempts[i]['correct'])}/${asInt(attempts[i]['total'])}',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
              ],
            ]),
          ),
        ],
        if (asList(attendance['recent'], 'recent').isNotEmpty) ...<Widget>[
          SectionTitle(tr('So\'nggi darslar')),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(children: <Widget>[
              for (final lesson in asList(attendance['recent'], 'recent').take(8))
                ListTile(
                  dense: true,
                  title: Text(<String>[date(lesson['date']), asText(lesson['group'])].join(' · ')),
                  subtitle: lesson['topic'] != null ? Text(asText(lesson['topic'])) : null,
                  trailing: Pill(tr(attendanceLabels[lesson['status']] ?? '—'),
                      color: attendanceColors[lesson['status']] ?? AppColors.muted),
                ),
            ]),
          ),
        ],
        if (payments.isNotEmpty) ...<Widget>[
          SectionTitle(tr("So'nggi to'lovlar")),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(children: <Widget>[
              for (var i = 0; i < payments.length; i++) ...<Widget>[
                if (i > 0) const Divider(),
                ListTile(
                  title: Text(money(asInt(payments[i]['amount'])),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        decoration: payments[i]['voided_at'] != null ? TextDecoration.lineThrough : null,
                      )),
                  subtitle: Text(<String>[
                    dateTime(payments[i]['paid_at']),
                    tr(paymentMethods[payments[i]['method']] ?? asText(payments[i]['method'])),
                    if (payments[i]['receipt'] != null) asText(payments[i]['receipt']),
                  ].join(' · ')),
                  trailing: payments[i]['voided_at'] != null ? Pill(tr('Bekor qilingan'), color: AppColors.danger) : null,
                ),
              ],
            ]),
          ),
        ],
      ],
    );
  }
}
