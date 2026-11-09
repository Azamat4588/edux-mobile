// 3.24 (server 2.57/2.59): lidga mos guruh va yakka dars. Qulay kunlar (Du..Ya), vaqt oralig'i va daraja —
// PUT crm/leads/{id}/preferences; natija — GET crm/leads/{id}/matches; sinov — POST .../trial yoki .../trial-slot.
import 'package:flutter/material.dart';

import '../../core/adaptive.dart';
import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

const List<String> _weekdays = <String>['Du', 'Se', 'Ch', 'Pa', 'Ju', 'Sh', 'Ya'];

class LeadMatchPage extends StatefulWidget {
  const LeadMatchPage({super.key, required this.leadId, required this.lead});

  final int leadId;
  final Map<String, dynamic> lead;

  @override
  State<LeadMatchPage> createState() => _LeadMatchPageState();
}

class _LeadMatchPageState extends State<LeadMatchPage> {
  late Set<int> _days = asRawList(widget.lead['preferred_days']).map((d) => asInt(d)).where((d) => d >= 1 && d <= 7).toSet();
  late String _from = asText(widget.lead['preferred_from']);
  late String _to = asText(widget.lead['preferred_to']);
  late final TextEditingController _level = TextEditingController(text: asText(widget.lead['level']));
  Map<String, dynamic>? _data;
  String? _error;
  bool _busy = false;
  bool _changed = false;

  static const List<(String, String, String)> _parts = <(String, String, String)>[
    ('Ertalab', '08:00', '12:00'),
    ('Tushdan keyin', '12:00', '17:00'),
    ('Kechqurun', '17:00', '21:00'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _level.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = asMap(await AppScope.read(context).api.get('crm/leads/${widget.leadId}/matches'));
      if (mounted) setState(() => _data = data);
    } catch (error) {
      if (mounted) setState(() => _error = errorText(error));
    }
  }

