// Hujjatlar (3.13, server 1.47): «Hujjatlarim» — menga, tashkilotimga yoki farzandimga yuborilgan shartnoma, buyruq va
// ma'lumotnomalar (o'qish va «Tanishdim va roziman»), rahbar va platforma egasi uchun — berilgan hujjatlar ro'yxati,
// yuborish va bekor qilish. Yangi hujjat tuzish — veb panelda (shablon muharriri katta ekranda qulay).
// Hujjat ixtiyoriy: tasdiqlanmagani ilovadagi hech bir imkoniyatni yopmaydi.
// API: GET my/documents, GET my/documents/{id}, POST my/documents/{id}/sign; GET [platform/]documents, GET .../{id},
// POST .../{id}/issue, POST .../{id}/cancel.
import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/web_links.dart';
import '../../core/widgets.dart';

const Map<String, String> documentKindLabels = <String, String>{
  'contract': 'Shartnoma',
  'agreement': 'Kelishuv',
  'order': 'Buyruq',
  'act': 'Dalolatnoma',
  'consent': 'Rozilik',
  'certificate': "Ma'lumotnoma",
  'application': 'Ariza',
  'other': 'Boshqa',
};

/// Holat yorlig'i va rangi.
(String, Color) documentStatus(Map<String, dynamic> item) {
  if (item['awaiting'] == true) return (tr('Tasdiqlang'), AppColors.warning);
  switch (asText(item['status'])) {
    case 'draft':
      return (tr('Qoralama'), AppColors.muted);
    case 'issued':
      return (tr('Tasdiq kutilmoqda'), AppColors.warning);
    case 'signed':
      return (asText(item['sign_method']) == 'issuer' ? tr('Berilgan') : tr('Tasdiqlangan'), AppColors.success);
    case 'cancelled':
      return (tr('Bekor qilingan'), AppColors.danger);
  }
  return (asText(item['status']), AppColors.muted);
}

class DocumentTile extends StatelessWidget {
  const DocumentTile({super.key, required this.item, required this.onTap, this.showParty = false});

  final Map<String, dynamic> item;
  final VoidCallback onTap;
  final bool showParty;

  @override
  Widget build(BuildContext context) {
    final (label, color) = documentStatus(item);
    final meta = <String>[
      '№ ${asText(item['number'])}',
      date(item['date']),
      tr(documentKindLabels[asText(item['kind'])] ?? asText(item['kind'])),
      if (showParty) asText(item['party_name']) else asText(item['issuer'], tr('Platforma')),
    ].where((part) => part.isNotEmpty).join(' · ');
    return ListTile(
      leading: Icon(Icons.description_outlined, color: AppColors.muted),
      title: Text(asText(item['title']), style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(meta, style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
      trailing: Pill(label, color: color),
      onTap: onTap,
    );
  }
}

/// «Hujjatlarim».
class MyDocumentsPage extends StatelessWidget {
  const MyDocumentsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: pageBar(context, title: Text(tr('Hujjatlarim'))),
      body: AsyncView<Map<String, dynamic>>(
        load: () async => asMap(await AppScope.read(context).api.get('my/documents')),
        builder: (context, data, reload) {
          final items = asList(data['data']);
          if (items.isEmpty) {
            return ListView(children: <Widget>[EmptyState(text: tr('Sizga hali hujjat yuborilmagan.'), icon: Icons.description_outlined)]);
          }
          final awaiting = items.where((item) => item['awaiting'] == true).toList();
          final others = items.where((item) => item['awaiting'] != true).toList();
          Widget group(String title, List<Map<String, dynamic>> list) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                SectionTitle(title),
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(children: <Widget>[
                    for (final item in list)
                      DocumentTile(
                        item: item,
                        onTap: () async {
                          await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => MyDocumentPage(id: asInt(item['id']))));
                          await reload();
                        },
                      ),
                  ]),
                ),
                const SizedBox(height: 14),
              ]);
          return ListView(padding: const EdgeInsets.all(16), children: <Widget>[
            Text(tr("Sizga, tashkilotingizga yoki farzandingizga yuborilgan shartnoma, buyruq va ma'lumotnomalar. Tasdiqlash ixtiyoriy — tizimdan foydalanishga ta'sir qilmaydi."),
                style: TextStyle(color: AppColors.muted)),
            const SizedBox(height: 12),
            if (awaiting.isNotEmpty) group(tr('Tasdiq kutmoqda'), awaiting),
            if (others.isNotEmpty) group(tr('Boshqa hujjatlar'), others),
          ]);
        },
      ),
    );
  }
}

