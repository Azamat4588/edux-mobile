// Olimpiada sahifasi: ma'lumot, ro'yxatdan o'tish, badal to'lovi, testni boshlash (ilovadagi test oynasi),
// natija va sertifikat, e'lonlar va reyting. Ma'lumot: GET /public/olympiads/{token} (kirgan foydalanuvchi uchun «me»).
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/payments.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../student/my_tests_page.dart';
import 'olympiad_store.dart';
import 'olympiads_page.dart';

class OlympiadPage extends StatefulWidget {
  const OlympiadPage({super.key, required this.token});

  final String token;

  @override
  State<OlympiadPage> createState() => _OlympiadPageState();
}

class _OlympiadPageState extends State<OlympiadPage> {
  final GlobalKey<AsyncViewState<Map<String, dynamic>>> _view = GlobalKey<AsyncViewState<Map<String, dynamic>>>();
  bool _busy = false;

  Future<Map<String, dynamic>> _load(Session session) async {
    final data = await OlympiadStore.fetch(session, widget.token);
    // Ishtirokchi bo'lsa — «Olimpiadalarim» ro'yxatida saqlanadi.
    if (data['me'] is Map) await OlympiadStore.remember(session, widget.token);
    return data;
  }

  Future<void> _reload() async => _view.currentState?.reload();

  Future<void> _register(Map<String, dynamic> data) async {
    final viewer = asMap(data['viewer']);
    Map<String, Object?> body = <String, Object?>{};
    if (viewer['internal'] != true) {
      final form = await showModalBottomSheet<Map<String, Object?>>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
        builder: (context) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: _RegisterForm(name: AppScope.read(context).userName, phone: asText(AppScope.read(context).user['phone'])),
        ),
      );
      if (form == null) return;
      body = form;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final session = AppScope.read(context);
      final result = asMap(await session.api.post('public/olympiads/${widget.token}/register', body));
      await OlympiadStore.rememberParticipant(session, widget.token, asText(result['token']));
      await OlympiadStore.remember(session, widget.token);
      if (!mounted) return;
      showMessage(
        context,
        asText(result['status']) == 'pending_payment'
            ? tr("Ro'yxatdan o'tdingiz. Qatnashish uchun badalni to'lang.")
            : tr("Ro'yxatdan o'tdingiz. Olimpiada boshlanganda shu sahifadan kirasiz."),
      );
      await _reload();
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pay(String participant, String provider) async {
    setState(() => _busy = true);
    try {
      final data = asMap(await AppScope.read(context).api.post('public/olympiads/${widget.token}/pay', <String, Object?>{
        'p': participant,
        'provider': provider,
      }));
      final url = Uri.tryParse(asText(data['url']));
      if (url == null) throw ApiException(500, tr("To'lov sahifasini ochib bo'lmadi. Qayta urinib ko'ring."));
      await launchUrl(url, mode: LaunchMode.externalApplication);
      if (mounted) showMessage(context, tr("To'lovdan keyin sahifani pastga tortib yangilang."));
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Olimpiada testi: o'z o'quvchimiz bo'lsa — ilovadagi test oynasi; tashqi ishtirokchi — brauzerdagi shaxsiy havola.
  Future<void> _start(Map<String, dynamic> data) async {
    final olympiad = asMap(data['olympiad']);
    final me = asMap(data['me']);
    final startUrl = asText(me['start_url']);
    final examId = int.tryParse(RegExp(r'/my/exams/(\d+)').firstMatch(startUrl)?.group(1) ?? '');
    if (me['internal'] == true && examId != null) {
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => TakeTestPage(examId: examId, title: asText(olympiad['title'])),
      ));
      await _reload();
      return;
    }
    if (startUrl.isEmpty) {
      showMessage(context, tr("Test havolasi hali tayyor emas. Olimpiada boshlanganda qayta urinib ko'ring."), error: true);
      return;
    }
    await launchUrl(Uri.parse(AppScope.read(context).api.absolute(startUrl)), mode: LaunchMode.externalApplication);
  }

