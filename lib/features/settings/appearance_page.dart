// «Ko'rinish» (3.9, dizayn v3 «Koshin»; veb: Profil → Ko'rinish, Components/ThemePicker.vue): rejim, shablon (9), asosiy rang (12), matn o'lchami,
// animatsiya darajasi, zichlik va qo'shimcha (shrift, burchaklar, karta uslubi, fon naqshi, menyu). Tepada — jonli namuna:
// ilovaning haqiqiy komponentlari (hero, «Bugun» kartalari, holat chipi, pastki menyu) tanlangan ko'rinishda.
// Tanlov darhol qo'llanadi va hisobga saqlanadi (PUT profile/appearance). Rang va shablonni platforma ruxsat bergandagina
// foydalanuvchi o'zi tanlaydi; rejim, o'lcham va animatsiya — har doim shaxsiy.
import 'package:flutter/material.dart';

import '../../core/adaptive.dart';
import '../../core/design.dart';
import '../../core/home_today.dart';
import '../../core/home_widgets.dart';
import '../../core/i18n.dart';
import '../../core/koshin.dart';
import '../../core/motion.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

class AppearancePage extends StatelessWidget {
  const AppearancePage({super.key});

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context);
    final choice = session.themeChoice;
    final open = session.canCustomizeTheme;
    final systemReduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    void apply(String field, String? value) => session.setAppearance(<String, String?>{field: value});
    return Scaffold(
      appBar: pageBar(context, title: Text(tr("Ko'rinish"))),
      body: ListView(
        padding: readable(context, const EdgeInsets.fromLTRB(16, 16, 16, 32)),
        children: <Widget>[
          const AppearancePreview(),
          const SizedBox(height: 8),
          Text(
            tr('Hozirgi ko\'rinish: {0}, {1}', <Object?>[tr(templateLabels[choice.template] ?? ''), tr(accentOf(choice.accent).label)]),
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.subtle, fontSize: 12.5),
          ),
          _Section(
            title: tr('Rejim'),
            child: _Segments(
              values: const <String>['light', 'dark', 'system'],
              labels: modeLabels,
              selected: choice.mode,
              onSelect: session.setThemeMode,
            ),
          ),
          if (open) ...<Widget>[
            _Section(
              title: tr('Shablon'),
              child: _TemplateGrid(selected: choice.template, accent: accentOf(choice.accent), onSelect: (value) => apply('template', value)),
            ),
            _Section(
              title: tr('Asosiy rang'),
              child: _AccentRow(selected: choice.accent, onSelect: (value) => apply('accent', value)),
            ),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 18),
              child: ToneBox(
                color: AppColors.accent,
                background: AppColors.accentSoft,
                padding: const EdgeInsets.all(12),
                child: Text(tr("Shablon va rangni tashkilot belgilaydi. Rejim, matn o'lchami va animatsiyani o'zingiz tanlaysiz."),
                    style: TextStyle(color: AppColors.ink, fontSize: 13.5, height: 1.4)),
              ),
            ),
          _Section(
            title: tr("Matn o'lchami"),
            child: _Segments(values: const <String>['sm', 'md', 'lg', 'xl'], labels: sizeLabels, selected: choice.size, onSelect: (value) => apply('size', value)),
          ),
          _Section(
            title: tr('Animatsiya'),
            hint: systemReduced
                ? tr("Telefoningizda «Harakatni kamaytirish» yoqilgan — faqat yumshoq so'nish qoladi.")
                : tr("«Kam» — faqat yumshoq so'nish, «O'chiq» — hech qanday harakat."),
            child: _Segments(values: const <String>['full', 'reduced', 'off'], labels: motionLabels, selected: choice.motion, onSelect: (value) => apply('motion', value)),
          ),
          if (open) ...<Widget>[
            _Section(
              title: tr('Zichlik'),
              child: _Segments(values: const <String>['auto', 'comfy', 'normal', 'compact'], labels: densityLabels, selected: choice.density, onSelect: (value) => apply('density', value)),
            ),
            _Section(
              title: tr('Qo\'shimcha'),
              child: AppCard(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(children: <Widget>[
                  _Dropdown(label: tr('Shrift'), icon: Icons.font_download_outlined, labels: fontLabels, value: choice.font, onChanged: (value) => apply('font', value)),
                  const Divider(indent: 56),
                  _Dropdown(label: tr('Burchaklar'), icon: Icons.rounded_corner, labels: radiusLabels, value: choice.radius, onChanged: (value) => apply('radius', value)),
                  const Divider(indent: 56),
                  _Dropdown(label: tr('Karta uslubi'), icon: Icons.crop_square_rounded, labels: cardsLabels, value: choice.cards, onChanged: (value) => apply('cards', value)),
                  const Divider(indent: 56),
                  _Dropdown(label: tr('Fon naqshi'), icon: Icons.grid_4x4_rounded, labels: patternLabels, value: choice.pattern, onChanged: (value) => apply('pattern', value)),
                  const Divider(indent: 56),
                  _Dropdown(
                    label: tr('Pastki menyu'),
                    icon: Icons.space_bar_rounded,
                    labels: const <String, String>{'auto': 'Shablonga qarab', 'full': "To'liq", 'floating': 'Suzuvchi'},
                    value: choice.sidebar == 'icons' ? 'full' : choice.sidebar,
                    onChanged: (value) => apply('sidebar', value),
                  ),
                  const Divider(indent: 56),
                  _Dropdown(label: tr('Menyu ikonalari'), icon: Icons.palette_outlined, labels: iconsLabels, value: choice.icons, onChanged: (value) => apply('icons', value)),
                ]),
              ),
            ),
          ],
          const SizedBox(height: 20),
          Center(
            child: TextButton.icon(
              onPressed: () => session.setAppearance(<String, String?>{
                for (final field in themeOptions.keys)
                  if (field != 'mode' && (open || personalThemeFields.contains(field))) field: null,
              }),
              icon: const Icon(Icons.restart_alt_rounded, size: 20),
              label: Text(tr('Standart ko\'rinishga qaytarish')),
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.hint});

  final String title;
  final String? hint;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      SectionTitle(title),
      child,
      if (hint != null) ...<Widget>[
        const SizedBox(height: 6),
        Text(hint!, style: TextStyle(color: AppColors.subtle, fontSize: 12.5, height: 1.35)),
      ],
    ]);
  }
}

