// `flutter create` yaratgan Android va iOS fayllariga EduX sozlamalarini qo'shadi:
// kamera, galereya va mikrofon ruxsat matnlari, ilova nomi, havolalarni ochish, push (fon rejimi),
// iOS minimal versiyasi (Firebase va mobile_scanner uchun 15.0). Takror ishga tushirish xavfsiz.
// 3.7 (iPhone va iPad): iPad — hamma yo'nalishlar, Split View / Slide Over (UIRequiresFullScreen = false), sichqoncha va
// trackpad, TARGETED_DEVICE_FAMILY = "1,2"; push uchun `aps-environment` (Release/Profile — imzolanganda), ilova tillari,
// ishga tushish ekrani (EduX rangi va belgisi — tool/ios/LaunchImage*.png).
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
    // 3.12: SMS shlyuz fon xizmati — ekran qulflansa ham, ilova yopilsa ham ishlaydi (doimiy bildirishnoma bilan).
    'android.permission.FOREGROUND_SERVICE',
    'android.permission.FOREGROUND_SERVICE_SPECIAL_USE',
    'android.permission.WAKE_LOCK',
    'android.permission.POST_NOTIFICATIONS',
    'android.permission.RECEIVE_BOOT_COMPLETED',
    'android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS',
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
  // 3.12: SMS shlyuz fon xizmati va telefon qayta yoqilganda uni tiklovchi qabul qiluvchi.
  if (!text.contains('.SmsGatewayService')) {
    const service = '''
        <service android:name=".SmsGatewayService" android:exported="false" android:foregroundServiceType="specialUse">
            <property android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"
                android:value="Sends the user's organization SMS (login codes, payment reminders) from this phone's SIM card while the user keeps the SMS gateway switched on." />
        </service>
        <receiver android:name=".GatewayBootReceiver" android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED" />
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED" />
            </intent-filter>
        </receiver>
''';
    text = text.replaceFirst('</application>', '$service    </application>');
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
  if (!original.contains('gatewayStatus')) {
    file.writeAsStringSync(_mainActivitySource.replaceAll('__PACKAGE__', package));
    stdout.writeln('  android: MainActivity.kt (SMS kanali, bank SMS)');
  }
  final receiver = File('${file.parent.path}/BankSmsReceiver.kt');
  receiver.writeAsStringSync(_bankReceiverSource.replaceAll('__PACKAGE__', package));
  stdout.writeln('  android: BankSmsReceiver.kt');
  File('${file.parent.path}/SmsGatewayService.kt').writeAsStringSync(_gatewayServiceSource.replaceAll('__PACKAGE__', package));
  stdout.writeln('  android: SmsGatewayService.kt (SMS shlyuz fon xizmati)');
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
                // 3.12: SMS shlyuz fon xizmati (SmsGatewayService.kt).
                "gatewayStart" -> {
                    val scope = call.argument<String>("scope") ?: "organization"
                    SmsGatewayService.configure(this, scope, call.argument<String>("config"))
                    SmsGatewayService.start(this)
                    result.success(true)
                }
                "gatewayStop" -> {
                    SmsGatewayService.configure(this, call.argument<String>("scope") ?: "organization", null)
                    SmsGatewayService.start(this)
                    result.success(true)
                }
                "gatewayStopAll" -> {
                    SmsGatewayService.clear(this)
                    stopService(Intent(this, SmsGatewayService::class.java))
                    result.success(true)
                }
                "gatewayPoke" -> {
                    SmsGatewayService.poke(this)
                    result.success(true)
                }
                "gatewayStatus" -> result.success(SmsGatewayService.status(this, call.argument<String>("scope") ?: "organization"))
                "batteryOptimized" -> {
                    val power = getSystemService(Context.POWER_SERVICE) as android.os.PowerManager
                    result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !power.isIgnoringBatteryOptimizations(packageName))
                }
                "requestBatteryExemption" -> {
                    try {
                        startActivity(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$packageName")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        result.success(true)
                    } catch (e: Exception) {
                        try {
                            startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                            result.success(true)
                        } catch (_: Exception) {
                            result.success(false)
                        }
                    }
                }
                "requestNotifications" -> {
                    if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission("android.permission.POST_NOTIFICATIONS") != PackageManager.PERMISSION_GRANTED) {
                        requestPermissions(arrayOf("android.permission.POST_NOTIFICATIONS"), 4713)
                    }
                    result.success(true)
                }
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
    // iPad: Split View va Slide Over (to'liq ekran majburiy emas), sichqoncha/trackpad hodisalari
    'UIRequiresFullScreen': '<false/>',
    'UIApplicationSupportsIndirectInputEvents': '<true/>',
    // App Store sahifasida ko'rinadigan tillar (ilova ichida uz/ru/en)
    'CFBundleLocalizations': '<array>\n\t\t<string>uz</string>\n\t\t<string>ru</string>\n\t\t<string>en</string>\n\t</array>',
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
  // Eski shablonda `UIRequiresFullScreen = true` bo'lsa — iPad Split View ishlamaydi.
  text = text.replaceAllMapped(RegExp(r'(<key>UIRequiresFullScreen</key>\s*)<true/>'), (match) => '${match.group(1)}<false/>');
  text = _orientations(text);
  plist.writeAsStringSync(text);
  stdout.writeln("  ios: Info.plist (iPad: hamma yo'nalishlar, Split View)");
  _entitlements();
  _launchScreen();

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
            // Imzolangan yig'ishda (App Store) pod resurs to'plamlari alohida imzo talab qilmasin.
            "      config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO' if target.respond_to?(:product_type) && target.product_type == 'com.apple.product-type.bundle'\n"
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
  _deviceFamily();
  final framework = File('ios/Flutter/AppFrameworkInfo.plist');
  if (framework.existsSync()) {
    final text = framework.readAsStringSync().replaceFirstMapped(
          RegExp(r'(<key>MinimumOSVersion</key>\s*<string>)[^<]*(</string>)'),
          (match) => '${match.group(1)}$iosMinimum${match.group(2)}',
        );
    framework.writeAsStringSync(text);
  }
}

