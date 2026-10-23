// O'qituvchi va rahbar (1.35 Ta'lim): dars bo'yicha savollarga javob berish va kurs e'lonlari.
// API: GET lms/questions?status=open|resolved|all, POST lms/comments/{id}/reply {body, resolve}, POST lms/comments/{id}/resolve,
// GET lms/courses/options, GET/POST lms/courses/{id}/announcements, DELETE lms/announcements/{id}.
// Doskani chizish — vebda (mobilda shart emas).
import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/help_links.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

class LmsQuestionsPage extends StatefulWidget {
  const LmsQuestionsPage({super.key});

  @override
  State<LmsQuestionsPage> createState() => _LmsQuestionsPageState();
}

class _LmsQuestionsPageState extends State<LmsQuestionsPage> {
  String _status = 'open';
  final GlobalKey<AsyncViewState<List<Map<String, dynamic>>>> _view = GlobalKey<AsyncViewState<List<Map<String, dynamic>>>>();

  Future<void> _reply(Map<String, dynamic> question) async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet))),
      builder: (_) => _ReplySheet(question: question),
    );
    if (sent == true) _view.currentState?.reload();
  }

  Future<void> _resolve(Map<String, dynamic> question, bool resolved) async {
    try {
      await AppScope.read(context).api.post('lms/comments/${asInt(question['id'])}/resolve', <String, Object?>{'resolved': resolved});
      _view.currentState?.reload();
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = AppScope.of(context).api;
    return Scaffold(
      appBar: AppBar(title: Text(tr("O'quvchi savollari")), actions: const <Widget>[HelpButton(HelpLinks.courseQuestions)]),
      body: Column(children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: SegmentedButton<String>(
            segments: <ButtonSegment<String>>[
              ButtonSegment<String>(value: 'open', label: Text(tr('Javobsiz'))),
              ButtonSegment<String>(value: 'resolved', label: Text(tr('Hal qilingan'))),
              ButtonSegment<String>(value: 'all', label: Text(tr('Hammasi'))),
            ],
            selected: <String>{_status},
            showSelectedIcon: false,
            onSelectionChanged: (value) => setState(() => _status = value.first),
          ),
        ),
        Expanded(
          child: AsyncView<List<Map<String, dynamic>>>(
            key: ValueKey<String>(_status),
            load: () async => asList(asMap(await api.get('lms/questions', query: <String, Object?>{'status': _status}))['questions'], 'questions'),
            builder: (context, questions, reload) {
              if (questions.isEmpty) {
                return ListView(children: <Widget>[
                  EmptyState(
                    icon: Icons.mark_chat_read_outlined,
                    text: _status == 'open' ? tr("Javob kutayotgan savol yo'q. O'quvchilar dars sahifasida savol yozsa, shu yerda ko'rinadi.") : tr("Savollar yo'q."),
                  ),
                ]);
              }
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: questions.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) => QuestionCard(
                  question: questions[index],
                  onReply: () => _reply(questions[index]),
                  onResolve: (resolved) => _resolve(questions[index], resolved),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

/// Savol va uning javoblari (o'qituvchi va o'quvchi sahifalarida).
class QuestionCard extends StatelessWidget {
  const QuestionCard({super.key, required this.question, this.onReply, this.onResolve, this.replyLabel});

  final Map<String, dynamic> question;
  final VoidCallback? onReply;
  final ValueChanged<bool>? onResolve;
  final String? replyLabel;

  @override
  Widget build(BuildContext context) {
    final resolved = question['resolved_at'] != null;
    final replies = asList(question['replies'], 'replies');
    final where = <String>[asText(question['course']), asText(question['lesson'])].where((item) => item.isNotEmpty).join(' · ');
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Row(children: <Widget>[
          Expanded(
            child: Text(asText(question['student'], tr("O'quvchi")), style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          Pill(resolved ? tr('Hal qilindi') : tr('Javob kutmoqda'), color: resolved ? AppColors.success : AppColors.warning),
        ]),
        if (where.isNotEmpty) Text(where, style: TextStyle(color: AppColors.muted, fontSize: 12)),
        const SizedBox(height: 8),
        Text(asText(question['body']), style: const TextStyle(fontSize: 15, height: 1.35)),
        Text(dateTime(question['created_at']), style: TextStyle(color: AppColors.muted, fontSize: 11.5)),
        for (final reply in replies)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(10),
            width: double.infinity,
            decoration: BoxDecoration(
              color: reply['from_student'] == true ? AppColors.surface2 : AppColors.soft(AppColors.brand),
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text(asText(reply['author'], reply['from_student'] == true ? tr("O'quvchi") : tr("O'qituvchi")),
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
              const SizedBox(height: 2),
              Text(asText(reply['body'])),
            ]),
          ),
        if (onReply != null || onResolve != null) ...<Widget>[
          const SizedBox(height: 10),
          Row(children: <Widget>[
            if (onReply != null)
              Expanded(child: FilledButton.tonalIcon(onPressed: onReply, icon: const Icon(Icons.reply, size: 18), label: Text(replyLabel ?? tr('Javob berish')))),
            if (onReply != null && onResolve != null) const SizedBox(width: 8),
            if (onResolve != null)
              OutlinedButton(
                onPressed: () => onResolve!(!resolved),
                child: Text(resolved ? tr('Qayta ochish') : tr('Hal qilindi')),
              ),
          ]),
        ],
      ]),
    );
  }
}

class _ReplySheet extends StatefulWidget {
  const _ReplySheet({required this.question});

  final Map<String, dynamic> question;

  @override
  State<_ReplySheet> createState() => _ReplySheetState();
}

class _ReplySheetState extends State<_ReplySheet> {
  final TextEditingController _body = TextEditingController();
  bool _resolve = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_body.text.trim().isEmpty) {
      setState(() => _error = tr('Javob matnini yozing.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AppScope.read(context).api.post('lms/comments/${asInt(widget.question['id'])}/reply', <String, Object?>{'body': _body.text.trim(), 'resolve': _resolve});
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        Text(tr('Javob berish'), style: AppTheme.title(size: 19)),
        const SizedBox(height: 8),
        Text(asText(widget.question['body']), maxLines: 4, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.muted)),
        const SizedBox(height: 12),
        TextField(controller: _body, minLines: 3, maxLines: 8, autofocus: true, decoration: InputDecoration(hintText: tr('Javobingiz'), errorText: _error)),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _resolve,
          title: Text(tr('Savol hal qilindi deb belgilansin')),
          onChanged: (value) => setState(() => _resolve = value),
        ),
        FilledButton(onPressed: _busy ? null : _send, child: Text(_busy ? tr('Yuborilmoqda...') : tr('Yuborish'))),
      ]),
    );
  }
}

