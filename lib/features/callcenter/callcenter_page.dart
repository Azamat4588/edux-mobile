// Call markazi (3.1, operatorlar): jonli qo'ng'iroq va qo'ng'iroq qiluvchi kartasi (sahifa ochiq va ilova oldingi
// planda bo'lganda har 10 soniyada yangilanadi), javobsiz qo'ng'iroqlar navbati, jurnal va skriptlar.
// Barcha so'rovlar CallCenterRepository orqali.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../crm/leads_page.dart';
import '../staff/students_page.dart';
import 'callcenter_repository.dart';

class CallCenterPage extends StatefulWidget {
  const CallCenterPage({super.key});

  @override
  State<CallCenterPage> createState() => _CallCenterPageState();
}

class _CallCenterPageState extends State<CallCenterPage> with WidgetsBindingObserver {
  /// Jonli holatni so'rash oralig'i (faqat sahifa ko'rinib turganda).
  static const Duration _interval = Duration(seconds: 10);

  late final CallCenterRepository _repository = CallCenterRepository(AppScope.read(context));
  final GlobalKey<AsyncViewState<List<Map<String, dynamic>>>> _queueView = GlobalKey<AsyncViewState<List<Map<String, dynamic>>>>();

  Timer? _timer;
  bool _foreground = true;
  bool _polling = false;
  Map<String, dynamic>? _live;
  Object? _liveError;
  int? _queueCount;

