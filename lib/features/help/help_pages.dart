// «Yordam» (3.5): yordam markazi qidiruvi, «Ko'p beriladigan savollar», maqolani ilova ichida o'qish va «Yordam berdimi?»,
// murojaat yuborish va «Mening murojaatlarim». API: help/search, help/articles/{slug}, help/articles/{slug}/feedback
// (kirmagan bo'lsa — public/help/...), public/support (aloqa kanallari). Maqola HTML'i — lib/core/help_html.dart.
import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/help_html.dart';
import '../../core/help_links.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/support.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../support/support_page.dart';

/// Yordam API yo'li: kirgan foydalanuvchi — `help/...` (roliga mos saralanadi), aks holda ochiq `public/help/...`.
String helpApi(Session session, String path) => session.signedIn ? 'help/$path' : 'public/help/$path';

class HelpPage extends StatefulWidget {
  const HelpPage({super.key});

  @override
  State<HelpPage> createState() => _HelpPageState();
}

class _HelpPageState extends State<HelpPage> {
  final _query = TextEditingController();
  Timer? _debounce;
  String _searched = '';
  bool _searching = false;
  String? _error;
  List<Map<String, dynamic>> _results = <Map<String, dynamic>>[];
  Map<String, String> _contacts = <String, String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadContacts());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    try {
      final meta = asMap(await AppScope.read(context).api.get('public/support'));
      if (mounted) setState(() => _contacts = supportContacts(meta));
    } catch (_) {
      // aloqa kanallari ixtiyoriy
    }
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(value));
  }

  Future<void> _search(String value) async {
    final query = value.trim();
    if (query.length < 2) {
      setState(() {
        _searched = '';
        _results = <Map<String, dynamic>>[];
        _error = null;
      });
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
    });
    final session = AppScope.read(context);
    try {
      final data = asMap(await session.api.get(helpApi(session, 'search'), query: <String, Object?>{'q': query, 'limit': 15, 'locale': I18n.locale}));
      if (!mounted || _query.text.trim() != query) return;
      setState(() {
        _searched = query;
        _results = asList(data['results'], 'results');
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context);
    final query = _query.text.trim();
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Yordam')),
        actions: <Widget>[
          IconButton(tooltip: tr('Brauzerda ochish'), icon: const Icon(Icons.open_in_new), onPressed: () => HelpLinks.open(context)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: <Widget>[
          TextField(
            controller: _query,
            textInputAction: TextInputAction.search,
            onChanged: _onChanged,
            onSubmitted: _search,
            decoration: InputDecoration(
              hintText: tr('Yordam markazidan qidirish'),
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searching
                  ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                  : query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: tr('Tozalash'),
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _query.clear();
                            _search('');
                          },
                        ),
            ),
          ),
          const SizedBox(height: 12),
          if (_error != null) Text(_error!, style: TextStyle(color: AppColors.danger)),
          if (query.length >= 2 && _searched.isNotEmpty) ...<Widget>[
            if (_results.isEmpty)
              EmptyState(
                icon: Icons.search_off_rounded,
                text: tr("«{0}» bo'yicha maqola topilmadi. Boshqa so'z bilan qidiring yoki murojaat yuboring.", <Object?>[_searched]),
                action: OutlinedButton.icon(
                  onPressed: () => openNewTicket(context, page: 'help/search', subject: _searched),
                  icon: const Icon(Icons.edit_outlined),
                  label: Text(tr('Murojaat yuborish')),
                ),
              )
            else
              for (final item in _results) ...<Widget>[
                _ResultCard(item: item),
                const SizedBox(height: 8),
              ],
          ] else ...<Widget>[
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(children: <Widget>[
                _tile(Icons.quiz_outlined, tr("Ko'p beriladigan savollar"), tr('Kirish, parol, to\'lov, davomat va ilova haqida qisqa javoblar.'),
                    () => HelpLinks.show(context, HelpLinks.faq)),
                const Divider(height: 1),
                _tile(Icons.build_circle_outlined, tr('Muammolar va yechimlar'), tr("Kod kelmasa, ilova ochilmasa yoki to'lov o'tmasa."),
                    () => HelpLinks.show(context, HelpLinks.problems)),
                const Divider(height: 1),
                _tile(Icons.menu_book_outlined, tr('Yordam markazi'), tr("Barcha qo'llanmalar — brauzerda."), () => HelpLinks.open(context),
                    trailing: const Icon(Icons.open_in_new, size: 18)),
              ]),
            ),
            SectionTitle(tr("Qo'llab-quvvatlash")),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(children: <Widget>[
                _tile(Icons.edit_outlined, tr('Murojaat yuborish'), tr("Savol, xatolik yoki taklif — EduX jamoasi javob beradi."),
                    () => openNewTicket(context, page: 'help')),
                if (session.signedIn) ...<Widget>[
                  const Divider(height: 1),
                  _tile(Icons.support_agent_outlined, tr('Mening murojaatlarim'), tr('Yuborilgan murojaatlar va javoblar.'),
                      () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SupportPage()))),
                ],
              ]),
            ),
            if (_contacts.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              SupportContactsView(contacts: _contacts),
            ],
          ],
        ],
      ),
    );
  }

  Widget _tile(IconData icon, String title, String subtitle, VoidCallback onTap, {Widget? trailing}) {
    return ListTile(
      leading: Icon(icon, color: AppColors.brand),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle),
      trailing: trailing ?? const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final snippet = parseHelpInline(asText(item['snippet']));
    return AppCard(
      onTap: () => HelpLinks.show(context, asText(item['slug'])),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Text(asText(item['title']), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        if (snippet.isNotEmpty) ...<Widget>[
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(children: <InlineSpan>[
              for (final span in snippet)
                TextSpan(
                  text: span.text,
                  style: span.mark ? TextStyle(backgroundColor: AppColors.soft(AppColors.warning), color: AppColors.ink, fontWeight: FontWeight.w600) : null,
                ),
            ]),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: AppColors.muted, fontSize: 13, height: 1.35),
          ),
        ],
      ]),
    );
  }
}

