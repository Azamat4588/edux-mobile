// Platforma egasi paneli (3.11, server 1.45): bosh sahifa ko'rsatkichlari, tashkilotlar (obunani uzaytirish, to'xtatish,
// xodimni bloklash va qurilmalardan chiqarish), hisoblar (qo'lda to'lovni tasdiqlash), ulanish arizalari, yordam
// so'rovlari va barcha kirishlar (sessiyalar). To'liq tahrir (narxlar, sayt, server) — veb panelda.
// API: platform/stats, platform/organizations[/{id}[/subscription/quick]], platform/invoices[/{id}/confirm],
// platform/requests[/{id}], platform/support[/{id}], platform/sessions, platform/users/{id}/sessions|session-limit.
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../documents/documents_pages.dart';
import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/organization_picker.dart' show roleLabel;
import '../settings/sessions_page.dart';

Api _api(BuildContext context) => AppScope.read(context).api;

Future<void> _push(BuildContext context, Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

/// Obuna holati yorlig'i va rangi (server SubscriptionStatus).
(String, Color) subscriptionStatus(String status, {bool suspended = false}) {
  if (suspended) return (tr("To'xtatilgan"), AppColors.danger);
  switch (status) {
    case 'trial':
      return (tr('Sinov'), AppColors.info);
    case 'active':
      return (tr('Faol'), AppColors.success);
    case 'past_due':
      return (tr("Muddati o'tgan"), AppColors.warning);
    case 'read_only':
      return (tr("Faqat o'qish"), AppColors.danger);
  }
  return (tr("Obuna yo'q"), AppColors.muted);
}

Future<void> _call(BuildContext context, String phone) async {
  if (phone.isEmpty) return;
  final ok = await launchUrl(Uri.parse('tel:$phone'));
  if (!ok && context.mounted) showMessage(context, tr("Qo'ng'iroq ilovasini ochib bo'lmadi."), error: true);
}

/// Bajarib, xabar ko'rsatadi; xato — qizil xabar. Muvaffaqiyatda true.
Future<bool> _act(BuildContext context, Future<String?> Function() action) async {
  try {
    final message = await action();
    if (context.mounted && message != null && message.isNotEmpty) showMessage(context, message);
    return true;
  } on ApiException catch (error) {
    if (context.mounted) showMessage(context, error.message, error: true);
    return false;
  }
}

/// Holat bo'yicha filtr (yorliqlar qatori).
class _Filters extends StatelessWidget {
  const _Filters({required this.options, required this.value, required this.onChanged});

  final List<(String, String)> options;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(children: <Widget>[
        for (final option in options)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(label: Text(option.$2), selected: value == option.$1, onSelected: (_) => onChanged(option.$1)),
          ),
      ]),
    );
  }
}

// ─────────────────────────────── Bosh sahifa ───────────────────────────────

