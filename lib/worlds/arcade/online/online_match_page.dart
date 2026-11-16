import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/audio/music_service.dart';
import '../../../core/online/cloud_profile_sync.dart';
import '../../../core/online/match_link.dart';
import '../../../core/online/online_service.dart';
import '../../../core/profile/profile_service.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/theme/nx_theme.dart';
import '../../../games/game_registry.dart';

/// Hosts one online match: opens the move link, builds the game in online mode,
/// rebuilds + replays the log on reconnect/resync, reports the result and shows it.
class OnlineMatchPage extends ConsumerStatefulWidget {
  const OnlineMatchPage(
      {super.key,
      required this.matchId,
      required this.gameId,
      this.tournamentMatchId});
  final String matchId;
  final String gameId;

  /// Set when this game belongs to a tournament match: the result is also reported to the tournament
  /// (nx_t_report — both players' reports must agree, otherwise it becomes a dispute).
  final String? tournamentMatchId;

  @override
  ConsumerState<OnlineMatchPage> createState() => _OnlineMatchPageState();
}

class _OnlineMatchPageState extends ConsumerState<OnlineMatchPage>
    with WidgetsBindingObserver {
  SupabaseMatchLink? _link;
  String? _error;
  int _generation = 0;
  bool _finished = false;
  GameResult? _result;
  String? _resultNoteFa;
  String? _resultNoteEn;
  bool _recorded = false;
  bool _graceStarted = false;

  @override
  void initState() {
    super.initState();
    MusicService.instance.enterGame();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_open());
  }

  Future<void> _open() async {
    final OnlineService o = ref.read(onlineProvider);
    final client = o.client;
    if (client == null) {
      setState(() => _error = 'offline');
      return;
    }
    try {
      final SupabaseMatchLink link =
          await SupabaseMatchLink.open(client, widget.matchId);
      if (!mounted) {
        link.dispose();
        return;
      }
      link.addListener(_onLinkChanged);
      link.resyncRequests.addListener(_onResync);
      setState(() => _link = link);
      if (link.isOver) _onLinkChanged();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from background: rebuild from the server log so this phone catches up exactly.
    if (state == AppLifecycleState.resumed && _link != null && !_finished) {
      _onResync();
    }
  }

  void _onResync() {
    if (!mounted || _finished) return;
    setState(() => _generation++);
  }

  void _onLinkChanged() {
    final SupabaseMatchLink? l = _link;
    if (l == null || !mounted) return;
    final MatchEnd? end = l.end;
    if (end != null && !_finished && !end.isForfeit && !_graceStarted) {
      // Another phone reported the normal end first: our deterministic game ends the same way in a moment.
      _graceStarted = true;
      Future<void>.delayed(const Duration(seconds: 8), () {
        if (mounted && !_finished) _onLinkChanged();
      });
      setState(() {});
      return;
    }
    if (end != null && !_finished) {
      // Ended on the server without our game finishing (forfeit / opponent left).
      final bool won = end.winners.contains(l.mySeat);
      final bool draw = end.winners.isEmpty;
      final int? fs = end.forfeitSeat;
      final String who =
          fs != null && fs >= 0 && fs < l.names.length ? l.names[fs] : '';
      _resultNoteFa = fs == l.mySeat
          ? 'از بازی خارج شدی'
          : (fs != null ? '$who از بازی خارج شد' : null);
      _resultNoteEn = fs == l.mySeat
          ? 'You left the match'
          : (fs != null ? '$who left the match' : null);
      _finish(
          GameResult(
            outcome: draw
                ? GameOutcome.draw
                : (won ? GameOutcome.win : GameOutcome.loss),
            summaryFa: _resultNoteFa ?? '',
            summaryEn: _resultNoteEn ?? '',
          ),
          report: false);
    } else {
      setState(() {});
    }
  }

  List<int> _winnersFor(GameResult r, SupabaseMatchLink l) {
    if (r.winnerSeats != null) return r.winnerSeats!;
    if (r.outcome == GameOutcome.draw) return <int>[];
    if (r.outcome == GameOutcome.win) return <int>[l.mySeat];
    return <int>[
      for (int s = 0; s < l.seatCount; s++)
        if (s != l.mySeat) s
    ];
  }

  void _onGameFinish(GameResult r) => _finish(r, report: true);

  void _finish(GameResult r, {required bool report}) {
    if (_finished) return;
    _finished = true;
    final SupabaseMatchLink? l = _link;
    if (ref.read(settingsProvider).haptics) HapticFeedback.heavyImpact();
    if (l != null && report) {
      unawaited(l
          .report(_winnersFor(r, l), r.scores)
          .then((_) => ref.read(cloudSyncProvider).refreshWallet()));
      if (widget.tournamentMatchId != null) unawaited(_reportTournament(r, l));
    } else {
      unawaited(ref.read(cloudSyncProvider).refreshWallet());
    }
    if (!_recorded) {
      _recorded = true;
      final GameInfo? g = gameById(widget.gameId);
      ref.read(profileProvider).recordOnlineGame(
            gameId: widget.gameId,
            gameNameFa: g?.nameFa ?? widget.gameId,
            gameNameEn: g?.nameEn ?? widget.gameId,
            outcome: switch (r.outcome) {
              GameOutcome.win => 'win',
              GameOutcome.loss => 'loss',
              GameOutcome.draw => 'draw'
            },
            score: r.score,
          );
    }
    Future<void>.delayed(Duration(milliseconds: report ? 900 : 200), () {
      if (mounted) setState(() => _result = r);
    });
  }

  /// Tournament: this phone's own report of the game (seat 0 = home). Retries a few times on bad network.
  Future<void> _reportTournament(GameResult r, SupabaseMatchLink l) async {
    final List<int> winners = _winnersFor(r, l);
    final int winnerSeat = winners.length == 1 ? winners.first : -1;
    final List<int> s = List<int>.filled(l.seatCount < 2 ? 2 : l.seatCount, 0);
    final List<int>? scores = r.scores;
    if (scores != null && scores.length >= 2) {
      s[0] = scores[0];
      s[1] = scores[1];
    } else if (l.mySeat >= 0 && l.mySeat < 2) {
      s[l.mySeat] = r.score;
      s[1 - l.mySeat] = r.opponentScore;
    }
    // keep the report consistent with the winner (the server rejects contradictions)
    if (winnerSeat == 0 && s[0] < s[1]) s[0] = s[1];
    if (winnerSeat == 1 && s[1] < s[0]) s[1] = s[0];
    if (winnerSeat == -1 && s[0] != s[1]) s[1] = s[0];
    for (int attempt = 0; attempt < 4; attempt++) {
      try {
        await ref
            .read(onlineProvider)
            .client
            ?.rpc('nx_t_report', params: <String, dynamic>{
          'p_game': widget.matchId,
          'p_winner_seat': winnerSeat,
          'p_s0': s[0],
          'p_s1': s[1],
        });
        return;
      } catch (e) {
        debugPrint('tournament report failed (try $attempt): $e');
        await Future<void>.delayed(Duration(seconds: 2 * (attempt + 1)));
      }
    }
  }

  Future<bool> _confirmLeave() async {
    if (_finished || _link == null) return true;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(ctx.tx('ترک بازی آنلاین؟', 'Leave the online match?')),
        content: Text(ctx.tx(
            'خروج یعنی تسلیم: در بازی دونفره حریف برنده می‌شود.',
            'Leaving counts as a forfeit: in a 2-player game your opponent wins.')),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(ctx.tx('ادامه', 'Keep playing'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: NxColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.tx('تسلیم و خروج', 'Forfeit & leave')),
          ),
        ],
      ),
    );
    if (ok == true) {
      _finished = true;
      await _link?.forfeit();
      return true;
    }
    return false;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final SupabaseMatchLink? l = _link;
    if (l != null) {
      l.removeListener(_onLinkChanged);
      l.resyncRequests.removeListener(_onResync);
      l.dispose();
    }
    MusicService.instance.exitGame();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppSettings s = ref.watch(settingsProvider);
    final SupabaseMatchLink? l = _link;
    final GameInfo? game = gameById(widget.gameId);
    Widget body;
    if (_error != null) {
      body = Center(
          child: Text(
              context.tx('ورود به بازی ممکن نشد', 'Could not open the match')));
    } else if (l == null || game == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      final GameLaunch launch = GameLaunch(
        gameId: widget.gameId,
        mode: GameMode.online,
        difficulty: BotDifficulty.normal,
        playerName: l.mySeat >= 0 && l.mySeat < l.names.length
            ? l.names[l.mySeat]
            : 'Explorer',
        isFa: s.isFa,
        fancyEffects: s.fancyEffects,
        reducedMotion: s.reducedMotion,
        soundOn: s.sound && s.haptics,
        playerCount: l.seatCount,
        skins: Map<String, String>.from(ref.read(profileProvider).equipped),
        seed: l.seed,
        net: l,
        onFinish: _onGameFinish,
      );
      final Widget gameView = KeyedSubtree(
        key: ValueKey<int>(_generation),
        child: game.builder(launch),
      );
      body = gameView;
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, _) async {
        if (didPop) return;
        final NavigatorState nav = Navigator.of(context);
        if (await _confirmLeave()) nav.pop();
      },
      child: Scaffold(
        backgroundColor: NxColors.navyDeep,
        body: Stack(children: <Widget>[
          Positioned.fill(child: body),
          PositionedDirectional(
            top: MediaQuery.paddingOf(context).top + 6,
            start: 6,
            child: Material(
              color: Colors.black.withValues(alpha: 0.35),
              shape: const CircleBorder(),
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: () async {
                  final NavigatorState nav = Navigator.of(context);
                  if (await _confirmLeave()) nav.pop();
                },
              ),
            ),
          ),
          if (l != null && _result == null)
            PositionedDirectional(
                top: MediaQuery.paddingOf(context).top + 10,
                end: 10,
                child: _presenceBar(l)),
          if (_result != null)
            Positioned.fill(child: _overlay(context, _result!)),
        ]),
      ),
    );
  }

  Widget _presenceBar(SupabaseMatchLink l) {
    return IgnorePointer(
      child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
        for (int s = 0; s < l.seatCount; s++)
          Padding(
            padding: const EdgeInsets.only(left: 3),
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: l.forfeitedSeats.contains(s)
                    ? NxColors.danger
                    : (l.connectedSeats.contains(s)
                        ? NxColors.success
                        : NxColors.gold),
                border: s == l.mySeat
                    ? Border.all(color: Colors.white, width: 1.5)
                    : null,
              ),
            ),
          ),
      ]),
    );
  }

  Widget _overlay(BuildContext context, GameResult r) {
    final (String title, Color color, IconData icon) = switch (r.outcome) {
      GameOutcome.win => (
          context.tx('پیروزی!', 'Victory!'),
          NxColors.gold,
          Icons.emoji_events_rounded
        ),
      GameOutcome.draw => (
          context.tx('مساوی', 'Draw'),
          NxColors.turquoise,
          Icons.handshake_rounded
        ),
      GameOutcome.loss => (
          context.tx('شکست', 'Defeat'),
          NxColors.danger,
          Icons.sentiment_dissatisfied_rounded
        ),
    };
    final String summary = context.tx(r.summaryFa, r.summaryEn);
    final String reward = switch (r.outcome) {
      GameOutcome.win => '+80 XP · +50',
      GameOutcome.draw => '+40 XP · +20',
      GameOutcome.loss => '+20 XP · +8',
    };
    return Container(
      color: Colors.black.withValues(alpha: 0.72),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        Icon(icon, color: color, size: 72),
        const SizedBox(height: 10),
        Text(title,
            style: TextStyle(
                fontSize: 34, fontWeight: FontWeight.w900, color: color)),
        if (summary.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Text(summary,
              textAlign: TextAlign.center,
              style: const TextStyle(color: NxColors.iceWhite)),
        ],
        const SizedBox(height: 10),
        Text(
            '${context.tx('بازی آنلاین ثبت شد', 'Online match recorded')} · $reward 🪙',
            style: const TextStyle(color: NxColors.textDim)),
        if (widget.tournamentMatchId != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
                context.tx(
                    'نتیجه برای تورنمنت ارسال شد؛ با تأیید هر دو بازیکن ثبت می‌شود.',
                    'Result sent to the tournament; it counts once both players agree.'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: NxColors.gold, fontSize: 12)),
          ),
        const SizedBox(height: 22),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(),
          icon: Icon(widget.tournamentMatchId != null
              ? Icons.emoji_events_rounded
              : Icons.meeting_room_rounded),
          label: Text(widget.tournamentMatchId != null
              ? context.tx('بازگشت به تورنمنت', 'Back to the tournament')
              : context.tx('بازگشت به اتاق (بازی دوباره)',
                  'Back to the room (rematch)')),
        ),
      ]),
    );
  }
}
