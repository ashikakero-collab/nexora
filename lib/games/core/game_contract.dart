import 'package:flutter/widgets.dart';

import 'net_link.dart';

export 'net_link.dart';

/// ===================== NEXORA GAME CONTRACT (STEP_16) =====================
/// Every Arcade game is an independent module under lib/games/<id>/.
///  * Pure-Dart rules engine in lib/games/<id>/core/ (no Flutter/Flame imports,
///    deterministic, unit-tested; the same logic will run server-side online).
///  * Rendering (Flame or Flutter CustomPainter) + UI in lib/games/<id>/ui/.
///  * One entry function `Widget build<Name>Game(GameLaunch launch)` in
///    lib/games/<id>/<id>_entry.dart registered in game_registry.dart.
///  * When a match ends the game calls `launch.onFinish(GameResult(...))` exactly
///    once. The host shows the result screen, awards XP/coins and offers rematch.
///  * The host draws the exit button (top-start corner, 56x56 safe area): keep
///    that corner free of important UI.
/// ==========================================================================

enum GameMode {
  /// Against offline AI.
  vsBot,

  /// Pass-and-play / same-device multiplayer.
  local,

  /// Online match: [GameLaunch.net] carries the move link, seats are global.
  online,
}

enum BotDifficulty { easy, normal, hard }

enum GameOutcome { win, loss, draw }

class GameLaunch {
  const GameLaunch({
    required this.gameId,
    required this.mode,
    required this.difficulty,
    required this.playerName,
    required this.isFa,
    required this.fancyEffects,
    required this.reducedMotion,
    required this.soundOn,
    required this.onFinish,
    this.playerCount = 2,
    this.skins = const {},
    this.seed,
    this.net,
    this.tournamentMatchId,
  });

  final String gameId;
  final GameMode mode;
  final BotDifficulty difficulty;

  /// Display name of the local player (from Personal Orbit identity).
  final String playerName;
  final bool isFa;

  /// false on Low quality or Reduced Motion: drop particles/trails/shake.
  final bool fancyEffects;
  final bool reducedMotion;
  final bool soundOn;

  /// Total seats (2..6 depending on the game). Seat 0 is always the local player.
  final int playerCount;

  /// Equipped cosmetic items, e.g. {'puck': 'puck_nx_green', 'striker': 'striker_soccer', 'cue': 'cue_classic'}.
  final Map<String, String> skins;
  final int? seed;

  /// Call exactly once at the end of the match.
  final void Function(GameResult result) onFinish;

  /// Online link (null offline). Seats are global: [mySeat] is this phone.
  final NetLink? net;

  /// Optional tournament match this game is played for (null for normal matches).
  /// Games pass it back in [GameResult.tournamentMatchId].
  final String? tournamentMatchId;

  bool get vsBot => mode == GameMode.vsBot;
  bool get online => net != null;
  int get mySeat => net?.mySeat ?? 0;

  /// True when this phone controls [seat] by touch (local pass-and-play: every seat).
  bool controlsSeat(int seat) => net == null ? true : seat == net!.mySeat;

  /// True when [seat] is played by another phone.
  bool isRemoteSeat(int seat) => net != null && seat != net!.mySeat;

  /// Online name for a seat, or null offline.
  String? netName(int seat) {
    final NetLink? n = net;
    if (n == null || seat < 0 || seat >= n.names.length) return null;
    return n.names[seat];
  }
  String tx(String fa, String en) => isFa ? fa : en;
}

class GameResult {
  const GameResult({
    required this.outcome,
    this.score = 0,
    this.opponentScore = 0,
    this.summaryFa = '',
    this.summaryEn = '',
    this.winnerSeats,
    this.scores,
    this.tournamentMatchId,
  });

  /// Tournament match id from [GameLaunch.tournamentMatchId] (null for normal matches).
  final String? tournamentMatchId;

  /// Goals / points of the local player and of the opponent (aliases of [score] / [opponentScore]).
  int get goalsFor => score;
  int get goalsAgainst => opponentScore;

  /// Online: winning global seats (empty = draw) and per-seat scores, reported to the server.
  final List<int>? winnerSeats;
  final List<int>? scores;

  /// Outcome from the local player's (seat 0) perspective. In local
  /// pass-and-play report win if seat 0 won.
  final GameOutcome outcome;
  final int score;
  final int opponentScore;
  final String summaryFa;
  final String summaryEn;
}

/// Metadata shown in the Arcade lobby.
class GameInfo {
  const GameInfo({
    required this.id,
    required this.nameFa,
    required this.nameEn,
    required this.taglineFa,
    required this.taglineEn,
    required this.rulesFa,
    required this.rulesEn,
    required this.minPlayers,
    required this.maxPlayers,
    required this.builder,
    required this.accent,
    this.supportsLocal = true,
    this.defaultPlayers = 2,
    this.supportsOnline = false,
  });

  /// Online multiplayer (lobby, rooms, matchmaking) is wired for this game.
  final bool supportsOnline;

  final String id;
  final String nameFa;
  final String nameEn;
  final String taglineFa;
  final String taglineEn;
  final String rulesFa;
  final String rulesEn;
  final int minPlayers;
  final int maxPlayers;
  final int defaultPlayers;
  final bool supportsLocal;
  final Color accent;
  final Widget Function(GameLaunch launch) builder;
}
