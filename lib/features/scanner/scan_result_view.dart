// Tekshirilgan varaqa: to'g'rilangan rasm ustida belgilar (to'g'ri — yashil, xato — qizil, shubhali — sariq),
// natija va holat. Skaner ostidagi kartochka va to'liq ko'rinish (pastdan ochiladigan oyna).
import 'dart:io';
import 'dart:typed_data';

import 'package:edux_omr/edux_omr.dart';
import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'scan_queue.dart';
import 'scan_review_page.dart';

const Map<String, String> scanFlagLabels = <String, String>{
  'multiple': 'bir nechta belgi',
  'uncertain': 'xira belgi',
  'student_code_unreadable': "o'quvchi kodi o'qilmadi",
  'qr_not_read': "QR kod o'qilmadi",
  'marker_missing': "burchak belgisi ko'rinmaydi",
  'low_resolution': 'rasm sifati past',
  'device_mismatch': "telefon boshqacha o'qidi",
  'server_unavailable': "server ishlamadi — telefon o'qishi",
  'server_unreadable': "server o'qiy olmadi — telefon o'qishi",
};

String flagText(Map<String, dynamic> flag) {
  final label = tr(scanFlagLabels[flag['type']] ?? '${flag['type']}');
  final question = flag['question'];
  return question == null ? label : '${tr('{0}-savol', <Object?>[question])}: $label';
}

class StatusStyle {
  const StatusStyle(this.label, this.color, this.icon);

  final String label;
  final Color color;
  final IconData icon;
}

StatusStyle scanStatusStyle(String status) {
  if (status == ScanStatus.processed) return StatusStyle(tr('Tekshirildi'), AppColors.success, Icons.check_circle);
  if (status == ScanStatus.needsReview) return StatusStyle(tr("Ko'rib chiqish kerak"), AppColors.warning, Icons.rate_review);
  if (status == ScanStatus.failed) return StatusStyle(tr("O'qilmadi"), AppColors.danger, Icons.error);
  if (status == ScanStatus.offline) return StatusStyle(tr("Internet yo'q — navbatda"), AppColors.muted, Icons.cloud_off);
  if (status == ScanStatus.uploading) return StatusStyle(tr('Yuborilmoqda...'), AppColors.brand, Icons.cloud_upload);
  return StatusStyle(tr('Navbatda'), AppColors.muted, Icons.schedule);
}

/// To'g'rilangan varaqa va belgilar.
class SheetMarksView extends StatelessWidget {
  const SheetMarksView({
    super.key,
    required this.image,
    required this.answers,
    this.options = 4,
    this.key2,
    this.doubtful = const <int, List<int>>{},
  });

  final ImageProvider image;
  final List<List<int>> answers;
  final int options;

  /// Variant kaliti (bo'lsa, to'g'ri/xato ranglanadi).
  final List<List<int>>? key2;

  /// Savol (0 dan) -> shubhali variantlar.
  final Map<int, List<int>> doubtful;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: InteractiveViewer(
        maxScale: 5,
        child: AspectRatio(
          aspectRatio: OmrLayout.sheetWidth / OmrLayout.sheetHeight,
          child: Stack(fit: StackFit.expand, children: <Widget>[
            Image(image: image, fit: BoxFit.fill, gaplessPlayback: true),
            CustomPaint(painter: _MarksPainter(answers, options, key2, doubtful)),
          ]),
        ),
      ),
    );
  }
}

class _MarksPainter extends CustomPainter {
  _MarksPainter(this.answers, this.options, this.key, this.doubtful);

