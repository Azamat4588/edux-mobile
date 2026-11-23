// `flutter create` yaratgan Android va iOS fayllariga EduX sozlamalarini qo'shadi:
// kamera, galereya va mikrofon ruxsat matnlari, ilova nomi, havolalarni ochish, push (fon rejimi),
// iOS minimal versiyasi (Firebase va mobile_scanner uchun 15.0). Takror ishga tushirish xavfsiz.
// 3.7 (iPhone va iPad): iPad — hamma yo'nalishlar, Split View / Slide Over (UIRequiresFullScreen = false), sichqoncha va
// trackpad, TARGETED_DEVICE_FAMILY = "1,2"; push uchun `aps-environment` (Release/Profile — imzolanganda), ilova tillari,
// ishga tushish ekrani (EduX rangi va belgisi — tool/ios/LaunchImage*.png).
//
//   dart run tool/configure_platforms.dart          # Android va iOS
//   dart run tool/configure_platforms.dart --ios    # faqat iOS (macOS CI, android/ papkasiz)
//   dart run tool/configure_platforms.dart --store  # 3.34: Google Play nusxasi — SMS ruxsatlari, SMS shlyuz xizmati va bank
//                                                   # SMS qabul qiluvchisi olib tashlanadi (Play SMS siyosati); oddiy
//                                                   # yig'ishdan keyin ishga tushirilsa ham ularni tozalaydi.
import 'dart:io';

/// firebase_core 5 / firebase_messaging 17 (Firebase iOS SDK 12) iOS 15 talab qiladi; mobile_scanner 7 — 13+.
const String iosMinimum = '15.0';

void main(List<String> args) {
  // 3.39: SMS shlyuz, bank SMS va «Telefon orqali» — alohida EduX Shlyuz ilovasida (gateway/). Asosiy ilova hamma
  // nusxada (sayt APK ham) SMS/qo'ng'iroq ruxsatlarisiz va fon xizmatlarisiz yig'iladi — do'kon nusxasi bilan bir xil.
  if (!args.contains('--ios')) _android(store: true);
  _ios();
  stdout.writeln('EduX: platforma sozlamalari tayyor.');
}

/// Google Play nusxasida bo'lmasligi kerak bo'lgan ruxsatlar (SMS siyosati; fon xizmati deklaratsiyasi; batareya istisnosi).
const List<String> storeRemoved = <String>[
  'android.permission.SEND_SMS',
  'android.permission.RECEIVE_SMS',
  'android.permission.READ_SMS',
  'android.permission.FOREGROUND_SERVICE_SPECIAL_USE',
  'android.permission.RECEIVE_BOOT_COMPLETED',
  'android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS',
  // 3.38: telefon orqali call markaz — Play faqat standart telefon ilovasiga qo'ng'iroqlar jurnalini beradi.
  'android.permission.READ_CALL_LOG',
  'android.permission.READ_PHONE_STATE',
  'android.permission.CALL_PHONE',
];

