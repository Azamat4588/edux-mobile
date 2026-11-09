// 3.22 (server 2.53–2.58): oila (ota-ona va o'quvchi) uchun yangi sahifalar.
//   GET  crm/my/lesson-reports[?student_id] — darsdan keyingi hisobotlar (mavzu, uy vazifasi, ustoz izohi);
//   GET  crm/my/progress[?student_id]       — oylik hisobotlar;
//   POST crm/my/review                       — markaz haqida sharh (moderatsiyadan keyin saytda);
//   GET/POST crm/my/practice                 — uyda mashq kundaligi (yozadi — o'quvchi, ko'radi — ota-ona);
//   GET  crm/my/booking/slots, POST crm/my/booking, POST crm/my/booking/{id}/reply — yakka darslar;
//   GET  my/reenroll, POST my/reenroll/{id}  — keyingi o'quv yiliga qayta ro'yxat (ota-ona).
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/adaptive.dart';
import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../documents/documents_pages.dart';

Map<String, Object?> _who(int? studentId) => <String, Object?>{if (studentId != null && studentId > 0) 'student_id': studentId};

const Map<String, String> _statusLabels = <String, String>{'present': 'Keldi', 'late': 'Kechikdi', 'absent': 'Kelmadi', 'excused': 'Sababli'};

Color _statusColor(String status) => switch (status) {
      'present' => AppColors.success,
      'late' => AppColors.warning,
      'absent' => AppColors.danger,
      _ => AppColors.muted,
    };

// ---------------------------------------------------------------------------------------------------------------------
// Dars hisobotlari va oylik hisobot
// ---------------------------------------------------------------------------------------------------------------------

class LessonReportsPage extends StatefulWidget {
  const LessonReportsPage({super.key, this.studentId});

  final int? studentId;

  @override
  State<LessonReportsPage> createState() => _LessonReportsPageState();
}

class _LessonReportsPageState extends State<LessonReportsPage> {
  @override
  Widget build(BuildContext context) {
    final api = AppScope.of(context).api;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: pageBar(context,
            title: Text(tr('Dars hisobotlari')),
            bottom: TabBar(tabs: <Widget>[Tab(text: tr('Darslar')), Tab(text: tr('Oylik hisobot'))])),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => showReviewSheet(context, studentId: widget.studentId),
          icon: const Icon(Icons.rate_review_outlined),
          label: Text(tr('Sharh qoldirish')),
        ),
        body: TabBarView(children: <Widget>[
          AsyncView<List<Map<String, dynamic>>>(
            cacheKey: 'family_lessons_${widget.studentId ?? 0}',
            decode: (raw) => asList(raw),
            load: () async => asList(await api.get('crm/my/lesson-reports', query: _who(widget.studentId))),
            builder: (context, items, reload) {
              if (items.isEmpty) {
                return ListView(children: <Widget>[EmptyState(icon: Icons.menu_book_outlined, text: tr("Hali dars hisoboti yo'q. Ustoz darsdan keyin yuborgach shu yerda ko'rinadi."))]);
              }
              return ListView.separated(
                padding: readable(context, const EdgeInsets.fromLTRB(16, 16, 16, 96)),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) => _LessonCard(items[i]),
              );
            },
          ),
          AsyncView<List<Map<String, dynamic>>>(
            cacheKey: 'family_progress_${widget.studentId ?? 0}',
            decode: (raw) => asList(raw),
            load: () async => asList(await api.get('crm/my/progress', query: _who(widget.studentId))),
            builder: (context, items, reload) {
              if (items.isEmpty) {
                return ListView(children: <Widget>[EmptyState(icon: Icons.insights_outlined, text: tr("Oylik hisobot hali yo'q. Oy yakunida ustoz yuboradi."))]);
              }
              return ListView.separated(
                padding: readable(context, const EdgeInsets.fromLTRB(16, 16, 16, 96)),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) => _MonthlyCard(items[i]),
              );
            },
          ),
        ]),
      ),
    );
  }
}

