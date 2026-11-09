// 3.25 (server 2.58): «Qayta ro'yxat» paneli (rahbar, administrator). Kampaniya tanlanadi; umumiy natija, sinflar kesimida
// javoblar, o'quvchilar ro'yxati (ota-ona telefoni bilan qo'ng'iroq, javobni o'zi belgilash), javobsizlarga eslatma va
// bo'shagan o'ringa kutish ro'yxatidan taklif. Kampaniya yaratish va tahrirlash — vebda.
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/adaptive.dart';
import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

const List<String> _order = <String>['yes', 'thinking', 'pending', 'no'];

const Map<String, String> _labels = <String, String>{'yes': 'Davom etadi', 'thinking': "O'ylayapti", 'pending': "Javob yo'q", 'no': 'Ketadi'};

Color _color(String answer) => switch (answer) {
      'yes' => AppColors.success,
      'thinking' => AppColors.warning,
      'no' => AppColors.danger,
      _ => AppColors.muted,
    };

class ReEnrollAdminPage extends StatefulWidget {
  const ReEnrollAdminPage({super.key});

  @override
  State<ReEnrollAdminPage> createState() => _ReEnrollAdminPageState();
}

class _ReEnrollAdminPageState extends State<ReEnrollAdminPage> {
  List<Map<String, dynamic>> _campaigns = <Map<String, dynamic>>[];
  int? _current;
  Map<String, dynamic>? _board;
  String? _error;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final api = AppScope.read(context).api;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = asList(asMap(await api.get('reenroll'))['data'], 'data');
      final current = list.any((c) => asInt(c['id']) == _current) ? _current : (list.isEmpty ? null : asInt(list.first['id']));
      final board = current == null ? null : asMap(await api.get('reenroll/$current'));
      if (!mounted) return;
      setState(() {
        _campaigns = list;
        _current = current;
        _board = board;
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = errorText(error);
          _loading = false;
        });
      }
    }
  }

  Future<void> _remind() async {
    final api = AppScope.read(context).api;
    setState(() => _busy = true);
    try {
      final sent = asInt(asMap(await api.post('reenroll/$_current/remind'))['sent']);
      if (mounted) showMessage(context, sent > 0 ? tr('Eslatma yuborildi: {0} ta oila.', <Object>[sent]) : tr("Hozir eslatiladigan oila yo'q (yaqinda eslatilgan)."));
    } catch (error) {
      if (mounted) showMessage(context, errorText(error), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _offer(Map<String, dynamic> cls) async {
    final count = asInt(cls['no']) < asInt(cls['waiting']) ? asInt(cls['no']) : asInt(cls['waiting']);
    final ok = await confirm(context, tr("{0}: kutish ro'yxatidagi {1} kishiga joy taklif qilinsinmi?", <Object>[asText(cls['name']), count]));
    if (!ok || !mounted) return;
    final api = AppScope.read(context).api;
    try {
      final offered = asInt(asMap(await api.post('reenroll/$_current/offer-waitlist', <String, Object?>{'group_id': asInt(cls['group_id'])}))['offered']);
      if (mounted) showMessage(context, tr('Taklif yuborildi: {0} ta.', <Object>[offered]));
      await _load();
    } catch (error) {
      if (mounted) showMessage(context, errorText(error), error: true);
    }
  }

  Future<void> _openClass(Map<String, dynamic> cls) async {
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(
      builder: (_) => _ClassPage(cls: cls, editable: asText(asMap(_board?['campaign'])['status']) != 'draft'),
    ));
    if (changed == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: pageBar(context, title: Text(tr("Qayta ro'yxat"))),
      body: _loading
          ? const SkeletonList(count: 5)
          : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : _campaigns.isEmpty
                  ? ListView(children: <Widget>[
                      EmptyState(icon: Icons.event_available_outlined, text: tr("O'quv yili oxiriga 2–3 oy qolganda kampaniya oching: oilalar ilovada javob beradi.")),
                    ])
                  : RefreshIndicator(onRefresh: _load, child: _content(context)),
    );
  }

  Widget _content(BuildContext context) {
    final board = _board ?? <String, dynamic>{};
    final campaign = asMap(board['campaign']);
    final totals = asMap(board['totals']);
    final total = asInt(totals['total']);
    final classes = asList(board['classes'], 'classes');
    final reasons = asMap(totals['reasons']);
    final status = asText(campaign['status']);
    return ListView(
      padding: readable(context, const EdgeInsets.fromLTRB(16, 12, 16, 32)),
      children: <Widget>[
        if (_campaigns.length > 1)
          DropdownButtonFormField<int>(
            initialValue: _current,
            decoration: InputDecoration(labelText: tr('Kampaniya')),
            items: <DropdownMenuItem<int>>[for (final c in _campaigns) DropdownMenuItem<int>(value: asInt(c['id']), child: Text(asText(c['title'])))],
            onChanged: (value) {
              setState(() => _current = value);
              _load();
            },
          ),
        const SizedBox(height: 8),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
            Row(children: <Widget>[
              Expanded(child: Text(asText(campaign['title']), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
              Pill(tr(status == 'open' ? 'Ochiq' : status == 'draft' ? 'Qoralama' : 'Yopilgan'), color: status == 'open' ? AppColors.success : AppColors.muted),
            ]),
            const SizedBox(height: 4),
            Text(<String>[
              tr('Javob muddati: {0}', <Object>[date(campaign['deadline'])]),
              if (asInt(campaign['deposit']) > 0) tr('Avans: {0}', <Object>[money(asInt(campaign['deposit']))]),
            ].join(' · '), style: TextStyle(color: AppColors.muted)),
            if (status == 'draft') ...<Widget>[
              const SizedBox(height: 8),
              Text(tr("Tayyor bo'lsa vebda «Oilalarga yuborish» ni bosing."), style: TextStyle(color: AppColors.info)),
            ],
            if (total > 0) ...<Widget>[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  height: 10,
                  child: Row(children: <Widget>[
                    for (final k in _order)
                      if (asInt(totals[k]) > 0) Expanded(flex: asInt(totals[k]), child: Container(color: _color(k))),
                  ]),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
                for (final k in _order) Pill('${tr(_labels[k]!)}: ${asInt(totals[k])}', color: _color(k)),
                if (asInt(campaign['deposit']) > 0) Pill(tr("Avans to'ladi") + ': ${asInt(totals['deposit_paid'])}/${asInt(totals['yes'])}', color: AppColors.info, dot: false),
                if (campaign['contract'] != null) Pill(tr('Shartnoma tasdiqlandi') + ': ${asInt(totals['signed'])}/${asInt(totals['yes'])}', color: AppColors.info, dot: false),
              ]),
            ],
            if (status == 'open' && campaign['accepting'] == true) ...<Widget>[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _busy ? null : _remind,
                icon: const Icon(Icons.notifications_active_outlined),
                label: Text(tr('Javobsizlarga eslatish')),
              ),
            ],
          ]),
        ),
        if (reasons.isNotEmpty) ...<Widget>[
          SectionTitle(tr('Ketish sabablari')),
          Wrap(spacing: 6, runSpacing: 6, children: <Widget>[
            for (final entry in reasons.entries) Pill('${entry.key} · ${entry.value}', color: AppColors.danger, dot: false),
          ]),
        ],
        if (classes.isNotEmpty) SectionTitle(tr('Sinflar')),
        for (final cls in classes)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppCard(
              onTap: () => _openClass(cls),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
                Row(children: <Widget>[
                  Expanded(
                    child: Text(
                      cls['capacity'] == null ? asText(cls['name']) : '${asText(cls['name'])} · ${asInt(cls['total'])}/${asInt(cls['capacity'])}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ]),
                const SizedBox(height: 6),
                Text(
                  '${tr('Davom etadi')}: ${asInt(cls['yes'])} · ${tr('Ketadi')}: ${asInt(cls['no'])} · ${tr("Javob yo'q")}: ${asInt(cls['pending']) + asInt(cls['thinking'])}',
                  style: TextStyle(color: AppColors.muted, fontSize: 13),
                ),
                if (asInt(cls['no']) > 0 && asInt(cls['waiting']) > 0 && cls['group_id'] != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => _offer(cls),
                      icon: const Icon(Icons.how_to_reg_outlined, size: 18),
                      label: Text(tr('Navbatdagilarga taklif ({0})', <Object>[asInt(cls['waiting'])])),
                    ),
                  ),
              ]),
            ),
          ),
      ],
    );
  }
}

