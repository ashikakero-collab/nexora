// Pure-Dart tournament structures (no Flutter imports).
//
// This is the client mirror of the server engine in
// supabase/migrations/20261116000100_nx_tournaments_engine.sql: same seed order, same bye
// handling, same double-elimination wiring, same round-robin circle method, same snake groups,
// same swiss pairing and the same series / standings rules. The server is the authority (it
// generates the real bracket at draw time); this file powers the admin wizard preview and the
// unit tests that pin the algorithms down.

/// Tournament formats (string codes match nx_tournaments.format).
enum TFormat { singleElim, doubleElim, twoLegs, roundRobin, groupsKo, swiss, custom }

extension TFormatCode on TFormat {
  String get code => switch (this) {
        TFormat.singleElim => 'single_elim',
        TFormat.doubleElim => 'double_elim',
        TFormat.twoLegs => 'two_legs',
        TFormat.roundRobin => 'round_robin',
        TFormat.groupsKo => 'groups_ko',
        TFormat.swiss => 'swiss',
        TFormat.custom => 'custom',
      };

  bool get isLeague => this == TFormat.roundRobin || this == TFormat.swiss || this == TFormat.custom;

  static TFormat parse(String? s) {
    for (final TFormat f in TFormat.values) {
      if (f.code == s) return f;
    }
    return TFormat.singleElim;
  }
}

/// Elimination-bracket brackets (W winners, L losers, GF grand final, GF2 reset, P3 third place).
const Set<String> kElimBrackets = <String>{'W', 'L', 'GF', 'GF2', 'P3'};

/// Final states of a match.
const Set<String> kFinalStatuses = <String>{'done', 'walkover', 'bye', 'void', 'skipped'};

/// One bracket match. Players are seed numbers (1-based); null in a filled slot = bye.
class BMatch {
  BMatch({
    required this.bracket,
    required this.round,
    required this.idx,
    this.group,
    this.bestOf = 1,
    this.aggregate = false,
  });

  final String bracket;
  final int round;
  final int idx;
  final int? group;
  int bestOf;
  bool aggregate;

  int? p1;
  int? p2;
  bool p1Set = false;
  bool p2Set = false;
  String? winTo;
  int? winSlot;
  String? loseTo;
  int? loseSlot;

  String status = 'pending';
  int? winner;
  int? loser;
  bool draw = false;

  String get id => matchId(bracket, round, idx, group);
  bool get isFinal => kFinalStatuses.contains(status);
  bool get playable => status == 'scheduled';

  static String matchId(String bracket, int round, int idx, [int? group]) =>
      group == null ? '$bracket$round-$idx' : '$bracket$group.$round-$idx';
}

/// A generated bracket that can also be simulated (byes resolve automatically, winners advance).
class Bracket {
  final Map<String, BMatch> _m = <String, BMatch>{};

  Iterable<BMatch> get matches => _m.values;
  BMatch? operator [](String id) => _m[id];
  int get length => _m.length;

  BMatch add(BMatch m) {
    _m[m.id] = m;
    return m;
  }

  List<BMatch> where(String bracket) => _m.values.where((BMatch m) => m.bracket == bracket).toList();

  /// Matches waiting to be played.
  List<BMatch> get playable => _m.values.where((BMatch m) => m.playable).toList();

  bool get finished => _m.values.every((BMatch m) => m.isFinal);

  void put(String? id, int slot, int? player) {
    if (id == null) return;
    final BMatch m = _m[id]!;
    if (slot == 1) {
      m.p1 = player;
      m.p1Set = true;
    } else {
      m.p2 = player;
      m.p2Set = true;
    }
    _check(m);
  }

  void _check(BMatch m) {
    if (m.status != 'pending' || !m.p1Set || !m.p2Set) return;
    if (m.p1 == null || m.p2 == null) {
      complete(m.id, m.p1 ?? m.p2, null, status: 'bye');
      return;
    }
    m.status = 'scheduled';
  }

  /// Record a result and advance players (mirrors _nx_t_complete + _nx_t_propagate).
  void complete(String id, int? winner, int? loser, {String status = 'done', bool draw = false}) {
    final BMatch m = _m[id]!;
    if (m.isFinal) return;
    m
      ..winner = winner
      ..loser = loser
      ..draw = draw
      ..status = status;
    if (m.bracket == 'GF') {
      final BMatch? gf2 = _m.values.where((BMatch x) => x.bracket == 'GF2' && x.status == 'pending').firstOrNull;
      if (gf2 == null) return;
      if (winner == m.p1 || m.p1 == null || m.p2 == null) {
        gf2.status = 'skipped';
      } else {
        put(gf2.id, 1, m.p1);
        put(gf2.id, 2, m.p2);
      }
      return;
    }
    if (m.winTo != null) put(m.winTo, m.winSlot!, winner);
    if (m.loseTo != null) put(m.loseTo, m.loseSlot!, loser);
  }