class LmsAnnouncementsPage extends StatefulWidget {
  const LmsAnnouncementsPage({super.key});

  @override
  State<LmsAnnouncementsPage> createState() => _LmsAnnouncementsPageState();
}

class _LmsAnnouncementsPageState extends State<LmsAnnouncementsPage> {
  int? _course;
  final GlobalKey<AsyncViewState<Map<String, dynamic>>> _list = GlobalKey<AsyncViewState<Map<String, dynamic>>>();

  Future<void> _write(int course) async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet))),
      builder: (_) => _AnnouncementSheet(courseId: course),
    );
    if (created == true) _list.currentState?.reload();
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    if (!await confirm(context, tr("E'lon o'chirilsinmi?"), action: tr("O'chirish"), danger: true)) return;
    if (!mounted) return;
    try {
      await AppScope.read(context).api.delete('lms/announcements/${asInt(item['id'])}');
      _list.currentState?.reload();
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = AppScope.of(context).api;
    return Scaffold(
      appBar: AppBar(title: Text(tr("Kurs e'lonlari")), actions: const <Widget>[HelpButton(HelpLinks.courseQuestions)]),
      floatingActionButton: _course == null
          ? null
          : FloatingActionButton.extended(onPressed: () => _write(_course!), icon: const Icon(Icons.campaign_outlined), label: Text(tr("E'lon yozish"))),
      body: AsyncView<List<Map<String, dynamic>>>(
        load: () async {
          final data = await api.get('lms/courses/options');
          return asList(data);
        },
        builder: (context, courses, reload) {
          if (courses.isEmpty) {
            return ListView(children: <Widget>[EmptyState(icon: Icons.menu_book_outlined, text: tr("Kurslar hali yo'q. Kursni veb-versiyada yarating."))]);
          }
          final selected = courses.any((item) => asInt(item['id']) == _course) ? _course! : asInt(courses.first['id']);
          if (_course != selected) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _course = selected);
            });
          }
          return Column(children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: DropdownButtonFormField<int>(
                initialValue: selected,
                isExpanded: true,
                decoration: InputDecoration(labelText: tr('Kurs')),
                items: courses
                    .map((item) => DropdownMenuItem<int>(value: asInt(item['id']), child: Text(asText(item['title']), overflow: TextOverflow.ellipsis)))
                    .toList(),
                onChanged: (value) => setState(() => _course = value),
              ),
            ),
            Expanded(
              child: AsyncView<Map<String, dynamic>>(
                key: _list,
                load: () async => asMap(await api.get('lms/courses/$selected/announcements')),
                builder: (context, data, reload) {
                  final items = asList(data['announcements'], 'announcements');
                  final manage = data['can_manage'] == true;
                  if (data['enabled'] == false) {
                    return ListView(children: <Widget>[EmptyState(icon: Icons.campaign_outlined, text: tr("Kurs e'lonlari sozlamalarda o'chirilgan (Sozlamalar → Ta'lim)."))]);
                  }
                  if (items.isEmpty) {
                    return ListView(children: <Widget>[
                      EmptyState(icon: Icons.campaign_outlined, text: tr("Bu kursda hali e'lon yo'q. Yangi dars, uchrashuv yoki eslatma haqida yozing — o'quvchilarga xabar boradi.")),
                    ]);
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return AppCard(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                          Row(children: <Widget>[
                            Expanded(child: Text(asText(item['title']), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5))),
                            if (manage)
                              IconButton(tooltip: tr("O'chirish"), onPressed: () => _delete(item), icon: const Icon(Icons.delete_outline)),
                          ]),
                          if (asText(item['body']).isNotEmpty) Text(asText(item['body'])),
                          const SizedBox(height: 6),
                          Text(
                            <String>[
                              if (asText(item['author']).isNotEmpty) asText(item['author']),
                              dateTime(item['created_at']),
                              if (asInt(item['notified_count']) > 0) tr('{0} kishiga xabar', <Object?>[asInt(item['notified_count'])]),
                            ].join(' · '),
                            style: TextStyle(color: AppColors.muted, fontSize: 12),
                          ),
                        ]),
                      );
                    },
                  );
                },
              ),
            ),
          ]);
        },
      ),
    );
  }
}

