// Murojaat (qo'llab-quvvatlash): o'z murojaatlarim, yangi murojaat (rasm bilan), yozishma, yopish va baho.
// API (server 1.38, docs/support.md): GET my/support, GET public/support (mavzular, aloqa, rasm cheklovi),
// POST public/support (JSON yoki multipart; context[app|app_version|os|page|screen] — ilova o'zi qo'shadi),
// GET|POST public/support/{token}, POST public/support/{token}/close, POST public/support/{token}/rate.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/adaptive.dart';
import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/help_links.dart';
import '../../core/i18n.dart';
import '../../core/push.dart';
import '../../core/session.dart';
import '../../core/support.dart';
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

/// Yangi murojaat oynasi; yuborilgach yozishma ochiladi. [page] — qaysi ekrandan (murojaat kontekstiga yoziladi).
Future<void> openNewTicket(BuildContext context, {String page = '', String subject = '', Map<String, dynamic>? meta}) async {
  final navigator = Navigator.of(context);
  final token = await navigator.push<String>(
    MaterialPageRoute<String>(builder: (_) => NewTicketPage(page: page, subject: subject, meta: meta)),
  );
  if (token != null && token.isNotEmpty) {
    await navigator.push(MaterialPageRoute<void>(builder: (_) => TicketPage(token: token)));
  }
}

/// Aloqa kanallari: telefon, Telegram, email va ish vaqti.
class SupportContactsView extends StatelessWidget {
  const SupportContactsView({super.key, required this.contacts});

