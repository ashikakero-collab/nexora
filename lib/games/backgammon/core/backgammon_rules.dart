import 'dart:math';

/// Pure-Dart backgammon rules (no Flutter imports, deterministic).
///
/// Board model: 24 points indexed 0..23. Positive counts are player 0's
/// checkers (they move from index 23 toward index 0, home board 0..5), negative
/// counts are player 1's checkers (they move from 0 toward 23, home 18..23).

/// Source index meaning "from the bar".
const int kBgBar = -1;

/// Destination index meaning "borne off".
const int kBgOff = -2;

const int kBgCheckers = 15;

class BgMove {
  const BgMove(this.from, this.to, this.die, {this.hit = false});

  /// Point index, or [kBgBar].
  final int from;

  /// Point index, or [kBgOff].
  final int to;
  final int die;
  final bool hit;

  bool sameAs(BgMove o) => o.from == from && o.to == to && o.die == die;

  @override
  String toString() => 'BgMove($from->$to d$die${hit ? ' hit' : ''})';
}

class BgState {
  BgState({
    required this.points,
    required this.bar,
    required this.off,
    this.turn = 0,
  });

  factory BgState.initial() {
    final List<int> pts = List<int>.filled(24, 0);
    pts[23] = 2;
    pts[12] = 5;
    pts[7] = 3;
    pts[5] = 5;
    pts[0] = -2;
    pts[11] = -5;
    pts[16] = -3;
    pts[18] = -5;
    return BgState(points: pts, bar: <int>[0, 0], off: <int>[0, 0]);
  }

  final List<int> points;
  final List<int> bar;
  final List<int> off;
  int turn;

  BgState copy() => BgState(
        points: List<int>.from(points),
        bar: List<int>.from(bar),
        off: List<int>.from(off),
        turn: turn,
      );

  /// Number of player [p]'s checkers on point [idx].
  int own(int p, int idx) {
    final int v = points[idx];
    if (p == 0) return v > 0 ? v : 0;
    return v < 0 ? -v : 0;
  }

  int opp(int p, int idx) => own(1 - p, idx);

  static int sign(int p) => p == 0 ? 1 : -1;

  String get key =>
      '${points.join(',')}|${bar[0]},${bar[1]}|${off[0]},${off[1]}';

  int? get winner {
    if (off[0] >= kBgCheckers) return 0;
    if (off[1] >= kBgCheckers) return 1;
    return null;
  }

  /// Pip count: total pips player [p] still has to travel to bear everything off.
  int pip(int p) {
    int total = bar[p] * 25;
    for (int i = 0; i < 24; i++) {
      final int c = own(p, i);
      if (c > 0) total += c * BgRules.relPos(p, i);
    }
    return total;
  }

  int checkersOnBoard(int p) {
    int c = bar[p];
    for (int i = 0; i < 24; i++) {
      c += own(p, i);
    }
    return c;
  }
}

/// A full play for one roll and the position it produces.
class BgPlay {
  const BgPlay(this.moves, this.state);
  final List<BgMove> moves;
  final BgState state;
}

class BgRules {
  BgRules._();

  /// Relative position 1..24 of point [idx] for player [p] (1 = closest to off).
  static int relPos(int p, int idx) => p == 0 ? idx + 1 : 24 - idx;

  static int idxOf(int p, int pos) => p == 0 ? pos - 1 : 24 - pos;

  static int entryIndex(int p, int die) => p == 0 ? 24 - die : die - 1;

  static bool isHome(int p, int idx) => relPos(p, idx) <= 6;

  static List<int> expandDice(List<int> dice) {
    if (dice.length == 2 && dice[0] == dice[1]) {
      return <int>[dice[0], dice[0], dice[0], dice[0]];
    }
    return List<int>.from(dice);
  }

  static bool allHome(BgState s, int p) {
    if (s.bar[p] > 0) return false;
    int c = s.off[p];
    for (int i = 0; i < 24; i++) {
      if (isHome(p, i)) c += s.own(p, i);
    }
    return c == kBgCheckers;
  }

  static bool _hasHigher(BgState s, int p, int pos) {
    for (int q = pos + 1; q <= 6; q++) {
      if (s.own(p, idxOf(p, q)) > 0) return true;
    }
    return false;
  }