class _AnnouncementSheet extends StatefulWidget {
  const _AnnouncementSheet({required this.courseId});

  final int courseId;

  @override
  State<_AnnouncementSheet> createState() => _AnnouncementSheetState();
}

class _AnnouncementSheetState extends State<_AnnouncementSheet> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _body = TextEditingController();
  bool _notify = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      setState(() => _error = tr("E'lon sarlavhasini yozing."));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AppScope.read(context).api.post('lms/courses/${widget.courseId}/announcements', <String, Object?>{
        'title': _title.text.trim(),
        'body': _body.text.trim().isEmpty ? null : _body.text.trim(),
        'notify': _notify,
      });
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        Text(tr("E'lon yozish"), style: AppTheme.title(size: 19)),
        const SizedBox(height: 12),
        TextField(controller: _title, autofocus: true, maxLength: 200, decoration: InputDecoration(labelText: tr('Sarlavha'), errorText: _error)),
        TextField(controller: _body, minLines: 3, maxLines: 8, maxLength: 5000, decoration: InputDecoration(labelText: tr('Matn (ixtiyoriy)'))),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _notify,
          title: Text(tr("O'quvchilarga xabar yuborilsin")),
          subtitle: Text(tr('Push va Telegram (sozlama ruxsat bersa)')),
          onChanged: (value) => setState(() => _notify = value),
        ),
        FilledButton(onPressed: _busy ? null : _save, child: Text(_busy ? tr('Saqlanmoqda...') : tr("E'lon qilish"))),
      ]),
    );
  }
}