  // Eng yangi jonli qo'ng'iroq raqami bo'yicha karta (har so'rovda qayta olinmaydi).
  String? _callerPhone;
  Map<String, dynamic>? _caller;
  bool _callerLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _poll());
    _timer = Timer.periodic(_interval, (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) _poll();
  }

  void _tick() {
    if (!mounted || !_foreground) return;
    // Pastki menyuda boshqa bo'lim tanlangan (IndexedStack'da yashirin) — so'ramaymiz.
    if (!TabVisibility.of(context)) return;
    // Ustida boshqa sahifa (lid, o'quvchi kartasi) ochiq bo'lsa — so'ramaymiz.
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    _poll();
  }

  Future<void> _poll() async {
    if (_polling || !mounted) return;
    _polling = true;
    try {
      final live = await _repository.live();
      if (!mounted) return;
      final queue = asInt(live['queue']);
      final changedQueue = _queueCount != null && _queueCount != queue;
      setState(() {
        _live = live;
        _liveError = null;
        _queueCount = queue;
      });
      if (changedQueue) unawaited(_queueView.currentState?.reload());
      final calls = asList(live['live'], 'live');
      final phone = calls.isEmpty ? null : asText(calls.first['phone']);
      if (phone != null && phone.isNotEmpty && phone != _callerPhone) unawaited(_loadCaller(phone));
      if (phone == null && _callerPhone != null) {
        setState(() {
          _callerPhone = null;
          _caller = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _liveError = error);
    } finally {
      _polling = false;
    }
  }

  Future<void> _loadCaller(String phone) async {
    setState(() {
      _callerPhone = phone;
      _callerLoading = true;
    });
    try {
      final caller = await _repository.caller(phone);
      if (mounted && _callerPhone == phone) setState(() => _caller = caller);
    } catch (_) {
      if (mounted && _callerPhone == phone) setState(() => _caller = null);
    } finally {
      if (mounted) setState(() => _callerLoading = false);
    }
  }

  Future<void> _setStatus(String status) async {
    try {
      final live = await _repository.setStatus(status);
      if (mounted) setState(() => _live = live);
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    }
  }

  Future<void> _logCall() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet))),
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _LogCallForm(repository: _repository),
      ),
    );
    if (saved == true && mounted) {
      showMessage(context, tr("Qo'ng'iroq qayd etildi."));
      unawaited(_poll());
    }
  }

  @override
  Widget build(BuildContext context) {
    final queue = _queueCount ?? 0;
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(tr('Call markazi')),
          actions: <Widget>[
            IconButton(tooltip: tr("Qo'ng'iroqni qayd etish"), onPressed: _logCall, icon: const Icon(Icons.add_call)),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: <Widget>[
              Tab(text: tr('Jonli')),
              Tab(
                child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                  Text(tr('Navbat')),
                  if (queue > 0) ...<Widget>[
                    const SizedBox(width: 6),
                    Badge(label: Text('$queue'), backgroundColor: AppColors.danger),
                  ],
                ]),
              ),
              Tab(text: tr('Jurnal')),
              Tab(text: tr('Skriptlar')),
            ],
          ),
        ),
        body: TabBarView(children: <Widget>[
          _LiveTab(
            live: _live,
            error: _liveError,
            caller: _caller,
            callerLoading: _callerLoading,
            repository: _repository,
            onRefresh: _poll,
            onStatus: _setStatus,
          ),
          _QueueTab(viewKey: _queueView, repository: _repository, onChanged: _poll),
          _JournalTab(repository: _repository),
          _ScriptsTab(repository: _repository),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Jonli
// ---------------------------------------------------------------------------

class _LiveTab extends StatelessWidget {
  const _LiveTab({
    required this.live,
    required this.error,
    required this.caller,
    required this.callerLoading,
    required this.repository,
    required this.onRefresh,
    required this.onStatus,
  });

  final Map<String, dynamic>? live;
  final Object? error;
  final Map<String, dynamic>? caller;
  final bool callerLoading;
  final CallCenterRepository repository;
  final Future<void> Function() onRefresh;
  final ValueChanged<String> onStatus;

  @override
  Widget build(BuildContext context) {
    final data = live;
    if (data == null) {
      final failure = error;
      if (failure == null) return const SkeletonList(count: 3);
      if (failure is ApiException && failure.isForbidden) return ForbiddenState(details: failure.message, onRetry: onRefresh);
      return ErrorState(message: errorText(failure), onRetry: onRefresh);
    }
    final me = asMap(data['me']);
    final calls = asList(data['live'], 'live');
    final operators = asList(data['operators'], 'operators');
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.l),
        children: <Widget>[
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.m),
              child: Text(errorText(error), style: const TextStyle(color: AppColors.danger, fontSize: 13)),
            ),
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text(tr('Mening holatim'), style: TextStyle(color: AppColors.muted, fontSize: 13)),
              const SizedBox(height: AppSpacing.s),
              Wrap(spacing: AppSpacing.s, runSpacing: AppSpacing.s, children: <Widget>[
                for (final entry in operatorStatusLabels.entries)
                  ChoiceChip(
                    label: Text(tr(entry.value)),
                    selected: asText(me['status'], 'offline') == entry.key,
                    onSelected: (_) => onStatus(entry.key),
                  ),
              ]),
              if (asText(me['extension']).isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.s),
                Text(tr('Ichki raqam: {0}', <Object?>[asText(me['extension'])]), style: TextStyle(color: AppColors.muted, fontSize: 13)),
              ],
            ]),
          ),
          const SizedBox(height: AppSpacing.m),
          if (calls.isEmpty)
            AppCard(
              child: Row(children: <Widget>[
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: AppColors.soft(AppColors.success), shape: BoxShape.circle),
                  child: const Icon(Icons.phone_in_talk_outlined, color: AppColors.success),
                ),
                const SizedBox(width: AppSpacing.m),
                Expanded(
                  child: Text(tr("Hozir faol qo'ng'iroq yo'q. Kiruvchi qo'ng'iroq bo'lsa, shu yerda qo'ng'iroq qiluvchi kartasi chiqadi."),
                      style: TextStyle(color: AppColors.muted)),
                ),
              ]),
            )
          else ...<Widget>[
            for (var i = 0; i < calls.length; i++) ...<Widget>[
              _LiveCallCard(call: calls[i], repository: repository),
              if (i == 0) ...<Widget>[
                const SizedBox(height: AppSpacing.s),
                if (callerLoading && caller == null)
                  const Padding(padding: EdgeInsets.all(AppSpacing.l), child: Center(child: CircularProgressIndicator()))
                else if (caller != null)
                  CallerCardView(caller: caller!, repository: repository, callId: asInt(calls[i]['id'])),
              ],
              const SizedBox(height: AppSpacing.m),
            ],
          ],
          const SizedBox(height: AppSpacing.s),
          _LookupCard(repository: repository),
          if (operators.isNotEmpty) ...<Widget>[
            SectionTitle(tr('Operatorlar')),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(children: <Widget>[
                for (var i = 0; i < operators.length; i++) ...<Widget>[
                  if (i > 0) const Divider(),
                  ListTile(
                    leading: Avatar(asText(operators[i]['name'], '?'), size: 36),
                    title: Text(asText(operators[i]['name'], '—')),
                    subtitle: Text(tr("Bugun: {0} ta qo'ng'iroq", <Object?>[asInt(operators[i]['today'])])),
                    trailing: Pill(
                      tr(operatorStatusLabels[asText(operators[i]['status'])] ?? asText(operators[i]['status'])),
                      color: _operatorColor(asText(operators[i]['status'])),
                    ),
                  ),
                ],
              ]),
            ),
          ],
        ],
      ),
    );
  }

  static Color _operatorColor(String status) {
    if (status == 'available') return AppColors.success;
    if (status == 'break') return AppColors.warning;
    return AppColors.muted;
  }
}

