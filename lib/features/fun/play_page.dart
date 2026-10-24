// O'yin qobig'i: seansni boshlaydi (POST my/games, v: 2), umumiy vaqtni ko'rsatadi, yurishlarni serverga yuboradi
// (POST my/games/{id}/answer) va natijani chiqaradi (POST my/games/{id}/finish). O'yinning o'zi — games/*.dart.
// Javob kaliti klientda yo'q; vaqt server soatida ham tekshiriladi (kech javob hisoblanmaydi).
import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/games.dart';
import '../../core/i18n.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'fun_labels.dart';
import 'games/bank_games.dart';
import 'games/crossword_math.dart';
import 'games/game_host.dart';
import 'games/result_view.dart';
import 'games/word_games.dart';

/// O'yin kodi → ekran.
Widget gameBoard(String game, GameHost host, {Key? key}) {
  switch (game) {
    case 'quiz':
      return QuizBoard(key: key, host: host);
    case 'truefalse':
      return TrueFalseBoard(key: key, host: host);
    case 'millionaire':
      return MillionaireBoard(key: key, host: host);
    case 'survival':
      return SurvivalBoard(key: key, host: host);
    case 'duel':
      return DuelBoard(key: key, host: host);
    case 'match':
      return MatchBoard(key: key, host: host);
    case 'memory':
      return MemoryBoard(key: key, host: host);
    case 'scramble':
      return ScrambleBoard(key: key, host: host);
    case 'hangman':
      return HangmanBoard(key: key, host: host);
    case 'crossword':
      return CrosswordBoard(key: key, host: host);
    case 'typing':
      return TypingBoard(key: key, host: host);
    case 'flashcards':
      return FlashcardsBoard(key: key, host: host);
    case 'mathsprint':
      return MathSprintBoard(key: key, host: host);
    case 'sequence':
      return SequenceBoard(key: key, host: host);
    default:
      // sorting, numsort
      return SortingBoard(key: key, host: host);
  }
}

class PlayPage extends StatefulWidget {
  const PlayPage({super.key, required this.game, this.id, required this.title, this.lessonId, this.onFinished});

  final String game;

  /// Manba: fan id (bank), so'z to'plami id (words) yoki daraja 1–4 (math). Darsdagi o'yinda kerak emas.
  final int? id;
  final String title;

  /// Darsga biriktirilgan o'yin: manba darsdan olinadi.
  final int? lessonId;

  /// O'yin yakunlanganda (darsni o'tilgan deb belgilash uchun).
  final ValueChanged<GameResult>? onFinished;

  @override
  State<PlayPage> createState() => _PlayPageState();
}

class _PlayPageState extends State<PlayPage> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _session = <String, dynamic>{};
  GameResult? _result;
  bool _finishing = false;
  DateTime _started = DateTime.now();
  Timer? _ticker;
  final ValueNotifier<int?> _left = ValueNotifier<int?>(null);
  final ValueNotifier<DateTime> _clock = ValueNotifier<DateTime>(DateTime.now());
  GameHost? _host;
  int _round = 0;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _left.dispose();
    _clock.dispose();
    super.dispose();
  }

  int? get _seconds => _session['seconds'] == null ? null : asInt(_session['seconds']);

  Future<void> _start() async {
    _ticker?.cancel();
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    try {
      final api = AppScope.read(context).api;
      final data = asMap(await api.post('my/games', gameStartBody(widget.game, id: widget.id, lessonId: widget.lessonId)));
      if (!mounted) return;
      setState(() {
        _session = data;
        _started = DateTime.now();
        _left.value = _seconds;
        _round++;
        _host = GameHost(
          session: data,
          send: _send,
          finish: _finish,
          left: _left,
          clock: _clock,
          imageUrl: api.absolute,
        );
        _loading = false;
      });
      _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    }
  }

  void _tick() {
    if (!mounted || _result != null) return;
    final now = DateTime.now();
    _clock.value = now;
    final seconds = _seconds;
    if (seconds == null) return;
    final left = (seconds - now.difference(_started).inSeconds).clamp(0, seconds);
    if (_left.value != left) _left.value = left;
    // Vaqt tugadi: o'yin ekrani yakunda yuboriladigan javoblarni beradi (krossvord).
    if (left == 0 && !_finishing) _finish(_host?.timeoutPayload?.call() ?? const <String, Object?>{});
  }

  Future<Map<String, dynamic>?> _send(Map<String, Object?> body) async {
    if (_session.isEmpty || _result != null) return null;
    try {
      return asMap(await AppScope.read(context).api.post('my/games/${asInt(_session['session_id'])}/answer', body));
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
      return null;
    }
  }

  Future<void> _finish([Map<String, Object?> extra = const <String, Object?>{}]) async {
    if (_finishing || _result != null || _session.isEmpty) return;
    _finishing = true;
    _ticker?.cancel();
    try {
      final data = asMap(await AppScope.read(context).api.post('my/games/${asInt(_session['session_id'])}/finish', extra));
      final result = GameResult.fromJson(data);
      if (!mounted) return;
      setState(() => _result = result);
      widget.onFinished?.call(result);
    } on ApiException catch (error) {
      if (mounted) {
        showMessage(context, error.message, error: true, actionLabel: tr('Qayta urinish'), onAction: () => _finish(extra));
        // Natija saqlanmadi — o'yin ekrani ochiq qoladi, taymer davom etadi (qayta urinish mumkin).
        _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
      }
    } finally {
      _finishing = false;
    }
  }

  Future<bool> _confirmLeave() async {
    if (_result != null || _session.isEmpty || _loading) return true;
    return confirm(context, tr("O'yinni tark etasizmi? Natija saqlanmaydi."), action: tr('Chiqish'), danger: true);
  }

  @override
  Widget build(BuildContext context) {
    final playing = !_loading && _result == null && _session.isNotEmpty;
    return PopScope(
      canPop: !playing,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: pageBar(context,
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(tr(gameTitleLabels[widget.game] ?? widget.game)),
            if (widget.title.isNotEmpty)
              Text(widget.title, style: TextStyle(fontSize: 12.5, color: AppColors.muted, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
          ]),
          actions: <Widget>[
            if (playing)
              ValueListenableBuilder<int?>(
                valueListenable: _left,
                builder: (context, left, _) {
                  if (left == null) return const SizedBox();
                  final low = left <= 10;
                  return Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: Center(
                      child: Semantics(
                        label: tr('Qolgan vaqt: {0}', <Object?>[clock(left)]),
                        child: Row(children: <Widget>[
                          Icon(Icons.timer_outlined, size: 20, color: low ? AppColors.danger : AppColors.onChrome),
                          const SizedBox(width: 4),
                          Text(clock(left),
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                                color: low ? AppColors.danger : AppColors.onChrome,
                              )),
                        ]),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
        body: SafeArea(top: false, child: _body()),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final result = _result;
    if (result != null) {
      return GameResultView(
        result: result,
        onAgain: _start,
        closeLabel: widget.lessonId != null ? tr('Darsga qaytish') : null,
      );
    }
    final host = _host;
    if (_session.isEmpty || host == null) {
      return ErrorState(message: _error ?? tr("O'yinni boshlab bo'lmadi."), onRetry: _start);
    }
    return AbsorbPointer(absorbing: _finishing, child: gameBoard(widget.game, host, key: ValueKey<int>(_round)));
  }
}
