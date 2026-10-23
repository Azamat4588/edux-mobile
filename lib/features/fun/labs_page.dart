// Virtual laboratoriya (o'quvchi): 38 ta lab katalogi fan bo'yicha filtr bilan (GET /my/labs). Lab bosilganda interaktiv
// tajriba ilova ichidagi WebView'da ochiladi (veb /labs/{code} sahifasi, shu foydalanuvchi tokeni bilan); «Topshiriq» —
// tasodifiy qiymatli masala, javob serverda tekshiriladi (3 ta urinish), XP. API: POST /my/labs/{code}, /my/labs/runs/{run}.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/api.dart';
import '../../core/external_links.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/webview_guard.dart';
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

/// Lablar katalogidagi fanlar (server tartibida, takrorsiz).
List<String> labSubjects(List<Map<String, dynamic>> labs) {
  final result = <String>[];
  for (final lab in labs) {
    final subject = asText(lab['subject']);
    if (subject.isNotEmpty && !result.contains(subject)) result.add(subject);
  }
  return result;
}

class LabsPage extends StatefulWidget {
  const LabsPage({super.key});

  @override
  State<LabsPage> createState() => _LabsPageState();
}

class _LabsPageState extends State<LabsPage> {
  String? _subject;

  @override
  Widget build(BuildContext context) {
    final api = AppScope.of(context).api;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Laboratoriya'))),
      body: AsyncView<List<Map<String, dynamic>>>(
        cacheKey: 'my_labs',
        decode: (raw) => asList(raw),
        load: () async => asList(asMap(await api.get('my/labs'))['labs'], 'labs'),
        builder: (context, labs, reload) {
          if (labs.isEmpty) {
            return ListView(children: <Widget>[EmptyState(icon: Icons.science_outlined, text: tr("Laboratoriya ishlari hali yo'q."))]);
          }
          final subjects = labSubjects(labs);
          final shown = _subject == null ? labs : labs.where((lab) => asText(lab['subject']) == _subject).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: <Widget>[
              SizedBox(
                height: 48,
                child: ListView(scrollDirection: Axis.horizontal, children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(tr('Hammasi ({0})', <Object?>[labs.length])),
                      selected: _subject == null,
                      onSelected: (_) => setState(() => _subject = null),
                    ),
                  ),
                  for (final subject in subjects)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        avatar: Icon(_labIcon(subject), size: 16, color: _labColor(subject)),
                        label: Text(tr(subject)),
                        selected: _subject == subject,
                        onSelected: (_) => setState(() => _subject = subject),
                      ),
                    ),
                ]),
              ),
              const SizedBox(height: 6),
              for (final lab in shown) ...<Widget>[
                _LabCard(lab: lab, onChanged: reload),
                const SizedBox(height: 10),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _LabCard extends StatelessWidget {
  const _LabCard({required this.lab, required this.onChanged});

  final Map<String, dynamic> lab;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final subject = asText(lab['subject']);
    final color = _labColor(subject);
    final passed = asInt(lab['passed']);
    return AppCard(
      onTap: () async {
        await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => LabWebPage(code: asText(lab['code']), title: tr(asText(lab['name'])))));
        await onChanged();
      },
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(color: color.withAlpha(30), borderRadius: BorderRadius.circular(AppRadius.control)),
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
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: <Widget>[
              if (passed > 0) Pill(tr('{0} ta topshiriq bajarildi', <Object?>[passed]), color: AppColors.success),
              TextButton.icon(
                style: TextButton.styleFrom(minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 8)),
                onPressed: () async {
                  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => LabPage(lab: lab)));
                  await onChanged();
                },
                icon: const Icon(Icons.calculate_outlined, size: 18),
                label: Text(tr('Topshiriq')),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }
}

/// Labning interaktiv sahifasi (veb /labs/{code}) ilova ichida. Kirish — shu ilovadagi token (veb `edu.token`).
class LabWebPage extends StatefulWidget {
  const LabWebPage({super.key, required this.code, required this.title});

  final String code;
  final String title;

  @override
  State<LabWebPage> createState() => _LabWebPageState();
}

class _LabWebPageState extends State<LabWebPage> {
  WebViewController? _controller;
  int _progress = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  void _open() {
    final session = AppScope.read(context);
    final server = session.server.replaceAll(RegExp(r'/+$'), '');
    // Tokenni veb-ilova xotirasiga yozib, lab sahifasiga o'tadigan kichik sahifa (shu server manzilida).
    final html = '<!doctype html><html><head><meta name="viewport" content="width=device-width"></head><body><script>'
        'try{localStorage.setItem("edu.token",${jsonEncode(session.token ?? '')});'
        'localStorage.setItem("edu.organization",${jsonEncode('${session.organizationId ?? ''}')});'
        'localStorage.setItem("edu.locale",${jsonEncode(I18n.locale)});}catch(e){}'
        'location.replace(${jsonEncode('/labs/${Uri.encodeComponent(widget.code)}')});'
        '</script></body></html>';
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (value) {
          if (mounted) setState(() => _progress = value);
        },
        // Boshqa saytga havola — tashqi brauzerda emas, shu yerda ochilmaydi.
        onNavigationRequest: (request) {
          // sms:, SMSTO:, tel: ... — telefonning o'z ilovasida.
          if (isSystemLink(request.url)) {
            openSystemLink(request.url);
            return NavigationDecision.prevent;
          }
          // Faqat shu server (aynan origin): token yozilgan localStorage boshqa saytga ochilmasin.
          return sameOrigin(request.url, server) || request.url.startsWith('about:')
              ? NavigationDecision.navigate
              : NavigationDecision.prevent;
        },
      ))
      ..loadHtmlString(html, baseUrl: '$server/');
    setState(() => _controller = controller);
  }

  @override
  void dispose() {
    // Lab yopildi — token WebView xotirasida qolmasin (keyingi ochilishda qayta yoziladi).
    clearWebViewData();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: <Widget>[
          if (controller != null) IconButton(tooltip: tr('Yangilash'), onPressed: controller.reload, icon: const Icon(Icons.refresh)),
        ],
        bottom: _progress > 0 && _progress < 100
            ? PreferredSize(preferredSize: const Size.fromHeight(3), child: LinearProgressIndicator(value: _progress / 100, minHeight: 3))
            : null,
      ),
      body: controller == null ? const Center(child: CircularProgressIndicator()) : WebViewWidget(controller: controller),
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
              Text(_error!, style: TextStyle(color: AppColors.danger)),
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
