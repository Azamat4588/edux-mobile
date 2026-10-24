// Bosh sahifa komponentlari (veb 1.40: Components/Home/HomeHeader.vue, TodayCard.vue, ActionTile.vue, LessonTimeline.vue,
// AttentionList.vue, Sparkline.vue). Hoshiya — chap chetdagi rangli chiziq — hero, «Bugun» kartasi, «hozir» darsi va diqqat
// ro'yxatini bir tilda bog'laydi.
import 'package:flutter/material.dart';

import 'adaptive.dart';
import 'api.dart';
import 'design.dart';
import 'format.dart';
import 'home_today.dart';
import 'i18n.dart';
import 'motion.dart';
import 'theme.dart';
import 'widgets.dart';

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

/// Ohangning matn rangi (raqam): qizil / sariq / yashil yoki siyoh.
Color toneText(TodayTone tone) {
  switch (tone) {
    case TodayTone.danger:
      return AppColors.danger;
    case TodayTone.warning:
      return AppColors.warning;
    case TodayTone.success:
      return AppColors.success;
    case TodayTone.none:
      return AppColors.ink;
  }
}

/// Ohang plitkasi (veb: TodayCard TILE): qizil → tile-rose, sariq → tile-sun, yashil → tile-green, oddiy — asosiy rang.
StatusColors toneTile(TodayTone tone) {
  final tiles = AppColors.tiles;
  if (tiles.length < 6) return StatusColors(AppColors.brand, AppColors.accentSoft);
  switch (tone) {
    case TodayTone.danger:
      return tiles[5];
    case TodayTone.warning:
      return tiles[4];
    case TodayTone.success:
      return tiles[3];
    case TodayTone.none:
      return tiles[0];
  }
}

/// Bosh sahifa «hero»si (veb: HomeHeader, `home-hero`): sana (asosiy rangda), salom (sarlavha shriftida), 1–2 fakt va asosiy
/// harakat. Chap chetida hoshiya, o'ng tomonda asosiy rangdagi nozik katak (chapga so'nadi).
class HomeHeader extends StatelessWidget {
  const HomeHeader({super.key, required this.name, this.lead = '', this.facts = const <HeroFact>[], this.action, this.secondary, this.trailing, this.title, this.subtitle});

  final String name;

  /// Salom o'rnida sarlavha (ota-ona: farzand ismi) va uning ostidagi izoh (kod, guruhlar).
  final String? title;
  final String? subtitle;
  final String lead;
  final List<HeroFact> facts;

  /// Asosiy harakat (to'liq tugma) va ikkinchi darajali.
  final Widget? action;
  final Widget? secondary;

