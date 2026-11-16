import 'dart:math';

import 'ludo_rules.dart';

/// Offline Ludo AI. Priorities: capture > escape danger > advance > leave base.
/// [level]: 0 = easy, 1 = normal, 2 = hard.
class LudoBot {
  LudoBot({required this.level, int? seed}) : _rng = Random(seed);

  final int level;
  final Random _rng;

  LudoMove choose(LudoState s, List<LudoMove> moves) {
    if (moves.length == 1) return moves.first;
    if (level == 0 && _rng.nextDouble() < 0.4) {
      return moves[_rng.nextInt(moves.length)];
    }
    LudoMove best = moves.first;
    double bestScore = -1e9;
    for (final LudoMove m in moves) {
      double v = score(s, m);
      if (level == 0) {
        v += _rng.nextDouble() * 25;
      } else if (level == 1) {
        v += _rng.nextDouble() * 8;
      }
      if (v > bestScore) {
        bestScore = v;
        best = m;
      }
    }
    return best;
  }

  static double score(LudoState s, LudoMove m) {
    double v = 0;
    if (m.captures.isNotEmpty) {
      v += 100;
      for (final LudoCapture c in m.captures) {
        v += c.from * 0.8;
      }
    }
    if (m.finishes) v += 70;
    final LudoState after = LudoRules.apply(s, m);
    final bool dangerBefore = LudoRules.isOnTrack(m.from) &&
        LudoRules.isThreatened(s, m.seat, m.from);
    final bool dangerAfter = LudoRules.isOnTrack(m.to) &&
        LudoRules.isThreatened(after, m.seat, m.to);
    if (dangerBefore && !dangerAfter) v += 45 + m.from * 0.4;
    if (dangerAfter) v -= 30 + m.to * 0.4;
    if (m.leavesBase) {
      v += 18;
    } else {
      final int steps = m.to - m.from;
      v += 10 + steps * 1.5;
      if (m.to > kLudoLastTrack && m.from <= kLudoLastTrack) v += 22;
      if (m.to >= 40) v += 6;
    }
    if (LudoRules.isOnTrack(m.to) &&
        LudoRules.isSafeGlobal(s.globalOf(m.seat, m.to))) {
      v += 12;
    }
    // Weigh how exposed the rest of the army is afterwards.
    int exposed = 0;
    for (int t = 0; t < kLudoTokens; t++) {
      if (t == m.token) continue;
      final int p = after.tokens[m.seat][t];
      if (LudoRules.isThreatened(after, m.seat, p)) exposed++;
    }
    v -= exposed * 6;
    return v;
  }
}