/// iPhone: tik va ikki yotiq holat; iPad: to'rttala holat (Split View va Slide Over uchun App Store talabi).
String _orientations(String text) {
  const phone = <String>['UIInterfaceOrientationPortrait', 'UIInterfaceOrientationLandscapeLeft', 'UIInterfaceOrientationLandscapeRight'];
  const pad = <String>[
    'UIInterfaceOrientationPortrait',
    'UIInterfaceOrientationPortraitUpsideDown',
    'UIInterfaceOrientationLandscapeLeft',
    'UIInterfaceOrientationLandscapeRight',
  ];
  String array(List<String> items) => '<array>\n${items.map((item) => '\t\t<string>$item</string>\n').join()}\t</array>';
  var result = text;
  final keys = <String, List<String>>{'UISupportedInterfaceOrientations': phone, 'UISupportedInterfaceOrientations~ipad': pad};
  for (final entry in keys.entries) {
    final pattern = RegExp('<key>${RegExp.escape(entry.key)}</key>\\s*<array>[\\s\\S]*?</array>');
    final value = '<key>${entry.key}</key>\n\t${array(entry.value)}';
    if (pattern.hasMatch(result)) {
      result = result.replaceFirst(pattern, value);
    } else {
      result = result.replaceFirst(RegExp(r'</dict>\s*</plist>\s*$'), '\t$value\n</dict>\n</plist>\n');
    }
  }
  return result;
}

const String _entitlementsPlist = '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>aps-environment</key>
	<string>production</string>
