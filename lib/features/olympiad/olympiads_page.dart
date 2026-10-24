// Olimpiadalarim (o'quvchi): qatnashgan olimpiadalar, havola orqali qo'shilish.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/adaptive.dart';
import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'olympiad_page.dart';
import 'olympiad_store.dart';

const Map<String, String> olympiadStageLabels = <String, String>{
  'registration': "Ro'yxatdan o'tish ochiq",
  'waiting': 'Boshlanishi kutilmoqda',
  'running': 'Davom etmoqda',
  'finished': 'Yakunlandi',
  'results': "Natijalar e'lon qilindi",
};

Color olympiadStageColor(String stage) {
  switch (stage) {
    case 'registration':
      return AppColors.brand;
    case 'running':
      return AppColors.success;
    case 'results':
      return const Color(0xFF7C3AED);
    case 'waiting':
      return AppColors.warning;
    default:
      return AppColors.muted;
  }
}

class OlympiadsPage extends StatefulWidget {
  const OlympiadsPage({super.key});

  @override
  State<OlympiadsPage> createState() => _OlympiadsPageState();
}

class _OlympiadsPageState extends State<OlympiadsPage> {
  final GlobalKey<AsyncViewState<List<_Item>>> _view = GlobalKey<AsyncViewState<List<_Item>>>();

  Future<List<_Item>> _load(Session session) async {
    final tokens = await OlympiadStore.tokens(session);
    return Future.wait(tokens.map((token) async {
      try {
        return _Item(token, await OlympiadStore.fetch(session, token), null);
      } on ApiException catch (error) {
        return _Item(token, null, error);
      }
    }));
  }

  Future<void> _join() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr("Olimpiadaga qo'shilish")),
        content: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Text(tr("O'qituvchi yoki markaz yuborgan olimpiada havolasini qo'ying (…/o/…)."), style: TextStyle(color: AppColors.muted)),
          const SizedBox(height: 14),
          TextField(
            controller: controller,
            autofocus: true,
            autocorrect: false,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              hintText: 'https://…/o/abc123def456',
              suffixIcon: IconButton(
                tooltip: tr("Qo'yish"),
                icon: const Icon(Icons.content_paste_rounded),
                onPressed: () async {
                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                  if (data?.text != null) controller.text = data!.text!;
                },
              ),
            ),
          ),
        ]),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Bekor qilish'))),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: Text(tr('Ochish'))),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.trim().isEmpty || !mounted) return;
    final token = OlympiadStore.parse(value);
    if (token == null) {
      showMessage(context, tr("Olimpiada havolasi noto'g'ri. To'liq havolani qo'ying."), error: true);
      return;
    }
    await _open(token);
  }

  Future<void> _open(String token) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => OlympiadPage(token: token)));
    _view.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context);
    return Scaffold(
      appBar: pageBar(context, title: Text(tr('Olimpiadalarim'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _join,
        icon: const Icon(Icons.add_link_rounded),
        label: Text(tr("Qo'shilish")),
      ),
      body: AsyncView<List<_Item>>(
        key: _view,
        load: () => _load(session),
        builder: (context, items, reload) {
          if (items.isEmpty) {
            return ListView(children: <Widget>[
              EmptyState(
                icon: Icons.emoji_events_outlined,
                text: tr("Hali olimpiadada qatnashmagansiz. Olimpiada havolasini oching yoki «Qo'shilish» tugmasini bosib havolani qo'ying."),
                action: FilledButton.tonalIcon(onPressed: _join, icon: const Icon(Icons.add_link_rounded), label: Text(tr("Qo'shilish"))),
              ),
            ]);
          }
          return ListView.separated(
            padding: readable(context, const EdgeInsets.fromLTRB(16, 16, 16, 96)),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) => _OlympiadCard(
              item: items[index],
              onTap: () => _open(items[index].token),
              onForget: () async {
                await OlympiadStore.forget(session, items[index].token);
                await reload();
              },
            ),
          );
        },
      ),
    );
  }
}

class _Item {
  const _Item(this.token, this.data, this.error);

  final String token;
  final Map<String, dynamic>? data;
  final ApiException? error;
}

class _OlympiadCard extends StatelessWidget {
  const _OlympiadCard({required this.item, required this.onTap, required this.onForget});

  final _Item item;
  final VoidCallback onTap;
  final VoidCallback onForget;

  @override
  Widget build(BuildContext context) {
    final data = item.data;
    if (data == null) {
      return AppCard(
        child: Row(children: <Widget>[
          Icon(Icons.error_outline, color: AppColors.muted),
          const SizedBox(width: 12),
          Expanded(child: Text(item.error?.message ?? tr("Ma'lumotni yuklab bo'lmadi."), style: TextStyle(color: AppColors.muted))),
          if (item.error != null && item.error!.status == 404)
            IconButton(tooltip: tr("Ro'yxatdan olib tashlash"), onPressed: onForget, icon: const Icon(Icons.delete_outline)),
        ]),
      );
    }
    final olympiad = asMap(data['olympiad']);
    final me = asMap(data['me']);
    final result = asMap(me['result']);
    final stage = asText(olympiad['stage']);
    return AppCard(
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Row(children: <Widget>[
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: AppColors.sun.withAlpha(40), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.emoji_events_rounded, color: AppColors.sun),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text(asText(olympiad['title']), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              Text(<String>[
                if (olympiad['subject'] != null) asText(olympiad['subject']),
                asText(asMap(data['organization'])['name']),
              ].where((item) => item.isNotEmpty).join(', '), style: TextStyle(color: AppColors.muted, fontSize: 13)),
            ]),
          ),
          Icon(Icons.chevron_right, color: AppColors.muted),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 6, children: <Widget>[
          Pill(tr(olympiadStageLabels[stage] ?? stage), color: olympiadStageColor(stage)),
          if (olympiad['starts_at'] != null) Pill(dateTime(olympiad['starts_at']), color: AppColors.muted),
          if (me.isEmpty) Pill(tr("Ro'yxatdan o'tilmagan"), color: AppColors.warning),
          if (asText(me['status']) == 'pending_payment') Pill(tr("Badal to'lanmagan"), color: AppColors.danger),
          if (result['rank'] != null) Pill(tr('{0}-o\'rin', <Object?>[asInt(result['rank'])]), color: AppColors.success),
        ]),
      ]),
    );
  }
}
