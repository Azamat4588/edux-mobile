// Bank SMS'larini serverga yuborish (backend 1.35, docs/payments.md «Kartaga o'tkazma»): shlyuz telefoniga bank
// jo'natuvchilaridan (UZCARD, HUMO, bank nomlari — sozlamada ro'yxat) kelgan SMS server tomonidan o'qiladi va mos
// kartaga o'tkazma buyurtmasi avtomatik tasdiqlanadi.
//
// Android: RECEIVE_SMS ruxsati, manifestdagi BroadcastReceiver (tool/configure_platforms.dart) SMS'ni jo'natuvchi
// ro'yxatiga qarab ajratib, telefondagi navbatga yozadi (ilova yopiq bo'lsa ham). Ilova ochiq/fonda bo'lsa navbat
// darhol olinadi va POST crm/sms/gateway/incoming {messages: [{sender, body, received_at}]} (≤ 50) bilan yuboriladi;
// internet bo'lmasa — telefonda qoladi, keyin yuboriladi. Javobda enabled=false bo'lsa — yuborish to'xtatiladi.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'session.dart';

/// Standart bank jo'natuvchilari (SMS «kimdan» maydoni). Sozlamada o'zgartiriladi.
const List<String> defaultBankSenders = <String>[
  'UZCARD', 'HUMO', 'HUMOCARD', 'CardXabar', 'Kapitalbank', 'Hamkorbank', 'NBU', 'Agrobank', 'Ipotekabank', 'Asakabank',
  'Xalqbank', 'Infinbank', 'TBC', 'Anorbank', 'Davrbank', 'Orient', 'Aloqabank', 'Turonbank', 'Trastbank', 'SQB',
  'Universalbank', 'Uzumbank', 'Ipakyuli', 'Hayotbank', 'Poytaxtbank', 'Mikrokreditbank', 'Tengebank', 'KDB', 'Ziraat',
  'Octobank', 'Garantbank', 'AVO',
];

/// Bitta so'rovda ko'pi bilan (server: messages max:50).
const int bankBatch = 50;

String _norm(String value) => value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9а-яё]'), '');

/// Jo'natuvchi ro'yxatdagilardan birimi: katta-kichik harf, bo'shliq va belgilar hisobga olinmaydi; "UZCARD" ham
/// "Uzcard.uz" ham mos (jo'natuvchi nomi ro'yxatdagi nomdan boshlanadi yoki unga teng).
bool matchesBankSender(String sender, List<String> senders) {
  final value = _norm(sender);
  if (value.isEmpty) return false;
  for (final item in senders) {
    final key = _norm(item);
    if (key.isNotEmpty && (value == key || value.startsWith(key))) return true;
  }
  return false;
}

/// Ro'yxatni bo'laklarga bo'lish (≤ [size]).
List<List<T>> chunked<T>(List<T> items, [int size = bankBatch]) {
  return <List<T>>[for (var i = 0; i < items.length; i += size) items.sublist(i, i + size > items.length ? items.length : i + size)];
}

/// ISO 8601 mahalliy vaqt bilan: 2026-10-15T14:25:00+05:00.
String isoWithOffset(DateTime time) {
  final local = time.toLocal();
  final offset = local.timeZoneOffset;
  String two(int value) => value.abs().toString().padLeft(2, '0');
  final sign = offset.isNegative ? '-' : '+';
  final base = '${local.year.toString().padLeft(4, '0')}-${two(local.month)}-${two(local.day)}T${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  return '$base$sign${two(offset.inHours)}:${two(offset.inMinutes % 60)}';
}

/// Sozlamadagi matn → jo'natuvchilar ro'yxati (vergul yoki yangi qator bilan).
List<String> parseSenders(String text) =>
    text.split(RegExp(r'[,;\n]')).map((item) => item.trim()).where((item) => item.isNotEmpty).toSet().toList();

class BankSmsRecord {
  const BankSmsRecord({required this.sender, required this.body, required this.receivedAt, this.status = 'queued', this.sentAt});

  factory BankSmsRecord.fromJson(Map<String, dynamic> json) => BankSmsRecord(
        sender: asText(json['sender']),
        body: asText(json['body']),
        receivedAt: asText(json['received_at']),
        status: asText(json['status'], 'queued'),
        sentAt: json['sent_at']?.toString(),
      );

  final String sender;
  final String body;
  final String receivedAt;

  /// queued | matched | unmatched | duplicate | not_credit | disabled
  final String status;
  final String? sentAt;

  Map<String, Object?> toPayload() => <String, Object?>{'sender': sender, 'body': body, 'received_at': receivedAt};

  Map<String, Object?> toJson() => <String, Object?>{...toPayload(), 'status': status, 'sent_at': sentAt};

  BankSmsRecord withStatus(String value) => BankSmsRecord(sender: sender, body: body, receivedAt: receivedAt, status: value, sentAt: DateTime.now().toIso8601String());
}

