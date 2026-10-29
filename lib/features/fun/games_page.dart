// O'yinlar katalogi (o'quvchi): 16 ta o'yin manba bo'yicha guruhlangan — savollar bankidan, so'z to'plamlaridan,
// matematika. O'yin tanlanganda manba (fan / to'plam / daraja) rekordlari bilan tanlanadi. GET my/games.
import 'package:flutter/material.dart';

import '../../core/adaptive.dart';
import '../../core/api.dart';
import '../../core/games.dart';
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

  Future<void> _open(Map<String, dynamic> catalog, String game) async {
    final items = gameSourceItems(catalog, game);
    final picked = await showModalBottomSheet<GameSourceItem>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => GameSourceSheet(game: game, items: items),
    );
    if (picked == null || !mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PlayPage(game: game, id: picked.id, title: picked.title)));
    // Yangi rekord ro'yxatda ko'rinsin
    _view.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final api = AppScope.of(context).api;
    return Scaffold(
      appBar: pageBar(context,
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
        builder: (context, data, reload) => GamesCatalog(catalog: data, onOpen: (game) => _open(data, game)),
      ),
    );
  }
}

/// Katalog ro'yxati (skrinshot testlari ham shu vidjetni chizadi).
class GamesCatalog extends StatelessWidget {
  const GamesCatalog({super.key, required this.catalog, required this.onOpen});

  final Map<String, dynamic> catalog;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final games = availableGames(catalog);
    return ListView(
      padding: readable(context, const EdgeInsets.fromLTRB(16, 0, 16, 32), max: kGridWidth),
      children: <Widget>[
        for (final source in gameSourceOrder)
          if (games.any((game) => gameSourceOf(game) == source)) ...<Widget>[
            SectionTitle(tr(gameSourceLabels[source]!)),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
              child: Text(tr(gameSourceHintLabels[source]!), style: TextStyle(color: AppColors.muted, fontSize: 13)),
            ),
            // Telefonda bitta ustun, iPad'da 2–3 ustunli to'r.
            AdaptiveGrid(minTile: 320, minColumns: 1, maxColumns: 3, spacing: 8, children: <Widget>[
              for (final game in games.where((game) => gameSourceOf(game) == source))
                GameCard(game: game, blocked: gameBlockedReason(catalog, game), record: gameBestRecord(catalog, game), onTap: () => onOpen(game)),
            ]),
          ],
      ],
    );
  }
}

Color gameSourceColor(String source) => switch (source) {
      'bank' => AppColors.accent,
      'math' => Koshin.olxori,
      _ => Koshin.pista,
    };


class GameCard extends StatelessWidget {
  const GameCard({super.key, required this.game, required this.onTap, this.blocked, this.record});

  final String game;
  final VoidCallback onTap;

  /// Manba yo'q — sababi (lug'at kaliti).
  final String? blocked;
  final int? record;

  @override
  Widget build(BuildContext context) {
    final color = gameSourceColor(gameSourceOf(game));
    final disabled = blocked != null;
    return Opacity(
      opacity: disabled ? 0.65 : 1,
      child: AppCard(
        onTap: disabled ? () => showMessage(context, tr(blocked!)) : onTap,
        padding: const EdgeInsets.all(14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          IconTile(icon: gameIcon(game), colors: StatusColors(Colors.white, color), size: 46),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text(tr(gameTitleLabels[game] ?? game), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.ink)),
              const SizedBox(height: 2),
              Text(tr(gameDescriptionLabels[game] ?? ''), style: TextStyle(color: AppColors.muted, fontSize: 13, height: 1.3)),
              if (disabled) ...<Widget>[
                const SizedBox(height: 6),
                Row(children: <Widget>[
                  Icon(Icons.info_outline_rounded, size: 15, color: AppColors.warning),
                  const SizedBox(width: 4),
                  Expanded(child: Text(tr(blocked!), style: TextStyle(color: AppColors.warning, fontSize: 12.5, fontWeight: FontWeight.w600))),
                ]),
              ],
            ]),
          ),
          if (!disabled) ...<Widget>[
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: <Widget>[
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22),
              ),
              if (record != null) ...<Widget>[
                const SizedBox(height: 6),
                Text('$record', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.ink, fontFeatures: AppTheme.tabular)),
                Text(tr('rekord'), style: TextStyle(fontSize: 11, color: AppColors.subtle)),
              ],
            ]),
          ],
        ]),
      ),
    );
  }
}

/// Manba tanlash: fan, so'z to'plami yoki daraja — har birida shu o'yindagi rekord.
class GameSourceSheet extends StatelessWidget {
  const GameSourceSheet({super.key, required this.game, required this.items});

  final String game;
  final List<GameSourceItem> items;

  @override
  Widget build(BuildContext context) {
    final source = gameSourceOf(game);
    final prompt = switch (source) {
      'bank' => tr('Fanni tanlang'),
      'math' => tr('Darajani tanlang'),
      _ => tr("So'z to'plamini tanlang"),
    };
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: <Widget>[
          Row(children: <Widget>[
            Icon(gameIcon(game), color: gameSourceColor(source)),
            const SizedBox(width: 8),
            Expanded(child: Text(tr(gameTitleLabels[game] ?? game), style: AppTheme.title(size: 18))),
          ]),
          const SizedBox(height: 4),
          Text(tr(gameDescriptionLabels[game] ?? ''), style: TextStyle(color: AppColors.muted, fontSize: 13)),
          const SizedBox(height: 14),
          Text(prompt, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (items.isEmpty) EmptyState(text: tr("So'z to'plami kerak — o'qituvchidan so'rang.")),
          for (final item in items) ...<Widget>[
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              onTap: () => Navigator.of(context).pop(item),
              child: Row(children: <Widget>[
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                    Text(tr(item.title), style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
                    if (item.subtitle.isNotEmpty)
                      Text(
                        source == 'bank' ? tr('{0} ta savol bazada', <Object?>[item.subtitle]) : (source == 'words' ? _setSubtitle(item.subtitle) : item.subtitle),
                        style: TextStyle(color: AppColors.muted, fontSize: 12.5),
                      ),
                  ]),
                ),
                if (item.record != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Column(children: <Widget>[
                      Text('${item.record}', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.ink)),
                      Text(tr('rekord'), style: TextStyle(fontSize: 11, color: AppColors.muted)),
                    ]),
                  ),
                Icon(Icons.play_arrow_rounded, color: AppColors.brand),
              ]),
            ),
            const SizedBox(height: 8),
          ],
        ]),
      ),
    );
  }

  /// «Ingliz tili · 12» → «Ingliz tili · 12 ta so'z».
  static String _setSubtitle(String subtitle) {
    final parts = subtitle.split(' · ');
    final count = parts.removeLast();
    return <String>[...parts, tr("{0} ta so'z", <Object?>[count])].join(', ');
  }
}
