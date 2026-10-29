// Virtual laboratoriya (o'quvchi, 3.7 / server 1.39 — 462 lab, 15 fan): ro'yxat serverdan (GET my/labs — yangi lablar
// ilovani yangilamasdan chiqadi). «Fanlar bo'yicha» — fan → sinf guruhlari (guruhda 6 ta + «Yana»), qidiruv nom, tavsif va
// darslik mavzusi bo'yicha; «Darslik bo'yicha» — GET fun/labs/topics?subject=&grade= (darslik → bob → mavzu → lablar).
// Lab bosilganda interaktiv tajriba ilova ichidagi WebView'da ochiladi (veb /labs/{code}, shu foydalanuvchi tokeni bilan);
// «Topshiriq» — tasodifiy qiymatli masala, javob serverda tekshiriladi (3 ta urinish), XP. API: POST /my/labs/{code}, /my/labs/runs/{run}.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/adaptive.dart';
import '../../core/api.dart';
import '../../core/external_links.dart';
import '../../core/format.dart';
import '../../core/help_links.dart';
import '../../core/i18n.dart';
import '../../core/labs.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/webview_guard.dart';
import '../../core/widgets.dart';

/// Fan ikonkasi (server `subject` kaliti — o'zbekcha nom, tarjima qilinmaydi).
IconData labIcon(String subject) {
  switch (subject) {
    case 'Kimyo':
      return Icons.science_rounded;
    case 'Biologiya':
      return Icons.eco_rounded;
    case 'Matematika':
      return Icons.functions_rounded;
    case 'Informatika':
      return Icons.memory_rounded;
    case 'Geografiya':
      return Icons.public_rounded;
    case 'Astronomiya':
      return Icons.nightlight_round;
    case 'Tarix':
      return Icons.history_edu_rounded;
    case 'Ona tili':
      return Icons.spellcheck_rounded;
    case 'Ingliz tili':
      return Icons.translate_rounded;
    case 'Texnologiya':
      return Icons.handyman_rounded;
    case 'Chizmachilik':
      return Icons.architecture_rounded;
    case 'Iqtisodiyot':
      return Icons.trending_up_rounded;
    case 'Musiqa':
      return Icons.music_note_rounded;
    case "Tasviriy san'at":
      return Icons.palette_rounded;
    case 'Tabiiy fanlar':
      return Icons.park_rounded;
    default:
      return Icons.bolt_rounded;
  }
}

