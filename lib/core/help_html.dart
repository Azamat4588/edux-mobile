// Yordam maqolasi HTML'ini (server: HelpCatalog — CommonMark natijasi) ilova bloklariga aylantirish. Yangi paket
// qo'shmaslik uchun oddiy o'quvchi: sarlavha (h2/h3), paragraf, ro'yxat, «Eslatma/Diqqat» bloki, rasm, jadval, kod.
// Matn ichida: qalin, kursiv, kod, havola, <mark> (qidiruv natijasi). Toza mantiq — test/help_html_test.dart.

/// Matn bo'lagi.
class HelpSpan {
  const HelpSpan(this.text, {this.bold = false, this.italic = false, this.code = false, this.mark = false, this.href});

  final String text;
  final bool bold;
  final bool italic;
  final bool code;
  final bool mark;
  final String? href;

  @override
  String toString() => text;
}

/// Blok turi.
enum HelpBlockType { heading, paragraph, item, image, table, code, rule }

class HelpBlock {
  HelpBlock(
    this.type, {
    this.spans = const <HelpSpan>[],
    this.level = 0,
    this.ordered = false,
    this.index = 0,
    this.quote,
    this.id,
    this.src,
    this.alt,
    this.rows = const <List<List<HelpSpan>>>[],
  });

  final HelpBlockType type;
  final List<HelpSpan> spans;

  /// Sarlavha darajasi (2, 3) yoki ro'yxat chuqurligi (1 dan).
  final int level;
  final bool ordered;

  /// Tartibli ro'yxatdagi raqam.
  final int index;

  /// Blok «Eslatma» (note), «Diqqat» (warning) yoki oddiy iqtibos (quote) ichida bo'lsa.
  final String? quote;

  /// Sarlavha id si (mundarija havolasi).
  final String? id;
  final String? src;
  final String? alt;

  /// Jadval: qatorlar → kataklar → matn bo'laklari (birinchi qator — sarlavha bo'lishi mumkin).
  final List<List<List<HelpSpan>>> rows;

  String get text => spans.map((span) => span.text).join();
}

final RegExp _tag = RegExp(r'<(/?)([a-zA-Z][a-zA-Z0-9]*)([^>]*?)(/?)>|<!--.*?-->', dotAll: true);

String _attr(String attrs, String name) {
  final match = RegExp('$name\\s*=\\s*("([^"]*)"|\'([^\']*)\')').firstMatch(attrs);
  if (match == null) return '';
  return decodeEntities(match.group(2) ?? match.group(3) ?? '');
}

/// HTML belgilari: &amp; &lt; &gt; &quot; &#039; &nbsp; &#8212; &#x2014; ...
String decodeEntities(String value) {
  if (!value.contains('&')) return value;
  const named = <String, String>{
    'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"', 'apos': "'", 'nbsp': '\u00A0', 'mdash': '—', 'ndash': '–',
    'laquo': '«', 'raquo': '»', 'hellip': '…', 'rsquo': '’', 'lsquo': '‘', 'ldquo': '“', 'rdquo': '”', 'times': '×',
    'rarr': '→', 'larr': '←', 'copy': '©',
  };
  return value.replaceAllMapped(RegExp(r'&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);'), (m) {
    final code = m.group(1)!;
    if (code.startsWith('#x') || code.startsWith('#X')) {
      final number = int.tryParse(code.substring(2), radix: 16);
      return number == null ? m.group(0)! : String.fromCharCode(number);
    }
    if (code.startsWith('#')) {
      final number = int.tryParse(code.substring(1));
      return number == null ? m.group(0)! : String.fromCharCode(number);
    }
    return named[code.toLowerCase()] ?? m.group(0)!;
  });
}

class _Style {
  bool bold = false;
  bool italic = false;
  bool code = false;
  bool mark = false;
  String? href;
}

class _ListState {
  _ListState(this.ordered, this.next);

  final bool ordered;
  int next;
}

