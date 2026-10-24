// Uy vazifalari: ro'yxat, javob yuborish (matn va/yoki daftar surati), baho va o'qituvchi izohi.
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../../core/adaptive.dart';
import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

class AssignmentsPage extends StatelessWidget {
  const AssignmentsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final api = AppScope.of(context).api;
    return Scaffold(
      appBar: pageBar(context, title: Text(tr('Uy vazifalari'))),
      body: AsyncView<List<Map<String, dynamic>>>(
        cacheKey: 'lms_my_assignments',
        decode: (raw) => asList(raw),
        load: () async => asList(asMap(await api.get('lms/my/assignments'))['assignments'], 'assignments'),
        builder: (context, items, reload) {
          if (items.isEmpty) {
            return ListView(children: <Widget>[
              EmptyState(text: tr("Hozircha uy vazifasi yo'q. O'qituvchi vazifa berganda shu yerda ko'rinadi.")),
            ]);
          }
          return ListView.separated(
            padding: readable(context, const EdgeInsets.all(16)),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) => AssignmentCard(assignment: items[index], onChanged: reload, showCourse: true),
          );
        },
      ),
    );
  }
}

class AssignmentCard extends StatelessWidget {
  const AssignmentCard({super.key, required this.assignment, required this.onChanged, this.showCourse = false});

  final Map<String, dynamic> assignment;
  final Future<void> Function() onChanged;
  final bool showCourse;

  @override
  Widget build(BuildContext context) {
    final submission = asMap(assignment['submission']);
    final graded = submission['is_graded'] == true;
    final submitted = submission.isNotEmpty;
    final overdue = assignment['is_overdue'] == true;
    final color = graded ? AppColors.success : (submitted ? AppColors.brand : (overdue ? AppColors.danger : AppColors.warning));
    final status = graded
        ? '${tr('Baholandi')}: ${number(asDouble(submission['score']))} / ${asInt(assignment['max_score'])}'
        : submitted
            ? tr('Topshirildi')
            : (overdue ? tr("Muddati o'tgan") : tr('Topshirish kerak'));
    final canSubmit = assignment['can_submit'] != false && !graded;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Row(children: <Widget>[
          Expanded(child: Text(asText(assignment['title']), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
          Pill(status, color: color),
        ]),
        if (showCourse && assignment['course'] != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(<String>[asText(asMap(assignment['course'])['title']), asText(asMap(assignment['lesson'])['title'])].join(' · '),
                style: TextStyle(color: AppColors.muted, fontSize: 13)),
          ),
        if (asText(assignment['description']).isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          MathText(asText(assignment['description'])),
        ],
        if (assignment['due_at'] != null) ...<Widget>[
          const SizedBox(height: 6),
          Text(tr('Muddat: {0}', <Object?>[dateTime(assignment['due_at'])]), style: TextStyle(color: overdue ? AppColors.danger : AppColors.muted, fontSize: 13)),
        ],
        if (submitted) ...<Widget>[
          const Divider(height: 20),
          if (asText(submission['content']).isNotEmpty) Text(asText(submission['content'])),
          if (submission['has_file'] == true)
            Text('📎 ${asText(submission['file_name'])}', style: TextStyle(color: AppColors.muted)),
          if (asText(submission['feedback']).isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppColors.success.withAlpha(20), borderRadius: BorderRadius.circular(10)),
              child: Text('${tr("O'qituvchi izohi:")} ${asText(submission['feedback'])}'),
            ),
          ],
        ],
        if (assignment['closed_reason'] != null && !graded) ...<Widget>[
          const SizedBox(height: 6),
          Text(tr(asText(assignment['closed_reason'])), style: TextStyle(color: AppColors.muted, fontSize: 13)),
        ],
        if (canSubmit) ...<Widget>[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              final sent = await showSubmissionSheet(context, assignment);
              if (sent == true) await onChanged();
            },
            icon: Icon(submitted ? Icons.edit_outlined : Icons.send_outlined),
            label: Text(submitted ? tr('Javobni yangilash') : tr('Javobni yuborish')),
          ),
        ],
      ]),
    );
  }
}

Future<bool?> showSubmissionSheet(BuildContext context, Map<String, dynamic> assignment) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _SubmissionForm(assignment: assignment),
    ),
  );
}

class _SubmissionForm extends StatefulWidget {
  const _SubmissionForm({required this.assignment});

  final Map<String, dynamic> assignment;

  @override
  State<_SubmissionForm> createState() => _SubmissionFormState();
}

class _SubmissionFormState extends State<_SubmissionForm> {
  late final TextEditingController _content =
      TextEditingController(text: asText(asMap(widget.assignment['submission'])['content']));
  XFile? _photo;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _content.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    final file = await ImagePicker().pickImage(source: source, imageQuality: 80, maxWidth: 2200);
    if (file != null) setState(() => _photo = file);
  }

  Future<void> _send() async {
    if (_content.text.trim().isEmpty && _photo == null) {
      setState(() => _error = tr('Javob matnini yozing yoki fayl biriktiring.'));
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    final api = AppScope.read(context).api;
    try {
      final files = <http.MultipartFile>[];
      if (_photo != null) {
        files.add(http.MultipartFile.fromBytes('file', await _photo!.readAsBytes(), filename: 'javob.jpg'));
      }
      await api.multipart(
        'lms/my/assignments/${asInt(widget.assignment['id'])}/submission',
        fields: <String, String>{'content': _content.text.trim()},
        files: files,
      );
      if (!mounted) return;
      showMessage(context, tr('Yuborildi'));
      Navigator.pop(context, true);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: <Widget>[
        Text(asText(widget.assignment['title']), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
        const SizedBox(height: 14),
        if (_error != null) ...<Widget>[
          Text(_error!, style: TextStyle(color: AppColors.danger)),
          const SizedBox(height: 8),
        ],
        TextField(
          controller: _content,
          minLines: 4,
          maxLines: 10,
          decoration: InputDecoration(hintText: tr('Javobingizni shu yerga yozing')),
        ),
        const SizedBox(height: 12),
        Row(children: <Widget>[
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _pick(ImageSource.camera),
              icon: const Icon(Icons.photo_camera_outlined),
              label: Text(tr('Suratga olish')),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _pick(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined),
              label: Text(tr('Galereya')),
            ),
          ),
        ]),
        if (_photo != null) ...<Widget>[
          const SizedBox(height: 8),
          Row(children: <Widget>[
            Icon(Icons.image_outlined, color: AppColors.success),
            const SizedBox(width: 8),
            Expanded(child: Text(_photo!.name, overflow: TextOverflow.ellipsis)),
            IconButton(onPressed: () => setState(() => _photo = null), icon: const Icon(Icons.close)),
          ]),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _sending ? null : _send,
          child: _sending
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
              : Text(tr('Yuborish')),
        ),
      ]),
    );
  }
}
