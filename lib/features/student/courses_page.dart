// Onlayn kurslar: kurslar ro'yxati, bo'limlar va darslar, dars matni, video, materiallar, uy vazifasi.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'assignments_page.dart';

class CoursesPage extends StatelessWidget {
  const CoursesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final api = AppScope.of(context).api;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Kurslarim'))),
      body: AsyncView<List<Map<String, dynamic>>>(
        load: () async => asList(asMap(await api.get('lms/my/courses'))['courses'], 'courses'),
        builder: (context, courses, reload) {
          if (courses.isEmpty) {
            return ListView(children: <Widget>[
              EmptyState(text: tr("Sizga hali kurs ochilmagan. O'qituvchi kurs e'lon qilganda shu yerda ko'rinadi.")),
            ]);
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: courses.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final course = courses[index];
              final progress = asMap(course['progress']);
              final locked = course['has_access'] == false;
              return AppCard(
                onTap: () async {
                  await Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => CoursePage(courseId: asInt(course['id']), title: asText(course['title'])),
                  ));
                  await reload();
                },
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  Row(children: <Widget>[
                    Expanded(child: Text(asText(course['title']), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
                    if (locked) Icon(Icons.lock_outline, color: AppColors.muted, size: 20),
                  ]),
                  if (asMap(course['subject'])['name'] != null)
                    Text(asText(asMap(course['subject'])['name']), style: TextStyle(color: AppColors.muted)),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(value: asDouble(progress['percent']) / 100, minHeight: 8),
                  ),
                  const SizedBox(height: 4),
                  Text('${asInt(progress['done'])} / ${asInt(progress['total'])} ${tr('dars')}',
                      style: TextStyle(color: AppColors.muted, fontSize: 12)),
                ]),
              );
            },
          );
        },
      ),
    );
  }
}

class CoursePage extends StatelessWidget {
  const CoursePage({super.key, required this.courseId, required this.title});

  final int courseId;
  final String title;

