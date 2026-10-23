// Shubhali varaqani ko'rib chiqish: rasm, belgilarni tuzatish, o'quvchi kodi va variant — tasdiqlash yoki rad etish.
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'exam_kit.dart';
import 'scan_result_view.dart';

const String _letters = 'ABCDE';

class ScanReviewPage extends StatefulWidget {
  const ScanReviewPage({super.key, required this.scanId});

  final int scanId;

  @override
  State<ScanReviewPage> createState() => _ScanReviewPageState();
}

class _ScanReviewPageState extends State<ScanReviewPage> {
  bool _loading = true;
  String? _error;
  bool _saving = false;
  Map<String, dynamic> _scan = <String, dynamic>{};
  Uint8List? _image;
  List<Map<String, dynamic>> _exams = <Map<String, dynamic>>[];
  ExamKit? _kit;

  int? _examId;
  final TextEditingController _variant = TextEditingController();
  final TextEditingController _code = TextEditingController();
  List<Set<int>> _answers = <Set<int>>[];
  int _options = 4;
  Map<int, List<int>> _doubtful = <int, List<int>>{};
  final Set<int> _flagged = <int>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _variant.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = AppScope.read(context).api;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final scan = asMap(await api.get('scans/${widget.scanId}'));
      final result = asMap(scan['result']);
      final exams = asList(await api.get('exams'))
          .where((exam) => exam['status'] != 'draft')
          .toList();
      Uint8List? image;
      try {
        image = await api.bytes('scans/${widget.scanId}/image');
      } catch (_) {}
      final questions = asInt(result['questions'], 0);
      final rows = asRawList(result['answers'])
          .map((row) => asRawList(row).map((v) => asInt(v)).toSet())
          .toList();
      while (rows.length < questions) {
        rows.add(<int>{});
      }
      final flags = asRawList(result['flags']).whereType<Map>().map((f) => Map<String, dynamic>.from(f)).toList();
      _flagged
        ..clear()
        ..addAll(flags.where((f) => f['question'] is num).map((f) => (f['question'] as num).toInt() - 1));
      final examId = scan['exam_id'] ?? result['exam_id'];
      setState(() {
        _scan = scan;
        _image = image;
        _exams = exams;
        _examId = examId == null ? null : asInt(examId);
        _variant.text = asText(result['variant'], '1');
        _code.text = asText(result['student_code'] ?? result['suggested_student_code']);
        _answers = rows;
        _options = asInt(result['options'], 4);
        _doubtful = doubtfulFromFlags(flags);
        _loading = false;
      });
      if (_examId != null) _loadKit(_examId!);
    } on ApiException catch (error) {
      setState(() {
        _error = error.message;
        _loading = false;
      });
    }
  }

  Future<void> _loadKit(int examId) async {
    final kit = await KitStore.instance.get(AppScope.read(context).api, examId);
    if (mounted) setState(() => _kit = kit);
  }

  Future<void> _confirm() async {
    final code = _code.text.trim();
    final variant = int.tryParse(_variant.text.trim());
    if (_examId == null) {
      showMessage(context, tr('Testni tanlang'), error: true);
      return;
    }
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      showMessage(context, tr("O'quvchi kodi 6 ta raqamdan iborat."), error: true);
      return;
    }
    if (variant == null || variant < 1) {
      showMessage(context, tr('Variantni kiriting.'), error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await AppScope.read(context).api.post('scans/${widget.scanId}/confirm', <String, Object?>{
        'exam_id': _examId,
        'variant': variant,
        'student_code': code,
        'answers': _answers.map((row) => (row.toList()..sort())).toList(),
      });
      if (!mounted) return;
      showMessage(context, tr('Varaqa tasdiqlandi va natija yozildi.'));
      Navigator.pop(context, true);
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reject() async {
    if (!await confirm(context, tr('Varaqa rad etilsinmi? Natija yozilmaydi.'), action: tr('Rad etish'), danger: true)) return;
    if (!mounted) return;
    setState(() => _saving = true);
    try {
      await AppScope.read(context).api.post('scans/${widget.scanId}/reject');
      if (!mounted) return;
      showMessage(context, tr('Varaqa rad etildi.'));
      Navigator.pop(context, true);
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr("Varaqani ko'rib chiqish"))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : _body(),
      bottomNavigationBar: _loading || _error != null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(children: <Widget>[
                  OutlinedButton(
                    onPressed: _saving ? null : _reject,
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                    child: Text(tr('Rad etish')),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _saving ? null : _confirm,
                      child: _saving
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text(tr('Tasdiqlash')),
                    ),
                  ),
                ]),
              ),
            ),
    );
  }

  Widget _body() {
    final result = asMap(_scan['result']);
    final flags = asRawList(result['flags']).whereType<Map>().map((f) => Map<String, dynamic>.from(f)).toList();
    final variant = int.tryParse(_variant.text);
    final key = _kit?.keyFor(variant);
    final studentName = _kit?.studentName(_code.text.trim());
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        if (flags.isNotEmpty)
          AppCard(
            color: AppColors.soft(AppColors.warning),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: flags
                  .map((flag) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text('• ${flagText(flag)}'),
                      ))
                  .toList(),
            ),
          ),
        if (_scan['error'] != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(tr(asText(_scan['error'])), style: const TextStyle(color: AppColors.danger)),
        ],
        const SizedBox(height: 12),
        AppCard(
          child: Column(children: <Widget>[
            DropdownButtonFormField<int>(
              // initialValue faqat birinchi qiymat: test tashqaridan o'zgarsa (kalit) maydon qayta quriladi.
              key: ValueKey<int?>(_examId),
              initialValue: _exams.any((exam) => asInt(exam['id']) == _examId) ? _examId : null,
              isExpanded: true,
              decoration: InputDecoration(labelText: tr('Test')),
              items: _exams
                  .map((exam) => DropdownMenuItem<int>(
                        value: asInt(exam['id']),
                        child: Text(asText(exam['title']), overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: (value) {
                setState(() => _examId = value);
                if (value != null) _loadKit(value);
              },
            ),
            const SizedBox(height: 12),
            Row(children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _variant,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: tr('Variant')),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _code,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: InputDecoration(labelText: tr("O'quvchi kodi"), counterText: '', helperText: studentName),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ]),
          ]),
        ),
        if (_image != null) ...<Widget>[
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: InteractiveViewer(maxScale: 6, child: Image.memory(_image!)),
          ),
        ],
        SectionTitle(tr('Javoblar')),
        Text(tr("To'g'ri javobni belgilash uchun harfni bosing."), style: TextStyle(color: AppColors.muted, fontSize: 13)),
        const SizedBox(height: 8),
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
          child: Column(
            children: List<Widget>.generate(_answers.length, (question) {
              final flagged = _flagged.contains(question);
              final expected = key != null && question < key.length ? key[question] : null;
              return Container(
                color: flagged ? AppColors.soft(AppColors.warning) : null,
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: <Widget>[
                  SizedBox(
                    width: 34,
                    child: Text('${question + 1}',
                        textAlign: TextAlign.right,
                        style: TextStyle(fontWeight: FontWeight.w700, color: flagged ? AppColors.warning : AppColors.ink)),
                  ),
                  const SizedBox(width: 10),
                  for (var option = 0; option < _options; option++)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _Bubble(
                        letter: _letters[option],
                        selected: _answers[question].contains(option),
                        doubtful: _doubtful[question]?.contains(option) ?? false,
                        correct: expected?.contains(option),
                        onTap: () => setState(() {
                          final row = _answers[question];
                          if (!row.remove(option)) row.add(option);
                        }),
                      ),
                    ),
                ]),
              );
            }),
          ),
        ),
        const SizedBox(height: 80),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.letter, required this.selected, required this.doubtful, required this.onTap, this.correct});

  final String letter;
  final bool selected;
  final bool doubtful;
  final bool? correct;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Color border = AppColors.line;
    if (doubtful) border = AppColors.warning;
    if (correct == true) border = AppColors.success;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? AppColors.ink : AppColors.card,
          border: Border.all(color: border, width: doubtful || correct == true ? 2.4 : 1.4),
        ),
        child: Text(letter, style: TextStyle(fontWeight: FontWeight.w700, color: selected ? AppColors.card : AppColors.muted)),
      ),
    );
  }
}
