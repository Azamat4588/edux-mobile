// 3.30 (server 2.74): o'zbek tilining ikki qo'shimcha yozuvi — kirill (oz, «Ўзбекча») va yangi lotin (yl, «Özbekça»).
// Matnlar alohida tarjima qilinmaydi: o'zbekcha (lotin) asl matn qoidalar bilan o'giriladi. Qoidalar veb
// (resources/js/i18n/script.js) va server (app/Support/I18n/Script.php) bilan aynan bir xil — test/script_test.dart.
// O'girilmaydi: brend va xalqaro qisqartmalar (SMS, Click, Telegram...), havola, e-pochta, {0} o'rinbosarlar, HTML teglar.

class Script {
  Script._();

  static const List<String> locales = <String>['oz', 'yl'];

  static bool isScript(String locale) => locales.contains(locale);

  static const String _apos = "'ʻʼ‘’`";
  static final RegExp _word = RegExp(r"[A-Za-z'ʻʼ‘’`]+");
  static final RegExp _protect = RegExp(
    r'''(https?://\S+|www\.\S+|[\w.+-]+@[\w-]+\.[\w.-]+|\b[\w-]+\.(?:uz|com|io|org|net|ru)\b\S*|\{[^{}]*\}|<[^>]*>|&[a-z#0-9]+;|`[^`]*`|(?:^|\s)/[\w\-./:?=&]+|~/[\w.\-/]*|\b[\w.-]+(?:/[\w.-]+)+\.(?:php|js|json|md|sh|env|conf|py|yml|yaml|service|log|ini|txt)\b|\b[\w-]+\.(?:php|js|json|md|sh|env|xlsx|csv|pdf|png|jpg|zip|apk|webp)\b|[A-Za-z0-9]*_[A-Za-z0-9_]+|(?<![A-Za-z'ʻʼ‘’`])(?=[A-Za-z0-9₀-₉₊₋]*[0-9₀-₉])[A-Z][a-z]?(?:[A-Z][a-z]?|[0-9₀-₉₊₋]|n(?=[A-Z0-9₀-₉₊₋]))*(?![A-Za-z'ʻʼ‘’`])|(?<=[–—])[A-Z][a-z]?(?:[A-Z][a-z]?)*(?![A-Za-z'ʻʼ‘’`])|\b(?:HCHO|COOH|CHO)\b)''',
  );

  /// O'zgarmaydigan so'zlar: brend, mahsulot va xalqaro qisqartmalar (katta-kichik harfi bilan aynan).
  static const Set<String> keepWords = <String>{
    'EduX', 'Call', 'call', 'Click', 'Payme', 'Uzum', 'Paynet', 'Oson', 'OSON', 'Alif', 'Pay', 'Atmos', 'ATMOS', 'Multicard', 'Telegram', 'Instagram',
    'Excel', 'Google', 'Android', 'iPhone', 'iPad', 'Windows', 'macOS', 'Linux', 'Hikvision', 'ZKTeco', 'OpenAI', 'Claude', 'Gemini', 'Face',
    'Bluetooth', 'WhatsApp', 'Facebook', 'YouTube', 'Zoom', 'Meet', 'Zadarma', 'OnlinePBX', 'UTEL', 'Modme', 'ModMe', 'AlfaCRM', 'Hollihop', 'Eskiz',
    'Infobip', 'PlayMobile', 'Chrome', 'Safari', 'Firefox', 'Yandex', 'Bing', 'Firebase', 'Apple', 'Microsoft', 'Outlook', 'iCloud', 'Sheets', 'Docs',
    'Drive', 'Calendar', 'Webmaster', 'Search', 'Console', 'Store', 'Play', 'App', 'Gmail', 'Mail', 'Webhook', 'webhook', 'Markdown', 'Ollama',
    'Groq', 'OpenRouter', 'DeepSeek', 'Mistral', 'Anthropic', 'Uzcard', 'Humo', 'Visa', 'Mastercard', 'Kapitalbank', 'Ipak', "Yo'li", 'Supervisor',
    'Nginx', 'PHP', 'MySQL', 'Redis', 'Python', 'Pillow', 'NumPy', 'Laravel', 'Vue', 'Ubuntu', 'Debian', 'healthchecks', 'UptimeRobot', 'BetterStack',
    'Cloudflare', 'Mock', 'Writing', 'Reading', 'Listening', 'Speaking', 'Task', 'Band', 'Academic', 'General', 'Beginner', 'Elementary',
    'Intermediate', 'Advanced', 'Upper', 'Pre', 'Milliy', 'Lojuvard', 'Atlas', 'Bahor', 'Grafit', 'Okean', 'Onest', 'Commissioner', 'Manrope',
    'Nunito', 'Golos', 'Inter', 'Roboto', 'Asterisk', 'FreePBX', 'Bitrix', 'amoCRM', 'Sipuni', 'Mango', 'Zvonobot', 'Kiosk', 'Wi', 'Fi', 'Wi-Fi',
    'LaTeX', 'MathJax', 'Meta', 'Pixel', 'Ads', 'TikTok', 'Uzbekistan', 'Aqlly', 'Igoo', 'Darslinker', 'UstozCRM', 'Zukkoma', 'Umai', 'Edulog',
    'Soff', 'Alfa', 'PlayMarket', 'GitHub', 'GitLab', 'PerformTransaction', 'CancelTransaction', 'GetStatement', 'GetInformation', 'Mini',
    'TestFlight', 'Xcode', 'Gradle', 'Flutter', 'Tauri', 'Rust', 'Node', 'npm', 'Vite', 'Tailwind', 'Lucide', 'OFL',
    'sudo', 'bash', 'apt', 'curl', 'wget', 'ffmpeg', 'artisan', 'systemctl', 'supervisorctl', 'git', 'composer', 'php', 'nginx', 'crontab', 'cron', 'unzip', 'docker', 'certbot',
  };