/// Bitta hujjat: o'qish va tasdiqlash.
class MyDocumentPage extends StatefulWidget {
  const MyDocumentPage({super.key, required this.id});

  final int id;

  @override
  State<MyDocumentPage> createState() => _MyDocumentPageState();
}

class _MyDocumentPageState extends State<MyDocumentPage> {
  final GlobalKey<AsyncViewState<Map<String, dynamic>>> _view = GlobalKey<AsyncViewState<Map<String, dynamic>>>();
  bool _agree = false;
  bool _busy = false;

  Future<void> _sign() async {
    setState(() => _busy = true);
    try {
      final data = asMap(await AppScope.read(context).api.post('my/documents/${widget.id}/sign', <String, dynamic>{'agree': true}));
      if (mounted) showMessage(context, asText(data['kind']) == 'order' ? tr('Tanishganingiz qayd etildi.') : tr('Hujjat tasdiqlandi.'));
      await _view.currentState?.reload();
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: pageBar(context, title: Text(tr('Hujjat')), actions: <Widget>[
        IconButton(
          tooltip: tr('Chop etish / PDF'),
          icon: const Icon(Icons.print_outlined),
          onPressed: () => openWebPage(AppScope.read(context).api, '/documents/my/${widget.id}'),
        ),
      ]),
      body: AsyncView<Map<String, dynamic>>(
        key: _view,
        load: () async => asMap(await AppScope.read(context).api.get('my/documents/${widget.id}')),
        builder: (context, doc, reload) {
          final order = asText(doc['kind']) == 'order';
          return ListView(padding: const EdgeInsets.all(16), children: <Widget>[
            Text(asText(doc['title']), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('№ ${asText(doc['number'])} · ${date(doc['date'])} · ${asText(doc['issuer'], tr('Platforma'))}', style: TextStyle(color: AppColors.muted)),
            const SizedBox(height: 12),
            if (doc['awaiting'] == true)
              ToneBox(
                color: AppColors.warning,
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _agree,
                    onChanged: (value) => setState(() => _agree = value ?? false),
                    title: Text(order ? tr("Buyruq bilan to'liq tanishdim.") : tr("Hujjat bilan to'liq tanishdim va uning shartlariga roziman.")),
                  ),
                  Text(tr("Tasdiqlaganingizda ismingiz, sana, vaqt va IP manzil hujjatga yoziladi. Savolingiz bo'lsa, tasdiqlamay turib hujjatni bergan tashkilotga murojaat qiling."),
                      style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
                  const SizedBox(height: 10),
                  FilledButton(onPressed: _agree && !_busy ? _sign : null, child: Text(order ? tr('Tanishdim') : tr('Tasdiqlayman'))),
                ]),
              )
            else if (asText(doc['status']) == 'signed' && asText(doc['sign_method']) == 'online')
              ToneBox(
                color: AppColors.success,
                padding: const EdgeInsets.all(12),
                child: Text(tr('Tasdiqlangan: {0}, {1}.', <Object?>[asText(doc['signer_name']), dateTime(doc['signed_at'])])),
              )
            else if (asText(doc['status']) == 'cancelled')
              ToneBox(
                color: AppColors.danger,
                padding: const EdgeInsets.all(12),
                child: Text(tr('Hujjat bekor qilingan: {0}', <Object?>[asText(doc['cancel_reason'])])),
              ),
            const SizedBox(height: 14),
            DocumentSheet(blocks: asList(doc['blocks']), verifyCode: asText(doc['verify_code'])),
          ]);
        },
      ),
    );
  }
}

/// Hujjat varag'i: server bloklari (sarlavha, xatboshi, ro'yxat, rekvizitlar) — oq qog'oz ko'rinishida.
class DocumentSheet extends StatelessWidget {
  const DocumentSheet({super.key, required this.blocks, this.verifyCode = ''});

  final List<Map<String, dynamic>> blocks;
  final String verifyCode;

  static const Color _ink = Color(0xFF111827);

  /// **qalin** belgisi → qalin matn.
  static List<TextSpan> spans(String text) {
    final parts = <TextSpan>[];
    final pattern = RegExp(r'\*\*(.+?)\*\*');
    var index = 0;
    for (final match in pattern.allMatches(text)) {
      if (match.start > index) parts.add(TextSpan(text: text.substring(index, match.start)));
      parts.add(TextSpan(text: match.group(1), style: const TextStyle(fontWeight: FontWeight.w700)));
      index = match.end;
    }
    if (index < text.length) parts.add(TextSpan(text: text.substring(index)));
    return parts;
  }

