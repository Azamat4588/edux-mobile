// Faol qurilmalar (3.11, server 1.45): hisobga kirilgan telefon, kompyuter va brauzerlar — bittasini yoki joriydan
// boshqa hammasini yopish. API: GET profile/sessions, DELETE profile/sessions/{id}, POST profile/sessions/logout-others.
import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

/// Kirish turi belgisi (server `client`: web, android, ios, app, desktop, telegram).
IconData sessionIcon(String client) {
  switch (client) {
    case 'android':
    case 'ios':
    case 'app':
      return Icons.smartphone_outlined;
    case 'desktop':
      return Icons.laptop_outlined;
    case 'telegram':
      return Icons.send_outlined;
  }
  return Icons.language_outlined;
}

/// «hozir», «12 daqiqa oldin», «bugun 14:05» yoki to'liq sana.
String sessionWhen(Object? value) {
  final date = parseDate(value)?.toLocal();
  if (date == null) return '—';
  final now = DateTime.now();
  final minutes = now.difference(date).inMinutes;
  if (minutes < 2) return tr('hozir');
  if (minutes < 60) return tr('{0} daqiqa oldin', <Object?>[minutes]);
  if (date.year == now.year && date.month == now.month && date.day == now.day) {
    return tr('bugun {0}', <Object?>['${two(date.hour)}:${two(date.minute)}']);
  }
  return dateTime(value);
}

/// Bitta kirish qatori (o'z ro'yxati va platforma ro'yxati uchun umumiy).
class SessionTile extends StatelessWidget {
  const SessionTile({super.key, required this.item, this.title, this.trailing});

  final Map<String, dynamic> item;
  final String? title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final details = <String>[
      asText(item['client_label']),
      if (title != null) asText(item['device']),
      if (asText(item['app_version']).isNotEmpty) 'v${asText(item['app_version'])}',
      if (asText(item['ip']).isNotEmpty) asText(item['ip']),
    ].where((part) => part.isNotEmpty).join(', ');
    return ListTile(
      leading: Icon(sessionIcon(asText(item['client'])), color: AppColors.muted),
      title: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: <Widget>[
        Text(title ?? asText(item['device']), style: const TextStyle(fontWeight: FontWeight.w600)),
        if (item['current'] == true)
          Pill(tr('Shu qurilma'), color: AppColors.success)
        else if (item['online'] == true)
          Pill(tr('Hozir onlayn'), color: AppColors.info),
      ]),
      subtitle: Text('$details — ${sessionWhen(item['last_used_at'])}', style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
      trailing: trailing,
    );
  }
}

class SessionsPage extends StatefulWidget {
  const SessionsPage({super.key});

  @override
  State<SessionsPage> createState() => _SessionsPageState();
}

class _SessionsPageState extends State<SessionsPage> {
  final GlobalKey<AsyncViewState<Map<String, dynamic>>> _view = GlobalKey<AsyncViewState<Map<String, dynamic>>>();
  bool _busy = false;

  Future<Map<String, dynamic>> _load() async => asMap(await AppScope.read(context).api.get('profile/sessions'));

  Future<void> _close(Map<String, dynamic> item) async {
    final session = AppScope.read(context);
    if (item['current'] == true) {
      if (await confirm(context, tr('Shu qurilmadan chiqasizmi?'), action: tr('Chiqish'), danger: true)) await session.signOut();
      return;
    }
    await _run(() async {
      await session.api.delete('profile/sessions/${asInt(item['id'])}');
      return tr('Qurilmadan chiqildi.');
    });
  }

  Future<void> _closeOthers() async {
    if (!await confirm(context, tr("Boshqa hamma qurilmalardan chiqilsinmi? SMS shlyuz telefonlari ham qayta kirishi kerak bo'ladi."), danger: true)) return;
    if (!mounted) return;
    final api = AppScope.read(context).api;
    await _run(() async => asText(asMap(await api.post('profile/sessions/logout-others'))['message']));
  }

  Future<void> _run(Future<String> Function() action) async {
    setState(() => _busy = true);
    try {
      final message = await action();
      if (mounted && message.isNotEmpty) showMessage(context, message);
      await _view.currentState?.reload();
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: pageBar(context, title: Text(tr('Faol qurilmalar'))),
      body: AsyncView<Map<String, dynamic>>(
        key: _view,
        load: _load,
        builder: (context, data, reload) {
          final items = asList(data['data']);
          final policy = asMap(data['policy']);
          final limit = asInt(data['limit']);
          final others = items.where((item) => item['current'] != true).length;
          return ListView(padding: const EdgeInsets.all(16), children: <Widget>[
            Text(tr('Hisobingizga kirilgan telefon, kompyuter va brauzerlar. Tanimagan qurilmani yoping va parolni almashtiring.'),
                style: TextStyle(color: AppColors.muted)),
            const SizedBox(height: 6),
            Text(
              <String>[
                limit > 0 ? tr("Ko'pi bilan {0} ta qurilma.", <Object?>[limit]) : tr('Qurilmalar soni cheklanmagan.'),
                tr('Brauzerda {0} kun, ilovada {1} kun amal qiladi.', <Object?>[asInt(policy['session_days']), asInt(policy['app_session_days'])]),
                if (asInt(policy['idle_hours']) > 0) tr('{0} soat foydalanilmasa yopiladi.', <Object?>[asInt(policy['idle_hours'])]),
              ].join(' '),
              style: TextStyle(color: AppColors.muted, fontSize: 12.5),
            ),
            const SizedBox(height: 14),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(children: <Widget>[
                for (final item in items)
                  SessionTile(
                    item: item,
                    trailing: TextButton(
                      onPressed: _busy ? null : () => _close(item),
                      child: Text(item['current'] == true ? tr('Chiqish') : tr('Yopish')),
                    ),
                  ),
              ]),
            ),
            if (others > 0) ...<Widget>[
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _busy ? null : _closeOthers,
                icon: const Icon(Icons.logout),
                label: Text(tr('Boshqa qurilmalardan chiqish')),
              ),
            ],
          ]);
        },
      ),
    );
  }
}
