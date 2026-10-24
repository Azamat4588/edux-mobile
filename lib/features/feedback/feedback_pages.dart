// Mijozlar fikri (1.39, docs/feedback.md): «Fikr bildirish» (turi, yo'nalishi, kimga tegishli, baho, rasm, anonim),
// «Mening fikrlarim» (holat va markaz javoblari) va rahbariyatning «Fikrlar» paneli (ro'yxat, filtr, tafsilot, javob,
// ichki izoh, mas'ul, holat). iPad'da panel ikki ustunli (ro'yxat + tafsilot, lib/core/adaptive.dart).
// API: GET feedback/meta, POST feedback, GET my/feedback(/{id}), GET feedback(/{id}), PATCH feedback/{id},
// POST feedback/{id}/notes, POST feedback/{id}/reply. Toza mantiq — lib/core/feedback.dart.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/adaptive.dart';
import '../../core/api.dart';
import '../../core/feedback.dart';
import '../../core/format.dart';
import '../../core/help_links.dart';
import '../../core/i18n.dart';
import '../../core/push.dart';
import '../../core/session.dart';
import '../../core/support.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../support/support_page.dart';

IconData feedbackKindIcon(String kind) {
  switch (kind) {
    case 'complaint':
      return Icons.report_gmailerrorred_outlined;
    case 'suggestion':
      return Icons.lightbulb_outline_rounded;
    case 'bug':
      return Icons.bug_report_outlined;
    case 'thanks':
      return Icons.favorite_border_rounded;
    default:
      return Icons.help_outline_rounded;
  }
}

Color feedbackKindColor(String kind) {
  switch (kind) {
    case 'complaint':
      return AppColors.danger;
    case 'suggestion':
      return AppColors.brand;
    case 'bug':
      return AppColors.warning;
    case 'thanks':
      return AppColors.success;
    default:
      return const Color(0xFF7C3AED);
  }
}

Color feedbackStatusColor(String status) {
  switch (feedbackStatusTone(status)) {
    case 'warning':
      return AppColors.warning;
    case 'brand':
      return AppColors.brand;
    case 'success':
      return AppColors.success;
    default:
      return AppColors.muted;
  }
}

/// Fikr kontekstidagi ilova ma'lumoti (`context[app|app_version|page]`).
Map<String, String> feedbackAppContext(String page) {
  String app;
  try {
    app = Platform.isIOS ? 'ios' : 'android';
  } catch (_) {
    app = 'android';
  }
  return supportContext(app: app, version: PushService.appVersion, page: page);
}

/// Baho (1–5 yulduz). [onChanged] null bo'lsa — faqat ko'rsatadi.
class FeedbackStars extends StatelessWidget {
  const FeedbackStars({super.key, required this.value, this.onChanged, this.size = 28});

  final int value;
  final ValueChanged<int>? onChanged;
  final double size;

  @override
  Widget build(BuildContext context) {
    final change = onChanged;
    return Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
      for (var i = 1; i <= 5; i++)
        change == null
            ? Icon(i <= value ? Icons.star_rounded : Icons.star_outline_rounded, size: size, color: i <= value ? AppColors.warning : AppColors.muted)
            : IconButton(
                tooltip: tr('{0} baho', <Object?>[i]),
                visualDensity: VisualDensity.compact,
                onPressed: () => change(i == value ? 0 : i),
                icon: Icon(i <= value ? Icons.star_rounded : Icons.star_outline_rounded, size: size, color: i <= value ? AppColors.warning : AppColors.muted),
              ),
    ]);
  }
}

/// Biriktirilgan rasmlar (token bilan ochiq manzil — Authorization kerak emas).
class FeedbackAttachments extends StatelessWidget {
  const FeedbackAttachments({super.key, required this.files});

  final List<Map<String, dynamic>> files;

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
      for (final file in files)
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => ImageViewerPage(url: asText(file['url']), title: asText(file['name'])),
          )),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              asText(file['url']),
              width: 96,
              height: 96,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 96,
                height: 96,
                color: AppColors.surface2,
                child: Icon(Icons.broken_image_outlined, color: AppColors.muted),
              ),
            ),
          ),
        ),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Yuboruvchi: «Fikr bildirish» va «Mening fikrlarim»
// ---------------------------------------------------------------------------

class MyFeedbackPage extends StatefulWidget {
  const MyFeedbackPage({super.key, this.initialTab = 0});

  /// 0 — yangi fikr, 1 — mening fikrlarim.
  final int initialTab;

  @override
  State<MyFeedbackPage> createState() => _MyFeedbackPageState();
}

class _MyFeedbackPageState extends State<MyFeedbackPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this, initialIndex: widget.initialTab.clamp(0, 1));
  final GlobalKey<AsyncViewState<Map<String, dynamic>>> _list = GlobalKey<AsyncViewState<Map<String, dynamic>>>();

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _sent() async {
    _tabs.animateTo(1);
    await _list.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final api = AppScope.of(context).api;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Fikr bildirish')),
        actions: const <Widget>[HelpButton(HelpLinks.feedback)],
        bottom: TabBar(controller: _tabs, tabs: <Widget>[Tab(text: tr('Yangi fikr')), Tab(text: tr('Mening fikrlarim'))]),
      ),
      body: TabBarView(controller: _tabs, children: <Widget>[
        FeedbackForm(onSent: _sent),
        AsyncView<Map<String, dynamic>>(
          key: _list,
          load: () async => asMap(await api.get('my/feedback')),
          builder: (context, data, reload) => MyFeedbackList(data: data, onChanged: reload),
        ),
      ]),
    );
  }
}