  /// All single-checker moves for one die (ignores the "use both dice" rule).
  static List<BgMove> singleMoves(BgState s, int p, int die) {
    final List<BgMove> out = <BgMove>[];
    if (s.bar[p] > 0) {
      final int to = entryIndex(p, die);
      final int o = s.opp(p, to);
      if (o < 2) out.add(BgMove(kBgBar, to, die, hit: o == 1));
      return out;
    }
    final bool canBear = allHome(s, p);
    for (int i = 0; i < 24; i++) {
      if (s.own(p, i) == 0) continue;
      final int pos = relPos(p, i);
      final int targetPos = pos - die;
      if (targetPos >= 1) {
        final int to = p == 0 ? i - die : i + die;
        final int o = s.opp(p, to);
        if (o < 2) out.add(BgMove(i, to, die, hit: o == 1));
      } else if (canBear) {
        if (targetPos == 0 || !_hasHigher(s, p, pos)) {
          out.add(BgMove(i, kBgOff, die));
        }
      }
    }
    return out;
  }

  /// Returns a new state with [m] played by player [p].
  static BgState apply(BgState s, int p, BgMove m) {
    final BgState n = s.copy();
    applyInPlace(n, p, m);
    return n;
  }

  static void applyInPlace(BgState n, int p, BgMove m) {
    final int sg = BgState.sign(p);
    if (m.from == kBgBar) {
      n.bar[p] -= 1;
    } else {
      n.points[m.from] -= sg;
    }
    if (m.to == kBgOff) {
      n.off[p] += 1;
      return;
    }
    if (n.opp(p, m.to) == 1) {
      n.points[m.to] = 0;
      n.bar[1 - p] += 1;
    }
    n.points[m.to] += sg;
  }

  /// Maximum number of dice from [pool] player [p] can play.
  static int maxDepth(BgState s, int p, List<int> pool) {
    if (pool.isEmpty) return 0;
    int best = 0;
    final Set<int> tried = <int>{};
    for (int k = 0; k < pool.length; k++) {
      final int d = pool[k];
      if (!tried.add(d)) continue;
      final List<BgMove> moves = singleMoves(s, p, d);
      if (moves.isEmpty) continue;
      final List<int> rest = List<int>.from(pool)..removeAt(k);
      for (final BgMove m in moves) {
        final int v = 1 + maxDepth(apply(s, p, m), p, rest);
        if (v > best) best = v;
        if (best == pool.length) return best;
      }
    }
    return best;
  }

  /// When only one die can be played and the dice differ, the larger die must
  /// be used if it can be. Returns the forced die value, or null.
  static int? forcedDie(BgState s, int p, List<int> pool, int total) {
    if (total != 1 || pool.length != 2 || pool[0] == pool[1]) return null;
    final int hi = max(pool[0], pool[1]);
    if (singleMoves(s, p, hi).isNotEmpty) return hi;
    return min(pool[0], pool[1]);
  }

  /// Legal next single moves given the dice still [remaining], when the player
  /// still has to play [needed] more dice this turn.
  static List<BgMove> legalNextMoves(
      BgState s, int p, List<int> remaining, int needed,
      {int? forceDie}) {
    final List<BgMove> out = <BgMove>[];
    if (needed <= 0) return out;
    final Set<int> tried = <int>{};
    for (int k = 0; k < remaining.length; k++) {
      final int d = remaining[k];
      if (!tried.add(d)) continue;
      if (forceDie != null && d != forceDie) continue;
      final List<int> rest = List<int>.from(remaining)..removeAt(k);
      for (final BgMove m in singleMoves(s, p, d)) {
        final int depth = 1 + maxDepth(apply(s, p, m), p, rest);
        if (depth >= needed) out.add(m);
      }
    }
    return out;
  }