/// Fan rangi (v3 — koshin oilasi): fan belgisi plitkasi foni va «fan, sinf» yozuvi.
Color labColor(String subject) {
  switch (subject) {
    case 'Kimyo':
      return Koshin.olxori;
    case 'Biologiya':
      return Koshin.pista;
    case 'Matematika':
      return const Color(0xFFB45F00);
    case 'Fizika':
      return Koshin.lojuvard;
    case 'Informatika':
      return Koshin.feruza;
    case 'Geografiya':
      return const Color(0xFF0B8576);
    case 'Astronomiya':
      return const Color(0xFF5149DC);
    case 'Tarix':
      return const Color(0xFF9A5B13);
    case 'Ona tili':
      return const Color(0xFF2D6FB8);
    case 'Ingliz tili':
      return Koshin.anor;
    case 'Texnologiya':
      return const Color(0xFF556378);
    case 'Chizmachilik':
      return const Color(0xFF3D52A8);
    case 'Iqtisodiyot':
      return const Color(0xFF0F7A5A);
    case 'Musiqa':
      return const Color(0xFF7446E6);
    case "Tasviriy san'at":
      return const Color(0xFFD2560C);
    case 'Tabiiy fanlar':
      return const Color(0xFF4C7D12);
    default:
      return AppColors.accent;
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

/// Guruhda dastlab ko'rinadigan lablar (qolgani «Yana N ta»).
const int _labsPerGroup = 6;

/// Qidiruv natijalari sahifasi.
const int _searchPage = 30;

class LabsPage extends StatefulWidget {
  const LabsPage({super.key, this.initialTab = 0});

  /// 0 — fanlar bo'yicha, 1 — darslik bo'yicha.
  final int initialTab;

  @override
  State<LabsPage> createState() => _LabsPageState();
}

class _LabsPageState extends State<LabsPage> {
  @override
  Widget build(BuildContext context) {
    final api = AppScope.of(context).api;
    return DefaultTabController(
      length: 2,
      initialIndex: widget.initialTab.clamp(0, 1),
      child: Scaffold(
        appBar: pageBar(context,
          title: Text(tr('Laboratoriya')),
          actions: const <Widget>[HelpButton(HelpLinks.labs)],
          bottom: TabBar(tabs: <Widget>[Tab(text: tr("Fanlar bo'yicha")), Tab(text: tr("Darslik bo'yicha"))]),
        ),
        body: AsyncView<List<Map<String, dynamic>>>(
          cacheKey: 'my_labs_v139',
          decode: (raw) => asList(raw),
          load: () async => asList(asMap(await api.get('my/labs'))['labs'], 'labs'),
          refreshable: false,
          builder: (context, labs, reload) {
            if (labs.isEmpty) {
              return ListView(children: <Widget>[EmptyState(icon: Icons.science_outlined, text: tr("Laboratoriya ishlari hali yo'q."))]);
            }
            return TabBarView(children: <Widget>[
              RefreshIndicator(onRefresh: reload, child: LabsCatalogView(labs: labs, onChanged: reload)),
              LabsTextbookView(labs: labs, onChanged: reload),
            ]);
          },
        ),
      ),
    );
  }
}

/// «Fanlar bo'yicha»: qidiruv, fan tanlovi, sinf guruhlari (skrinshot testlari ham shu vidjetni chizadi).
class LabsCatalogView extends StatefulWidget {
  const LabsCatalogView({super.key, required this.labs, required this.onChanged, this.initialSubject});

  final List<Map<String, dynamic>> labs;
  final Future<void> Function() onChanged;
  final String? initialSubject;

  @override
  State<LabsCatalogView> createState() => _LabsCatalogViewState();
}

class _LabsCatalogViewState extends State<LabsCatalogView> with AutomaticKeepAliveClientMixin {
  final TextEditingController _search = TextEditingController();
  late String? _subject = widget.initialSubject;
  final Set<String> _expanded = <String>{};
  int _shown = _searchPage;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _pick(String? subject) => setState(() {
        _subject = subject;
        _expanded.clear();
      });

  Widget _grid(List<Map<String, dynamic>> labs) => AdaptiveGrid(
        minTile: 320,
        minColumns: 1,
        maxColumns: 3,
        spacing: 10,
        children: <Widget>[for (final lab in labs) LabCard(lab: lab, onChanged: widget.onChanged)],
      );

  Widget _more(String key, int hidden) => Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => setState(() => _expanded.add(key)),
          icon: const Icon(Icons.expand_more),
          label: Text(tr('Yana {0} ta', <Object?>[hidden])),
        ),
      );

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final labs = widget.labs;
    final subjects = labSubjects(labs);
    final query = _search.text.trim();
    final children = <Widget>[];
    if (query.isNotEmpty) {
      final found = labs.where((lab) => (_subject == null || asText(lab['subject']) == _subject) && labMatches(lab, query)).toList();
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
        child: Text(tr('Topildi: {0}', <Object?>[found.length]), style: TextStyle(color: AppColors.muted)),
      ));
      if (found.isEmpty) {
        children.add(EmptyState(icon: Icons.search_off_rounded, text: tr("Hech narsa topilmadi. Qidiruv so'zini yoki filtrni o'zgartirib ko'ring.")));
      } else {
        children.add(_grid(found.take(_shown).toList()));
        if (found.length > _shown) {
          children.add(Center(
            child: TextButton(
              onPressed: () => setState(() => _shown += _searchPage),
              child: Text(tr('Yana {0} ta', <Object?>[found.length - _shown])),
            ),
          ));
        }
      }
    } else if (_subject == null) {
      // Hamma fanlar: har fan — 6 ta lab va «Yana» (fanni tanlaydi).
      for (final subject in subjects) {
        final list = labs.where((lab) => asText(lab['subject']) == subject).toList();
        children
          ..add(SectionTitle(
            labSubjectLabel(list.first),
            trailing: list.length > _labsPerGroup
                ? TextButton(onPressed: () => _pick(subject), child: Text(tr('Hammasi ({0})', <Object?>[list.length])))
                : Text('${list.length}', style: TextStyle(color: AppColors.subtle, fontWeight: FontWeight.w600)),
          ))
          ..add(_grid(list.take(_labsPerGroup).toList()));
      }
    } else {
      final list = labs.where((lab) => asText(lab['subject']) == _subject).toList();
      for (final entry in labsByGrade(list).entries) {
        final key = '$_subject/${entry.key}';
        final open = _expanded.contains(key);
        children
          ..add(SectionTitle(tr('{0}-sinf', <Object?>[entry.key]), trailing: Text('${entry.value.length}', style: TextStyle(color: AppColors.subtle, fontWeight: FontWeight.w600))))
          ..add(_grid(open ? entry.value : entry.value.take(_labsPerGroup).toList()));
        if (!open && entry.value.length > _labsPerGroup) children.add(_more(key, entry.value.length - _labsPerGroup));
      }
    }
    return ListView(
      padding: readable(context, const EdgeInsets.fromLTRB(16, 8, 16, 32), max: kGridWidth),
      children: <Widget>[
        TextField(
          controller: _search,
          textInputAction: TextInputAction.search,
          onChanged: (_) => setState(() => _shown = _searchPage),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: tr('Lab nomi yoki darslik mavzusi'),
            isDense: true,
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    tooltip: tr('Tozalash'),
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _search.clear()),
                  ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 48,
          child: ListView(scrollDirection: Axis.horizontal, children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(tr('Hammasi ({0})', <Object?>[labs.length])),
                selected: _subject == null,
                onSelected: (_) => _pick(null),
              ),
            ),
            for (final subject in subjects)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  avatar: Icon(labIcon(subject), size: 16, color: _subject == subject ? null : labColor(subject)),
                  label: Text(labSubjectLabel(labs.firstWhere((lab) => asText(lab['subject']) == subject))),
                  selected: _subject == subject,
                  onSelected: (_) => _pick(subject),
                ),
              ),
          ]),
        ),
        ...children,
      ],
    );
  }
}

