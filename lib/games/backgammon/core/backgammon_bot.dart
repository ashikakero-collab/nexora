import 'dart:math';

import 'backgammon_rules.dart';

/// Offline backgammon AI: enumerates every legal play for the roll and scores
/// the resulting positions with a positional heuristic.
/// [level]: 0 = easy, 1 = normal, 2 = hard.
class BgBot {
  BgBot({required this.level, int? seed}) : _rng = Random(seed);

  final int level;
  final Random _rng;

  /// Approximate number of the 36 rolls that hit a blot at a given distance.
  static const List<int> _shotTable = <int>[
    0, 11, 12, 14, 15, 15, 17, 6, 6, 5, 3, 2, 3, //
    0, 0, 1, 1, 0, 1, 0, 1, 0, 0, 0, 1,
  ];

  List<BgMove> choose(BgState s, int p, List<int> dice) {
    final List<BgPlay> plays = BgRules.enumeratePlays(s, p, dice);
    if (plays.isEmpty) return const <BgMove>[];
    if (plays.length == 1) return plays.first.moves;
    if (level == 0 && _rng.nextDouble() < 0.3) {
      return plays[_rng.nextInt(plays.length)].moves;
    }
    double bestScore = -1e18;
    BgPlay best = plays.first;
    for (final BgPlay pl in plays) {
      double v = evaluate(pl.state, p);
      if (level == 0) {
        v += _rng.nextDouble() * 30.0;
      } else if (level == 1) {
        v += _rng.nextDouble() * 5.0;
      }
      if (v > bestScore) {
        bestScore = v;
        best = pl;
      }
    }
    return best.moves;
  }

  static int shotsOn(BgState s, int p, int idx) {
    final int o = 1 - p;
    final Set<int> distances = <int>{};
    if (o == 1) {
      // Opponent moves upward (toward higher indices).
      if (s.bar[1] > 0) distances.add(idx + 1);
      for (int j = 0; j < idx; j++) {
        if (s.own(1, j) > 0) distances.add(idx - j);
      }
    } else {
      if (s.bar[0] > 0) distances.add(24 - idx);
      for (int j = idx + 1; j < 24; j++) {
        if (s.own(0, j) > 0) distances.add(j - idx);
      }
    }
    int shots = 0;
    for (final int d in distances) {
      if (d > 0 && d < _shotTable.length) shots += _shotTable[d];
    }
    return shots > 36 ? 36 : shots;
  }

  static double evaluate(BgState s, int p) {
    final int o = 1 - p;
    if (s.off[p] >= kBgCheckers) return 100000.0;
    final int myPip = s.pip(p);
    final int opPip = s.pip(o);
    double v = (opPip - myPip).toDouble();

    if (!BgRules.hasContact(s)) {
      // Pure race: pips and borne-off checkers matter, nothing else.
      v = v * 2.0 + s.off[p] * 3.0;
      for (int pos = 1; pos <= 6; pos++) {
        final int c = s.own(p, BgRules.idxOf(p, pos));
        if (c > 3) v -= (c - 3) * 0.6;
      }
      return v;
    }

    v += s.off[p] * 2.0;
    v += s.bar[o] * 5.0;
    v -= s.bar[p] * 4.0;

    int run = 0;
    int bestRun = 0;
    int homeMade = 0;
    for (int pos = 1; pos <= 24; pos++) {
      final int idx = BgRules.idxOf(p, pos);
      final int c = s.own(p, idx);
      if (c >= 2) {
        run++;
        if (run > bestRun) bestRun = run;
        double pv;
        if (pos <= 6) {
          pv = 4.0;
          homeMade++;
          if (s.bar[o] > 0) pv += 3.0;
        } else if (pos == 7) {
          pv = 3.5;
        } else if (pos <= 11) {
          pv = 2.0;
        } else if (pos >= 19) {
          pv = 2.5; // anchor in the opponent's home board
        } else {
          pv = 1.0;
        }
        v += pv;
        if (c > 4) v -= (c - 4) * 1.5;
      } else {
        run = 0;
        if (c == 1) {
          final int shots = shotsOn(s, p, idx);
          final double loss = (25 - pos).toDouble();
          v -= 1.0 + shots / 36.0 * loss * 0.9;
        }
      }
    }
    if (bestRun >= 3) v += bestRun * bestRun * 1.2;
    if (s.bar[o] > 0) v += homeMade * homeMade * 0.6;
    return v;
  }
}