  /// Every distinct final position reachable with a fully legal play.
  static List<BgPlay> enumeratePlays(BgState s, int p, List<int> dice) {
    final List<int> pool = expandDice(dice);
    final int total = maxDepth(s, p, pool);
    if (total == 0) return <BgPlay>[BgPlay(const <BgMove>[], s.copy())];
    final int? force = forcedDie(s, p, pool, total);
    final Map<String, BgPlay> results = <String, BgPlay>{};
    final Set<String> visited = <String>{};

    void rec(BgState st, List<int> rest, List<BgMove> prefix) {
      if (prefix.length == total) {
        results.putIfAbsent(st.key, () => BgPlay(prefix, st));
        return;
      }
      final List<int> sorted = List<int>.from(rest)..sort();
      final String vk = '${st.key}#${sorted.join()}';
      if (!visited.add(vk)) return;
      final Set<int> tried = <int>{};
      for (int k = 0; k < rest.length; k++) {
        final int d = rest[k];
        if (!tried.add(d)) continue;
        if (prefix.isEmpty && force != null && d != force) continue;
        final List<int> nextRest = List<int>.from(rest)..removeAt(k);
        for (final BgMove m in singleMoves(st, p, d)) {
          rec(apply(st, p, m), nextRest, <BgMove>[...prefix, m]);
        }
      }
    }

    rec(s, pool, <BgMove>[]);
    return results.values.toList();
  }

  /// 1 = single, 2 = gammon, 3 = backgammon.
  static int resultMultiplier(BgState s, int winner) {
    final int loser = 1 - winner;
    if (s.off[loser] > 0) return 1;
    if (s.bar[loser] > 0) return 3;
    for (int i = 0; i < 24; i++) {
      if (isHome(winner, i) && s.own(loser, i) > 0) return 3;
    }
    return 2;
  }

  /// True while the two armies can still hit each other.
  static bool hasContact(BgState s) {
    int back0 = -100;
    int back1 = 100;
    if (s.bar[0] > 0) back0 = 24;
    if (s.bar[1] > 0) back1 = -1;
    for (int i = 0; i < 24; i++) {
      if (s.own(0, i) > 0 && i > back0) back0 = i;
      if (s.own(1, i) > 0 && i < back1) back1 = i;
    }
    if (back0 == -100 || back1 == 100) return false;
    return back0 > back1;
  }
}

/// Tracks a human's turn move-by-move with legality + undo.
class BgTurnTracker {
  BgTurnTracker(BgState start, this.player, List<int> dice)
      : _start = start.copy(),
        state = start.copy(),
        rolled = List<int>.from(dice),
        pool = BgRules.expandDice(dice) {
    used = List<bool>.filled(pool.length, false);
    total = BgRules.maxDepth(_start, player, pool);
    forceDie = BgRules.forcedDie(_start, player, pool, total);
  }

  final BgState _start;
  final int player;
  final List<int> rolled;
  final List<int> pool;
  late List<bool> used;
  late int total;
  int? forceDie;
  BgState state;
  final List<BgMove> played = <BgMove>[];

  List<int> get remaining {
    final List<int> r = <int>[];
    for (int i = 0; i < pool.length; i++) {
      if (!used[i]) r.add(pool[i]);
    }
    return r;
  }

  int get needed => total - played.length;
  bool get complete => needed <= 0;

  List<BgMove> legalMoves() => BgRules.legalNextMoves(
      state, player, remaining, needed,
      forceDie: played.isEmpty ? forceDie : null);

  List<BgMove> movesFrom(int from) =>
      legalMoves().where((BgMove m) => m.from == from).toList();

  /// Plays [m] if legal. Returns the actually played (canonical) move or null.
  BgMove? play(BgMove m) {
    final List<BgMove> legal = legalMoves();
    BgMove? found;
    for (final BgMove l in legal) {
      if (l.sameAs(m)) {
        found = l;
        break;
      }
    }
    if (found == null) return null;
    BgRules.applyInPlace(state, player, found);
    for (int i = 0; i < pool.length; i++) {
      if (!used[i] && pool[i] == found.die) {
        used[i] = true;
        break;
      }
    }
    played.add(found);
    return found;
  }

  bool get canUndo => played.isNotEmpty;

  void undo() {
    if (played.isEmpty) return;
    final List<BgMove> keep = List<BgMove>.from(played)..removeLast();
    state = _start.copy();
    used = List<bool>.filled(pool.length, false);
    played.clear();
    for (final BgMove m in keep) {
      play(m);
    }
  }
}

/// Seedable dice.
class BgDice {
  BgDice([int? seed]) : _rng = Random(seed);
  final Random _rng;
  int roll() => _rng.nextInt(6) + 1;
}