class _Parser {
  final List<HelpBlock> blocks = <HelpBlock>[];
  List<HelpSpan> _spans = <HelpSpan>[];
  final _Style _style = _Style();
  final List<String> _inline = <String>[];
  final List<_ListState> _lists = <_ListState>[];
  final List<String> _quotes = <String>[];

  // Joriy blok: heading / item / code / null (paragraf).
  HelpBlockType _current = HelpBlockType.paragraph;
  int _level = 0;
  String? _id;
  int _itemIndex = 0;
  bool _itemOrdered = false;
  bool _pre = false;

  // Jadval
  List<List<List<HelpSpan>>>? _table;
  List<List<HelpSpan>>? _row;

  void text(String raw) {
    var value = decodeEntities(raw);
    if (!_pre) value = value.replaceAll(RegExp(r'\s+'), ' ');
    if (value.isEmpty) return;
    // Blok boshidagi bo'sh joy kerak emas.
    if (_spans.isEmpty && !_pre) {
      value = value.trimLeft();
      if (value.isEmpty) return;
    }
    _spans.add(HelpSpan(value, bold: _style.bold, italic: _style.italic, code: _style.code || _pre, mark: _style.mark, href: _style.href));
  }

  String? get _quote => _quotes.isEmpty ? null : _quotes.last;

  List<HelpSpan> _takeSpans() {
    final spans = _spans;
    _spans = <HelpSpan>[];
    // Oxirgi bo'sh joylarni olib tashlash.
    while (spans.isNotEmpty && !_pre) {
      final last = spans.last;
      final trimmed = last.text.trimRight();
      if (trimmed == last.text) break;
      spans.removeLast();
      if (trimmed.isNotEmpty) {
        spans.add(HelpSpan(trimmed, bold: last.bold, italic: last.italic, code: last.code, mark: last.mark, href: last.href));
        break;
      }
    }
    return spans;
  }

  /// Joriy matnni blok sifatida yopish.
  void flush() {
    if (_row != null) return; // jadval katagida — katak yopilganda olinadi
    final spans = _takeSpans();
    if (spans.isEmpty || spans.every((span) => span.text.trim().isEmpty)) {
      return;
    }
    switch (_current) {
      case HelpBlockType.heading:
        blocks.add(HelpBlock(HelpBlockType.heading, spans: spans, level: _level, id: _id, quote: _quote));
      case HelpBlockType.item:
        blocks.add(HelpBlock(HelpBlockType.item, spans: spans, level: _lists.length, ordered: _itemOrdered, index: _itemIndex, quote: _quote));
      case HelpBlockType.code:
        blocks.add(HelpBlock(HelpBlockType.code, spans: spans, quote: _quote));
      default:
        blocks.add(HelpBlock(HelpBlockType.paragraph, spans: spans, quote: _quote));
    }
  }

  void open(String name, String attrs) {
    switch (name) {
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        flush();
        _current = HelpBlockType.heading;
        _level = int.parse(name.substring(1)).clamp(2, 4);
        _id = _attr(attrs, 'id');
        if (_id!.isEmpty) _id = null;
      case 'p':
        flush();
        if (_current != HelpBlockType.item) _current = HelpBlockType.paragraph;
      case 'ul':
      case 'ol':
        flush();
        final start = int.tryParse(_attr(attrs, 'start')) ?? 1;
        _lists.add(_ListState(name == 'ol', start));
      case 'li':
        flush();
        _current = HelpBlockType.item;
        if (_lists.isEmpty) _lists.add(_ListState(false, 1));
        final list = _lists.last;
        _itemOrdered = list.ordered;
        _itemIndex = list.next++;
      case 'blockquote':
        flush();
        final cls = _attr(attrs, 'class');
        _quotes.add(cls.contains('warning') ? 'warning' : (cls.contains('note') ? 'note' : 'quote'));
      case 'pre':
        flush();
        _current = HelpBlockType.code;
        _pre = true;
      case 'table':
        flush();
        _table = <List<List<HelpSpan>>>[];
      case 'tr':
        _row = <List<HelpSpan>>[];
      case 'td':
      case 'th':
        _spans = <HelpSpan>[];
        if (name == 'th') {
          _inline.add('th');
          _style.bold = true;
        }
      case 'img':
        final src = _attr(attrs, 'src');
        if (src.isNotEmpty) {
          final keep = _current;
          flush();
          blocks.add(HelpBlock(HelpBlockType.image, src: src, alt: _attr(attrs, 'alt'), quote: _quote));
          _current = keep;
        }
      case 'hr':
        flush();
        blocks.add(HelpBlock(HelpBlockType.rule));
      case 'br':
        if (_spans.isNotEmpty) _spans.add(HelpSpan('\n', bold: _style.bold, italic: _style.italic, href: _style.href));
      case 'strong':
      case 'b':
        _inline.add(name);
        _style.bold = true;
      case 'em':
      case 'i':
        _inline.add(name);
        _style.italic = true;
      case 'code':
        _inline.add(name);
        _style.code = true;
      case 'mark':
        _inline.add(name);
        _style.mark = true;
      case 'a':
        _inline.add(name);
        final href = _attr(attrs, 'href');
        _style.href = href.isEmpty ? null : href;
    }
  }

