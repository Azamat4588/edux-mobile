// Virtual laboratoriya (o'quvchi): topshiriq tasodifiy qiymatlar bilan, javob serverda tekshiriladi (3 ta urinish),
// to'g'ri javob uchun XP. API: GET /my/labs, POST /my/labs/{code}, POST /my/labs/runs/{run}.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

IconData _labIcon(String subject) {
  switch (subject) {
    case 'Kimyo':
      return Icons.science_rounded;
    case 'Biologiya':
      return Icons.eco_rounded;
    case 'Matematika':
      return Icons.functions_rounded;
    default:
      return Icons.bolt_rounded;
  }
}

Color _labColor(String subject) {
  switch (subject) {
    case 'Kimyo':
      return const Color(0xFF7C3AED);
    case 'Biologiya':
      return AppColors.success;
    case 'Matematika':
      return AppColors.warning;
    default:
      return AppColors.brand;
  }
}

/// Topshiriq parametrlarining nomlari (server kalitlari).
const Map<String, String> labParamLabels = <String, String>{
  'length': 'Ip uzunligi',
  'speed': 'Tezlik',
  'angle': 'Burchak',
  'voltage': 'Kuchlanish',
  'resistance': 'Qarshilik',
  'focus': 'Fokus masofasi',
  'distance': 'Buyum masofasi',
  'acid_volume': 'Kislota hajmi',
  'acid': 'Kislota konsentratsiyasi',
  'base': 'Ishqor konsentratsiyasi',
  'p1': '1-ota-ona',
  'p2': '2-ota-ona',
};

class LabsPage extends StatelessWidget {
  const LabsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final api = AppScope.of(context).api;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Virtual laboratoriya'))),
      body: AsyncView<List<Map<String, dynamic>>>(
        load: () async => asList(asMap(await api.get('my/labs'))['labs'], 'labs'),
        builder: (context, labs, reload) {
          if (labs.isEmpty) {
            return ListView(children: <Widget>[EmptyState(icon: Icons.science_outlined, text: tr("Laboratoriya ishlari hali yo'q."))]);
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: labs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final lab = labs[index];
              final subject = asText(lab['subject']);
              final color = _labColor(subject);
              final passed = asInt(lab['passed']);
              return AppCard(
                onTap: () async {
                  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => LabPage(lab: lab)));
                  await reload();
                },
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(color: color.withAlpha(30), borderRadius: BorderRadius.circular(12)),
                    child: Icon(_labIcon(subject), color: color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                      Text(tr(asText(lab['name'])), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      Text('${tr(subject)} · ${tr('{0}-sinf', <Object?>[asText(lab['grades'])])}',
                          style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13)),
                      const SizedBox(height: 4),
                      Text(tr(asText(lab['description'])), style: TextStyle(color: AppColors.muted, fontSize: 13)),
                      if (passed > 0) ...<Widget>[
                        const SizedBox(height: 6),
                        Pill(tr('{0} ta topshiriq bajarildi', <Object?>[passed]), color: AppColors.success),
                      ],
                    ]),
                  ),
                ]),
              );
            },
          );
        },
      ),
    );
  }
}

class LabPage extends StatefulWidget {
  const LabPage({super.key, required this.lab});

  final Map<String, dynamic> lab;

  @override
  State<LabPage> createState() => _LabPageState();
}

class _LabPageState extends State<LabPage> {
  final _answer = TextEditingController();
  Map<String, dynamic>? _task;
  Map<String, dynamic>? _feedback;
  bool _busy = false;
  String? _error;
  int _xp = 0;

  @override
  void initState() {
    super.initState();
    _newTask();
  }

  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  Future<void> _newTask() async {
    setState(() {
      _busy = true;
      _error = null;
      _feedback = null;
      _answer.clear();
    });
    try {
      final data = asMap(await AppScope.read(context).api.post('my/labs/${asText(widget.lab['code'])}'));
      if (mounted) setState(() => _task = data);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _check() async {
    final text = _answer.text.trim();
    if (text.isEmpty || _task == null) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = asMap(await AppScope.read(context).api.post('my/labs/runs/${asInt(_task!['run_id'])}', <String, Object?>{'answer': text}));
      if (!mounted) return;
      setState(() {
        _feedback = data;
        _xp += asInt(data['xp']);
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lab = widget.lab;
    final task = _task;
    final feedback = _feedback;
    final passed = feedback?['passed'] == true;
    final over = feedback != null && !passed && asInt(feedback['tries_left']) == 0;
    final params = asMap(task?['params']);
    final unit = asText(task?['unit']);
    return Scaffold(
      appBar: AppBar(title: Text(tr(asText(lab['name'])))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: <Widget>[
          Text(tr(asText(lab['description'])), style: TextStyle(color: AppColors.muted)),
          if (_xp > 0) ...<Widget>[
            const SizedBox(height: 8),
            Align(alignment: Alignment.centerLeft, child: Pill(tr('+{0} XP olindi', <Object?>[_xp]), color: AppColors.success)),
          ],
          const SizedBox(height: 14),
          if (task == null && _busy) const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
          if (task == null && !_busy && _error != null) ErrorState(message: _error!, onRetry: _newTask),
          if (task != null) ...<Widget>[
            AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Row(children: <Widget>[
                  Icon(Icons.assignment_outlined, color: AppColors.brand),
                  const SizedBox(width: 8),
                  Text(tr('Topshiriq'), style: const TextStyle(fontWeight: FontWeight.w800)),
                ]),
                const SizedBox(height: 10),
                MathText(asText(task['text']), style: TextStyle(fontSize: 16, color: AppColors.ink, height: 1.4)),
                if (params.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
                    for (final entry in params.entries)
                      Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text('${tr(labParamLabels[entry.key] ?? entry.key)}: ${entry.value}'),
                      ),
                  ]),
                ],
              ]),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _answer,
              enabled: !passed && !over && !_busy,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\- ]'))],
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              onSubmitted: (_) => _check(),
              decoration: InputDecoration(labelText: tr('Javobingiz'), suffixText: unit.isEmpty ? null : unit),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: AppColors.danger)),
            ],
            if (feedback != null) ...<Widget>[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.soft(passed ? AppColors.success : AppColors.danger),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(children: <Widget>[
                  Icon(passed ? Icons.check_circle_rounded : Icons.cancel_rounded, color: passed ? AppColors.success : AppColors.danger),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      passed
                          ? (asInt(feedback['xp']) > 0
                              ? tr("To'g'ri! +{0} XP", <Object?>[asInt(feedback['xp'])])
                              : tr("To'g'ri!"))
                          : over
                              ? tr("Urinishlar tugadi. To'g'ri javob: {0} {1}", <Object?>[number(asDouble(feedback['expected']), decimals: 3), unit])
                              : tr("Noto'g'ri. Yana {0} ta urinish qoldi.", <Object?>[asInt(feedback['tries_left'])]),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ]),
              ),
            ],
            const SizedBox(height: 16),
            if (passed || over)
              FilledButton.icon(onPressed: _busy ? null : _newTask, icon: const Icon(Icons.refresh_rounded), label: Text(tr('Yangi topshiriq')))
            else ...<Widget>[
              FilledButton(
                onPressed: _busy ? null : _check,
                child: _busy
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                    : Text(tr('Tekshirish')),
              ),
              const SizedBox(height: 8),
              TextButton(onPressed: _busy ? null : _newTask, child: Text(tr('Boshqa topshiriq'))),
            ],
          ],
        ],
      ),
    );
  }
}
