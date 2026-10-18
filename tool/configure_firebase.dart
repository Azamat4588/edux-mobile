// Firebase (push) uchun Android Gradle sozlamasi. android/app/google-services.json bo'lsa —
// google-services plaginini ulaydi; bo'lmasa hech narsa qilmaydi (ilova push'siz ishlaydi).
// Groovy (build.gradle) va Kotlin DSL (build.gradle.kts) ikkalasi ham. Takror ishga tushirish xavfsiz.
//
//   dart run tool/configure_firebase.dart
import 'dart:io';

const _version = '4.4.2';

void main() {
  if (!File('android/app/google-services.json').existsSync()) {
    stdout.writeln('Firebase: google-services.json yo\'q — push o\'chiq.');
    return;
  }
  _settings();
  _app();
  stdout.writeln('Firebase: google-services plagini ulandi.');
}

void _settings() {
  final kts = File('android/settings.gradle.kts');
  final groovy = File('android/settings.gradle');
  if (kts.existsSync()) {
    var text = kts.readAsStringSync();
    if (!text.contains('com.google.gms.google-services')) {
      text = text.replaceFirstMapped(RegExp(r'plugins\s*\{'),
          (m) => '${m[0]}\n    id("com.google.gms.google-services") version "$_version" apply false');
      kts.writeAsStringSync(text);
    }
  } else if (groovy.existsSync()) {
    var text = groovy.readAsStringSync();
    if (!text.contains('com.google.gms.google-services')) {
      text = text.replaceFirstMapped(RegExp(r'plugins\s*\{'),
          (m) => '${m[0]}\n    id "com.google.gms.google-services" version "$_version" apply false');
      groovy.writeAsStringSync(text);
    }
  }
}

void _app() {
  final kts = File('android/app/build.gradle.kts');
  final groovy = File('android/app/build.gradle');
  final file = kts.existsSync() ? kts : groovy;
  var text = file.readAsStringSync();
  if (text.contains('com.google.gms.google-services')) return;
  final line = kts.existsSync() ? '    id("com.google.gms.google-services")' : '    id "com.google.gms.google-services"';
  text = text.replaceFirstMapped(RegExp(r'plugins\s*\{'), (m) => '${m[0]}\n$line');
  file.writeAsStringSync(text);
}
