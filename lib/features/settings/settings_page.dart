// «Yana» (3.8): profil, pastki menyuga sig'magan bo'limlar (to'dalar bo'yicha: «Kundalik ish», «Pul va aloqa», «Boshqaruv»),
// ilova bandlari (bildirishnomalar, murojaatlar, yordam), sozlamalar (til, «Ko'rinish», skaner) va chiqish.
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/adaptive.dart';
import '../../core/app_update.dart';
import '../../core/design.dart';
import '../../core/i18n.dart';
import '../../core/push.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/organization_picker.dart';
import '../help/help_pages.dart';
import 'appearance_page.dart';

/// Skaner sozlamalari (qurilmada saqlanadi).
class ScannerPrefs {
  ScannerPrefs._();

  static bool autoCapture = true;
  static bool sound = true;
  static bool continuous = true;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    autoCapture = prefs.getBool('scan.auto') ?? true;
    sound = prefs.getBool('scan.sound') ?? true;
    continuous = prefs.getBool('scan.continuous') ?? true;
  }

  static Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('scan.auto', autoCapture);
    await prefs.setBool('scan.sound', sound);
    await prefs.setBool('scan.continuous', continuous);
  }
}

/// «Yana» guruhi: sarlavha (to'da nomi) va bandlar.
class MenuGroup {
  const MenuGroup(this.title, this.items);

  final String? title;
  final List<Widget> items;
}

/// «Yana» bandi: bo'lim rangidagi belgi plitkasi, nom, ixtiyoriy izoh va son.
class MenuTile extends StatelessWidget {
  const MenuTile({super.key, required this.icon, required this.label, this.color, this.subtitle, this.onTap, this.page, this.badge = 0, this.danger = false});

  final IconData icon;
  final String label;
  final Color? color;
  final String? subtitle;
  final VoidCallback? onTap;