/// Bir qatordagi tanlov (segmentlar): faol segment asosiy rangda.
class _Segments extends StatelessWidget {
  const _Segments({required this.values, required this.labels, required this.selected, required this.onSelect});

  final List<String> values;
  final Map<String, String> labels;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<String>(
      showSelectedIcon: false,
      expandedInsets: EdgeInsets.zero,
      segments: <ButtonSegment<String>>[
        for (final value in values)
          ButtonSegment<String>(
            value: value,
            label: Text(tr(labels[value] ?? value), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
          ),
      ],
      selected: <String>{values.contains(selected) ? selected : values.first},
      onSelectionChanged: (value) => onSelect(value.first),
    );
  }
}

class _Dropdown extends StatelessWidget {
  const _Dropdown({required this.label, required this.icon, required this.labels, required this.value, required this.onChanged});

  final String label;
  final IconData icon;
  final Map<String, String> labels;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing: DropdownButton<String>(
        value: labels.containsKey(value) ? value : labels.keys.first,
        underline: const SizedBox(),
        items: labels.entries.map((entry) => DropdownMenuItem<String>(value: entry.key, child: Text(tr(entry.value)))).toList(),
        onChanged: (next) {
          if (next != null) onChanged(next);
        },
      ),
    );
  }
}

/// 12 asosiy rang: doiralar, tanlangani halqa va belgi bilan.
class _AccentRow extends StatelessWidget {
  const _AccentRow({required this.selected, required this.onSelect});

  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 10, runSpacing: 10, children: <Widget>[
      for (final accent in accents)
        Semantics(
          label: tr(accent.label),
          selected: accent.key == selected,
          button: true,
          child: Tooltip(
            message: tr(accent.label),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => onSelect(accent.key),
              child: AnimatedContainer(
                duration: Motion.duration(context, AppDurations.d2),
                width: 40,
                height: 40,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: accent.key == selected ? AppColors.ink : Colors.transparent, width: 2),
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(color: accent.c600, shape: BoxShape.circle),
                  child: accent.key == selected ? const Icon(Icons.check_rounded, size: 18, color: Colors.white) : null,
                ),
              ),
            ),
          ),
        ),
    ]);
  }
}

