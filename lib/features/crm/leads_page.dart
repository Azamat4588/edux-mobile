// Lidlar (CRM): holat bo'yicha ro'yxat, qidiruv, qo'ng'iroq, holatni o'zgartirish, izoh va yangi lid.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

const List<(String, String)> leadStatuses = <(String, String)>[
  ('new', 'Yangi'),
  ('contacted', "Bog'lanildi"),
  ('trial', 'Sinov darsi'),
  ('enrolled', "O'quvchi bo'ldi"),
  ('lost', 'Rad etdi'),
];

String leadStatusLabel(String status) => tr(leadStatuses.firstWhere((item) => item.$1 == status, orElse: () => (status, status)).$2);

Color leadStatusColor(String status) => switch (status) {
      'new' => AppColors.brand,
      'contacted' => AppColors.warning,
      'trial' => const Color(0xFF7C3AED),
      'enrolled' => AppColors.success,
      _ => AppColors.muted,
    };

class LeadsPage extends StatefulWidget {
  const LeadsPage({super.key});

  @override
  State<LeadsPage> createState() => _LeadsPageState();
}

class _LeadsPageState extends State<LeadsPage> {
  String? _status = 'new';
  String _search = '';
  Timer? _debounce;
  final GlobalKey<AsyncViewState<Map<String, dynamic>>> _view = GlobalKey<AsyncViewState<Map<String, dynamic>>>();

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _reload() => _view.currentState?.reload();

  Future<void> _open(Map<String, dynamic> lead) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => LeadPage(leadId: asInt(lead['id']))));
    _reload();
  }

  Future<void> _add() async {
    final created = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, builder: (_) => const _LeadForm());
    if (created == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final api = AppScope.of(context).api;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Lidlar'))),
      floatingActionButton: FloatingActionButton.extended(onPressed: _add, icon: const Icon(Icons.person_add_alt_1), label: Text(tr('Lid'))),
      body: Column(children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: tr('Ism yoki telefon')),
            onChanged: (value) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 400), () {
                _search = value.trim();
                _reload();
              });
            },
          ),
        ),
        Expanded(
          child: AsyncView<Map<String, dynamic>>(
            key: _view,
            load: () async => asMap(await api.get('crm/leads', query: <String, Object?>{'status': _status, 'search': _search, 'archived': 0})),
            builder: (context, data, reload) {
              final counts = asMap(data['counts']);
              final leads = asList(data['data']);
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                children: <Widget>[
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: <Widget>[
                      for (final (key, label) in leadStatuses)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text('${tr(label)} ${asInt(counts[key])}'),
                            selected: _status == key,
                            selectedColor: AppColors.soft(leadStatusColor(key)),
                            onSelected: (_) {
                              setState(() => _status = _status == key ? null : key);
                              _reload();
                            },
                          ),
                        ),
                    ]),
                  ),
                  const SizedBox(height: 10),
                  if (leads.isEmpty) EmptyState(text: tr("Lid topilmadi."), icon: Icons.person_search_outlined),
                  for (final lead in leads) ...<Widget>[
                    AppCard(
                      onTap: () => _open(lead),
                      child: Row(children: <Widget>[
                        Avatar(asText(lead['full_name'], '?'), color: leadStatusColor(asText(lead['status']))),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                            Text(asText(lead['full_name'], asText(lead['phone'])), style: const TextStyle(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text(
                              <String>[asText(lead['phone']), asText(lead['source_name']), date(lead['created_at'])].where((item) => item.isNotEmpty).join(' · '),
                              style: TextStyle(color: AppColors.muted, fontSize: 13),
                            ),
                          ]),
                        ),
                        Pill(leadStatusLabel(asText(lead['status'])), color: leadStatusColor(asText(lead['status']))),
                      ]),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              );
            },
          ),
        ),
      ]),
    );
  }
}

class LeadPage extends StatefulWidget {
  const LeadPage({super.key, required this.leadId});

  final int leadId;

  @override
  State<LeadPage> createState() => _LeadPageState();
}

class _LeadPageState extends State<LeadPage> {
  final GlobalKey<AsyncViewState<Map<String, dynamic>>> _view = GlobalKey<AsyncViewState<Map<String, dynamic>>>();
  final TextEditingController _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _status(String status) async {
    try {
      await AppScope.read(context).api.post('crm/leads/${widget.leadId}/status', <String, Object?>{'status': status});
      if (!mounted) return;
      showMessage(context, tr('Holat saqlandi.'));
      await _view.currentState?.reload();
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    }
  }

