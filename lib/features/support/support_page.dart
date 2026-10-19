// Murojaat (qo'llab-quvvatlash): o'z murojaatlarim, yangi murojaat va yozishma.
// API: GET /my/support, GET /public/support (mavzular, aloqa), POST /public/support, GET|POST /public/support/{token}.
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

const Map<String, String> supportTopicLabels = <String, String>{
  'question': 'Savol',
  'bug': 'Xatolik',
  'payment': "To'lov va hisob",
  'feature': 'Taklif',
  'other': 'Boshqa',
};

const Map<String, String> supportStatusLabels = <String, String>{
  'open': 'Yangi',
  'answered': 'Javob berilgan',
  'closed': 'Yopilgan',
};

Color supportStatusColor(String status) {
  if (status == 'answered') return AppColors.success;
  if (status == 'closed') return AppColors.muted;
  return AppColors.warning;
}

class SupportPage extends StatefulWidget {
  const SupportPage({super.key});

  @override
  State<SupportPage> createState() => _SupportPageState();
}

class _SupportPageState extends State<SupportPage> {
  final GlobalKey<AsyncViewState<Map<String, dynamic>>> _view = GlobalKey<AsyncViewState<Map<String, dynamic>>>();
  Map<String, dynamic> _meta = <String, dynamic>{};

  Future<Map<String, dynamic>> _load(Session session) async {
    final results = await Future.wait<dynamic>(<Future<dynamic>>[
      session.api.get('my/support'),
      session.api.get('public/support').catchError((_) => null),
    ]);
    _meta = asMap(results[1]);
    return <String, dynamic>{'tickets': asList(results[0]), 'meta': _meta};
  }

  Future<void> _create() async {
    final token = await Navigator.of(context).push<String>(MaterialPageRoute<String>(builder: (_) => _NewTicketPage(meta: _meta)));
    _view.currentState?.reload();
    if (token != null && token.isNotEmpty && mounted) {
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TicketPage(token: token)));
      _view.currentState?.reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Murojaatlar'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.edit_outlined),
        label: Text(tr('Yangi murojaat')),
      ),
      body: AsyncView<Map<String, dynamic>>(
        key: _view,
        load: () => _load(session),
        builder: (context, data, reload) {
          final tickets = asList(data['tickets'], 'tickets');
          final contacts = asMap(asMap(data['meta'])['contacts']);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: <Widget>[
              Text(tr("Savol, xatolik yoki taklifingizni yozing — EduX jamoasi javob beradi. Javob kelganda shu yerda ko'rinadi."),
                  style: TextStyle(color: AppColors.muted)),
              if (contacts.values.any((value) => value != null)) ...<Widget>[
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
                  if (contacts['phone'] != null)
                    ActionChip(
                      avatar: const Icon(Icons.call_outlined, size: 18),
                      label: Text(asText(contacts['phone'])),
                      onPressed: () => launchUrl(Uri.parse('tel:${asText(contacts['phone']).replaceAll(' ', '')}')),
                    ),
                  if (contacts['telegram'] != null)
                    ActionChip(
                      avatar: const Icon(Icons.send_rounded, size: 18, color: Color(0xFF229ED9)),
                      label: Text('@${asText(contacts['telegram'])}'),
                      onPressed: () => launchUrl(Uri.parse('https://t.me/${asText(contacts['telegram'])}'), mode: LaunchMode.externalApplication),
                    ),
                  if (contacts['email'] != null)
                    ActionChip(
                      avatar: const Icon(Icons.mail_outline, size: 18),
                      label: Text(asText(contacts['email'])),
                      onPressed: () => launchUrl(Uri.parse('mailto:${asText(contacts['email'])}')),
                    ),
                ]),
              ],
              const SizedBox(height: 12),
              if (tickets.isEmpty)
                EmptyState(icon: Icons.support_agent_outlined, text: tr("Hali murojaat yubormagansiz."))
              else
                for (final ticket in tickets) ...<Widget>[
                  AppCard(
                    onTap: () async {
                      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TicketPage(token: asText(ticket['token']))));
                      await reload();
                    },
                    child: Row(children: <Widget>[
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                          Text(asText(ticket['subject']), style: const TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text(
                            '${tr(supportTopicLabels[ticket['topic']] ?? asText(ticket['topic']))} · ${dateTime(ticket['updated_at'])}',
                            style: TextStyle(color: AppColors.muted, fontSize: 13),
                          ),
                        ]),
                      ),
                      Pill(tr(supportStatusLabels[ticket['status']] ?? asText(ticket['status'])),
                          color: supportStatusColor(asText(ticket['status']))),
                    ]),
                  ),
                  const SizedBox(height: 8),
                ],
            ],
          );
        },
      ),
    );
  }
}

class _NewTicketPage extends StatefulWidget {
  const _NewTicketPage({required this.meta});

  final Map<String, dynamic> meta;

  @override
  State<_NewTicketPage> createState() => _NewTicketPageState();
}

class _NewTicketPageState extends State<_NewTicketPage> {
  late final TextEditingController _name;
  late final TextEditingController _contact;
  final _subject = TextEditingController();
  final _body = TextEditingController();
  String _topic = 'question';
  bool _busy = false;
  String? _error;
  Map<String, String> _errors = <String, String>{};

  @override
  void initState() {
    super.initState();
    final session = AppScope.read(context);
    _name = TextEditingController(text: session.userName);
    _contact = TextEditingController(text: asText(session.user['phone'], asText(session.user['email'])));
  }