/// Yangi fikr formasi (`GET feedback/meta` → `POST feedback`).
class FeedbackForm extends StatefulWidget {
  const FeedbackForm({super.key, required this.onSent, this.meta});

  final Future<void> Function() onSent;

  /// Oldindan olingan meta (skrinshot va testlar uchun); bo'lmasa serverdan.
  final Map<String, dynamic>? meta;

  @override
  State<FeedbackForm> createState() => _FeedbackFormState();
}

class _FeedbackFormState extends State<FeedbackForm> with AutomaticKeepAliveClientMixin {
  final TextEditingController _body = TextEditingController();
  Map<String, dynamic>? _meta;
  String? _loadError;
  String _kind = '';
  String _category = '';
  int _rating = 0;
  bool _anonymous = false;
  int _student = 0;
  int _group = 0;
  int _teacher = 0;
  bool _busy = false;
  String? _error;
  final List<PickedImage> _files = <PickedImage>[];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final meta = widget.meta;
    if (meta != null) {
      _apply(meta);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  void _apply(Map<String, dynamic> meta) {
    _meta = meta;
    final kinds = feedbackLabels(meta, 'kinds', feedbackKindLabels);
    if (!kinds.containsKey(_kind)) _kind = kinds.isEmpty ? 'question' : kinds.keys.first;
    final targets = FeedbackTargets.fromMeta(meta);
    // Bitta farzand (yoki o'quvchining o'zi) — oldindan tanlanadi.
    if (_student == 0 && targets.students.length == 1) _student = asInt(targets.students.first['id']);
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loadError = null);
    try {
      final meta = asMap(await AppScope.read(context).api.get('feedback/meta'));
      if (mounted) setState(() => _apply(meta));
    } on ApiException catch (error) {
      if (mounted) setState(() => _loadError = error.message);
    }
  }

  SupportAttachmentRules get _rules => SupportAttachmentRules.fromMeta(_meta ?? <String, dynamic>{});

  Future<void> _attach() async {
    final picked = await pickImages(context, _rules, _files.length);
    if (picked.isNotEmpty && mounted) setState(() => _files.addAll(picked));
  }