class _LiveCallCard extends StatelessWidget {
  const _LiveCallCard({required this.call, required this.repository});

  final Map<String, dynamic> call;
  final CallCenterRepository repository;

  @override
  Widget build(BuildContext context) {
    final status = asText(call['live_status']);
    final ringing = status == 'ringing';
    final incoming = asText(call['direction']) == 'in';
    final phone = asText(call['phone']);
    final color = ringing ? AppColors.warning : AppColors.success;
    return AppCard(
      color: AppColors.soft(color),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Row(children: <Widget>[
          Icon(incoming ? Icons.call_received_rounded : Icons.call_made_rounded, color: color),
          const SizedBox(width: AppSpacing.s),
          Expanded(
            child: Text(asText(call['caller']).isNotEmpty ? asText(call['caller']) : phone,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ),
          Pill(tr(liveStatusLabels[status] ?? status), color: color),
        ]),
        const SizedBox(height: AppSpacing.xs),
        Text(<String>[
          phone,
          if (asText(call['operator']).isNotEmpty) asText(call['operator']),
          if (asText(call['extension']).isNotEmpty) '#${asText(call['extension'])}',
          dateTime(call['started_at']),
        ].join(' · '), style: TextStyle(color: AppColors.muted, fontSize: 13)),
        const SizedBox(height: AppSpacing.m),
        Row(children: <Widget>[
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => showOutcomeSheet(context, repository, call),
              icon: const Icon(Icons.edit_note_rounded),
              label: Text(tr('Natija')),
            ),
          ),
          const SizedBox(width: AppSpacing.s),
          Expanded(
            child: FilledButton.icon(
              onPressed: phone.isEmpty ? null : () => launchUrl(Uri.parse('tel:${dialable(phone)}')),
              icon: const Icon(Icons.call),
              label: Text(tr("Qo'ng'iroq")),
            ),
          ),
        ]),
      ]),
    );
  }
}

/// Raqam bo'yicha qo'lda qidirish (PBX ulanmagan bo'lsa ham karta ko'rinsin).
class _LookupCard extends StatefulWidget {
  const _LookupCard({required this.repository});

  final CallCenterRepository repository;

  @override
  State<_LookupCard> createState() => _LookupCardState();
}

class _LookupCardState extends State<_LookupCard> {
  final TextEditingController _phone = TextEditingController();

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  void _search() {
    final phone = _phone.text.trim();
    if (dialable(phone).replaceAll('+', '').length < 7) {
      showMessage(context, tr("Telefon raqamini to'liq kiriting."), error: true);
      return;
    }
    FocusScope.of(context).unfocus();
    showCallerSheet(context, widget.repository, phone);
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Text(tr('Raqam bo\'yicha qidirish'), style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: AppSpacing.s),
        Row(children: <Widget>[
          Expanded(
            child: TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: const InputDecoration(hintText: '+998 90 123 45 67', isDense: true, prefixIcon: Icon(Icons.phone_outlined)),
            ),
          ),
          const SizedBox(width: AppSpacing.s),
          IconButton.filled(tooltip: tr('Qidirish'), onPressed: _search, icon: const Icon(Icons.person_search_outlined)),
        ]),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Qo'ng'iroq qiluvchi kartasi
// ---------------------------------------------------------------------------

/// Raqam bo'yicha karta pastki varaqda (navbat, jurnal, qidiruvdan).
Future<void> showCallerSheet(BuildContext context, CallCenterRepository repository, String phone, {Map<String, dynamic>? call}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet))),
    builder: (sheetContext) => FractionallySizedBox(
      heightFactor: 0.85,
      child: Column(children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 4),
          child: Row(children: <Widget>[
            Expanded(child: Text(phone, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
            IconButton(onPressed: () => Navigator.pop(sheetContext), icon: const Icon(Icons.close)),
          ]),
        ),
        Expanded(
          child: AsyncView<Map<String, dynamic>>(
            load: () => repository.caller(phone),
            skeleton: const SkeletonList(count: 3),
            builder: (context, caller, reload) => ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: <Widget>[
                Row(children: <Widget>[
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => launchUrl(Uri.parse('tel:${dialable(phone)}')),
                      icon: const Icon(Icons.call),
                      label: Text(tr("Qayta qo'ng'iroq")),
                    ),
                  ),
                  if (call != null) ...<Widget>[
                    const SizedBox(width: AppSpacing.s),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => showOutcomeSheet(context, repository, call),
                        icon: const Icon(Icons.edit_note_rounded),
                        label: Text(tr('Natija')),
                      ),
                    ),
                  ],
                ]),
                const SizedBox(height: AppSpacing.m),
                CallerCardView(caller: caller, repository: repository, callId: call == null ? null : asInt(call['id'])),
              ],
            ),
          ),
        ),
      ]),
    ),
  );
}