  /// Topshirilgan olimpiada testining tahlili: my/exams ichidan shu test urinishi topiladi.
  Future<void> _review(Map<String, dynamic> data) async {
    final startUrl = asText(asMap(data['me'])['start_url']);
    final examId = int.tryParse(RegExp(r'/my/exams/(\d+)').firstMatch(startUrl)?.group(1) ?? '');
    if (examId == null) return;
    setState(() => _busy = true);
    try {
      final exams = asList(asMap(await AppScope.read(context).api.get('my/exams'))['exams'], 'exams');
      final exam = exams.firstWhere((item) => asInt(item['id']) == examId, orElse: () => <String, dynamic>{});
      final attemptId = asInt(asMap(exam['attempt'])['id']);
      if (!mounted) return;
      if (attemptId == 0) {
        showMessage(context, tr('Natija tahlili hozircha ochiq emas.'), error: true);
        return;
      }
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AttemptResultPage(attemptId: attemptId)));
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Olimpiada'))),
      body: AsyncView<Map<String, dynamic>>(
        key: _view,
        load: () => _load(session),
        builder: (context, data, reload) {
          final olympiad = asMap(data['olympiad']);
          final organization = asMap(data['organization']);
          final announcements = asList(data['announcements'], 'announcements');
          final leaderboard = asList(data['leaderboard'], 'leaderboard');
          final stage = asText(olympiad['stage']);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(gradient: AppColors.gradient, borderRadius: BorderRadius.circular(18)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  Text(asText(organization['name']), style: const TextStyle(color: Colors.white70)),
                  const SizedBox(height: 4),
                  Text(asText(olympiad['title']),
                      style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                  if (olympiad['subject'] != null || olympiad['grades'] != null) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(<String>[
                      if (olympiad['subject'] != null) asText(olympiad['subject']),
                      if (olympiad['grades'] != null) tr('{0}-sinflar', <Object?>[asText(olympiad['grades'])]),
                    ].join(' · '), style: const TextStyle(color: Colors.white)),
                  ],
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: Colors.white.withAlpha(46), borderRadius: BorderRadius.circular(99)),
                    child: Text(tr(olympiadStageLabels[stage] ?? stage),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12.5)),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
              AppCard(
                child: Column(children: <Widget>[
                  if (olympiad['starts_at'] != null) KeyValue(tr('Boshlanishi'), dateTime(olympiad['starts_at'])),
                  if (olympiad['ends_at'] != null) KeyValue(tr('Tugashi'), dateTime(olympiad['ends_at'])),
                  if (olympiad['registration_closes_at'] != null)
                    KeyValue(tr("Ro'yxat yopiladi"), dateTime(olympiad['registration_closes_at'])),
                  if (olympiad['duration_minutes'] != null)
                    KeyValue(tr('Davomiyligi'), tr('{0} daqiqa', <Object?>[asInt(olympiad['duration_minutes'])])),
                  if (asInt(olympiad['questions']) > 0) KeyValue(tr('Savollar'), '${asInt(olympiad['questions'])}'),
                  KeyValue(tr('Ishtirokchilar'), '${asInt(olympiad['participants'])}'),
                  KeyValue(tr('Ishtirok badali'), asInt(olympiad['price']) > 0 ? money(asInt(olympiad['price'])) : tr('Bepul')),
                ]),
              ),
              const SizedBox(height: 12),
              _MeCard(
                data: data,
                busy: _busy,
                onRegister: () => _register(data),
                onPay: _pay,
                onStart: () => _start(data),
                onReview: () => _review(data),
              ),
              if (asText(olympiad['description']).isNotEmpty) ...<Widget>[
                SectionTitle(tr('Olimpiada haqida')),
                AppCard(child: MathText(asText(olympiad['description']))),
              ],
              if (asText(olympiad['rules']).isNotEmpty) ...<Widget>[
                SectionTitle(tr('Qoidalar')),
                AppCard(child: MathText(asText(olympiad['rules']))),
              ],
              if (announcements.isNotEmpty) ...<Widget>[
                SectionTitle(tr("E'lonlar")),
                for (final item in announcements) ...<Widget>[
                  AppCard(
                    color: asText(item['kind']) == 'urgent' ? AppColors.soft(AppColors.warning) : null,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                      Text(asText(item['body'])),
                      const SizedBox(height: 6),
                      Text(dateTime(item['created_at']), style: TextStyle(color: AppColors.muted, fontSize: 12)),
                    ]),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
              if (leaderboard.isNotEmpty) ...<Widget>[
                SectionTitle(tr('Reyting')),
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(children: <Widget>[
                    for (var i = 0; i < leaderboard.length; i++) ...<Widget>[
                      if (i > 0) const Divider(),
                      ListTile(
                        dense: true,
                        leading: _RankBadge(rank: asInt(leaderboard[i]['rank'])),
                        title: Text(asText(leaderboard[i]['name']), style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(<String>[asText(leaderboard[i]['school']), asText(leaderboard[i]['region'])]
                            .where((item) => item.isNotEmpty)
                            .join(' · ')),
                        trailing: Text('${number(asDouble(leaderboard[i]['score']))} / ${number(asDouble(leaderboard[i]['max_score']))}',
                            style: const TextStyle(fontWeight: FontWeight.w800)),
                      ),
                    ],
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

class _MeCard extends StatelessWidget {
  const _MeCard({
    required this.data,
    required this.busy,
    required this.onRegister,
    required this.onPay,
    required this.onStart,
    required this.onReview,
  });

  final Map<String, dynamic> data;
  final bool busy;
  final VoidCallback onRegister;
  final void Function(String participant, String provider) onPay;
  final VoidCallback onStart;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final olympiad = asMap(data['olympiad']);
    final me = asMap(data['me']);
    final stage = asText(olympiad['stage']);
    if (me.isEmpty) {
      final open = olympiad['registration_open'] == true;
      return AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          Text(open ? tr("Siz hali ro'yxatdan o'tmagansiz.") : tr("Ro'yxatdan o'tish yopilgan."),
              style: const TextStyle(fontWeight: FontWeight.w700)),
          if (open) ...<Widget>[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: busy ? null : onRegister,
              icon: const Icon(Icons.how_to_reg_rounded),
              label: Text(tr("Ro'yxatdan o'tish")),
            ),
          ],
        ]),
      );
    }
    final status = asText(me['status']);
    final examStatus = asText(me['exam_status']);
    final result = asMap(me['result']);
    final providers = asMap(data['providers']);
    final certificate = asText(result['certificate_url']);
    final telegram = asText(me['telegram_link']);
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        Row(children: <Widget>[
          Avatar(asText(me['full_name']), size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text(asText(me['full_name']), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              Text(<String>[
                if (me['number'] != null) tr('Ishtirokchi №{0}', <Object?>[asText(me['number'])]),
                if (me['school'] != null) asText(me['school']),
              ].join(' · '), style: TextStyle(color: AppColors.muted, fontSize: 13)),
            ]),
          ),
          Pill(status == 'pending_payment' ? tr("Badal to'lanmagan") : tr("Ro'yxatdan o'tgan"),
              color: status == 'pending_payment' ? AppColors.danger : AppColors.success),
        ]),
        if (result.isNotEmpty) ...<Widget>[
          const Divider(height: 24),
          Row(children: <Widget>[
            Expanded(
              child: _Metric(
                label: tr("O'rin"),
                value: result['rank'] == null ? '—' : '${asInt(result['rank'])} / ${asInt(result['total'])}',
                color: AppColors.sun,
              ),
            ),
            Expanded(
              child: _Metric(
                label: tr('Ball'),
                value: result['score'] == null ? '—' : '${number(asDouble(result['score']))} / ${number(asDouble(result['max_score']))}',
                color: AppColors.brand,
              ),
            ),
          ]),
          if (certificate.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => launchUrl(Uri.parse(AppScope.read(context).api.absolute(certificate)), mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.workspace_premium_rounded),
              label: Text(tr('Sertifikatni ochish')),
            ),
          ],
        ],
        if (status == 'pending_payment') ...<Widget>[
          const SizedBox(height: 12),
          Text(tr("Olimpiadada qatnashish uchun badalni to'lang: {0}", <Object?>[money(asInt(olympiad['price']))]),
              style: TextStyle(color: AppColors.muted)),
          const SizedBox(height: 10),
          for (final provider in readyProviders(providers, withP2p: false)) ...<Widget>[
            FilledButton(
              onPressed: busy ? null : () => onPay(asText(me['token']), provider),
              child: Text(tr("{0} orqali to'lash", <Object?>[providerNames[provider] ?? provider])),
            ),
            const SizedBox(height: 8),
          ],
          if (readyProviders(providers, withP2p: false).isEmpty)
            Text(tr("Onlayn to'lov yoqilmagan. Badalni markaz ma'muriyatiga topshiring."), style: TextStyle(color: AppColors.danger)),
        ] else if (result.isEmpty) ...<Widget>[
          const SizedBox(height: 12),
          if (examStatus == 'finished') ...<Widget>[
            Text(tr("Siz testni topshirdingiz. Natijalar e'lon qilinganda shu yerda ko'rinadi."), style: TextStyle(color: AppColors.muted)),
            if (me['internal'] == true) ...<Widget>[
              const SizedBox(height: 10),
              OutlinedButton.icon(onPressed: busy ? null : onReview, icon: const Icon(Icons.fact_check_outlined), label: Text(tr('Javoblarim'))),
            ],
          ] else if (stage == 'running')
            FilledButton.icon(
              onPressed: busy ? null : onStart,
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(examStatus == 'in_progress' ? tr('Davom ettirish') : tr('Olimpiadani boshlash')),
            )
          else if (stage == 'registration' || stage == 'waiting')
            Text(
              olympiad['starts_at'] != null
                  ? tr('Olimpiada {0} da boshlanadi. Shu sahifadan kirasiz.', <Object?>[dateTime(olympiad['starts_at'])])
                  : tr('Olimpiada boshlanganda shu sahifadan kirasiz.'),
              style: TextStyle(color: AppColors.muted),
            )
          else
            Text(tr("Olimpiada yakunlandi. Natijalar e'lon qilinishini kuting."), style: TextStyle(color: AppColors.muted)),
        ],
        if (telegram.isNotEmpty && me['telegram_linked'] != true) ...<Widget>[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => launchUrl(Uri.parse(telegram), mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.send_rounded, color: Color(0xFF229ED9)),
            label: Text(tr('Telegramda xabarlarni olish')),
          ),
        ],
      ]),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(children: <Widget>[
      Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
      Text(label, style: TextStyle(color: AppColors.muted, fontSize: 12)),
    ]);
  }
}

