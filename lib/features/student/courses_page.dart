// Onlayn kurslar: kurslar ro'yxati, bo'limlar va darslar, kurs e'lonlari, pullik kursni sotib olish.
// Dars sahifasi (3.4, backend 1.35): bloklar konstruktor tartibida (matn, video, fayl, doska, test, uy vazifasi,
// interaktiv blok), jonli dars kartasi, savol-javob va dars oxiridagi «tushundim» so'rovi.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/adaptive.dart';
import '../../core/api.dart';
import '../../core/file_open.dart';
import '../../core/format.dart';
import '../../core/help_links.dart';
import '../../core/i18n.dart';
import '../../core/lms.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../core/games.dart';
import '../fun/fun_labels.dart';
import '../fun/play_page.dart';
import '../fun/labs_page.dart';
import '../lms/board_view.dart';
import '../lms/lms_staff_pages.dart';
import 'assignments_page.dart';
import 'my_tests_page.dart';
import 'online_pay.dart';

class CoursesPage extends StatelessWidget {
  const CoursesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final api = AppScope.of(context).api;
    return Scaffold(
      appBar: pageBar(context, title: Text(tr('Kurslarim'))),
      body: AsyncView<List<Map<String, dynamic>>>(
        cacheKey: 'lms_my_courses',
        decode: (raw) => asList(raw),
        load: () async => asList(asMap(await api.get('lms/my/courses'))['courses'], 'courses'),
        builder: (context, courses, reload) {
          if (courses.isEmpty) {
            return ListView(children: <Widget>[
              EmptyState(text: tr("Sizga hali kurs ochilmagan. O'qituvchi kurs e'lon qilganda shu yerda ko'rinadi.")),
            ]);
          }
          return ListView.separated(
            padding: readable(context, const EdgeInsets.all(16)),
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
      appBar: pageBar(context, title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: AsyncView<Map<String, dynamic>>(
        cacheKey: 'lms_my_course_$courseId',
        decode: asMap,
        load: () async => asMap(await api.get('lms/my/courses/$courseId')),
        builder: (context, data, reload) {
          final course = asMap(data['course']);
          final sections = asList(data['sections'], 'sections');
          final announcements = asList(data['announcements'], 'announcements');
          final locked = data['has_access'] == false;
          final price = asInt(course['price']);
          final monthly = asText(course['billing']) == 'monthly';
          final subscription = asMap(data['subscription']);
          final daysLeft = subscription['days_left'] == null ? null : asInt(subscription['days_left']);
          return ListView(
            padding: readable(context, const EdgeInsets.all(16)),
            children: <Widget>[
              if (asText(course['description']).isNotEmpty) ...<Widget>[
                Text(asText(course['description']), style: TextStyle(color: AppColors.muted)),
                const SizedBox(height: 12),
              ],
              if (locked || (monthly && daysLeft != null && daysLeft <= 7 && subscription['permanent'] != true))
                _BuyCard(courseId: courseId, price: price, monthly: monthly, locked: locked, daysLeft: daysLeft, onPaid: reload),
              if (announcements.isNotEmpty) ...<Widget>[
                SectionTitle(tr("E'lonlar")),
                for (final item in announcements.take(3)) ...<Widget>[
                  AppCard(
                    color: AppColors.soft(AppColors.brand),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                      Row(children: <Widget>[
                        Icon(Icons.campaign_outlined, size: 18, color: AppColors.brand),
                        const SizedBox(width: 6),
                        Expanded(child: Text(asText(item['title']), style: const TextStyle(fontWeight: FontWeight.w700))),
                      ]),
                      if (asText(item['body']).isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(asText(item['body']))),
                      const SizedBox(height: 4),
                      Text(<String>[if (asText(item['author']).isNotEmpty) asText(item['author']), dateTime(item['created_at'])].join(', '),
                          style: TextStyle(color: AppColors.muted, fontSize: 12)),
                    ]),
                  ),
                  const SizedBox(height: 8),
                ],
                if (announcements.length > 3)
                  TextButton(
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      useSafeArea: true,
                      builder: (_) => ListView(padding: const EdgeInsets.all(16), children: <Widget>[
                        Text(tr("E'lonlar"), style: AppTheme.title(size: 19)),
                        for (final item in announcements)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(asText(item['title']), style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text(<String>[asText(item['body']), dateTime(item['created_at'])].where((text) => text.isNotEmpty).join('\n')),
                          ),
                      ]),
                    ),
                    child: Text(tr("Barcha e'lonlar ({0})", <Object?>[announcements.length])),
                  ),
              ],
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
                          if (lesson['live_at'] != null) '${tr('Jonli dars')}: ${dateTime(lesson['live_at'])}',
                          if (lesson['has_video'] == true) tr('video'),
                          if (asInt(lesson['materials_count']) > 0) tr('{0} ta fayl', <Object?>[asInt(lesson['materials_count'])]),
                          if (asInt(lesson['assignments_count']) > 0) tr('uy vazifasi'),
                          if (lesson['has_exam'] == true) tr('test'),
                        ].join(', ')),
                        trailing: lesson['live_at'] != null ? Icon(Icons.videocam_outlined, color: AppColors.danger) : const Icon(Icons.chevron_right),
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

/// Pullik kurs: sotib olish yoki obunani uzaytirish (onlayn to'lov yoqilgan bo'lsa).
class _BuyCard extends StatefulWidget {
  const _BuyCard({required this.courseId, required this.price, required this.monthly, required this.locked, required this.daysLeft, required this.onPaid});

  final int courseId;
  final int price;
  final bool monthly;
  final bool locked;
  final int? daysLeft;
  final Future<void> Function() onPaid;

  @override
  State<_BuyCard> createState() => _BuyCardState();
}

class _BuyCardState extends State<_BuyCard> {
  int _months = 1;

  @override
  Widget build(BuildContext context) {
    final canBuy = widget.price > 0;
    return AppCard(
      color: AppColors.soft(AppColors.warning),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Text(
          widget.locked
              ? (canBuy ? tr('Bu kurs pullik. Darslarni ochish uchun kursni sotib oling.') : tr("Kursni ochish uchun to'lovni tashkilot ma'muriyatiga topshiring: ular sizga ruxsat beradi."))
              : tr('Obuna tugashiga {0} kun qoldi.', <Object?>[widget.daysLeft ?? 0]),
        ),
        if (canBuy) ...<Widget>[
          const SizedBox(height: 10),
          if (widget.monthly)
            Wrap(spacing: 8, children: <Widget>[
              for (final months in const <int>[1, 3, 6, 12])
                ChoiceChip(
                  label: Text(tr('{0} oy', <Object?>[months])),
                  selected: _months == months,
                  onSelected: (_) => setState(() => _months = months),
                ),
            ]),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () => startOnlinePayment(
              context,
              courseId: widget.courseId,
              months: widget.monthly ? _months : 1,
              coursePrice: widget.price,
              onDone: (paid) {
                if (paid) widget.onPaid();
              },
            ),
            icon: const Icon(Icons.lock_open),
            label: Text(widget.locked
                ? tr('Sotib olish — {0}', <Object?>[money(widget.price * (widget.monthly ? _months : 1))])
                : tr('Uzaytirish — {0}', <Object?>[money(widget.price * _months)])),
          ),
        ],
      ]),
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
  int? _feedback;
  bool _feedbackTouched = false;

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

  Future<void> _sendFeedback(int value) async {
    setState(() {
      _feedback = value;
      _feedbackTouched = true;
    });
    try {
      await AppScope.read(context).api.post('lms/my/lessons/${widget.lessonId}/feedback', <String, Object?>{'value': value});
      if (mounted) showMessage(context, tr('Rahmat! Javobingiz o\'qituvchiga yetkaziladi.'));
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    }
  }

  Future<void> _openMaterial(Map<String, dynamic> material) async {
    final api = AppScope.read(context).api;
    final id = asInt(material['id']);
    setState(() => _opening = id);
    try {
      final download = material['can_download'] == true;
      final raw = await api.bytes(download ? 'lms/materials/$id/download' : 'lms/materials/$id/view');
      // Himoyalangan ko'rish (`view`) base64 matn qaytaradi (docs/lms.md, 7-bo'lim).
      List<int> bytes = raw;
      if (!download) {
        try {
          bytes = base64Decode(utf8.decode(raw).trim());
        } catch (_) {
          bytes = raw;
        }
      }
      final name = asText(material['original_name'], 'material.${asText(material['extension'], 'pdf')}');
      final opened = await openBytesAsFile(bytes, name, prefix: '$id-');
      if (!opened && mounted) {
        showMessage(context, tr('Bu turdagi fayl ilova ichida ochilmaydi.'), error: true);
      }
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  Widget _block(BuildContext context, LessonBlock block, Map<String, dynamic> lesson, Future<void> Function() reload) {
    switch (block.type) {
      case 'video':
        final url = block.url;
        return AppCard(
          onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
          child: Row(children: <Widget>[
            Icon(Icons.play_circle_fill, color: AppColors.danger, size: 40),
            const SizedBox(width: 12),
            Expanded(child: Text(tr('Videoni ochish'), style: const TextStyle(fontWeight: FontWeight.w700))),
            Icon(Icons.open_in_new, color: AppColors.muted),
          ]),
        );
      case 'content':
        return AppCard(child: MathText(asText(lesson['content']), style: TextStyle(fontSize: 16, height: 1.5, color: AppColors.ink)));
      case 'text':
        return AppCard(child: MathText(block.text, style: TextStyle(fontSize: 16, height: 1.5, color: AppColors.ink)));
      case 'file':
        final material = asList(lesson['materials'], 'materials').firstWhere((item) => asInt(item['id']) == block.ref);
        return AppCard(
          padding: EdgeInsets.zero,
          child: ListTile(
            leading: Icon(Icons.insert_drive_file_outlined, color: AppColors.brand),
            title: Text(asText(material['title'])),
            subtitle: Text(asText(material['original_name'])),
            trailing: _opening == asInt(material['id'])
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.open_in_new),
            onTap: material['viewable'] == true || material['can_download'] == true ? () => _openMaterial(material) : null,
          ),
        );
      case 'assignment':
        final assignment = asList(lesson['assignments'], 'assignments').firstWhere((item) => asInt(item['id']) == block.ref);
        return AssignmentCard(assignment: assignment, onChanged: reload);
      case 'board':
        final board = asList(lesson['boards'], 'boards').firstWhere((item) => asInt(item['id']) == block.ref);
        return BoardPreview(board: board);
      case 'exam':
        final exam = asMap(lesson['exam']);
        final attempt = asMap(exam['attempt']);
        return AppCard(
          child: Row(children: <Widget>[
            Icon(Icons.quiz_outlined, color: AppColors.brand, size: 30),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text(asText(exam['title']), style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(
                  attempt.isNotEmpty
                      ? tr('Natija: {0} / {1}', <Object?>[number(asDouble(attempt['score'])), number(asDouble(attempt['max_score']))])
                      : (exam['open'] == true ? tr('{0} daqiqa', <Object?>[asInt(exam['duration_minutes'])]) : tr('Test hozir yopiq')),
                  style: TextStyle(color: AppColors.muted, fontSize: 13),
                ),
              ]),
            ),
            if (attempt.isNotEmpty)
              TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AttemptResultPage(attemptId: asInt(attempt['id'])))),
                child: Text(tr('Natija')),
              )
            else if (exam['open'] == true)
              FilledButton(
                onPressed: () async {
                  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TakeTestPage(examId: asInt(exam['id']), title: asText(exam['title']))));
                  await reload();
                },
                child: Text(tr('Boshlash')),
              ),
          ]),
        );
      case 'activity':
        return _ActivityBlock(lessonId: widget.lessonId, activity: asMap(lesson['activity']), onDone: reload);
    }
    return const SizedBox();
  }

  @override
  Widget build(BuildContext context) {
    final api = AppScope.of(context).api;
    return Scaffold(
      appBar: pageBar(context, title: Text(tr('Dars')), actions: const <Widget>[HelpButton(HelpLinks.lesson)]),
      body: AsyncView<Map<String, dynamic>>(
        key: _view,
        load: () async => asMap(await api.get('lms/my/lessons/${widget.lessonId}')),
        builder: (context, lesson, reload) {
          final blocks = lessonBlocks(lesson);
          final done = lesson['completed_at'] != null;
          final live = asMap(lesson['live']);
          final qa = asMap(lesson['qa']);
          final feedback = asMap(lesson['feedback']);
          final feedbackValue = _feedbackTouched ? _feedback : (feedback['value'] == null ? null : asInt(feedback['value']));
          return ListView(
            padding: readable(context, const EdgeInsets.fromLTRB(16, 16, 16, 32)),
            children: <Widget>[
              Text(asText(asMap(lesson['section'])['title']), style: TextStyle(color: AppColors.muted)),
              const SizedBox(height: 4),
              Text(asText(lesson['title']), style: AppTheme.title(size: 22)),
              const SizedBox(height: 14),
              if (live.isNotEmpty) ...<Widget>[
                LiveLessonCard(live: live, onRefresh: reload),
                const SizedBox(height: 12),
              ],
              for (final block in blocks) ...<Widget>[
                _block(context, block, lesson, reload),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 4),
              FilledButton.icon(
                onPressed: () => _toggleComplete(lesson),
                style: done ? FilledButton.styleFrom(backgroundColor: AppColors.successFill, foregroundColor: Colors.white) : null,
                icon: Icon(done ? Icons.check_circle : Icons.check),
                label: Text(done ? tr('Dars tugatilgan') : tr('Darsni tugatdim')),
              ),
              if (done && lesson['completed_at'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(dateTime(lesson['completed_at']), textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 12)),
                ),
              if (feedback['enabled'] == true) ...<Widget>[
                SectionTitle(tr('Dars tushunarli bo\'ldimi?')),
                Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
                  for (final value in const <int>[2, 1, 0])
                    ChoiceChip(
                      label: Text(tr(feedbackLabels[value]!)),
                      avatar: Icon(value == 2 ? Icons.sentiment_satisfied_alt : (value == 1 ? Icons.sentiment_neutral : Icons.sentiment_dissatisfied), size: 18),
                      selected: feedbackValue == value,
                      onSelected: (_) => _sendFeedback(value),
                    ),
                ]),
              ],
              if (qa['enabled'] == true) ...<Widget>[
                SectionTitle(tr('Savol-javob')),
                LessonQuestions(lessonId: widget.lessonId, public: qa['public'] == true),
              ],
              if (lesson['previous_lesson_id'] != null || lesson['next_lesson_id'] != null) ...<Widget>[
                const SizedBox(height: 16),
                Row(children: <Widget>[
                  if (lesson['previous_lesson_id'] != null)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => LessonPage(lessonId: asInt(lesson['previous_lesson_id'])))),
                        icon: const Icon(Icons.chevron_left),
                        label: Text(tr('Oldingi')),
                      ),
                    ),
                  if (lesson['previous_lesson_id'] != null && lesson['next_lesson_id'] != null) const SizedBox(width: 8),
                  if (lesson['next_lesson_id'] != null)
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => LessonPage(lessonId: asInt(lesson['next_lesson_id'])))),
                        icon: const Icon(Icons.chevron_right),
                        label: Text(tr('Keyingi dars')),
                      ),
                    ),
                ]),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Jonli dars kartasi: boshlanishiga 15 daqiqa qolganda «Darsga qo'shilish» (Zoom/Meet ... havolasi ilovada ochiladi).