/// Karta: kim qo'ng'iroq qilyapti — o'quvchi(lar), lid(lar), ochiq vazifalar, so'nggi qo'ng'iroqlar.
class CallerCardView extends StatelessWidget {
  const CallerCardView({super.key, required this.caller, required this.repository, this.callId});

  final Map<String, dynamic> caller;
  final CallCenterRepository repository;
  final int? callId;

  void _push(BuildContext context, Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context);
    final students = asList(caller['students'], 'students');
    final leads = asList(caller['leads'], 'leads');
    final tasks = asList(caller['tasks'], 'tasks');
    final calls = asList(caller['calls'], 'calls');
    if (students.isEmpty && leads.isEmpty && calls.isEmpty) {
      return AppCard(
        child: Row(children: <Widget>[
          const Icon(Icons.person_outline, color: AppColors.warning),
          const SizedBox(width: AppSpacing.m),
          Expanded(
            child: Text(tr('Notanish raqam. Natijani «Qiziqdi» yoki «Sinov darsiga yozildi» deb belgilasangiz, yangi lid yaratiladi.'),
                style: TextStyle(color: AppColors.muted)),
          ),
        ]),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      for (final student in students) ...<Widget>[
        AppCard(
          onTap: session.canSeeStudents
              ? () => _push(context, StudentCardPage(studentId: asInt(student['id']), name: asText(student['name'])))
              : null,
          child: Row(children: <Widget>[
            Avatar(asText(student['name'], '?')),
            const SizedBox(width: AppSpacing.m),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Row(children: <Widget>[
                  Flexible(child: Text(asText(student['name']), style: const TextStyle(fontWeight: FontWeight.w700))),
                  const SizedBox(width: AppSpacing.s),
                  Pill(student['parent'] == true ? tr('Ota-ona') : session.term('student', "O'quvchi"),
                      color: student['parent'] == true ? AppColors.warning : AppColors.brand),
                ]),
                if (asRawList(student['groups']).isNotEmpty)
                  Text(asRawList(student['groups']).join(', '),
                      style: TextStyle(color: AppColors.muted, fontSize: 13)),
                if (student['parent'] == true && asText(student['parent_name']).isNotEmpty)
                  Text(asText(student['parent_name']), style: TextStyle(color: AppColors.muted, fontSize: 13)),
              ]),
            ),
            if (student['balance'] is num)
              Text(money(asDouble(student['balance'])),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: asDouble(student['balance']) < 0 ? AppColors.danger : AppColors.success,
                  )),
          ]),
        ),
        const SizedBox(height: AppSpacing.s),
      ],
      for (final lead in leads) ...<Widget>[
        AppCard(
          // Lid kartasi (crm/leads) kassirga yopiq — faqat direktor, administrator, marketolog.
          onTap: AppScope.of(context).canSeeLeads ? () => _push(context, LeadPage(leadId: asInt(lead['id']))) : null,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Row(children: <Widget>[
              const Icon(Icons.person_search_outlined, size: 20),
              const SizedBox(width: AppSpacing.s),
              Expanded(child: Text(asText(lead['name'], '—'), style: const TextStyle(fontWeight: FontWeight.w700))),
              Pill(leadStatusLabel(asText(lead['status'])), color: leadStatusColor(asText(lead['status']))),
            ]),
            if (asText(lead['interest']).isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.xs),
              Text(asText(lead['interest']), style: TextStyle(color: AppColors.muted, fontSize: 13)),
            ],
            for (final event in asList(lead['events'], 'events').take(3))
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text('${date(event['created_at'])} · ${tr(asText(event['body']))}',
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: AppColors.muted)),
              ),
          ]),
        ),
        const SizedBox(height: AppSpacing.s),
      ],
      if (tasks.isNotEmpty) ...<Widget>[
        SectionTitle(tr('Ochiq vazifalar')),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(children: <Widget>[
            for (var i = 0; i < tasks.length; i++) ...<Widget>[
              if (i > 0) const Divider(),
              ListTile(
                leading: const Icon(Icons.task_alt),
                title: Text(asText(tasks[i]['title'])),
                subtitle: tasks[i]['due_at'] != null ? Text(dateTime(tasks[i]['due_at'])) : null,
              ),
            ],
          ]),
        ),
      ],
      if (calls.isNotEmpty) ...<Widget>[
        SectionTitle(tr("So'nggi qo'ng'iroqlar")),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(children: <Widget>[
            for (var i = 0; i < calls.length; i++) ...<Widget>[
              if (i > 0) const Divider(),
              _CallRow(call: calls[i]),
            ],
          ]),
        ),
      ],
    ]);
  }
}

