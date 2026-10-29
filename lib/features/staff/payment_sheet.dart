// To'lov qabul qilish (kassa): summa, usul, guruh va izoh. Natija — girih muhri (veb: PaymentModal + SuccessStamp),
// summa va kvitansiya raqami.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/koshin.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'students_page.dart';

/// true — to'lov saqlandi (muhr ko'rinishi «Tayyor» bosilmay yopilsa ham).
Future<bool?> showPaymentSheet(
  BuildContext context, {
  required int studentId,
  required String studentName,
  List<Map<String, dynamic>> groups = const <Map<String, dynamic>>[],
}) async {
  var saved = false;
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _PaymentForm(studentId: studentId, studentName: studentName, groups: groups, onSaved: () => saved = true),
    ),
  );
  return result ?? (saved ? true : null);
}

class _PaymentForm extends StatefulWidget {
  const _PaymentForm({required this.studentId, required this.studentName, required this.groups, required this.onSaved});

  final VoidCallback onSaved;
  final int studentId;
  final String studentName;
  final List<Map<String, dynamic>> groups;

  @override
  State<_PaymentForm> createState() => _PaymentFormState();
}

class _PaymentFormState extends State<_PaymentForm> {
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _note = TextEditingController();
  String _method = 'cash';
  int? _groupId;
  bool _saving = false;
  String? _error;

  /// Saqlangan to'lov: summa va kvitansiya (muhr ko'rinishi).
  ({int amount, String receipt})? _done;

  @override
  void initState() {
    super.initState();
    if (widget.groups.length == 1) _groupId = asInt(widget.groups.first['id']);
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = int.tryParse(_amount.text.replaceAll(RegExp(r'\D'), ''));
    if (amount == null || amount < 1) {
      setState(() => _error = tr('Summani kiriting.'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final payment = asMap(await AppScope.read(context).api.post('crm/payments', <String, Object?>{
        'student_id': widget.studentId,
        'amount': amount,
        'method': _method,
        'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
        'group_id': _groupId,
      }));
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      final receipt = asText(asMap(payment['payment']).isNotEmpty ? asMap(payment['payment'])['receipt'] : payment['receipt']);
      widget.onSaved();
      setState(() => _done = (amount: amount, receipt: receipt));
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _success(({int amount, String receipt}) done) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        const Center(child: SuccessStamp(size: 84)),
        const SizedBox(height: 16),
        Semantics(
          liveRegion: true,
          child: Text(tr("To'lov qabul qilindi"), textAlign: TextAlign.center, style: AppTheme.title(size: 22)),
        ),
        const SizedBox(height: 6),
        Text(money(done.amount), textAlign: TextAlign.center, style: AppTheme.display(size: 30, color: AppColors.ink)),
        const SizedBox(height: 4),
        Text(
          <String>[widget.studentName, if (done.receipt.isNotEmpty) '${tr('Kvitansiya')}: ${done.receipt}'].join(', '),
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.muted),
        ),
        const SizedBox(height: 20),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('Tayyor'))),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final done = _done;
    if (done != null) return _success(done);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: <Widget>[
        Text(tr("To'lov qabul qilish"), style: AppTheme.title(size: 21)),
        const SizedBox(height: 2),
        Text(widget.studentName, style: TextStyle(color: AppColors.muted)),
        const SizedBox(height: 18),
        if (_error != null) ...<Widget>[
          Text(_error!, style: TextStyle(color: AppColors.danger)),
          const SizedBox(height: 10),
        ],
        TextField(
          controller: _amount,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly, _GroupedDigits()],
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          decoration: InputDecoration(labelText: tr('Summa (so\'m)'), suffixText: tr("so'm")),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: paymentMethods.entries
              .map((entry) => ChoiceChip(
                    label: Text(tr(entry.value)),
                    selected: _method == entry.key,
                    onSelected: (_) => setState(() => _method = entry.key),
                  ))
              .toList(),
        ),
        if (widget.groups.length > 1) ...<Widget>[
          const SizedBox(height: 14),
          DropdownButtonFormField<int?>(
            key: ValueKey<int?>(_groupId),
            initialValue: _groupId,
            decoration: InputDecoration(labelText: tr('Qaysi guruh uchun')),
            items: <DropdownMenuItem<int?>>[
              DropdownMenuItem<int?>(value: null, child: Text(tr('Tanlang'))),
              ...widget.groups.map((group) => DropdownMenuItem<int?>(value: asInt(group['id']), child: Text(asText(group['name'])))),
            ],
            onChanged: (value) => setState(() => _groupId = value),
          ),
        ],
        const SizedBox(height: 14),
        TextField(controller: _note, decoration: InputDecoration(labelText: tr('Izoh (ixtiyoriy)'))),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
              : Text(tr("To'lovni saqlash")),
        ),
      ]),
    );
  }
}

/// 1500000 -> "1 500 000" (yozish paytida)
class _GroupedDigits extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return const TextEditingValue();
    if (digits.length > 12) return oldValue;
    final text = groupDigits(int.parse(digits));
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}