  /// O'ng yuqori burchakdagi qo'shimcha (masalan, bola tanlash).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final now = homeClock();
    final first = firstNameOf(name);
    final dense = AppColors.choice.dense;
    final radius = BorderRadius.circular(AppRadius.card);
    final pad = (20 * AppColors.choice.densityFactor).clamp(14, 24).toDouble();
    final content = Padding(
      padding: EdgeInsets.fromLTRB(pad + AppSpacing.hoshiya, pad, pad, pad),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Row(children: <Widget>[
          Expanded(
            child: Text(dayTitle(now), style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.accentStrong)),
          ),
          if (trailing != null) trailing!,
        ]),
        const SizedBox(height: 4),
        Semantics(
          header: true,
          child: Text(
            title ?? (first.isEmpty ? greetingFor(now) : '${greetingFor(now)}, $first'),
            style: AppTheme.title(size: dense ? 24 : 28),
          ),
        ),
        if (subtitle != null && subtitle!.isNotEmpty) ...<Widget>[
          const SizedBox(height: 2),
          Text(subtitle!, style: TextStyle(color: AppColors.subtle, fontSize: 13)),
        ],
        if (facts.isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          Wrap(spacing: 18, runSpacing: 6, children: <Widget>[
            for (var i = 0; i < facts.length; i++) _Fact(fact: facts[i], countKey: 'hero:$i:${facts[i].text}'),
          ]),
        ] else if (lead.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Text(lead, style: TextStyle(color: AppColors.muted, fontSize: 14.5, height: 1.4)),
        ],
        if (action != null || secondary != null) ...<Widget>[
          const SizedBox(height: 16),
          Row(children: <Widget>[
            if (action != null) Expanded(child: action!),
            if (action != null && secondary != null) const SizedBox(width: 10),
            if (secondary != null) Expanded(child: secondary!),
          ]),
        ],
      ]),
    );
    Widget card = Material(
      color: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: AppColors.cardBorder)),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(
        painter: _HeroGridPainter(color: AppColors.accent, background: AppColors.card),
        child: DecoratedBox(
          decoration: BoxDecoration(border: Border(left: BorderSide(color: AppColors.accent, width: AppSpacing.hoshiya))),
          child: content,
        ),
      ),
    );
    if (AppColors.cardShadow.isNotEmpty) {
      card = DecoratedBox(decoration: BoxDecoration(borderRadius: radius, boxShadow: AppColors.cardShadow), child: card);
    }
    return card;
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.fact, required this.countKey});

  final HeroFact fact;
  final String countKey;

  @override
  Widget build(BuildContext context) {
    final valueStyle = TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: toneText(fact.tone), fontFeatures: AppTheme.tabular);
    return Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
      if (fact.tone != TodayTone.none) ...<Widget>[
        Container(width: 8, height: 8, decoration: BoxDecoration(color: toneColor(fact.tone), shape: BoxShape.circle)),
        const SizedBox(width: 7),
      ],
      CountUpText(fact.value, countKey: countKey, style: valueStyle),
      if (fact.text.isNotEmpty) ...<Widget>[
        const SizedBox(width: 6),
        Text(fact.text, style: TextStyle(fontSize: 15, color: AppColors.muted)),
      ],
    ]);
  }
}

/// Hero foni: o'ng tomonda asosiy rangdagi 20px katak, chapga so'nadi (veb: home-hero::after).
class _HeroGridPainter extends CustomPainter {
  _HeroGridPainter({required this.color, required this.background});

  final Color color;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    const step = 20.0;
    final line = Paint()
      ..color = color.withAlpha(AppColors.dark ? 34 : 28)
      ..strokeWidth = 1;
    final start = size.width * 0.3;
    for (var x = size.width - 0.5; x > start; x -= step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
    for (var y = step - 0.5; y < size.height; y += step) {
      canvas.drawLine(Offset(start, y), Offset(size.width, y), line);
    }
    // Chapga so'nish: karta rangidan shaffofga.
    final fade = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawRect(
      fade,
      Paint()
        ..shader = LinearGradient(
          colors: <Color>[background, background, background.withAlpha(0)],
          stops: const <double>[0, 0.38, 0.88],
        ).createShader(fade),
    );
  }

  @override
  bool shouldRepaint(_HeroGridPainter oldDelegate) => oldDelegate.color != color || oldDelegate.background != background;
}

/// «Bugun» kartasi v2 (veb: TodayCard 1.40): rangli belgi plitkasi, katta raqam (sanab o'tadi), oddiy so'zlar bilan jumla,
/// ixtiyoriy o'zgarish va mini-grafik. Diqqat talab qilsa — chap chetida ohang hoshiyasi.
class TodayCard extends StatelessWidget {
  const TodayCard({super.key, required this.item, this.onTap});