  @override
  void dispose() {
    for (final controller in <TextEditingController>[_name, _contact, _subject, _body]) {
      controller.dispose();
    }
    super.dispose();
  }

  Map<String, String> get _topics {
    final fromServer = asMap(widget.meta['topics']);
    if (fromServer.isEmpty) return supportTopicLabels;
    return fromServer.map((key, value) => MapEntry(key, asText(value)));
  }

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _error = null;
      _errors = <String, String>{};
    });
    final session = AppScope.read(context);
    try {
      final data = asMap(await session.api.post('public/support', <String, Object?>{
        'name': _name.text.trim(),
        'contact': _contact.text.trim(),
        'topic': _topic,
        'subject': _subject.text.trim(),
        'body': _body.text.trim(),
        'organization_id': session.organizationId,
      }));
      if (!mounted) return;
      showMessage(context, tr(asText(data['message'], 'Murojaatingiz qabul qilindi.')));
      Navigator.pop(context, asText(data['token']));
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _errors = <String, String>{
          for (final field in <String>['name', 'contact', 'subject', 'body'])
            if (error.field(field) != null) field: error.field(field)!,
        };
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final topics = _topics;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Yangi murojaat'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          if (_error != null && _errors.isEmpty) ...<Widget>[
            Text(_error!, style: const TextStyle(color: AppColors.danger)),
            const SizedBox(height: 12),
          ],
          DropdownButtonFormField<String>(
            value: topics.containsKey(_topic) ? _topic : topics.keys.first,
            decoration: InputDecoration(labelText: tr('Mavzu turi')),
            items: topics.entries
                .map((entry) => DropdownMenuItem<String>(value: entry.key, child: Text(tr(entry.value))))
                .toList(),
            onChanged: (value) => setState(() => _topic = value ?? 'question'),
          ),
          const SizedBox(height: 12),
          TextField(controller: _name, decoration: InputDecoration(labelText: tr('Ismingiz'), errorText: _errors['name'])),
          const SizedBox(height: 12),
          TextField(
            controller: _contact,
            decoration: InputDecoration(labelText: tr("Bog'lanish (telefon yoki email)"), errorText: _errors['contact']),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _subject,
            maxLength: 150,
            decoration: InputDecoration(labelText: tr('Mavzu'), errorText: _errors['subject']),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _body,
            minLines: 5,
            maxLines: 10,
            maxLength: 5000,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: tr('Xabar'), alignLabelWithHint: true, errorText: _errors['body']),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _send,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                : const Icon(Icons.send_rounded),
            label: Text(tr('Yuborish')),
          ),
        ],
      ),
    );
  }
}

/// Murojaat yozishmasi (maxfiy token bo'yicha).
class TicketPage extends StatefulWidget {
  const TicketPage({super.key, required this.token});

  final String token;

  @override
  State<TicketPage> createState() => _TicketPageState();
}

class _TicketPageState extends State<TicketPage> {
  final GlobalKey<AsyncViewState<Map<String, dynamic>>> _view = GlobalKey<AsyncViewState<Map<String, dynamic>>>();
  final _reply = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _reply.text.trim();
    if (text.length < 2) return;
    setState(() => _sending = true);
    try {
      await AppScope.read(context).api.post('public/support/${widget.token}', <String, Object?>{'body': text});
      _reply.clear();
      await _view.currentState?.reload();
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = AppScope.of(context).api;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Murojaat'))),
      body: Column(children: <Widget>[
        Expanded(
          child: AsyncView<Map<String, dynamic>>(
            key: _view,
            load: () async => asMap(await api.get('public/support/${widget.token}')),
            builder: (context, ticket, reload) {
              final messages = asList(ticket['messages'], 'messages');
              final status = asText(ticket['status']);
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                children: <Widget>[
                  Text(asText(ticket['subject']), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 8, runSpacing: 6, children: <Widget>[
                    Pill(tr(supportStatusLabels[status] ?? status), color: supportStatusColor(status)),
                    Pill(tr(supportTopicLabels[ticket['topic']] ?? asText(ticket['topic'])), color: AppColors.muted),
                    Pill(dateTime(ticket['created_at']), color: AppColors.muted),
                  ]),
                  const SizedBox(height: 14),
                  for (final message in messages) _MessageBubble(message: message),
                  if (status == 'closed')
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(tr("Murojaat yopilgan. Yangi xabar yozsangiz, u qayta ochiladi."),
                          textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 13)),
                    ),
                ],
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            decoration: BoxDecoration(color: AppColors.card, border: Border(top: BorderSide(color: AppColors.line))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _reply,
                  minLines: 1,
                  maxLines: 5,
                  maxLength: 5000,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(hintText: tr('Xabar yozing...'), counterText: '', isDense: true),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filled(
                tooltip: tr('Yuborish'),
                onPressed: _sending ? null : _send,
                icon: _sending
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_rounded),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final Map<String, dynamic> message;

  @override
  Widget build(BuildContext context) {
    final staff = message['from_staff'] == true;
    return Align(
      alignment: staff ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
        decoration: BoxDecoration(
          color: staff ? AppColors.card : AppColors.soft(AppColors.brand),
          border: Border.all(color: staff ? AppColors.line : AppColors.brand.withAlpha(60)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          if (staff)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(tr("Qo'llab-quvvatlash"), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.brand)),
            ),
          SelectableText(asText(message['body']), style: TextStyle(color: AppColors.ink)),
          const SizedBox(height: 4),
          Text(dateTime(message['created_at']), style: TextStyle(fontSize: 11, color: AppColors.muted)),
        ]),
      ),
    );
  }
}