class _ClassPage extends StatefulWidget {
  const _ClassPage({required this.cls, required this.editable});

  final Map<String, dynamic> cls;
  final bool editable;

  @override
  State<_ClassPage> createState() => _ClassPageState();
}

class _ClassPageState extends State<_ClassPage> {
  late List<Map<String, dynamic>> _students = asList(widget.cls['students'], 'students');
  bool _changed = false;

  Future<void> _set(Map<String, dynamic> row, String answer) async {
    String? reason;
    if (answer == 'no') {
      final controller = TextEditingController(text: asText(row['reason']));
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text(tr('Sababi (ixtiyoriy)')),
          content: TextField(controller: controller, maxLength: 255, autofocus: true),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.pop(dialog, false), child: Text(tr('Bekor qilish'))),
            FilledButton(onPressed: () => Navigator.pop(dialog, true), child: Text(tr('Saqlash'))),
          ],
        ),
      );
      reason = controller.text.trim();
      controller.dispose();
      if (ok != true) return;
    }
    if (!mounted) return;
    final api = AppScope.read(context).api;
    try {
      final board = asMap(await api.put('reenroll/responses/${asInt(row['id'])}', <String, Object?>{'answer': answer, if (reason != null && reason.isNotEmpty) 'reason': reason}));
      final cls = asList(board['classes'], 'classes').firstWhere((c) => c['group_id'] == widget.cls['group_id'], orElse: () => widget.cls);
      if (!mounted) return;
      setState(() {
        _students = asList(cls['students'], 'students');
        _changed = true;
      });
      showMessage(context, tr('Saqlandi.'));
    } catch (error) {
      if (mounted) showMessage(context, errorText(error), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        appBar: pageBar(context, title: Text(asText(widget.cls['name']))),
        body: ListView.separated(
          padding: readable(context, const EdgeInsets.fromLTRB(16, 12, 16, 32)),
          itemCount: _students.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final row = _students[i];
            final answer = asText(row['answer'], 'pending');
            final guardians = asList(row['guardians'], 'guardians');
            final document = row['document'] is Map ? asMap(row['document']) : null;
            return AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
                Row(children: <Widget>[
                  Expanded(child: Text(asText(asMap(row['student'])['full_name']), style: const TextStyle(fontWeight: FontWeight.w700))),
                  Pill(tr(_labels[answer] ?? answer), color: _color(answer)),
                ]),
                if (asText(row['reason']).isNotEmpty) Text(asText(row['reason']), style: TextStyle(color: AppColors.danger, fontSize: 13)),
                if (answer == 'yes')
                  Wrap(spacing: 6, runSpacing: 6, children: <Widget>[
                    if (row['deposit_paid'] != null)
                      Pill(row['deposit_paid'] == true ? tr("Avans to'langan") : tr('Avans kutilmoqda'), color: row['deposit_paid'] == true ? AppColors.success : AppColors.warning, dot: false),
                    if (document != null)
                      Pill(asText(document['status']) == 'signed' ? tr('Shartnoma tasdiqlangan') : tr('Shartnoma kutilmoqda'),
                          color: asText(document['status']) == 'signed' ? AppColors.success : AppColors.warning, dot: false),
                  ]),
                for (final g in guardians)
                  if (asText(g['phone']).isNotEmpty)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.call_outlined),
                      title: Text(<String>[asText(g['name']), asText(g['phone'])].where((s) => s.isNotEmpty).join(' · ')),
                      onTap: () => launchUrl(Uri.parse('tel:${asText(g['phone']).replaceAll(RegExp(r'[^+\d]'), '')}')),
                    ),
                if (widget.editable)
                  Wrap(spacing: 6, runSpacing: 6, children: <Widget>[
                    for (final k in const <String>['yes', 'thinking', 'no'])
                      ChoiceChip(label: Text(tr(_labels[k]!)), selected: answer == k, onSelected: answer == k ? null : (_) => _set(row, k)),
                  ]),
              ]),
            );
          },
        ),
      ),
    );
  }
}