  Future<void> _send() async {
    final problem = feedbackBodyError(_body.text);
    if (problem != null) {
      setState(() => _error = tr(problem));
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final api = AppScope.read(context).api;
    final payload = feedbackPayload(
      kind: _kind,
      body: _body.text,
      category: _category,
      rating: _rating,
      anonymous: _anonymous,
      studentId: _student,
      groupId: _group,
      teacherId: _teacher,
      context: feedbackAppContext('feedback'),
    );
    try {
      final data = asMap(_files.isEmpty
          ? await api.post('feedback', payload)
          : await api.multipart('feedback', fields: supportFields(feedbackMultipartPayload(payload)), files: imageMultipartFiles(_files)));
      if (!mounted) return;
      showMessage(context, asText(data['message'], tr('Fikringiz markaz rahbariyatiga yuborildi.')));
      setState(() {
        _body.clear();
        _files.clear();
        _rating = 0;
        _category = '';
        _anonymous = false;
      });
      await widget.onSent();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.field('body') ?? error.field('anonymous') ?? error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _dropdown({required String label, required int value, required List<Map<String, dynamic>> items, required ValueChanged<int> onChanged, String Function(Map<String, dynamic>)? title}) {
    final ids = items.map((item) => asInt(item['id'])).toSet();
    return DropdownButtonFormField<int>(
      key: ValueKey<String>('$label-$value-${items.length}'),
      initialValue: ids.contains(value) ? value : 0,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: <DropdownMenuItem<int>>[
        DropdownMenuItem<int>(value: 0, child: Text(tr('Tanlanmagan'), style: TextStyle(color: AppColors.muted))),
        for (final item in items)
          DropdownMenuItem<int>(
            value: asInt(item['id']),
            child: Text(title == null ? asText(item['name']) : title(item), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: _busy ? null : (next) => onChanged(next ?? 0),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final meta = _meta;
    if (meta == null) {
      if (_loadError != null) return ErrorState(message: _loadError!, onRetry: _load);
      return const SkeletonList();
    }
    if (meta['enabled'] == false || meta['can_submit'] == false) {
      return ListView(children: <Widget>[
        EmptyState(icon: Icons.rate_review_outlined, text: tr("Markazda fikr yuborish hozircha o'chirilgan.")),
      ]);
    }
    final kinds = feedbackLabels(meta, 'kinds', feedbackKindLabels);
    final categories = asRawList(meta['categories']).map((item) => '$item').where((item) => item.isNotEmpty).toList();
    final targets = FeedbackTargets.fromMeta(meta);
    final rules = _rules;
    final groupTeacher = _group > 0 ? targets.teacherOfGroup(_group) : 0;
    final teacherName = groupTeacher == 0
        ? ''
        : asText(targets.groups.firstWhere((group) => asInt(group['id']) == _group, orElse: () => <String, dynamic>{})['teacher']);
    return ListView(
      padding: readable(context, const EdgeInsets.fromLTRB(16, 16, 16, 32), max: 720),
      children: <Widget>[
        Text(tr("Fikringiz faqat markaz rahbariyatiga boradi. Javob shu yerda — «Mening fikrlarim» bo'limida ko'rinadi."),
            style: TextStyle(color: AppColors.muted)),
        const SizedBox(height: 16),
        Text(tr('Fikr turi'), style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
          for (final entry in kinds.entries)
            ChoiceChip(
              avatar: Icon(feedbackKindIcon(entry.key), size: 18, color: _kind == entry.key ? Colors.white : feedbackKindColor(entry.key)),
              label: Text(tr(entry.value)),
              selected: _kind == entry.key,
              showCheckmark: false,
              selectedColor: feedbackKindColor(entry.key),
              labelStyle: TextStyle(fontWeight: FontWeight.w600, color: _kind == entry.key ? Colors.white : AppColors.ink),
              onSelected: _busy ? null : (_) => setState(() => _kind = entry.key),
            ),
        ]),
        const SizedBox(height: 16),
        if (categories.isNotEmpty) ...<Widget>[
          DropdownButtonFormField<String>(
            key: ValueKey<String>('category-$_category-${categories.length}'),
            initialValue: categories.contains(_category) ? _category : '',
            isExpanded: true,
            decoration: InputDecoration(labelText: tr("Yo'nalish")),
            items: <DropdownMenuItem<String>>[
              DropdownMenuItem<String>(value: '', child: Text(tr('Tanlanmagan'), style: TextStyle(color: AppColors.muted))),
              for (final category in categories) DropdownMenuItem<String>(value: category, child: Text(tr(category))),
            ],
            onChanged: _busy ? null : (value) => setState(() => _category = value ?? ''),
          ),
          const SizedBox(height: 12),
        ],
        if (!targets.isEmpty) ...<Widget>[
          Text(tr('Kimga tegishli (ixtiyoriy)'), style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (targets.students.length > 1) ...<Widget>[
            _dropdown(label: tr('Farzand'), value: _student, items: targets.students, onChanged: (value) => setState(() => _student = value)),
            const SizedBox(height: 12),
          ],
          if (targets.groups.isNotEmpty) ...<Widget>[
            _dropdown(
              label: tr('Guruh'),
              value: _group,
              items: targets.groups,
              onChanged: (value) => setState(() {
                _group = value;
                if (value > 0) _teacher = 0;
              }),
            ),
            const SizedBox(height: 12),
          ],
          if (_group > 0 && teacherName.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12, left: 4),
              child: Text(tr("O'qituvchi: {0}", <Object?>[teacherName]), style: TextStyle(color: AppColors.muted)),
            )
          else if (targets.teachers.isNotEmpty) ...<Widget>[
            _dropdown(label: tr("O'qituvchi"), value: _teacher, items: targets.teachers, onChanged: (value) => setState(() => _teacher = value)),
            const SizedBox(height: 12),
          ],
        ],
        Row(children: <Widget>[
          Expanded(child: Text(tr('Baho (ixtiyoriy)'), style: const TextStyle(fontWeight: FontWeight.w700))),
          FeedbackStars(value: _rating, onChanged: _busy ? null : (value) => setState(() => _rating = value)),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: _body,
          minLines: 5,
          maxLines: 12,
          maxLength: 3000,
          enabled: !_busy,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: tr('Fikringiz'), alignLabelWithHint: true, hintText: tr('Nima bo\'ldi, qachon va qayerda — batafsil yozing.')),
        ),
        if (rules.allowed) ...<Widget>[
          if (_files.isNotEmpty) ...<Widget>[
            PickedImageStrip(items: _files, onRemove: (i) => setState(() => _files.removeAt(i))),
            const SizedBox(height: 8),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _busy || _files.length >= rules.maxFiles ? null : _attach,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text(tr('Rasm biriktirish ({0}/{1})', <Object?>[_files.length, rules.maxFiles])),
            ),
          ),
        ],
        if (meta['anonymous'] == true)
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _anonymous,
            onChanged: _busy ? null : (value) => setState(() => _anonymous = value),
            title: Text(tr('Anonim yuborish')),
            subtitle: Text(tr("Rahbariyat ismingiz va telefoningizni ko'rmaydi."), style: TextStyle(color: AppColors.muted, fontSize: 13)),
          ),
        if (_error != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: AppColors.danger)),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _busy ? null : _send,
          icon: _busy
              ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.onBrand))
              : const Icon(Icons.send_rounded),
          label: Text(tr('Yuborish')),
        ),
      ],
    );
  }
}

/// «Mening fikrlarim» ro'yxati (`GET my/feedback`).
class MyFeedbackList extends StatelessWidget {
  const MyFeedbackList({super.key, required this.data, required this.onChanged});