  @override
  Widget build(BuildContext context) {
    final api = AppScope.of(context).api;
    return Scaffold(
      appBar: AppBar(title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: AsyncView<Map<String, dynamic>>(
        load: () async => asMap(await api.get('lms/my/courses/$courseId')),
        builder: (context, data, reload) {
          final course = asMap(data['course']);
          final sections = asList(data['sections'], 'sections');
          final locked = data['has_access'] == false;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              if (asText(course['description']).isNotEmpty) ...<Widget>[
                Text(asText(course['description']), style: TextStyle(color: AppColors.muted)),
                const SizedBox(height: 12),
              ],
              if (locked)
                AppCard(
                  color: AppColors.soft(AppColors.warning),
                  child: Text(tr("Kursni ochish uchun to'lovni tashkilot ma'muriyatiga topshiring: ular sizga ruxsat beradi.")),
                ),
              for (final section in sections) ...<Widget>[
                SectionTitle(asText(section['title'])),
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(children: <Widget>[
                    for (final lesson in asList(section['lessons'], 'lessons'))
                      ListTile(
                        enabled: !locked,
                        leading: Icon(
                          lesson['completed'] == true ? Icons.check_circle : Icons.radio_button_unchecked,
                          color: lesson['completed'] == true ? AppColors.success : AppColors.muted,
                        ),
                        title: Text(asText(lesson['title'])),
                        subtitle: Text(<String>[
                          if (lesson['has_video'] == true) tr('video'),
                          if (asInt(lesson['materials_count']) > 0) tr('{0} ta fayl', <Object?>[asInt(lesson['materials_count'])]),
                          if (asInt(lesson['assignments_count']) > 0) tr('uy vazifasi'),
                          if (lesson['has_exam'] == true) tr('test'),
                        ].join(' · ')),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          await Navigator.of(context).push(MaterialPageRoute<void>(
                            builder: (_) => LessonPage(lessonId: asInt(lesson['id'])),
                          ));
                          await reload();
                        },
                      ),
                  ]),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class LessonPage extends StatefulWidget {
  const LessonPage({super.key, required this.lessonId});

  final int lessonId;

  @override
  State<LessonPage> createState() => _LessonPageState();
}

class _LessonPageState extends State<LessonPage> {
  final GlobalKey<AsyncViewState<Map<String, dynamic>>> _view = GlobalKey<AsyncViewState<Map<String, dynamic>>>();
  int? _opening;

  Future<void> _toggleComplete(Map<String, dynamic> lesson) async {
    final api = AppScope.read(context).api;
    try {
      if (lesson['completed_at'] == null) {
        await api.post('lms/my/lessons/${widget.lessonId}/complete');
        if (mounted) showMessage(context, tr('Dars tugatilgan deb belgilandi.'));
      } else {
        await api.delete('lms/my/lessons/${widget.lessonId}/complete');
      }
      _view.currentState?.reload();
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    }
  }

  Future<void> _openMaterial(Map<String, dynamic> material) async {
    final api = AppScope.read(context).api;
    final id = asInt(material['id']);
    setState(() => _opening = id);
    try {
      final bytes = await api.bytes(material['can_download'] == true ? 'lms/materials/$id/download' : 'lms/materials/$id/view');
      final dir = await getTemporaryDirectory();
      final name = asText(material['original_name'], 'material.${asText(material['extension'], 'pdf')}');
      final file = File('${dir.path}/$id-$name');
      await file.writeAsBytes(bytes, flush: true);
      final result = await OpenFilex.open(file.path);
      if (result.type != ResultType.done && mounted) {
        showMessage(context, tr("Bu turdagi fayl ilova ichida ochilmaydi."), error: true);
      }
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = AppScope.of(context).api;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Dars'))),
      body: AsyncView<Map<String, dynamic>>(
        key: _view,
        load: () async => asMap(await api.get('lms/my/lessons/${widget.lessonId}')),
        builder: (context, lesson, reload) {
          final materials = asList(lesson['materials'], 'materials');
          final assignments = asList(lesson['assignments'], 'assignments');
          final video = asText(lesson['video_url']);
          final done = lesson['completed_at'] != null;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: <Widget>[
              Text(asText(asMap(lesson['section'])['title']), style: TextStyle(color: AppColors.muted)),
              const SizedBox(height: 4),
              Text(asText(lesson['title']), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              if (video.isNotEmpty) ...<Widget>[
                AppCard(
                  onTap: () => launchUrl(Uri.parse(video), mode: LaunchMode.externalApplication),
                  child: Row(children: <Widget>[
                    const Icon(Icons.play_circle_fill, color: AppColors.danger, size: 40),
                    const SizedBox(width: 12),
                    Expanded(child: Text(tr('Videoni ochish'), style: const TextStyle(fontWeight: FontWeight.w700))),
                    Icon(Icons.open_in_new, color: AppColors.muted),
                  ]),
                ),
                const SizedBox(height: 12),
              ],
              if (asText(lesson['content']).isNotEmpty)
                AppCard(child: MathText(asText(lesson['content']), style: TextStyle(fontSize: 16, height: 1.5, color: AppColors.ink))),
              if (materials.isNotEmpty) ...<Widget>[
                SectionTitle(tr('Materiallar')),
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(children: <Widget>[
                    for (final material in materials)
                      ListTile(
                        leading: Icon(Icons.insert_drive_file_outlined, color: AppColors.brand),
                        title: Text(asText(material['title'])),
                        subtitle: Text(asText(material['original_name'])),
                        trailing: _opening == asInt(material['id'])
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.open_in_new),
                        onTap: material['viewable'] == true || material['can_download'] == true ? () => _openMaterial(material) : null,
                      ),
                  ]),
                ),
              ],
              if (assignments.isNotEmpty) ...<Widget>[
                SectionTitle(tr('Uy vazifasi')),
                for (final assignment in assignments) ...<Widget>[
                  AssignmentCard(assignment: assignment, onChanged: reload),
                  const SizedBox(height: 10),
                ],
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => _toggleComplete(lesson),
                style: done ? FilledButton.styleFrom(backgroundColor: AppColors.success) : null,
                icon: Icon(done ? Icons.check_circle : Icons.check),
                label: Text(done ? tr('Dars tugatilgan') : tr('Darsni tugatdim')),
              ),
              if (done && lesson['completed_at'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(dateTime(lesson['completed_at']), textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 12)),
                ),
            ],
          );
        },
      ),
    );
  }
}