  /// Bosilganda ochiladigan sahifa ([onTap] bo'lmasa).
  final Widget? page;
  final int badge;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final tone = danger ? AppColors.danger : (color ?? AppColors.muted);
    final target = page;
    return ListTile(
      leading: IconTile(icon: icon, colors: danger || color != null ? tileOf(tone) : StatusColors(AppColors.muted, AppColors.sunken), size: 36),
      title: Text(label, style: TextStyle(fontWeight: FontWeight.w500, color: danger ? AppColors.danger : AppColors.ink)),
      subtitle: subtitle == null || subtitle!.isEmpty ? null : Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: danger
          ? null
          : Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
              if (badge > 0) Badge(label: Text(badge > 99 ? '99+' : '$badge'), backgroundColor: AppColors.dangerFill, textColor: Colors.white),
              Icon(Icons.chevron_right, color: AppColors.subtle),
            ]),
      onTap: onTap ?? (target == null ? null : () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => target))),
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.extra = const <Widget>[], this.groups = const <MenuGroup>[]});

  /// Rolga xos qo'shimcha bandlar (eski ko'rinish: bitta guruh).
  final List<Widget> extra;

  /// Bo'limlar to'dalar bo'yicha (3.8).
  final List<MenuGroup> groups;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  void initState() {
    super.initState();
    ScannerPrefs.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  Widget _group(String? title, List<Widget> items) {
    final children = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      if (i > 0) children.add(const Divider(indent: 68));
      children.add(items[i]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      if (title != null) SectionTitle(title) else const SizedBox(height: 16),
      AppCard(padding: const EdgeInsets.symmetric(vertical: 4), child: Column(children: children)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context);
    final membership = session.membership;
    final choice = session.themeChoice;
    final appearance = <String>[
      tr(templateLabels[choice.template] ?? choice.template),
      tr(accentOf(choice.accent).label),
      tr(modeLabels[choice.mode] ?? choice.mode),
    ].join(', ');
    return Scaffold(
      appBar: pageBar(context, title: Text(tr('Yana'))),
      body: ListView(
        padding: readable(context, const EdgeInsets.fromLTRB(16, 16, 16, 32)),
        children: <Widget>[
          AppCard(
            tone: AppColors.accent,
            child: Row(children: <Widget>[
              Avatar(session.userName, size: 52),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  Text(session.userName, style: AppTheme.title(size: 19)),
                  const SizedBox(height: 2),
                  Text(
                    <String>[if (membership != null) roleLabel(membership.role), session.organizationName].where((item) => item.isNotEmpty).join(', '),
                    style: TextStyle(color: AppColors.muted, fontSize: 13.5),
                  ),
                ]),
              ),
            ]),
          ),
          if (widget.extra.isNotEmpty) _group(null, widget.extra),
          for (final group in widget.groups)
            if (group.items.isNotEmpty) _group(group.title, group.items),
          _group(tr('Sozlamalar'), <Widget>[
            MenuTile(
              icon: Icons.palette_outlined,
              color: AppColors.accent,
              label: tr("Ko'rinish"),
              subtitle: appearance,
              page: const AppearancePage(),
            ),
            ListTile(
              leading: IconTile(icon: Icons.language, colors: StatusColors(AppColors.muted, AppColors.sunken), size: 36),
              title: Text(tr('Til')),
              trailing: DropdownButton<String>(
                value: I18n.locale,
                underline: const SizedBox(),
                items: I18n.codes.map((code) => DropdownMenuItem<String>(value: code, child: Text(I18n.labels[code] ?? code))).toList(),
                onChanged: (code) {
                  if (code != null) session.setLocale(code);
                },
              ),
            ),
            if (session.memberships.length > 1)
              MenuTile(
                icon: Icons.swap_horiz,
                label: tr('Tashkilotni almashtirish'),
                onTap: () => Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(builder: (_) => const OrganizationPicker(inline: true))),
              ),
            if (session.canScan) ...<Widget>[
              SwitchListTile(
                secondary: IconTile(icon: Icons.center_focus_strong_outlined, colors: StatusColors(AppColors.muted, AppColors.sunken), size: 36),
                title: Text(tr("Varaqani o'zi suratga olsin")),
                subtitle: Text(tr("To'rt burchak ko'ringan va rasm tiniq bo'lganda")),
                value: ScannerPrefs.autoCapture,
                onChanged: (value) => setState(() {
                  ScannerPrefs.autoCapture = value;
                  ScannerPrefs.save();
                }),
              ),
              SwitchListTile(
                secondary: IconTile(icon: Icons.volume_up_outlined, colors: StatusColors(AppColors.muted, AppColors.sunken), size: 36),
                title: Text(tr('Ovoz va tebranish')),
                value: ScannerPrefs.sound,
                onChanged: (value) => setState(() {
                  ScannerPrefs.sound = value;
                  ScannerPrefs.save();
                }),
              ),
            ],
          ]),
          _group(tr('Ilova'), <Widget>[
            MenuTile(
              icon: Icons.help_outline,
              label: tr('Yordam'),
              subtitle: tr("Yordam markazi, ko'p beriladigan savollar va murojaat."),
              page: const HelpPage(),
            ),
            AppVersionTile(api: session.api),
            ListTile(
              leading: IconTile(icon: Icons.dns_outlined, colors: StatusColors(AppColors.muted, AppColors.sunken), size: 36),
              title: Text(tr('Tizim manzili')),
              subtitle: Text(session.server),
            ),
            MenuTile(
              icon: Icons.logout,
              label: tr('Chiqish'),
              danger: true,
              onTap: () async {
                if (await confirm(context, tr('Hisobdan chiqilsinmi?'), action: tr('Chiqish'), danger: true)) {
                  await session.signOut();
                }
              },
            ),
          ]),
          const SizedBox(height: 24),
          Center(child: Text('EduX ${PushService.appVersion}', style: TextStyle(color: AppColors.subtle, fontSize: 12))),
        ],
      ),
    );
  }
}
