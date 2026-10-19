// Yutuqlarim (o'quvchi): XP, daraja, ketma-ket kunlar, nishonlar, so'nggi XP va haftalik reyting (guruhdoshlar orasida).
import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'fun_labels.dart';

class AchievementsPage extends StatelessWidget {
  const AchievementsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final api = AppScope.of(context).api;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Yutuqlarim'))),
      body: AsyncView<Map<String, dynamic>>(
        load: () async => asMap(await api.get('my/achievements')),
        builder: (context, data, reload) {
          final level = asMap(data['level']);
          final badges = asList(data['badges'], 'badges');
          final recent = asList(data['recent'], 'recent');
          final board = asList(data['leaderboard'], 'leaderboard');
          final earned = badges.where((item) => item['earned_at'] != null).length;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: <Widget>[
              _LevelCard(xp: asInt(data['xp']), level: level),
              const SizedBox(height: 10),
              StatGrid(children: <Widget>[
                StatCard(label: tr('Shu hafta'), value: '+${asInt(data['week_xp'])} XP', icon: Icons.trending_up_rounded, color: AppColors.success),
                StatCard(
                  label: tr('Ketma-ket kunlar'),
                  value: '${asInt(data['streak'])}',
                  icon: Icons.local_fire_department_rounded,
                  color: AppColors.warning,
                ),
              ]),
              SectionTitle(tr('Nishonlar'), trailing: Text('$earned / ${badges.length}', style: TextStyle(color: AppColors.muted))),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.82,
                children: <Widget>[for (final badge in badges) _BadgeTile(badge: badge)],
              ),
              if (board.isNotEmpty) ...<Widget>[
                SectionTitle(tr('Haftalik reyting')),
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(children: <Widget>[
                    for (var i = 0; i < board.length; i++) ...<Widget>[
                      if (i > 0) const Divider(),
                      _BoardRow(row: board[i]),
                    ],
                  ]),
                ),
              ],
              if (recent.isNotEmpty) ...<Widget>[
                SectionTitle(tr("So'nggi XP")),
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(children: <Widget>[
                    for (var i = 0; i < recent.length; i++) ...<Widget>[
                      if (i > 0) const Divider(),
                      ListTile(
                        dense: true,
                        title: Text(tr(asText(recent[i]['label'])), style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(<String>[
                          if (asText(recent[i]['note']).isNotEmpty) tr(asText(recent[i]['note'])),
                          dateTime(recent[i]['at']),
                        ].join(' · ')),
                        trailing: Text('+${asInt(recent[i]['points'])}',
                            style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.success, fontSize: 16)),
                      ),
                    ],
                  ]),
                ),
              ],
              if (recent.isEmpty && badges.every((item) => item['earned_at'] == null))
                EmptyState(
                  icon: Icons.emoji_events_outlined,
                  text: tr("Test topshiring, o'yin o'ynang yoki laboratoriya topshirig'ini bajaring — XP va nishonlar shu yerda to'planadi."),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _LevelCard extends StatelessWidget {
  const _LevelCard({required this.xp, required this.level});

  final int xp;
  final Map<String, dynamic> level;

  @override
  Widget build(BuildContext context) {
    final progress = (asInt(level['progress']) / 100).clamp(0.0, 1.0).toDouble();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(gradient: AppColors.gradient, borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Row(children: <Widget>[
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: Colors.white.withAlpha(46), shape: BoxShape.circle),
            child: Text('${asInt(level['level'], 1)}', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text(tr('{0}-daraja', <Object?>[asInt(level['level'], 1)]), style: const TextStyle(color: Colors.white70)),
              Text(tr(asText(level['title'])), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
            ]),
          ),
          Text('$xp XP', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 10,
            backgroundColor: Colors.white.withAlpha(56),
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        ),
        const SizedBox(height: 6),
        Text(tr('Keyingi darajagacha: {0} XP', <Object?>[(asInt(level['next']) - xp).clamp(0, 1 << 30)]),
            style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
      ]),
    );
  }
}

class _BadgeTile extends StatelessWidget {
  const _BadgeTile({required this.badge});

  final Map<String, dynamic> badge;

  @override
  Widget build(BuildContext context) {
    final earned = badge['earned_at'] != null;
    final color = earned ? AppColors.sun : AppColors.muted;
    return AppCard(
      padding: const EdgeInsets.all(10),
      color: earned ? null : AppColors.surface,
      onTap: () => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: Icon(badgeIcon(asText(badge['icon'])), color: color, size: 40),
          title: Text(tr(asText(badge['name']))),
          content: Text(
            earned
                ? '${tr(asText(badge['description']))}\n\n${tr('Olingan: {0}', <Object?>[date(badge['earned_at'])])}'
                : tr(asText(badge['description'])),
            textAlign: TextAlign.center,
          ),
          actions: <Widget>[TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Yopish')))],
        ),
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: color.withAlpha(earned ? 46 : 26), shape: BoxShape.circle),
          child: Icon(earned ? badgeIcon(asText(badge['icon'])) : Icons.lock_outline_rounded, color: color),
        ),
        const SizedBox(height: 8),
        Text(tr(asText(badge['name'])),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: earned ? AppColors.ink : AppColors.muted)),
      ]),
    );
  }
}

class _BoardRow extends StatelessWidget {
  const _BoardRow({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final me = row['me'] == true;
    final rank = asInt(row['rank']);
    return Container(
      color: me ? AppColors.soft(AppColors.brand) : null,
      child: ListTile(
        dense: true,
        leading: CircleAvatar(
          radius: 16,
          backgroundColor: (rank <= 3 ? AppColors.sun : AppColors.muted).withAlpha(40),
          child: Text('$rank', style: TextStyle(fontWeight: FontWeight.w800, color: rank <= 3 ? AppColors.warning : AppColors.muted)),
        ),
        title: Text(me ? '${asText(row['name'])} (${tr('siz')})' : asText(row['name']),
            style: TextStyle(fontWeight: me ? FontWeight.w800 : FontWeight.w600)),
        subtitle: Text(tr('{0}-daraja', <Object?>[asInt(row['level'], 1)])),
        trailing: Text('${asInt(row['xp'])} XP', style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
    );
  }
}