class PlatformDashboardPage extends StatelessWidget {
  const PlatformDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context);
    return Scaffold(
      appBar: pageBar(context, title: Text(tr('Platforma'))),
      body: AsyncView<Map<String, dynamic>>(
        cacheKey: 'platform.stats',
        decode: asMap,
        load: () async => asMap(await _api(context).get('platform/stats')),
        builder: (context, data, reload) {
          final organizations = asMap(data['organizations']);
          final byStatus = asMap(organizations['by_status']);
          final revenue = asMap(data['revenue']);
          final open = asMap(data['open_invoices']);
          final sessions = asMap(data['sessions']);
          return ListView(padding: const EdgeInsets.all(16), children: <Widget>[
            Text(tr('Salom, {0}', <Object?>[session.userName]), style: AppTheme.title(size: 20)),
            const SizedBox(height: 4),
            Text(tr('Platforma holati: tashkilotlar, tushum va kutilayotgan ishlar.'), style: TextStyle(color: AppColors.muted)),
            const SizedBox(height: 14),
            StatGrid(children: <Widget>[
              StatCard(
                label: tr('Tashkilotlar'),
                value: '${asInt(organizations['total'])}',
                hint: tr('Faol: {0}', <Object?>[asInt(organizations['active'])]),
                icon: Icons.domain_outlined,
                color: AppColors.brand,
                onTap: () => _push(context, const PlatformOrganizationsPage()),
              ),
              StatCard(
                label: tr("To'langan obunalar"),
                value: '${asInt(byStatus['active'])}',
                hint: tr('Sinovda: {0}', <Object?>[asInt(byStatus['trial'])]),
                icon: Icons.verified_outlined,
                color: AppColors.success,
                onTap: () => _push(context, const PlatformOrganizationsPage(initialStatus: 'active')),
              ),
              StatCard(
                label: tr("Muddati o'tgan"),
                value: '${asInt(byStatus['past_due']) + asInt(byStatus['read_only'])}',
                icon: Icons.warning_amber_rounded,
                color: AppColors.warning,
                onTap: () => _push(context, const PlatformOrganizationsPage(initialStatus: 'overdue')),
              ),
              StatCard(
                label: tr('Bu oy tushum'),
                value: money(asInt(revenue['this_month'])),
                hint: tr('Jami: {0}', <Object?>[money(asInt(revenue['total']))]),
                icon: Icons.payments_outlined,
                color: AppColors.success,
              ),
              StatCard(
                label: tr("To'lanmagan hisoblar"),
                value: '${asInt(open['count'])}',
                hint: money(asInt(open['amount'])),
                icon: Icons.receipt_long_outlined,
                color: AppColors.info,
                onTap: () => _push(context, const PlatformInvoicesPage()),
              ),
              StatCard(
                label: tr('Yangi arizalar'),
                value: '${asInt(data['requests_new'])}',
                icon: Icons.mark_email_unread_outlined,
                color: AppColors.warning,
                onTap: () => _push(context, const PlatformRequestsPage()),
              ),
              StatCard(
                label: tr("Ochiq yordam so'rovlari"),
                value: '${asInt(data['support_open'])}',
                icon: Icons.support_agent_outlined,
                color: AppColors.danger,
                onTap: () => _push(context, const PlatformSupportPage()),
              ),
              StatCard(
                label: tr('Hujjatlar'),
                value: '${asInt(asMap(data['documents'])['awaiting'])}',
                hint: tr('Tasdiq kutilmoqda'),
                icon: Icons.description_outlined,
                color: AppColors.info,
                onTap: () => _push(context, const IssuedDocumentsPage(platform: true)),
              ),
              StatCard(
                label: tr('Faol kirishlar'),
                value: '${asInt(sessions['total'])}',
                hint: tr('Onlayn: {0}', <Object?>[asInt(sessions['online'])]),
                icon: Icons.devices_outlined,
                color: AppColors.brand,
                onTap: () => _push(context, const PlatformSessionsPage()),
              ),
            ]),
            const SizedBox(height: 14),
            Text(
              tr("O'quvchilar: {0}, foydalanuvchilar: {1}.", <Object?>[asInt(data['students']), asInt(data['users'])]),
              style: TextStyle(color: AppColors.muted, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(tr('Narxlar, sayt, sozlamalar va server — veb panelda.'), style: TextStyle(color: AppColors.muted, fontSize: 13)),
          ]);
        },
      ),
    );
  }
}

// ─────────────────────────────── Tashkilotlar ───────────────────────────────

class PlatformOrganizationsPage extends StatefulWidget {
  const PlatformOrganizationsPage({super.key, this.initialStatus = ''});

  /// '' — hammasi, trial, active, overdue (muddati o'tgan yoki faqat o'qish), suspended.
  final String initialStatus;

  @override
  State<PlatformOrganizationsPage> createState() => _PlatformOrganizationsPageState();
}

class _PlatformOrganizationsPageState extends State<PlatformOrganizationsPage> {
  final GlobalKey<AsyncViewState<List<Map<String, dynamic>>>> _view = GlobalKey<AsyncViewState<List<Map<String, dynamic>>>>();
  late String _status = widget.initialStatus;
  String _search = '';

