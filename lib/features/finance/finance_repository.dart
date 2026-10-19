// Moliya (3.1, CRM moduli; direktor, administrator, kassir): barcha so'rovlar shu yerda.
//
//   GET  crm/payments?from&to&page   — to'lovlar va jami (summary: {amount, count})
//   GET  crm/cash?from&to            — kassalar: qoldiq, kirim, chiqim, ochiq smena
//   GET  crm/debtors?page            — qarzdorlar (total_debt, count, last_page)
//   POST crm/debtors/remind          — ota-onalarga eslatma (Telegram / SMS shablon)
//   GET  crm/reports/summary?from&to — davr hisobi: kunlar bo'yicha tushum, usullar, xarajat, foyda
//   GET  crm/reports/monthly         — oxirgi 12 oy: tushum, xarajat, foyda
import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/session.dart';

class FinanceRepository {
  FinanceRepository(this.session);

  final Session session;

  Api get _api => session.api;

  static String get today => isoDay(DateTime.now());

  Future<Map<String, dynamic>> payments({required String from, required String to, int page = 1}) async =>
      asMap(await _api.get('crm/payments', query: <String, Object?>{'from': from, 'to': to, 'page': page}));

  Future<Map<String, dynamic>> cash({required String from, required String to}) async =>
      asMap(await _api.get('crm/cash', query: <String, Object?>{'from': from, 'to': to}));

  Future<Map<String, dynamic>> debtors({int page = 1}) async =>
      asMap(await _api.get('crm/debtors', query: <String, Object?>{'page': page}));

  /// {queued, without_telegram, recently_reminded, sms}
  Future<Map<String, dynamic>> remind(List<int> studentIds) async =>
      asMap(await _api.post('crm/debtors/remind', <String, Object?>{'student_ids': studentIds}));

  Future<Map<String, dynamic>> summary({required String from, required String to}) async =>
      asMap(await _api.get('crm/reports/summary', query: <String, Object?>{'from': from, 'to': to}));

  /// [{period, label, income, expenses, profit, charged}]
  Future<List<Map<String, dynamic>>> monthly() async => asList(await _api.get('crm/reports/monthly'));
}