</dict>
</plist>
''';

/// Push (APNs): `aps-environment` faqat imzolangan Release/Profile yig'ishda (App Store / TestFlight profili — production).
/// Imzosiz yig'ishda (`--no-codesign`) entitlements ishlatilmaydi — zarar bermaydi; Debug (dasturchi profili) o'zgarmaydi.
void _entitlements() {
  File('ios/Runner/Runner.entitlements').writeAsStringSync(_entitlementsPlist.trimLeft());
  final project = File('ios/Runner.xcodeproj/project.pbxproj');
  if (!project.existsSync()) return;
  final text = project.readAsStringSync();
  final updated = text.replaceAllMapped(
    RegExp(r'/\* (Release|Profile) \*/ = \{\s*isa = XCBuildConfiguration;[\s\S]*?name = (Release|Profile);\s*\};'),
    (match) {
      final block = match.group(0)!;
      if (!block.contains('INFOPLIST_FILE = Runner/Info.plist;') || block.contains('CODE_SIGN_ENTITLEMENTS')) return block;
      return block.replaceFirst(
          'INFOPLIST_FILE = Runner/Info.plist;', 'CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;\n\t\t\t\tINFOPLIST_FILE = Runner/Info.plist;');
    },
  );
  project.writeAsStringSync(updated);
  final count = 'CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;'.allMatches(updated).length;
  stdout.writeln('  ios: Runner.entitlements (aps-environment — $count ta konfiguratsiya)');
}

/// iPhone va iPad (1,2): Runner target'ining barcha konfiguratsiyalarida.
void _deviceFamily() {
  final project = File('ios/Runner.xcodeproj/project.pbxproj');
  if (!project.existsSync()) return;
  var text = project.readAsStringSync();
  text = text.replaceAll(RegExp(r'TARGETED_DEVICE_FAMILY = [^;]*;'), 'TARGETED_DEVICE_FAMILY = "1,2";');
  text = text.replaceAllMapped(
    RegExp(r'/\* (Debug|Release|Profile) \*/ = \{\s*isa = XCBuildConfiguration;[\s\S]*?name = (Debug|Release|Profile);\s*\};'),
    (match) {
      final block = match.group(0)!;
      if (!block.contains('INFOPLIST_FILE = Runner/Info.plist;') || block.contains('TARGETED_DEVICE_FAMILY')) return block;
      return block.replaceFirst('INFOPLIST_FILE = Runner/Info.plist;', 'INFOPLIST_FILE = Runner/Info.plist;\n\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";');
    },
  );
  project.writeAsStringSync(text);
  final count = 'TARGETED_DEVICE_FAMILY = "1,2";'.allMatches(text).length;
  stdout.writeln('  ios: project.pbxproj (TARGETED_DEVICE_FAMILY "1,2" — $count ta konfiguratsiya)');
}

/// Ishga tushish ekrani: EduX rangi (#1F63F5) va belgi (84 pt) — ilovadagi birinchi ekran bilan bir xil.
void _launchScreen() {
  final storyboard = File('ios/Runner/Base.lproj/LaunchScreen.storyboard');
  final imageset = Directory('ios/Runner/Assets.xcassets/LaunchImage.imageset');
  if (!storyboard.existsSync() || !imageset.existsSync()) return;
  for (final suffix in <String>['', '@2x', '@3x']) {
    final source = File('tool/ios/LaunchImage$suffix.png');
    if (source.existsSync()) source.copySync('${imageset.path}/LaunchImage$suffix.png');
  }
  var text = storyboard.readAsStringSync();
  text = text.replaceFirst(
    RegExp(r'<color key="backgroundColor"[^>]*/>'),
    '<color key="backgroundColor" red="0.12156862745098039" green="0.38823529411764707" blue="0.96078431372549022" '
        'alpha="1" colorSpace="custom" customColorSpace="sRGB"/>',
  );
  text = text.replaceFirst(RegExp(r'<image name="LaunchImage" width="[0-9.]+" height="[0-9.]+"/>'), '<image name="LaunchImage" width="84" height="84"/>');
  storyboard.writeAsStringSync(text);
  stdout.writeln('  ios: LaunchScreen (EduX rangi va belgisi)');
}

/// 3.12: SMS shlyuz fon xizmati. Oldin navbat Dart tomonida tekshirilardi — telefon qulflansa yoki Android ilovani
/// uxlatsa (Doze, batareya tejash) SMS'lar to'xtardi. Endi doimiy bildirishnomali xizmat (foreground service) o'zi
/// serverdan navbatni oladi, SIM kartadan yuboradi va natijani qaytaradi: ekran qulflanganda, ilova yopilganda va
/// telefon qayta yoqilganda ham ishlaydi. Dart faqat sozlamani beradi va holatni o'qiydi.
const String _gatewayServiceSource = r'''
package __PACKAGE__

import android.Manifest
import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.PowerManager
import android.telephony.SmsManager
import org.json.JSONArray
import org.json.JSONObject
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference

/** SmsManager orqali yuborish — natija kutiladi (fon ipida). null — yuborildi, aks holda xato matni. */
object SmsSender {
    private val ids = AtomicInteger(50000)
    private val thread: HandlerThread by lazy { HandlerThread("edux-sms-results").apply { start() } }

