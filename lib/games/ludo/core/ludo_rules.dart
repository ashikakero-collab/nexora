import 'dart:math';

/// Pure-Dart Ludo rules (no Flutter imports, deterministic).
///
/// Token progress (relative to its owner):
///   -1        in base
///   0..50     on the 52-square main track (0 = own start square)
///   51..55    own home column
///   56        finished (home)
/// Global main-track square = (13 * corner + progress) % 52.
/// Corners: 0 = top-left, 1 = top-right, 2 = bottom-right, 3 = bottom-left.

const int kLudoBase = -1;
const int kLudoLastTrack = 50;
const int kLudoHome = 56;
const int kLudoTrackLen = 52;
const int kLudoTokens = 4;

class LudoCapture {
  const LudoCapture(this.seat, this.token, this.from);
  final int seat;
  final int token;
  final int from;
}

class LudoMove {
  const LudoMove({
    required this.seat,
    required this.token,
    required this.from,
    required this.to,
    this.captures = const <LudoCapture>[],
  });

  final int seat;
  final int token;
  final int from;
  final int to;
  final List<LudoCapture> captures;

  bool get leavesBase => from == kLudoBase;
  bool get finishes => to == kLudoHome;

  @override
  String toString() => 'LudoMove(s$seat t$token $from->$to x${captures.length})';
}

class LudoState {
  LudoState({
    required this.playerCount,
    required this.corners,
    required this.tokens,
    this.turn = 0,
    this.sixStreak = 0,
    this.winner,
  });

  factory LudoState.initial(int playerCount) {
    final int n = playerCount < 2 ? 2 : (playerCount > 4 ? 4 : playerCount);
    return LudoState(
      playerCount: n,
      corners: LudoRules.cornersFor(n),
      tokens: List<List<int>>.generate(
          n, (_) => List<int>.filled(kLudoTokens, kLudoBase)),
    );
  }

  final int playerCount;

  /// Board corner of each seat (seats play in clockwise order).
  final List<int> corners;
  final List<List<int>> tokens;
  int turn;
  int sixStreak;
  int? winner;

  LudoState copy() => LudoState(
        playerCount: playerCount,
        corners: List<int>.from(corners),
        tokens: tokens.map((List<int> t) => List<int>.from(t)).toList(),
        turn: turn,
        sixStreak: sixStreak,
        winner: winner,
      );

  int globalOf(int seat, int progress) =>
      (13 * corners[seat] + progress) % kLudoTrackLen;

  int homeCount(int seat) =>
      tokens[seat].where((int p) => p == kLudoHome).length;

  bool hasWon(int seat) => homeCount(seat) == kLudoTokens;
}

class LudoRules {
  LudoRules._();

  static List<int> cornersFor(int n) {
    if (n <= 2) return <int>[3, 1];
    if (n == 3) return <int>[3, 0, 1];
    return <int>[3, 0, 1, 2];
  }

  static bool isOnTrack(int progress) =>
      progress >= 0 && progress <= kLudoLastTrack;

  /// Start squares and star squares are safe for everyone.
  static bool isSafeGlobal(int g) => g % 13 == 0 || g % 13 == 8;

  static List<LudoMove> legalMoves(LudoState s, int seat, int roll) {
    final List<LudoMove> out = <LudoMove>[];
    for (int t = 0; t < kLudoTokens; t++) {
      final int p = s.tokens[seat][t];
      int to;
      if (p == kLudoHome) continue;
      if (p == kLudoBase) {
        if (roll != 6) continue;
        to = 0;
      } else {
        to = p + roll;
        if (to > kLudoHome) continue;
      }
      out.add(LudoMove(
        seat: seat,
        token: t,
        from: p,
        to: to,
        captures: capturesAt(s, seat, to),
      ));
    }
    return out;
  }

  static List<LudoCapture> capturesAt(LudoState s, int seat, int to) {
    if (!isOnTrack(to)) return const <LudoCapture>[];
    final int g = s.globalOf(seat, to);
    if (isSafeGlobal(g)) return const <LudoCapture>[];
    final List<LudoCapture> caps = <LudoCapture>[];
    for (int o = 0; o < s.playerCount; o++) {
      if (o == seat) continue;
      for (int u = 0; u < kLudoTokens; u++) {
        final int q = s.tokens[o][u];
        if (isOnTrack(q) && s.globalOf(o, q) == g) {
          caps.add(LudoCapture(o, u, q));
        }
      }
    }
    return caps;
  }

