import 'dart:math' as math;

import 'pool_config.dart';
import 'pool_match.dart';
import 'pool_physics.dart';

enum PoolBotLevel { easy, normal, hard }

class _Cand {
  _Cand(this.dirX, this.dirY, this.power, this.prior, {this.spin = 0, this.cueX, this.cueY});
  final double dirX;
  final double dirY;
  final double power;
  final double prior;
  final double spin;
  final double? cueX;
  final double? cueY;
  double score = -double.infinity;

  PoolShot toShot() => PoolShot(dirX: dirX, dirY: dirY, power: power, spin: spin, cueX: cueX, cueY: cueY);
}

/// Offline AI. Builds candidate shots from ghost-ball geometry (every legal ball
/// x every pocket), simulates each one with the real physics on a clone of the
/// match, scores the outcome, then adds aim noise by difficulty.
///
/// Incremental: call [step] once per frame until it returns true, then [result].
class PoolBotPlanner {
  PoolBotPlanner({required PoolMatch match, required this.level, required math.Random rng})
      : _base = match.clone(),
        _rng = rng,
        player = match.current {
    _build();
  }

  final PoolMatch _base;
  final PoolBotLevel level;
  final math.Random _rng;
  final int player;
  final List<_Cand> _cands = <_Cand>[];
  int _next = 0;

  int get candidateCount => _cands.length;
  bool get done => _next >= _cands.length;

  static const double _r = PoolConfig.ballR;

  // ---------------------------------------------------------------- candidates
  void _build() {
    final PoolMatch m = _base;
    if (m.isBreak) {
      final List<double> offs = level == PoolBotLevel.easy ? <double>[0] : <double>[0, -70, 70];
      final PoolBall apex = m.balls[1];
      for (final double o in offs) {
        final double cx = PoolConfig.breakCueX + o, cy = PoolConfig.breakCueY;
        if (!m.canPlaceCue(cx, cy)) continue;
        final double p = level == PoolBotLevel.easy ? 0.8 : 1.0;
        _cands.add(_Cand(apex.x - cx, apex.y - cy, p, 1, cueX: cx, cueY: cy));
      }
      return;
    }
    final List<int> targets = m.legalTargets(player);
    final List<_Cand> pots = <_Cand>[];
    for (final int t in targets) {
      final PoolBall b = m.balls[t];
      for (int p = 0; p < 6; p++) {
        final double px = PoolConfig.pocketAim[p][0], py = PoolConfig.pocketAim[p][1];
        double ux = px - b.x, uy = py - b.y;
        final double dBP = math.sqrt(ux * ux + uy * uy);
        if (dBP < 1) continue;
        ux /= dBP;
        uy /= dBP;
        // side pockets accept only fairly direct approaches
        if (p == 2 && ux > -0.35) continue;
        if (p == 3 && ux < 0.35) continue;
        final double gx = b.x - ux * 2 * _r, gy = b.y - uy * 2 * _r;
        if (_blocked(m, b.x, b.y, px, py, t, -1)) continue;
        if (m.ballInHand) {
          for (final double d in <double>[120, 240]) {
            final double cx = gx - ux * d, cy = gy - uy * d;
            if (!m.canPlaceCue(cx, cy)) continue;
            if (_blocked(m, cx, cy, gx, gy, t, 0)) continue;
            final double power = _powerFor(d + dBP, 1);
            final double prior = 3 - dBP / 1500;
            pots.add(_Cand(ux, uy, power, prior, cueX: cx, cueY: cy));
          }
        } else {
          final PoolBall c = m.cue;
          double vx = gx - c.x, vy = gy - c.y;
          final double dCG = math.sqrt(vx * vx + vy * vy);
          if (dCG < 1) continue;
          vx /= dCG;
          vy /= dCG;
          final double cut = vx * ux + vy * uy;
          if (cut < 0.22) continue;
          if (_blocked(m, c.x, c.y, gx, gy, t, 0)) continue;
          final double power = _powerFor(dCG + dBP / cut, cut);
          final double prior = cut * 2 - (dCG + dBP) / 1800;
          pots.add(_Cand(vx, vy, power, prior));
        }
      }
    }
    pots.sort((_Cand a, _Cand b) => b.prior.compareTo(a.prior));
    final int keep = level == PoolBotLevel.easy ? 5 : (level == PoolBotLevel.normal ? 12 : 20);
    for (int i = 0; i < pots.length && i < keep; i++) {
      final _Cand c = pots[i];
      _cands.add(c);
      if (level != PoolBotLevel.easy) {
        _cands.add(_Cand(c.dirX, c.dirY, math.min(1.0, c.power * 1.3), c.prior, cueX: c.cueX, cueY: c.cueY));
      }
      if (level == PoolBotLevel.hard) {
        _cands.add(_Cand(c.dirX, c.dirY, c.power, c.prior, spin: -0.6, cueX: c.cueX, cueY: c.cueY));
        _cands.add(_Cand(c.dirX, c.dirY, math.max(0.12, c.power * 0.8), c.prior, spin: 0.5, cueX: c.cueX, cueY: c.cueY));
      }
    }
    // contact / safety shots: straight at each legal ball
    final double? hx = m.ballInHand ? PoolConfig.tableW / 2 : null;
    double? hy;
    if (hx != null) {
      hy = PoolConfig.breakCueY;
      if (!m.canPlaceCue(hx, hy)) hy = _freeSpotY(m, hx);
    }
    final double cx = hx ?? m.cue.x, cy = hy ?? m.cue.y;
    for (final int t in targets) {
      final PoolBall b = m.balls[t];
      final double dx = b.x - cx, dy = b.y - cy;
      final double d = math.sqrt(dx * dx + dy * dy);
      if (d < 1) continue;
      if (_blocked(m, cx, cy, b.x, b.y, t, 0)) continue;
      _cands.add(_Cand(dx / d, dy / d, 0.30, 0, cueX: hx, cueY: hy));
      if (level == PoolBotLevel.hard) _cands.add(_Cand(dx / d, dy / d, 0.45, 0, cueX: hx, cueY: hy));
    }
    if (_cands.isEmpty) {
      // nothing obvious: deterministic fan of directions
      for (int k = 0; k < 12; k++) {
        final double a = k * math.pi / 6;
        _cands.add(_Cand(math.cos(a), math.sin(a), 0.4, -1, cueX: hx, cueY: hy));
      }
    }
  }