class _CallRow extends StatelessWidget {
  const _CallRow({required this.call, this.onTap});

  final Map<String, dynamic> call;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final incoming = asText(call['direction']) == 'in';
    final result = asText(call['result']);
    final answered = result == 'answered';
    final outcome = asText(call['outcome']);
    final operator = asText(asMap(call['user'])['name']);
    final color = answered ? AppColors.success : (incoming ? AppColors.danger : AppColors.muted);
    return ListTile(
      onTap: onTap,
      leading: Icon(incoming ? (answered ? Icons.call_received_rounded : Icons.call_missed_rounded) : Icons.call_made_rounded, color: color),
      title: Text(asText(call['phone'], '—'), style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Text(<String>[
          dateTime(call['created_at']),
          tr(callResultLabels[result] ?? result),
          if (answered && call['duration'] != null) callDuration(call['duration']),
          if (operator.isNotEmpty) operator,
        ].join(' · ')),
        if (asText(call['note']).isNotEmpty || asText(call['summary']).isNotEmpty)
          Text(asText(call['note']).isNotEmpty ? asText(call['note']) : asText(call['summary']),
              maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.ink, fontSize: 13)),
      ]),
      trailing: outcome.isEmpty ? null : Pill(tr(callOutcomeLabels[outcome] ?? outcome), color: _outcomeColor(outcome)),
    );
  }
}

Color _outcomeColor(String outcome) {
  if (outcome == 'trial' || outcome == 'enrolled' || outcome == 'interested') return AppColors.success;
  if (outcome == 'complaint' || outcome == 'not_interested') return AppColors.danger;
  if (outcome == 'callback' || outcome == 'payment') return AppColors.warning;
  return AppColors.brand;
}

// ---------------------------------------------------------------------------
// Natija
// ---------------------------------------------------------------------------

/// Qo'ng'iroq natijasini belgilash. true — saqlandi.
Future<bool> showOutcomeSheet(BuildContext context, CallCenterRepository repository, Map<String, dynamic> call) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet))),
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _OutcomeForm(repository: repository, call: call),
    ),
  );
  if (saved == true && context.mounted) showMessage(context, tr('Natija saqlandi.'));
  return saved == true;
}

class _OutcomeForm extends StatefulWidget {
  const _OutcomeForm({required this.repository, required this.call});

  final CallCenterRepository repository;
  final Map<String, dynamic> call;

  @override
  State<_OutcomeForm> createState() => _OutcomeFormState();
}

class _OutcomeFormState extends State<_OutcomeForm> {
  final TextEditingController _note = TextEditingController();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _interest = TextEditingController();
  String? _outcome;
  DateTime? _callbackAt;
  bool _saving = false;
  String? _error;

  /// Raqam hali hech kimga bog'lanmagan (jonli/navbatdagi qo'ng'iroqda `caller` bo'sh) — lid uchun ism so'raladi.
  bool get _unknown {
    final call = widget.call;
    if (call.containsKey('subject_type')) return call['subject_type'] == null;
    return asText(call['caller']).isEmpty;
  }

  @override
  void initState() {
    super.initState();
    final outcome = asText(widget.call['outcome']);
    if (callOutcomeLabels.containsKey(outcome)) _outcome = outcome;
    _note.text = asText(widget.call['note']);
  }

  @override
  void dispose() {
    _note.dispose();
    _name.dispose();
    _interest.dispose();
    super.dispose();
  }

