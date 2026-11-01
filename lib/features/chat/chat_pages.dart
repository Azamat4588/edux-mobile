// Suhbatlar (3.13, server 1.47): o'quvchi ↔ ustoz, ota-ona ↔ o'qituvchi va rahbariyat, xodimlar, guruh kanallari va
// izohlar (test natijasi, davomat). Kim kimga yoza olishi — server (tashkilot sozlamasi). Ochiq suhbat har 5 soniyada,
// ro'yxat har 20 soniyada yangilanadi (faqat ekran ko'rinib turganda). Yangi xabar — push (type=chat, thread_id).
// API: GET chat/meta, chat/threads, chat/contacts, POST chat/threads, chat/subject, GET/POST chat/threads/{id}/messages,
// PUT/DELETE chat/messages/{id}, POST chat/messages/{id}/report.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

/// O'qilmagan xabarlar soni («Yana» menyusidagi belgi uchun).
final ValueNotifier<int> chatUnread = ValueNotifier<int>(0);

const Map<String, String> chatRoleLabels = <String, String>{
  'director': 'Direktor',
  'admin': 'Administrator',
  'teacher': "O'qituvchi",
  'cashier': 'Kassir',
  'marketer': 'Marketolog',
  'student': "O'quvchi",
  'guardian': 'Ota-ona',
  'staff': 'Xodim',
};

Future<void> refreshChatUnread(Api api) async {
  try {
    chatUnread.value = asInt(asMap(await api.get('chat/unread'))['unread']);
  } on ApiException {
    // jim
  }
}

String chatTime(Object? value) {
  final date = parseDate(value)?.toLocal();
  if (date == null) return '';
  final now = DateTime.now();
  if (date.year == now.year && date.month == now.month && date.day == now.day) return '${two(date.hour)}:${two(date.minute)}';
  return '${two(date.day)}.${two(date.month)}';
}

class ChatListPage extends StatefulWidget {
  const ChatListPage({super.key});

  @override
  State<ChatListPage> createState() => _ChatListPageState();
}

class _ChatListPageState extends State<ChatListPage> {
  final GlobalKey<AsyncViewState<Map<String, dynamic>>> _view = GlobalKey<AsyncViewState<Map<String, dynamic>>>();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted && (ModalRoute.of(context)?.isCurrent ?? false)) _view.currentState?.reload();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<Map<String, dynamic>> _load() async {
    final api = AppScope.read(context).api;
    final results = await Future.wait(<Future<dynamic>>[api.get('chat/meta'), api.get('chat/threads')]);
    final meta = asMap(results[0]);
    chatUnread.value = asInt(meta['unread']);
    return <String, dynamic>{'meta': meta, 'threads': asList(asMap(results[1])['data'])};
  }

  Future<void> _open(int id) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ChatThreadPage(threadId: id)));
    await _view.currentState?.reload();
  }

  Future<void> _new(Map<String, dynamic> meta) async {
    final id = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _NewChatSheet(groups: asList(meta['groups'])),
    );
    if (id != null && mounted) await _open(id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: pageBar(context, title: Text(tr('Suhbatlar'))),
      body: AsyncView<Map<String, dynamic>>(
        key: _view,
        load: _load,
        builder: (context, data, reload) {
          final meta = asMap(data['meta']);
          final threads = asList(data['threads']);
          if (meta['enabled'] != true) {
            return ListView(children: <Widget>[EmptyState(text: tr("Suhbatlar tashkilotda o'chirilgan."), icon: Icons.forum_outlined)]);
          }
          return Stack(children: <Widget>[
            if (threads.isEmpty)
              ListView(children: <Widget>[
                EmptyState(text: tr("Suhbat yo'q. «Yangi» tugmasi bilan o'qituvchi, ota-ona yoki hamkasbga yozing."), icon: Icons.forum_outlined),
              ])
            else
              ListView.separated(
                padding: const EdgeInsets.only(bottom: 88),
                itemCount: threads.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = threads[index];
                  final last = asMap(item['last']);
                  final kind = asText(item['kind']);
                  final preview = last.isEmpty
                      ? ''
                      : '${last['mine'] == true ? '${tr('Siz')}: ' : (kind != 'direct' ? '${asText(last['author'])}: ' : '')}'
                          '${last['deleted'] == true ? tr("Xabar o'chirildi") : asText(last['body'], '📎 ${asText(asMap(last['attachment'])['name'])}')}';
                  final unread = asInt(item['unread']);
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppColors.soft(AppColors.brand),
                      foregroundColor: AppColors.brand,
                      child: kind == 'direct'
                          ? Text(asText(item['title'], '?').characters.first)
                          : Icon(kind == 'group' ? Icons.groups_outlined : Icons.comment_outlined, size: 20),
                    ),
                    title: Text(asText(item['title']), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(preview, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.muted, fontSize: 13)),
                    trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: <Widget>[
                      Text(chatTime(item['last_message_at']), style: TextStyle(color: AppColors.muted, fontSize: 11.5)),
                      if (unread > 0) ...<Widget>[
                        const SizedBox(height: 4),
                        Pill('$unread', color: AppColors.brand),
                      ],
                    ]),
                    onTap: () => _open(asInt(item['id'])),
                  );
                },
              ),
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton.extended(
                heroTag: 'chat-new',
                onPressed: () => _new(meta),
                icon: const Icon(Icons.edit_outlined),
                label: Text(tr('Yangi')),
              ),
            ),
          ]);
        },
      ),
    );
  }
}