  double _freeSpotY(PoolMatch m, double x) {
    double y = PoolConfig.tableH - _r * 2;
    while (y > _r * 2 && !m.canPlaceCue(x, y)) {
      y -= 7;
    }
    return y;
  }

  static double _powerFor(double travel, double cut) {
    double p = 0.10 + travel / 4200 + (1 - cut) * 0.12;
    if (p < 0.12) p = 0.12;
    if (p > 0.85) p = 0.85;
    return p;
  }

  /// Is the corridor of width 2r from (x1,y1) to (x2,y2) obstructed by a ball
  /// other than [ignoreA] / [ignoreB]?
  static bool _blocked(PoolMatch m, double x1, double y1, double x2, double y2, int ignoreA, int ignoreB) {
    final double ex = x2 - x1, ey = y2 - y1;
    final double l2 = ex * ex + ey * ey;
    if (l2 <= 0) return false;
    for (int i = 0; i < m.balls.length; i++) {
      if (i == ignoreA || i == ignoreB) continue;
      final PoolBall b = m.balls[i];
      if (b.pocketed) continue;
      final double t = ((b.x - x1) * ex + (b.y - y1) * ey) / l2;
      if (t <= 0 || t >= 1) continue;
      final double qx = x1 + ex * t, qy = y1 + ey * t;
      final double dx = b.x - qx, dy = b.y - qy;
      if (dx * dx + dy * dy < (2 * _r - 1) * (2 * _r - 1)) return true;
    }
    return false;
  }

  // ---------------------------------------------------------------- evaluation
  /// Evaluates up to [maxEvals] candidates. Returns true when all are evaluated.
  bool step([int maxEvals = 2]) {
    int n = 0;
    while (_next < _cands.length && n < maxEvals) {
      final _Cand c = _cands[_next];
      c.score = _evaluate(c);
      _next++;
      n++;
    }
    return done;
  }