class LiveLessonCard extends StatefulWidget {
  const LiveLessonCard({super.key, required this.live, required this.onRefresh});

  final Map<String, dynamic> live;
  final Future<void> Function() onRefresh;

  @override
  State<LiveLessonCard> createState() => _LiveLessonCardState();
}

class _LiveLessonCardState extends State<LiveLessonCard> {
  Timer? _timer;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    // Har 30 soniyada holat qayta hisoblanadi; vaqt kelib havola yo'q bo'lsa — dars qayta yuklanadi.
    _timer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (!mounted) return;
      final state = liveState(widget.live, DateTime.now());
      if (state == 'open' && asText(widget.live['url']).isEmpty && !_refreshing) {
        _refreshing = true;
        await widget.onRefresh();
        _refreshing = false;
      } else {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final live = widget.live;
    final state = liveState(live, DateTime.now());
    final url = asText(live['url']);
    final provider = liveProviderLabel(asText(live['provider']));
    final color = state == 'open' ? AppColors.danger : (state == 'soon' ? AppColors.brand : AppColors.muted);
    return AppCard(
      color: state == 'open' ? AppColors.soft(AppColors.danger) : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Row(children: <Widget>[
          Icon(Icons.videocam_rounded, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              state == 'open' ? tr('Jonli dars hozir') : (state == 'soon' ? tr('Jonli dars') : tr('Jonli dars tugadi')),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          if (provider.isNotEmpty) Pill(provider, color: color),
        ]),
        const SizedBox(height: 6),
        Text(tr('Boshlanishi: {0} · {1} daqiqa', <Object?>[dateTime(live['starts_at']), asInt(live['minutes'])]), style: TextStyle(color: AppColors.muted)),
        if (state != 'ended') ...<Widget>[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: state == 'open' && url.isNotEmpty ? () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication) : null,
              icon: const Icon(Icons.login),
              label: Text(state == 'open' ? tr("Darsga qo'shilish") : tr('Havola dars boshlanishiga 15 daqiqa qolganda ochiladi')),
            ),
          ),
        ],
      ]),
    );
  }
}