  Future<void> _pickCallback() async {
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate: _callbackAt ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 90)),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_callbackAt ?? now.add(const Duration(hours: 1))),
    );
    if (time == null || !mounted) return;
    setState(() => _callbackAt = DateTime(day.year, day.month, day.day, time.hour, time.minute));
  }

  Future<void> _save() async {
    final outcome = _outcome;
    if (outcome == null) {
      setState(() => _error = tr('Natijani tanlang.'));
      return;
    }
    if (outcome == 'callback' && _callbackAt == null) {
      setState(() => _error = tr("Qayta qo'ng'iroq vaqtini kiriting."));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.outcome(
        asInt(widget.call['id']),
        outcome: outcome,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        callbackAt: _callbackAt,
        leadName: _name.text.trim().isEmpty ? null : _name.text.trim(),
        interest: _interest.text.trim().isEmpty ? null : _interest.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final outcome = _outcome;
    final askLead = _unknown && outcome != null && leadOutcomes.contains(outcome);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: <Widget>[
        Text(tr("Qo'ng'iroq natijasi"), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(asText(widget.call['phone']), style: TextStyle(color: AppColors.muted)),
        const SizedBox(height: AppSpacing.l),
        if (_error != null) ...<Widget>[
          Text(_error!, style: const TextStyle(color: AppColors.danger)),
          const SizedBox(height: AppSpacing.m),
        ],
        Wrap(spacing: AppSpacing.s, runSpacing: AppSpacing.s, children: <Widget>[
          for (final entry in callOutcomeLabels.entries)
            ChoiceChip(
              label: Text(tr(entry.value)),
              selected: outcome == entry.key,
              onSelected: (_) => setState(() => _outcome = entry.key),
            ),
        ]),
        if (outcome == 'callback') ...<Widget>[
          const SizedBox(height: AppSpacing.m),
          OutlinedButton.icon(
            onPressed: _pickCallback,
            icon: const Icon(Icons.schedule),
            label: Text(_callbackAt == null ? tr("Qayta qo'ng'iroq vaqti") : dateTime(_callbackAt!.toIso8601String())),
          ),
        ],
        if (askLead) ...<Widget>[
          const SizedBox(height: AppSpacing.m),
          Text(tr('Yangi lid yaratiladi'), style: TextStyle(color: AppColors.muted, fontSize: 13)),
          const SizedBox(height: AppSpacing.s),
          TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: InputDecoration(labelText: tr('Ismi'))),
          const SizedBox(height: AppSpacing.s),
          TextField(controller: _interest, decoration: InputDecoration(labelText: tr('Qiziqishi (kurs, fan)'))),
        ],
        const SizedBox(height: AppSpacing.m),
        TextField(controller: _note, maxLength: 255, decoration: InputDecoration(labelText: tr('Izoh (ixtiyoriy)'), counterText: '')),
        const SizedBox(height: AppSpacing.l),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
              : Text(tr('Saqlash')),
        ),
      ]),
    );
  }
}

/// Qo'lda qayd: PBX ulanmagan bo'lsa ham qo'ng'iroq jurnalga tushadi.
class _LogCallForm extends StatefulWidget {
  const _LogCallForm({required this.repository});

  final CallCenterRepository repository;

  @override
  State<_LogCallForm> createState() => _LogCallFormState();
}