/// Bitta maqola (ilova ichida). [slug] — serverdagi maqola nomi.
class HelpArticlePage extends StatefulWidget {
  const HelpArticlePage({super.key, required this.slug});

  final String slug;

  @override
  State<HelpArticlePage> createState() => _HelpArticlePageState();
}

class _HelpArticlePageState extends State<HelpArticlePage> {
  bool? _helpful;
  bool _sending = false;

  Future<Map<String, dynamic>> _load(Session session) async {
    final data = asMap(await session.api.get(helpApi(session, 'articles/${widget.slug}'), query: <String, Object?>{'locale': I18n.locale}));
    return data;
  }

  Future<void> _feedback(bool helpful) async {
    final session = AppScope.read(context);
    setState(() => _sending = true);
    try {
      await session.api.post(helpApi(session, 'articles/${widget.slug}/feedback'), <String, Object?>{'helpful': helpful});
      if (mounted) setState(() => _helpful = helpful);
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Yordam')),
        actions: <Widget>[
          IconButton(tooltip: tr('Brauzerda ochish'), icon: const Icon(Icons.open_in_new), onPressed: () => HelpLinks.open(context, widget.slug)),
        ],
      ),
      body: AsyncView<Map<String, dynamic>>(
        load: () => _load(session),
        cacheKey: 'help_${widget.slug}_${I18n.locale}_${session.signedIn ? 'in' : 'out'}',
        decode: (raw) => asMap(raw),
        builder: (context, article, reload) {
          final blocks = parseHelpHtml(asText(article['html']));
          final related = asList(article['related'], 'related');
          final video = article['video'];
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: <Widget>[
              Text(asText(article['title']), style: AppTheme.title(size: 22)),
              if (asText(article['summary']).isNotEmpty) ...<Widget>[
                const SizedBox(height: 6),
                Text(asText(article['summary']), style: TextStyle(color: AppColors.muted, fontSize: 15, height: 1.4)),
              ],
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 6, children: <Widget>[
                if (asText(asMap(article['section'])['title']).isNotEmpty) Pill(asText(asMap(article['section'])['title']), color: AppColors.muted),
                if (article['reading_minutes'] != null) Pill(tr('{0} daqiqa', <Object?>[asInt(article['reading_minutes'])]), color: AppColors.muted),
              ]),
              if (video != null && video != false) ...<Widget>[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => HelpLinks.open(context, widget.slug),
                  icon: const Icon(Icons.play_circle_outline),
                  label: Text(tr("Videoni ko'rish")),
                ),
              ],
              const SizedBox(height: 12),
              HelpContent(blocks: blocks),
              const SizedBox(height: 20),
              _FeedbackCard(
                helpful: _helpful,
                busy: _sending,
                onAnswer: _feedback,
                onSupport: () => openNewTicket(context, page: 'help/${widget.slug}', subject: asText(article['title'])),
              ),
              if (related.isNotEmpty) ...<Widget>[
                SectionTitle(tr("O'xshash maqolalar")),
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(children: <Widget>[
                    for (var i = 0; i < related.length; i++) ...<Widget>[
                      if (i > 0) const Divider(height: 1),
                      ListTile(
                        leading: Icon(Icons.article_outlined, color: AppColors.brand),
                        title: Text(asText(related[i]['title'])),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => HelpLinks.show(context, asText(related[i]['slug'])),
                      ),
                    ],
                  ]),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _FeedbackCard extends StatelessWidget {
  const _FeedbackCard({required this.helpful, required this.busy, required this.onAnswer, required this.onSupport});

  final bool? helpful;
  final bool busy;
  final ValueChanged<bool> onAnswer;
  final VoidCallback onSupport;

  @override
  Widget build(BuildContext context) {
    final answered = helpful;
    return AppCard(
      color: AppColors.surface2,
      child: answered == null
          ? Row(children: <Widget>[
              Expanded(child: Text(tr('Yordam berdimi?'), style: const TextStyle(fontWeight: FontWeight.w700))),
              OutlinedButton.icon(
                onPressed: busy ? null : () => onAnswer(true),
                icon: const Icon(Icons.thumb_up_alt_outlined, size: 18),
                label: Text(tr('Ha')),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: busy ? null : () => onAnswer(false),
                icon: const Icon(Icons.thumb_down_alt_outlined, size: 18),
                label: Text(tr("Yo'q")),
              ),
            ])
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text(tr('Rahmat! Fikringiz maqolani yaxshilashga yordam beradi.'), style: const TextStyle(fontWeight: FontWeight.w600)),
              if (!answered) ...<Widget>[
                const SizedBox(height: 8),
                Text(tr("Javob topilmadimi? Murojaat yuboring — EduX jamoasi yordam beradi."), style: TextStyle(color: AppColors.muted)),
                const SizedBox(height: 8),
                FilledButton.icon(onPressed: onSupport, icon: const Icon(Icons.edit_outlined), label: Text(tr('Murojaat yuborish'))),
              ],
            ]),
    );
  }
}

/// Maqola matni: sarlavhalar, paragraflar, ro'yxatlar, «Eslatma/Diqqat» bloklari, rasmlar va jadvallar.
class HelpContent extends StatelessWidget {
  const HelpContent({super.key, required this.blocks});

  final List<HelpBlock> blocks;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (final block in blocks) {
      final widget = _block(context, block);
      if (block.quote != null && block.type != HelpBlockType.rule) {
        final warning = block.quote == 'warning';
        final color = warning ? AppColors.warning : (block.quote == 'note' ? AppColors.brand : AppColors.muted);
        children.add(Container(
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          decoration: BoxDecoration(color: AppColors.soft(color), border: Border(left: BorderSide(color: color, width: 3))),
          child: widget,
        ));
      } else {
        children.add(widget);
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }

  Widget _block(BuildContext context, HelpBlock block) {
    switch (block.type) {
      case HelpBlockType.heading:
        return Padding(
          padding: EdgeInsets.only(top: block.level <= 2 ? 18 : 12, bottom: 6),
          child: HelpRichText(spans: block.spans, style: AppTheme.title(size: block.level <= 2 ? 18 : 16)),
        );
      case HelpBlockType.item:
        final indent = 4.0 + 18.0 * (block.level - 1).clamp(0, 4);
        return Padding(
          padding: EdgeInsets.only(left: indent, bottom: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            SizedBox(
              width: 22,
              child: Text(block.ordered ? '${block.index}.' : '•', style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700, height: 1.45)),
            ),
            Expanded(child: HelpRichText(spans: block.spans)),
          ]),
        );
      case HelpBlockType.image:
        final api = AppScope.read(context).api;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(
              api.absolute(block.src ?? ''),
              fit: BoxFit.contain,
              semanticLabel: block.alt,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
        );
      case HelpBlockType.table:
        return Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: _HelpTable(rows: block.rows));
      case HelpBlockType.code:
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.line)),
          child: SelectableText(block.text, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
        );
      case HelpBlockType.rule:
        return const Divider(height: 24);
      case HelpBlockType.paragraph:
        return Padding(padding: const EdgeInsets.only(bottom: 10), child: HelpRichText(spans: block.spans));
    }
  }
}