  final Map<String, dynamic> data;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final items = asList(data);
    final kinds = feedbackLabels(data, 'kinds', feedbackKindLabels);
    final statuses = feedbackLabels(data, 'statuses', feedbackStatusLabels);
    if (items.isEmpty) {
      return ListView(children: <Widget>[
        EmptyState(icon: Icons.rate_review_outlined, text: tr('Hali fikr yubormagansiz. Shikoyat, taklif yoki minnatdorchilik — barchasi rahbariyatga yetadi.')),
      ]);
    }
    return ListView(
      padding: readable(context, const EdgeInsets.fromLTRB(16, 12, 16, 32), max: 720),
      children: <Widget>[
        for (final item in items) ...<Widget>[
          MyFeedbackCard(
            item: item,
            kinds: kinds,
            statuses: statuses,
            onTap: () async {
              await openDetail(context, id: 'my-feedback-${asInt(item['id'])}', builder: (_) => MyFeedbackDetailPage(id: asInt(item['id']), initial: item));
              await onChanged();
            },
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class MyFeedbackCard extends StatelessWidget {
  const MyFeedbackCard({super.key, required this.item, required this.kinds, required this.statuses, this.onTap});

  final Map<String, dynamic> item;
  final Map<String, String> kinds;
  final Map<String, String> statuses;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final kind = asText(item['kind']);
    final status = asText(item['status']);
    final replies = asList(item['replies'], 'replies');
    final about = feedbackAboutLine(item);
    return AppCard(
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Row(children: <Widget>[
          Icon(feedbackKindIcon(kind), size: 20, color: feedbackKindColor(kind)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(tr(kinds[kind] ?? feedbackKindLabels[kind] ?? kind), style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          Pill(tr(statuses[status] ?? feedbackStatusLabels[status] ?? status), color: feedbackStatusColor(status)),
        ]),
        const SizedBox(height: 8),
        Text(asText(item['body']), maxLines: 3, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 8),
        Wrap(spacing: 10, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: <Widget>[
          Text('#${asInt(item['id'])} · ${dateTime(item['created_at'])}', style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
          if (about.isNotEmpty) Text(about, style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
          if (item['is_anonymous'] == true)
            Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
              Icon(Icons.visibility_off_outlined, size: 15, color: AppColors.muted),
              const SizedBox(width: 3),
              Text(tr('Anonim'), style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
            ]),
          if (replies.isNotEmpty)
            Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
              Icon(Icons.mark_chat_read_outlined, size: 15, color: AppColors.success),
              const SizedBox(width: 3),
              Text(tr('{0} ta javob', <Object?>[replies.length]), style: TextStyle(color: AppColors.success, fontSize: 12.5, fontWeight: FontWeight.w600)),
            ]),
          if (item['mine'] == false) Pill(tr('Oila a\'zosi yozgan'), color: AppColors.muted),
        ]),
      ]),
    );
  }
}

/// Bitta fikr (muallif uchun): matn, baho, rasmlar, markaz javoblari.
class MyFeedbackDetailPage extends StatelessWidget {
  const MyFeedbackDetailPage({super.key, required this.id, this.initial});

  final int id;
  final Map<String, dynamic>? initial;

  @override
  Widget build(BuildContext context) {
    final api = AppScope.of(context).api;
    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: !isEmbeddedDetail(context), title: Text(tr('Fikr #{0}', <Object?>[id]))),
      body: AsyncView<Map<String, dynamic>>(
        load: () async {
          final data = asMap(await api.get('my/feedback/$id'));
          // Javob `{feedback: {...}}` yoki to'g'ridan-to'g'ri fikr bo'lishi mumkin.
          return data['feedback'] is Map ? asMap(data['feedback']) : data;
        },
        builder: (context, item, reload) => MyFeedbackView(item: item),
      ),
    );
  }
}

class MyFeedbackView extends StatelessWidget {
  const MyFeedbackView({super.key, required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final kind = asText(item['kind']);
    final status = asText(item['status']);
    final replies = asList(item['replies'], 'replies');
    final about = feedbackAboutLine(item);
    return ListView(
      padding: readable(context, const EdgeInsets.fromLTRB(16, 12, 16, 32)),
      children: <Widget>[
        Wrap(spacing: 8, runSpacing: 6, children: <Widget>[
          Pill(tr(feedbackKindLabels[kind] ?? kind), color: feedbackKindColor(kind)),
          Pill(tr(feedbackStatusLabels[status] ?? status), color: feedbackStatusColor(status)),
          if (asText(item['category']).isNotEmpty) Pill(tr(asText(item['category'])), color: AppColors.muted),
          if (item['is_anonymous'] == true) Pill(tr('Anonim'), color: AppColors.muted),
        ]),
        const SizedBox(height: 12),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            SelectableText(asText(item['body']), style: TextStyle(color: AppColors.ink, height: 1.4)),
            if (asInt(item['rating']) > 0) ...<Widget>[
              const SizedBox(height: 10),
              FeedbackStars(value: asInt(item['rating']), size: 20),
            ],
            if (asList(item['attachments'], 'attachments').isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              FeedbackAttachments(files: asList(item['attachments'], 'attachments')),
            ],
            const SizedBox(height: 10),
            Text(<String>[dateTime(item['created_at']), if (about.isNotEmpty) about].join(' · '), style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
          ]),
        ),
        SectionTitle(tr('Markaz javobi')),
        if (replies.isEmpty)
          AppCard(
            color: AppColors.surface2,
            child: Text(
              feedbackClosed(status) ? tr('Fikr yopilgan.') : tr("Fikringiz ko'rib chiqilmoqda. Javob kelganda bildirishnoma keladi."),
              style: TextStyle(color: AppColors.muted),
            ),
          )
        else
          for (final reply in replies) ...<Widget>[
            AppCard(
              color: AppColors.soft(AppColors.success),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text(tr('Markaz rahbariyati'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.success)),
                const SizedBox(height: 4),
                SelectableText(asText(reply['body']), style: TextStyle(color: AppColors.ink)),
                const SizedBox(height: 4),
                Text(dateTime(reply['created_at']), style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
              ]),
            ),
            const SizedBox(height: 8),
          ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Rahbariyat paneli: «Fikrlar»
// ---------------------------------------------------------------------------

class FeedbackAdminPage extends StatefulWidget {
  const FeedbackAdminPage({super.key});

  @override
  State<FeedbackAdminPage> createState() => _FeedbackAdminPageState();
}

class _FeedbackAdminPageState extends State<FeedbackAdminPage> {
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;
  String _status = '';
  String _kind = '';
  bool _mine = false;
  Map<String, dynamic> _data = <String, dynamic>{};
  List<Map<String, dynamic>> _items = <Map<String, dynamic>>[];
  int _page = 1;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Map<String, Object?> _query(int page) => feedbackListQuery(status: _status, kind: _kind, mine: _mine, search: _search.text, page: page);

  Future<void> _load() async {
    if (!mounted) return;
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = asMap(await AppScope.read(context).api.get('feedback', query: _query(1)));
      if (!mounted || request != _request) return;
      setState(() {
        _data = data;
        _items = asList(data);
        _page = asInt(asMap(data['meta'])['current_page'], 1);
        _loading = false;
      });
    } on ApiException catch (error) {
      if (!mounted || request != _request) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    }
  }

  Future<void> _more() async {
    final request = _request;
    setState(() => _loadingMore = true);
    try {
      final data = asMap(await AppScope.read(context).api.get('feedback', query: _query(_page + 1)));
      if (!mounted || request != _request) return;
      setState(() {
        _items = <Map<String, dynamic>>[..._items, ...asList(data)];
        _page = asInt(asMap(data['meta'])['current_page'], _page + 1);
      });
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _filter(String status) {
    setState(() => _status = status);
    _load();
  }

  Widget _chip(String label, bool selected, VoidCallback onTap, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        labelStyle: TextStyle(fontWeight: FontWeight.w600, color: selected ? Colors.white : (color ?? AppColors.ink)),
        selectedColor: color ?? AppColors.brand,
        onSelected: (_) => onTap(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final counts = asMap(_data['counts']);
    final overdue = asInt(_data['overdue']);
    final kinds = feedbackLabels(_data, 'kinds', feedbackKindLabels);
    final statuses = feedbackLabels(_data, 'statuses', feedbackStatusLabels);
    final meta = asMap(_data['meta']);
    final total = asInt(meta['total'], _items.length);
    final lastPage = asInt(meta['last_page'], 1);
    final all = counts.values.fold<int>(0, (sum, value) => sum + asInt(value));
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !isEmbeddedDetail(context),
        title: Text(tr('Fikrlar')),
        actions: <Widget>[
          PopupMenuButton<String>(
            tooltip: tr('Fikr turi'),
            icon: Icon(_kind.isEmpty ? Icons.filter_list : Icons.filter_list_alt, color: _kind.isEmpty ? null : AppColors.brand),
            onSelected: (value) {
              setState(() => _kind = value);
              _load();
            },
            itemBuilder: (_) => <PopupMenuEntry<String>>[
              CheckedPopupMenuItem<String>(value: '', checked: _kind.isEmpty, child: Text(tr('Barcha turlar'))),
              for (final entry in kinds.entries)
                CheckedPopupMenuItem<String>(value: entry.key, checked: _kind == entry.key, child: Text(tr(entry.value))),
            ],
          ),
          const HelpButton(HelpLinks.feedbackPanel),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onChanged: (_) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 400), _load);
              },
              onSubmitted: (_) => _load(),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: tr('Matn, ism, telefon yoki #raqam'),
                isDense: true,
                fillColor: AppColors.surface,
              ),
            ),
          ),
        ),
      ),
      body: Column(children: <Widget>[
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            children: <Widget>[
              _chip(all > 0 ? tr('Hammasi ({0})', <Object?>[all]) : tr('Hammasi'), _status.isEmpty, () => _filter('')),
              for (final entry in feedbackFilterLabels.entries)
                if (entry.key != 'overdue' || overdue > 0 || _status == 'overdue')
                  _chip(
                    () {
                      final count = entry.key == 'overdue' ? overdue : asInt(counts[entry.key]);
                      final label = tr(entry.key == 'overdue' ? entry.value : (statuses[entry.key] ?? entry.value));
                      return count > 0 ? '$label ($count)' : label;
                    }(),
                    _status == entry.key,
                    () => _filter(entry.key),
                    color: entry.key == 'overdue' ? AppColors.danger : feedbackStatusColor(entry.key),
                  ),
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilterChip(
                  label: Text(tr('Menga biriktirilgan')),
                  selected: _mine,
                  onSelected: (value) {
                    setState(() => _mine = value);
                    _load();
                  },
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading && _items.isEmpty
              ? const SkeletonList()
              : _error != null && _items.isEmpty
                  ? ErrorState(message: _error!, onRetry: _load)
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: _items.isEmpty
                          ? ListView(children: <Widget>[EmptyState(icon: Icons.rate_review_outlined, text: tr("Bu filtr bo'yicha fikr yo'q."))])
                          : ListView.separated(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: readable(context, const EdgeInsets.fromLTRB(0, 4, 0, 24)),
                              itemCount: _items.length + (_page < lastPage ? 1 : 0),
                              separatorBuilder: (_, __) => const Divider(indent: 68),
                              itemBuilder: (context, index) {
                                if (index >= _items.length) {
                                  return Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Center(
                                      child: _loadingMore
                                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
                                          : TextButton(onPressed: _more, child: Text(tr('Yana {0} ta', <Object?>[total - _items.length]))),
                                    ),
                                  );
                                }
                                final item = _items[index];
                                final id = asInt(item['id']);
                                return FeedbackAdminTile(
                                  item: item,
                                  kinds: kinds,
                                  statuses: statuses,
                                  selected: isDetailSelected(context, 'feedback-$id'),
                                  onTap: () async {
                                    await openDetail(context, id: 'feedback-$id', builder: (_) => FeedbackAdminDetailPage(id: id, onChanged: _load));
                                    if (mounted) await _load();
                                  },
                                );
                              },
                            ),
                    ),
        ),
      ]),
    );
  }
}