  Widget _text(String text, {TextAlign align = TextAlign.start, double size = 14.5, FontWeight weight = FontWeight.w400}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text.rich(
        TextSpan(children: spans(text)),
        textAlign: align,
        style: TextStyle(fontFamily: 'serif', color: _ink, fontSize: size, height: 1.45, fontWeight: weight),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (final block in blocks) {
      final text = asText(block['text']);
      switch (asText(block['type'])) {
        case 'h1':
          children.add(_text(text, align: TextAlign.center, size: 16.5, weight: FontWeight.w700));
        case 'h2':
          children.add(Padding(padding: const EdgeInsets.only(top: 6), child: _text(text, weight: FontWeight.w700)));
        case 'center':
          children.add(_text(text, align: TextAlign.center));
        case 'right':
          children.add(_text(text, align: TextAlign.right));
        case 'li':
          children.add(Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              const Text('•  ', style: TextStyle(color: _ink, fontSize: 14.5, height: 1.45)),
              Expanded(child: _text(text)),
            ]),
          ));
        case 'hr':
          children.add(const Divider(color: Color(0xFF9CA3AF)));
        case 'party':
          children.add(Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 6, bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE5E7EB)), borderRadius: BorderRadius.circular(6)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text(asText(block['role']), style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12.5)),
              Text(text, style: const TextStyle(color: _ink, fontWeight: FontWeight.w700, fontSize: 14.5)),
              for (final line in asList(block['lines']).map((item) => item.toString()))
                Text(line, style: const TextStyle(color: Color(0xFF374151), fontSize: 13)),
              const SizedBox(height: 6),
              Text(asText(block['sign']), style: const TextStyle(color: _ink, fontSize: 13)),
            ]),
          ));
        case 'sign':
        case 'ack':
          children.add(Padding(padding: const EdgeInsets.only(top: 14), child: _text(text, weight: FontWeight.w600)));
        default:
          children.add(_text(text, align: TextAlign.justify));
      }
    }
    if (verifyCode.isNotEmpty) {
      children.add(Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(tr('Tekshirish kodi: {0}', <Object?>[verifyCode]), style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12)),
      ));
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFE5E7EB))),
      child: SelectionArea(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children)),
    );
  }
}

/// Rahbar (tashkilot) yoki platforma egasi: berilgan hujjatlar. [platform] — tashkilotlar bilan shartnomalar.
class IssuedDocumentsPage extends StatefulWidget {
  const IssuedDocumentsPage({super.key, this.platform = false});

  final bool platform;

  @override
  State<IssuedDocumentsPage> createState() => _IssuedDocumentsPageState();
}

class _IssuedDocumentsPageState extends State<IssuedDocumentsPage> {
  String _status = '';

  String get _base => widget.platform ? 'platform/documents' : 'documents';

  @override
  Widget build(BuildContext context) {
    final statuses = <String, String>{'': tr('Hammasi'), 'draft': tr('Qoralama'), 'issued': tr('Tasdiq kutilmoqda'), 'signed': tr('Kuchda'), 'cancelled': tr('Bekor qilingan')};
    return Scaffold(
      appBar: pageBar(context, title: Text(tr('Hujjatlar')), actions: <Widget>[
        IconButton(
          tooltip: tr('Yangi hujjat'),
          icon: const Icon(Icons.add),
          onPressed: () => openWebPage(AppScope.read(context).api, widget.platform ? '/platform/documents/new' : '/documents/new'),
        ),
      ]),
      body: AsyncView<Map<String, dynamic>>(
        key: ValueKey<String>(_status),
        load: () async => asMap(await AppScope.read(context).api.get(_base, query: <String, dynamic>{if (_status.isNotEmpty) 'status': _status})),
        builder: (context, data, reload) {
          final items = asList(data['data']);
          return ListView(padding: const EdgeInsets.all(16), children: <Widget>[
            Text(tr("Hujjatlar ixtiyoriy: hujjati yo'q xodim yoki o'quvchi bilan ham tizim to'liq ishlaydi. Bu yerda faqat kimda bor, kimda yo'qligi ko'rinadi."),
                style: TextStyle(color: AppColors.muted, fontSize: 13)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
              for (final entry in statuses.entries)
                ChoiceChip(
                  label: Text(entry.key.isEmpty ? entry.value : '${entry.value} ${asInt(asMap(data['counts'])[entry.key])}'),
                  selected: _status == entry.key,
                  onSelected: (_) => setState(() => _status = entry.key),
                ),
            ]),
            const SizedBox(height: 12),
            if (items.isEmpty)
              EmptyState(text: tr("Bu shartga mos hujjat yo'q."), icon: Icons.description_outlined)
            else
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(children: <Widget>[
                  for (final item in items)
                    DocumentTile(
                      item: item,
                      showParty: true,
                      onTap: () async {
                        await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => IssuedDocumentPage(id: asInt(item['id']), platform: widget.platform)));
                        await reload();
                      },
                    ),
                ]),
              ),
          ]);
        },
      ),
    );
  }
}