  /// Play every open match with [pick] choosing the winner (a, b) → a or b, until nothing is left.
  void simulate(int Function(BMatch m, int a, int b) pick) {
    for (int guard = 0; guard < 10000; guard++) {
      final List<BMatch> open = playable;
      if (open.isEmpty) return;
      final BMatch m = open.first;
      final int w = pick(m, m.p1!, m.p2!);
      complete(m.id, w, w == m.p1 ? m.p2 : m.p1);
    }
    throw StateError('bracket did not finish');
  }

  /// Champion of a finished elimination bracket.
  int? get champion {
    final BMatch? gf2 = _m.values.where((BMatch m) => m.bracket == 'GF2' && m.status == 'done').firstOrNull;
    if (gf2 != null) return gf2.winner;
    final BMatch? gf = _m.values.where((BMatch m) => m.bracket == 'GF').firstOrNull;
    if (gf != null) return gf.winner;
    final List<BMatch> w = where('W');
    if (w.isEmpty) return null;
    final int last = w.map((BMatch m) => m.round).reduce((int a, int b) => a > b ? a : b);
    return w.firstWhere((BMatch m) => m.round == last).winner;
  }
}

/// Best-of for a round kind, per format (mirrors _nx_t_bo).
class BestOf {
  const BestOf({this.early = 1, this.semi = 1, this.finalRound = 1, this.twoLegs = false, this.finalOneLeg = false});
  final int early;
  final int semi;
  final int finalRound;
  final bool twoLegs;
  final bool finalOneLeg;

  static int _valid(int v) => const <int>{1, 2, 3, 5}.contains(v) ? v : 1;

  int of(String kind) {
    if (twoLegs) return kind == 'final' && finalOneLeg ? 1 : 2;
    return _valid(switch (kind) { 'final' => finalRound, 'semi' => semi, _ => early });
  }
}

class BracketGen {
  const BracketGen._();

  static int _clampInt(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);

  /// Smallest k with 2^k >= n.
  static int roundsFor(int n) {
    int k = 0;
    while ((1 << k) < n) {
      k++;
    }
    return k;
  }

  /// Standard bracket order (1, P, P/2+1, …): seeds 1 and 2 can only meet in the final.
  static List<int> seedOrder(int p) {
    List<int> a = <int>[1];
    int n = 1;
    while (n < p) {
      n *= 2;
      final List<int> b = <int>[];
      for (final int x in a) {
        b
          ..add(x)
          ..add(n + 1 - x);
      }
      a = b;
    }
    return a;
  }

  /// Matches in losers-bracket round m (1-based) of a double elimination of size p.
  static int lbCount(int p, int m) {
    if (m == 1) return p >> 2;
    if (m.isEven) return p >> (m ~/ 2 + 1);
    return p >> ((m - 1) ~/ 2 + 2);
  }

  /// Single elimination for n players (seeds 1..n). Byes go to the top seeds in round 1.
  static Bracket singleElim(int n, {bool thirdPlace = false, BestOf bo = const BestOf(), int roundOffset = 0}) {
    final Bracket b = Bracket();
    if (n < 2) return b;
    final int k = roundsFor(n);
    final int p = 1 << k;
    final List<int> ord = seedOrder(p);
    for (int r = 1; r <= k; r++) {
      final String kind = r == k ? 'final' : (r == k - 1 ? 'semi' : 'early');
      for (int i = 0; i < (p >> r); i++) {
        final int v = bo.of(kind);
        b.add(BMatch(bracket: 'W', round: roundOffset + r, idx: i, bestOf: v, aggregate: bo.twoLegs && v == 2));
      }
    }
    for (int r = 1; r < k; r++) {
      for (int i = 0; i < (p >> r); i++) {
        b[BMatch.matchId('W', roundOffset + r, i)]!
          ..winTo = BMatch.matchId('W', roundOffset + r + 1, i ~/ 2)
          ..winSlot = (i % 2) + 1;
      }
    }
    if (k >= 2 && thirdPlace) {
      final int v = bo.of('final');
      final BMatch p3 = b.add(BMatch(bracket: 'P3', round: roundOffset + k, idx: 0, bestOf: v, aggregate: bo.twoLegs && v == 2));
      b[BMatch.matchId('W', roundOffset + k - 1, 0)]!
        ..loseTo = p3.id
        ..loseSlot = 1;
      b[BMatch.matchId('W', roundOffset + k - 1, 1)]!
        ..loseTo = p3.id
        ..loseSlot = 2;
    }
    for (int i = 0; i < p ~/ 2; i++) {
      final int a = ord[2 * i];
      final int c = ord[2 * i + 1];
      final String id = BMatch.matchId('W', roundOffset + 1, i);
      final BMatch m = b[id]!
        ..p1 = a <= n ? a : null
        ..p1Set = true
        ..p2 = c <= n ? c : null
        ..p2Set = true;
      b._check(m);
    }
    return b;
  }

