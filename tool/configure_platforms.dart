// `flutter create` yaratgan Android va iOS fayllariga EduX sozlamalarini qo'shadi:
// kamera, galereya va mikrofon ruxsat matnlari, ilova nomi, havolalarni ochish, push (fon rejimi),
// iOS minimal versiyasi (Firebase va mobile_scanner uchun 15.0). Takror ishga tushirish xavfsiz.
//
//   dart run tool/configure_platforms.dart          # Android va iOS
//   dart run tool/configure_platforms.dart --ios    # faqat iOS (macOS CI, android/ papkasiz)
import 'dart:io';

/// firebase_core 5 / firebase_messaging 17 (Firebase iOS SDK 12) iOS 15 talab qiladi; mobile_scanner 7 — 13+.
const String iosMinimum = '15.0';

void main(List<String> args) {
  if (!args.contains('--ios')) _android();
  _ios();
  stdout.writeln('EduX: platforma sozlamalari tayyor.');
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
    // 3.4: bank SMS'larini serverga yuborish (kartaga o'tkazmani avtomatik tasdiqlash).
    'android.permission.RECEIVE_SMS',
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
  // Bank SMS qabul qiluvchisi (ilova yopiq bo'lsa ham SMS telefondagi navbatga yoziladi).
  if (!text.contains('.BankSmsReceiver')) {
    const receiver = '''
        <receiver android:name=".BankSmsReceiver" android:exported="true" android:permission="android.permission.BROADCAST_SMS">
            <intent-filter android:priority="999">
                <action android:name="android.provider.Telephony.SMS_RECEIVED" />
            </intent-filter>
        </receiver>
''';
    text = text.replaceFirst('</application>', '$receiver    </application>');
  }
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
        <intent>
            <action android:name="android.intent.action.SENDTO" />
            <data android:scheme="sms" />
        </intent>
        <intent>
            <action android:name="android.intent.action.VIEW" />
            <data android:scheme="sms" />
        </intent>
    </queries>
''';
    if (text.contains('<queries>')) {
      text = text.replaceFirst('<queries>', '${queries.trim().replaceFirst('</queries>', '').trimRight()}\n');
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
  final package = RegExp(r'^package\s+([\w.]+)', multiLine: true).firstMatch(original)?.group(1) ?? 'uz.edux.app';
  if (!original.contains('bankDrain')) {
    file.writeAsStringSync(_mainActivitySource.replaceAll('__PACKAGE__', package));
    stdout.writeln('  android: MainActivity.kt (SMS kanali, bank SMS)');
  }
  final receiver = File('${file.parent.path}/BankSmsReceiver.kt');
  receiver.writeAsStringSync(_bankReceiverSource.replaceAll('__PACKAGE__', package));
  stdout.writeln('  android: BankSmsReceiver.kt');
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
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.os.Handler
import android.os.Looper
import android.telephony.SmsManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicInteger

class MainActivity : FlutterActivity() {
    companion object {
        /** Bank SMS kelganda Dart tomonini uyg'otish uchun (ilova ochiq bo'lsa). */
        @JvmStatic var channel: MethodChannel? = null
    }

    private val smsPermissionCode = 4711
    private val receivePermissionCode = 4712
    private var pendingPermission: MethodChannel.Result? = null
    private var pendingReceive: MethodChannel.Result? = null
    private val requestIds = AtomicInteger(1)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val methods = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "edux/sms")
        channel = methods
        methods.setMethodCallHandler { call, result ->
            when (call.method) {
                "hasReceivePermission" -> result.success(hasReceivePermission())
                "requestReceivePermission" -> {
                    if (hasReceivePermission()) {
                        result.success(true)
                    } else {
                        pendingReceive?.success(false)
                        pendingReceive = result
                        requestPermissions(arrayOf(Manifest.permission.RECEIVE_SMS), receivePermissionCode)
                    }
                }
                "bankConfigure" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    val senders = call.argument<List<String>>("senders") ?: emptyList()
                    BankSmsReceiver.configure(this, enabled, senders)
                    result.success(null)
                }
                "bankDrain" -> result.success(BankSmsReceiver.drain(this))
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
                "openAppSettings" -> {
                    // Ruxsat butunlay rad etilgan bo'lsa — foydalanuvchi uni faqat shu sahifadan yoqadi.
                    try {
                        startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", packageName, null)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
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

    private fun hasReceivePermission(): Boolean =
        checkSelfPermission(Manifest.permission.RECEIVE_SMS) == PackageManager.PERMISSION_GRANTED

    override fun onDestroy() {
        channel = null
        super.onDestroy()
    }

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
        if (requestCode == receivePermissionCode) {
            pendingReceive?.success(grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED)
            pendingReceive = null
        }
    }
}
''';

/// Bank SMS qabul qiluvchisi: faqat sozlamadagi jo'natuvchilardan kelgan SMS telefondagi navbatga yoziladi
/// (shaxsiy SMS saqlanmaydi), ilova ochiq bo'lsa Dart tomoni darhol xabardor qilinadi.
const String _bankReceiverSource = r'''
package __PACKAGE__

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.provider.Telephony
import org.json.JSONArray
import org.json.JSONObject

class BankSmsReceiver : BroadcastReceiver() {
    companion object {
        private const val PREFS = "edux_bank_sms"
        private const val MAX_QUEUE = 300

        fun configure(context: Context, enabled: Boolean, senders: List<String>) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putBoolean("enabled", enabled)
                .putString("senders", JSONArray(senders).toString())
                .apply()
        }

        @Synchronized
        fun drain(context: Context): String {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val queue = prefs.getString("queue", "[]") ?: "[]"
            prefs.edit().putString("queue", "[]").apply()
            return queue
        }

        private fun norm(value: String): String = value.lowercase().replace(Regex("[^a-z0-9а-яё]"), "")

        fun matches(sender: String, senders: List<String>): Boolean {
            val value = norm(sender)
            if (value.isEmpty()) return false
            return senders.any { val key = norm(it); key.isNotEmpty() && (value == key || value.startsWith(key)) }
        }

        @Synchronized
        private fun append(context: Context, items: List<JSONObject>) {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val queue = try { JSONArray(prefs.getString("queue", "[]")) } catch (e: Exception) { JSONArray() }
            for (item in items) queue.put(item)
            while (queue.length() > MAX_QUEUE) queue.remove(0)
            prefs.edit().putString("queue", queue.toString()).apply()
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (!prefs.getBoolean("enabled", false)) return
        val senders = try {
            val array = JSONArray(prefs.getString("senders", "[]"))
            (0 until array.length()).map { array.getString(it) }
        } catch (e: Exception) { emptyList() }
        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent) ?: return
        // Ko'p qismli SMS: bir jo'natuvchidan kelgan qismlar birlashtiriladi.
        val grouped = LinkedHashMap<String, StringBuilder>()
        var time = System.currentTimeMillis()
        for (message in messages) {
            val sender = message?.displayOriginatingAddress ?: message?.originatingAddress ?: continue
            grouped.getOrPut(sender) { StringBuilder() }.append(message.displayMessageBody ?: message.messageBody ?: "")
            if (message.timestampMillis > 0) time = message.timestampMillis
        }
        val items = grouped.filter { matches(it.key, senders) }.map { (sender, body) ->
            JSONObject().put("sender", sender).put("body", body.toString()).put("time", time)
        }
        if (items.isEmpty()) return
        append(context, items)
        Handler(Looper.getMainLooper()).post { MainActivity.channel?.invokeMethod("bankSms", null) }
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
    // camera, mobile_scanner (QR kirish nazorati), kiosk (yuz), WebView ichidagi kamera
    'NSCameraUsageDescription':
        '<string>Javob varaqalarini skanerlash, QR kodni o\'qish va uy vazifasi suratini yuborish uchun kamera kerak.</string>',
    // image_picker
    'NSPhotoLibraryUsageDescription':
        '<string>Varaqa yoki uy vazifasi rasmini galereyadan tanlash uchun.</string>',
    // camera plagini audio API larini ham bog'laydi (ilova ovoz yozmaydi) — App Store bu matnni talab qiladi.
    'NSMicrophoneUsageDescription':
        '<string>EduX ovoz yozmaydi; ruxsat faqat kamera bilan ishlash uchun so\'raladi.</string>',
    'LSApplicationQueriesSchemes':
        '<array>\n\t\t<string>https</string>\n\t\t<string>tel</string>\n\t\t<string>sms</string>\n\t\t<string>tg</string>\n\t</array>',
    // Push (Firebase Cloud Messaging): fon rejimida xabar qabul qilish
    'UIBackgroundModes': '<array>\n\t\t<string>remote-notification</string>\n\t</array>',
    // Faqat standart HTTPS — eksport shifrlash hujjati talab qilinmaydi (TestFlight savoli)
    'ITSAppUsesNonExemptEncryption': '<false/>',
  };
  entries.forEach((key, value) {
    if (!text.contains('<key>$key</key>')) {
      text = text.replaceFirst(RegExp(r'</dict>\s*</plist>\s*$'), '\t<key>$key</key>\n\t$value\n</dict>\n</plist>\n');
    }
  });
  // Eski versiyada qo'shilgan ro'yxatga yangi sxemalar (sms, tg) ham qo'shilsin
  final schemes = RegExp(r'(<key>LSApplicationQueriesSchemes</key>\s*<array>)([\s\S]*?)(</array>)').firstMatch(text);
  if (schemes != null) {
    var inner = schemes.group(2)!;
    for (final scheme in <String>['https', 'tel', 'sms', 'tg']) {
      if (!inner.contains('<string>$scheme</string>')) inner = '$inner\t<string>$scheme</string>\n\t';
    }
    text = text.replaceRange(schemes.start, schemes.end, '${schemes.group(1)}$inner${schemes.group(3)}');
  }
  text = text.replaceFirstMapped(
    RegExp(r'(<key>CFBundleDisplayName</key>\s*<string>)[^<]*(</string>)'),
    (match) => '${match.group(1)}EduX${match.group(2)}',
  );
  plist.writeAsStringSync(text);
  stdout.writeln('  ios: Info.plist');

  final podfile = File('ios/Podfile');
  if (podfile.existsSync()) {
    var pods = podfile.readAsStringSync();
    pods = pods.replaceFirst(RegExp(r"^#?\s*platform :ios, '[0-9.]+'", multiLine: true), "platform :ios, '$iosMinimum'");
    if (!pods.contains('platform :ios')) pods = "platform :ios, '$iosMinimum'\n$pods";
    // Barcha pod'lar ham kamida shu versiyaga yig'ilsin (eski pod'lar Xcode 16 da xato bermasin)
    if (!pods.contains('EDUX_DEPLOYMENT_TARGET')) {
      pods = pods.replaceFirst(
        'flutter_additional_ios_build_settings(target)',
        'flutter_additional_ios_build_settings(target)\n'
            '    target.build_configurations.each do |config| # EDUX_DEPLOYMENT_TARGET\n'
            "      if config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'].to_f < $iosMinimum\n"
            "        config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '$iosMinimum'\n"
            '      end\n'
            '    end',
      );
    }
    podfile.writeAsStringSync(pods);
    stdout.writeln('  ios: Podfile (iOS $iosMinimum+)');
  } else {
    stdout.writeln('  ios: Podfile hali yo\'q — `flutter build ios --config-only` dan keyin qayta ishga tushiring');
  }

  // Xcode loyihasi va Flutter freymvorki ham shu minimal versiya bilan
  final project = File('ios/Runner.xcodeproj/project.pbxproj');
  if (project.existsSync()) {
    final text = project.readAsStringSync().replaceAll(
          RegExp(r'IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+;'),
          'IPHONEOS_DEPLOYMENT_TARGET = $iosMinimum;',
        );
    project.writeAsStringSync(text);
    stdout.writeln('  ios: project.pbxproj (IPHONEOS_DEPLOYMENT_TARGET $iosMinimum)');
  }
  final framework = File('ios/Flutter/AppFrameworkInfo.plist');
  if (framework.existsSync()) {
    final text = framework.readAsStringSync().replaceFirstMapped(
          RegExp(r'(<key>MinimumOSVersion</key>\s*<string>)[^<]*(</string>)'),
          (match) => '${match.group(1)}$iosMinimum${match.group(2)}',
        );
    framework.writeAsStringSync(text);
  }
}