class BankSmsForwarder extends ChangeNotifier {
  BankSmsForwarder._() {
    if (supported) {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'bankSms') unawaited(drain());
        return null;
      });
    }
  }

  static final BankSmsForwarder instance = BankSmsForwarder._();

  static const MethodChannel _channel = MethodChannel('edux/sms');

  Session? _session;
  bool enabled = false;
  List<String> senders = List<String>.from(defaultBankSenders);
  List<BankSmsRecord> pending = <BankSmsRecord>[];
  List<BankSmsRecord> recent = <BankSmsRecord>[];
  String? lastError;
  DateTime? lastSent;

  /// Server sozlamada SMS manbasini o'chirgan (javob enabled=false).
  bool serverDisabled = false;
  bool _busy = false;

  bool get supported => !kIsWeb && Platform.isAndroid;

  String get _scope => '${_session?.organizationId ?? 0}';

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    enabled = prefs.getBool('bank_sms.enabled.$_scope') ?? false;
    senders = prefs.getStringList('bank_sms.senders') ?? List<String>.from(defaultBankSenders);
    pending = _decode(prefs.getString('bank_sms.pending.$_scope'));
    recent = _decode(prefs.getString('bank_sms.recent.$_scope'));
  }

  List<BankSmsRecord> _decode(String? raw) {
    if (raw == null) return <BankSmsRecord>[];
    try {
      return asList(jsonDecode(raw)).map(BankSmsRecord.fromJson).toList();
    } catch (_) {
      return <BankSmsRecord>[];
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('bank_sms.enabled.$_scope', enabled);
    await prefs.setStringList('bank_sms.senders', senders);
    await prefs.setString('bank_sms.pending.$_scope', jsonEncode(pending.map((item) => item.toJson()).toList()));
    await prefs.setString('bank_sms.recent.$_scope', jsonEncode(recent.take(30).map((item) => item.toJson()).toList()));
  }

  /// Ilova ochilganda: avval yoqilgan bo'lsa — native qabul qiluvchini sozlaydi va navbatni yuboradi.
  Future<void> resume(Session session) async {
    _session = session;
    if (!supported) return;
    await _loadPrefs();
    final allowed = session.canUseSmsGateway && !session.readOnly;
    await _configure(enabled && allowed);
    notifyListeners();
    if (enabled && allowed) await drain();
  }

  Future<bool> hasPermission() async => supported && (await _channel.invokeMethod<bool>('hasReceivePermission') ?? false);

  Future<bool> requestPermission() async => supported && (await _channel.invokeMethod<bool>('requestReceivePermission') ?? false);

  Future<void> _configure(bool on) async {
    try {
      await _channel.invokeMethod<void>('bankConfigure', <String, Object?>{'enabled': on, 'senders': senders});
    } catch (_) {
      // eski native qism (3.3) — bank SMS qabul qilinmaydi
    }
  }

  /// Yoqish: telefon shlyuz sifatida ro'yxatdan o'tgan bo'lishi kerak (server shu foydalanuvchi telefonini kutadi).
  Future<void> enable(Session session, {required String deviceModel}) async {
    _session = session;
    await _loadPrefs();
    await session.api.post('crm/sms/gateway/register', <String, Object?>{'name': session.userName, 'device_model': deviceModel});
    enabled = true;
    serverDisabled = false;
    lastError = null;
    await _save();
    await _configure(true);
    notifyListeners();
    await drain();
  }

  Future<void> disable() async {
    enabled = false;
    await _save();
    await _configure(false);
    notifyListeners();
  }

  Future<void> setSenders(List<String> value) async {
    senders = value.isEmpty ? List<String>.from(defaultBankSenders) : value;
    await _save();
    await _configure(enabled);
    notifyListeners();
  }

  /// Native navbatdan yangi SMS'larni olib, serverga yuboradi (internet bo'lmasa — telefonda qoladi).
  Future<void> drain() async {
    final session = _session;
    if (!supported || session == null || !session.signedIn || _busy) return;
    _busy = true;
    try {
      try {
        final raw = await _channel.invokeMethod<String>('bankDrain');
        if (raw != null && raw.isNotEmpty) {
          for (final item in asList(jsonDecode(raw))) {
            final sender = asText(item['sender']);
            // Native qism ham tekshiradi; ro'yxat o'zgargan bo'lsa ham shaxsiy SMS serverga ketmasin.
            if (!matchesBankSender(sender, senders)) continue;
            final millis = asInt(item['time']);
            pending.add(BankSmsRecord(
              sender: sender,
              body: asText(item['body']),
              receivedAt: isoWithOffset(millis > 0 ? DateTime.fromMillisecondsSinceEpoch(millis) : DateTime.now()),
            ));
          }
          await _save();
          notifyListeners();
        }
      } catch (_) {
        // native qism yo'q
      }
      if (!enabled || pending.isEmpty) return;
      for (final batch in chunked(List<BankSmsRecord>.from(pending))) {
        final data = asMap(await session.api.post('crm/sms/gateway/incoming', <String, Object?>{
          'messages': batch.map((item) => item.toPayload()).toList(),
        }));
        final results = asList(data['results'], 'results');
        for (var i = 0; i < batch.length; i++) {
          final status = i < results.length ? asText(results[i]['status'], 'unmatched') : 'unmatched';
          recent.insert(0, batch[i].withStatus(status));
        }
        pending.removeRange(0, batch.length.clamp(0, pending.length));
        lastSent = DateTime.now();
        lastError = null;
        if (data['enabled'] == false) {
          // Sozlamada SMS manbasi o'chirilgan — telefon yuborishni to'xtatadi.
          serverDisabled = true;
          enabled = false;
          await _configure(false);
          break;
        }
      }
      if (recent.length > 30) recent = recent.take(30).toList();
      await _save();
    } on ApiException catch (error) {
      lastError = error.message;
    } catch (error) {
      lastError = error.toString();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
