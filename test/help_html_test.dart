// Yordam maqolasi HTML → ilova bloklari (lib/core/help_html.dart). Fixture'lar — backend HelpCatalog::article()
// natijasi (help/articles/{slug} javobi): FAQ (uz), QR davomat (ru, jadval va ro'yxat), o'qituvchi (uz, «Maslahat» bloki).
import 'dart:convert';
import 'dart:io';

import 'package:edux/core/api.dart';
import 'package:edux/core/help_html.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> article(String name) => asMap(jsonDecode(File('test/fixtures/help_article_$name.json').readAsStringSync()));

void main() {
  test('belgilar (entity) ochiladi', () {
    expect(decodeEntities('O&#039;quvchi &amp; &laquo;x&raquo; &#x2014; &lt;b&gt;'), "O'quvchi & «x» — <b>");
    expect(decodeEntities('oddiy matn'), 'oddiy matn');
  });

  test('FAQ: sarlavhalar mundarija bilan bir xil, havola va rasm', () {
    final data = article('faq');
    final blocks = parseHelpHtml(asText(data['html']));
    final headings = blocks.where((block) => block.type == HelpBlockType.heading).toList();
    final toc = asList(data['toc'], 'toc');
    expect(headings.map((block) => block.id).toList(), toc.map((item) => asText(item['id'])).toList());
    expect(headings.map((block) => block.text).toList(), toc.map((item) => asText(item['text'])).toList());
    expect(headings.every((block) => block.level == 2), isTrue);

    final first = blocks.first;
    expect(first.type, HelpBlockType.paragraph);
    expect(first.text, startsWith("Bu yerda eng ko'p beriladigan savollar"));
    final link = first.spans.firstWhere((span) => span.href != null);
    expect(link.href, '/help/muammolar-va-yechimlar');
    expect(link.text, 'Muammolar va yechimlar');

    final image = blocks.firstWhere((block) => block.type == HelpBlockType.image);
    expect(image.src, '/media/help/img/kop-beriladigan-savollar-1.jpg');
    expect(image.alt, 'Kirish sahifasi');

    final question = blocks.firstWhere((block) => block.text.startsWith('Parolimni unutdim'));
    expect(question.spans.first.bold, isTrue);
    expect(question.spans.first.text, 'Parolimni unutdim. Nima qilaman?');
    expect(question.spans[1].bold, isFalse);
    // Bo'sh blok yo'q, matnda HTML qolmagan.
    for (final block in blocks.where((block) => block.type == HelpBlockType.paragraph || block.type == HelpBlockType.heading)) {
      expect(block.text.trim(), isNotEmpty);
      expect(block.text, isNot(contains('<')));
    }
  });

  test('QR davomat (ru): jadval va tartibli ro\'yxat', () {
    final blocks = parseHelpHtml(asText(article('checkin')['html']));
    final table = blocks.firstWhere((block) => block.type == HelpBlockType.table);
    expect(table.rows.length, 4);
    expect(table.rows.first.map((cell) => cell.map((span) => span.text).join()).toList(), <String>['Способ', 'Где', 'Кому удобно']);
    expect(table.rows.first.first.first.bold, isTrue);
    expect(table.rows[1].first.map((span) => span.text).join(), 'Сканер (USB или Bluetooth)');

    final items = blocks.where((block) => block.type == HelpBlockType.item).toList();
    expect(items.length, 15);
    final ordered = items.where((block) => block.ordered).toList();
    expect(ordered.first.text, 'Подключите сканер к компьютеру.');
    expect(ordered.take(5).map((block) => block.index).toList(), <int>[1, 2, 3, 4, 5]);
    expect(items.every((block) => block.level == 1), isTrue);
  });

  test("O'qituvchi: «Maslahat» bloki va ro'yxatlar", () {
    final blocks = parseHelpHtml(asText(article('teacher')['html']));
    final note = blocks.firstWhere((block) => block.quote != null);
    expect(note.quote, 'note');
    expect(note.spans.first.text, 'Maslahat:');
    expect(note.spans.first.bold, isTrue);
    expect(blocks.where((block) => block.type == HelpBlockType.item).length, 21);
    expect(blocks.where((block) => block.type == HelpBlockType.image).length, 3);
    expect(blocks.where((block) => block.type == HelpBlockType.heading).length, 7);
    // Blokdan keyingi paragraf iqtibos ichida emas.
    final after = blocks[blocks.indexOf(note) + 1];
    expect(after.quote, isNull);
  });

  test('qidiruv natijasi: <mark> ajratiladi', () {
    final spans = parseHelpInline('<mark>Davomat</mark> har dars uchun o&#039;quvchi');
    expect(spans.first.text, 'Davomat');
    expect(spans.first.mark, isTrue);
    expect(spans.map((span) => span.text).join(), "Davomat har dars uchun o'quvchi");
    final results = asList(asMap(jsonDecode(File('test/fixtures/help_search.json').readAsStringSync()))['results'], 'results');
    expect(results, isNotEmpty);
    expect(asText(results.first['slug']), 'davomat-belgilash');
    expect(parseHelpInline(asText(results.first['snippet'])).any((span) => span.mark), isTrue);
  });

  test('ichma-ich ro\'yxat, kod va hr', () {
    final blocks = parseHelpHtml('<ul><li>Bir<ul><li>Ichki</li></ul></li><li>Ikki</li></ul><pre><code>a  b\nc</code></pre><hr /><p>Oxiri</p>');
    expect(blocks.map((block) => block.type).toList(),
        <HelpBlockType>[HelpBlockType.item, HelpBlockType.item, HelpBlockType.item, HelpBlockType.code, HelpBlockType.rule, HelpBlockType.paragraph]);
    expect(blocks[0].level, 1);
    expect(blocks[1].level, 2);
    expect(blocks[1].text, 'Ichki');
    expect(blocks[2].text, 'Ikki');
    expect(blocks[3].text, 'a  b\nc');
  });
}