    @Suppress("DEPRECATION")
    private fun manager(context: Context): SmsManager =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) context.getSystemService(SmsManager::class.java) else SmsManager.getDefault()

    fun send(context: Context, phone: String, body: String, timeoutMs: Long = 60000): String? {
        val app = context.applicationContext
        if (app.checkSelfPermission(Manifest.permission.SEND_SMS) != PackageManager.PERMISSION_GRANTED) return "no_permission"
        if (phone.isBlank() || body.isBlank()) return "bad_args"
        val manager = manager(app)
        val parts = manager.divideMessage(body)
        val action = "uz.edux.GW_SENT_" + ids.getAndIncrement()
        val latch = CountDownLatch(parts.size)
        val failed = AtomicReference<String?>(null)
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (resultCode != Activity.RESULT_OK) failed.compareAndSet(null, "error code $resultCode")
                latch.countDown()
            }
        }
        val handler = Handler(thread.looper)
        val filter = IntentFilter(action)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            app.registerReceiver(receiver, filter, null, handler, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            app.registerReceiver(receiver, filter, null, handler)
        }
        try {
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            val intents = ArrayList<PendingIntent>()
            for (i in parts.indices) {
                intents.add(PendingIntent.getBroadcast(app, ids.getAndIncrement(), Intent(action).setPackage(app.packageName), flags))
            }
            if (parts.size > 1) manager.sendMultipartTextMessage(phone, null, parts, intents, null)
            else manager.sendTextMessage(phone, null, body, intents[0], null)
            // Operator javob bermasa — «yuborildi» deb hisoblanmaydi.
            if (!latch.await(timeoutMs, TimeUnit.MILLISECONDS)) return "timeout"
            return failed.get()
        } catch (e: Exception) {
            return e.message ?: "send error"
        } finally {
            try { app.unregisterReceiver(receiver) } catch (_: Exception) {}
        }
    }
}