  bool _matches(Map<String, dynamic> item) {
    final suspended = item['suspended'] == true;
    final status = asText(item['status']);
    final ok = switch (_status) {
      'trial' => status == 'trial' && !suspended,
      'active' => status == 'active' && !suspended,
      'overdue' => (status == 'past_due' || status == 'read_only') && !suspended,
      'suspended' => suspended,
      _ => true,
    };
    if (!ok) return false;
    final query = _search.trim().toLowerCase();
    return query.isEmpty || asText(item['name']).toLowerCase().contains(query);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: pageBar(context, title: Text(tr('Tashkilotlar'))),
      body: Column(children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: tr('Nomi bo\'yicha qidirish')),
            onChanged: (value) => setState(() => _search = value),
          ),
        ),
        _Filters(
          options: <(String, String)>[
            ('', tr('Hammasi')),
            ('trial', tr('Sinov')),
            ('active', tr('Faol')),
            ('overdue', tr("Muddati o'tgan")),
            ('suspended', tr("To'xtatilgan")),
          ],
          value: _status,
          onChanged: (value) => setState(() => _status = value),
        ),
        Expanded(
          child: AsyncView<List<Map<String, dynamic>>>(
            key: _view,
            cacheKey: 'platform.organizations',
            decode: (raw) => asList(raw),
            load: () async => asList(await _api(context).get('platform/organizations')),
            builder: (context, items, reload) {
              final visible = items.where(_matches).toList();
              if (visible.isEmpty) {
                return ListView(children: <Widget>[EmptyState(icon: Icons.domain_outlined, text: tr('Bu shartga mos tashkilot yo\'q.'))]);
              }
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: visible.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final item = visible[index];
                  final (label, color) = subscriptionStatus(asText(item['status']), suspended: item['suspended'] == true);
                  final ends = asText(item['status']) == 'trial' ? item['trial_ends_at'] : item['period_ends_at'];
                  return AppCard(
                    onTap: () async {
                      await _push(context, PlatformOrganizationPage(id: asInt(item['id']), title: asText(item['name'])));
                      await _view.currentState?.reload();
                    },
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                      Row(children: <Widget>[
                        Expanded(child: Text(asText(item['name']), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
                        Pill(label, color: color),
                      ]),
                      const SizedBox(height: 4),
                      Text(
                        <String>[
                          tr("{0} o'quvchi", <Object?>[asInt(item['active_students'])]),
                          if (ends != null) tr('{0} gacha', <Object?>[date(ends)]),
                          if (item['is_active'] == false) tr("O'chirilgan"),
                        ].join(' · '),
                        style: TextStyle(color: AppColors.muted, fontSize: 13),
                      ),
                    ]),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}

class PlatformOrganizationPage extends StatefulWidget {
  const PlatformOrganizationPage({super.key, required this.id, required this.title});

  final int id;
  final String title;

  @override
  State<PlatformOrganizationPage> createState() => _PlatformOrganizationPageState();
}

class _PlatformOrganizationPageState extends State<PlatformOrganizationPage> {
  final GlobalKey<AsyncViewState<Map<String, dynamic>>> _view = GlobalKey<AsyncViewState<Map<String, dynamic>>>();
  bool _busy = false;

  Future<void> _quick(String action, {int? days}) async {
    setState(() => _busy = true);
    await _act(context, () async {
      await _api(context).post('platform/organizations/${widget.id}/subscription/quick', <String, Object?>{'action': action, 'days': days});
      return switch (action) {
        'extend' => tr('Obuna {0} kunga uzaytirildi.', <Object?>[days]),
        'trial' => tr('Sinov {0} kunga uzaytirildi.', <Object?>[days]),
        'suspend' => tr("Obuna to'xtatildi."),
        _ => tr('Obuna qayta yoqildi.'),
      };
    });
    if (mounted) setState(() => _busy = false);
    await _view.currentState?.reload();
  }

  Future<void> _extend(String action) async {
    final days = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          ListTile(title: Text(action == 'trial' ? tr('Sinovni uzaytirish') : tr('Obunani uzaytirish'), style: AppTheme.title(size: 17))),
          for (final days in action == 'trial' ? <int>[7, 14, 30] : <int>[30, 90, 180, 365])
            ListTile(
              leading: const Icon(Icons.event_available_outlined),
              title: Text(tr('{0} kun', <Object?>[days])),
              onTap: () => Navigator.pop(context, days),
            ),
        ]),
      ),
    );
    if (days != null) await _quick(action, days: days);
  }

  Future<void> _suspend(bool suspended) async {
    final ok = await confirm(
      context,
      suspended
          ? tr('Obuna qayta yoqilsinmi? Tashkilot yana yozuv kirita oladi.')
          : tr("Obuna to'xtatilsinmi? Tashkilot ma'lumotlarni ko'radi, lekin yangi yozuv kirita olmaydi."),
      action: suspended ? tr('Yoqish') : tr("To'xtatish"),
      danger: !suspended,
    );
    if (ok) await _quick(suspended ? 'resume' : 'suspend');
  }

  Future<void> _staffAction(Map<String, dynamic> member, String action) async {
    final api = _api(context);
    final user = asInt(member['user_id']);
    final name = asText(member['name']);
    if (action == 'block' || action == 'unblock') {
      final block = action == 'block';
      if (!await confirm(context, block ? tr('{0} bloklansinmi? U tizimga kira olmaydi.', <Object?>[name]) : tr('{0} blokdan chiqarilsinmi?', <Object?>[name]), danger: block)) return;
      if (!mounted) return;
      await _act(context, () async {
        await api.put('platform/organizations/${widget.id}/staff/$user/block', <String, Object?>{'blocked': block});
        return block ? tr('Bloklandi.') : tr('Blokdan chiqarildi.');
      });
    } else if (action == 'sessions') {
      if (!await confirm(context, tr('{0} hamma qurilmalardan chiqarilsinmi?', <Object?>[name]), danger: true)) return;
      if (!mounted) return;
      await _act(context, () async => asText(asMap(await api.delete('platform/users/$user/sessions'))['message']));
    } else if (action == 'devices') {
      await _push(context, PlatformSessionsPage(userId: user, title: name));
    }
    await _view.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: pageBar(context, title: Text(widget.title)),
      body: AsyncView<Map<String, dynamic>>(
        key: _view,
        load: () async => asMap(await _api(context).get('platform/organizations/${widget.id}')),
        builder: (context, data, reload) {
          final subscription = asMap(data['subscription']);
          final suspended = subscription['suspended_at'] != null;
          final (label, color) = subscriptionStatus(asText(data['status']), suspended: suspended);
          final staff = asList(data['staff']);
          final modules = asRawList(data['modules']).map((item) => tr(_moduleLabels[asText(item)] ?? asText(item))).join(', ');
          return ListView(padding: const EdgeInsets.all(16), children: <Widget>[
            AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Row(children: <Widget>[
                  Expanded(child: Text(asText(data['name']), style: AppTheme.title(size: 18))),
                  Pill(label, color: color),
                ]),
                const SizedBox(height: 8),
                KeyValue(tr("O'quvchilar"), '${asInt(data['active_students'])} / ${asInt(data['students'])}'),
                if (data['trial_ends_at'] != null) KeyValue(tr('Sinov tugashi'), date(data['trial_ends_at'])),
                if (data['period_ends_at'] != null) KeyValue(tr('Obuna tugashi'), date(data['period_ends_at'])),
                if (asText(subscription['plan_code']).isNotEmpty) KeyValue(tr('Tarif'), asText(subscription['plan_code'])),
                if (modules.isNotEmpty) KeyValue(tr('Modullar'), modules),
                KeyValue(tr('Ochilgan'), date(data['created_at'])),
                if (asText(subscription['note']).isNotEmpty) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(asText(subscription['note']), style: TextStyle(color: AppColors.muted)),
                ],
              ]),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
              FilledButton.icon(onPressed: _busy ? null : () => _extend('extend'), icon: const Icon(Icons.event_repeat), label: Text(tr('Uzaytirish'))),
              if (asText(data['status']) == 'trial')
                OutlinedButton.icon(onPressed: _busy ? null : () => _extend('trial'), icon: const Icon(Icons.hourglass_top), label: Text(tr('Sinovni uzaytirish'))),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _suspend(suspended),
                icon: Icon(suspended ? Icons.play_arrow_outlined : Icons.pause_circle_outline),
                label: Text(suspended ? tr('Qayta yoqish') : tr("To'xtatish")),
              ),
            ]),
            SectionTitle(tr('Xodimlar')),
            if (staff.isEmpty)
              Text(tr("Xodim yo'q."), style: TextStyle(color: AppColors.muted))
            else
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(children: <Widget>[
                  for (final member in staff)
                    ListTile(
                      title: Text(asText(member['name'])),
                      subtitle: Text(<String>[asText(member['phone']), roleLabel(asText(member['role'])), if (member['blocked'] == true) tr('Bloklangan')].join(' · ')),
                      onTap: () => _call(context, asText(member['phone'])),
                      trailing: PopupMenuButton<String>(
                        onSelected: (action) => _staffAction(member, action),
                        itemBuilder: (context) => <PopupMenuEntry<String>>[
                          PopupMenuItem<String>(value: 'devices', child: Text(tr('Qurilmalari'))),
                          PopupMenuItem<String>(value: 'sessions', child: Text(tr('Hamma qurilmalardan chiqarish'))),
                          PopupMenuItem<String>(
                            value: member['blocked'] == true ? 'unblock' : 'block',
                            child: Text(member['blocked'] == true ? tr('Blokdan chiqarish') : tr('Bloklash')),
                          ),
                        ],
                      ),
                    ),
                ]),
              ),
            const SizedBox(height: 12),
            Text(tr('Modullar, tarif, narx va integratsiyalar — veb panelda (Tashkilotlar).'), style: TextStyle(color: AppColors.muted, fontSize: 13)),
          ]);
        },
      ),
    );
  }
}

