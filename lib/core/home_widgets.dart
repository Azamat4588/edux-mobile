// Bosh sahifa komponentlari (veb 1.41 «Koshin»: Components/Home/HomeHeader.vue, TodayCard.vue, ActionTile.vue,
// LessonTimeline.vue, AttentionList.vue, Sparkline.vue). Rang ma'noli joyda: koshin plitkalar (KPI), «hozir» darsi —
// shafran, diqqat ro'yxatidagi son plitkasi — holat rangida; hero kartasiz, kanvasning o'zida.
import 'package:flutter/material.dart';

import 'adaptive.dart';
import 'api.dart';
import 'design.dart';
import 'format.dart';
import 'home_today.dart';
import 'i18n.dart';
import 'koshin.dart';
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
    'coins': Icons.toll_outlined,
    'clock': Icons.schedule_outlined,
    'inbox': Icons.inbox_outlined,
    'user-plus': Icons.person_add_alt_1_outlined,
    'credit-card': Icons.credit_card,
    'timer': Icons.timer_outlined,
    'trending-up': Icons.trending_up_rounded,
  };
  return icons[name] ?? Icons.circle_outlined;
}

/// Koshin plitka rangi «Bugun» kartasi uchun (veb TodayCard: holat → anor/shafran/pista, aks holda belgi ma'nosidan).
KoshinHue todayHue(TodayItem item) => hueOf(tone: item.tone, icon: item.icon);

/// Bosh sahifa «hero»si (veb 1.41: HomeHeader, `home-hero` — kartasiz, kanvasning o'zida): sana tabletkasi (shafran romb),
/// katta salom (Commissioner), faktlar — chip ichida rangli son doirasi, asosiy harakat.
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
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Row(children: <Widget>[
          Flexible(child: HeroDate(text: dayTitle(now))),
          const Spacer(),
          if (trailing != null) trailing!,
        ]),
        SizedBox(height: dense ? 8 : 10),
        Semantics(
          header: true,
          child: Text(
            title ?? (first.isEmpty ? greetingFor(now) : '${greetingFor(now)}, $first'),
            style: AppTheme.title(size: dense ? 26 : 31).copyWith(height: 1.08),
          ),
        ),
        if (subtitle != null && subtitle!.isNotEmpty) ...<Widget>[
          const SizedBox(height: 4),
          Text(subtitle!, style: TextStyle(color: AppColors.subtle, fontSize: 13.5)),
        ],
        if (facts.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
            for (var i = 0; i < facts.length; i++) HeroFactChip(fact: facts[i], countKey: 'hero:$i:${facts[i].text}'),
          ]),
        ] else if (lead.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Text(lead, style: TextStyle(color: AppColors.muted, fontSize: 15, height: 1.4)),
        ],
        if (action != null || secondary != null) ...<Widget>[
          const SizedBox(height: 16),
          // Telefonda tugmalar butun kenglikda, keng ekranda (iPad) — o'z kengligida (veb: home-hero-actions).
          LayoutBuilder(builder: (context, box) {
            final wide = box.maxWidth >= 600;
            Widget slot(Widget child) => wide ? ConstrainedBox(constraints: const BoxConstraints(minWidth: 220), child: child) : Expanded(child: child);
            return Row(children: <Widget>[
              if (action != null) slot(action!),
              if (action != null && secondary != null) const SizedBox(width: 10),
              if (secondary != null) slot(secondary!),
            ]);
          }),
        ],
      ]),
    );
  }
}

/// Sana tabletkasi (veb: home-hero-date): asosiy rangning och fonida, chapda shafran romb.
class HeroDate extends StatelessWidget {
  const HeroDate({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 5, 12, 5),
      decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
        Transform.rotate(
          angle: 0.785398,
          child: Container(width: 8, height: 8, decoration: BoxDecoration(color: Koshin.shafran, borderRadius: BorderRadius.circular(2))),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.accentStrong)),
        ),
      ]),
    );
  }
}