class _HelpTable extends StatelessWidget {
  const _HelpTable({required this.rows});

  final List<List<List<HelpSpan>>> rows;

  @override
  Widget build(BuildContext context) {
    final columns = rows.fold<int>(0, (max, row) => row.length > max ? row.length : max);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        border: TableBorder.all(color: AppColors.line),
        children: <TableRow>[
          for (var r = 0; r < rows.length; r++)
            TableRow(
              decoration: r == 0 ? BoxDecoration(color: AppColors.surface2) : null,
              children: <Widget>[
                for (var c = 0; c < columns; c++)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: c < rows[r].length ? HelpRichText(spans: rows[r][c], style: const TextStyle(fontSize: 13)) : const SizedBox.shrink(),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Matn bo'laklari (qalin, kursiv, kod, havola). Havola: boshqa maqola — ilova ichida, qolgani — brauzerda.
class HelpRichText extends StatefulWidget {
  const HelpRichText({super.key, required this.spans, this.style});

  final List<HelpSpan> spans;
  final TextStyle? style;

  @override
  State<HelpRichText> createState() => _HelpRichTextState();
}

class _HelpRichTextState extends State<HelpRichText> {
  final List<TapGestureRecognizer> _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    super.dispose();
  }

  void _open(String href) {
    final slug = HelpLinks.slugOf(href);
    if (slug != null) {
      HelpLinks.show(context, slug);
      return;
    }
    if (href.startsWith('#')) return;
    final api = AppScope.read(context).api;
    final target = href.startsWith('http://') || href.startsWith('https://') || href.startsWith('mailto:') || href.startsWith('tel:')
        ? href
        : api.absolute(href);
    final uri = Uri.tryParse(target);
    if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
    final base = TextStyle(color: AppColors.ink, fontSize: 15, height: 1.45).merge(widget.style);
    return Text.rich(TextSpan(
      style: base,
      children: <InlineSpan>[
        for (final span in widget.spans) _span(span),
      ],
    ));
  }

  TextSpan _span(HelpSpan span) {
    TapGestureRecognizer? recognizer;
    final href = span.href;
    if (href != null) {
      recognizer = TapGestureRecognizer()..onTap = () => _open(href);
      _recognizers.add(recognizer);
    }
    return TextSpan(
      text: span.text,
      recognizer: recognizer,
      style: TextStyle(
        fontWeight: span.bold ? FontWeight.w700 : null,
        fontStyle: span.italic ? FontStyle.italic : null,
        fontFamily: span.code ? 'monospace' : null,
        backgroundColor: span.code ? AppColors.surface2 : (span.mark ? AppColors.soft(AppColors.warning) : null),
        color: href != null ? AppColors.brand : null,
        decoration: href != null ? TextDecoration.underline : null,
      ),
    );
  }
}