  /// Double elimination: W (k rounds), L (2(k-1) rounds), GF and the reset GF2.
  static Bracket doubleElim(int n, {BestOf bo = const BestOf()}) {
    final Bracket b = Bracket();
    if (n < 2) return b;
    final int k = roundsFor(n);
    final int p = 1 << k;
    final List<int> ord = seedOrder(p);
    final int lr = 2 * (k - 1);
    for (int r = 1; r <= k; r++) {
      final String kind = r == k ? 'final' : (r == k - 1 ? 'semi' : 'early');
      for (int i = 0; i < (p >> r); i++) {
        b.add(BMatch(bracket: 'W', round: r, idx: i, bestOf: bo.of(kind)));
      }
    }
    for (int m = 1; m <= lr; m++) {
      for (int i = 0; i < lbCount(p, m); i++) {
        b.add(BMatch(bracket: 'L', round: m, idx: i, bestOf: bo.of(m == lr ? 'semi' : 'early')));
      }
    }
    final BMatch gf = b.add(BMatch(bracket: 'GF', round: 1, idx: 0, bestOf: bo.of('final')));
    b.add(BMatch(bracket: 'GF2', round: 1, idx: 0, bestOf: bo.of('final')));
    for (int r = 1; r <= k; r++) {
      final int cnt = p >> r;
      for (int i = 0; i < cnt; i++) {
        final BMatch m = b[BMatch.matchId('W', r, i)]!;
        if (r < k) {
          m
            ..winTo = BMatch.matchId('W', r + 1, i ~/ 2)
            ..winSlot = (i % 2) + 1;
        } else {
          m
            ..winTo = gf.id
            ..winSlot = 1;
        }
        if (k == 1) {
          m
            ..loseTo = gf.id
            ..loseSlot = 2;
        } else if (r == 1) {
          m
            ..loseTo = BMatch.matchId('L', 1, i ~/ 2)
            ..loseSlot = (i % 2) + 1;
        } else {
          final int j = r.isEven ? cnt - 1 - i : i;
          m
            ..loseTo = BMatch.matchId('L', 2 * (r - 1), j)
            ..loseSlot = 2;
        }
      }
    }
    for (int m = 1; m <= lr; m++) {
      for (int i = 0; i < lbCount(p, m); i++) {
        final BMatch x = b[BMatch.matchId('L', m, i)]!;
        if (m == lr) {
          x
            ..winTo = gf.id
            ..winSlot = 2;
        } else if (m.isOdd) {
          x
            ..winTo = BMatch.matchId('L', m + 1, i)
            ..winSlot = 1;
        } else {
          x
            ..winTo = BMatch.matchId('L', m + 1, i ~/ 2)
            ..winSlot = (i % 2) + 1;
        }
      }
    }
    for (int i = 0; i < p ~/ 2; i++) {
      final int a = ord[2 * i];
      final int c = ord[2 * i + 1];
      final BMatch m = b[BMatch.matchId('W', 1, i)]!
        ..p1 = a <= n ? a : null
        ..p1Set = true
        ..p2 = c <= n ? c : null
        ..p2Set = true;
      b._check(m);
    }
    return b;
  }

  /// Round robin (circle method). Returns rounds of (home, away) seed pairs; odd n → one rests per round.
  static List<List<(int, int)>> roundRobin(int n, {bool double = false}) {
    final List<List<(int, int)>> out = <List<(int, int)>>[];
    if (n < 2) return out;
    final List<int?> base = <int?>[for (int i = 1; i <= n; i++) i];
    if (base.length.isOdd) base.add(null);
    final int m = base.length;
    for (int cyc = 0; cyc < (double ? 2 : 1); cyc++) {
      List<int?> arr = List<int?>.of(base);
      for (int r = 0; r < m - 1; r++) {
        final List<(int, int)> round = <(int, int)>[];
        for (int i = 0; i < m ~/ 2; i++) {
          final int? a = arr[i];
          final int? b = arr[m - 1 - i];
          if (a != null && b != null) {
            final bool swap = (r.isOdd && i == 0) != (cyc == 1);
            round.add(swap ? (b, a) : (a, b));
          }
        }
        out.add(round);
        arr = <int?>[arr[0], arr[m - 1], ...arr.sublist(1, m - 1)];
      }
    }
    return out;
  }