/// Dars bo'yicha savol-javob (o'quvchi): savol yozish, o'z savollari (yoki sozlamaga ko'ra hammasi) va javoblar.
class LessonQuestions extends StatefulWidget {
  const LessonQuestions({super.key, required this.lessonId, required this.public});

  final int lessonId;
  final bool public;

  @override
  State<LessonQuestions> createState() => _LessonQuestionsState();
}

class _LessonQuestionsState extends State<LessonQuestions> {
  final TextEditingController _ask = TextEditingController();
  final GlobalKey<AsyncViewState<List<Map<String, dynamic>>>> _list = GlobalKey<AsyncViewState<List<Map<String, dynamic>>>>();
  bool _busy = false;

  @override
  void dispose() {
    _ask.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _ask.text.trim();
    if (text.length < 2) return;
    setState(() => _busy = true);
    try {
      await AppScope.read(context).api.post('lms/my/lessons/${widget.lessonId}/comments', <String, Object?>{'body': text});
      _ask.clear();
      _list.currentState?.reload();
      if (mounted) showMessage(context, tr("Savolingiz o'qituvchiga yuborildi."));
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _follow(Map<String, dynamic> question) async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr("Qo'shimcha savol")),
        content: TextField(controller: controller, autofocus: true, minLines: 2, maxLines: 5),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Bekor qilish'))),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: Text(tr('Yuborish'))),
        ],
      ),
    );
    controller.dispose();
    if (text == null || text.isEmpty || !mounted) return;
    try {
      await AppScope.read(context).api.post('lms/my/comments/${asInt(question['id'])}', <String, Object?>{'body': text});
      _list.currentState?.reload();
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = AppScope.of(context).api;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      TextField(
        controller: _ask,
        minLines: 1,
        maxLines: 5,
        maxLength: 3000,
        decoration: InputDecoration(
          hintText: tr("Tushunmagan joyingiz bo'yicha savol yozing"),
          suffixIcon: IconButton(
            tooltip: tr('Yuborish'),
            onPressed: _busy ? null : _send,
            icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send),
          ),
        ),
      ),
      AsyncView<List<Map<String, dynamic>>>(
        key: _list,
        refreshable: false,
        skeleton: const SizedBox(height: 40),
        load: () async => asList(asMap(await api.get('lms/my/lessons/${widget.lessonId}/comments'))['questions'], 'questions'),
        builder: (context, questions, reload) {
          if (questions.isEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(widget.public ? tr("Hali savol yo'q.") : tr("Savollaringizni faqat siz va o'qituvchi ko'radi."), style: TextStyle(color: AppColors.muted, fontSize: 13)),
            );
          }
          return Column(children: <Widget>[
            for (final question in questions) ...<Widget>[
              QuestionCard(
                question: question,
                onReply: question['mine'] == true ? () => _follow(question) : null,
                replyLabel: tr("Qo'shimcha yozish"),
              ),
              const SizedBox(height: 8),
            ],
          ]);
        },
      ),
    ]);
  }
}