  Future<void> _addNote() async {
    final text = _note.text.trim();
    if (text.isEmpty) return;
    try {
      await AppScope.read(context).api.post('crm/leads/${widget.leadId}/notes', <String, Object?>{'body': text});
      _note.clear();
      await _view.currentState?.reload();
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = AppScope.of(context).api;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Lid'))),
      body: AsyncView<Map<String, dynamic>>(
        key: _view,
        load: () async => asMap(await api.get('crm/leads/${widget.leadId}')),
        builder: (context, lead, reload) {
          final phone = asText(lead['phone']).replaceAll(RegExp(r'[^+\d]'), '');
          final status = asText(lead['status']);
          final events = asList(lead['events']);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              AppCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  Row(children: <Widget>[
                    Expanded(child: Text(asText(lead['full_name'], '—'), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800))),
                    Pill(leadStatusLabel(status), color: leadStatusColor(status)),
                  ]),
                  const SizedBox(height: 8),
                  KeyValue(tr('Telefon'), asText(lead['phone'], '—')),
                  KeyValue(tr('Manba'), asText(lead['source_name'], '—')),
                  if (asText(lead['interest']).isNotEmpty) KeyValue(tr('Qiziqishi'), asText(lead['interest'])),
                  if (asMap(lead['assignee'])['name'] != null) KeyValue(tr("Mas'ul"), asText(asMap(lead['assignee'])['name'])),
                  if (asText(lead['note']).isNotEmpty) KeyValue(tr('Izoh'), asText(lead['note'])),
                  KeyValue(tr("Qo'shilgan"), dateTime(lead['created_at'])),
                  if (phone.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 10),
                    Row(children: <Widget>[
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => launchUrl(Uri.parse('tel:$phone')),
                          icon: const Icon(Icons.call),
                          label: Text(tr("Qo'ng'iroq"))),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => launchUrl(Uri.parse('sms:$phone')),
                          icon: const Icon(Icons.sms_outlined),
                          label: Text(tr('SMS'))),
                      ),
                    ]),
                  ],
                ]),
              ),
              if (lead['student_id'] == null) ...<Widget>[
                SectionTitle(tr('Holat')),
                Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
                  for (final (key, label) in leadStatuses.where((item) => item.$1 != 'enrolled'))
                    ChoiceChip(
                      label: Text(tr(label)),
                      selected: status == key,
                      selectedColor: AppColors.soft(leadStatusColor(key)),
                      onSelected: status == key ? null : (_) => _status(key),
                    ),
                ]),
              ],
              SectionTitle(tr('Tarix va izohlar')),
              Row(children: <Widget>[
                Expanded(child: TextField(controller: _note, decoration: InputDecoration(hintText: tr('Izoh yozing')))),
                const SizedBox(width: 8),
                IconButton.filled(onPressed: _addNote, icon: const Icon(Icons.send)),
              ]),
              const SizedBox(height: 10),
              for (final event in events)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                    Icon(Icons.circle, size: 8, color: AppColors.brand),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                        Text(asText(event['body'], asText(event['text']))),
                        Text(
                          <String>[dateTime(event['created_at']), asText(event['user'])].where((item) => item.isNotEmpty).join(' · '),
                          style: TextStyle(color: AppColors.muted, fontSize: 12),
                        ),
                      ]),
                    ),
                  ]),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _LeadForm extends StatefulWidget {
  const _LeadForm();

  @override
  State<_LeadForm> createState() => _LeadFormState();
}

class _LeadFormState extends State<_LeadForm> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _phone = TextEditingController(text: '+998 ');
  final TextEditingController _interest = TextEditingController();
  List<Map<String, dynamic>> _sources = <Map<String, dynamic>>[];
  String? _source;
  bool _saving = false;
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    _loadSources();
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _interest.dispose();
    super.dispose();
  }

  Future<void> _loadSources() async {
    try {
      final data = asMap(await AppScope.read(context).api.get('crm/lookups'));
      final sources = asList(data['sources']).where((item) => item['is_active'] != false).toList();
      if (!mounted) return;
      setState(() {
        _sources = sources;
        _source = sources.isEmpty ? null : asText(sources.first['key']);
      });
    } catch (_) {}
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await AppScope.read(context).api.post('crm/leads', <String, Object?>{
        'full_name': _name.text.trim(),
        'phone': _phone.text.replaceAll(RegExp(r'[^+\d]'), ''),
        'source': _source,
        'interest': _interest.text.trim().isEmpty ? null : _interest.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          Text(tr('Yangi lid'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          TextField(controller: _name, autofocus: true, decoration: InputDecoration(labelText: tr('Ism'), errorText: _error?.field('full_name'))),
          const SizedBox(height: 10),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(labelText: tr('Telefon'), errorText: _error?.field('phone')),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            key: ValueKey<int>(_sources.length),
            initialValue: _source,
            items: _sources
                .map((item) => DropdownMenuItem<String>(value: asText(item['key']), child: Text(tr(asText(item['name'])))))
                .toList(),
            onChanged: (value) => setState(() => _source = value),
            decoration: InputDecoration(labelText: tr('Qayerdan'), errorText: _error?.field('source')),
          ),
          const SizedBox(height: 10),
          TextField(controller: _interest, decoration: InputDecoration(labelText: tr('Qiziqishi / izoh'))),
          if (_error != null && _error!.errors.isEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(_error!.message, style: const TextStyle(color: AppColors.danger)),
          ],
          const SizedBox(height: 14),
          FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? tr('Saqlanmoqda...') : tr('Saqlash'))),
        ]),
      ),
    );
  }
}