class _LessonCard extends StatelessWidget {
  const _LessonCard(this.row);

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final status = asText(row['status']);
    final score = row['score'];
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Row(children: <Widget>[
          Expanded(child: Text('${date(row['date'])} · ${asText(row['group'])}', style: TextStyle(color: AppColors.muted, fontSize: 13))),
          if (status.isNotEmpty) Pill(tr(_statusLabels[status] ?? status), color: _statusColor(status)),
          if (score != null) ...<Widget>[const SizedBox(width: 6), Pill('${tr('Baho')}: $score', color: AppColors.info, dot: false)],
        ]),
        if (asText(row['topic']).isNotEmpty) ...<Widget>[
          const SizedBox(height: 6),
          Text(asText(row['topic']), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        ],
        if (asText(row['summary']).isNotEmpty) ...<Widget>[const SizedBox(height: 6), Text(asText(row['summary']))],
        if (asText(row['homework']).isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          _Labeled(icon: Icons.edit_note, label: tr('Uy vazifasi'), text: asText(row['homework'])),
        ],
        if (asText(row['note']).isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          _Labeled(icon: Icons.chat_bubble_outline, label: tr('Ustoz izohi'), text: asText(row['note']), color: AppColors.accent),
        ],
      ]),
    );
  }
}

class _MonthlyCard extends StatelessWidget {
  const _MonthlyCard(this.row);

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final stats = asMap(row['stats']);
    final period = asText(row['period']);
    final parts = period.split('-');
    final title = parts.length == 2 ? '${monthName(int.tryParse(parts[1]) ?? 1)} ${parts[0]}' : period;
    final lessons = asInt(stats['lessons']);
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        if (asText(row['group']).isNotEmpty) Text(asText(row['group']), style: TextStyle(color: AppColors.muted, fontSize: 13)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
          if (lessons > 0) Pill(tr('Davomat: {0}% ({1}/{2})', <Object>[asInt(stats['attendance_percent']), asInt(stats['present']), lessons]), color: AppColors.success, dot: false),
          if (stats['avg_score'] != null) Pill(tr("O'rtacha baho: {0}/{1}", <Object>[stats['avg_score'], stats['score_max'] ?? '']), color: AppColors.info, dot: false),
          if (asInt(stats['practice_days']) > 0)
            Pill(tr('Uyda mashq: {0} kun, {1} daqiqa', <Object>[asInt(stats['practice_days']), asInt(stats['practice_minutes'])]), color: AppColors.accent, dot: false),
          for (final exam in asList(stats['exams'], 'exams')) Pill('${asText(exam['title'])}: ${asText(exam['score'])}/${asText(exam['max'])}', color: AppColors.muted, dot: false),
        ]),
        if (asText(row['text']).isNotEmpty) ...<Widget>[const SizedBox(height: 10), Text(asText(row['text']), style: const TextStyle(height: 1.45))],
      ]),
    );
  }
}

class _Labeled extends StatelessWidget {
  const _Labeled({required this.icon, required this.label, required this.text, this.color});

  final IconData icon;
  final String label;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tone = color ?? AppColors.muted;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: AppColors.sunken.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(10)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Icon(icon, size: 18, color: tone),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(label, style: TextStyle(fontSize: 12, color: tone, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(text),
          ]),
        ),
      ]),
    );
  }
}

/// «Sharh qoldirish»: baho, matn, natija va saytda ko'rsatishga rozilik (server: oyiga bitta).
Future<void> showReviewSheet(BuildContext context, {int? studentId}) async {
  final api = AppScope.read(context).api;
  var rating = 5;
  var consent = false;
  var busy = false;
  final text = TextEditingController();
  final result = TextEditingController();
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheet) => StatefulBuilder(
      builder: (sheet, setSheet) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(sheet).bottom),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: <Widget>[
            Text(tr('Markaz haqida sharh'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
              for (var star = 1; star <= 5; star++)
                IconButton(
                  tooltip: tr('{0} yulduz', <Object>[star]),
                  onPressed: () => setSheet(() => rating = star),
                  icon: Icon(star <= rating ? Icons.star_rounded : Icons.star_outline_rounded, color: const Color(0xFFF2A93B), size: 36),
                ),
            ]),
            TextField(controller: text, maxLines: 4, maxLength: 1500, decoration: InputDecoration(labelText: tr('Sharhingiz'))),
            TextField(controller: result, maxLength: 120, decoration: InputDecoration(labelText: tr('Natija (ixtiyoriy)'), hintText: tr('Masalan: IELTS 7.5'))),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: consent,
              onChanged: (value) => setSheet(() => consent = value ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(tr("Sharh va natija markaz saytida ism bosh harfi bilan ko'rsatilishiga roziman."), style: const TextStyle(fontSize: 14)),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: busy || !consent || text.text.trim().length < 10
                  ? null
                  : () async {
                      setSheet(() => busy = true);
                      try {
                        await api.post('crm/my/review', <String, Object?>{
                          ..._who(studentId),
                          'rating': rating,
                          'text': text.text.trim(),
                          if (result.text.trim().isNotEmpty) 'result': result.text.trim(),
                          'consent': true,
                        });
                        if (sheet.mounted) Navigator.of(sheet).pop();
                        if (context.mounted) showMessage(context, tr("Rahmat! Sharhingiz ko'rib chiqilgach saytda chiqadi."));
                      } catch (error) {
                        setSheet(() => busy = false);
                        if (sheet.mounted) showMessage(sheet, errorText(error), error: true);
                      }
                    },
              child: Text(tr('Yuborish')),
            ),
          ]),
        ),
      ),
    ),
  );
  text.dispose();
  result.dispose();
}

