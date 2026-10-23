// «Yana»: profil, tashkilotni almashtirish, til, skaner sozlamalari, «Yordam», chiqish.
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/app_update.dart';
import '../../core/design.dart';
import '../../core/i18n.dart';
import '../../core/push.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/organization_picker.dart';
import '../help/help_pages.dart';

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

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.extra = const <Widget>[]});

  /// Rolga xos qo'shimcha bandlar (davomat, to'lov va h.k.) — ro'yxat boshida.
  final List<Widget> extra;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  /// Ko'rinish tanlovi (veb: Profil → Ko'rinish): darhol qo'llanadi va hisobga saqlanadi.
  Widget _choice(Session session, String field, String title, IconData icon, Map<String, String> labels) {
    final current = session.themeChoice.toJson()[field];
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: DropdownButton<String>(
        value: labels.containsKey(current) ? current : labels.keys.first,
        underline: const SizedBox(),
        items: labels.entries.map((entry) => DropdownMenuItem<String>(value: entry.key, child: Text(tr(entry.value)))).toList(),
        onChanged: (value) {
          if (value != null) session.setAppearance(<String, String?>{field: value});
        },
      ),
    );
  }

  Widget _accentTile(Session session) {
    final current = session.themeChoice.accent;
    return ListTile(
      leading: const Icon(Icons.color_lens_outlined),
      title: Text(tr('Asosiy rang')),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Wrap(spacing: 10, runSpacing: 8, children: <Widget>[
          for (final accent in accents)
            Semantics(
              label: tr(accent.label),
              selected: accent.key == current,
              button: true,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => session.setAppearance(<String, String?>{'accent': accent.key}),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: accent.from,
                    shape: BoxShape.circle,
                    border: Border.all(color: accent.key == current ? AppColors.ink : Colors.transparent, width: 2.5),
                  ),
                  child: accent.key == current ? const Icon(Icons.check, size: 18, color: Colors.white) : null,
                ),
              ),
            ),
        ]),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    ScannerPrefs.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context);
    final membership = session.membership;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Yana'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          AppCard(
            child: Row(children: <Widget>[
              Avatar(session.userName, size: 48),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  Text(session.userName, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    <String>[if (membership != null) roleLabel(membership.role), session.organizationName]
                        .where((item) => item.isNotEmpty)
                        .join(' · '),
                    style: TextStyle(color: AppColors.muted),
                  ),
                ]),
              ),
            ]),
          ),
          if (widget.extra.isNotEmpty) ...<Widget>[
            const SizedBox(height: 16),
            AppCard(padding: EdgeInsets.zero, child: Column(children: widget.extra)),
          ],
          const SizedBox(height: 16),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(children: <Widget>[
              ListTile(
                leading: const Icon(Icons.language),
                title: Text(tr('Til')),
                trailing: DropdownButton<String>(
                  value: I18n.locale,
                  underline: const SizedBox(),
                  items: I18n.codes
                      .map((code) => DropdownMenuItem<String>(value: code, child: Text(I18n.labels[code] ?? code)))
                      .toList(),
                  onChanged: (code) {
                    if (code != null) session.setLocale(code);
                  },
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.dark_mode_outlined),
                title: Text(tr('Rejim')),
                trailing: DropdownButton<String>(
                  value: <String>['light', 'dark', 'system'].contains(session.themeMode) ? session.themeMode : 'system',
                  underline: const SizedBox(),
                  items: <DropdownMenuItem<String>>[
                    DropdownMenuItem<String>(value: 'light', child: Text(tr('Kunduzgi'))),
                    DropdownMenuItem<String>(value: 'dark', child: Text(tr('Tungi'))),
                    DropdownMenuItem<String>(value: 'system', child: Text(tr('Qurilmaga qarab'))),
                  ],
                  onChanged: (mode) {
                    if (mode != null) session.setThemeMode(mode);
                  },
                ),
              ),
              const Divider(),
              _choice(session, 'size', tr("Shrift o'lchami"), Icons.format_size, sizeLabels),
              if (session.canCustomizeTheme) ...<Widget>[
                const Divider(),
                _accentTile(session),
                const Divider(),
                _choice(session, 'template', tr('Shablon'), Icons.dashboard_customize_outlined, templateLabels),
                const Divider(),
                _choice(session, 'font', tr('Shrift'), Icons.font_download_outlined, fontLabels),
                const Divider(),
                _choice(session, 'radius', tr('Burchaklar'), Icons.rounded_corner, radiusLabels),
                const Divider(),
                _choice(session, 'icons', tr('Menyu ikonalari'), Icons.palette_outlined, iconsLabels),
              ],
              if (session.memberships.length > 1) ...<Widget>[
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.swap_horiz),
                  title: Text(tr('Tashkilotni almashtirish')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context, rootNavigator: true)
                      .push(MaterialPageRoute<void>(builder: (_) => const OrganizationPicker(inline: true))),
                ),
              ],
              if (session.canScan) ...<Widget>[
                const Divider(),
                SwitchListTile(
                  secondary: const Icon(Icons.center_focus_strong_outlined),
                  title: Text(tr("Varaqani o'zi suratga olsin")),
                  subtitle: Text(tr("To'rt burchak ko'ringan va rasm tiniq bo'lganda")),
                  value: ScannerPrefs.autoCapture,
                  onChanged: (value) => setState(() {
                    ScannerPrefs.autoCapture = value;
                    ScannerPrefs.save();
                  }),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.volume_up_outlined),
                  title: Text(tr('Ovoz va tebranish')),
                  value: ScannerPrefs.sound,
                  onChanged: (value) => setState(() {
                    ScannerPrefs.sound = value;
                    ScannerPrefs.save();
                  }),
                ),
              ],
            ]),
          ),
          const SizedBox(height: 16),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(children: <Widget>[
              ListTile(
                leading: const Icon(Icons.help_outline),
                title: Text(tr('Yordam')),
                subtitle: Text(tr("Yordam markazi, ko'p beriladigan savollar va murojaat.")),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const HelpPage())),
              ),
              const Divider(),
              AppVersionTile(api: session.api),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.dns_outlined),
                title: Text(tr('Tizim manzili')),
                subtitle: Text(session.server),
              ),
              const Divider(),
              ListTile(
                leading: Icon(Icons.logout, color: AppColors.danger),
                title: Text(tr('Chiqish'), style: TextStyle(color: AppColors.danger)),
                onTap: () async {
                  if (await confirm(context, tr('Hisobdan chiqilsinmi?'), action: tr('Chiqish'), danger: true)) {
                    await session.signOut();
                  }
                },
              ),
            ]),
          ),
          const SizedBox(height: 24),
          Center(child: Text('EduX ${PushService.appVersion}', style: TextStyle(color: AppColors.muted, fontSize: 12))),
        ],
      ),
    );
  }
}