/// «Darslik bo'yicha»: fan va sinf tanlanadi, darslik → bob → mavzu → lablar (GET fun/labs/topics).
class LabsTextbookView extends StatefulWidget {
  const LabsTextbookView({super.key, required this.labs, required this.onChanged, this.initialSubject, this.tree});

  final List<Map<String, dynamic>> labs;
  final Future<void> Function() onChanged;
  final String? initialSubject;

  /// Oldindan olingan daraxt (skrinshot uchun); bo'lmasa serverdan.
  final Map<String, dynamic>? tree;

  @override
  State<LabsTextbookView> createState() => _LabsTextbookViewState();
}

class _LabsTextbookViewState extends State<LabsTextbookView> with AutomaticKeepAliveClientMixin {
  late String _subject = widget.initialSubject ?? (labSubjects(widget.labs).isEmpty ? '' : labSubjects(widget.labs).first);
  int _grade = 0;
  final Map<String, Map<String, dynamic>> _trees = <String, Map<String, dynamic>>{};
  bool _loading = false;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final tree = widget.tree;
    if (tree != null) {
      _trees[_subject] = tree;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  Future<void> _load() async {
    final subject = _subject;
    if (subject.isEmpty || _trees.containsKey(subject) || !mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tree = asMap(await AppScope.read(context).api.get('fun/labs/topics', query: <String, Object?>{'subject': subject}));
      if (!mounted) return;
      setState(() => _trees[subject] = tree);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _pick(String subject) {
    setState(() {
      _subject = subject;
      _grade = 0;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final labs = widget.labs;
    final subjects = labSubjects(labs);
    final byCode = <String, Map<String, dynamic>>{for (final lab in labs) asText(lab['code']): lab};
    final tree = _trees[_subject];
    final grades = tree == null ? <int>[] : textbookGrades(tree);
    final grade = grades.contains(_grade) ? _grade : (grades.isEmpty ? 0 : grades.first);
    final books = tree == null ? <Map<String, dynamic>>[] : asList(tree['books'], 'books').where((book) => asInt(book['grade']) == grade).toList();
    String label(String subject) => labSubjectLabel(labs.firstWhere((lab) => asText(lab['subject']) == subject, orElse: () => <String, dynamic>{'subject': subject}));
    return ListView(
      padding: readable(context, const EdgeInsets.fromLTRB(16, 12, 16, 32)),
      children: <Widget>[
        DropdownButtonFormField<String>(
          key: ValueKey<String>('subject-$_subject'),
          initialValue: subjects.contains(_subject) ? _subject : null,
          isExpanded: true,
          decoration: InputDecoration(labelText: tr('Fan'), prefixIcon: Icon(labIcon(_subject), color: labColor(_subject))),
          items: <DropdownMenuItem<String>>[
            for (final subject in subjects) DropdownMenuItem<String>(value: subject, child: Text(label(subject))),
          ],
          onChanged: (value) {
            if (value != null) _pick(value);
          },
        ),
        const SizedBox(height: 10),
        if (grades.isNotEmpty)
          SizedBox(
            height: 48,
            child: ListView(scrollDirection: Axis.horizontal, children: <Widget>[
              for (final item in grades)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(tr('{0}-sinf', <Object?>[item])),
                    selected: item == grade,
                    onSelected: (_) => setState(() => _grade = item),
                  ),
                ),
            ]),
          ),
        if (_loading && tree == null) const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
        if (_error != null && tree == null) ErrorState(message: _error!, onRetry: _load),
        if (tree != null && books.isEmpty)
          EmptyState(icon: Icons.menu_book_outlined, text: tr("Bu fan uchun darslik mavzulari hali kiritilmagan. «Fanlar bo'yicha» ro'yxatidan tanlang.")),
        for (final book in books) ...<Widget>[
          SectionTitle(asText(book['book'])),
          for (final chapter in asList(book['chapters'], 'chapters'))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppCard(
                padding: EdgeInsets.zero,
                child: Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    initiallyExpanded: chapterLabCount(chapter) > 0 && asList(book['chapters'], 'chapters').length <= 3,
                    title: Text(asText(chapter['chapter']), style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(tr('{0} ta mavzuda lab bor', <Object?>[chapterLabCount(chapter)]), style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      for (final topic in asList(chapter['topics'], 'topics')) _TopicRow(topic: topic, labs: topicLabs(topic, byCode), onChanged: widget.onChanged),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _TopicRow extends StatelessWidget {
  const _TopicRow({required this.topic, required this.labs, required this.onChanged});

  final Map<String, dynamic> topic;
  final List<Map<String, dynamic>> labs;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Text(asText(topic['topic']), style: TextStyle(color: labs.isEmpty ? AppColors.muted : AppColors.ink, fontWeight: FontWeight.w600)),
        if (labs.isNotEmpty) ...<Widget>[
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: <Widget>[
            for (final lab in labs)
              ActionChip(
                avatar: Icon(labIcon(asText(lab['subject'])), size: 16, color: labColor(asText(lab['subject']))),
                label: Text(asText(lab['name'])),
                onPressed: () async {
                  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => LabWebPage(code: asText(lab['code']), title: asText(lab['name']))));
                  await onChanged();
                },
              ),
          ]),
        ],
      ]),
    );
  }
}

class LabCard extends StatelessWidget {
  const LabCard({super.key, required this.lab, required this.onChanged});

  final Map<String, dynamic> lab;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final subject = asText(lab['subject']);
    final color = labColor(subject);
    final passed = asInt(lab['passed']);
    final topic = labTopicLine(lab);
    return AppCard(
      onTap: () async {
        await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => LabWebPage(code: asText(lab['code']), title: asText(lab['name']))));
        await onChanged();
      },
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        // Fan belgisi — to'liq rangli koshin plitka (veb: lab katalogi).
        IconTile(icon: labIcon(subject), colors: StatusColors(Colors.white, color), size: 46),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(asText(lab['name']), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.ink, height: 1.25)),
            const SizedBox(height: 2),
            Text('${labSubjectLabel(lab)}, ${tr('{0}-sinf', <Object?>[asText(lab['grades'])])}',
                style: TextStyle(color: readableOn(AppColors.dark ? Color.lerp(color, Colors.white, 0.45)! : color, AppColors.card), fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 4),
            Text(asText(lab['description']), maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.muted, fontSize: 13)),
            if (topic.isNotEmpty) ...<Widget>[
              const SizedBox(height: 4),
              Row(children: <Widget>[
                Icon(Icons.menu_book_outlined, size: 14, color: AppColors.muted),
                const SizedBox(width: 4),
                Expanded(child: Text(topic, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.muted, fontSize: 12))),
              ]),
            ],
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
      appBar: pageBar(context,
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
    // Qiymatlar topshiriq matnida bor; chiplar faqat nomi ma'lum parametrlar uchun (yangi lablar kalitlari xom ko'rinmasin).
    final params = Map<String, dynamic>.fromEntries(asMap(task?['params']).entries.where((entry) => labParamLabels.containsKey(entry.key)));
    final unit = asText(task?['unit']);
    return Scaffold(
      appBar: pageBar(context, title: Text(tr(asText(lab['name'])))),
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