class IssuedDocumentPage extends StatefulWidget {
  const IssuedDocumentPage({super.key, required this.id, this.platform = false});

  final int id;
  final bool platform;

  @override
  State<IssuedDocumentPage> createState() => _IssuedDocumentPageState();
}

class _IssuedDocumentPageState extends State<IssuedDocumentPage> {
  final GlobalKey<AsyncViewState<Map<String, dynamic>>> _view = GlobalKey<AsyncViewState<Map<String, dynamic>>>();
  bool _busy = false;

  String get _url => '${widget.platform ? 'platform/documents' : 'documents'}/${widget.id}';

  Future<void> _action(String path, String done, {Map<String, dynamic>? body}) async {
    setState(() => _busy = true);
    try {
      await AppScope.read(context).api.post('$_url/$path', body ?? <String, dynamic>{});
      if (mounted) showMessage(context, done);
      await _view.currentState?.reload();
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Bekor qilish sababi')),
        content: TextField(controller: controller, autofocus: true, maxLength: 300),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Yopish'))),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: Text(tr('Bekor qilish'))),
        ],
      ),
    );
    controller.dispose();
    if (reason == null || reason.length < 3) return;
    await _action('cancel', tr('Hujjat bekor qilindi.'), body: <String, dynamic>{'reason': reason});
  }

  @override
  Widget build(BuildContext context) {
    final web = widget.platform ? '/platform/documents/${widget.id}' : '/documents/${widget.id}';
    return Scaffold(
      appBar: pageBar(context, title: Text(tr('Hujjat')), actions: <Widget>[
        IconButton(tooltip: tr('Chop etish / PDF'), icon: const Icon(Icons.print_outlined), onPressed: () => openWebPage(AppScope.read(context).api, web)),
      ]),
      body: AsyncView<Map<String, dynamic>>(
        key: _view,
        load: () async => asMap(await AppScope.read(context).api.get(_url)),
        builder: (context, doc, reload) {
          final (label, color) = documentStatus(doc);
          final status = asText(doc['status']);
          return ListView(padding: const EdgeInsets.all(16), children: <Widget>[
            Text(asText(doc['title']), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('№ ${asText(doc['number'])} · ${date(doc['date'])} · ${asText(doc['party_name'])}', style: TextStyle(color: AppColors.muted)),
            const SizedBox(height: 8),
            Align(alignment: Alignment.centerLeft, child: Pill(label, color: color)),
            if (doc['signed_at'] != null && asText(doc['sign_method']) != 'issuer') ...<Widget>[
              const SizedBox(height: 8),
              Text('${asText(doc['signer_name'])}, ${dateTime(doc['signed_at'])}${asText(doc['sign_ip']).isNotEmpty ? ' · IP ${asText(doc['sign_ip'])}' : ''}',
                  style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
            ],
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
              if (status == 'draft')
                FilledButton(
                  onPressed: _busy ? null : () => _action('issue', doc['requires_signature'] == true ? tr('Tarafga yuborildi.') : tr('Hujjat berildi.')),
                  child: Text(doc['requires_signature'] == true ? tr('Tasdiqlashga yuborish') : tr('Berish')),
                ),
              if (status == 'issued' || status == 'signed')
                OutlinedButton(onPressed: _busy ? null : _cancel, child: Text(tr('Bekor qilish'))),
            ]),
            const SizedBox(height: 14),
            DocumentSheet(blocks: asList(doc['blocks']), verifyCode: asText(doc['verify_code'])),
          ]);
        },
      ),
    );
  }
}
