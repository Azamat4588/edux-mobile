// 3.17: QR/shtrix-kod skaner qurilmasi (USB-OTG yoki Bluetooth HID — klaviatura bo'lib ulanadi): kodni tez «yozadi» va
// oxirida Enter (yoki Tab) bosadi. [HidScanBuffer] — toza mantiq (test/hid_scanner_test.dart), [HidScannerListener] — vidjet:
// faqat o'zi ekranda (joriy sahifada) va hech qaysi matn maydoni fokusda bo'lmaganda tinglaydi.
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Skaner belgilarini yig'adi: belgilar orasida [maxGapMs] dan uzun tanaffus — bufer tozalanadi; Enter/Tab kelganda
/// kamida [minLength] belgi bo'lsa — kod qaytariladi.
class HidScanBuffer {
  HidScanBuffer({this.maxGapMs = 300, this.minLength = 4, this.maxLength = 300});

  final int maxGapMs;
  final int minLength;
  final int maxLength;

  final StringBuffer _buffer = StringBuffer();
  int? _last;

  /// Hozir yig'ilgan belgilar.
  String get value => _buffer.toString();

  void reset() {
    _buffer.clear();
    _last = null;
  }

  /// Bosilgan belgi ([timeMs] — millisekund). Boshqaruv belgisi yoki bo'sh — bufer tozalanadi.
  void addCharacter(String? character, int timeMs) {
    if (character == null || character.isEmpty || character.runes.length != 1 || character.codeUnitAt(0) < 32 || character.codeUnitAt(0) == 127) {
      reset();
      return;
    }
    final last = _last;
    if (last != null && timeMs - last > maxGapMs) reset();
    if (_buffer.length >= maxLength) reset();
    _buffer.write(character);
    _last = timeMs;
  }

  /// Enter / Tab: yetarli uzun va vaqtida kelgan bo'lsa — kod, aks holda null. Bufer har holda tozalanadi.
  String? terminate(int timeMs) {
    final last = _last;
    final text = value;
    reset();
    if (last == null || timeMs - last > maxGapMs || text.length < minLength) return null;
    return text;
  }
}

/// Skanerdan kelgan matn: faqat chetdagi bo'shliqlar olinadi (server QR matni, Code128 raqamlari, 6 xonali kodni qabul qiladi).
String normalizeHidCode(String text) => text.trim();

final Set<LogicalKeyboardKey> _terminators = <LogicalKeyboardKey>{
  LogicalKeyboardKey.enter,
  LogicalKeyboardKey.numpadEnter,
  LogicalKeyboardKey.tab,
};

final Set<LogicalKeyboardKey> _modifiers = <LogicalKeyboardKey>{
  LogicalKeyboardKey.shift,
  LogicalKeyboardKey.shiftLeft,
  LogicalKeyboardKey.shiftRight,
  LogicalKeyboardKey.capsLock,
  LogicalKeyboardKey.numLock,
  LogicalKeyboardKey.control,
  LogicalKeyboardKey.controlLeft,
  LogicalKeyboardKey.controlRight,
  LogicalKeyboardKey.alt,
  LogicalKeyboardKey.altLeft,
  LogicalKeyboardKey.altRight,
  LogicalKeyboardKey.altGraph,
  LogicalKeyboardKey.meta,
  LogicalKeyboardKey.metaLeft,
  LogicalKeyboardKey.metaRight,
  LogicalKeyboardKey.fn,
};

/// Ekranda turganida tashqi skaner kodlarini [onCode] ga beradi. Matn maydoni fokusda bo'lsa yoki ustida boshqa
/// sahifa / oyna ochiq bo'lsa — aralashmaydi.
class HidScannerListener extends StatefulWidget {
  const HidScannerListener({super.key, required this.child, required this.onCode, this.enabled = true, this.minLength = 4, this.maxGapMs = 300});

  final Widget child;
  final ValueChanged<String> onCode;
  final bool enabled;
  final int minLength;
  final int maxGapMs;

  @override
  State<HidScannerListener> createState() => _HidScannerListenerState();
}

class _HidScannerListenerState extends State<HidScannerListener> {
  late HidScanBuffer _buffer = HidScanBuffer(maxGapMs: widget.maxGapMs, minLength: widget.minLength);
  final Stopwatch _clock = Stopwatch()..start();

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void didUpdateWidget(HidScannerListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.minLength != widget.minLength || oldWidget.maxGapMs != widget.maxGapMs) {
      _buffer = HidScanBuffer(maxGapMs: widget.maxGapMs, minLength: widget.minLength);
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  /// Fokusdagi vidjet matn maydonimi (TextField, dialogdagi kod maydoni ...).
  bool _textFocused() {
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused == null) return false;
    if (focused.widget is EditableText) return true;
    return focused.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  bool _onKey(KeyEvent event) {
    if (!mounted || !widget.enabled) return false;
    if (ModalRoute.of(context)?.isCurrent == false || _textFocused()) {
      _buffer.reset();
      return false;
    }
    if (event is! KeyDownEvent) return false;
    final key = event.logicalKey;
    if (_modifiers.contains(key)) return false;
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed || keyboard.isAltPressed || keyboard.isMetaPressed) {
      _buffer.reset();
      return false;
    }
    final now = _clock.elapsedMilliseconds;
    if (_terminators.contains(key)) {
      final code = _buffer.terminate(now);
      if (code == null) return false;
      final clean = normalizeHidCode(code);
      if (clean.isEmpty) return false;
      widget.onCode(clean);
      return true;
    }
    _buffer.addCharacter(event.character, now);
    return false;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
