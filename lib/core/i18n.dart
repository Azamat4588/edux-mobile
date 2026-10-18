// Ko'p tillilik: veb-tizim bilan bir xil yondashuv — o'zbekcha matnning o'zi kalit.
// Lug'atlar: assets/i18n/ru.json, en.json (veb lug'atlari + ilovaga xos matnlar).
import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

class I18n {
  I18n._();

  static const List<String> codes = <String>['uz', 'ru', 'en'];
  static const Map<String, String> labels = <String, String>{
    'uz': "O'zbekcha",
    'ru': 'Русский',
    'en': 'English',
  };

  static String _locale = 'uz';
  static Map<String, String> _dictionary = <String, String>{};

  static String get locale => _locale;

  static Future<void> load(String code) async {
    final next = codes.contains(code) ? code : 'uz';
    if (next == 'uz') {
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

  static String translate(String key) => _dictionary[key] ?? key;
}

/// Tarjima: `tr("O'quvchilar")`, `tr('{0} ta test', [5])`.
String tr(String key, [List<Object?> args = const <Object?>[]]) {
  var text = I18n.translate(key);
  for (var i = 0; i < args.length; i++) {
    text = text.replaceAll('{$i}', '${args[i] ?? ''}');
  }
  return text;
}
