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
    // SMS shlyuz (1.18): markaz SMS'larini shu telefon SIM kartasidan yuborish.
    'android.permission.SEND_SMS',
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
  _mainActivity();
  _minSdk();
}

/// mobile_scanner va WebView kamerasi uchun Android 6.0+ (API 23).
void _minSdk() {
  for (final name in <String>['android/app/build.gradle.kts', 'android/app/build.gradle']) {
    final file = File(name);
    if (!file.existsSync()) continue;
    var text = file.readAsStringSync();
    text = text.replaceFirst(RegExp(r'minSdk(Version)?\s*=?\s*flutter\.minSdkVersion'),
        name.endsWith('.kts') ? 'minSdk = maxOf(flutter.minSdkVersion, 23)' : 'minSdkVersion Math.max(flutter.minSdkVersion, 23)');
    file.writeAsStringSync(text);
    stdout.writeln('  android: $name (minSdk 23+)');
  }
}

/// MainActivity.kt ga "edux/sms" kanali: SMS ruxsati va SmsManager orqali yuborish (natija — "sent" broadcast).
void _mainActivity() {
  final dir = Directory('android/app/src/main/kotlin');
  if (!dir.existsSync()) return;
  final file = dir.listSync(recursive: true).whereType<File>().firstWhere(
        (item) => item.path.endsWith('MainActivity.kt'),
        orElse: () => File(''),
      );
  if (file.path.isEmpty) return;
  final original = file.readAsStringSync();
  if (original.contains('edux/sms')) return;
  final package = RegExp(r'^package\s+([\w.]+)', multiLine: true).firstMatch(original)?.group(1) ?? 'uz.edux.app';
  file.writeAsStringSync(_mainActivitySource.replaceAll('__PACKAGE__', package));
  stdout.writeln('  android: MainActivity.kt (SMS kanali)');
}

const String _mainActivitySource = r'''
package __PACKAGE__

import android.Manifest
import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.telephony.SmsManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicInteger

class MainActivity : FlutterActivity() {
    private val smsPermissionCode = 4711
    private var pendingPermission: MethodChannel.Result? = null
    private val requestIds = AtomicInteger(1)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "edux/sms").setMethodCallHandler { call, result ->
            when (call.method) {
                "hasPermission" -> result.success(hasSmsPermission())
                "requestPermission" -> {
                    if (hasSmsPermission()) {
                        result.success(true)
                    } else {
                        pendingPermission?.success(false)
                        pendingPermission = result
                        requestPermissions(arrayOf(Manifest.permission.SEND_SMS), smsPermissionCode)
                    }
                }
                "deviceModel" -> result.success("${Build.MANUFACTURER} ${Build.MODEL}".trim())
                "send" -> {
                    val phone = call.argument<String>("phone")
                    val body = call.argument<String>("body")
                    if (phone.isNullOrBlank() || body.isNullOrBlank()) {
                        result.error("bad_args", "phone/body empty", null)
                    } else if (!hasSmsPermission()) {
                        result.error("no_permission", "SEND_SMS permission denied", null)
                    } else {
                        send(phone, body, result)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun hasSmsPermission(): Boolean =
        checkSelfPermission(Manifest.permission.SEND_SMS) == PackageManager.PERMISSION_GRANTED

    @Suppress("DEPRECATION")
    private fun smsManager(): SmsManager =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) getSystemService(SmsManager::class.java) else SmsManager.getDefault()

    private fun send(phone: String, body: String, result: MethodChannel.Result) {
        val manager = smsManager()
        val parts = manager.divideMessage(body)
        val action = "uz.edux.SMS_SENT_" + requestIds.getAndIncrement()
        val remaining = AtomicInteger(parts.size)
        var failed: String? = null
        var finished = false
        val handler = Handler(Looper.getMainLooper())
        lateinit var receiver: BroadcastReceiver
        val finish = fun(error: String?) {
            if (finished) return
            finished = true
            try { unregisterReceiver(receiver) } catch (_: Exception) {}
            if (error == null) result.success(true) else result.error("send_failed", error, null)
        }
        receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (resultCode != Activity.RESULT_OK && failed == null) failed = "error code $resultCode"
                if (remaining.decrementAndGet() <= 0) finish(failed)
            }
        }
        val filter = IntentFilter(action)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(receiver, filter)
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        val intents = ArrayList<PendingIntent>()
        for (i in parts.indices) {
            intents.add(PendingIntent.getBroadcast(this, requestIds.getAndIncrement(), Intent(action).setPackage(packageName), flags))
        }
        try {
            if (parts.size > 1) {
                manager.sendMultipartTextMessage(phone, null, parts, intents, null)
            } else {
                manager.sendTextMessage(phone, null, body, intents[0], null)
            }
        } catch (e: Exception) {
            finish(e.message ?: "send error")
            return
        }
        // Operator javob bermasa — 60 soniyadan keyin "yuborildi" deb hisoblamaymiz.
        handler.postDelayed({ finish("timeout") }, 60000)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == smsPermissionCode) {
            pendingPermission?.success(grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED)
            pendingPermission = null
        }
    }
}
''';

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
