// Call markazi (3.1): operator uchun barcha server so'rovlari shu yerda — endpointlar o'zgarsa, faqat shu fayl almashadi.
//
// Hozirgi manbalar (server 1.25+, `feature:callcenter`, rollar: direktor, administrator, marketolog, kassir):
//   GET  crm/callcenter/live                 — jonli qo'ng'iroqlar, navbat soni, operatorlar, mening holatim
//   PUT  crm/callcenter/status               — operator holati (available | break | offline)
//   GET  crm/callcenter/caller?phone=        — qo'ng'iroq qiluvchi kartasi (lid, o'quvchi, vazifa, so'nggi qo'ng'iroqlar)
//   GET  crm/callcenter/queue                — javobsiz qo'ng'iroqlar navbati (7 kun)
//   GET  crm/callcenter/calls?from&to&page   — qo'ng'iroqlar jurnali
//   POST crm/callcenter/calls                — qo'lda qayd (PBX ulanmagan bo'lsa)
//   POST crm/callcenter/calls/{id}/outcome   — natija, izoh, qayta qo'ng'iroq vaqti (notanish raqam → lid)
//   POST crm/callcenter/calls/{id}/handled   — «hal qilindi»
//   GET  crm/callcenter/scripts              — suhbat skriptlari
import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/session.dart';

/// Suhbat natijalari (server: Call::OUTCOMES) — o'zbekcha kalit, tarjima tr() orqali.
const Map<String, String> callOutcomeLabels = <String, String>{
  'interested': 'Qiziqdi',
  'trial': 'Sinov darsiga yozildi',
  'enrolled': 'Kursga yozildi',
  'callback': "Qayta qo'ng'iroq",
  'info': "Ma'lumot berildi",
  'payment': "To'lov masalasi",
  'complaint': 'Shikoyat',
  'not_interested': 'Qiziqmadi',
  'other': 'Boshqa',
};

/// Qo'ng'iroq natijasi (server: Call::RESULTS).
const Map<String, String> callResultLabels = <String, String>{
  'answered': 'Gaplashildi',
  'no_answer': 'Javob bermadi',
  'busy': 'Band',
  'wrong_number': "Noto'g'ri raqam",
};

/// Operator holati (server: CallOperator::STATUSES).
const Map<String, String> operatorStatusLabels = <String, String>{
  'available': 'Qabul qilyapti',
  'break': 'Tanaffus',
  'offline': 'Ishda emas',
};

/// Jonli qo'ng'iroq bosqichi.
const Map<String, String> liveStatusLabels = <String, String>{
  'ringing': 'Jiringlamoqda',
  'talking': 'Gaplashilmoqda',
};

/// Natija lid yaratishga olib keladigan turlar (notanish raqam uchun ism so'raladi).
const List<String> leadOutcomes = <String>['interested', 'trial', 'callback', 'enrolled'];

/// Telefon raqami tel: havolasi uchun (faqat + va raqamlar).
String dialable(String phone) => phone.replaceAll(RegExp(r'[^+\d]'), '');

/// 75 -> "1:15"
String callDuration(Object? seconds) {
  if (seconds == null) return '—';
  final value = asInt(seconds);
  return '${value ~/ 60}:${two(value % 60)}';
}

class CallCenterRepository {
  CallCenterRepository(this.session);

  final Session session;

  static const String base = 'crm/callcenter';

  Api get _api => session.api;

  /// {me: {status, extension}, live: [...], queue: int, operators: [...]}
  Future<Map<String, dynamic>> live() async => asMap(await _api.get('$base/live'));

  Future<Map<String, dynamic>> setStatus(String status) async =>
      asMap(await _api.put('$base/status', <String, Object?>{'status': status}));

  /// {phone, leads: [...], students: [...], tasks: [...], calls: [...], scripts, outcomes}
  Future<Map<String, dynamic>> caller(String phone) async =>
      asMap(await _api.get('$base/caller', query: <String, Object?>{'phone': phone}));

  /// Javobsiz qo'ng'iroqlar: [{id, phone, created_at, caller, attempts}]
  Future<List<Map<String, dynamic>>> queue() async => asList(await _api.get('$base/queue'));

  /// Sahifalangan jurnal: {data, current_page, last_page, total, ...}. from/to — YYYY-MM-DD.
  Future<Map<String, dynamic>> calls({required String from, required String to, int page = 1, String? direction}) async =>
      asMap(await _api.get('$base/calls', query: <String, Object?>{'from': from, 'to': to, 'page': page, 'direction': direction}));

  Future<Map<String, dynamic>> logCall({required String phone, required String direction, required String result, int? duration}) async =>
      asMap(await _api.post('$base/calls', <String, Object?>{
        'phone': phone,
        'direction': direction,
        'result': result,
        'duration': duration,
      }));

  Future<Map<String, dynamic>> outcome(
    int callId, {
    required String outcome,
    String? note,
    DateTime? callbackAt,
    String? leadName,
    String? interest,
  }) async =>
      asMap(await _api.post('$base/calls/$callId/outcome', <String, Object?>{
        'outcome': outcome,
        'note': note,
        'callback_at': callbackAt?.toUtc().toIso8601String(),
        'lead_name': leadName,
        'interest': interest,
      }));

  Future<void> handled(int callId) async {
    await _api.post('$base/calls/$callId/handled');
  }

  /// [{id, title, body, position}]
  Future<List<Map<String, dynamic>>> scripts() async => asList(await _api.get('$base/scripts'));
}