class _LogCallFormState extends State<_LogCallForm> {
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _minutes = TextEditingController();
  String _direction = 'out';
  String _result = 'answered';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _minutes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final phone = _phone.text.trim();
    if (dialable(phone).replaceAll('+', '').length < 7) {
      setState(() => _error = tr("Telefon raqamini to'liq kiriting."));
      return;
    }
    final minutes = double.tryParse(_minutes.text.replaceAll(',', '.'));
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.logCall(
        phone: phone,
        direction: _direction,
        result: _result,
        duration: minutes == null ? null : (minutes * 60).round(),
      );
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: <Widget>[
        Text(tr("Qo'ng'iroqni qayd etish"), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: AppSpacing.l),
        if (_error != null) ...<Widget>[
          Text(_error!, style: const TextStyle(color: AppColors.danger)),
          const SizedBox(height: AppSpacing.m),
        ],
        TextField(
          controller: _phone,
          autofocus: true,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(labelText: tr('Telefon'), prefixIcon: const Icon(Icons.phone_outlined)),
        ),
        const SizedBox(height: AppSpacing.m),
        SegmentedButton<String>(
          segments: <ButtonSegment<String>>[
            ButtonSegment<String>(value: 'out', label: Text(tr('Chiquvchi')), icon: const Icon(Icons.call_made_rounded)),
            ButtonSegment<String>(value: 'in', label: Text(tr('Kiruvchi')), icon: const Icon(Icons.call_received_rounded)),
          ],
          selected: <String>{_direction},
          onSelectionChanged: (value) => setState(() => _direction = value.first),
        ),
        const SizedBox(height: AppSpacing.m),
        Wrap(spacing: AppSpacing.s, runSpacing: AppSpacing.s, children: <Widget>[
          for (final entry in callResultLabels.entries)
            ChoiceChip(
              label: Text(tr(entry.value)),
              selected: _result == entry.key,
              onSelected: (_) => setState(() => _result = entry.key),
            ),
        ]),
        if (_result == 'answered') ...<Widget>[
          const SizedBox(height: AppSpacing.m),
          TextField(
            controller: _minutes,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: tr('Davomiyligi (daqiqa)')),
          ),
        ],
        const SizedBox(height: AppSpacing.l),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
              : Text(tr('Saqlash')),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Navbat
// ---------------------------------------------------------------------------

class _QueueTab extends StatelessWidget {
  const _QueueTab({required this.viewKey, required this.repository, required this.onChanged});

  final GlobalKey<AsyncViewState<List<Map<String, dynamic>>>> viewKey;
  final CallCenterRepository repository;
  final Future<void> Function() onChanged;

  Future<void> _handled(BuildContext context, Map<String, dynamic> call) async {
    try {
      await repository.handled(asInt(call['id']));
      if (context.mounted) showMessage(context, tr('Hal qilindi deb belgilandi.'));
      await viewKey.currentState?.reload();
      unawaited(onChanged());
    } on ApiException catch (error) {
      if (context.mounted) showMessage(context, error.message, error: true);
    }
  }

  Future<void> _outcome(BuildContext context, Map<String, dynamic> call) async {
    if (await showOutcomeSheet(context, repository, call)) {
      await viewKey.currentState?.reload();
      unawaited(onChanged());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AsyncView<List<Map<String, dynamic>>>(
      key: viewKey,
      load: repository.queue,
      builder: (context, items, reload) {
        if (items.isEmpty) {
          return ListView(children: <Widget>[
            EmptyState(icon: Icons.phone_callback_outlined, text: tr("Javobsiz qo'ng'iroq yo'q. Hammasiga qayta qo'ng'iroq qilingan."))
          ]);
        }
        return ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.l),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.s),
          itemBuilder: (context, index) {
            final call = items[index];
            final phone = asText(call['phone']);
            final attempts = asInt(call['attempts'], 1);
            return AppCard(
              onTap: () => showCallerSheet(context, repository, phone, call: call),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Row(children: <Widget>[
                  const Icon(Icons.call_missed_rounded, color: AppColors.danger),
                  const SizedBox(width: AppSpacing.s),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                      Text(asText(call['caller']).isNotEmpty ? asText(call['caller']) : phone,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      Text(<String>[if (asText(call['caller']).isNotEmpty) phone, dateTime(call['created_at'])].join(' · '),
                          style: TextStyle(color: AppColors.muted, fontSize: 13)),
                    ]),
                  ),
                  if (attempts > 1) Pill(tr('{0} marta', <Object?>[attempts]), color: AppColors.danger),
                ]),
                const SizedBox(height: AppSpacing.m),
                Row(children: <Widget>[
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => launchUrl(Uri.parse('tel:${dialable(phone)}')),
                      icon: const Icon(Icons.call, size: 18),
                      label: Text(tr("Qo'ng'iroq"), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _outcome(context, call),
                      child: Text(tr('Natija'), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s),
                  IconButton.outlined(
                    tooltip: tr('Hal qilindi'),
                    onPressed: () => _handled(context, call),
                    icon: const Icon(Icons.done_rounded),
                  ),
                ]),
              ]),
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Jurnal
// ---------------------------------------------------------------------------

class _JournalTab extends StatefulWidget {
  const _JournalTab({required this.repository});

  final CallCenterRepository repository;

  @override
  State<_JournalTab> createState() => _JournalTabState();
}

class _JournalTabState extends State<_JournalTab> with AutomaticKeepAliveClientMixin {
  static const Map<String, String> _periodLabels = <String, String>{
    'today': 'Bugun',
    'week': '7 kun',
    'month': 'Shu oy',
  };

  String _period = 'today';
  final List<Map<String, dynamic>> _items = <Map<String, dynamic>>[];
  int _page = 1;
  int _lastPage = 1;
  bool _loading = true;
  bool _more = false;
  Object? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<String> _range() {
    final now = DateTime.now();
    if (_period == 'week') return <String>[isoDay(now.subtract(const Duration(days: 6))), isoDay(now)];
    if (_period == 'month') return <String>[isoDay(DateTime(now.year, now.month, 1)), isoDay(now)];
    return <String>[isoDay(now), isoDay(now)];
  }

  Future<void> _load({bool more = false}) async {
    final range = _range();
    setState(() {
      if (more) {
        _more = true;
      } else {
        _loading = true;
      }
      _error = null;
    });
    try {
      final page = more ? _page + 1 : 1;
      final data = await widget.repository.calls(from: range[0], to: range[1], page: page);
      if (!mounted) return;
      setState(() {
        if (!more) _items.clear();
        _items.addAll(asList(data));
        _page = asInt(data['current_page'], page);
        _lastPage = asInt(data['last_page'], page);
      });
    } catch (error) {
      if (!mounted) return;
      if (more) {
        showMessage(context, errorText(error), error: true);
      } else {
        setState(() => _error = error);
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _more = false;
        });
      }
    }
  }

