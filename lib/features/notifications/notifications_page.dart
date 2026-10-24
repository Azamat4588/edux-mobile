// Bildirishnomalar markazi (3.1): kelgan push xabarlar ro'yxati (o'qilgan/o'qilmagan), bosilganda tegishli sahifa
// ochiladi. Bosh sahifalardagi qo'ng'iroqcha — o'qilmaganlar soni bilan.
import 'package:flutter/material.dart';

import '../../core/adaptive.dart';
import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/motion.dart';
import '../../core/notification_store.dart';
import '../../core/push.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

/// Xabar turi → belgi va rang.
IconData notificationIcon(String type) {
  switch (type) {
    case 'payment':
      return Icons.payments_outlined;
    case 'attendance':
      return Icons.event_busy_outlined;
    case 'arrival':
      return Icons.login_rounded;
    case 'attempt':
      return Icons.quiz_outlined;
    case 'assignment':
      return Icons.task_outlined;
    case 'certificate':
      return Icons.workspace_premium_outlined;
    case 'lead':
      return Icons.person_add_alt;
    case 'task':
      return Icons.task_alt;
    case 'diary':
      return Icons.event_note_outlined;
    case 'child':
      return Icons.family_restroom_outlined;
    default:
      return Icons.notifications_none_rounded;
  }
}

Color notificationColor(String type) {
  switch (type) {
    case 'payment':
    case 'arrival':
      return AppColors.success;
    case 'attendance':
      return AppColors.danger;
    case 'certificate':
      return AppColors.warning;
    default:
      return AppColors.brand;
  }
}

/// Bosh sahifa sarlavhasidagi qo'ng'iroqcha: o'qilmaganlar soni nishoni bilan.
class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context) {
    final store = NotificationStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final unread = store.unread;
        return IconButton(
          tooltip: tr('Bildirishnomalar'),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const NotificationsPage())),
          icon: Badge(
            isLabelVisible: unread > 0,
            backgroundColor: AppColors.dangerFill,
            label: Text(unread > 99 ? '99+' : '$unread'),
            child: Icon(unread > 0 ? Icons.notifications_active_outlined : Icons.notifications_none_rounded),
          ),
        );
      },
    );
  }
}

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final NotificationStore _store = NotificationStore.instance;

  /// Surib o'chirilganlar (Dismissible o'zi yig'adi — ro'yxat harakati takrorlanmaydi).
  final Set<String> _dismissed = <String>{};

  @override
  void initState() {
    super.initState();
    _store.load();
  }

  Future<void> _open(AppNotification item) async {
    await _store.markRead(item.id);
    if (!mounted) return;
    // Turi yo'q, lekin veb manzili (route/url) bor xabar ham ochiladi; noma'lumi — bosh sahifa.
    if (item.data.isEmpty) return;
    await PushService.instance.open(item.data);
  }

  Future<void> _clear() async {
    if (!await confirm(context, tr("Barcha bildirishnomalar o'chirilsinmi?"), action: tr("O'chirish"), danger: true)) return;
    await _store.clear();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        final items = _store.items;
        return Scaffold(
          appBar: pageBar(context,
            title: Text(tr('Bildirishnomalar')),
            actions: <Widget>[
              if (_store.unread > 0)
                IconButton(tooltip: tr("Hammasini o'qilgan deb belgilash"), onPressed: _store.markAllRead, icon: const Icon(Icons.done_all_rounded)),
              if (items.isNotEmpty)
                IconButton(tooltip: tr('Tozalash'), onPressed: _clear, icon: const Icon(Icons.delete_sweep_outlined)),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: _store.load,
            child: items.isEmpty
                ? ListView(children: <Widget>[
                    EmptyState(
                      icon: Icons.notifications_none_rounded,
                      text: PushService.instance.available
                          ? tr("Hozircha bildirishnoma yo'q. To'lov, baho, test natijasi va vazifalar haqidagi xabarlar shu yerda saqlanadi.")
                          : tr("Hozircha bildirishnoma yo'q. Push-bildirishnomalar bu ilova yig'ilishida yoqilmagan bo'lishi mumkin."),
                    ),
                  ])
                // 3.8: yangi xabar chapdan paydo bo'ladi, o'chirilgani yig'iladi (AnimatedList).
                : DiffAnimatedList<AppNotification>(
                    padding: readable(context, const EdgeInsets.symmetric(vertical: AppSpacing.s)),
                    physics: const AlwaysScrollableScrollPhysics(),
                    items: items,
                    keyOf: (item) => item.id,
                    skipRemoval: (item) => _dismissed.contains(item.id),
                    itemBuilder: (context, item, index) => Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                      if (index > 0) const Divider(indent: 72),
                      Dismissible(
                        key: ValueKey<String>(item.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: AppSpacing.xl),
                          color: AppColors.dangerBg,
                          child: Icon(Icons.delete_outline, color: AppColors.danger),
                        ),
                        onDismissed: (_) {
                          _dismissed.add(item.id);
                          _store.remove(item.id);
                        },
                        child: _NotificationTile(item: item, onTap: () => _open(item)),
                      ),
                    ]),
                  ),
          ),
        );
      },
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.item, required this.onTap});

  final AppNotification item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final type = asText(PushService.normalize(item.data)['type']);
    final color = notificationColor(type);
    // O'qilmagan xabar — chap chetida hoshiya (diqqat talab qiladi).
    return ListTile(
      onTap: onTap,
      tileColor: item.read ? null : AppColors.accentSoft.withAlpha(AppColors.dark ? 120 : 150),
      shape: item.read ? null : Border(left: BorderSide(color: AppColors.accent, width: AppSpacing.hoshiya)),
      leading: IconTile(icon: notificationIcon(type), colors: tileOf(color), size: 44),
      title: Text(
        item.title.isEmpty ? tr('Bildirishnoma') : item.title,
        style: TextStyle(fontWeight: item.read ? FontWeight.w500 : FontWeight.w700),
      ),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        if (item.body.isNotEmpty) Text(item.body, maxLines: 3, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 2),
        Text(dateTime(item.receivedAt.toIso8601String()), style: TextStyle(fontSize: 12, color: AppColors.muted)),
      ]),
      trailing: item.read
          ? null
          : Container(width: 10, height: 10, decoration: BoxDecoration(color: AppColors.brand, shape: BoxShape.circle)),
    );
  }
}
