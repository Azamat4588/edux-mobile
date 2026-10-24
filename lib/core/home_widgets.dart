// Bosh sahifa komponentlari (veb: Components/Home/TodayCard.vue, ActionTile.vue, HomeHeader.vue).
import 'package:flutter/material.dart';

import 'adaptive.dart';
import 'design.dart';
import 'format.dart';
import 'home_today.dart';
import 'i18n.dart';
import 'theme.dart';

/// Veb ikonka nomi → Material belgi.
IconData navIcon(String name) {
  const icons = <String, IconData>{
    'home': Icons.home_outlined,
    'academic-cap': Icons.school_outlined,
    'users': Icons.groups_outlined,
    'book': Icons.menu_book_outlined,
    'clipboard-list': Icons.assignment_outlined,
    'banknote': Icons.payments_outlined,
    'wallet': Icons.account_balance_wallet_outlined,
    'warning': Icons.warning_amber_rounded,
    'chat': Icons.forum_outlined,
    'cog': Icons.settings_outlined,
    'list-checks': Icons.task_alt,
    'sparkle': Icons.auto_awesome_outlined,
    'columns': Icons.view_kanban_outlined,
    'headphones': Icons.headset_mic_outlined,
    'pen-line': Icons.edit_note_outlined,
    'trophy': Icons.emoji_events_outlined,
    'server': Icons.dns_outlined,
    'calendar': Icons.event_outlined,
    'camera': Icons.document_scanner_outlined,
    'pencil': Icons.edit_outlined,
    'phone': Icons.phone_outlined,
    'plus': Icons.person_add_alt_1_outlined,
    'check-circle': Icons.fact_check_outlined,
    'star': Icons.star_outline_rounded,
    'receipt': Icons.receipt_long_outlined,
    'qr': Icons.qr_code_scanner,
    'card': Icons.credit_card,
    'question': Icons.help_outline,
    'megaphone': Icons.campaign_outlined,
    'science': Icons.science_outlined,
    'feedback': Icons.rate_review_outlined,
  };
  return icons[name] ?? Icons.circle_outlined;
}

Color toneColor(TodayTone tone) {
  switch (tone) {
    case TodayTone.danger:
      return AppColors.toneDanger;
    case TodayTone.warning:
      return AppColors.toneWarning;
    case TodayTone.success:
      return AppColors.toneSuccess;
    case TodayTone.none:
      return Colors.transparent;
  }
}

/// Sarlavha: salomlashish, bugungi sana va «bu sahifada nima qilinadi» (page-lead). Maktab shablonida — katak daftar foni.
class HomeHeader extends StatelessWidget {
  const HomeHeader({super.key, required this.name, this.lead = ''});

  final String name;
  final String lead;

  @override
  Widget build(BuildContext context) {
    final parts = name.trim().split(RegExp(r'\s+'));
    final first = parts.length > 1 ? parts[1] : name;
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Row(children: <Widget>[
          if (AppColors.choice.notebook)
            Container(width: 4, height: 24, margin: const EdgeInsets.only(right: 8), decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(2))),
          Expanded(child: Text(tr('Assalomu alaykum, {0}', <Object?>[first]), style: AppTheme.title(size: AppColors.choice.dense ? 20 : 22))),
        ]),
        const SizedBox(height: 4),
        Text(dayTitle(DateTime.now()), style: TextStyle(color: AppColors.muted)),
        if (lead.isNotEmpty) ...<Widget>[
          const SizedBox(height: 6),
          Text(lead, style: TextStyle(color: AppColors.muted, fontSize: 13.5, height: 1.35)),
        ],
      ]),
    );
    if (!AppColors.choice.notebook) return content;
    return CustomPaint(painter: _NotebookPainter(dark: AppColors.dark), child: content);
  }
}

/// Katak daftar chizig'i (Maktab shabloni): 24px katak, pastga qarab so'nadi.
class _NotebookPainter extends CustomPainter {
  _NotebookPainter({required this.dark});

  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    const step = 24.0;
    final base = dark ? const Color(0xFFFFFFFF) : const Color(0xFF3A5CA0);
    for (var y = 0.0; y <= size.height; y += step) {
      final fade = 1 - (y / (size.height + 1));
      canvas.drawLine(Offset(-16, y), Offset(size.width + 16, y), Paint()..color = base.withAlpha((18 * fade).round()));
    }
    for (var x = -16.0; x <= size.width + 16; x += step) {
      final shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[base.withAlpha(18), base.withAlpha(0)],
      ).createShader(Rect.fromLTWH(x, 0, 1, size.height));
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), Paint()..shader = shader);
    }
  }

  @override
  bool shouldRepaint(_NotebookPainter oldDelegate) => oldDelegate.dark != dark;
}