class FeedbackAdminTile extends StatelessWidget {
  const FeedbackAdminTile({super.key, required this.item, required this.kinds, required this.statuses, required this.onTap, this.selected = false});

  final Map<String, dynamic> item;
  final Map<String, String> kinds;
  final Map<String, String> statuses;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final kind = asText(item['kind']);
    final status = asText(item['status']);
    final about = feedbackAboutLine(item);
    final author = feedbackAuthorLine(item, anonymousLabel: 'Anonim', translate: tr);
    final rating = asInt(item['rating']);
    return Material(
      color: selected ? AppColors.soft(AppColors.brand) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: feedbackKindColor(kind).withAlpha(28), shape: BoxShape.circle),
              child: Icon(feedbackKindIcon(kind), size: 20, color: feedbackKindColor(kind)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Row(children: <Widget>[
                  Expanded(
                    child: Text(author.isEmpty ? tr(kinds[kind] ?? kind) : author,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 8),
                  Text(date(item['created_at']), style: TextStyle(color: AppColors.muted, fontSize: 12)),
                ]),
                const SizedBox(height: 2),
                Text(
                  <String>[tr(kinds[kind] ?? feedbackKindLabels[kind] ?? kind), if (asText(item['category']).isNotEmpty) tr(asText(item['category'])), if (about.isNotEmpty) about]
                      .join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: feedbackKindColor(kind), fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(asText(item['body']), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.ink, fontSize: 14)),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: <Widget>[
                  Pill(tr(statuses[status] ?? feedbackStatusLabels[status] ?? status), color: feedbackStatusColor(status)),
                  if (item['overdue'] == true) Pill(tr("Muddati o'tgan"), color: AppColors.danger),
                  if (rating > 0) FeedbackStars(value: rating, size: 15),
                  if (asInt(item['attachments_count']) > 0)
                    Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                      Icon(Icons.image_outlined, size: 15, color: AppColors.muted),
                      Text(' ${asInt(item['attachments_count'])}', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                    ]),
                  if (asText(asMap(item['assignee'])['name']).isNotEmpty)
                    Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                      Icon(Icons.person_pin_outlined, size: 15, color: AppColors.muted),
                      const SizedBox(width: 2),
                      Text(asText(asMap(item['assignee'])['name']), style: TextStyle(color: AppColors.muted, fontSize: 12)),
                    ]),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Fikr kartasi (rahbariyat): to'liq matn, muallif, rasmlar, tarix; holat, mas'ul, javob va ichki izoh.
class FeedbackAdminDetailPage extends StatefulWidget {
  const FeedbackAdminDetailPage({super.key, required this.id, this.onChanged, this.initial});

