// Topshiriqlar (CRM; veb: «Topshiriqlar»): bugungi, muddati o'tgan, keyingi va bajarilgan. Bajarildi deb belgilash, yangi topshiriq qo'shish.
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

const Map<String, String> _tabLabels = <String, String>{
  'overdue': "Muddati o'tgan",
  'today': 'Bugun',
  'upcoming': 'Keyingi',
  'done': 'Bajarilgan',
};

class TasksPage extends StatefulWidget {
  const TasksPage({super.key, this.initialTab = 'today'});

  final String initialTab;

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  late String _tab = widget.initialTab;
  final GlobalKey<AsyncViewState<Map<String, dynamic>>> _view = GlobalKey<AsyncViewState<Map<String, dynamic>>>();

  Future<void> _complete(Map<String, dynamic> task) async {
    try {
      await AppScope.read(context).api.post('crm/tasks/${asInt(task['id'])}/complete', <String, Object?>{});
      if (!mounted) return;
      showMessage(context, tr('Vazifa bajarildi.'));
      await _view.currentState?.reload();
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    }
  }

  Future<void> _add() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _TaskForm(),
    );
    if (created == true) await _view.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final api = AppScope.of(context).api;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Topshiriqlar'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add_task),
        label: Text(tr('Vazifa')),
      ),
      body: AsyncView<Map<String, dynamic>>(
        key: _view,
        load: () async => asMap(await api.get('crm/tasks', query: <String, Object?>{'tab': _tab})),
        builder: (context, data, reload) {
          final counts = asMap(data['counts']);
          final tasks = asList(data['data']);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: <Widget>[
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: <Widget>[
                  for (final key in _tabLabels.keys)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text('${tr(_tabLabels[key]!)} ${asInt(counts[key])}'),
                        selected: _tab == key,
                        selectedColor: key == 'overdue' ? AppColors.soft(AppColors.danger) : AppColors.soft(AppColors.brand),
                        onSelected: (_) {
                          setState(() => _tab = key);
                          _view.currentState?.reload();
                        },
                      ),
                    ),
                ]),
              ),
              const SizedBox(height: 12),
              if (tasks.isEmpty) EmptyState(text: tr("Bu yerda vazifa yo'q."), icon: Icons.task_alt),
              for (final task in tasks) ...<Widget>[
                _TaskCard(task: task, onComplete: task['completed_at'] == null ? () => _complete(task) : null),
                const SizedBox(height: 10),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.task, this.onComplete});

  final Map<String, dynamic> task;
  final VoidCallback? onComplete;

  @override
  Widget build(BuildContext context) {
    final subject = asMap(task['subject']);
    final phone = asText(subject['phone']);
    final overdue = task['overdue'] == true;
    final done = task['completed_at'] != null;
    return AppCard(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        IconButton(
          onPressed: onComplete,
          icon: Icon(done ? Icons.check_circle : Icons.radio_button_unchecked, color: done ? AppColors.success : AppColors.muted),
          tooltip: tr('Bajarildi'),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(asText(task['title']),
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, decoration: done ? TextDecoration.lineThrough : null)),
            if (asText(task['note']).isNotEmpty) ...<Widget>[
              const SizedBox(height: 2),
              Text(asText(task['note']), style: TextStyle(color: AppColors.muted)),
            ],
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 4, children: <Widget>[
              if (task['due_at'] != null) Pill(dateTime(task['due_at']), color: overdue ? AppColors.danger : AppColors.brand),
              if (subject.isNotEmpty) Pill(asText(subject['name']), color: AppColors.muted),
              if (asMap(task['assignee'])['name'] != null) Pill(asText(asMap(task['assignee'])['name']), color: AppColors.muted),
            ]),
          ]),
        ),
        if (phone.isNotEmpty)
          IconButton(
            onPressed: () => launchUrl(Uri.parse('tel:${phone.replaceAll(RegExp(r'[^+\d]'), '')}')),
            icon: Icon(Icons.call, color: AppColors.success),
            tooltip: tr("Qo'ng'iroq qilish"),
          ),
      ]),
    );
  }
}

class _TaskForm extends StatefulWidget {
  const _TaskForm();

  @override
  State<_TaskForm> createState() => _TaskFormState();
}

class _TaskFormState extends State<_TaskForm> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _note = TextEditingController();
  DateTime _due = DateTime.now().add(const Duration(hours: 1));
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final day = await showDatePicker(context: context, initialDate: _due, firstDate: DateTime.now().subtract(const Duration(days: 1)), lastDate: DateTime.now().add(const Duration(days: 365)));
    if (day == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_due));
    if (!mounted) return;
    setState(() => _due = DateTime(day.year, day.month, day.day, time?.hour ?? _due.hour, time?.minute ?? _due.minute));
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      setState(() => _error = tr('Vazifa nomini yozing.'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await AppScope.read(context).api.post('crm/tasks', <String, Object?>{
        'title': _title.text.trim(),
        'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
        'due_at': '${isoDay(_due)} ${two(_due.hour)}:${two(_due.minute)}',
      });
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error.field('title') ?? error.message;
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
          Text(tr('Yangi vazifa'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          TextField(controller: _title, autofocus: true, decoration: InputDecoration(labelText: tr('Nima qilish kerak'), errorText: _error)),
          const SizedBox(height: 10),
          TextField(controller: _note, maxLines: 2, decoration: InputDecoration(labelText: tr('Izoh'))),
          const SizedBox(height: 10),
          OutlinedButton.icon(onPressed: _pick, icon: const Icon(Icons.schedule), label: Text('${isoDay(_due)} ${two(_due.hour)}:${two(_due.minute)}')),
          const SizedBox(height: 14),
          FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? tr('Saqlanmoqda...') : tr('Saqlash'))),
        ]),
      ),
    );
  }
}