  final TodayItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.card);
    final tone = toneColor(item.tone);
    final dense = AppColors.choice.dense;
    final long = item.value.length > 8;
    final delta = item.delta;
    final trend = item.trend;
    final body = Container(
      constraints: BoxConstraints(minHeight: dense ? 104 : 124),
      decoration: item.tone == TodayTone.none ? null : BoxDecoration(border: Border(left: BorderSide(color: tone, width: AppSpacing.hoshiya))),
      padding: EdgeInsets.fromLTRB(dense ? 12 : 14, dense ? 10 : 14, dense ? 10 : 12, dense ? 10 : 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Row(children: <Widget>[
          if (item.icon.isNotEmpty) IconTile(icon: navIcon(item.icon), colors: toneTile(item.tone), size: dense ? 30 : 34),
          const Spacer(),
          if (delta != null)
            Text(
              '${delta > 0 ? '+' : ''}$delta%',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: delta == 0 ? AppColors.muted : (delta > 0 ? AppColors.success : AppColors.danger)),
            )
          else if (onTap != null)
            Icon(Icons.chevron_right, size: 18, color: AppColors.subtle),
        ]),
        SizedBox(height: dense ? 8 : 10),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: CountUpText(
            item.value,
            countKey: 'today:${item.key}',
            style: TextStyle(
              fontSize: long ? (dense ? 19 : 21) : (dense ? 24 : 28),
              fontWeight: FontWeight.w700,
              height: 1.05,
              letterSpacing: -0.5,
              color: toneText(item.tone),
              fontFeatures: AppTheme.tabular,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(item.text, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: AppColors.ink, height: 1.3)),
        if (item.hint.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(item.hint, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: AppColors.subtle)),
          ),
        if (trend != null && trend.length > 1) ...<Widget>[
          const SizedBox(height: 8),
          Sparkline(values: trend, height: 26, label: tr("So'nggi 6 oy tushumi"), animationKey: 'today:${item.key}'),
        ],
      ]),
    );
    Widget card = Material(
      color: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: AppColors.cardBorder)),
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? body : InkWell(onTap: onTap, child: body),
    );
    if (AppColors.cardShadow.isNotEmpty) {
      card = DecoratedBox(decoration: BoxDecoration(borderRadius: radius, boxShadow: AppColors.cardShadow), child: card);
    }
    return Pressable(enabled: onTap != null, child: card);
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

/// Katta tezkor tugma (veb: action-tile): rangli plitka, nom va izoh. `primary` — asosiy rangda to'liq.
class ActionTile extends StatelessWidget {
  const ActionTile({super.key, required this.action, required this.onTap, this.index = 0});

  final QuickAction action;
  final VoidCallback onTap;

  /// Plitka rangi tartibi (veb: tile-green, tile-blue, tile-violet ...).
  final int index;

  @override
  Widget build(BuildContext context) {
    final primary = action.primary;
    final radius = BorderRadius.circular(AppRadius.card);
    final fg = primary ? Colors.white : AppColors.ink;
    final tiles = AppColors.tiles;
    const order = <int>[0, 1, 2, 3, 4, 5];
    final tile = tiles.isEmpty ? StatusColors(AppColors.brand, AppColors.accentSoft) : tiles[order[index % order.length]];
    return Pressable(
      child: DecoratedBox(
        decoration: BoxDecoration(borderRadius: radius, boxShadow: primary ? const <BoxShadow>[] : AppColors.cardShadow),
        child: Material(
          color: primary ? AppColors.accent : AppColors.card,
          shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: primary ? AppColors.accent : AppColors.cardBorder)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Container(
              constraints: BoxConstraints(minHeight: AppColors.choice.dense ? 56 : 66),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(children: <Widget>[
                primary
                    ? Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(color: Colors.white.withAlpha(36), borderRadius: BorderRadius.circular(AppRadius.control)),
                        child: Icon(navIcon(action.icon), size: 20, color: Colors.white),
                      )
                    : IconTile(icon: navIcon(action.icon), colors: tile, size: 38),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                    Text(action.label, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5, color: fg, height: 1.25)),
                    if (action.hint.isNotEmpty)
                      Text(action.hint, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: primary ? Colors.white.withAlpha(215) : AppColors.subtle)),
                  ]),
                ),
              ]),
            ),
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
      for (var i = 0; i < actions.length; i++) ActionTile(action: actions[i], index: i + 1, onTap: () => onTap(actions[i])),
    ]);
  }
}