  /// Snake distribution of seeds 1..n into g groups (1-based group numbers per seed index).
  static List<List<int>> snakeGroups(int n, int groups) {
    final int g = _clampInt(groups, 1, n ~/ 2 < 1 ? 1 : n ~/ 2);
    final List<List<int>> out = <List<int>>[for (int i = 0; i < g; i++) <int>[]];
    for (int i = 1; i <= n; i++) {
      final int row = (i - 1) ~/ g;
      final int grp = row.isEven ? (i - 1) % g : g - 1 - ((i - 1) % g);
      out[grp].add(i);
    }
    return out;
  }

  /// Knockout seeding after groups: A1, B1, C1…, A2, B2… (the standard order then keeps group mates apart).
  static List<int> groupAdvancers(List<List<int>> rankedGroups, int advance) {
    final List<int> out = <int>[];
    for (int rk = 0; rk < advance; rk++) {
      for (final List<int> g in rankedGroups) {
        if (rk < g.length) out.add(g[rk]);
      }
    }
    return out;
  }

  /// Swiss pairing for one round. [order]: players by current standing (round 1: by seed).
  /// [played]: set of "a-b" keys (a<b) already met. [hadBye]: players who already had a bye.
  /// Returns pairs plus the bye player (or null).
  static ({List<(int, int)> pairs, int? bye}) swissRound(
      int round, List<int> order, Set<String> played, Set<int> hadBye) {
    final List<int> ord = List<int>.of(order);
    int? bye;
    if (ord.length.isOdd) {
      for (int i = ord.length - 1; i >= 0; i--) {
        if (!hadBye.contains(ord[i])) {
          bye = ord[i];
          break;
        }
      }
      bye ??= ord.last;
      ord.remove(bye);
    }
    final List<(int, int)> pairs = <(int, int)>[];
    if (round == 1) {
      final int h = ord.length ~/ 2;
      for (int i = 0; i < h; i++) {
        pairs.add((ord[i], ord[i + h]));
      }
      return (pairs: pairs, bye: bye);
    }
    final List<bool> used = List<bool>.filled(ord.length, false);
    for (int i = 0; i < ord.length; i++) {
      if (used[i]) continue;
      int? partner;
      for (int j = i + 1; j < ord.length; j++) {
        if (!used[j] && !played.contains(pairKey(ord[i], ord[j]))) {
          partner = j;
          break;
        }
      }
      if (partner == null) {
        for (int j = i + 1; j < ord.length; j++) {
          if (!used[j]) {
            partner = j;
            break;
          }
        }
      }
      if (partner == null) break;
      used[i] = true;
      used[partner] = true;
      pairs.add((ord[i], ord[partner]));
    }
    return (pairs: pairs, bye: bye);
  }

  static String pairKey(int a, int b) => a < b ? '$a-$b' : '$b-$a';

  /// Default number of swiss rounds: ceil(log2 n), at most n-1.
  static int swissRounds(int n, [int configured = 0]) {
    final int k = roundsFor(n < 2 ? 2 : n);
    final int r = configured > 0 ? configured : (k < 1 ? 1 : k);
    return _clampInt(r, 1, n - 1 < 1 ? 1 : n - 1);
  }

  /// Place of a player knocked out in round [rr] (1-based within the stage) of a k-round single elimination.
  static int elimPlace(int k, int rr) => (1 << (k - rr)) + 1;

  /// Number of matches a format will create (preview in the admin wizard).
  static int matchCount(TFormat f, int n,
      {bool thirdPlace = false, bool rrDouble = false, int groups = 2, int advance = 2, int swissRoundsCfg = 0}) {
    if (n < 2) return 0;
    switch (f) {
      case TFormat.singleElim:
      case TFormat.twoLegs:
        final int p = 1 << roundsFor(n);
        return p - 1 + (thirdPlace && p >= 4 ? 1 : 0);
      case TFormat.doubleElim:
        return doubleElim(n).length;
      case TFormat.roundRobin:
        return roundRobin(n, double: rrDouble).fold<int>(0, (int s, List<(int, int)> r) => s + r.length);
      case TFormat.groupsKo:
        final List<List<int>> gs = snakeGroups(n, groups);
        int c = 0;
        for (final List<int> g in gs) {
          c += roundRobin(g.length, double: rrDouble).fold<int>(0, (int s, List<(int, int)> r) => s + r.length);
        }
        final int adv = gs.fold<int>(0, (int s, List<int> g) => s + (advance < g.length ? advance : g.length));
        return c + (adv >= 2 ? (1 << roundsFor(adv)) - 1 : 0);
      case TFormat.swiss:
        return swissRounds(n, swissRoundsCfg) * (n ~/ 2);
      case TFormat.custom:
        return 0;
    }
  }
}

