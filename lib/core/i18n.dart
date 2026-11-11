// Ko'p tillilik: veb-tizim bilan bir xil yondashuv — o'zbekcha matnning o'zi kalit.
// Lug'atlar: assets/i18n/ru.json, en.json (veb lug'atlari + ilovaga xos matnlar).
import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'script.dart';

class I18n {
  I18n._();

  // 3.30: oz — o'zbekcha kirill, yl — yangi lotin (server 2.74): lug'at yo'q, o'zbekcha matn Script bilan o'giriladi.
  static const List<String> codes = <String>['uz', 'oz', 'yl', 'ru', 'en'];
  static const Map<String, String> labels = <String, String>{
    'uz': "O'zbekcha",
    'oz': 'Ўзбекча',
    'yl': 'Ózbekça',
    'ru': 'Русский',
    'en': 'English',
  };

  /// Tugmadagi qisqa nom (UZ, ЎЗ, ÓZ, RU, EN).
  static const Map<String, String> short = <String, String>{'uz': 'UZ', 'oz': 'ЎЗ', 'yl': 'ÓZ', 'ru': 'RU', 'en': 'EN'};

  /// Tizim (Material) tili: kirill va yangi lotin — o'zbekcha.
  static String get materialLocale => Script.isScript(_locale) ? 'uz' : _locale;

  /// Kontent tili (sana, son formati): kirill va yangi lotin — o'zbekcha.
  static String get contentLocale => materialLocale;
  static final Map<String, String> _scripted = <String, String>{};

  static String _locale = 'uz';
  static Map<String, String> _dictionary = <String, String>{};

  static String get locale => _locale;

  static Future<void> load(String code) async {
    final next = codes.contains(code) ? code : 'uz';
    _scripted.clear();
    if (next == 'uz' || Script.isScript(next)) {
      _dictionary = <String, String>{};
    } else {
      final raw = await rootBundle.loadString('assets/i18n/$next.json');
      final data = jsonDecode(raw) as Map<String, dynamic>;
      _dictionary = data.map((key, value) => MapEntry(key, value.toString()));
    }
    _locale = next;
  }

  /// Qurilma tili: rus yoki ingliz bo'lsa — o'sha, aks holda o'zbekcha.
  static String fromDevice(String languageCode) {
    if (languageCode == 'ru' || languageCode == 'en') return languageCode;
    return 'uz';
  }

  static String translate(String key) {
    if (Script.isScript(_locale)) return _scripted[key] ??= Script.convert(key, _locale);
    return _dictionary[key] ?? key;
  }

  /// Serverdan kelgan yoki dinamik o'zbekcha matnni joriy yozuvga o'giradi.
  static String script(String text) => Script.isScript(_locale) ? Script.convert(text, _locale) : text;
}

/// Tarjima: `tr("O'quvchilar")`, `tr('{0} ta test', [5])`.
String tr(String key, [List<Object?> args = const <Object?>[]]) {
  var text = I18n.translate(key);
  for (var i = 0; i < args.length; i++) {
    text = text.replaceAll('{$i}', '${args[i] ?? ''}');
  }
  return text;
}