  static LudoState apply(LudoState s, LudoMove m) {
    final LudoState n = s.copy();
    n.tokens[m.seat][m.token] = m.to;
    for (final LudoCapture c in m.captures) {
      n.tokens[c.seat][c.token] = kLudoBase;
    }
    if (n.hasWon(m.seat)) n.winner = m.seat;
    return n;
  }

  /// A 6, a capture or bringing a token home earns another roll.
  static bool grantsExtraTurn(LudoMove m, int roll) =>
      roll == 6 || m.captures.isNotEmpty || m.to == kLudoHome;

  /// True if an opponent token could land on [progress] of [seat] next roll.
  static bool isThreatened(LudoState s, int seat, int progress) {
    if (!isOnTrack(progress)) return false;
    final int g = s.globalOf(seat, progress);
    if (isSafeGlobal(g)) return false;
    for (int o = 0; o < s.playerCount; o++) {
      if (o == seat) continue;
      for (final int q in s.tokens[o]) {
        if (!isOnTrack(q)) continue;
        final int d = (g - s.globalOf(o, q) + kLudoTrackLen) % kLudoTrackLen;
        if (d >= 1 && d <= 6 && q + d <= kLudoLastTrack) return true;
      }
    }
    return false;
  }
}

class LudoRollResult {
  const LudoRollResult({
    required this.roll,
    required this.moves,
    this.forfeited = false,
    this.rollAgain = false,
  });
  final int roll;
  final List<LudoMove> moves;

  /// Third six in a row: the turn is lost.
  final bool forfeited;

  /// No move possible but the roll was a 6: same player rolls again.
  final bool rollAgain;

  bool get passes => moves.isEmpty && !rollAgain;
}

class LudoPlayResult {
  const LudoPlayResult({required this.extraTurn, required this.won});
  final bool extraTurn;
  final bool won;
}

/// Turn engine with injectable dice.
class LudoEngine {
  LudoEngine({required int playerCount, int? seed})
      : state = LudoState.initial(playerCount),
        _rng = Random(seed);

  LudoState state;
  final Random _rng;
  int? pendingRoll;

  int rollDie() => _rng.nextInt(6) + 1;

  LudoRollResult roll() => applyRoll(rollDie());

  /// Applies a roll value for the current player (used directly in tests).
  LudoRollResult applyRoll(int r) {
    if (state.winner != null) {
      return LudoRollResult(roll: r, moves: const <LudoMove>[]);
    }
    if (r == 6 && state.sixStreak >= 2) {
      advanceTurn();
      return LudoRollResult(roll: r, moves: const <LudoMove>[], forfeited: true);
    }
    final List<LudoMove> moves = LudoRules.legalMoves(state, state.turn, r);
    if (moves.isEmpty) {
      if (r == 6) {
        state.sixStreak += 1;
        return LudoRollResult(roll: r, moves: moves, rollAgain: true);
      }
      advanceTurn();
      return LudoRollResult(roll: r, moves: moves);
    }
    pendingRoll = r;
    return LudoRollResult(roll: r, moves: moves);
  }

  LudoPlayResult play(LudoMove m) {
    final int r = pendingRoll ?? 0;
    pendingRoll = null;
    state = LudoRules.apply(state, m);
    if (state.winner != null) {
      return const LudoPlayResult(extraTurn: false, won: true);
    }
    final bool extra = LudoRules.grantsExtraTurn(m, r);
    if (extra) {
      state.sixStreak = r == 6 ? state.sixStreak + 1 : 0;
      return const LudoPlayResult(extraTurn: true, won: false);
    }
    advanceTurn();
    return const LudoPlayResult(extraTurn: false, won: false);
  }

  void advanceTurn() {
    state.turn = (state.turn + 1) % state.playerCount;
    state.sixStreak = 0;
  }
}