// ---------------------------------------------------------------------------------------------------------------------
// Uyda mashq kundaligi
// ---------------------------------------------------------------------------------------------------------------------

class PracticePage extends StatelessWidget {
  const PracticePage({super.key, this.studentId});

  final int? studentId;

  @override
  Widget build(BuildContext context) {
    final api = AppScope.of(context).api;
    return Scaffold(
      appBar: pageBar(context, title: Text(tr('Uyda mashq'))),
      body: AsyncView<Map<String, dynamic>>(
        cacheKey: 'family_practice_${studentId ?? 0}',
        decode: (raw) => asMap(raw),
        load: () async => asMap(await api.get('crm/my/practice', query: _who(studentId))),
        builder: (context, data, reload) {
          final logs = asList(data['data']);
          final streak = asInt(data['streak']);
          final minutes = logs.fold<int>(0, (sum, row) => sum + asInt(row['minutes']));
          return ListView(
            padding: readable(context, const EdgeInsets.fromLTRB(16, 16, 16, 32)),
            children: <Widget>[
              Row(children: <Widget>[
                Expanded(child: StatCard(label: tr('Ketma-ket'), value: streak > 0 ? '🔥 $streak' : '0', icon: Icons.local_fire_department_outlined, color: AppColors.warning)),
                const SizedBox(width: 10),
                Expanded(child: StatCard(label: tr('30 kunda'), value: tr('{0} daqiqa', <Object>[minutes]), icon: Icons.timer_outlined, color: AppColors.accent)),
              ]),
              const SizedBox(height: 14),
              if (data['can_write'] == true) _PracticeForm(today: asText(data['today']), onSaved: reload),
              SectionTitle(tr('Oxirgi 30 kun')),
              if (logs.isEmpty)
                EmptyState(icon: Icons.self_improvement_outlined, text: tr("Hali yozuv yo'q. Har kuni necha daqiqa mashq qilganingizni yozib boring."))
              else
                for (final log in logs)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                        Row(children: <Widget>[
                          Expanded(child: Text(date(log['date']), style: const TextStyle(fontWeight: FontWeight.w700))),
                          Pill(tr('{0} daqiqa', <Object>[asInt(log['minutes'])]), color: AppColors.accent, dot: false),
                        ]),
                        if (asText(log['note']).isNotEmpty) ...<Widget>[const SizedBox(height: 4), Text(asText(log['note']))],
                        if (asText(log['teacher_note']).isNotEmpty) ...<Widget>[
                          const SizedBox(height: 8),
                          _Labeled(icon: Icons.chat_bubble_outline, label: tr('Ustoz izohi'), text: asText(log['teacher_note']), color: AppColors.accent),
                        ],
                      ]),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}

class _PracticeForm extends StatefulWidget {
  const _PracticeForm({required this.today, required this.onSaved});

  final String today;
  final Future<void> Function() onSaved;

  @override
  State<_PracticeForm> createState() => _PracticeFormState();
}

class _PracticeFormState extends State<_PracticeForm> {
  int _minutes = 30;
  bool _yesterday = false;
  bool _busy = false;
  final TextEditingController _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final today = DateTime.tryParse(widget.today) ?? DateTime.now();
    final day = _yesterday ? today.subtract(const Duration(days: 1)) : today;
    try {
      await AppScope.read(context).api.post('crm/my/practice', <String, Object?>{'date': isoDay(day), 'minutes': _minutes, if (_note.text.trim().isNotEmpty) 'note': _note.text.trim()});
      _note.clear();
      if (mounted) showMessage(context, tr('Saqlandi.'));
      await widget.onSaved();
    } catch (error) {
      if (mounted) showMessage(context, errorText(error), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          Text(tr('Bugun mashq qildingizmi?'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 10),
          SegmentedButton<bool>(
            segments: <ButtonSegment<bool>>[ButtonSegment<bool>(value: false, label: Text(tr('Bugun'))), ButtonSegment<bool>(value: true, label: Text(tr('Kecha')))],
            selected: <bool>{_yesterday},
            onSelectionChanged: (value) => setState(() => _yesterday = value.first),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
            for (final m in const <int>[15, 30, 45, 60, 90])
              ChoiceChip(label: Text(tr('{0} daqiqa', <Object>[m])), selected: _minutes == m, onSelected: (_) => setState(() => _minutes = m)),
          ]),
          const SizedBox(height: 8),
          TextField(controller: _note, maxLength: 500, decoration: InputDecoration(labelText: tr('Nima qildingiz? (ixtiyoriy)'))),
          FilledButton(onPressed: _busy ? null : _save, child: Text(tr('Saqlash'))),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------------
// Keyingi o'quv yili (qayta ro'yxat)
// ---------------------------------------------------------------------------------------------------------------------

class ReEnrollPage extends StatelessWidget {
  const ReEnrollPage({super.key});

  @override
  Widget build(BuildContext context) {
    final api = AppScope.of(context).api;
    return Scaffold(
      appBar: pageBar(context, title: Text(tr("Keyingi o'quv yili"))),
      body: AsyncView<List<Map<String, dynamic>>>(
        load: () async => asList(await api.get('my/reenroll')),
        builder: (context, rows, reload) {
          if (rows.isEmpty) {
            return ListView(children: <Widget>[EmptyState(icon: Icons.event_available_outlined, text: tr("Maktab keyingi yil uchun ro'yxatni boshlaganda shu yerda ko'rasiz."))]);
          }
          return ListView.separated(
            padding: readable(context, const EdgeInsets.fromLTRB(16, 16, 16, 32)),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) => _ReEnrollCard(row: rows[i], onChanged: reload),
          );
        },
      ),
    );
  }
}

class _ReEnrollCard extends StatefulWidget {
  const _ReEnrollCard({required this.row, required this.onChanged});

  final Map<String, dynamic> row;
  final Future<void> Function() onChanged;

  @override
  State<_ReEnrollCard> createState() => _ReEnrollCardState();
}

class _ReEnrollCardState extends State<_ReEnrollCard> {
  bool _busy = false;

  static const List<String> _reasons = <String>["Boshqa shaharga ko'chamiz", "Narx to'g'ri kelmaydi", "Boshqa maktabga o'tamiz", "Ta'lim sifati qoniqtirmadi", 'Uzoq / qatnov noqulay'];

  Future<void> _answer(String answer) async {
    String? reason;
    if (answer == 'no') {
      reason = await _askReason();
      if (reason == null) return;
    }
    if (!mounted) return;
    final api = AppScope.read(context).api;
    setState(() => _busy = true);
    try {
      await api.post('my/reenroll/${asInt(widget.row['id'])}', <String, Object?>{'answer': answer, if (reason != null) 'reason': reason});
      if (mounted) {
        showMessage(context, answer == 'yes' ? tr('Rahmat! Joy saqlab qolindi.') : answer == 'no' ? tr('Javobingiz qabul qilindi. Rahmat!') : tr('Yaxshi, muddatgacha qaror qiling.'));
      }
      await widget.onChanged();
    } catch (error) {
      if (mounted) showMessage(context, errorText(error), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askReason() {
    final controller = TextEditingController(text: asText(widget.row['reason']));
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(sheet).bottom),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: <Widget>[
            Text(tr('Sababini qisqacha yozing — bu bizga yaxshilanishga yordam beradi.'), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: <Widget>[
              for (final r in _reasons)
                ChoiceChip(label: Text(tr(r)), selected: controller.text == tr(r), onSelected: (_) => setSheet(() => controller.text = tr(r))),
            ]),
            const SizedBox(height: 8),
            TextField(controller: controller, maxLength: 255, onChanged: (_) => setSheet(() {}), decoration: InputDecoration(labelText: tr('Sababi'))),
            FilledButton(
              onPressed: controller.text.trim().isEmpty ? null : () => Navigator.of(sheet).pop(controller.text.trim()),
              child: Text(tr('Yuborish')),
            ),
          ]),
        ),
      ),
    ).whenComplete(controller.dispose);
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final campaign = asMap(row['campaign']);
    final student = asMap(row['student']);
    final answer = asText(row['answer'], 'pending');
    final accepting = campaign['accepting'] == true;
    final document = row['document'] is Map ? asMap(row['document']) : null;
    final deposit = asInt(campaign['deposit']);
    final payUrl = asText(row['pay_url']);
    Widget choice(String value, String label, Color color) {
      final active = answer == value;
      return Expanded(
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            side: BorderSide(color: active ? color : AppColors.line, width: active ? 2 : 1),
            backgroundColor: active ? AppColors.soft(color) : null,
            foregroundColor: active ? color : null,
          ),
          onPressed: _busy || !accepting ? null : () => _answer(value),
          child: Text(label, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      );
    }

    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        Text(asText(campaign['title']), style: TextStyle(color: AppColors.muted, fontSize: 13)),
        const SizedBox(height: 2),
        Text(tr('{0} keyingi yil ham biz bilanmi?', <Object>[asText(student['full_name'])]), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(<String>[
          tr('Javob muddati: {0}', <Object>[date(campaign['deadline'])]),
          if (campaign['next_fee'] != null) tr('Keyingi yil: {0}', <Object>[money(asInt(campaign['next_fee']))]),
        ].join(' · '), style: TextStyle(color: AppColors.muted)),
        if (asText(campaign['message']).isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.sunken.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(12)),
            child: Text(asText(campaign['message'])),
          ),
        ],
        const SizedBox(height: 14),
        if (accepting)
          Row(children: <Widget>[
            choice('yes', tr('Ha, davom etamiz'), AppColors.success),
            const SizedBox(width: 8),
            choice('thinking', tr("O'ylayapmiz"), AppColors.warning),
            const SizedBox(width: 8),
            choice('no', tr("Yo'q"), AppColors.danger),
          ])
        else
          Text(tr('Javob qabul qilish yakunlangan.'), style: TextStyle(color: AppColors.muted)),
        if (answer == 'no' && asText(row['reason']).isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Text('${tr('Sababi')}: ${asText(row['reason'])}', style: TextStyle(color: AppColors.muted)),
        ],
        if (answer == 'yes' && (document != null || deposit > 0)) ...<Widget>[
          const SizedBox(height: 14),
          Text(tr('Keyingi qadamlar'), style: const TextStyle(fontWeight: FontWeight.w700)),
          if (document != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.description_outlined, color: AppColors.accent),
              title: Text(tr('Shartnoma № {0}', <Object>[asText(document['number'])])),
              subtitle: Text(asText(document['status']) == 'signed' ? tr('tasdiqlangan') : tr('tasdiqlash kutilmoqda'),
                  style: TextStyle(color: asText(document['status']) == 'signed' ? AppColors.success : AppColors.warning)),
              trailing: asText(document['status']) == 'signed'
                  ? null
                  : FilledButton(
                      onPressed: () async {
                        await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => MyDocumentPage(id: asInt(document['id']))));
                        await widget.onChanged();
                      },
                      child: Text(tr('Tasdiqlash')),
                    ),
            ),
          if (deposit > 0)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.savings_outlined, color: AppColors.accent),
              title: Text(tr('Joy band qilish avansi: {0}', <Object>[money(deposit)])),
              subtitle: Text(row['deposit_paid'] == true ? tr("to'langan") : tr("Avans farzandingiz balansiga tushadi va keyingi yil to'loviga hisoblanadi."),
                  style: TextStyle(color: row['deposit_paid'] == true ? AppColors.success : AppColors.muted)),
              trailing: payUrl.isEmpty
                  ? null
                  : FilledButton(onPressed: () => launchUrl(Uri.parse(payUrl), mode: LaunchMode.externalApplication), child: Text(tr("To'lash"))),
            ),
        ],
      ]),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------------