  /// Xalqaro qisqartmalar — lotincha qoladi. O'zbekcha qisqartmalar (BSB, DTM, STIR, MChJ...) o'giriladi.
  static const Set<String> keepUpper = <String>{
    'SMS', 'AI', 'QR', 'PDF', 'IELTS', 'SAT', 'CEFR', 'TOEFL', 'GMAT', 'GRE', 'CRM', 'LMS', 'KPI', 'LTV', 'UTM', 'USB', 'API', 'ID', 'IP', 'PBX',
    'SMTP', 'URL', 'OMR', 'XP', 'MCP', 'HTML', 'CSV', 'JSON', 'XML', 'PIN', 'OTP', 'SIP', 'VoIP', 'HTTP', 'HTTPS', 'SSL', 'TLS', 'DNS', 'VPS', 'CPU',
    'RAM', 'SSD', 'HDD', 'GB', 'MB', 'KB', 'TB', 'OK', 'IT', 'UI', 'UX', 'PWA', 'APK', 'IPA', 'iOS', 'SEO', 'FAQ', 'IBAN', 'SWIFT', 'MFO', 'NFC',
    'RFID', 'HID', 'PC', 'TV', 'LED', 'GPS', 'VIP', 'CEO', 'HR', 'PR', 'SaaS', 'ZIP', 'WEBP', 'PNG', 'JPG', 'JPEG', 'MP4', 'MP3', 'WAV', 'DOCX',
    'XLSX', 'PPTX', 'TXT', 'S3', 'WebDAV', 'FCM', 'ASCII', 'UTC', 'GMT', 'NB', 'PS', 'AM', 'PM', 'ISO', 'IIN', 'STEM', 'STEAM', 'GPT', 'LLM', 'TTS',
    'STT', 'ASR', 'ELO', 'MMR', 'BMI', 'IQ', 'EQ', 'DISC', 'MBTI', 'RIASEC', 'SMART', 'GROW', 'OKR', 'SWOT', 'KYC', 'P2P', 'PUSH', 'POP', 'SHA',
    'LIFO', 'FIFO', 'ENQUEUE', 'DEQUEUE',
  };

  static const Map<String, String> _cyr = <String, String>{
    'a': 'а', 'b': 'б', 'd': 'д', 'e': 'е', 'f': 'ф', 'g': 'г', 'h': 'ҳ', 'i': 'и', 'j': 'ж', 'k': 'к', 'l': 'л', 'm': 'м', 'n': 'н', 'o': 'о',
    'p': 'п', 'q': 'қ', 'r': 'р', 's': 'с', 't': 'т', 'u': 'у', 'v': 'в', 'x': 'х', 'y': 'й', 'z': 'з', 'c': 'с', 'w': 'в', 'ц': 'ц',
  };
  static const String _vowels = 'aeiouAEIOU';

  // -tsiya/-ksiya/-nsiya → ц (operatsiya → операция); istisnolar — o'z holicha.
  static final RegExp _tsiya = RegExp(r'(ts|(?<=[kn])s)(iya|ion|ioner|ial)', caseSensitive: false);
  static final RegExp _tsiyaKeep = RegExp(r'^(pensiya|ekspansiya|dispansiya|pensioner)', caseSensitive: false);
  static final RegExp _twoUpper = RegExp(r'[A-Z].*[A-Z]');
  static final RegExp _mixed = RegExp(r'^[a-z]+[A-Z]');
  static final RegExp _edgeApos = RegExp(r"^['ʻʼ‘’`]+|['ʻʼ‘’`]+$");
  static final RegExp _brand = RegExp(r"^(.+?)(['’])([a-z]+)$");
  // O'zbek lotinida «w» yo'q, «c» faqat «ch» da — bunday so'z chet tilidan (check, cache, switch, Scratch).
  static final RegExp _foreign = RegExp(r'[wW]|[cC](?![hH])');

