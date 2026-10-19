// O'yinlar (o'quvchi): viktorina-blits (fan bo'yicha) va so'z to'plamlari bilan «Juftini top», «So'z yig'ish».
import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'achievements_page.dart';
import 'fun_labels.dart';
import 'play_page.dart';

class GamesPage extends StatefulWidget {
  const GamesPage({super.key});

  @override
  State<GamesPage> createState() => _GamesPageState();
}

class _GamesPageState extends State<GamesPage> {
  final GlobalKey<AsyncViewState<Map<String, dynamic>>> _view = GlobalKey<AsyncViewState<Map<String, dynamic>>>();

  Future<void> _play(String game, int id, String title) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PlayPage(game: game, id: id, title: title)));
    // Yangi rekord ro'yxatda ko'rinsin
    _view.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final api = AppScope.of(context).api;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr("O'yinlar")),
        actions: <Widget>[
          IconButton(
            tooltip: tr('Yutuqlarim'),
            icon: const Icon(Icons.emoji_events_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AchievementsPage())),
          ),
        ],
      ),
      body: AsyncView<Map<String, dynamic>>(
        key: _view,
        load: () async => asMap(await api.get('my/games')),
        builder: (context, data, reload) {
          final subjects = asList(data['subjects'], 'subjects');
          final sets = asList(data['sets'], 'sets');
          if (subjects.isEmpty && sets.isEmpty) {
            return ListView(children: <Widget>[
              EmptyState(
                icon: Icons.sports_esports_outlined,
                text: tr("Hozircha o'yin yo'q. O'qituvchi so'z to'plami qo'shganda yoki savollar bazasi to'lganda o'yinlar shu yerda paydo bo'ladi."),
              ),
            ]);
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: <Widget>[
              if (subjects.isNotEmpty) ...<Widget>[
                SectionTitle(tr('Viktorina-blits')),
                Text(tr("15 ta savol, 90 soniya. Tez va to'g'ri javob — ko'proq ball."), style: TextStyle(color: AppColors.muted, fontSize: 13)),
                const SizedBox(height: 10),
                for (final subject in subjects) ...<Widget>[
                  AppCard(
                    onTap: () => _play('quiz', asInt(subject['id']), asText(subject['name'])),
                    child: Row(children: <Widget>[
                      _GameIcon(game: 'quiz'),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                          Text(asText(subject['name']), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                          Text(tr('{0} ta savol bazada', <Object?>[asInt(subject['count'])]), style: TextStyle(color: AppColors.muted, fontSize: 13)),
                        ]),
                      ),
                      if (subject['best'] != null) _Best(score: asInt(subject['best'])),
                      Icon(Icons.play_arrow_rounded, color: AppColors.brand),
                    ]),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
              if (sets.isNotEmpty) ...<Widget>[
                SectionTitle(tr("So'z to'plamlari")),
                for (final set in sets) ...<Widget>[
                  _SetCard(set: set, onPlay: (game) => _play(game, asInt(set['id']), asText(set['title']))),
                  const SizedBox(height: 10),
                ],
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SetCard extends StatelessWidget {
  const _SetCard({required this.set, required this.onPlay});

  final Map<String, dynamic> set;
  final ValueChanged<String> onPlay;

  @override
  Widget build(BuildContext context) {
    final best = asMap(set['best']);
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        Text(asText(set['title']), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        Text(<String>[
          if (set['subject'] != null) asText(set['subject']),
          tr("{0} ta so'z", <Object?>[asInt(set['count'])]),
        ].join(' · '), style: TextStyle(color: AppColors.muted, fontSize: 13)),
        if (asText(set['description']).isNotEmpty) ...<Widget>[
          const SizedBox(height: 4),
          Text(asText(set['description']), style: const TextStyle(fontSize: 13)),
        ],
        const SizedBox(height: 12),
        Row(children: <Widget>[
          for (final game in <String>['match', 'scramble']) ...<Widget>[
            if (game == 'scramble') const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                onPressed: () => onPlay(game),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10)),
                child: Column(children: <Widget>[
                  Icon(gameIcon(game), color: AppColors.brand),
                  const SizedBox(height: 2),
                  Text(tr(gameTitleLabels[game] ?? game), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
                  if (best[game] != null)
                    Text(tr('Rekord: {0}', <Object?>[asInt(best[game])]), style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
                ]),
              ),
            ),
          ],
        ]),
      ]),
    );
  }
}

class _GameIcon extends StatelessWidget {
  const _GameIcon({required this.game});

  final String game;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(color: AppColors.sun.withAlpha(46), borderRadius: BorderRadius.circular(12)),
      child: Icon(gameIcon(game), color: AppColors.warning),
    );
  }
}

class _Best extends StatelessWidget {
  const _Best({required this.score});

  final int score;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Column(children: <Widget>[
        Text('$score', style: const TextStyle(fontWeight: FontWeight.w800)),
        Text(tr('rekord'), style: TextStyle(fontSize: 11, color: AppColors.muted)),
      ]),
    );
  }
}