/// Hero fakti (veb: home-hero-fact): tabletka, chapda son — holat rangidagi doirada.
class HeroFactChip extends StatelessWidget {
  const HeroFactChip({super.key, required this.fact, required this.countKey});

  final HeroFact fact;
  final String countKey;

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg) = switch (fact.tone) {
      TodayTone.danger => (AppColors.toneDanger, Colors.white),
      TodayTone.warning => (AppColors.toneWarning, Koshin.shafranInk),
      TodayTone.success => (AppColors.toneSuccess, Colors.white),
      TodayTone.none => (AppColors.sunken, AppColors.ink),
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(5, 5, 12, 5),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(99), border: Border.all(color: AppColors.line)),
      child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
        Container(
          constraints: const BoxConstraints(minWidth: 26),
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 7),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
          child: CountUpText(fact.value, countKey: countKey, style: AppTheme.display(size: 14, color: fg).copyWith(letterSpacing: 0, height: 1.1)),
        ),
        if (fact.text.isNotEmpty) ...<Widget>[
          const SizedBox(width: 8),
          Flexible(child: Text(fact.text, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.muted))),
        ],
      ]),
    );
  }
}

/// «Bugun» kartasi v3 (veb: TodayCard 1.41) — koshin plitka: to'liq rangli fon, burchakda girih yulduzi, katta raqam
/// (sanab o'tadi), oddiy so'zlar bilan jumla, ixtiyoriy o'zgarish va mini-grafik.
class TodayCard extends StatelessWidget {
  const TodayCard({super.key, required this.item, this.onTap});

  final TodayItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final hue = todayHue(item);
    final colors = KoshinTileColors.of(hue);
    final delta = item.delta;
    final trend = item.trend;
    return KoshinTile(
      hue: hue,
      value: item.value,
      text: item.text,
      hint: item.hint,
      icon: item.icon.isEmpty ? null : navIcon(item.icon),
      delta: delta == null ? null : '${delta > 0 ? '+' : ''}$delta%',
      onTap: onTap,
      valueBuilder: (style) => CountUpText(item.value, countKey: 'today:${item.key}', maxLines: 1, style: style),
      footer: trend != null && trend.length > 1
          ? Sparkline(values: trend, height: 26, color: colors.value, label: tr("So'nggi 6 oy tushumi"), animationKey: 'today:${item.key}')
          : null,
    );
  }
}

/// «Bugun» plitkalari to'ri (telefonda 2 ustun, iPad'da 4 tagacha). Bosh sahifa yuklanishida plitkalar navbat bilan
/// «qo'yiladi» ([IntroTile]).
class TodayGrid extends StatelessWidget {
  const TodayGrid({super.key, required this.items, required this.onOpen});

  final List<TodayItem> items;
  final void Function(String target)? onOpen;

  @override
  Widget build(BuildContext context) {
    Widget cell(int index) {
      final item = items[index];
      final target = item.target;
      return IntroTile(order: index, child: TodayCard(item: item, onTap: target == null || onOpen == null ? null : () => onOpen!(target)));
    }

    return AdaptiveGrid(minTile: 160, children: <Widget>[for (var i = 0; i < items.length; i++) cell(i)]);
  }
}

/// Katta tezkor tugma (veb: action-tile): oq karta, rangli belgi plitkasi (bosilganda qiyshayadi), nom va izoh.
/// `primary` — asosiy rangda to'liq.
class ActionTile extends StatefulWidget {
  const ActionTile({super.key, required this.action, required this.onTap, this.index = 0});

  final QuickAction action;
  final VoidCallback onTap;

  /// Plitka rangi tartibi.
  final int index;

  @override
  State<ActionTile> createState() => _ActionTileState();
}