/// 9 shablon: har biri o'z palitrasida chizilgan kichik namuna — yon menyu (faol band), sarlavha paneli, ikki koshin
/// plitka (Ixcham/Grafit — och), ostida nom va kimga mosligi.
class _TemplateGrid extends StatelessWidget {
  const _TemplateGrid({required this.selected, required this.accent, required this.onSelect});

  final String selected;
  final Accent accent;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final keys = themeOptions['template']!;
    return AdaptiveGrid(
      minTile: 104,
      minColumns: 3,
      maxColumns: 5,
      spacing: 10,
      children: <Widget>[for (final key in keys) _TemplateSwatch(template: key, accent: accent, selected: key == selected, onTap: () => onSelect(key))],
    );
  }
}

class _TemplateSwatch extends StatelessWidget {
  const _TemplateSwatch({required this.template, required this.accent, required this.selected, required this.onTap});

  final String template;
  final Accent accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = templatePalettes[template]![AppColors.dark ? 1 : 0];
    final quiet = template == 'compact' || template == 'graphite';
    final activeBg = template == 'atlas' ? Koshin.shafran : accent.c600;
    final rk = const <String, double>{'soft': 1.35, 'compact': 0.65, 'atlas': 1.1, 'graphite': 0.5, 'spring': 1.5}[template] ?? 1;
    final radius = BorderRadius.circular(AppRadius.control);
    Widget tile(Color color) => Expanded(
          child: Container(
            height: 22,
            decoration: BoxDecoration(
              color: quiet ? Color.lerp(palette.surface, color, 0.12) : color,
              borderRadius: BorderRadius.circular(4 * rk),
              border: quiet ? Border.all(color: color.withAlpha(90), width: 0.8) : null,
            ),
            alignment: Alignment.bottomLeft,
            padding: const EdgeInsets.all(3),
            child: Container(width: 9, height: 3, color: quiet ? color : Colors.white.withAlpha(220)),
          ),
        );
    return Semantics(
      selected: selected,
      button: true,
      label: tr(templateLabels[template] ?? template),
      child: Pressable(
        child: AnimatedContainer(
          duration: Motion.duration(context, AppDurations.d2),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: radius,
            border: Border.all(color: selected ? AppColors.accent : AppColors.line, width: selected ? 2 : 1),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              borderRadius: radius,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
                  ClipRRect(
                    borderRadius: BorderRadius.circular((AppRadius.control - 3).clamp(2, 20).toDouble()),
                    child: SizedBox(
                      height: 66,
                      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
                        // Yon menyu: logo nuqtasi, faol band (tabletka), bandlar.
                        Container(
                          width: 22,
                          color: palette.sidebarBg,
                          padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
                          child: Column(children: <Widget>[
                            Container(height: 7, decoration: BoxDecoration(color: accent.c600, borderRadius: BorderRadius.circular(2))),
                            const SizedBox(height: 6),
                            Container(height: 6, decoration: BoxDecoration(color: template == 'school' || template == 'spring' ? Color.lerp(palette.sidebarBg, accent.c600, 0.3) : activeBg, borderRadius: BorderRadius.circular(3))),
                            for (var i = 0; i < 3; i++) ...<Widget>[
                              const SizedBox(height: 4),
                              Container(height: 3, margin: const EdgeInsets.symmetric(horizontal: 2), color: palette.sidebarFg.withAlpha(110)),
                            ],
                          ]),
                        ),
                        Expanded(
                          child: ColoredBox(
                            color: palette.canvas,
                            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
                              Container(height: 10, color: palette.headerBg, child: Align(alignment: Alignment.centerLeft, child: Container(margin: const EdgeInsets.only(left: 5), width: 18, height: 3, color: palette.text3.withAlpha(140)))),
                              Container(height: 1, color: palette.border),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(5, 6, 5, 0),
                                child: Align(alignment: Alignment.centerLeft, child: Container(width: 30, height: 4, color: palette.text1)),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(5, 6, 5, 0),
                                child: Row(children: <Widget>[tile(Koshin.anor), const SizedBox(width: 3), tile(Koshin.lojuvard)]),
                              ),
                            ]),
                          ),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(children: <Widget>[
                    Expanded(
                      child: Text(tr(templateLabels[template] ?? template),
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink)),
                    ),
                    if (selected) Icon(Icons.check_circle_rounded, size: 16, color: AppColors.accent),
                  ]),
                  Text(tr(templateHints[template] ?? ''), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: AppColors.subtle, height: 1.25)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Jonli namuna: ilovaning haqiqiy komponentlari joriy ko'rinishda (bosilmaydi).
class AppearancePreview extends StatelessWidget {
  const AppearancePreview({super.key});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.card + 6);
    const items = <TodayItem>[
      TodayItem(key: 'preview-debt', value: '3', text: "o'quvchining qarzi bor", tone: TodayTone.danger, icon: 'warning'),
      TodayItem(key: 'preview-lessons', value: '16:00', text: 'ING-5, davomat bir bosishda', icon: 'calendar'),
      TodayItem(key: 'preview-paid', value: '12', text: "to'lov bugun qabul qilindi", icon: 'banknote'),
    ];
    return Semantics(
      label: tr('Namuna'),
      child: ExcludeSemantics(
        child: IgnorePointer(
          child: Container(
            decoration: BoxDecoration(borderRadius: radius, border: Border.all(color: AppColors.lineStrong), color: AppColors.canvas),
            clipBehavior: Clip.antiAlias,
            child: FittedBox(
              fit: BoxFit.fitWidth,
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: 380,
                child: CanvasPattern(
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                      child: HomeHeader(
                        name: 'Karimova Nodira',
                        facts: <HeroFact>[
                          HeroFact('2', tr('ta dars bugun')),
                          HeroFact('3', tr("o'quvchining qarzi bor"), tone: TodayTone.danger),
                        ],
                        action: FilledButton.icon(onPressed: () {}, icon: const Icon(Icons.payments_outlined, size: 20), label: Text(tr("To'lov qabul qilish"))),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                      child: IntrinsicHeight(
                        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
                          for (var i = 0; i < items.length; i++) ...<Widget>[
                            if (i > 0) const SizedBox(width: 8),
                            Expanded(
                              child: KoshinTile(
                                hue: todayHue(items[i]),
                                value: items[i].value,
                                text: tr(items[i].text),
                                icon: navIcon(items[i].icon),
                                minHeight: 118,
                              ),
                            ),
                          ],
                        ]),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                      child: Wrap(spacing: 8, children: <Widget>[
                        Pill(tr("To'langan"), color: AppColors.success),
                        Pill(tr('Kutilmoqda'), color: AppColors.warning),
                        Pill(tr('Qarz'), color: AppColors.danger),
                      ]),
                    ),
                    MediaQuery.removePadding(
                      context: context,
                      removeBottom: true,
                      child: AppNavBar(
                      destinations: <AdaptiveDestination>[
                        AdaptiveDestination(icon: Icons.home_outlined, label: tr('Bosh sahifa')),
                        AdaptiveDestination(icon: Icons.event_outlined, label: tr('Jadval')),
                        AdaptiveDestination(icon: Icons.groups_outlined, label: tr("O'quvchilar")),
                        AdaptiveDestination(icon: Icons.payments_outlined, label: tr('Moliya')),
                        AdaptiveDestination(icon: Icons.menu, label: tr('Yana')),
                      ],
                      selected: 0,
                      onSelect: (_) {},
                    ),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
