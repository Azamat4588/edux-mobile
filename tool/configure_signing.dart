// Play Market imzosi: android/key.properties bo'lsa — release yig'ish shu kalit bilan imzolanadi.
// Bo'lmasa Flutter standarti qoladi (sinov kaliti). Kotlin DSL va Groovy. Takror ishga tushirish xavfsiz.
//
//   dart run tool/configure_signing.dart
import 'dart:io';

void main() {
  if (!File('android/key.properties').existsSync()) {
    stdout.writeln('Imzo: key.properties yo\'q — sinov kaliti.');
    return;
  }
  final kts = File('android/app/build.gradle.kts');
  if (kts.existsSync()) {
    var text = kts.readAsStringSync();
    if (text.contains('keystoreProperties')) return;
    text = '''
import java.io.FileInputStream
import java.util.Properties

val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) load(FileInputStream(file))
}

$text''';
    text = text.replaceFirstMapped(RegExp(r'android\s*\{'), (m) => '''${m[0]}
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
            storeFile = file(keystoreProperties["storeFile"] as String)
            storePassword = keystoreProperties["storePassword"] as String
        }
    }''');
    text = text.replaceAll('signingConfig = signingConfigs.getByName("debug")', 'signingConfig = signingConfigs.getByName("release")');
    kts.writeAsStringSync(text);
  } else {
    final groovy = File('android/app/build.gradle');
    var text = groovy.readAsStringSync();
    if (text.contains('keystoreProperties')) return;
    text = text.replaceFirst('android {', '''
def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}

android {
    signingConfigs {
        release {
            keyAlias keystoreProperties['keyAlias']
            keyPassword keystoreProperties['keyPassword']
            storeFile file(keystoreProperties['storeFile'])
            storePassword keystoreProperties['storePassword']
        }
    }''');
    text = text.replaceAll('signingConfig signingConfigs.debug', 'signingConfig signingConfigs.release');
    groovy.writeAsStringSync(text);
  }
  stdout.writeln('Imzo: release kaliti ulandi.');
}