class _ActionTileState extends State<ActionTile> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final action = widget.action;
    final primary = action.primary;
    final radius = BorderRadius.circular(AppRadius.card);
    final fg = primary ? AppColors.onBrand : AppColors.ink;
    final tiles = AppColors.tiles;
    final tile = tiles.isEmpty ? StatusColors(AppColors.brand, AppColors.accentSoft) : tiles[widget.index % tiles.length];
    final rich = Motion.rich(context);
    final icon = primary
        ? Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: Colors.white.withAlpha(51), borderRadius: BorderRadius.circular(AppRadius.control)),
            child: Icon(navIcon(action.icon), size: 20, color: AppColors.onBrand),
          )
        : IconTile(icon: navIcon(action.icon), colors: tile, size: 38);
    return Pressable(
      child: DecoratedBox(
        decoration: BoxDecoration(borderRadius: radius, boxShadow: primary ? const <BoxShadow>[] : AppColors.cardShadow),
        child: Material(
          color: primary ? AppColors.accent : AppColors.card,
          shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: primary ? AppColors.accent : AppColors.cardBorder)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            onHighlightChanged: (value) => setState(() => _down = value),
            child: Container(
              constraints: BoxConstraints(minHeight: AppColors.choice.dense ? 56 : 66),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(children: <Widget>[
                AnimatedRotation(
                  turns: _down && rich ? -4 / 360 : 0,
                  duration: AppDurations.d2,
                  curve: AppCurves.spring,
                  child: AnimatedScale(scale: _down && rich ? 1.08 : 1, duration: AppDurations.d2, curve: AppCurves.spring, child: icon),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                    Text(action.label, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5, color: fg, height: 1.25)),
                    if (action.hint.isNotEmpty)
                      Text(action.hint, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: primary ? AppColors.onBrand.withAlpha(215) : AppColors.subtle)),
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

/// Bugungi darslar — vaqt chizig'i (veb 1.41: LessonTimeline): chapda vaqt, o'rtada chiziq va romb nuqta (o'tdi / hozir /
/// keyingi), o'ngda guruh va izoh. «Hozir» — shafran romb (halqa tarqaladi) va shafran tusli qator.
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
    final next = state == LessonState.next;
    Widget dot = Transform.rotate(
      angle: 0.785398,
      child: Container(
        width: 13,
        height: 13,
        decoration: BoxDecoration(
          color: now ? Koshin.shafran : (done ? AppColors.lineStrong : AppColors.card),
          border: Border.all(color: now ? Koshin.shafran : (next ? AppColors.accent : AppColors.lineStrong), width: 2),
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
    if (now) dot = PulseRing(color: Koshin.shafran, size: 13, child: dot);
    final body = Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: now
          ? BoxDecoration(
              color: Color.lerp(AppColors.card, Koshin.shafran, AppColors.dark ? 0.2 : 0.16),
              borderRadius: BorderRadius.circular(AppRadius.control),
              border: Border.all(color: Koshin.shafran.withAlpha(115)),
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
                now
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                        decoration: BoxDecoration(color: Koshin.shafran, borderRadius: BorderRadius.circular(99)),
                        child: Text(stateText, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Koshin.shafranInk)),
                      )
                    : Text(stateText, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: done ? AppColors.subtle : AppColors.accentStrong)),
              ],
            ]),
            if (info.isNotEmpty) Text(info, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: now ? AppColors.muted : AppColors.subtle)),
          ]),
        ),
        if (status != null)
          Pill(tr(status), color: AppColors.muted)
        else if (onAttendance != null)
          SizedBox(
            height: 34,
            child: primary || now
                ? FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 34), padding: const EdgeInsets.symmetric(horizontal: 12), textStyle: TextStyle(fontFamily: AppColors.choice.fontFamily, fontSize: 13, fontWeight: FontWeight.w600)),
                    onPressed: () => onAttendance!(lesson),
                    child: Text(tr('Davomat')),
                  )
                : OutlinedButton(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 34), padding: const EdgeInsets.symmetric(horizontal: 12), textStyle: TextStyle(fontFamily: AppColors.choice.fontFamily, fontSize: 13, fontWeight: FontWeight.w600)),
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
            width: 48,
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
            child: Stack(alignment: Alignment.topCenter, clipBehavior: Clip.none, children: <Widget>[
              Positioned(top: 0, bottom: last ? null : 0, height: last ? 14 : null, child: Container(width: 2, decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(2)))),
              Padding(padding: const EdgeInsets.only(top: 14), child: dot),
            ]),
          ),
          const SizedBox(width: 8),
          Expanded(child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: body)),
        ]),
      ),
    );
  }
}