class SmsGatewayService : Service() {
    companion object {
        private const val PREFS = "edux_sms_gateway"
        private const val CHANNEL = "edux_sms_gateway"
        private const val NOTIFICATION_ID = 4801
        private const val ACTION_POKE = "uz.edux.GATEWAY_POKE"
        private const val INTERVAL_MS = 20000L

        private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

        @Synchronized
        fun queues(context: Context): JSONObject = try { JSONObject(prefs(context).getString("queues", "{}") ?: "{}") } catch (_: Exception) { JSONObject() }

        /** config — Dart bergan JSON (server, token, prefix, organization, device_id ...); null — navbat o'chiriladi. */
        @Synchronized
        fun configure(context: Context, scope: String, config: String?) {
            val all = queues(context)
            if (config == null) all.remove(scope) else all.put(scope, JSONObject(config))
            prefs(context).edit().putString("queues", all.toString()).apply()
            if (config != null) {
                val status = JSONObject(status(context, scope))
                status.put("enabled", true)
                status.remove("stopped")
                prefs(context).edit().putString("status_$scope", status.toString()).apply()
            }
        }

        @Synchronized
        fun clear(context: Context) {
            prefs(context).edit().putString("queues", "{}").apply()
        }

        fun status(context: Context, scope: String): String = prefs(context).getString("status_$scope", "{}") ?: "{}"

        @Synchronized
        fun saveStatus(context: Context, scope: String, status: JSONObject) {
            prefs(context).edit().putString("status_$scope", status.toString()).apply()
        }

        fun start(context: Context) {
            val intent = Intent(context, SmsGatewayService::class.java)
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) context.startForegroundService(intent) else context.startService(intent)
            } catch (_: Exception) {
                // Fonda ishga tushirishga ruxsat bo'lmasa — ilova ochilganda qayta urinadi.
            }
        }

        fun poke(context: Context) {
            try {
                context.startService(Intent(context, SmsGatewayService::class.java).setAction(ACTION_POKE))
            } catch (_: Exception) {}
        }
    }

    @Volatile private var stopping = false
    private var worker: Thread? = null
    private val signal = Object()
    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null
    private var sentTotal = 0

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(NotificationChannel(CHANNEL, "SMS shlyuz", NotificationManager.IMPORTANCE_LOW))
        }
    }

    private fun texts(): JSONObject {
        val all = queues(this)
        val keys = all.keys()
        while (keys.hasNext()) {
            val texts = all.optJSONObject(keys.next())?.optJSONObject("texts")
            if (texts != null) return texts
        }
        return JSONObject()
    }

    private fun notification(): Notification {
        val texts = texts()
        val title = texts.optString("title", "EduX: SMS shlyuz ishlayapti")
        val body = texts.optString("body", "Yuborildi: {0}").replace("{0}", sentTotal.toString())
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(this, CHANNEL) else @Suppress("DEPRECATION") Notification.Builder(this)
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        if (launch != null) {
            builder.setContentIntent(PendingIntent.getActivity(this, 0, launch, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
        }
        return builder.setSmallIcon(applicationInfo.icon).setContentTitle(title).setContentText(body).setOngoing(true).build()
    }

    private fun goForeground() {
        val note = notification()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIFICATION_ID, note, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, note)
        }
    }

    private fun refreshNotification() {
        try {
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).notify(NOTIFICATION_ID, notification())
        } catch (_: Exception) {}
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        try {
            goForeground()
        } catch (_: Exception) {
            stopSelf()
            return START_NOT_STICKY
        }
        if (queues(this).length() == 0) {
            stopForegroundCompat()
            stopSelf()
            return START_NOT_STICKY
        }
        acquireLocks()
        if (worker?.isAlive != true) {
            stopping = false
            worker = Thread({ loop() }, "edux-sms-gateway").also { it.start() }
        }
        synchronized(signal) { signal.notifyAll() }
        return START_STICKY
    }

    @Suppress("DEPRECATION")
    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) stopForeground(Service.STOP_FOREGROUND_REMOVE) else stopForeground(true)
    }

    @Suppress("DEPRECATION")
    private fun acquireLocks() {
        if (wakeLock == null) {
            wakeLock = (getSystemService(Context.POWER_SERVICE) as PowerManager)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "edux:sms-gateway").apply { setReferenceCounted(false) }
        }
        // Ekran o'chganda ham protsessor ishlasin (soatlik qayta olinadi — tizim «cheksiz» qulfni yoqtirmaydi).
        wakeLock?.acquire(60 * 60 * 1000L)
        if (wifiLock == null) {
            try {
                val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                val mode = if (Build.VERSION.SDK_INT >= 29) WifiManager.WIFI_MODE_FULL_HIGH_PERF else WifiManager.WIFI_MODE_FULL
                wifiLock = wifi.createWifiLock(mode, "edux:sms-gateway").apply { setReferenceCounted(false) }
            } catch (_: Exception) {}
        }
        try { wifiLock?.acquire() } catch (_: Exception) {}
    }

    override fun onDestroy() {
        stopping = true
        synchronized(signal) { signal.notifyAll() }
        try { wakeLock?.release() } catch (_: Exception) {}
        try { wifiLock?.release() } catch (_: Exception) {}
        super.onDestroy()
    }

    /** Ilova ro'yxatdan surib yopilsa ham xizmat qayta ishga tushadi (START_STICKY + bu). */
    override fun onTaskRemoved(rootIntent: Intent?) {
        if (queues(this).length() > 0) start(this)
        super.onTaskRemoved(rootIntent)
    }

    private fun loop() {
        while (!stopping) {
            val all = queues(this)
            if (all.length() == 0) break
            var again = false
            val keys = all.keys()
            while (keys.hasNext() && !stopping) {
                val scope = keys.next()
                val config = all.optJSONObject(scope) ?: continue
                again = runQueue(scope, config) || again
            }
            acquireLocks()
            if (!again && !stopping) synchronized(signal) { try { signal.wait(INTERVAL_MS) } catch (_: InterruptedException) {} }
        }
        if (!stopping) {
            stopForegroundCompat()
            stopSelf()
        }
    }

    private class Response(val code: Int, val body: String)

    private fun http(method: String, config: JSONObject, path: String, body: JSONObject? = null): Response {
        val server = config.optString("server").trimEnd('/')
        val connection = URL("$server/api/v1/$path").openConnection() as HttpURLConnection
        try {
            connection.requestMethod = method
            connection.connectTimeout = 20000
            connection.readTimeout = 30000
            connection.setRequestProperty("Accept", "application/json")
            connection.setRequestProperty("X-Requested-With", "EduXMobile")
            connection.setRequestProperty("X-Locale", config.optString("locale", "uz"))
            connection.setRequestProperty("X-Platform", "android")
            connection.setRequestProperty("X-Device-Id", config.optString("device_id"))
            connection.setRequestProperty("X-App-Version", config.optString("app_version"))
            connection.setRequestProperty("Authorization", "Bearer " + config.optString("token"))
            val organization = config.optInt("organization", 0)
            if (organization > 0) connection.setRequestProperty("X-Organization", organization.toString())
            if (body != null) {
                connection.doOutput = true
                connection.setRequestProperty("Content-Type", "application/json")
                OutputStreamWriter(connection.outputStream, Charsets.UTF_8).use { it.write(body.toString()) }
            }
            val code = connection.responseCode
            val stream = if (code >= 400) connection.errorStream else connection.inputStream
            val text = stream?.bufferedReader(Charsets.UTF_8)?.use { it.readText() } ?: ""
            return Response(code, text)
        } finally {
            connection.disconnect()
        }
    }

    private fun message(response: Response): String = try { JSONObject(response.body).optString("message", "HTTP ${response.code}") } catch (_: Exception) { "HTTP ${response.code}" }

    /** Bitta navbat (tashkilot yoki platforma). true — darhol yana so'rash kerak (to'liq to'plam keldi). */
    private fun runQueue(scope: String, config: JSONObject): Boolean {
        val status = JSONObject(status(this, scope))
        val prefix = config.optString("prefix")
        val device = config.optString("device_id")
        try {
            val next = http("GET", config, "$prefix/next?limit=10&device_id=" + URLEncoder.encode(device, "UTF-8"))
            status.put("last_poll", System.currentTimeMillis())
            if (next.code == 401 || next.code == 404 || next.code == 403) {
                // Kirish tugagan yoki shlyuz vebda o'chirilgan — bu navbat to'xtaydi, ilova ochilganda sabab ko'rinadi.
                status.put("enabled", false)
                status.put("stopped", next.code)
                status.put("last_error", message(next))
                saveStatus(this, scope, status)
                configure(this, scope, null)
                return false
            }
            if (next.code >= 400) {
                status.put("last_error", message(next))
                saveStatus(this, scope, status)
                return false
            }
            val data = JSONObject(next.body)
            status.put("data", data.also { it.remove("messages") })
            val messages = JSONObject(next.body).optJSONArray("messages") ?: JSONArray()
            if (messages.length() == 0) {
                saveStatus(this, scope, status)
                return false
            }
            val pause = data.optLong("pause_ms", 5000).coerceIn(500, 120000)
            val results = JSONArray()
            for (i in 0 until messages.length()) {
                if (stopping) break
                val item = messages.getJSONObject(i)
                val error = SmsSender.send(this, item.optString("phone"), item.optString("body"))
                val row = JSONObject().put("id", item.optLong("id")).put("ok", error == null)
                if (error != null) row.put("error", error)
                results.put(row)
                if (error == null) {
                    status.put("sent", status.optInt("sent") + 1)
                    sentTotal++
                } else {
                    status.put("failed", status.optInt("failed") + 1)
                    status.put("last_error", error)
                }
                saveStatus(this, scope, status)
                refreshNotification()
                // Operator spam deb bloklamasligi uchun SMS'lar orasida tanaffus (server sozlamasi).
                if (i < messages.length() - 1) Thread.sleep(pause)
            }
            if (results.length() > 0) {
                val report = http("POST", config, "$prefix/report", JSONObject().put("device_id", device).put("results", results))
                if (report.code < 400) {
                    val answer = try { JSONObject(report.body) } catch (_: Exception) { JSONObject() }
                    if (answer.has("paused_until")) data.put("paused_until", answer.opt("paused_until"))
                    status.put("data", data)
                } else {
                    status.put("last_error", message(report))
                }
            }
            saveStatus(this, scope, status)
            val windowLimit = data.optInt("window_limit", 0)
            val leftWindow = data.optInt("left_window", 0)
            return messages.length() >= 10 && data.isNull("paused_until") && (windowLimit == 0 || leftWindow > 0)
        } catch (e: Exception) {
            // Internet yo'q yoki server javob bermadi — keyingi aylanishda qayta urinadi.
            status.put("last_error", e.message ?: e.javaClass.simpleName)
            saveStatus(this, scope, status)
            return false
        }
    }
}

/** Telefon qayta yoqilganda (yoki ilova yangilanganda) yoqilgan shlyuz o'z-o'zidan tiklanadi. */
class GatewayBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (SmsGatewayService.queues(context).length() > 0) SmsGatewayService.start(context)
    }
}
''';