/// Outcome of a series after a game (mirrors _nx_t_game_result).
enum SeriesOutcome { p1, p2, draw, more }

class Series {
  Series({required this.bestOf, this.aggregate = false, this.knockout = true});
  final int bestOf;
  final bool aggregate;
  final bool knockout;
  int games = 0;
  int w1 = 0;
  int w2 = 0;
  int g1 = 0;
  int g2 = 0;

  /// The next game is a golden-goal decider once the regular games are used up.
  bool get nextIsGolden => games >= bestOf;

  /// Add one game (goals from p1's and p2's view; winner 1, 2 or 0 = draw) and decide.
  SeriesOutcome add(int s1, int s2, int winner) {
    games++;
    g1 += s1;
    g2 += s2;
    if (winner == 1) w1++;
    if (winner == 2) w2++;
    final int need = bestOf ~/ 2 + 1;
    if (aggregate) {
      if (games >= 2) {
        if (games > 2 && winner != 0) return winner == 1 ? SeriesOutcome.p1 : SeriesOutcome.p2;
        if (g1 > g2) return SeriesOutcome.p1;
        if (g2 > g1) return SeriesOutcome.p2;
        if (!knockout) return SeriesOutcome.draw;
      }
    } else {
      if (bestOf != 2 && w1 >= need) return SeriesOutcome.p1;
      if (bestOf != 2 && w2 >= need) return SeriesOutcome.p2;
      if (games >= bestOf) {
        if (w1 > w2) return SeriesOutcome.p1;
        if (w2 > w1) return SeriesOutcome.p2;
        if (!knockout) return SeriesOutcome.draw;
      }
    }
    return SeriesOutcome.more;
  }
}

/// League table row + ordering (pts, goal difference, goals for, wins, seed) like _nx_t_table / nx_t_standings.
class LeagueRow {
  LeagueRow(this.player, this.seed);
  final int player;
  final int seed;
  int played = 0;
  int won = 0;
  int drawn = 0;
  int lost = 0;
  int gf = 0;
  int ga = 0;

  int points({int win = 3, int draw = 1}) => won * win + drawn * draw;
  int get gd => gf - ga;

  static int compare(LeagueRow a, LeagueRow b, {int win = 3, int draw = 1}) {
    int c = b.points(win: win, draw: draw).compareTo(a.points(win: win, draw: draw));
    if (c != 0) return c;
    c = b.gd.compareTo(a.gd);
    if (c != 0) return c;
    c = b.gf.compareTo(a.gf);
    if (c != 0) return c;
    c = b.won.compareTo(a.won);
    if (c != 0) return c;
    return a.seed.compareTo(b.seed);
  }

  /// Build a sorted table from results (a, b, goalsA, goalsB); a null b = bye (counts as a win).
  static List<LeagueRow> table(List<int> seeds, Iterable<(int, int?, int, int)> results, {int win = 3, int draw = 1}) {
    final Map<int, LeagueRow> rows = <int, LeagueRow>{for (final int s in seeds) s: LeagueRow(s, s)};
    for (final (int a, int? b, int ga, int gb) in results) {
      final LeagueRow? ra = rows[a];
      if (ra == null) continue;
      ra.played++;
      if (b == null) {
        ra.won++;
        continue;
      }
      final LeagueRow? rb = rows[b];
      if (rb == null) continue;
      rb.played++;
      ra
        ..gf += ga
        ..ga += gb;
      rb
        ..gf += gb
        ..ga += ga;
      if (ga > gb) {
        ra.won++;
        rb.lost++;
      } else if (gb > ga) {
        rb.won++;
        ra.lost++;
      } else {
        ra.drawn++;
        rb.drawn++;
      }
    }
    final List<LeagueRow> out = rows.values.toList()
      ..sort((LeagueRow x, LeagueRow y) => compare(x, y, win: win, draw: draw));
    return out;
  }
}