class _NewChatSheet extends StatefulWidget {
  const _NewChatSheet({required this.groups});

  final List<Map<String, dynamic>> groups;

  @override
  State<_NewChatSheet> createState() => _NewChatSheetState();
}

class _NewChatSheetState extends State<_NewChatSheet> {
  final TextEditingController _search = TextEditingController();
  List<Map<String, dynamic>> _contacts = <Map<String, dynamic>>[];
  bool _loading = true;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _find());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _find() async {
    setState(() => _loading = true);
    try {
      final data = asMap(await AppScope.read(context).api.get('chat/contacts', query: <String, Object?>{if (_search.text.trim().isNotEmpty) 'q': _search.text.trim()}));
      if (mounted) setState(() => _contacts = asList(data['data']));
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _start(Map<String, dynamic> body) async {
    try {
      final data = asMap(await AppScope.read(context).api.post('chat/threads', body));
      if (mounted) Navigator.pop(context, asInt(data['id']));
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: <Widget>[
          Text(tr('Yangi suhbat'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          if (widget.groups.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Text(tr('Guruh kanali'), style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
              for (final group in widget.groups)
                ActionChip(
                  avatar: const Icon(Icons.groups_outlined, size: 18),
                  label: Text(asText(group['name'])),
                  onPressed: () => _start(<String, dynamic>{'group_id': asInt(group['id'])}),
                ),
            ]),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _search,
            decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: tr('Ism yoki telefon')),
            onChanged: (_) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 350), _find);
            },
          ),
          const SizedBox(height: 8),
          if (_loading)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
          else if (_contacts.isEmpty)
            Padding(padding: const EdgeInsets.all(16), child: Text(tr("Yozish mumkin bo'lgan odam topilmadi."), style: TextStyle(color: AppColors.muted)))
          else
            for (final item in _contacts)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(child: Text(asText(item['name'], '?').characters.first)),
                title: Text(asText(item['name'])),
                subtitle: Text(
                  (asList(item['roles']).isNotEmpty ? item['roles'] as List<dynamic> : <dynamic>[item['role']])
                      .map((role) => tr(chatRoleLabels[role.toString()] ?? role.toString()))
                      .join(', '),
                ),
                onTap: () => _start(<String, dynamic>{'user_id': asInt(item['id'])}),
              ),
        ]),
      ),
    );
  }
}

/// Bitta suhbat. [threadId] — mavjud; izoh uchun [ChatThreadPage.subject] (type, id).
class ChatThreadPage extends StatefulWidget {
  const ChatThreadPage({super.key, required this.threadId});

  final int threadId;

  /// Izoh (test natijasi, davomat): suhbatni topib/yaratib ochadi.
  static Future<void> subject(BuildContext context, String type, int id, {int? studentId}) async {
    final api = AppScope.read(context).api;
    try {
      final data = asMap(await api.post('chat/subject', <String, dynamic>{'type': type, 'id': id, if (studentId != null) 'student_id': studentId}));
      if (context.mounted) {
        await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ChatThreadPage(threadId: asInt(data['id']))));
      }
    } on ApiException catch (error) {
      if (context.mounted) showMessage(context, error.message, error: true);
    }
  }

  @override
  State<ChatThreadPage> createState() => _ChatThreadPageState();
}