// Yakka darslar (bron)
// ---------------------------------------------------------------------------------------------------------------------

class BookingPage extends StatelessWidget {
  const BookingPage({super.key, this.studentId});

  final int? studentId;

  @override
  Widget build(BuildContext context) {
    final api = AppScope.of(context).api;
    return Scaffold(
      appBar: pageBar(context, title: Text(tr('Yakka darslar'))),
      body: AsyncView<Map<String, dynamic>>(
        load: () async => asMap(await api.get('crm/my/booking/slots')),
        builder: (context, data, reload) {
          final mine = asList(data['bookings'], 'bookings')
              .where((row) => studentId == null || asInt(asMap(row['student'])['id']) == studentId)
              .where((row) => <String>['new', 'confirmed'].contains(asText(row['status'])))
              .toList();
          final credits = asList(data['credits'], 'credits').where((row) => studentId == null || asInt(row['student_id']) == studentId).toList();
          final slots = asList(data['data']);
          final byDay = <String, List<Map<String, dynamic>>>{};
          for (final slot in slots) {
            byDay.putIfAbsent(asText(slot['date']), () => <Map<String, dynamic>>[]).add(slot);
          }
          return ListView(
            padding: readable(context, const EdgeInsets.fromLTRB(16, 16, 16, 32)),
            children: <Widget>[
              if (mine.isNotEmpty) ...<Widget>[
                SectionTitle(tr('Yozilgan darslar')),
                for (final row in mine)
                  Padding(padding: const EdgeInsets.only(bottom: 8), child: _BookingCard(row: row, cancelHours: asInt(data['cancel_hours']), onChanged: reload)),
              ],
              if (credits.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: ToneBox(
                    color: AppColors.success,
                    padding: const EdgeInsets.all(12),
                    child: Text(tr('Qayta dars krediti: {0} ta — bron qilishda bepul ishlatiladi.', <Object>[credits.length])),
                  ),
                ),
              SectionTitle(tr("Bo'sh vaqtlar")),
              if (slots.isEmpty)
                EmptyState(icon: Icons.event_busy_outlined, text: tr("Hozircha bo'sh vaqt yo'q. Ustozlar jadvalni yangilagach shu yerda chiqadi."))
              else
                for (final entry in byDay.entries) ...<Widget>[
                  Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 6),
                    child: Text(dayTitle(DateTime.parse(entry.key)), style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
                    for (final slot in entry.value)
                      ActionChip(
                        avatar: const Icon(Icons.schedule, size: 18),
                        label: Text('${asText(slot['time'])} · ${asText(slot['teacher'])}'),
                        onPressed: () => _book(context, slot, credits, reload),
                      ),
                  ]),
                ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _book(BuildContext context, Map<String, dynamic> slot, List<Map<String, dynamic>> credits, Future<void> Function() reload) async {
    final teacher = asInt(slot['teacher_id']);
    final credit = credits.any((row) => row['teacher_id'] == null || asInt(row['teacher_id']) == teacher);
    final price = asInt(slot['price']);
    final ok = await confirm(
      context,
      <String>[
        tr('{0}, {1} — {2}', <Object>[dayTitle(DateTime.parse(asText(slot['date']))), asText(slot['time']), asText(slot['teacher'])]),
        if (credit) tr('Qayta dars krediti ishlatiladi (bepul).') else if (price > 0) tr('Narxi: {0}', <Object>[money(price)]),
      ].join('\n'),
      action: tr('Yozilish'),
    );
    if (!ok || !context.mounted) return;
    try {
      await AppScope.read(context).api.post('crm/my/booking', <String, Object?>{
        'teacher_id': teacher,
        'starts_at': asText(slot['starts_at']),
        if (studentId != null) 'student_id': studentId,
        if (credit) 'use_credit': true,
      });
      if (context.mounted) showMessage(context, tr('Yozildingiz. Ustoz tasdiqlagach xabar keladi.'));
      await reload();
    } catch (error) {
      if (context.mounted) showMessage(context, errorText(error), error: true);
    }
  }
}

class _BookingCard extends StatelessWidget {
  const _BookingCard({required this.row, required this.cancelHours, required this.onChanged});

  final Map<String, dynamic> row;
  final int cancelHours;
  final Future<void> Function() onChanged;

  Future<void> _reply(BuildContext context, String answer) async {
    if (answer == 'no') {
      final free = DateTime.tryParse(asText(row['free_until']))?.isAfter(DateTime.now()) ?? true;
      final ok = await confirm(
        context,
        free ? tr('Dars bekor qilinsinmi? Hozir bepul — qayta dars krediti beriladi.') : tr('Dars bekor qilinsinmi? {0} soatdan kam qolgani uchun dars haqi olinadi.', <Object>[cancelHours]),
        action: tr('Bekor qilish'),
        danger: true,
      );
      if (!ok || !context.mounted) return;
    }
    try {
      await AppScope.read(context).api.post('crm/my/booking/${asInt(row['id'])}/reply', <String, Object?>{'answer': answer});
      if (context.mounted) showMessage(context, answer == 'yes' ? tr('Rahmat! Ustozga xabar berildi.') : tr('Dars bekor qilindi.'));
      await onChanged();
    } catch (error) {
      if (context.mounted) showMessage(context, errorText(error), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reply = asText(row['reply']);
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Text(dateTime(row['starts_at']), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        Text(<String>[asText(asMap(row['teacher'])['name']), asText(asMap(row['student'])['full_name'])].where((s) => s.isNotEmpty).join(' · '),
            style: TextStyle(color: AppColors.muted)),
        const SizedBox(height: 10),
        if (reply == 'yes')
          Pill(tr('Kelishingizni tasdiqladingiz'), color: AppColors.success)
        else
          Row(children: <Widget>[
            Expanded(child: FilledButton(onPressed: () => _reply(context, 'yes'), child: Text(tr('Kelaman')))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton(onPressed: () => _reply(context, 'no'), child: Text(tr('Bekor qilish')))),
          ]),
      ]),
    );
  }
}

/// Ota-ona bosh sahifasi: farzand bo'yicha ochiq qayta ro'yxat so'rovi (javob kutilmoqda yoki keyingi qadam qolgan).
class ReEnrollBanner extends StatefulWidget {
  const ReEnrollBanner({super.key, required this.studentId});

  final int studentId;

  @override
  State<ReEnrollBanner> createState() => _ReEnrollBannerState();
}

class _ReEnrollBannerState extends State<ReEnrollBanner> {
  Map<String, dynamic>? _row;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final rows = asList(await AppScope.read(context).api.get('my/reenroll'));
      Map<String, dynamic>? found;
      for (final row in rows) {
        final campaign = asMap(row['campaign']);
        if (asInt(asMap(row['student'])['id']) != widget.studentId || campaign['accepting'] != true) continue;
        final answer = asText(row['answer']);
        final document = row['document'] is Map ? asMap(row['document']) : null;
        final open = answer == 'pending' || answer == 'thinking' ||
            (answer == 'yes' && ((document != null && asText(document['status']) != 'signed') || asText(row['pay_url']).isNotEmpty));
        if (open) {
          found = row;
          break;
        }
      }
      if (mounted) setState(() => _row = found);
    } catch (_) {
      // Modul yoki rol mos emas — banner ko'rsatilmaydi.
    }
  }

  @override
  Widget build(BuildContext context) {
    final row = _row;
    if (row == null) return const SizedBox.shrink();
    final campaign = asMap(row['campaign']);
    final waiting = asText(row['answer']) == 'yes';
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: AppCard(
        tone: AppColors.accent,
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ReEnrollPage()));
          await _load();
        },
        child: Row(children: <Widget>[
          Icon(Icons.event_available_outlined, color: AppColors.accent, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text(waiting ? tr('Keyingi qadamlar') : tr("Keyingi o'quv yili"), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              Text(waiting ? tr('Shartnoma va avans — joyni band qilish uchun.') : tr('Javob muddati: {0}', <Object>[date(campaign['deadline'])]),
                  style: TextStyle(color: AppColors.muted)),
            ]),
          ),
          const Icon(Icons.chevron_right),
        ]),
      ),
    );
  }
}
