// `flutter create` yaratgan Android va iOS fayllariga EduX sozlamalarini qo'shadi:
// kamera va galereya ruxsatlari, ilova nomi, havolalarni ochish, iOS minimal versiyasi.
// Takror ishga tushirish xavfsiz (qo'shilgan narsa qayta qo'shilmaydi).
//
//   dart run tool/configure_platforms.dart
import 'dart:io';

void main() {
  _android();
  _ios();
  stdout.writeln('EduX: Android va iOS sozlamalari tayyor.');
}

void _android() {
  final manifest = File('android/app/src/main/AndroidManifest.xml');
  if (!manifest.existsSync()) {
    stderr.writeln('android/app/src/main/AndroidManifest.xml topilmadi — avval `flutter create` ni ishga tushiring.');
    exit(1);
  }
  var text = manifest.readAsStringSync();
  const permissions = <String>[
    'android.permission.INTERNET',
    'android.permission.CAMERA',
  ];
  for (final permission in permissions) {
    if (!text.contains('"$permission"')) {
      text = text.replaceFirst('<application', '<uses-permission android:name="$permission"/>\n    <application');
    }
  }
  if (!text.contains('android.hardware.camera')) {
    text = text.replaceFirst(
        '<application', '<uses-feature android:name="android.hardware.camera" android:required="false"/>\n    <application');
  }
  text = text.replaceFirst(RegExp(r'android:label="[^"]*"'), 'android:label="EduX"');
  if (!text.contains('<data android:scheme="https"')) {
    const queries = '''
    <queries>
        <intent>
            <action android:name="android.intent.action.VIEW" />
            <data android:scheme="https" />
        </intent>
        <intent>
            <action android:name="android.intent.action.DIAL" />
            <data android:scheme="tel" />
        </intent>
    </queries>
''';
    if (text.contains('<queries>')) {
      text = text.replaceFirst('<queries>', queries.trim().replaceFirst('</queries>', '').trimRight() + '\n');
    } else {
      text = text.replaceFirst('</manifest>', '$queries</manifest>');
    }
  }
  manifest.writeAsStringSync(text);
  stdout.writeln('  android: AndroidManifest.xml');
}

void _ios() {
  final plist = File('ios/Runner/Info.plist');
  if (!plist.existsSync()) {
    stdout.writeln('  ios: Info.plist topilmadi (iOS papkasi yo\'q) — o\'tkazib yuborildi');
    return;
  }
  var text = plist.readAsStringSync();
  final entries = <String, String>{
    'NSCameraUsageDescription':
        '<string>Javob varaqalarini skanerlash va uy vazifasi suratini yuborish uchun kamera kerak.</string>',
    'NSPhotoLibraryUsageDescription':
        '<string>Varaqa yoki uy vazifasi rasmini galereyadan tanlash uchun.</string>',
    'LSApplicationQueriesSchemes': '<array>\n\t\t<string>https</string>\n\t\t<string>tel</string>\n\t</array>',
  };
  entries.forEach((key, value) {
    if (!text.contains('<key>$key</key>')) {
      text = text.replaceFirst(RegExp(r'</dict>\s*</plist>\s*$'), '\t<key>$key</key>\n\t$value\n</dict>\n</plist>\n');
    }
  });
  text = text.replaceFirstMapped(
    RegExp(r'(<key>CFBundleDisplayName</key>\s*<string>)[^<]*(</string>)'),
    (match) => '${match.group(1)}EduX${match.group(2)}',
  );
  plist.writeAsStringSync(text);
  stdout.writeln('  ios: Info.plist');

  final podfile = File('ios/Podfile');
  if (podfile.existsSync()) {
    var pods = podfile.readAsStringSync();
    pods = pods.replaceFirst(RegExp(r"^#?\s*platform :ios, '[0-9.]+'", multiLine: true), "platform :ios, '13.0'");
    podfile.writeAsStringSync(pods);
    stdout.writeln('  ios: Podfile (iOS 13+)');
  }
}
