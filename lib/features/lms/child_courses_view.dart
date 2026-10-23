// Ota-ona: «Farzandim → Kurslar» (1.35) — kurslar bo'yicha o'zlashtirish foizi, oxirgi dars, uy vazifalari (topshirilmagan,
// tekshirilmagan, baholangan), o'rtacha baho, «tushunmadim» deb belgilangan darslar va yaqin jonli dars.
// API: GET lms/child/courses?student_id= (backend ChildCourseController).
import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

class ChildCoursesView extends StatelessWidget {
  const ChildCoursesView({super.key, required this.studentId});

  final int studentId;

  @override
  Widget build(BuildContext context) {
    final api = AppScope.of(context).api;
    return AsyncView<Map<String, dynamic>>(
      cacheKey: 'child_courses_$studentId',
      decode: asMap,
      load: () async => asMap(await api.get('lms/child/courses', query: <String, Object?>{'student_id': studentId})),
      builder: (context, data, reload) {
        final courses = asList(data['courses'], 'courses');
        if (courses.isEmpty) {
          return ListView(children: <Widget>[
            EmptyState(icon: Icons.menu_book_outlined, text: tr("Farzandingizga hali kurs ochilmagan. O'qituvchi kurs e'lon qilganda shu yerda ko'rinadi.")),
          ]);
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
          itemCount: courses.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) => _ChildCourseCard(course: courses[index]),
        );
      },
    );
  }
}

class _ChildCourseCard extends StatelessWidget {
  const _ChildCourseCard({required this.course});

  final Map<String, dynamic> course;

  @override
  Widget build(BuildContext context) {
    final progress = asMap(course['progress']);
    final assignments = asMap(course['assignments']);
    final todo = asList(assignments['todo'], 'todo');
    final submitted = asList(assignments['submitted'], 'submitted');
    final graded = asList(assignments['graded'], 'graded');
    final last = asMap(course['last_lesson']);
    final live = asMap(course['next_live']);
    final confused = asRawList(course['not_understood']).map((item) => '$item').toList();
    final average = course['average_grade_percent'];
    final overdue = todo.where((item) => item['overdue'] == true).length;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Row(children: <Widget>[
          Expanded(child: Text(asText(course['title']), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
          if (course['unlocked'] == false) Pill(tr('Yopiq'), color: AppColors.muted),
        ]),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(value: (asDouble(progress['percent']) / 100).clamp(0, 1).toDouble(), minHeight: 8),
        ),
        const SizedBox(height: 4),
        Text(tr('{0} / {1} dars · {2}%', <Object?>[asInt(progress['done']), asInt(progress['total']), number(asDouble(progress['percent']))]),
            style: TextStyle(color: AppColors.muted, fontSize: 12)),
        if (last.isNotEmpty) KeyValue(tr('Oxirgi dars'), '${asText(last['title'])} · ${date(last['completed_at'])}'),
        if (average != null) KeyValue(tr("O'rtacha baho"), '${number(asDouble(average))}%'),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 6, children: <Widget>[
          Pill(tr('Topshirilmagan: {0}', <Object?>[todo.length]), color: overdue > 0 ? AppColors.danger : (todo.isEmpty ? AppColors.success : AppColors.warning)),
          Pill(tr('Tekshirilmoqda: {0}', <Object?>[submitted.length]), color: AppColors.brand),
          Pill(tr('Baholangan: {0}', <Object?>[graded.length]), color: AppColors.success),
        ]),
        if (todo.isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          for (final item in todo.take(4))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(children: <Widget>[
                Icon(item['overdue'] == true ? Icons.error_outline : Icons.edit_outlined, size: 16, color: item['overdue'] == true ? AppColors.danger : AppColors.muted),
                const SizedBox(width: 6),
                Expanded(child: Text(asText(item['title']), maxLines: 1, overflow: TextOverflow.ellipsis)),
                if (item['due_at'] != null) Text(date(item['due_at']), style: TextStyle(color: AppColors.muted, fontSize: 12)),
              ]),
            ),
        ],
        if (confused.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AppColors.soft(AppColors.warning), borderRadius: BorderRadius.circular(AppRadius.control)),
            child: Text('${tr('«Tushunmadim» deb belgilangan darslar')}: ${confused.join(', ')}', style: const TextStyle(fontSize: 13)),
          ),
        ],
        if (live.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Row(children: <Widget>[
            const Icon(Icons.videocam_outlined, size: 18, color: AppColors.danger),
            const SizedBox(width: 6),
            Expanded(child: Text(tr('Jonli dars: {0} · {1}', <Object?>[asText(live['title']), dateTime(live['starts_at'])]))),
          ]),
        ],
      ]),
    );
  }
}