class _ChatThreadPageState extends State<ChatThreadPage> with WidgetsBindingObserver {
  final TextEditingController _text = TextEditingController();
  final ScrollController _scroll = ScrollController();
  Map<String, dynamic> _thread = <String, dynamic>{};
  final List<Map<String, dynamic>> _messages = <Map<String, dynamic>>[];
  bool _loading = true;
  bool _canPost = false;
  bool _sending = false;
  int _readByOthers = 0;
  String? _error;
  Timer? _timer;
  bool _active = true;

  int get _lastId => _messages.isEmpty ? 0 : asInt(_messages.last['id']);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _poll());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _active = state == AppLifecycleState.resumed;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _down() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _load() async {
    try {
      final data = asMap(await AppScope.read(context).api.get('chat/threads/${widget.threadId}/messages'));
      if (!mounted) return;
      setState(() {
        _thread = asMap(data['thread']);
        _messages
          ..clear()
          ..addAll(asList(data['data']));
        _canPost = data['can_post'] == true;
        _readByOthers = asInt(data['read_by_others']);
        _loading = false;
      });
      _down();
      unawaited(refreshChatUnread(AppScope.read(context).api));
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          _loading = false;
        });
      }
    }
  }

  Future<void> _poll() async {
    if (!mounted || !_active || _loading || !(ModalRoute.of(context)?.isCurrent ?? false)) return;
    try {
      final data = asMap(await AppScope.read(context).api.get('chat/threads/${widget.threadId}/messages', query: <String, Object?>{'after': _lastId}));
      if (!mounted) return;
      final fresh = asList(data['data']).where((item) => !_messages.any((m) => m['id'] == item['id'])).toList();
      setState(() {
        _messages.addAll(fresh);
        _readByOthers = asInt(data['read_by_others']);
        _canPost = data['can_post'] == true;
      });
      if (fresh.isNotEmpty) _down();
    } on ApiException {
      // keyingi safar
    }
  }

  Future<void> _send() async {
    final body = _text.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final message = asMap(await AppScope.read(context).api.post('chat/threads/${widget.threadId}/messages', <String, dynamic>{'body': body}));
      if (!mounted) return;
      setState(() {
        _messages.add(message);
        _text.clear();
      });
      _down();
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _actions(Map<String, dynamic> message) async {
    final mine = message['mine'] == true;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          if (mine && asText(message['body']).isNotEmpty) ListTile(leading: const Icon(Icons.edit_outlined), title: Text(tr('Tahrirlash')), onTap: () => Navigator.pop(context, 'edit')),
          if (mine) ListTile(leading: const Icon(Icons.delete_outline), title: Text(tr("O'chirish")), onTap: () => Navigator.pop(context, 'delete')),
          if (!mine && message['reported'] != true)
            ListTile(leading: const Icon(Icons.flag_outlined), title: Text(tr('Shikoyat')), onTap: () => Navigator.pop(context, 'report')),
        ]),
      ),
    );
    if (action == null || !mounted) return;
    final api = AppScope.read(context).api;
    try {
      if (action == 'delete') {
        if (!await confirm(context, tr("Xabar o'chirilsinmi?"), danger: true)) return;
        await api.delete('chat/messages/${message['id']}');
        setState(() => message
          ..['deleted'] = true
          ..['body'] = null
          ..['attachment'] = null);
      } else if (action == 'report') {
        await api.post('chat/messages/${message['id']}/report', <String, dynamic>{});
        setState(() => message['reported'] = true);
        if (mounted) showMessage(context, tr('Shikoyat rahbariyatga yuborildi.'));
      } else if (action == 'edit') {
        final controller = TextEditingController(text: asText(message['body']));
        final text = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(tr('Tahrirlash')),
            content: TextField(controller: controller, maxLines: 4, maxLength: 4000, autofocus: true),
            actions: <Widget>[
              TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Bekor qilish'))),
              FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: Text(tr('Saqlash'))),
            ],
          ),
        );
        controller.dispose();
        if (text == null || text.isEmpty) return;
        final updated = asMap(await api.put('chat/messages/${message['id']}', <String, dynamic>{'body': text}));
        setState(() => message.addAll(updated));
      }
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    }
  }

  String get _subtitle {
    final kind = asText(_thread['kind']);
    if (kind == 'group') return tr('Guruh kanali · {0} kishi', <Object?>[asList(_thread['participants']).length]);
    if (kind == 'subject') return tr('Izoh');
    final matches = asList(_thread['participants']).where((p) => asText(p['name']) == asText(_thread['title'])).toList();
    return asList(matches.isEmpty ? null : matches.first['roles']).map((role) => tr(chatRoleLabels[role.toString()] ?? role.toString())).join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final kind = asText(_thread['kind']);
    return Scaffold(
      appBar: pageBar(context,
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(asText(_thread['title'], tr('Suhbat')), maxLines: 1, overflow: TextOverflow.ellipsis),
            if (_subtitle.isNotEmpty) Text(_subtitle, style: TextStyle(fontSize: 12, color: AppColors.muted)),
          ])),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : Column(children: <Widget>[
                  Expanded(
                    child: _messages.isEmpty
                        ? EmptyState(text: tr("Hali xabar yo'q. Birinchi bo'lib yozing."), icon: Icons.forum_outlined)
                        : ListView.builder(
                            controller: _scroll,
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                            itemCount: _messages.length,
                            itemBuilder: (context, index) => _Bubble(
                              message: _messages[index],
                              showAuthor: kind != 'direct',
                              read: asInt(_messages[index]['id']) <= _readByOthers,
                              onLongPress: _messages[index]['deleted'] == true ? null : () => _actions(_messages[index]),
                            ),
                          ),
                  ),
                  SafeArea(
                    top: false,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                      decoration: BoxDecoration(color: AppColors.card, border: Border(top: BorderSide(color: AppColors.line))),
                      child: _canPost
                          ? Row(crossAxisAlignment: CrossAxisAlignment.end, children: <Widget>[
                              Expanded(
                                child: TextField(
                                  controller: _text,
                                  minLines: 1,
                                  maxLines: 5,
                                  maxLength: 4000,
                                  textCapitalization: TextCapitalization.sentences,
                                  decoration: InputDecoration(hintText: tr('Xabar yozing...'), counterText: ''),
                                ),
                              ),
                              const SizedBox(width: 6),
                              IconButton.filled(onPressed: _sending ? null : _send, icon: const Icon(Icons.send_rounded), tooltip: tr('Yuborish')),
                            ])
                          : Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                kind == 'group' ? tr("Guruh kanalida faqat o'qituvchi yozadi.") : tr("Bu suhbatga yozib bo'lmaydi."),
                                textAlign: TextAlign.center,
                                style: TextStyle(color: AppColors.muted, fontSize: 13),
                              ),
                            ),
                    ),
                  ),
                ]),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.showAuthor, required this.read, this.onLongPress});

  final Map<String, dynamic> message;
  final bool showAuthor;
  final bool read;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final mine = message['mine'] == true;
    final deleted = message['deleted'] == true;
    final attachment = asMap(message['attachment']);
    final fg = mine ? Colors.white : AppColors.ink;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          decoration: BoxDecoration(
            color: mine ? AppColors.brand : AppColors.card,
            border: mine ? null : Border.all(color: AppColors.line),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(mine ? 16 : 4),
              bottomRight: Radius.circular(mine ? 4 : 16),
            ),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            if (showAuthor && !mine)
              Text(asText(message['author']), style: TextStyle(color: AppColors.brand, fontSize: 12, fontWeight: FontWeight.w700)),
            if (deleted)
              Text(tr("Xabar o'chirildi"), style: TextStyle(color: fg.withAlpha(180), fontStyle: FontStyle.italic))
            else ...<Widget>[
              if (asText(message['body']).isNotEmpty) SelectableText(asText(message['body']), style: TextStyle(color: fg, fontSize: 15, height: 1.35)),
              if (attachment.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                    Icon(attachment['image'] == true ? Icons.image_outlined : Icons.attach_file, size: 16, color: fg),
                    const SizedBox(width: 4),
                    Flexible(child: Text(asText(attachment['name']), style: TextStyle(color: fg, fontSize: 13, decoration: TextDecoration.underline))),
                  ]),
                ),
            ],
            const SizedBox(height: 2),
            Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
              if (message['edited'] == true) Text('${tr('tahrirlangan')} · ', style: TextStyle(color: fg.withAlpha(160), fontSize: 11)),
              Text(chatTime(message['created_at']), style: TextStyle(color: fg.withAlpha(160), fontSize: 11)),
              if (mine && !deleted) ...<Widget>[
                const SizedBox(width: 4),
                Icon(read ? Icons.done_all : Icons.done, size: 14, color: fg.withAlpha(190)),
              ],
            ]),
          ]),
        ),
      ),
    );
  }
}