  static bool _isApos(String? ch) => ch != null && ch.isNotEmpty && _apos.contains(ch);
  static bool _isUpper(String ch) => ch != ch.toLowerCase();
  static String _case(String cyr, String src, bool whole) =>
      whole ? cyr.toUpperCase() : (_isUpper(src) ? cyr[0].toUpperCase() + cyr.substring(1) : cyr);
  static bool _whole(String word) => word.length > 1 && word == word.toUpperCase() && _twoUpper.hasMatch(word);

  static String _at(String word, int i) => i >= 0 && i < word.length ? word[i] : '';

  static String _toCyrillic(String input) {
    var word = input;
    if (!_tsiyaKeep.hasMatch(word)) {
      word = word.replaceAllMapped(_tsiya, (m) {
        final s = m.group(1)!;
        return '${s == s.toUpperCase() ? 'Ц' : 'ц'}${m.group(2)}';
      });
    }
    final whole = _whole(word);
    final out = StringBuffer();
    for (var i = 0; i < word.length; i++) {
      final ch = word[i];
      final lo = ch.toLowerCase();
      final next = _at(word, i + 1);
      final nlo = next.toLowerCase();
      if (_isApos(ch)) {
        out.write(i > 0 && i < word.length - 1 ? (whole ? 'Ъ' : 'ъ') : ch);
        continue;
      }
      if ((lo == 'o' || lo == 'g') && _isApos(next)) {
        out.write(_case(lo == 'o' ? 'ў' : 'ғ', ch, whole));
        i++;
        continue;
      }
      if (lo == 's' && nlo == 'h') {
        out.write(_case('ш', ch, whole));
        i++;
        continue;
      }
      if (lo == 'c' && nlo == 'h') {
        out.write(_case('ч', ch, whole));
        i++;
        continue;
      }
      if (lo == 'y' && nlo.isNotEmpty && 'oaue'.contains(nlo) && !(nlo == 'o' && _isApos(_at(word, i + 2)))) {
        const map = <String, String>{'o': 'ё', 'a': 'я', 'u': 'ю', 'e': 'е'};
        out.write(_case(map[nlo]!, ch, whole));
        i++;
        continue;
      }
      if (lo == 'e') {
        final prev = _at(word, i - 1);
        out.write(_case(i == 0 || (prev.isNotEmpty && _vowels.contains(prev)) ? 'э' : 'е', ch, whole));
        continue;
      }
      final mapped = _cyr[lo];
      out.write(mapped != null ? _case(mapped, ch, whole) : ch);
    }
    return out.toString();
  }

  static String _toNewLatin(String word) {
    final whole = _whole(word);
    final out = StringBuffer();
    for (var i = 0; i < word.length; i++) {
      final ch = word[i];
      final lo = ch.toLowerCase();
      final nlo = _at(word, i + 1).toLowerCase();
      if ((lo == 'o' || lo == 'g') && _isApos(_at(word, i + 1))) {
        final mapped = lo == 'o' ? 'ö' : 'ğ';
        out.write(_isUpper(ch) ? mapped.toUpperCase() : mapped);
        i++;
        continue;
      }
      if ((lo == 's' || lo == 'c') && nlo == 'h') {
        final mapped = lo == 's' ? 'ş' : 'ç';
        out.write(_isUpper(ch) || whole ? mapped.toUpperCase() : mapped);
        i++;
        continue;
      }
      out.write(_isApos(ch) && i > 0 && i < word.length - 1 ? 'ʼ' : ch);
    }
    return out.toString();
  }

  static bool _keep(String word) {
    final bare = word.replaceAll(_edgeApos, '');
    if (keepWords.contains(bare) || keepUpper.contains(bare)) return true;
    // Bitta harf (javob varianti «C», koeffitsiyent «c») — o'giriladi.
    return _mixed.hasMatch(bare) || (bare.length > 1 && _foreign.hasMatch(bare));
  }

  static String _convertWord(String w, String Function(String) convert) {
    // Avval «brend + qo'shimcha» (GitHub'dagi: brend va apostrof qoladi, qo'shimcha o'giriladi), keyin o'zgarmas so'zlar.
    final match = _brand.firstMatch(w);
    if (match != null && _keep(match.group(1)!)) return match.group(1)! + match.group(2)! + convert(match.group(3)!);
    if (_keep(w)) return w;
    return convert(w);
  }

  static String _words(String text, String Function(String) convert) =>
      text.replaceAllMapped(_word, (m) => _convertWord(m.group(0)!, convert));

  /// Matnni yozuvga o'giradi (oz — kirill, yl — yangi lotin; boshqa tilda o'zgarmaydi).
  static String convert(String text, String locale) {
    if (text.isEmpty || !isScript(locale)) return text;
    final convertWord = locale == 'oz' ? _toCyrillic : _toNewLatin;
    final out = StringBuffer();
    var last = 0;
    for (final match in _protect.allMatches(text)) {
      out.write(_words(text.substring(last, match.start), convertWord));
      out.write(match.group(0));
      last = match.end;
    }
    out.write(_words(text.substring(last), convertWord));
    return out.toString();
  }
}