/// Bugungi darslar — vaqt chizig'i (veb: LessonTimeline.vue): chapda vaqt, o'rtada chiziq va nuqta (o'tdi / hozir /
/// keyingi), o'ngda guruh va izoh. «Hozir» darsi hoshiya bilan; davomat tugmasi (o'qituvchida — asosiy rangda).
class LessonTimeline extends StatelessWidget {
  const LessonTimeline({super.key, required this.lessons, this.primary = false, this.onAttendance, this.detail, this.now});

  final List<Map<String, dynamic>> lessons;
  final bool primary;
  final void Function(Map<String, dynamic> lesson)? onAttendance;

  /// Kichik izoh qatori (standart: o'qituvchi, xona).
  final String Function(Map<String, dynamic> lesson)? detail;

  /// Hozirgi vaqt (testlar uchun).
  final DateTime? now;

  static const Map<String, String> _status = <String, String>{'cancelled': 'Bekor qilingan', 'moved': "Ko'chirilgan", 'holiday': 'Dam olish'};

  @override
  Widget build(BuildContext context) {
    final states = lessonStates(lessons, now ?? homeClock());
    return Column(children: <Widget>[
      for (var i = 0; i < lessons.length; i++) _TimelineRow(lesson: lessons[i], state: states[i], last: i == lessons.length - 1, primary: primary, onAttendance: onAttendance, detail: detail),
    ]);
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.lesson, required this.state, required this.last, required this.primary, this.onAttendance, this.detail});

  final Map<String, dynamic> lesson;
  final LessonState state;
  final bool last;
  final bool primary;
  final void Function(Map<String, dynamic> lesson)? onAttendance;
  final String Function(Map<String, dynamic> lesson)? detail;

  @override
  Widget build(BuildContext context) {
    final group = asMap(lesson['group']);
    final info = detail?.call(lesson) ??
        <String>[if (lesson['course'] != null) asText(lesson['course']), if (lesson['teacher'] != null) asText(lesson['teacher']), if (lesson['room'] != null) asText(lesson['room'])]
            .where((item) => item.isNotEmpty)
            .join(', ');
    final stateText = switch (state) {
      LessonState.now => tr('Hozir'),
      LessonState.next => tr('Keyingi'),
      LessonState.done => tr("O'tdi"),
      _ => '',
    };
    final status = LessonTimeline._status[asText(lesson['status'])];
    final now = state == LessonState.now;
    final done = state == LessonState.done;
    final dot = Container(
      width: 14,
      height: 14,
      margin: const EdgeInsets.only(top: 5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: now ? AppColors.accent : (done ? AppColors.lineStrong : AppColors.card),
        border: Border.all(color: now || state == LessonState.next ? AppColors.accent : AppColors.lineStrong, width: 2),
        boxShadow: now ? <BoxShadow>[BoxShadow(color: AppColors.accent.withAlpha(60), spreadRadius: 4)] : null,
      ),
    );
    final body = Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: now
          ? BoxDecoration(
              color: AppColors.accentSoft,
              borderRadius: BorderRadius.circular(AppRadius.control),
              border: Border(left: BorderSide(color: AppColors.accent, width: AppSpacing.hoshiya)),
            )
          : null,
      child: Row(children: <Widget>[
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Row(children: <Widget>[
              Flexible(
                child: Text(asText(group['name']),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: AppColors.ink,
                      decoration: status != null ? TextDecoration.lineThrough : null,
                    )),
              ),
              if (stateText.isNotEmpty) ...<Widget>[
                const SizedBox(width: 8),
                Text(stateText, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: done ? AppColors.subtle : AppColors.accentStrong)),
              ],
            ]),
            if (info.isNotEmpty) Text(info, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: AppColors.subtle)),
          ]),
        ),
        if (status != null)
          Pill(tr(status), color: AppColors.muted)
        else if (onAttendance != null)
          SizedBox(
            height: 34,
            child: primary || now
                ? FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 34), padding: const EdgeInsets.symmetric(horizontal: 12), textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    onPressed: () => onAttendance!(lesson),
                    child: Text(tr('Davomat')),
                  )
                : OutlinedButton(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 34), padding: const EdgeInsets.symmetric(horizontal: 12), textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    onPressed: () => onAttendance!(lesson),
                    child: Text(tr('Davomat')),
                  ),
          ),
      ]),
    );
    return Opacity(
      opacity: done ? 0.72 : 1,
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          SizedBox(
            width: 50,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: <Widget>[
                Text(asText(lesson['start']), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.ink, fontFeatures: AppTheme.tabular)),
                Text(asText(lesson['end']), style: TextStyle(fontSize: 12, color: AppColors.subtle, fontFeatures: AppTheme.tabular)),
              ]),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 16,
            child: Stack(alignment: Alignment.topCenter, children: <Widget>[
              Positioned(top: 0, bottom: last ? null : 0, height: last ? 12 : null, child: Container(width: 2, color: AppColors.line)),
              Padding(padding: const EdgeInsets.only(top: 8), child: dot),
            ]),
          ),
          const SizedBox(width: 8),
          Expanded(child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: body)),
        ]),
      ),
    );
  }
}