  Future<void> _openCall(Map<String, dynamic> call) async {
    await showCallerSheet(context, widget.repository, asText(call['phone']), call: call);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final error = _error;
    Widget body;
    if (_loading && _items.isEmpty) {
      body = const SkeletonList();
    } else if (error != null && _items.isEmpty) {
      body = error is ApiException && error.isForbidden
          ? ForbiddenState(details: error.message, onRetry: _load)
          : ErrorState(message: errorText(error), onRetry: _load);
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        child: _items.isEmpty
            ? ListView(children: <Widget>[EmptyState(icon: Icons.call_outlined, text: tr("Bu davrda qo'ng'iroq yo'q."))])
            : ListView.separated(
                padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                itemCount: _items.length + (_page < _lastPage ? 1 : 0),
                separatorBuilder: (_, __) => const Divider(indent: 56),
                itemBuilder: (context, index) {
                  if (index >= _items.length) {
                    return Padding(
                      padding: const EdgeInsets.all(AppSpacing.l),
                      child: Center(
                        child: _more
                            ? const CircularProgressIndicator()
                            : OutlinedButton(onPressed: () => _load(more: true), child: Text(tr('Yana yuklash'))),
                      ),
                    );
                  }
                  return _CallRow(call: _items[index], onTap: () => _openCall(_items[index]));
                },
              ),
      );
    }
    return Column(children: <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.l, AppSpacing.m, AppSpacing.l, AppSpacing.s),
        child: Wrap(spacing: AppSpacing.s, children: <Widget>[
          for (final entry in _periodLabels.entries)
            ChoiceChip(
              label: Text(tr(entry.value)),
              selected: _period == entry.key,
              onSelected: (_) {
                setState(() => _period = entry.key);
                _load();
              },
            ),
        ]),
      ),
      Expanded(child: body),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Skriptlar
// ---------------------------------------------------------------------------

class _ScriptsTab extends StatelessWidget {
  const _ScriptsTab({required this.repository});

  final CallCenterRepository repository;

  @override
  Widget build(BuildContext context) {
    return AsyncView<List<Map<String, dynamic>>>(
      load: repository.scripts,
      builder: (context, scripts, reload) {
        if (scripts.isEmpty) {
          return ListView(children: <Widget>[
            EmptyState(icon: Icons.description_outlined, text: tr("Skriptlar hali qo'shilmagan. Ularni veb-versiyada direktor yoki administrator qo'shadi."))
          ]);
        }
        return ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.l),
          itemCount: scripts.length,
          separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.s),
          itemBuilder: (context, index) {
            final script = scripts[index];
            return AppCard(
              padding: EdgeInsets.zero,
              child: Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  leading: const Icon(Icons.description_outlined),
                  title: Text(asText(script['title']), style: const TextStyle(fontWeight: FontWeight.w700)),
                  childrenPadding: const EdgeInsets.fromLTRB(AppSpacing.l, 0, AppSpacing.l, AppSpacing.l),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SelectableText(asText(script['body']), style: TextStyle(color: AppColors.ink, height: 1.4)),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