  Future<void> _search() async {
    final api = AppScope.read(context).api;
    setState(() => _busy = true);
    try {
      final days = _days.toList()..sort();
      final data = asMap(await api.put('crm/leads/${widget.leadId}/preferences', <String, Object?>{
        'preferred_days': days,
        'preferred_from': _from.isEmpty ? null : _from,
        'preferred_to': _to.isEmpty ? null : _to,
        'level': _level.text.trim().isEmpty ? null : _level.text.trim(),
      }));
      if (mounted) {
        setState(() {
          _data = data;
          _changed = false;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) showMessage(context, errorText(error), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickTime(bool start) async {
    final current = start ? _from : _to;
    final parts = current.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: parts.length == 2 ? TimeOfDay(hour: int.tryParse(parts[0]) ?? 17, minute: int.tryParse(parts[1]) ?? 0) : TimeOfDay(hour: start ? 17 : 20, minute: 0),
    );
    if (picked == null || !mounted) return;
    final text = '${two(picked.hour)}:${two(picked.minute)}';
    setState(() {
      if (start) {
        _from = text;
      } else {
        _to = text;
      }
      _changed = true;
    });
  }

  Future<void> _trialGroup(Map<String, dynamic> group) async {
    final ok = await confirm(context, tr('{0}: {1} ga sinov darsiga yozilsinmi?', <Object>[asText(group['name']), dateTime(group['next_lesson'])]), action: tr('Sinovga yozish'));
    if (!ok || !mounted) return;
    final api = AppScope.read(context).api;
    setState(() => _busy = true);
    try {
      await api.post('crm/leads/${widget.leadId}/trial', <String, Object?>{'group_id': asInt(group['id'])});
      if (!mounted) return;
      showMessage(context, tr('{0}: sinov darsiga yozildi ({1}).', <Object>[asText(widget.lead['full_name']), asText(group['name'])]));
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) showMessage(context, errorText(error), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _trialSlot(Map<String, dynamic> slot) async {
    final ok = await confirm(context, tr('{0}, {1} — yakka sinov darsi bron qilinsinmi?', <Object>[dateTime(slot['starts_at']), asText(slot['teacher'])]), action: tr('Bron qilish'));
    if (!ok || !mounted) return;
    final api = AppScope.read(context).api;
    setState(() => _busy = true);
    try {
      await api.post('crm/leads/${widget.leadId}/trial-slot', <String, Object?>{'teacher_id': asInt(slot['teacher_id']), 'starts_at': asText(slot['starts_at'])});
      if (!mounted) return;
      showMessage(context, tr('{0}: yakka sinov darsi bron qilindi ({1}).', <Object>[asText(widget.lead['full_name']), asText(slot['teacher'])]));
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) showMessage(context, errorText(error), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final groups = data == null ? <Map<String, dynamic>>[] : asList(data['groups'], 'groups');
    final slots = data == null ? <Map<String, dynamic>>[] : asList(data['slots'], 'slots');
    return Scaffold(
      appBar: pageBar(context, title: Text(tr('Mos guruh'))),
      body: ListView(
        padding: readable(context, const EdgeInsets.fromLTRB(16, 12, 16, 32)),
        children: <Widget>[
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
              Text(tr('Qulay kunlar va vaqt'), style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: <Widget>[
                for (var i = 0; i < 7; i++)
                  FilterChip(
                    label: Text(tr(_weekdays[i])),
                    selected: _days.contains(i + 1),
                    onSelected: (on) => setState(() {
                      _days = <int>{..._days};
                      if (on) {
                        _days.add(i + 1);
                      } else {
                        _days.remove(i + 1);
                      }
                      _changed = true;
                    }),
                  ),
              ]),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: <Widget>[
                for (final part in _parts)
                  ChoiceChip(
                    label: Text(tr(part.$1)),
                    selected: _from == part.$2 && _to == part.$3,
                    onSelected: (_) => setState(() {
                      final same = _from == part.$2 && _to == part.$3;
                      _from = same ? '' : part.$2;
                      _to = same ? '' : part.$3;
                      _changed = true;
                    }),
                  ),
              ]),
              const SizedBox(height: 8),
              Row(children: <Widget>[
                Expanded(child: OutlinedButton(onPressed: () => _pickTime(true), child: Text(_from.isEmpty ? tr('dan') : _from))),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('–')),
                Expanded(child: OutlinedButton(onPressed: () => _pickTime(false), child: Text(_to.isEmpty ? tr('gacha') : _to))),
              ]),
              const SizedBox(height: 8),
              TextField(
                controller: _level,
                maxLength: 40,
                onChanged: (_) => setState(() => _changed = true),
                decoration: InputDecoration(labelText: tr('Daraja'), hintText: tr('Masalan: A2, Beginner, 9-sinf')),
              ),
              FilledButton.icon(
                onPressed: _busy ? null : _search,
                icon: const Icon(Icons.search),
                label: Text(_changed ? tr('Saqlash va qidirish') : tr('Qayta qidirish')),
              ),
            ]),
          ),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: ErrorState(message: _error!, onRetry: _load)),
          if (data == null && _error == null) const Padding(padding: EdgeInsets.only(top: 12), child: SkeletonList(count: 3)),
          if (data != null) ...<Widget>[
            SectionTitle(tr('Mos guruhlar')),
            if (groups.isEmpty)
              EmptyState(icon: Icons.group_off_outlined, text: tr("Bo'sh joyi bor mos guruh topilmadi. Kunlar yoki vaqtni kengaytiring yoki yangi nabor oching."))
            else
              for (final group in groups)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AppCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
                      Row(children: <Widget>[
                        Expanded(child: Text(asText(group['name']), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
                        if (asText(group['level']).isNotEmpty) Pill(asText(group['level']), color: AppColors.info, dot: false),
                      ]),
                      Text(
                        <String>[
                          asText(group['course']),
                          <String>[asText(group['days']), asText(group['time'])].where((s) => s.isNotEmpty).join(' · '),
                          asText(group['teacher']),
                        ].where((s) => s.isNotEmpty).join(' · '),
                        style: TextStyle(color: AppColors.muted, fontSize: 13),
                      ),
                      const SizedBox(height: 6),
                      Wrap(spacing: 6, runSpacing: 6, children: <Widget>[
                        for (final reason in asRawList(group['reasons']))
                          Pill(tr(asText(reason)), color: asText(reason) == 'Daraja boshqa' ? AppColors.warning : AppColors.success, dot: false),
                        Pill(group['free_seats'] == null ? tr('Joy cheklanmagan') : tr('{0} ta joy', <Object>[asInt(group['free_seats'])]), color: AppColors.muted, dot: false),
                      ]),
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: _busy || group['next_lesson'] == null ? null : () => _trialGroup(group),
                        child: Text(group['next_lesson'] == null ? tr('Sinovga yozish') : '${tr('Sinovga yozish')} · ${dateTime(group['next_lesson'])}'),
                      ),
                    ]),
                  ),
                ),
            if (slots.isNotEmpty) ...<Widget>[
              SectionTitle(tr("Yakka dars: ustozlarning bo'sh vaqti")),
              Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
                for (final slot in slots)
                  ActionChip(
                    avatar: const Icon(Icons.schedule, size: 18),
                    label: Text('${dateTime(slot['starts_at'])} · ${asText(slot['teacher'])}'),
                    onPressed: _busy ? null : () => _trialSlot(slot),
                  ),
              ]),
            ],
          ],
        ],
      ),
    );
  }
}