/// Modul nomlari (server App\\Enums\\Module::label).
const Map<String, String> _moduleLabels = <String, String>{
  'testing': 'Test tizimi',
  'crm': 'CRM',
  'lms': "Ta'lim (kurslar)",
  'school': 'Maktab boshqaruvi',
};

// ─────────────────────────────── Hisoblar ───────────────────────────────

class PlatformInvoicesPage extends StatefulWidget {
  const PlatformInvoicesPage({super.key});

  @override
  State<PlatformInvoicesPage> createState() => _PlatformInvoicesPageState();
}

class _PlatformInvoicesPageState extends State<PlatformInvoicesPage> {
  String _status = 'open';
  int _version = 0;

  Future<void> _confirm(Map<String, dynamic> invoice) async {
    final organization = asText(asMap(invoice['organization'])['name']);
    final ok = await confirm(
      context,
      tr("{0}: {1} to'lov qabul qilinganini tasdiqlaysizmi? Obuna darhol uzayadi.", <Object?>[organization, money(asInt(invoice['amount']))]),
      action: tr('Tasdiqlash'),
    );
    if (!ok || !mounted) return;
    final api = _api(context);
    final done = await _act(context, () async {
      await api.post('platform/invoices/${asInt(invoice['id'])}/confirm');
      return tr("To'lov tasdiqlandi.");
    });
    if (done && mounted) setState(() => _version++);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: pageBar(context, title: Text(tr('Hisoblar'))),
      body: Column(children: <Widget>[
        _Filters(
          options: <(String, String)>[('open', tr("To'lanmagan")), ('paid', tr("To'langan")), ('', tr('Hammasi'))],
          value: _status,
          onChanged: (value) => setState(() => _status = value),
        ),
        Expanded(
          child: AsyncView<List<Map<String, dynamic>>>(
            key: ValueKey<String>('invoices-$_status-$_version'),
            load: () async => asList(await _api(context).get('platform/invoices', query: <String, Object?>{'status': _status})),
            builder: (context, items, reload) {
              if (items.isEmpty) {
                return ListView(children: <Widget>[EmptyState(icon: Icons.receipt_long_outlined, text: tr("Hisob yo'q."))]);
              }
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final invoice = items[index];
                  final status = asText(invoice['status']);
                  final (label, color) = switch (status) {
                    'paid' => (tr("To'langan"), AppColors.success),
                    'void' => (tr('Bekor qilingan'), AppColors.muted),
                    _ => (tr("To'lanmagan"), AppColors.warning),
                  };
                  return AppCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                      Row(children: <Widget>[
                        Expanded(child: Text(asText(asMap(invoice['organization'])['name'], '—'), style: const TextStyle(fontWeight: FontWeight.w700))),
                        Pill(label, color: color),
                      ]),
                      const SizedBox(height: 4),
                      Text(money(asInt(invoice['amount'])), style: AppTheme.title(size: 18)),
                      Text(
                        <String>[
                          '№ ${asText(invoice['number'], asText(invoice['id']))}',
                          dateTime(invoice['created_at']),
                          if (invoice['paid_at'] != null) tr("To'langan: {0}", <Object?>[date(invoice['paid_at'])]),
                        ].join(' · '),
                        style: TextStyle(color: AppColors.muted, fontSize: 12.5),
                      ),
                      if (status == 'open') ...<Widget>[
                        const SizedBox(height: 10),
                        FilledButton.tonalIcon(onPressed: () => _confirm(invoice), icon: const Icon(Icons.check), label: Text(tr("To'lovni tasdiqlash"))),
                      ],
                    ]),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────── Ulanish arizalari ───────────────────────────────

const Map<String, String> _requestStatuses = <String, String>{
  'new': 'Yangi',
  'contacted': "Bog'lanildi",
  'connected': 'Ulandi',
  'rejected': 'Rad etildi',
};

class PlatformRequestsPage extends StatefulWidget {
  const PlatformRequestsPage({super.key});

  @override
  State<PlatformRequestsPage> createState() => _PlatformRequestsPageState();
}

class _PlatformRequestsPageState extends State<PlatformRequestsPage> {
  String _status = '';
  int _version = 0;

  Future<void> _setStatus(Map<String, dynamic> item, String status) async {
    final api = _api(context);
    final done = await _act(context, () async {
      await api.patch('platform/requests/${asInt(item['id'])}', <String, Object?>{'status': status});
      return tr('Saqlandi.');
    });
    if (done && mounted) setState(() => _version++);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: pageBar(context, title: Text(tr('Ulanish arizalari'))),
      body: Column(children: <Widget>[
        _Filters(
          options: <(String, String)>[('', tr('Hammasi')), for (final entry in _requestStatuses.entries) (entry.key, tr(entry.value))],
          value: _status,
          onChanged: (value) => setState(() => _status = value),
        ),
        Expanded(
          child: AsyncView<List<Map<String, dynamic>>>(
            key: ValueKey<String>('requests-$_status-$_version'),
            load: () async => asList(await _api(context).get('platform/requests', query: <String, Object?>{'status': _status})),
            builder: (context, items, reload) {
              if (items.isEmpty) {
                return ListView(children: <Widget>[EmptyState(icon: Icons.mark_email_read_outlined, text: tr("Hozircha ariza yo'q."))]);
              }
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final item = items[index];
                  final status = asText(item['status']);
                  final phone = asText(item['phone']);
                  return AppCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                      Row(children: <Widget>[
                        Expanded(child: Text(asText(item['name']), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
                        Pill(tr(_requestStatuses[status] ?? status), color: status == 'new' ? AppColors.info : status == 'connected' ? AppColors.success : AppColors.muted),
                      ]),
                      const SizedBox(height: 4),
                      Text(
                        <String>[
                          asText(item['organization'], tr("Tashkilot ko'rsatilmagan")),
                          if (asText(item['type_label']).isNotEmpty) asText(item['type_label']),
                          dateTime(item['created_at']),
                        ].join(' · '),
                        style: TextStyle(color: AppColors.muted, fontSize: 13),
                      ),
                      if (asText(item['message']).isNotEmpty) ...<Widget>[
                        const SizedBox(height: 6),
                        Text(asText(item['message'])),
                      ],
                      if (asText(item['note']).isNotEmpty) ...<Widget>[
                        const SizedBox(height: 6),
                        Text(asText(item['note']), style: TextStyle(color: AppColors.muted, fontStyle: FontStyle.italic)),
                      ],
                      const SizedBox(height: 10),
                      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: <Widget>[
                        FilledButton.tonalIcon(onPressed: () => _call(context, phone), icon: const Icon(Icons.call_outlined), label: Text(phone)),
                        PopupMenuButton<String>(
                          tooltip: tr('Holat'),
                          onSelected: (value) => _setStatus(item, value),
                          itemBuilder: (context) => <PopupMenuEntry<String>>[
                            for (final entry in _requestStatuses.entries)
                              if (entry.key != 'connected') PopupMenuItem<String>(value: entry.key, child: Text(tr(entry.value))),
                          ],
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                            child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[Text(tr('Holat')), const Icon(Icons.arrow_drop_down)]),
                          ),
                        ),
                      ]),
                    ]),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────── Yordam so'rovlari ───────────────────────────────

const Map<String, String> _ticketStatuses = <String, String>{
  'open': 'Javob kutmoqda',
  'answered': 'Javob berildi',
  'closed': 'Yopilgan',
};

class PlatformSupportPage extends StatefulWidget {
  const PlatformSupportPage({super.key});

  @override
  State<PlatformSupportPage> createState() => _PlatformSupportPageState();
}

class _PlatformSupportPageState extends State<PlatformSupportPage> {
  String _status = 'open';
  int _version = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: pageBar(context, title: Text(tr("Yordam so'rovlari"))),
      body: Column(children: <Widget>[
        _Filters(
          options: <(String, String)>[for (final entry in _ticketStatuses.entries) (entry.key, tr(entry.value)), ('', tr('Hammasi'))],
          value: _status,
          onChanged: (value) => setState(() => _status = value),
        ),
        Expanded(
          child: AsyncView<List<Map<String, dynamic>>>(
            key: ValueKey<String>('support-$_status-$_version'),
            load: () async => asList(await _api(context).get('platform/support', query: <String, Object?>{'status': _status})),
            builder: (context, items, reload) {
              if (items.isEmpty) {
                return ListView(children: <Widget>[EmptyState(icon: Icons.support_agent_outlined, text: tr("Bu holatda so'rov yo'q."))]);
              }
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final item = items[index];
                  final status = asText(item['status']);
                  return AppCard(
                    onTap: () async {
                      await _push(context, PlatformTicketPage(id: asInt(item['id'])));
                      if (mounted) setState(() => _version++);
                    },
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                      Row(children: <Widget>[
                        Expanded(child: Text(asText(item['subject'], asText(item['topic'])), style: const TextStyle(fontWeight: FontWeight.w700))),
                        Pill(tr(_ticketStatuses[status] ?? status), color: status == 'open' ? AppColors.warning : status == 'answered' ? AppColors.success : AppColors.muted),
                      ]),
                      const SizedBox(height: 4),
                      Text(
                        <String>[
                          asText(item['name']),
                          if (asText(item['organization']).isNotEmpty) asText(item['organization']),
                          tr('{0} xabar', <Object?>[asInt(item['messages_count'])]),
                          dateTime(item['updated_at']),
                        ].join(' · '),
                        style: TextStyle(color: AppColors.muted, fontSize: 13),
                      ),
                    ]),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}

class PlatformTicketPage extends StatefulWidget {
  const PlatformTicketPage({super.key, required this.id});

  final int id;

  @override
  State<PlatformTicketPage> createState() => _PlatformTicketPageState();
}

class _PlatformTicketPageState extends State<PlatformTicketPage> {
  final TextEditingController _reply = TextEditingController();
  Map<String, dynamic>? _ticket;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = asMap(await _api(context).get('platform/support/${widget.id}'));
      if (mounted) setState(() => _ticket = data);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Future<void> _send({String? status}) async {
    final body = _reply.text.trim();
    if (body.isEmpty && status == null) return;
    setState(() => _busy = true);
    try {
      final data = asMap(await _api(context).post('platform/support/${widget.id}', <String, Object?>{
        if (body.isNotEmpty) 'body': body,
        if (status != null) 'status': status,
      }));
      if (!mounted) return;
      _reply.clear();
      setState(() => _ticket = data);
      showMessage(context, body.isNotEmpty ? tr('Javob yuborildi.') : tr('Holat saqlandi.'));
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ticket = _ticket;
    return Scaffold(
      appBar: pageBar(
        context,
        title: Text(ticket == null ? tr("Yordam so'rovi") : asText(ticket['subject'], asText(ticket['topic']))),
        actions: <Widget>[
          if (ticket != null)
            PopupMenuButton<String>(
              tooltip: tr('Holat'),
              onSelected: (status) => _send(status: status),
              itemBuilder: (context) => <PopupMenuEntry<String>>[
                for (final entry in _ticketStatuses.entries) PopupMenuItem<String>(value: entry.key, child: Text(tr(entry.value))),
              ],
            ),
        ],
      ),
      body: _error != null
          ? ErrorState(message: _error!, onRetry: _load)
          : ticket == null
              ? const SkeletonList(count: 3)
              : Column(children: <Widget>[
                  Expanded(
                    child: ListView(padding: const EdgeInsets.all(16), children: <Widget>[
                      Text(
                        <String>[
                          asText(ticket['name']),
                          asText(asMap(ticket['user'])['phone'], asText(ticket['contact'])),
                          if (asText(asMap(ticket['organization'])['name']).isNotEmpty) asText(asMap(ticket['organization'])['name']),
                        ].where((part) => part.isNotEmpty).join(' · '),
                        style: TextStyle(color: AppColors.muted),
                      ),
                      const SizedBox(height: 12),
                      for (final message in asList(ticket['messages']))
                        Align(
                          alignment: message['from_staff'] == true ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            constraints: const BoxConstraints(maxWidth: 520),
                            decoration: BoxDecoration(
                              color: message['from_staff'] == true ? AppColors.soft(AppColors.brand) : AppColors.surface2,
                              borderRadius: BorderRadius.circular(AppRadius.control),
                            ),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                              SelectableText(asText(message['body'])),
                              if (asRawList(message['attachments']).isNotEmpty)
                                Text(tr('Ilova: {0} ta fayl (vebda ko\'ring)', <Object?>[asRawList(message['attachments']).length]),
                                    style: TextStyle(color: AppColors.muted, fontSize: 12)),
                              const SizedBox(height: 4),
                              Text(dateTime(message['created_at']), style: TextStyle(color: AppColors.muted, fontSize: 11.5)),
                            ]),
                          ),
                        ),
                    ]),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                      child: Row(children: <Widget>[
                        Expanded(
                          child: TextField(
                            controller: _reply,
                            minLines: 1,
                            maxLines: 5,
                            maxLength: 5000,
                            decoration: InputDecoration(hintText: tr('Javob yozing...'), counterText: ''),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(onPressed: _busy ? null : () => _send(), icon: const Icon(Icons.send), tooltip: tr('Yuborish')),
                      ]),
                    ),
                  ),
                ]),
    );
  }
}

// ─────────────────────────────── Sessiyalar ───────────────────────────────

class PlatformSessionsPage extends StatefulWidget {
  const PlatformSessionsPage({super.key, this.userId, this.title});

  /// Faqat bitta foydalanuvchining kirishlari (tashkilot xodimlari ro'yxatidan).
  final int? userId;
  final String? title;

  @override
  State<PlatformSessionsPage> createState() => _PlatformSessionsPageState();
}

class _PlatformSessionsPageState extends State<PlatformSessionsPage> {
  String _search = '';
  bool _online = false;
  int _version = 0;

  void _reload() => setState(() => _version++);

  Future<void> _close(Map<String, dynamic> item) async {
    final api = _api(context);
    if (await _act(context, () async => asText(asMap(await api.delete('platform/sessions/${asInt(item['id'])}'))['message']))) _reload();
  }

  Future<void> _closeUser(Map<String, dynamic> user) async {
    if (!await confirm(context, tr('{0} hamma qurilmalardan chiqarilsinmi?', <Object?>[asText(user['name'])]), danger: true)) return;
    if (!mounted) return;
    final api = _api(context);
    if (await _act(context, () async => asText(asMap(await api.delete('platform/users/${asInt(user['id'])}/sessions'))['message']))) _reload();
  }

  Future<void> _limit(Map<String, dynamic> user, Map<String, dynamic> policy) async {
    final controller = TextEditingController(text: user['max_sessions'] == null ? '' : asText(user['max_sessions']));
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('{0}: qurilmalar chegarasi', <Object?>[asText(user['name'])])),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(hintText: tr('Umumiy: {0}', <Object?>[asInt(policy['max_sessions'])])),
          ),
          const SizedBox(height: 8),
          Text(tr("Bo'sh — umumiy sozlama, 0 — cheklanmagan. Kamaytirilsa, ortiqcha kirishlar darhol yopiladi."), style: TextStyle(color: AppColors.muted, fontSize: 13)),
        ]),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Bekor qilish'))),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: Text(tr('Saqlash'))),
        ],
      ),
    );
    controller.dispose();
    if (value == null || !mounted) return;
    final number = value.isEmpty ? null : int.tryParse(value);
    if (value.isNotEmpty && (number == null || number < 0 || number > 100)) {
      showMessage(context, tr('0 dan 100 gacha son kiriting.'), error: true);
      return;
    }
    final api = _api(context);
    final done = await _act(context, () async {
      final data = asMap(await api.put('platform/users/${asInt(user['id'])}/session-limit', <String, Object?>{'max_sessions': number}));
      final closed = asInt(data['closed']);
      return closed > 0 ? tr('Chegara saqlandi, {0} ta ortiqcha kirish yopildi.', <Object?>[closed]) : tr('Chegara saqlandi.');
    });
    if (done) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: pageBar(context, title: Text(widget.title ?? tr('Sessiyalar'))),
      body: Column(children: <Widget>[
        if (widget.userId == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(children: <Widget>[
              Expanded(
                child: TextField(
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: tr('Ism yoki telefon')),
                  onSubmitted: (value) => setState(() {
                    _search = value.trim();
                    _version++;
                  }),
                ),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: Text(tr('Onlayn')),
                selected: _online,
                onSelected: (value) => setState(() {
                  _online = value;
                  _version++;
                }),
              ),
            ]),
          ),
        Expanded(
          child: AsyncView<Map<String, dynamic>>(
            key: ValueKey<String>('sessions-$_version'),
            load: () async => asMap(await _api(context).get('platform/sessions', query: <String, Object?>{
              'search': _search,
              'online': _online ? 1 : null,
              'user_id': widget.userId,
            })),
            builder: (context, data, reload) {
              final items = asList(data['data']);
              final summary = asMap(data['summary']);
              final policy = asMap(data['policy']);
              final total = asInt(asMap(data['meta'])['total'], items.length);
              return ListView(padding: const EdgeInsets.all(16), children: <Widget>[
                if (widget.userId == null) ...<Widget>[
                  StatGrid(children: <Widget>[
                    StatCard(label: tr('Faol kirishlar'), value: '${asInt(summary['total'])}', icon: Icons.devices_outlined),
                    StatCard(label: tr('Hozir onlayn'), value: '${asInt(summary['online'])}', icon: Icons.wifi_tethering, color: AppColors.success),
                    StatCard(label: tr('Foydalanuvchilar'), value: '${asInt(summary['users'])}', icon: Icons.people_outline, color: AppColors.info),
                    StatCard(label: tr('Vaqtincha yopilgan hisoblar'), value: '${asInt(summary['locked'])}', icon: Icons.lock_clock_outlined, color: AppColors.warning),
                  ]),
                  const SizedBox(height: 10),
                  Text(
                    <String>[
                      tr('Brauzerda {0} kun, ilovada {1} kun amal qiladi.', <Object?>[asInt(policy['session_days']), asInt(policy['app_session_days'])]),
                      if (policy['app_sliding'] == true) tr("Ilovada foydalanib turilsa, muddat o'zi uzayadi."),
                      asInt(policy['idle_hours']) > 0 ? tr('{0} soat foydalanilmasa yopiladi.', <Object?>[asInt(policy['idle_hours'])]) : tr("Faolsizlik chegarasi o'chiq."),
                      asInt(policy['max_sessions']) > 0
                          ? tr('Bitta hisobga {0} ta qurilma ({1}).', <Object?>[
                              asInt(policy['max_sessions']),
                              asText(policy['limit_mode']) == 'reject' ? tr("ortig'i rad etiladi") : tr('eng eskisi yopiladi'),
                            ])
                          : tr('Qurilmalar soni cheklanmagan.'),
                      tr('Qoidalar — veb: Sozlamalar → Kirish va Telegram → Sessiyalar.'),
                    ].join(' '),
                    style: TextStyle(color: AppColors.muted, fontSize: 12.5),
                  ),
                  const SizedBox(height: 12),
                ],
                if (items.isEmpty)
                  EmptyState(icon: Icons.devices_outlined, text: tr("Bu shartga mos kirish yo'q."))
                else
                  AppCard(
                    padding: EdgeInsets.zero,
                    child: Column(children: <Widget>[
                      for (final item in items)
                        SessionTile(
                          item: item,
                          title: widget.userId == null ? asText(asMap(item['user'])['name'], '—') : null,
                          trailing: PopupMenuButton<String>(
                            onSelected: (action) {
                              final user = asMap(item['user']);
                              if (action == 'close') _close(item);
                              if (action == 'user') _closeUser(user);
                              if (action == 'limit') _limit(user, policy);
                            },
                            itemBuilder: (context) => <PopupMenuEntry<String>>[
                              if (item['current'] != true) PopupMenuItem<String>(value: 'close', child: Text(tr('Yopish'))),
                              if (item['user'] != null) ...<PopupMenuEntry<String>>[
                                PopupMenuItem<String>(value: 'user', child: Text(tr('Hamma qurilmalardan chiqarish'))),
                                PopupMenuItem<String>(
                                  value: 'limit',
                                  child: Text(tr('Chegara: {0}', <Object?>[
                                    asInt(asMap(item['user'])['limit']) > 0 ? asInt(asMap(item['user'])['limit']) : '∞',
                                  ])),
                                ),
                              ],
                            ],
                          ),
                        ),
                    ]),
                  ),
                if (total > items.length)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(tr("Ko'rsatildi: {0} / {1}. Qidiruv bilan toraytiring.", <Object?>[items.length, total]), style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
                  ),
              ]);
            },
          ),
        ),
      ]),
    );
  }
}