  final Map<String, String> contacts;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
        if (contacts['phone'] != null)
          ActionChip(
            avatar: const Icon(Icons.call_outlined, size: 18),
            label: Text(contacts['phone']!),
            onPressed: () => launchUrl(Uri.parse('tel:${contacts['phone']!.replaceAll(RegExp(r'[^0-9+]'), '')}')),
          ),
        if (contacts['telegram'] != null)
          ActionChip(
            avatar: const Icon(Icons.send_rounded, size: 18, color: Color(0xFF229ED9)),
            label: Text('@${contacts['telegram']}'),
            onPressed: () => launchUrl(Uri.parse('https://t.me/${contacts['telegram']}'), mode: LaunchMode.externalApplication),
          ),
        if (contacts['email'] != null)
          ActionChip(
            avatar: const Icon(Icons.mail_outline, size: 18),
            label: Text(contacts['email']!),
            onPressed: () => launchUrl(Uri.parse('mailto:${contacts['email']}')),
          ),
      ]),
      if (contacts['hours'] != null) ...<Widget>[
        const SizedBox(height: 8),
        Row(children: <Widget>[
          Icon(Icons.schedule, size: 16, color: AppColors.muted),
          const SizedBox(width: 6),
          Expanded(child: Text(tr('Ish vaqti: {0}', <Object?>[contacts['hours']]), style: TextStyle(color: AppColors.muted, fontSize: 13))),
        ]),
      ],
    ]);
  }
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
    await openNewTicket(context, page: 'support', meta: _meta);
    _view.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Murojaatlar')), actions: const <Widget>[HelpButton(HelpLinks.support)]),
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
          final contacts = supportContacts(asMap(data['meta']));
          return ListView(
            padding: readable(context, const EdgeInsets.fromLTRB(16, 12, 16, 96)),
            children: <Widget>[
              Text(tr("Savol, xatolik yoki taklifingizni yozing — EduX jamoasi javob beradi. Javob kelganda shu yerda ko'rinadi."),
                  style: TextStyle(color: AppColors.muted)),
              if (contacts.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                SupportContactsView(contacts: contacts),
              ],
              const SizedBox(height: 12),
              if (tickets.isEmpty)
                EmptyState(icon: Icons.support_agent_outlined, text: tr('Hali murojaat yubormagansiz.'))
              else
                for (final ticket in tickets) ...<Widget>[
                  AppCard(
                    // iPad: yozishma o'ng ustunda (MasterDetail), telefonda — yangi sahifa.
                    color: isDetailSelected(context, 'ticket-${asText(ticket['token'])}') ? AppColors.soft(AppColors.brand) : null,
                    onTap: () async {
                      await openDetail(context, id: 'ticket-${asText(ticket['token'])}', builder: (_) => TicketPage(token: asText(ticket['token'])));
                      await reload();
                    },
                    child: Row(children: <Widget>[
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                          Text(asText(ticket['subject']), style: const TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text(
                            <String>[
                              if (ticket['id'] != null) '#${asInt(ticket['id'])}',
                              tr(supportTopicLabels[ticket['topic']] ?? asText(ticket['topic'])),
                              dateTime(ticket['updated_at']),
                            ].join(' · '),
                            style: TextStyle(color: AppColors.muted, fontSize: 13),
                          ),
                        ]),
                      ),
                      if (ticket['helpful'] == true || ticket['helpful'] == false)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Icon(ticket['helpful'] == true ? Icons.thumb_up_alt_outlined : Icons.thumb_down_alt_outlined,
                              size: 18, color: AppColors.muted),
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

/// Murojaat kontekstida qurilma ma'lumoti (ilova, versiya, OS, ekran).
Map<String, String> deviceSupportContext(BuildContext context, String page) {
  final size = MediaQuery.maybeOf(context)?.size;
  String os;
  try {
    os = '${Platform.isIOS ? 'iOS' : 'Android'} ${Platform.operatingSystemVersion}';
  } catch (_) {
    os = '';
  }
  return supportContext(
    app: Platform.isIOS ? 'ios' : 'android',
    version: PushService.appVersion,
    os: os,
    page: page,
    screen: size == null ? null : '${size.width.round()}x${size.height.round()}',
  );
}

/// Tanlangan rasm (yuborilguncha).
class PickedImage {
  PickedImage(this.name, this.bytes);

  final String name;
  final Uint8List bytes;
}

/// Rasm tanlash (galereyadan), cheklovlar bo'yicha tekshirib. Xato bo'lsa — xabar.
Future<List<PickedImage>> pickImages(BuildContext context, SupportAttachmentRules rules, int already) async {
  final left = rules.maxFiles - already;
  if (left <= 0) {
    showMessage(context, tr("Ko'pi bilan {0} ta rasm biriktiriladi.", <Object?>[rules.maxFiles]), error: true);
    return <PickedImage>[];
  }
  final files = await ImagePicker().pickMultiImage(imageQuality: 85, maxWidth: 2400, limit: left > 1 ? left : null);
  final result = <PickedImage>[];
  for (final file in files.take(left)) {
    var name = file.name.isEmpty ? 'rasm.jpg' : file.name;
    if (!name.contains('.')) name = '$name.jpg';
    if (!rules.acceptsName(name)) {
      if (context.mounted) showMessage(context, tr('Faqat JPG, PNG yoki WEBP rasm biriktiriladi.'), error: true);
      continue;
    }
    final bytes = await file.readAsBytes();
    if (!rules.acceptsSize(bytes.length)) {
      if (context.mounted) showMessage(context, tr('Rasm hajmi {0} MB dan oshmasin.', <Object?>[(rules.maxKb / 1024).toStringAsFixed(0)]), error: true);
      continue;
    }
    result.add(PickedImage(name, bytes));
  }
  return result;
}

List<http.MultipartFile> imageMultipartFiles(List<PickedImage> picked) =>
    picked.map((item) => http.MultipartFile.fromBytes('attachments[]', item.bytes, filename: item.name)).toList();

class PickedImageStrip extends StatelessWidget {
  const PickedImageStrip({super.key, required this.items, required this.onRemove});

  final List<PickedImage> items;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 76,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) => Stack(children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(items[i].bytes, width: 76, height: 76, fit: BoxFit.cover),
          ),
          Positioned(
            right: 0,
            top: 0,
            child: InkWell(
              onTap: () => onRemove(i),
              child: Container(
                decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                padding: const EdgeInsets.all(2),
                child: const Icon(Icons.close, size: 16, color: Colors.white),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class NewTicketPage extends StatefulWidget {
  const NewTicketPage({super.key, this.meta, this.page = '', this.subject = ''});

  final Map<String, dynamic>? meta;
  final String page;
  final String subject;

  @override
  State<NewTicketPage> createState() => _NewTicketPageState();
}

class _NewTicketPageState extends State<NewTicketPage> {
  late final TextEditingController _name;
  late final TextEditingController _contact;
  late final TextEditingController _subject;
  final _body = TextEditingController();
  String _topic = 'question';
  bool _busy = false;
  String? _error;
  Map<String, String> _errors = <String, String>{};
  Map<String, dynamic> _meta = <String, dynamic>{};
  final List<PickedImage> _files = <PickedImage>[];

  @override
  void initState() {
    super.initState();
    final session = AppScope.read(context);
    _name = TextEditingController(text: session.userName);
    _contact = TextEditingController(text: asText(session.user['phone'], asText(session.user['email'])));
    _subject = TextEditingController(text: widget.subject.length > 150 ? widget.subject.substring(0, 150) : widget.subject);
    _meta = widget.meta ?? <String, dynamic>{};
    if (widget.meta == null || widget.meta!.isEmpty) {
      session.api.get('public/support').then((value) {
        if (mounted) setState(() => _meta = asMap(value));
      }).catchError((_) {});
    }
  }

  @override
  void dispose() {
    for (final controller in <TextEditingController>[_name, _contact, _subject, _body]) {
      controller.dispose();
    }
    super.dispose();
  }

  Map<String, String> get _topics {
    final fromServer = asMap(_meta['topics']);
    if (fromServer.isEmpty) return supportTopicLabels;
    return fromServer.map((key, value) => MapEntry(key, asText(value)));
  }

  SupportAttachmentRules get _rules => SupportAttachmentRules.fromMeta(_meta);

  Future<void> _attach() async {
    final picked = await pickImages(context, _rules, _files.length);
    if (picked.isNotEmpty && mounted) setState(() => _files.addAll(picked));
  }

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _error = null;
      _errors = <String, String>{};
    });
    final session = AppScope.read(context);
    final payload = <String, Object?>{
      'name': _name.text.trim(),
      'contact': _contact.text.trim(),
      'topic': _topic,
      'subject': _subject.text.trim(),
      'body': _body.text.trim(),
      'organization_id': session.organizationId,
      'context': deviceSupportContext(context, widget.page),
    };
    try {
      final data = asMap(_files.isEmpty
          ? await session.api.post('public/support', payload)
          : await session.api.multipart('public/support', fields: supportFields(payload), files: imageMultipartFiles(_files)));
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
    final rules = _rules;
    final contacts = supportContacts(_meta);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Yangi murojaat')), actions: const <Widget>[HelpButton(HelpLinks.support)]),
      body: ListView(
        padding: readable(context, const EdgeInsets.all(16), max: 720),
        children: <Widget>[
          if (_error != null && _errors.isEmpty) ...<Widget>[
            Text(_error!, style: TextStyle(color: AppColors.danger)),
            const SizedBox(height: 12),
          ],
          DropdownButtonFormField<String>(
            key: ValueKey<String>('$_topic-${topics.length}'),
            initialValue: topics.containsKey(_topic) ? _topic : topics.keys.first,
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
          Text(tr("Ilova versiyasi va qurilma turi murojaatga avtomatik qo'shiladi."), style: TextStyle(color: AppColors.muted, fontSize: 12)),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _send,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                : const Icon(Icons.send_rounded),
            label: Text(tr('Yuborish')),
          ),
          if (contacts.isNotEmpty) ...<Widget>[
            const SizedBox(height: 20),
            SupportContactsView(contacts: contacts),
          ],
        ],
      ),
    );
  }
}

/// Murojaat yozishmasi (maxfiy token bo'yicha): javob yozish, rasm biriktirish, yopish va baho.
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
  Map<String, dynamic> _ticket = <String, dynamic>{};
  SupportAttachmentRules _rules = const SupportAttachmentRules();
  final List<PickedImage> _files = <PickedImage>[];

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _load(Api api) async {
    final results = await Future.wait<dynamic>(<Future<dynamic>>[
      api.get('public/support/${widget.token}'),
      api.get('public/support').catchError((_) => null),
    ]);
    _rules = SupportAttachmentRules.fromMeta(asMap(results[1]));
    final ticket = asMap(results[0]);
    if (mounted) setState(() => _ticket = ticket);
    return ticket;
  }

  Future<void> _send() async {
    final text = _reply.text.trim();
    if (text.length < 2) return;
    setState(() => _sending = true);
    final api = AppScope.read(context).api;
    try {
      if (_files.isEmpty) {
        await api.post('public/support/${widget.token}', <String, Object?>{'body': text});
      } else {
        await api.multipart('public/support/${widget.token}', fields: <String, String>{'body': text}, files: imageMultipartFiles(_files));
      }
      _reply.clear();
      _files.clear();
      await _view.currentState?.reload();
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _close() async {
    if (!await confirm(context, tr("Muammo hal bo'ldimi? Murojaat yopiladi. Keyin yozsangiz, u qayta ochiladi."), action: tr('Yopish'))) return;
    if (!mounted) return;
    try {
      await AppScope.read(context).api.post('public/support/${widget.token}/close');
      await _view.currentState?.reload();
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    }
  }

  Future<void> _rate(bool helpful) async {
    try {
      await AppScope.read(context).api.post('public/support/${widget.token}/rate', <String, Object?>{'helpful': helpful});
      await _view.currentState?.reload();
      if (mounted) showMessage(context, tr('Rahmat! Bahoyingiz qabul qilindi.'));
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = AppScope.of(context).api;
    // Yopish — yangi server (1.38: javobda rated_at bor) va murojaat ochiq bo'lsa.
    final canClose = _ticket.containsKey('rated_at') && supportCanClose(asText(_ticket['status']));
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !isEmbeddedDetail(context),
        title: Text(_ticket['id'] == null ? tr('Murojaat') : tr('Murojaat #{0}', <Object?>[asInt(_ticket['id'])])),
        actions: <Widget>[
          if (canClose)
            IconButton(tooltip: tr("Muammo hal bo'ldi"), icon: const Icon(Icons.task_alt), onPressed: _close),
        ],
      ),
      body: Column(children: <Widget>[
        Expanded(
          child: AsyncView<Map<String, dynamic>>(
            key: _view,
            load: () => _load(api),
            builder: (context, ticket, reload) {
              final messages = asList(ticket['messages'], 'messages');
              final status = asText(ticket['status']);
              return ListView(
                padding: readable(context, const EdgeInsets.fromLTRB(16, 12, 16, 16)),
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
                  if (status == 'closed') ...<Widget>[
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(tr('Murojaat yopilgan. Yangi xabar yozsangiz, u qayta ochiladi.'),
                          textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 13)),
                    ),
                    if (supportCanRate(ticket)) ...<Widget>[
                      const SizedBox(height: 12),
                      _RateCard(helpful: ticket['helpful'] is bool ? ticket['helpful'] as bool : null, onRate: _rate),
                    ],
                  ],
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
            child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
              if (_files.isNotEmpty) ...<Widget>[
                PickedImageStrip(items: _files, onRemove: (i) => setState(() => _files.removeAt(i))),
                const SizedBox(height: 6),
              ],
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: <Widget>[
                if (_rules.allowed)
                  IconButton(
                    tooltip: tr('Rasm biriktirish'),
                    onPressed: _sending || _files.length >= _rules.maxFiles
                        ? null
                        : () async {
                            final picked = await pickImages(context, _rules, _files.length);
                            if (picked.isNotEmpty && mounted) setState(() => _files.addAll(picked));
                          },
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                  ),
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
            ]),
          ),
        ),
      ]),
    );
  }
}

class _RateCard extends StatelessWidget {
  const _RateCard({required this.helpful, required this.onRate});

  final bool? helpful;
  final ValueChanged<bool> onRate;

  @override
  Widget build(BuildContext context) {
    final rated = helpful;
    return AppCard(
      color: AppColors.surface2,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Text(rated == null ? tr('Javob foydali bo\'ldimi?') : tr('Bahoyingiz: {0}', <Object?>[rated ? tr('Foydali') : tr('Foydali emas')]),
            style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Row(children: <Widget>[
          Expanded(
            child: OutlinedButton.icon(
              onPressed: rated == true ? null : () => onRate(true),
              icon: const Icon(Icons.thumb_up_alt_outlined, size: 18),
              label: Text(tr('Ha')),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: rated == false ? null : () => onRate(false),
              icon: const Icon(Icons.thumb_down_alt_outlined, size: 18),
              label: Text(tr("Yo'q")),
            ),
          ),
        ]),
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
    final files = supportAttachments(message);
    return Align(
      alignment: staff ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: BoxConstraints(maxWidth: math.min(MediaQuery.of(context).size.width * 0.82, 560)),
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
          if (asText(message['body']).isNotEmpty) SelectableText(asText(message['body']), style: TextStyle(color: AppColors.ink)),
          if (files.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: <Widget>[
              for (final file in files)
                GestureDetector(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ImageViewerPage(url: asText(file['url']), title: asText(file['name'])))),
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
            ]),
          ],
          const SizedBox(height: 4),
          Text(dateTime(message['created_at']), style: TextStyle(fontSize: 11, color: AppColors.muted)),
        ]),
      ),
    );
  }
}

class ImageViewerPage extends StatelessWidget {
  const ImageViewerPage({super.key, required this.url, required this.title});

  final String url;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: Center(child: InteractiveViewer(maxScale: 5, child: Image.network(url))),
    );
  }
}