  void _restyle() {
    _style
      ..bold = _inline.contains('strong') || _inline.contains('b') || _inline.contains('th')
      ..italic = _inline.contains('em') || _inline.contains('i')
      ..code = _inline.contains('code')
      ..mark = _inline.contains('mark');
    if (!_inline.contains('a')) _style.href = null;
  }

  void close(String name) {
    switch (name) {
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        flush();
        _current = HelpBlockType.paragraph;
        _id = null;
      case 'p':
        flush();
      case 'li':
        flush();
        _current = _lists.length > 1 ? HelpBlockType.item : HelpBlockType.paragraph;
      case 'ul':
      case 'ol':
        flush();
        if (_lists.isNotEmpty) _lists.removeLast();
        _current = _lists.isEmpty ? HelpBlockType.paragraph : HelpBlockType.item;
      case 'blockquote':
        flush();
        if (_quotes.isNotEmpty) _quotes.removeLast();
      case 'pre':
        flush();
        _pre = false;
        _current = HelpBlockType.paragraph;
      case 'td':
      case 'th':
        final cell = _takeSpans();
        _row?.add(cell);
        if (name == 'th') {
          _inline.remove('th');
          _restyle();
        }
      case 'tr':
        final row = _row;
        if (row != null && row.isNotEmpty) _table?.add(row);
        _row = null;
      case 'table':
        final table = _table;
        if (table != null && table.isNotEmpty) blocks.add(HelpBlock(HelpBlockType.table, rows: table, quote: _quote));
        _table = null;
        _row = null;
      case 'strong':
      case 'b':
      case 'em':
      case 'i':
      case 'code':
      case 'mark':
      case 'a':
        final at = _inline.lastIndexOf(name);
        if (at >= 0) _inline.removeAt(at);
        _restyle();
    }
  }
}

/// Maqola HTML → bloklar.
List<HelpBlock> parseHelpHtml(String html) {
  final parser = _Parser();
  var position = 0;
  for (final match in _tag.allMatches(html)) {
    if (match.start > position) parser.text(html.substring(position, match.start));
    position = match.end;
    final name = match.group(2);
    if (name == null) continue; // izoh
    final lower = name.toLowerCase();
    if (match.group(1) == '/') {
      parser.close(lower);
    } else {
      parser.open(lower, match.group(3) ?? '');
      if (match.group(4) == '/' && lower != 'img' && lower != 'br' && lower != 'hr') parser.close(lower);
    }
  }
  if (position < html.length) parser.text(html.substring(position));
  parser.flush();
  return parser.blocks;
}

/// Bitta qatorli HTML (qidiruv natijasidagi parcha: `<mark>` bilan) → matn bo'laklari.
List<HelpSpan> parseHelpInline(String html) {
  final blocks = parseHelpHtml('<p>$html</p>');
  return <HelpSpan>[for (final block in blocks) ...block.spans];
}