  final int id;

  /// Ro'yxatni yangilash (ikki ustunli rejimda).
  final Future<void> Function()? onChanged;

  /// Oldindan olingan karta (skrinshot uchun); bo'lmasa serverdan.
  final Map<String, dynamic>? initial;

  @override
  State<FeedbackAdminDetailPage> createState() => _FeedbackAdminDetailPageState();
}

class _FeedbackAdminDetailPageState extends State<FeedbackAdminDetailPage> {
  final TextEditingController _text = TextEditingController();
  Map<String, dynamic>? _item;
  String? _error;
  bool _busy = false;
  String _mode = 'reply';
  bool _resolve = false;
  MasterDetailState? _owner;

  @override
  void initState() {
    super.initState();
    _item = widget.initial;
    if (_item == null) WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final owner = detailOwner(context);
    if (owner != null && owner != _owner) {
      _owner = owner;
      owner.guard = _allowLeave;
    }
  }

  @override
  void dispose() {
    if (_owner?.guard == _allowLeave) _owner?.guard = null;
    _text.dispose();
    super.dispose();
  }

  /// Yozilgan, lekin yuborilmagan javob — boshqa fikr tanlanganda so'raladi.
  Future<bool> _allowLeave() async {
    if (_text.text.trim().isEmpty) return true;
    return confirm(context, tr('Yozilgan matn yuborilmagan. Tashlab ketilsinmi?'), action: tr('Tashlab ketish'), danger: true);
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _error = null);
    try {
      final data = asMap(await AppScope.read(context).api.get('feedback/${widget.id}'));
      if (mounted) setState(() => _item = data);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Future<void> _run(Future<dynamic> Function(Api api) action, {String? done}) async {
    setState(() => _busy = true);
    final api = AppScope.read(context).api;
    try {
      final result = await action(api);
      final map = asMap(result);
      if (!mounted) return;
      if (map['id'] != null && map['kind'] != null) {
        setState(() => _item = map);
      } else {
        await _load();
      }
      if (done != null && mounted) showMessage(context, done);
      await widget.onChanged?.call();
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.field('body') ?? error.field('assigned_to') ?? error.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setStatus(String status) => _run((api) => api.patch('feedback/${widget.id}', <String, Object?>{'status': status}), done: tr('Saqlandi.'));

  Future<void> _assign(int userId) =>
      _run((api) => api.patch('feedback/${widget.id}', <String, Object?>{'assigned_to': userId > 0 ? userId : null}), done: tr('Saqlandi.'));

  Future<void> _send() async {
    final text = _text.text.trim();
    if (text.length < 2) return;
    final reply = _mode == 'reply';
    await _run((api) async {
      final result = reply
          ? await api.post('feedback/${widget.id}/reply', <String, Object?>{'body': text, if (_resolve) 'status': 'resolved'})
          : await api.post('feedback/${widget.id}/notes', <String, Object?>{'body': text});
      _text.clear();
      _resolve = false;
      return result;
    }, done: reply ? tr('Javob muallifga yuborildi.') : tr("Izoh qo'shildi."));
  }

  Future<void> _call(String phone) async {
    final clean = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (clean.isNotEmpty) await launchUrl(Uri.parse('tel:$clean'));
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    final session = AppScope.of(context);
    final canWrite = !session.readOnly;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !isEmbeddedDetail(context),
        title: Text(tr('Fikr #{0}', <Object?>[widget.id])),
        actions: <Widget>[
          if (item != null && canWrite)
            PopupMenuButton<String>(
              tooltip: tr('Holat'),
              icon: const Icon(Icons.flag_outlined),
              enabled: !_busy,
              onSelected: _setStatus,
              itemBuilder: (_) => <PopupMenuEntry<String>>[
                for (final entry in feedbackLabels(item, 'statuses', feedbackStatusLabels).entries)
                  CheckedPopupMenuItem<String>(value: entry.key, checked: asText(item['status']) == entry.key, child: Text(tr(entry.value))),
              ],
            ),
          IconButton(tooltip: tr('Yangilash'), onPressed: _busy ? null : _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: item == null
          ? (_error != null ? ErrorState(message: _error!, onRetry: _load) : const SkeletonList())
          : Column(children: <Widget>[
              Expanded(child: _body(item, canWrite)),
              if (canWrite) _composer(),
            ]),
    );
  }

  Widget _body(Map<String, dynamic> item, bool canWrite) {
    final kind = asText(item['kind']);
    final status = asText(item['status']);
    final author = asMap(item['author']);
    final anonymous = item['is_anonymous'] == true;
    final staff = asList(item['staff'], 'staff');
    final assignee = asInt(asMap(item['assignee'])['id']);
    final events = asList(item['events'], 'events');
    final context0 = asMap(item['context']);
    final about = feedbackAboutLine(item);
    final rating = asInt(item['rating']);
    final phone = asText(author['phone']);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: readable(context, const EdgeInsets.fromLTRB(16, 12, 16, 24)),
        children: <Widget>[
          Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: <Widget>[
            Pill(tr(feedbackKindLabels[kind] ?? kind), color: feedbackKindColor(kind)),
            Pill(tr(feedbackStatusLabels[status] ?? status), color: feedbackStatusColor(status)),
            if (item['overdue'] == true) Pill(tr("Muddati o'tgan"), color: AppColors.danger),
            if (asText(item['category']).isNotEmpty) Pill(tr(asText(item['category'])), color: AppColors.muted),
            if (asText(item['source']) == 'link') Pill(tr('Havola / QR orqali'), color: AppColors.muted),
          ]),
          const SizedBox(height: 12),
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Row(children: <Widget>[
                Avatar(anonymous ? '?' : asText(author['name'], '?'), color: anonymous ? AppColors.muted : AppColors.brand),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                    Text(anonymous ? tr('Anonim muallif') : asText(author['name'], '—'), style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(
                      anonymous
                          ? tr("Muallif ismini ko'rsatmaslikni so'ragan.")
                          : <String>[tr(feedbackRoleLabels[asText(author['role'])] ?? asText(author['role'])), if (phone.isNotEmpty) phone].join(' · '),
                      style: TextStyle(color: AppColors.muted, fontSize: 13),
                    ),
                  ]),
                ),
                if (!anonymous && phone.isNotEmpty)
                  IconButton.outlined(tooltip: tr("Qo'ng'iroq"), onPressed: () => _call(phone), icon: const Icon(Icons.call_outlined)),
              ]),
              if (about.isNotEmpty) ...<Widget>[
                const Divider(height: 24),
                KeyValue(tr('Kimga tegishli'), about),
              ],
            ]),
          ),
          const SizedBox(height: 10),
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              SelectableText(asText(item['body']), style: TextStyle(color: AppColors.ink, height: 1.45, fontSize: 15)),
              if (rating > 0) ...<Widget>[
                const SizedBox(height: 10),
                FeedbackStars(value: rating, size: 20),
              ],
              if (asList(item['attachments'], 'attachments').isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                FeedbackAttachments(files: asList(item['attachments'], 'attachments')),
              ],
              const SizedBox(height: 10),
              Text(
                <String>[
                  dateTime(item['created_at']),
                  if (item['due_at'] != null && !feedbackClosed(status)) tr('Muddat: {0}', <Object?>[dateTime(item['due_at'])]),
                  if (asText(context0['app']).isNotEmpty) '${asText(context0['app'])} ${asText(context0['app_version'])}'.trim(),
                ].join(' · '),
                style: TextStyle(color: AppColors.muted, fontSize: 12.5),
              ),
            ]),
          ),
          if (staff.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              key: ValueKey<String>('assignee-$assignee-${staff.length}'),
              initialValue: staff.any((person) => asInt(person['id']) == assignee) ? assignee : 0,
              isExpanded: true,
              decoration: InputDecoration(labelText: tr("Mas'ul"), prefixIcon: const Icon(Icons.person_pin_outlined)),
              items: <DropdownMenuItem<int>>[
                DropdownMenuItem<int>(value: 0, child: Text(tr('Tayinlanmagan'), style: TextStyle(color: AppColors.muted))),
                for (final person in staff) DropdownMenuItem<int>(value: asInt(person['id']), child: Text(asText(person['name']))),
              ],
              onChanged: !canWrite || _busy ? null : (value) => _assign(value ?? 0),
            ),
          ],
          if (events.isNotEmpty) ...<Widget>[
            SectionTitle(tr('Tarix')),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(children: <Widget>[
                for (var i = 0; i < events.length; i++) ...<Widget>[
                  if (i > 0) const Divider(height: 1),
                  _EventRow(event: events[i]),
                ],
              ]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _composer() {
    final reply = _mode == 'reply';
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: BoxDecoration(color: AppColors.card, border: Border(top: BorderSide(color: AppColors.line))),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Row(children: <Widget>[
            SegmentedButton<String>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: <ButtonSegment<String>>[
                ButtonSegment<String>(value: 'reply', icon: const Icon(Icons.reply_rounded, size: 18), label: Text(tr('Javob'))),
                ButtonSegment<String>(value: 'note', icon: const Icon(Icons.sticky_note_2_outlined, size: 18), label: Text(tr('Ichki izoh'))),
              ],
              selected: <String>{_mode},
              onSelectionChanged: _busy ? null : (value) => setState(() => _mode = value.first),
            ),
            const SizedBox(width: 8),
            if (reply)
              Flexible(
                child: InkWell(
                  onTap: _busy ? null : () => setState(() => _resolve = !_resolve),
                  child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                    Checkbox(value: _resolve, onChanged: _busy ? null : (value) => setState(() => _resolve = value ?? false)),
                    Flexible(child: Text(tr('Hal qilindi'), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ]),
                ),
              ),
          ]),
          const SizedBox(height: 6),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: <Widget>[
            Expanded(
              child: TextField(
                controller: _text,
                minLines: 1,
                maxLines: 5,
                maxLength: 3000,
                enabled: !_busy,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: reply ? tr('Muallifga javob (bildirishnoma boradi)') : tr("Ichki izoh (muallif ko'rmaydi)"),
                  counterText: '',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton.filled(
              tooltip: tr('Yuborish'),
              onPressed: _busy ? null : _send,
              icon: _busy
                  ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onBrand))
                  : const Icon(Icons.send_rounded),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});

  final Map<String, dynamic> event;

  @override
  Widget build(BuildContext context) {
    final type = asText(event['type']);
    final data = asMap(event['data']);
    final body = asText(event['body']);
    String detail;
    IconData icon;
    Color color;
    switch (type) {
      case 'assign':
        detail = asText(data['name'], tr('Olib tashlandi'));
        icon = Icons.person_pin_outlined;
        color = AppColors.brand;
      case 'reply':
        detail = body;
        icon = Icons.reply_rounded;
        color = AppColors.success;
      case 'status':
        final from = asText(data['from']);
        final to = asText(data['to']);
        detail = '${tr(feedbackStatusLabels[from] ?? from)} → ${tr(feedbackStatusLabels[to] ?? to)}';
        icon = Icons.flag_outlined;
        color = feedbackStatusColor(to);
      default:
        detail = body;
        icon = Icons.sticky_note_2_outlined;
        color = AppColors.warning;
    }
    return ListTile(
      dense: true,
      leading: Icon(icon, color: color),
      title: Text(tr(feedbackEventLabels[type] ?? type), style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        if (detail.isNotEmpty) Text(detail, style: TextStyle(color: AppColors.ink)),
        Text(<String>[asText(event['user']), dateTime(event['created_at'])].where((part) => part.isNotEmpty).join(' · '),
            style: TextStyle(color: AppColors.muted, fontSize: 12)),
      ]),
    );
  }
}