  final List<List<int>> answers;
  final int options;
  final List<List<int>>? key;
  final Map<int, List<int>> doubtful;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / OmrLayout.sheetWidth;
    final radius = (OmrLayout.bubbleRadius + 0.7) * scale;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = (0.55 * scale).clamp(1.2, 4.0);
    final fill = Paint()..style = PaintingStyle.fill;
    final total = key?.length ?? answers.length;
    for (var question = 0; question < total; question++) {
      final marks = question < answers.length ? answers[question] : const <int>[];
      final expected = key != null && question < key!.length ? key![question] : null;
      for (var option = 0; option < options; option++) {
        final center = OmrLayout.answerCenter(question, option);
        final point = Offset(center.dx * scale, center.dy * scale);
        final marked = marks.contains(option);
        final correct = expected?.contains(option) ?? false;
        Color? color;
        if (marked && expected == null) {
          color = AppColors.brand;
        } else if (marked && correct) {
          color = AppColors.success;
        } else if (marked) {
          color = AppColors.danger;
        } else if (correct) {
          color = AppColors.success.withAlpha(150);
        }
        if (doubtful[question]?.contains(option) ?? false) color = AppColors.warning;
        if (color == null) continue;
        if (marked) {
          fill.color = color.withAlpha(45);
          canvas.drawCircle(point, radius, fill);
        }
        stroke.color = color;
        canvas.drawCircle(point, radius, stroke);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MarksPainter oldDelegate) =>
      oldDelegate.answers != answers || oldDelegate.key != key || oldDelegate.doubtful != doubtful;
}

Map<int, List<int>> doubtfulFromFlags(List<Map<String, dynamic>> flags) {
  final result = <int, List<int>>{};
  for (final flag in flags) {
    if (flag['type'] != 'uncertain' && flag['type'] != 'device_mismatch') continue;
    final question = flag['question'];
    if (question is! num) continue;
    result[question.toInt() - 1] = asRawList(flag['options']).map((v) => asInt(v)).toList();
  }
  return result;
}

/// Skaner ostidagi oxirgi natija kartochkasi.
class ScanResultCard extends StatelessWidget {
  const ScanResultCard({super.key, required this.item, this.onTap});

  final QueuedScan item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final style = scanStatusStyle(item.status);
    final correct = item.serverCorrect ?? item.localCorrect;
    final total = item.serverTotal ?? item.localTotal;
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: <Widget>[
            Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: style.color.withAlpha(28), borderRadius: BorderRadius.circular(14)),
              child: correct != null && total != null
                  ? Text('$correct/$total', style: TextStyle(fontWeight: FontWeight.w800, color: style.color, fontSize: 15))
                  : Icon(style.icon, color: style.color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text(item.displayName,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 3),
                Row(children: <Widget>[
                  Icon(style.icon, size: 14, color: style.color),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      <String>[
                        style.label,
                        if (item.variant != null) tr('{0}-variant', <Object?>[item.variant]),
                        if (item.serverScore != null) '${number(item.serverScore)} ${tr('ball')}'
                        else if (item.localScore != null) '≈ ${number(item.localScore)} ${tr('ball')}',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: style.color, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                ]),
              ]),
            ),
            Icon(Icons.chevron_right, color: AppColors.muted),
          ]),
        ),
      ),
    );
  }
}

/// Varaqa tafsiloti (pastdan ochiladi).
Future<void> showScanDetails(BuildContext context, QueuedScan item, {Uint8List? preview, List<List<int>>? key}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      maxChildSize: 0.95,
      builder: (context, controller) => AnimatedBuilder(
        animation: ScanQueue.instance,
        builder: (context, _) => _ScanDetails(item: item, preview: preview, answerKey: key, controller: controller),
      ),
    ),
  );
}

class _ScanDetails extends StatelessWidget {
  const _ScanDetails({required this.item, required this.controller, this.preview, this.answerKey});

