// 3.36: markaz logotipli ilova (white-label) — `flutter create` va configure_platforms'dan keyin ishga tushiriladi:
//
//   dart run tool/configure_brand.dart --name "Registon o'quv markazi" --id registon --icon /tmp/brand/icon.png
//
// Android: ilova nomi (android:label), paket nomi uz.edux.b.<id> (EduX ilovasi bilan yonma-yon o'rnatiladi), ikonka va
// kirish ekranidagi belgi (assets/brand/*.png) — markaz logotipi. Moslashuvchan (adaptive) ikonka o'chiriladi: logotip
// oddiy ikonka sifatida ishlatiladi (CI uni 1024×1024 kvadratga rang fonida joylaydi). Faqat Android (iOS ikonkasi yaratilmaydi).
// Takror ishga tushirish xavfsiz.
import 'dart:io';

void main(List<String> args) {
  String? value(String name) {
    final index = args.indexOf(name);
    return index >= 0 && index + 1 < args.length ? args[index + 1] : null;
  }

  final name = (value('--name') ?? '').trim();
  final id = (value('--id') ?? '').trim();
  final icon = value('--icon');
  if (name.isEmpty || name.length > 40 || !RegExp(r'^[a-z][a-z0-9]{1,30}$').hasMatch(id)) {
    stderr.writeln("--name (1–40 belgi) va --id (lotin kichik harf va raqam, 2–31 belgi, harf bilan boshlanadi) kerak.");
    exit(1);
  }

  final manifest = File('android/app/src/main/AndroidManifest.xml');
  if (!manifest.existsSync()) {
    stderr.writeln('android/ topilmadi — avval `flutter create` va configure_platforms.');
    exit(1);
  }
  final label = name.replaceAll('&', '&amp;').replaceAll('"', '&quot;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll("'", "\\'");
  manifest.writeAsStringSync(manifest.readAsStringSync().replaceFirst(RegExp(r'android:label="[^"]*"'), 'android:label="$label"'));

  final gradle = <File>[File('android/app/build.gradle.kts'), File('android/app/build.gradle')].firstWhere((f) => f.existsSync(),
      orElse: () => File('android/app/build.gradle.kts'));
  if (gradle.existsSync()) {
    final updated = gradle
        .readAsStringSync()
        .replaceAll(RegExp(r'applicationId\s*=\s*"[^"]*"'), 'applicationId = "uz.edux.b.$id"')
        .replaceAll(RegExp(r'applicationId\s+"[^"]*"'), 'applicationId "uz.edux.b.$id"');
    gradle.writeAsStringSync(updated);
  }

  if (icon != null && File(icon).existsSync()) {
    for (final target in <String>['assets/brand/icon.png', 'assets/brand/mark.png']) {
      File(icon).copySync(target);
    }
    final pubspec = File('pubspec.yaml');
    pubspec.writeAsStringSync(pubspec
        .readAsStringSync()
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('adaptive_icon_'))
        .map((line) => line == '  ios: true' ? '  ios: false' : line)
        .join('\n'));
  }
  stdout.writeln('EduX: markaz ilovasi sozlandi — $name (uz.edux.b.$id).');
}