/// «Bugun» kartasi: chap chetda ohang chizig'i (daftar hoshiyasi kabi), katta raqam, oddiy so'zlar bilan izoh.
class TodayCard extends StatelessWidget {
  const TodayCard({super.key, required this.item, this.onTap});

  final TodayItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.card);
    final tone = toneColor(item.tone);
    final dense = AppColors.choice.dense;
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: radius, boxShadow: AppColors.cardShadow),
      child: Material(
        color: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: AppColors.cardBorder)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: BoxConstraints(minHeight: dense ? 96 : 112),
            decoration: BoxDecoration(border: Border(left: BorderSide(color: tone, width: item.tone == TodayTone.none ? 0 : 4))),
            padding: EdgeInsets.fromLTRB(dense ? 12 : 14, dense ? 10 : 14, dense ? 10 : 12, dense ? 10 : 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Row(children: <Widget>[
                Icon(navIcon(item.icon), size: 18, color: item.tone == TodayTone.none ? AppColors.muted : tone),
                const Spacer(),
                if (onTap != null) Icon(Icons.chevron_right, size: 18, color: AppColors.muted),
              ]),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(item.value, style: TextStyle(fontSize: dense ? 20 : 24, fontWeight: FontWeight.w800, color: AppColors.ink)),
              ),
              const SizedBox(height: 2),
              Text(item.text, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: AppColors.ink)),
              if (item.hint.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(item.hint, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: AppColors.muted)),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// «Bugun» kartalari to'ri (telefonda 2 ustun).
class TodayGrid extends StatelessWidget {
  const TodayGrid({super.key, required this.items, required this.onOpen});

  final List<TodayItem> items;
  final void Function(String target)? onOpen;

  @override
  Widget build(BuildContext context) {
    Widget cell(TodayItem item) {
      final target = item.target;
      return TodayCard(item: item, onTap: target == null || onOpen == null ? null : () => onOpen!(target));
    }

    // Telefonda 2 ustun, iPad'da 4 tagacha (lib/core/adaptive.dart).
    return AdaptiveGrid(minTile: 200, children: <Widget>[for (final item in items) cell(item)]);
  }
}

/// Katta tezkor tugma (veb: action-tile; `primary` — asosiy rangda to'liq).
class ActionTile extends StatelessWidget {
  const ActionTile({super.key, required this.action, required this.onTap});

  final QuickAction action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = action.primary;
    final radius = BorderRadius.circular(AppRadius.card);
    final fg = primary ? Colors.white : AppColors.ink;
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: radius, boxShadow: AppColors.cardShadow),
      child: Material(
        color: primary ? AppColors.brand : AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: primary ? AppColors.brand : AppColors.cardBorder)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: BoxConstraints(minHeight: AppColors.choice.dense ? 56 : 64),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: <Widget>[
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: primary ? Colors.white.withAlpha(40) : AppColors.soft(AppColors.brand),
                  borderRadius: BorderRadius.circular(AppRadius.control),
                ),
                child: Icon(navIcon(action.icon), size: 20, color: primary ? Colors.white : AppColors.brand),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  Text(action.label, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: fg)),
                  if (action.hint.isNotEmpty)
                    Text(action.hint, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: primary ? Colors.white.withAlpha(210) : AppColors.muted)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Tezkor harakatlar to'ri (telefonda 2 ustun, keng ekranda 4 tagacha).
class ActionGrid extends StatelessWidget {
  const ActionGrid({super.key, required this.actions, required this.onTap});

  final List<QuickAction> actions;
  final void Function(QuickAction action) onTap;

  @override
  Widget build(BuildContext context) {
    return AdaptiveGrid(minTile: 200, children: <Widget>[
      for (final action in actions) ActionTile(action: action, onTap: () => onTap(action)),
    ]);
  }
}