/// «Diqqat talab qiladi» (veb 1.41: AttentionList): chapda to'liq rangli son plitkasi (ustuvorlik rangi), nima va qayerga
/// borish; bosilganda o'q siljiydi. Bo'sh bo'lsa — «Hammasi joyida».
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

class _AttentionRow extends StatefulWidget {
  const _AttentionRow({required this.item, this.onTap});

  final AttentionItem item;
  final VoidCallback? onTap;

  @override
  State<_AttentionRow> createState() => _AttentionRowState();
}

class _AttentionRowState extends State<_AttentionRow> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final (Color tone, Color ink) = switch (item.tone) {
      'danger' => (AppColors.toneDanger, Colors.white),
      'warning' => (AppColors.toneWarning, Koshin.shafranInk),
      'info' => (AppColors.toneInfo, Colors.white),
      _ => (AppColors.accent, AppColors.onBrand),
    };
    final radius = BorderRadius.circular(AppRadius.control);
    final row = Container(
      constraints: const BoxConstraints(minHeight: 54),
      padding: const EdgeInsets.fromLTRB(8, 8, 10, 8),
      child: Row(children: <Widget>[
        Container(
          constraints: const BoxConstraints(minWidth: 38),
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: tone, borderRadius: BorderRadius.circular(AppRadius.control)),
          child: CountUpText('${item.count}', countKey: 'attention:${item.key}', style: AppTheme.display(size: 17, color: ink).copyWith(letterSpacing: 0)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(item.text, style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.ink, fontSize: 14.5, height: 1.3)),
            if (item.hint.isNotEmpty) Text(item.hint, style: TextStyle(fontSize: 12, color: AppColors.subtle)),
          ]),
        ),
        if (widget.onTap != null)
          AnimatedSlide(
            offset: Offset(_down && Motion.rich(context) ? 0.18 : 0, 0),
            duration: AppDurations.d2,
            curve: AppCurves.spring,
            child: Icon(Icons.chevron_right, size: 20, color: AppColors.subtle),
          ),
      ]),
    );
    return Material(
      color: _down ? Color.lerp(AppColors.surface2, tone, 0.08) : AppColors.surface2,
      shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: _down ? tone.withAlpha(77) : Colors.transparent)),
      clipBehavior: Clip.antiAlias,
      child: widget.onTap == null
          ? row
          : InkWell(onTap: widget.onTap, onHighlightChanged: (value) => setState(() => _down = value), child: row),
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

/// iPad yon menyusi tepasida tashkilot bloki (veb: org-card): logo yoki bosh harf, nom va rol.
class RailOrg extends StatelessWidget {
  const RailOrg({super.key, required this.name, required this.logo, required this.subtitle});

  final String name;
  final String? logo;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final mark = OrgMark(url: logo, name: name, size: 40);
      if (box.maxWidth < 160) return Center(child: Tooltip(message: name, child: mark));
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Color.alphaBlend(AppColors.navFg.withAlpha(16), AppColors.navBg),
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        child: Row(children: <Widget>[
          mark,
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: AppColors.navDark ? Colors.white : AppColors.ink, height: 1.2)),
              if (subtitle.isNotEmpty) Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: AppColors.navFg)),
            ]),
          ),
        ]),
      );
    });
  }
}
