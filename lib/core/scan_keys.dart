// Skaner qurilmasi (veb 1.35 resources/js/lib/scanner.js bilan bir xil mantiq): Bluetooth yoki USB-OTG QR/shtrix-kod
// skaneri telefonga klaviatura bo'lib ulanadi — kodni juda tez (har belgi 5–50 ms) «yozadi» va oxirida Enter bosadi.
// Tez ketma-ketlik + Enter (yoki Tab) = kod; odam yozuvi (80–200 ms) e'tiborsiz. Toza mantiq — test/scan_keys_test.dart.

class ScanConfig {
  const ScanConfig({this.maxGap = 50, this.breakGap = 150, this.enterGap = 200, this.minLength = 6, this.maxLength = 300});

  /// Belgilar orasidagi o'rtacha vaqt (ms) shundan oshmasin.
  final int maxGap;

  /// Bitta tanaffus shundan uzun bo'lsa — yangi ketma-ketlik.
  final int breakGap;

  /// Enter oxirgi belgidan keyin shu vaqtgacha kelishi kerak (ms).
  final int enterGap;

  /// Eng qisqa kod (6 xonali o'quvchi kodi); shtrix-kod — 14 raqam.
  final int minLength;
  final int maxLength;
}

/// Klaviatura hodisasi (Flutter KeyEvent dan): [key] — mantiqiy tugma nomi (`Enter`, `Tab`, `Shift` ...), [character] — belgi.
class ScanKey {
  const ScanKey({this.key = '', this.character, this.control = false, this.alt = false, this.meta = false});

  final String key;
  final String? character;
  final bool control;
  final bool alt;
  final bool meta;
}

const Set<String> scanModifiers = <String>{
  'Shift', 'Shift Left', 'Shift Right', 'Caps Lock', 'CapsLock', 'Num Lock', 'NumLock', 'Control', 'Control Left', 'Control Right',
  'Alt', 'Alt Left', 'Alt Right', 'AltGraph', 'Meta', 'Meta Left', 'Meta Right', 'Fn', 'Unidentified', 'Dead',
};
const Set<String> scanTerminators = <String>{'Enter', 'Numpad Enter', 'NumpadEnter', 'Tab'};

class ScanDetector {
  ScanDetector([this.config = const ScanConfig()]);

  final ScanConfig config;
  final List<String> _chars = <String>[];
  int _first = 0;
  int _last = 0;

  void reset() {
    _chars.clear();
    _first = 0;
    _last = 0;
  }

  /// Hozir tez ketma-ketlik yig'ilyaptimi.
  bool get pending => _chars.length >= 2 && (_last - _first) / (_chars.length - 1) <= config.maxGap;

  /// Har tugmada chaqiriladi ([time] — ms). Tez yozilgan va Enter bilan tugagan kod qaytariladi, aks holda null.
  String? feed(ScanKey event, int time) {
    if (scanModifiers.contains(event.key)) return null;
    if (event.control || event.alt || event.meta) {
      reset();
      return null;
    }
    if (scanTerminators.contains(event.key)) {
      final value = _chars.join();
      final average = _chars.length > 1 ? (_last - _first) / (_chars.length - 1) : double.infinity;
      final ok = _chars.length >= config.minLength && average <= config.maxGap && time - _last <= config.enterGap;
      reset();
      return ok ? value : null;
    }
    final char = event.character;
    if (char == null || char.isEmpty || char.runes.length != 1 || char.codeUnitAt(0) < 32) {
      reset();
      return null;
    }
    if (_chars.isNotEmpty && time - _last > config.breakGap) reset();
    if (_chars.isEmpty) _first = time;
    if (_chars.length >= config.maxLength) reset();
    _chars.add(char);
    _last = time;
    return null;
  }
}

const String _ru = 'йцукенгшщзхъфывапролджэячсмитьбю.ё';
const String _en = "qwertyuiop[]asdfghjkl;'zxcvbnm,./`";
const String _ruShift = 'ЙЦУКЕНГШЩЗХЪФЫВАПРОЛДЖЭЯЧСМИТЬБЮ,Ё';
const String _enShift = 'QWERTYUIOP{}ASDFGHJKL:"ZXCVBNM<>?~';

/// Kirill joylashuvida yozilgan matnni lotin tugmalariga qaytaradi: «УВГЧЖЫЖ» → «EDUX:S:».
String fromCyrillicLayout(String text) {
  final buffer = StringBuffer();
  for (final char in text.split('')) {
    var index = _ru.indexOf(char);
    if (index >= 0) {
      buffer.write(_en[index]);
      continue;
    }
    index = _ruShift.indexOf(char);
    buffer.write(index >= 0 ? _enShift[index] : char);
  }
  return buffer.toString();
}

/// Yuborishdan oldin: boshqaruv belgilari va bo'shliqlar olinadi, kirill bo'lsa — lotinga qaytariladi.
String normalizeScanPayload(String text) {
  final clean = text.replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), '').trim();
  return RegExp(r'[Ѐ-ӿ]').hasMatch(clean) ? fromCyrillicLayout(clean) : clean;
}

/// Qo'lda kiritiladigan kod: 6 xonali o'quvchi kodi yoki kartadagi 14 raqamli shtrix-kod.
bool isManualCode(String value) => RegExp(r'^(\d{6}|\d{14})$').hasMatch(value);