void _android({bool store = false}) {
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
    'android.permission.READ_CALL_LOG',
    'android.permission.READ_PHONE_STATE',
    'android.permission.CALL_PHONE',
  ];
  for (final permission in permissions) {
    if (store && storeRemoved.contains(permission)) continue;
    if (!text.contains('"$permission"')) {
      text = text.replaceFirst('<application', '<uses-permission android:name="$permission"/>\n    <application');
    }
  }
  if (!text.contains('android.hardware.camera')) {
    text = text.replaceFirst(
        '<application', '<uses-feature android:name="android.hardware.camera" android:required="false"/>\n    <application');
  }
  text = text.replaceFirst(RegExp(r'android:label="[^"]*"'), 'android:label="EduX"');
  if (store) text = _stripForStore(text);
  // Bank SMS qabul qiluvchisi (ilova yopiq bo'lsa ham SMS telefondagi navbatga yoziladi).
  if (!store && !text.contains('.BankSmsReceiver')) {
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
  if (!store && !text.contains('.SmsGatewayService')) {
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
  // 3.38: telefon orqali call markaz fon xizmati.
  if (!store && !text.contains('.CallGatewayService')) {
    const service = '''
        <service android:name=".CallGatewayService" android:exported="false" android:foregroundServiceType="specialUse">
            <property android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"
                android:value="Logs the organization's work calls made and received on this phone (number, duration, result) to the user's CRM and dials numbers the user starts from the EduX website, while the user keeps call center mode switched on." />
        </service>
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
  _noLintVital();
}

/// 3.34: plaginlar (kutubxona modullari) uchun ham «lintVital*» vazifalari o'chiriladi — Flutter 3.50 + AGP lint
/// camera_android_camerax da NoSuchMethodError (JavaDocParser) bilan yiqiladi.
void _noLintVital() {
  for (final name in <String>['android/build.gradle.kts', 'android/build.gradle']) {
    final file = File(name);
    if (!file.existsSync()) continue;
    var text = file.readAsStringSync();
    if (text.contains('lintVital')) continue;
    // Kotlin DSL va Groovy uchun bir xil sintaksis.
    text += '\n// EduX: reliz yig\'ishda lintVital o\'chiq (tool/configure_platforms.dart)\nsubprojects {\n    tasks.matching { it.name.startsWith("lintVital") }.configureEach { enabled = false }\n}\n';
    file.writeAsStringSync(text);
    stdout.writeln('  android: $name (lintVital o\'chiq)');
  }
}

/// 3.34: Google Play nusxasi — SMS ruxsatlari, SMS shlyuz fon xizmati va bank SMS qabul qiluvchisi olib tashlanadi.
/// Plaginlar manifestlari birlashganda ham qaytib kelmasligi uchun `tools:node="remove"` qo'yiladi.
String _stripForStore(String text) {
  for (final permission in storeRemoved) {
    text = text.replaceAll(RegExp('\\s*<uses-permission android:name="${RegExp.escape(permission)}"\\s*/>'), '');
  }
  text = text.replaceAll(RegExp(r'\s*<receiver android:name="\.BankSmsReceiver".*?</receiver>', dotAll: true), '');
  text = text.replaceAll(RegExp(r'\s*<service android:name="\.SmsGatewayService".*?</service>', dotAll: true), '');
  text = text.replaceAll(RegExp(r'\s*<service android:name="\.CallGatewayService".*?</service>', dotAll: true), '');
  text = text.replaceAll(RegExp(r'\s*<receiver android:name="\.GatewayBootReceiver".*?</receiver>', dotAll: true), '');
  if (!text.contains('xmlns:tools=')) {
    text = text.replaceFirst('<manifest ', '<manifest xmlns:tools="http://schemas.android.com/tools" ');
  }
  final removals = storeRemoved.where((p) => !text.contains('"$p" tools:node="remove"'))
      .map((p) => '<uses-permission android:name="$p" tools:node="remove"/>').join('\n    ');
  if (removals.isNotEmpty) text = text.replaceFirst('<application', '$removals\n    <application');
  stdout.writeln("  android: do'kon nusxasi — SMS ruxsatlari va xizmatlari olib tashlandi");
  return text;
}

/// mobile_scanner va WebView kamerasi uchun Android 6.0+ (API 23).
void _minSdk() {
  for (final name in <String>['android/app/build.gradle.kts', 'android/app/build.gradle']) {
    final file = File(name);
    if (!file.existsSync()) continue;
    var text = file.readAsStringSync();
    text = text.replaceFirst(RegExp(r'minSdk(Version)?\s*=?\s*flutter\.minSdkVersion'),
        name.endsWith('.kts') ? 'minSdk = maxOf(flutter.minSdkVersion, 23)' : 'minSdkVersion Math.max(flutter.minSdkVersion, 23)');
    // 3.34: reliz yig'ishda «lintVital» o'chiq — Flutter 3.50 dagi lint plaginlarda (camera_android_camerax) NoSuchMethodError
    // bilan yiqiladi; lint yig'ish sifatiga ta'sir qilmaydi (tahlil «flutter analyze» da).
    if (!text.contains('checkReleaseBuilds')) {
      text = text.replaceFirst(RegExp(r'^android\s*\{', multiLine: true),
          name.endsWith('.kts') ? 'android {\n    lint {\n        checkReleaseBuilds = false\n    }' : 'android {\n    lint {\n        checkReleaseBuilds false\n    }');
    }
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
  if (!original.contains('callsStatus')) {
    file.writeAsStringSync(_mainActivitySource.replaceAll('__PACKAGE__', package));
    stdout.writeln('  android: MainActivity.kt (SMS kanali, bank SMS)');
  }
  final receiver = File('${file.parent.path}/BankSmsReceiver.kt');
  receiver.writeAsStringSync(_bankReceiverSource.replaceAll('__PACKAGE__', package));
  stdout.writeln('  android: BankSmsReceiver.kt');
  File('${file.parent.path}/SmsGatewayService.kt').writeAsStringSync(_gatewayServiceSource.replaceAll('__PACKAGE__', package));
  stdout.writeln('  android: SmsGatewayService.kt (SMS shlyuz fon xizmati)');
  File('${file.parent.path}/CallGatewayService.kt').writeAsStringSync(_callServiceSource.replaceAll('__PACKAGE__', package));
  stdout.writeln('  android: CallGatewayService.kt (telefon orqali call markaz)');
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
    private val callPermissionCode = 4714
    private var pendingCalls: MethodChannel.Result? = null
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
                // 3.38: telefon orqali call markaz (CallGatewayService.kt).
                "callPermissions" -> result.success(CallGatewayService.permissions(this))
                "requestCallPermissions" -> {
                    val missing = arrayOf(Manifest.permission.READ_CALL_LOG, Manifest.permission.READ_PHONE_STATE, Manifest.permission.CALL_PHONE)
                        .filter { checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
                    if (missing.isEmpty()) {
                        result.success(true)
                    } else {
                        pendingCalls?.success(false)
                        pendingCalls = result
                        requestPermissions(missing.toTypedArray(), callPermissionCode)
                    }
                }
                "callsStart" -> {
                    CallGatewayService.configure(this, call.argument<String>("config"))
                    CallGatewayService.start(this)
                    result.success(true)
                }
                "callsStop" -> {
                    CallGatewayService.stop(this)
                    result.success(true)
                }
                "callsPoke" -> {
                    CallGatewayService.poke(this)
                    result.success(true)
                }
                "callsStatus" -> result.success(CallGatewayService.status(this))
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
        if (requestCode == callPermissionCode) {
            pendingCalls?.success(grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED })
            pendingCalls = null
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
        if (CallGatewayService.config(context) != null) CallGatewayService.start(context)
    }
}
''';

/// 3.38: telefon orqali call markaz — telefon holati, qo'ng'iroqlar jurnali, vebdan terish.
const String _callServiceSource = r'''
package __PACKAGE__

import android.Manifest
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
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.provider.CallLog
import android.telecom.TelecomManager
import android.telephony.TelephonyManager
import org.json.JSONArray
import org.json.JSONObject
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

/**
 * 3.38: «Telefon orqali» call markaz. Telefon holatini kuzatadi (jiringlash → ko'tarildi → tugadi), tugagach
 * qo'ng'iroqlar jurnalidan raqam, davomiylik va natijani olib serverga yuboradi (internet bo'lmasa navbatda saqlaydi);
 * vebdan «Qo'ng'iroq» bosilsa raqamni teradi (CALL_PHONE bo'lsa — TelecomManager.placeCall, aks holda bildirishnoma).
 */
class CallGatewayService : Service() {
    companion object {
        private const val PREFS = "edux_call_gateway"
        private const val CHANNEL = "edux_call_gateway"
        private const val DIAL_CHANNEL = "edux_call_dial"
        private const val NOTIFICATION_ID = 4802
        private const val DIAL_NOTIFICATION_ID = 4803
        private const val ACTION_POKE = "uz.edux.CALLS_POKE"
        private const val MAX_PENDING = 500

        private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

        fun config(context: Context): JSONObject? {
            val raw = prefs(context).getString("config", null) ?: return null
            return try { JSONObject(raw) } catch (_: Exception) { null }
        }

        @Synchronized
        fun configure(context: Context, config: String?) {
            val edit = prefs(context).edit()
            if (config == null) edit.remove("config") else edit.putString("config", config)
            edit.apply()
            if (config != null) {
                val status = JSONObject(status(context))
                status.remove("stopped")
                status.remove("last_error")
                saveStatus(context, status)
            }
        }

        fun status(context: Context): String = prefs(context).getString("status", "{}") ?: "{}"

        @Synchronized
        fun saveStatus(context: Context, status: JSONObject) {
            prefs(context).edit().putString("status", status.toString()).apply()
        }

        @Synchronized
        fun pending(context: Context): JSONArray = try { JSONArray(prefs(context).getString("pending", "[]") ?: "[]") } catch (_: Exception) { JSONArray() }

        @Synchronized
        fun savePending(context: Context, events: JSONArray) {
            prefs(context).edit().putString("pending", events.toString()).apply()
        }

        @Synchronized
        fun enqueue(context: Context, event: JSONObject) {
            val events = pending(context)
            events.put(event)
            // Uzoq internet yo'q bo'lsa — eng eskilari tashlanadi.
            while (events.length() > MAX_PENDING) events.remove(0)
            savePending(context, events)
        }

        fun granted(context: Context, permission: String): Boolean =
            context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

        fun permissions(context: Context): Map<String, Boolean> = mapOf(
            "call_log" to granted(context, Manifest.permission.READ_CALL_LOG),
            "phone_state" to granted(context, Manifest.permission.READ_PHONE_STATE),
            "call_phone" to granted(context, Manifest.permission.CALL_PHONE),
        )

        fun start(context: Context) {
            val intent = Intent(context, CallGatewayService::class.java)
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) context.startForegroundService(intent) else context.startService(intent)
            } catch (_: Exception) {
                // Fonda ishga tushirishga ruxsat bo'lmasa — ilova ochilganda qayta urinadi.
            }
        }

        fun poke(context: Context) {
            try {
                context.startService(Intent(context, CallGatewayService::class.java).setAction(ACTION_POKE))
            } catch (_: Exception) {}
        }

        fun stop(context: Context) {
            configure(context, null)
            try { context.stopService(Intent(context, CallGatewayService::class.java)) } catch (_: Exception) {}
        }
    }

    /** Joriy qo'ng'iroq (telefon holatidan). */
    private class Current(val id: String, val direction: String, var number: String?, val startedAt: Long) {
        var answeredAt: Long = 0
        var ringingSent = false
    }

    @Volatile private var stopping = false
    private var worker: Thread? = null
    private val signal = Object()
    private var wakeLock: PowerManager.WakeLock? = null
    private var current: Current? = null
    private var lastDialNumber: String? = null
    private var lastDialAt: Long = 0
    private var pollMs: Long = 30000
    private val main = Handler(Looper.getMainLooper())

    private val stateReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val state = intent?.getStringExtra(TelephonyManager.EXTRA_STATE) ?: return
            @Suppress("DEPRECATION")
            val number = intent?.getStringExtra(TelephonyManager.EXTRA_INCOMING_NUMBER)
            onState(state, number)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(NotificationChannel(CHANNEL, "Call markaz", NotificationManager.IMPORTANCE_LOW))
            manager.createNotificationChannel(NotificationChannel(DIAL_CHANNEL, "Qo'ng'iroq qilish", NotificationManager.IMPORTANCE_HIGH))
        }
        val filter = IntentFilter(TelephonyManager.ACTION_PHONE_STATE_CHANGED)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(stateReceiver, filter, Context.RECEIVER_EXPORTED)
            } else {
                @Suppress("UnspecifiedRegisterReceiverFlag")
                registerReceiver(stateReceiver, filter)
            }
        } catch (_: Exception) {}
    }

    private fun texts(): JSONObject = config(this)?.optJSONObject("texts") ?: JSONObject()

    private fun notification(): Notification {
        val texts = texts()
        val logged = JSONObject(status(this)).optInt("logged")
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(this, CHANNEL) else @Suppress("DEPRECATION") Notification.Builder(this)
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        if (launch != null) {
            builder.setContentIntent(PendingIntent.getActivity(this, 1, launch, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
        }
        return builder.setSmallIcon(applicationInfo.icon)
            .setContentTitle(texts.optString("title", "EduX: qo'ng'iroqlar yozilmoqda"))
            .setContentText(texts.optString("body", "Yozildi: {0}").replace("{0}", logged.toString()))
            .setOngoing(true).build()
    }

    private fun refreshNotification() {
        try {
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).notify(NOTIFICATION_ID, notification())
        } catch (_: Exception) {}
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        try {
            val note = notification()
            if (Build.VERSION.SDK_INT >= 34) startForeground(NOTIFICATION_ID, note, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
            else startForeground(NOTIFICATION_ID, note)
        } catch (_: Exception) {
            stopSelf()
            return START_NOT_STICKY
        }
        if (config(this) == null) {
            stopForegroundCompat()
            stopSelf()
            return START_NOT_STICKY
        }
        if (wakeLock == null) {
            wakeLock = (getSystemService(Context.POWER_SERVICE) as PowerManager)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "edux:call-gateway").apply { setReferenceCounted(false) }
        }
        if (worker?.isAlive != true) {
            stopping = false
            worker = Thread({ loop() }, "edux-call-gateway").also { it.start() }
        }
        synchronized(signal) { signal.notifyAll() }
        return START_STICKY
    }

    @Suppress("DEPRECATION")
    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) stopForeground(Service.STOP_FOREGROUND_REMOVE) else stopForeground(true)
    }

    override fun onDestroy() {
        stopping = true
        synchronized(signal) { signal.notifyAll() }
        try { unregisterReceiver(stateReceiver) } catch (_: Exception) {}
        try { wakeLock?.release() } catch (_: Exception) {}
        super.onDestroy()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        if (config(this) != null) start(this)
        super.onTaskRemoved(rootIntent)
    }

    // --- Telefon holati ---

    private fun clean(number: String?): String? {
        val value = number?.filter { it.isDigit() || it == '+' }
        return if (value.isNullOrEmpty()) null else value
    }

    private fun event(call: Current, phase: String): JSONObject {
        val row = JSONObject().put("id", call.id).put("phase", phase).put("direction", call.direction)
        if (call.number != null) row.put("phone", call.number)
        return row
    }

    @Synchronized
    private fun onState(state: String, rawNumber: String?) {
        val now = System.currentTimeMillis()
        val number = clean(rawNumber)
        when (state) {
            TelephonyManager.EXTRA_STATE_RINGING -> {
                val call = current ?: Current(now.toString(), "in", number, now).also { current = it }
                if (call.number == null && number != null) call.number = number
                if (!call.ringingSent && call.number != null) {
                    call.ringingSent = true
                    enqueue(this, event(call, "ringing"))
                    wake()
                }
            }
            TelephonyManager.EXTRA_STATE_OFFHOOK -> {
                var call = current
                if (call == null) {
                    // Jiringlashsiz ko'tarilish — chiquvchi qo'ng'iroq (raqam: vebdan terilgan bo'lsa ma'lum, aks holda jurnaldan).
                    val dialed = if (now - lastDialAt < 60000) lastDialNumber else null
                    call = Current(now.toString(), "out", dialed, now)
                    current = call
                }
                if (call.answeredAt == 0L) {
                    call.answeredAt = now
                    if (call.number != null) {
                        enqueue(this, event(call, if (call.direction == "in") "talking" else "ringing"))
                        wake()
                    }
                }
            }
            TelephonyManager.EXTRA_STATE_IDLE -> {
                val call = current ?: return
                current = null
                // Qo'ng'iroqlar jurnali yozilishiga ulgursin.
                main.postDelayed({ Thread { finish(call, now) }.start() }, 2500)
            }
        }
    }

    private fun finish(call: Current, endedAt: Long) {
        val row = event(call, "end")
        var number = call.number
        var direction = call.direction
        var duration = if (call.answeredAt > 0) ((endedAt - call.answeredAt) / 1000).toInt() else 0
        var result = if (call.answeredAt > 0) "answered" else "no_answer"
        val log = readCallLog(call.startedAt - 15000)
        if (log != null) {
            number = log.optString("number").ifEmpty { number }
            direction = log.optString("direction", direction)
            duration = log.optInt("duration", duration)
            result = log.optString("result", result)
        }
        if (number == null) return // raqamsiz (yashirin raqam) — yozilmaydi
        row.put("phone", number).put("direction", direction).put("duration", duration).put("result", result)
        enqueue(this, row)
        wake()
    }

    /** Qo'ng'iroqlar jurnalidagi shu qo'ng'iroq (since dan keyingi eng yangisi). */
    private fun readCallLog(since: Long): JSONObject? {
        if (!granted(this, Manifest.permission.READ_CALL_LOG)) return null
        return try {
            contentResolver.query(
                CallLog.Calls.CONTENT_URI,
                arrayOf(CallLog.Calls.NUMBER, CallLog.Calls.TYPE, CallLog.Calls.DURATION),
                "${CallLog.Calls.DATE} >= ?", arrayOf(since.toString()), "${CallLog.Calls.DATE} DESC",
            )?.use { cursor ->
                if (!cursor.moveToFirst()) return null
                val type = cursor.getInt(1)
                val duration = cursor.getInt(2)
                val (direction, result) = when (type) {
                    CallLog.Calls.OUTGOING_TYPE -> "out" to (if (duration > 0) "answered" else "no_answer")
                    CallLog.Calls.INCOMING_TYPE -> "in" to "answered"
                    CallLog.Calls.REJECTED_TYPE -> "in" to "rejected"
                    CallLog.Calls.BLOCKED_TYPE -> return null
                    else -> "in" to "no_answer" // MISSED, VOICEMAIL
                }
                JSONObject().put("number", clean(cursor.getString(0)) ?: "").put("direction", direction).put("duration", duration).put("result", result)
            }
        } catch (_: Exception) {
            null
        }
    }

    // --- Server bilan ---

    private fun wake() = synchronized(signal) { signal.notifyAll() }

    private fun loop() {
        while (!stopping) {
            val config = config(this) ?: break
            try { wakeLock?.acquire(60 * 1000L) } catch (_: Exception) {}
            try {
                flush(config)
                poll(config)
            } catch (e: Exception) {
                val status = JSONObject(status(this))
                status.put("last_error", e.message ?: e.javaClass.simpleName)
                saveStatus(this, status)
            } finally {
                try { wakeLock?.release() } catch (_: Exception) {}
            }
            if (!stopping) synchronized(signal) { try { signal.wait(pollMs) } catch (_: InterruptedException) {} }
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
            connection.connectTimeout = 15000
            connection.readTimeout = 20000
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
            return Response(code, stream?.bufferedReader(Charsets.UTF_8)?.use { it.readText() } ?: "")
        } finally {
            connection.disconnect()
        }
    }

    private fun message(response: Response): String = try { JSONObject(response.body).optString("message", "HTTP ${response.code}") } catch (_: Exception) { "HTTP ${response.code}" }

    /** Kirish tugagan yoki telefon vebda o'chirilgan — xizmat to'xtaydi, ilova ochilganda sabab ko'rinadi. */
    private fun halt(response: Response) {
        val status = JSONObject(status(this))
        status.put("stopped", response.code)
        status.put("last_error", message(response))
        saveStatus(this, status)
        configure(this, null)
        stopping = true
    }

    private fun flush(config: JSONObject) {
        val events = pending(this)
        if (events.length() == 0) return
        val batch = JSONArray()
        for (i in 0 until minOf(50, events.length())) batch.put(events.get(i))
        val response = http("POST", config, "crm/callcenter/phone/events", JSONObject().put("device_id", config.optString("device_id")).put("events", batch))
        val status = JSONObject(status(this))
        if (response.code == 401 || response.code == 403 || response.code == 404) return halt(response)
        if (response.code == 422) {
            // Noto'g'ri hodisa — qayta yuborilmaydi (navbat tiqilib qolmasin).
            status.put("last_error", message(response))
        } else if (response.code >= 400) {
            status.put("last_error", message(response))
            saveStatus(this, status)
            return
        } else {
            val answer = try { JSONObject(response.body) } catch (_: Exception) { JSONObject() }
            status.put("logged", status.optInt("logged") + answer.optInt("logged"))
            status.remove("last_error")
        }
        synchronized(CallGatewayService.Companion) {
            val left = JSONArray()
            val now = pending(this)
            for (i in batch.length() until now.length()) left.put(now.get(i))
            savePending(this, left)
            status.put("pending", left.length())
        }
        saveStatus(this, status)
        refreshNotification()
        if (status.optInt("pending") > 0) wake()
    }

    private fun poll(config: JSONObject) {
        val device = URLEncoder.encode(config.optString("device_id"), "UTF-8")
        val query = permissions(this).entries.joinToString("") { "&permissions%5B${it.key}%5D=${if (it.value) 1 else 0}" }
        val response = http("GET", config, "crm/callcenter/phone/next?device_id=$device$query")
        val status = JSONObject(status(this))
        status.put("last_poll", System.currentTimeMillis())
        if (response.code == 401 || response.code == 403 || response.code == 404) return halt(response)
        if (response.code >= 400) {
            status.put("last_error", message(response))
            saveStatus(this, status)
            return
        }
        val data = JSONObject(response.body)
        pollMs = data.optLong("poll_ms", 30000).coerceIn(3000, 120000)
        status.put("log", data.optString("log", "all"))
        status.put("pending", pending(this).length())
        val dial = data.optJSONObject("dial")
        if (dial != null) {
            val phone = dial.optString("phone")
            if (phone.isNotEmpty()) {
                dial(phone)
                status.put("dialed", status.optInt("dialed") + 1)
            }
        }
        saveStatus(this, status)
    }

    /** Raqamni terish: CALL_PHONE bo'lsa — darhol (TelecomManager), aks holda bildirishnoma — bosilsa terish oynasi. */
    private fun dial(phone: String) {
        lastDialNumber = clean(phone)
        lastDialAt = System.currentTimeMillis()
        val uri = Uri.fromParts("tel", phone, null)
        if (granted(this, Manifest.permission.CALL_PHONE) && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                (getSystemService(Context.TELECOM_SERVICE) as TelecomManager).placeCall(uri, Bundle())
                return
            } catch (_: Exception) {}
        }
        try {
            val texts = texts()
            val tap = PendingIntent.getActivity(this, 2, Intent(Intent.ACTION_DIAL, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(this, DIAL_CHANNEL) else @Suppress("DEPRECATION") Notification.Builder(this)
            val note = builder.setSmallIcon(applicationInfo.icon)
                .setContentTitle(texts.optString("dial_title", "EduX: qo'ng'iroq qiling"))
                .setContentText(texts.optString("dial_body", "{0} raqamini terish uchun bosing").replace("{0}", phone))
                .setContentIntent(tap).setAutoCancel(true).build()
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).notify(DIAL_NOTIFICATION_ID, note)
        } catch (_: Exception) {}
    }
}
''';