/// «Diqqat talab qiladi» (veb: AttentionList.vue): har qatorda son (ohang rangida), nima va qayerga borish; chap chetida
/// ohang hoshiyasi. Bo'sh bo'lsa — «Hammasi joyida».
class AttentionList extends StatelessWidget {
  const AttentionList({super.key, required this.items, this.onOpen});

  final List<AttentionItem> items;
  final void Function(String target)? onOpen;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Row(children: <Widget>[
        Icon(Icons.check_circle_outline_rounded, color: AppColors.success, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text(tr("Hammasi joyida: shoshilinch ish yo'q."), style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w600))),
      ]);
    }
    return Column(children: <Widget>[
      for (final item in items)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _AttentionRow(item: item, onTap: item.target == null || onOpen == null ? null : () => onOpen!(item.target!)),
        ),
    ]);
  }
}

class _AttentionRow extends StatelessWidget {
  const _AttentionRow({required this.item, this.onTap});

  final AttentionItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tone = switch (item.tone) {
      'danger' => AppColors.toneDanger,
      'warning' => AppColors.toneWarning,
      _ => AppColors.accent,
    };
    final countColor = switch (item.tone) {
      'danger' => AppColors.danger,
      'warning' => AppColors.warning,
      _ => AppColors.accentStrong,
    };
    final radius = BorderRadius.circular(AppRadius.control);
    final row = Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(border: Border(left: BorderSide(color: tone, width: AppSpacing.hoshiya))),
      child: Row(children: <Widget>[
        SizedBox(
          width: 40,
          child: CountUpText('${item.count}',
              countKey: 'attention:${item.key}',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: countColor, fontFeatures: AppTheme.tabular)),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(item.text, style: TextStyle(fontWeight: FontWeight.w500, color: AppColors.ink, fontSize: 14.5)),
            if (item.hint.isNotEmpty) Text(item.hint, style: TextStyle(fontSize: 12, color: AppColors.subtle)),
          ]),
        ),
        if (onTap != null) Icon(Icons.chevron_right, size: 20, color: AppColors.subtle),
      ]),
    );
    return Material(
      color: AppColors.surface2,
      shape: RoundedRectangleBorder(borderRadius: radius),
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? row : InkWell(onTap: onTap, child: row),
    );
  }
}

/// Tashkilot belgisi: logo yoki bosh harf asosiy rangda (veb: org-card-mark).
class OrgMark extends StatelessWidget {
  const OrgMark({super.key, required this.url, required this.name, this.size = 34});

  final String? url;
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular((AppRadius.control * 0.9).clamp(4, 12).toDouble());
    final letter = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: AppColors.accent, borderRadius: radius),
      child: Text(name.trim().isEmpty ? 'E' : name.trim().substring(0, 1).toUpperCase(),
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: size * 0.46)),
    );
    if (url == null) return letter;
    return ClipRRect(
      borderRadius: radius,
      child: Container(
        color: Colors.white,
        width: size,
        height: size,
        child: Image.network(url!, width: size, height: size, fit: BoxFit.contain, cacheWidth: (size * 3).round(), errorBuilder: (_, __, ___) => letter),
      ),
    );
  }
}