  final QueuedScan item;
  final Uint8List? preview;
  final List<List<int>>? answerKey;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    final queue = ScanQueue.instance;
    final style = scanStatusStyle(item.status);
    final answers = asRawList(item.device['answers'])
        .map((row) => asRawList(row).map((v) => asInt(v)).toList())
        .toList();
    final flags = asRawList(item.device['flags']).whereType<Map>().map((f) => Map<String, dynamic>.from(f)).toList();
    final previewFile = queue.previewFile(item);
    ImageProvider? image;
    if (preview != null) {
      image = MemoryImage(preview!);
    } else if (previewFile.existsSync()) {
      image = FileImage(File(previewFile.path));
    }
    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      children: <Widget>[
        Center(
          child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(4))),
        ),
        const SizedBox(height: 14),
        Row(children: <Widget>[
          Avatar(item.displayName, size: 46, color: style.color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text(item.displayName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              Text(
                <String>[
                  if (item.examTitle != null) item.examTitle!,
                  if (item.variant != null) tr('{0}-variant', <Object?>[item.variant]),
                  if (item.studentCode != null) '#${item.studentCode}',
                ].join(' · '),
                style: TextStyle(color: AppColors.muted),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        AppCard(
          child: Column(children: <Widget>[
            Row(children: <Widget>[
              Icon(style.icon, color: style.color, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(style.label, style: TextStyle(color: style.color, fontWeight: FontWeight.w700))),
              Text(dateTime(item.createdAt.toIso8601String()), style: TextStyle(color: AppColors.muted, fontSize: 12)),
            ]),
            if (item.message != null && item.message!.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerLeft, child: Text(tr(item.message!), style: TextStyle(color: AppColors.muted))),
            ],
            const Divider(height: 20),
            if (item.serverCorrect != null)
              KeyValue(tr('Natija (server)'), '${item.serverCorrect} / ${item.serverTotal} · ${number(item.serverScore)} ${tr('ball')}'),
            if (item.localCorrect != null)
              KeyValue(tr('Telefonda hisoblangan'), '${item.localCorrect} / ${item.localTotal} · ${number(item.localScore)} ${tr('ball')}'),
            if (item.serverCorrect == null && item.localCorrect == null)
              KeyValue(tr('Belgilangan javoblar'), '${answers.where((row) => row.isNotEmpty).length} / ${answers.length}'),
          ]),
        ),
        if (flags.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          AppCard(
            color: AppColors.soft(AppColors.warning),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: flags
                  .map((flag) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(children: <Widget>[
                          Icon(Icons.warning_amber_rounded, size: 18, color: AppColors.warning),
                          const SizedBox(width: 8),
                          Expanded(child: Text(flagText(flag))),
                        ]),
                      ))
                  .toList(),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Row(children: <Widget>[
          if (item.status == ScanStatus.needsReview && item.scanId != null)
            Expanded(
              child: FilledButton.icon(
                icon: const Icon(Icons.rate_review_outlined),
                label: Text(tr("Ko'rib chiqish")),
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ScanReviewPage(scanId: item.scanId!)));
                },
              ),
            ),
          if (item.status == ScanStatus.failed || item.status == ScanStatus.offline)
            Expanded(
              child: FilledButton.icon(
                icon: const Icon(Icons.refresh),
                label: Text(tr('Qayta yuborish')),
                onPressed: () => queue.retry(item),
              ),
            ),
          if (item.done || item.status == ScanStatus.offline) ...<Widget>[
            const SizedBox(width: 10),
            OutlinedButton(
              onPressed: () async {
                if (await confirm(context, tr("Varaqa telefondan o'chirilsinmi? Serverdagi natija o'zgarmaydi."), danger: true)) {
                  await queue.remove(item);
                  if (context.mounted) Navigator.pop(context);
                }
              },
              child: const Icon(Icons.delete_outline),
            ),
          ],
        ]),
        if (image != null) ...<Widget>[
          const SizedBox(height: 16),
          SheetMarksView(
            image: image,
            answers: answers,
            options: asOptions(item.device['options']),
            key2: answerKey,
            doubtful: doubtfulFromFlags(flags),
          ),
          const SizedBox(height: 8),
          Text(tr("Yashil — to'g'ri, qizil — xato, sariq — shubhali. Kattalashtirish uchun ikki barmoq bilan suring."),
              textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 12)),
        ],
      ],
    );
  }
}

int asOptions(dynamic value) => value is num ? value.toInt() : 4;