  /// Runs everything synchronously (tests).
  PoolShot plan() {
    while (!step(64)) {}
    return result();
  }

  double _evaluate(_Cand c) {
    final PoolMatch sim = _base.clone();
    final int ownBefore = sim.groups[player] == PoolGroup.none ? 0 : sim.remainingOf(sim.groups[player]);
    final PoolShotReport? r = sim.playShot(c.toShot());
    if (r == null) return -1e9;
    if (sim.isOver) return sim.winner == player ? 1e6 : -1e6;
    double s = c.prior * 10;
    if (r.isFoul) s -= 2500;
    final PoolGroup g = sim.groups[player];
    if (g != PoolGroup.none) {
      final int ownAfter = sim.remainingOf(g);
      final int before = r.assigned != PoolGroup.none ? 7 : ownBefore;
      s += (before - ownAfter) * 400;
      final int oppPotted = r.pocketed.where((int id) => id != 0 && id != 8 && poolGroupOf(id) != g).length;
      s -= oppPotted * 250;
    }
    if (r.continues) {
      s += 1500 + _easyShots(sim, player) * 140;
    } else if (!r.isFoul && level == PoolBotLevel.hard) {
      s -= _easyShots(sim, 1 - player) * 90;
    }
    return s;
  }

  /// Number of open straight-ish pots available to [who] from the current cue spot.
  static int _easyShots(PoolMatch m, int who) {
    final PoolBall c = m.cue;
    int n = 0;
    for (final int t in m.legalTargets(who)) {
      final PoolBall b = m.balls[t];
      for (int p = 0; p < 6; p++) {
        final double px = PoolConfig.pocketAim[p][0], py = PoolConfig.pocketAim[p][1];
        double ux = px - b.x, uy = py - b.y;
        final double dBP = math.sqrt(ux * ux + uy * uy);
        if (dBP < 1) continue;
        ux /= dBP;
        uy /= dBP;
        final double gx = b.x - ux * 2 * _r, gy = b.y - uy * 2 * _r;
        double vx = gx - c.x, vy = gy - c.y;
        final double d = math.sqrt(vx * vx + vy * vy);
        if (d < 1) continue;
        vx /= d;
        vy /= d;
        if (vx * ux + vy * uy < 0.55) continue;
        if (_blocked(m, c.x, c.y, gx, gy, t, 0) || _blocked(m, b.x, b.y, px, py, t, -1)) continue;
        n++;
        break;
      }
      if (n >= 4) break;
    }
    return n;
  }

  /// Best candidate with difficulty-scaled aim/power noise applied.
  PoolShot result() {
    if (_cands.isEmpty) {
      return const PoolShot(dirX: 0, dirY: -1, power: 0.5);
    }
    final List<_Cand> sorted = List<_Cand>.from(_cands)..sort((_Cand a, _Cand b) => b.score.compareTo(a.score));
    _Cand pick = sorted.first;
    if (level == PoolBotLevel.easy && sorted.length > 1 && _rng.nextDouble() < 0.35) {
      pick = sorted[_rng.nextInt(math.min(3, sorted.length))];
    }
    final double noiseDeg = level == PoolBotLevel.easy ? 2.6 : (level == PoolBotLevel.normal ? 1.0 : 0.3);
    final double pNoise = level == PoolBotLevel.easy ? 0.08 : (level == PoolBotLevel.normal ? 0.04 : 0.015);
    final double gauss = (_rng.nextDouble() + _rng.nextDouble() + _rng.nextDouble() - 1.5) / 1.5;
    final double a = gauss * noiseDeg * math.pi / 180;
    final double ca = math.cos(a), sa = math.sin(a);
    final double dx = pick.dirX * ca - pick.dirY * sa;
    final double dy = pick.dirX * sa + pick.dirY * ca;
    double p = pick.power * (1 + (_rng.nextDouble() * 2 - 1) * pNoise);
    if (p > 1) p = 1;
    if (p < 0.08) p = 0.08;
    return PoolShot(dirX: dx, dirY: dy, power: p, spin: pick.spin, cueX: pick.cueX, cueY: pick.cueY);
  }
}