class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank});

  final int rank;

  @override
  Widget build(BuildContext context) {
    final color = rank == 1
        ? AppColors.sun
        : rank == 2
            ? const Color(0xFF94A3B8)
            : rank == 3
                ? const Color(0xFFB45309)
                : AppColors.muted;
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color.withAlpha(36), shape: BoxShape.circle),
      child: Text('$rank', style: TextStyle(fontWeight: FontWeight.w800, color: color)),
    );
  }
}

/// Tashqi ishtirokchi (boshqa markaz o'quvchisi) uchun ro'yxatdan o'tish formasi.
class _RegisterForm extends StatefulWidget {
  const _RegisterForm({required this.name, required this.phone});

  final String name;
  final String phone;

  @override
  State<_RegisterForm> createState() => _RegisterFormState();
}

class _RegisterFormState extends State<_RegisterForm> {
  late final TextEditingController _name = TextEditingController(text: widget.name);
  late final TextEditingController _phone = TextEditingController(text: widget.phone);
  final _school = TextEditingController();
  final _grade = TextEditingController();
  final _region = TextEditingController();
  String? _error;

  @override
  void dispose() {
    for (final controller in <TextEditingController>[_name, _phone, _school, _grade, _region]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _submit() {
    if (_name.text.trim().length < 3 || _phone.text.replaceAll(RegExp(r'\D'), '').length < 9) {
      setState(() => _error = tr("Ism-familiya va telefon raqamini to'liq kiriting."));
      return;
    }
    Navigator.pop(context, <String, Object?>{
      'full_name': _name.text.trim(),
      'phone': _phone.text.trim(),
      'school': _school.text.trim(),
      'grade': _grade.text.trim(),
      'region': _region.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        Text(tr("Ro'yxatdan o'tish"), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 14),
        if (_error != null) ...<Widget>[
          Text(_error!, style: TextStyle(color: AppColors.danger)),
          const SizedBox(height: 8),
        ],
        TextField(controller: _name, decoration: InputDecoration(labelText: tr('Ism-familiya'))),
        const SizedBox(height: 10),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(labelText: tr('Telefon raqam'), hintText: '+998 90 123 45 67'),
        ),
        const SizedBox(height: 10),
        TextField(controller: _school, decoration: InputDecoration(labelText: tr('Maktab (ixtiyoriy)'))),
        const SizedBox(height: 10),
        Row(children: <Widget>[
          Expanded(child: TextField(controller: _grade, decoration: InputDecoration(labelText: tr('Sinf (ixtiyoriy)')))),
          const SizedBox(width: 10),
          Expanded(child: TextField(controller: _region, decoration: InputDecoration(labelText: tr('Hudud (ixtiyoriy)')))),
        ]),
        const SizedBox(height: 18),
        FilledButton(onPressed: _submit, child: Text(tr("Ro'yxatdan o'tish"))),
      ]),
    );
  }
}