/// Interaktiv blok: tekshiruv savollari (javoblar serverda tekshiriladi), laboratoriya yoki o'yin.
class _ActivityBlock extends StatefulWidget {
  const _ActivityBlock({required this.lessonId, required this.activity, required this.onDone});

  final int lessonId;
  final Map<String, dynamic> activity;
  final Future<void> Function() onDone;

  @override
  State<_ActivityBlock> createState() => _ActivityBlockState();
}

class _ActivityBlockState extends State<_ActivityBlock> {
  final Map<int, int> _answers = <int, int>{};
  List<bool>? _results;
  bool _busy = false;

  Future<void> _check(int count) async {
    setState(() => _busy = true);
    try {
      final data = asMap(await AppScope.read(context).api.post('lms/my/lessons/${widget.lessonId}/check', <String, Object?>{
        'answers': <int?>[for (var i = 0; i < count; i++) _answers[i]],
      }));
      final results = asRawList(data['results']).map((item) => item == true).toList();
      setState(() => _results = results);
      if (data['all'] == true) {
        if (mounted) showMessage(context, tr("Barcha javoblar to'g'ri! Dars o'tilgan deb belgilandi."));
        await widget.onDone();
      }
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Darsdagi o'yin tugadi: dars o'tilgan deb belgilanadi (veb kabi).
  Future<void> _gameDone() async {
    try {
      await AppScope.read(context).api.post('lms/my/lessons/${widget.lessonId}/complete');
    } on ApiException {
      // Dars allaqachon belgilangan yoki aloqa yo'q — o'yin natijasi baribir saqlangan.
    }
    await widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final activity = widget.activity;
    final type = asText(activity['type']);
    if (type == 'lab') {
      return AppCard(
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => LabWebPage(code: asText(activity['lab']), title: tr('Laboratoriya')))),
        child: Row(children: <Widget>[
          const Icon(Icons.science_outlined, color: Color(0xFF7C3AED), size: 30),
          const SizedBox(width: 12),
          Expanded(child: Text(tr('Virtual laboratoriya ishini bajarish'), style: const TextStyle(fontWeight: FontWeight.w700))),
          Icon(Icons.chevron_right, color: AppColors.muted),
        ]),
      );
    }
    if (type == 'game') {
      final game = asText(activity['game'], 'match');
      return AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Row(children: <Widget>[
            Icon(gameIcon(game), color: AppColors.success, size: 28),
            const SizedBox(width: 10),
            Expanded(child: Text(tr(gameTitleLabels[game] ?? "O'yin"), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
          ]),
          if (gameDescriptionLabels[game] != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(tr(gameDescriptionLabels[game]!), style: TextStyle(color: AppColors.muted, fontSize: 13)),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(tr("«{0}» o'yinini boshlash", <Object?>[tr(gameTitleLabels[game] ?? game)])),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => PlayPage(game: game, lessonId: widget.lessonId, title: tr('Dars'), onFinished: (_) => _gameDone()),
              )),
            ),
          ),
        ]),
      );
    }
    final questions = asList(activity['questions'], 'questions');
    if (questions.isEmpty) return const SizedBox();
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Row(children: <Widget>[
          Icon(Icons.fact_check_outlined, color: AppColors.brand),
          const SizedBox(width: 8),
          Expanded(child: Text(tr("O'zingizni tekshiring"), style: const TextStyle(fontWeight: FontWeight.w700))),
        ]),
        for (var i = 0; i < questions.length; i++) ...<Widget>[
          const SizedBox(height: 12),
          Row(children: <Widget>[
            Expanded(child: MathText('${i + 1}. ${asText(questions[i]['q'])}', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink))),
            if (_results != null && i < _results!.length)
              Icon(_results![i] ? Icons.check_circle : Icons.cancel, color: _results![i] ? AppColors.success : AppColors.danger, size: 20),
          ]),
          for (var j = 0; j < asRawList(questions[i]['options']).length; j++)
            RadioListTile<int>(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: j,
              // ignore: deprecated_member_use
              groupValue: _answers[i],
              title: MathText('${asRawList(questions[i]['options'])[j]}'),
              // ignore: deprecated_member_use
              onChanged: (value) => setState(() {
                if (value != null) _answers[i] = value;
                _results = null;
              }),
            ),
        ],
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _busy || _answers.length < questions.length ? null : () => _check(questions.length),
            child: Text(_busy ? tr('Tekshirilmoqda...') : tr('Tekshirish')),
          ),
        ),
      ]),
    );
  }
}
