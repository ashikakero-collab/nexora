import 'dart:math' as math;

import 'carrom_config.dart';
import 'carrom_match.dart';
import 'carrom_physics.dart';

enum CrBotLevel { easy, normal, hard }

class _Cand {
  _Cand(this.x, this.dx, this.dy, this.power, this.quality, this.order);
  final double x;
  final double dx;
  final double dy;
  final double power;
  final double quality;
  final int order;
}

/// Offline Carrom AI: builds geometric "ghost-coin" shots (coin -> pocket) plus a few free shots,
/// simulates every candidate with the SAME deterministic physics on a clone, and keeps the best.
/// Difficulty = number of candidates + aim jitter + execution noise.
/// Not part of the determinism contract (only the chosen shot is).
class CrBot {
  CrBot({required this.seat, this.level = CrBotLevel.normal, int seed = 9}) : _rng = math.Random(seed);

  final int seat;
  final CrBotLevel level;
  final math.Random _rng;

  int get candidateCount => switch (level) {
        CrBotLevel.easy => 10,
        CrBotLevel.normal => 24,
        CrBotLevel.hard => 64,
      };

  double get _aimJitter => switch (level) {
        CrBotLevel.easy => 0.06,
        CrBotLevel.normal => 0.02,
        CrBotLevel.hard => 0.005,
      };

  double get _execNoise => switch (level) {
        CrBotLevel.easy => 0.06,
        CrBotLevel.normal => 0.02,
        CrBotLevel.hard => 0.003,
      };

  double _clamp(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

  List<CrShot> candidates(CrMatch m) {
    final by = CrMatch.baselineY(seat);
    final ownK = CrMatch.kindFor(seat);
    final targets = <CrBody>[];
    for (final b in m.bodies) {
      if (!b.onBoard) continue;
      if (b.kind == ownK) targets.add(b);
      if (b.kind == CrKind.queen && m.queenCoveredBy < 0 && m.queenPendingFor != seat) targets.add(b);
    }
    const reach = CrConfig.coinR + CrConfig.strikerR;
    final geo = <_Cand>[];
    var order = 0;
    for (final t in targets) {
      for (final p in CrConfig.pockets) {
        var ux = p[0] - t.x, uy = p[1] - t.y;
        final ul = math.sqrt(ux * ux + uy * uy);
        if (ul < 1e-6) continue;
        ux /= ul;
        uy /= ul;
        final gx = t.x - ux * reach, gy = t.y - uy * reach;
        final xs = <double>[];
        if (uy.abs() > 0.05) {
          final s = (by - gy) / (-uy);
          if (s > 0) xs.add(gx - ux * s);
        }
        xs.add(gx);
        xs.add(t.x);
        for (final x0 in xs) {
          final x = m.nearestPlacement(_clamp(x0, CrConfig.baseMinX, CrConfig.baseMaxX));
          if (x == null) continue;
          final dx = gx - x, dy = gy - by;
          final dl = math.sqrt(dx * dx + dy * dy);
          if (dl < 1e-6) continue;
          final cosCut = (dx * ux + dy * uy) / dl;
          if (cosCut < 0.25) continue;
          final dist = dl + ul;
          final power = _clamp(0.26 + dist / 1900 + (1 - cosCut) * 0.35, 0.2, 1.0);
          geo.add(_Cand(x, dx / dl, dy / dl, power, cosCut * 2 - dist / 1500, order++));
        }
      }
    }
    if (level == CrBotLevel.easy) {
      geo.shuffle(_rng);
    } else {
      geo.sort((_Cand a, _Cand b) {
        final c = b.quality.compareTo(a.quality);
        return c != 0 ? c : a.order.compareTo(b.order);
      });
    }
    final out = <CrShot>[];
    final count = candidateCount;
    final takeGeo = (count * (level == CrBotLevel.easy ? 0.5 : 0.8)).round();
    for (final c in geo) {
      if (out.length >= takeGeo) break;
      out.add(_rotated(c.x, c.dx, c.dy, c.power, (_rng.nextDouble() * 2 - 1) * _aimJitter));
      if (level == CrBotLevel.hard && out.length < takeGeo) {
        out.add(_rotated(c.x, c.dx, c.dy, _clamp(c.power * 1.2, 0.2, 1.0), (_rng.nextDouble() * 2 - 1) * _aimJitter));
      }
    }
    var guard = 0;
    while (out.length < count && guard < count * 6) {
      guard++;
      final x = m.nearestPlacement(CrConfig.baseMinX + _rng.nextDouble() * (CrConfig.baseMaxX - CrConfig.baseMinX));
      if (x == null) break;
      final tx = CrConfig.centerX + (_rng.nextDouble() * 2 - 1) * 170;
      final ty = CrConfig.centerY + (_rng.nextDouble() * 2 - 1) * 170;
      final dx = tx - x, dy = ty - by;
      final dl = math.sqrt(dx * dx + dy * dy);
      if (dl < 1e-6) continue;
      out.add(CrShot(placeX: x, dirX: dx / dl, dirY: dy / dl, power: 0.55 + _rng.nextDouble() * 0.45));
    }
    return out;
  }

  CrShot _rotated(double x, double dx, double dy, double power, double ang) {
    final c = math.cos(ang), s = math.sin(ang);
    return CrShot(placeX: x, dirX: dx * c - dy * s, dirY: dx * s + dy * c, power: power);
  }

  /// Simulates [shot] on a clone of [m] and scores the result (null if illegal).
  double? evaluate(CrMatch m, CrShot shot) {
    if (m.turn != seat) return null;
    final sim = m.clone();
    if (sim.validate(shot) != null) return null;
    final out = sim.playShot(shot);
    return score(m, sim, out);
  }

  double score(CrMatch before, CrMatch after, CrTurnOutcome o) {
    final w = after.winner;
    if (w == seat) return 1e6;
    if (w == 1 - seat) return -1e6;
    var s = 0.0;
    s += 120.0 * (before.remaining(seat) - after.remaining(seat));
    s -= 80.0 * (before.remaining(1 - seat) - after.remaining(1 - seat));
    if (o.foul) s -= 260;
    if (o.queenCovered) s += 220;
    if (after.queenPendingFor == seat) s += 60;
    if (o.continueTurn) s += 40;
    final ownK = CrMatch.kindFor(seat);
    for (final b in after.bodies) {
      if (!b.onBoard || b.isStriker) continue;
      var best = 1e9;
      for (final p in CrConfig.pockets) {
        final dx = b.x - p[0], dy = b.y - p[1];
        final d = math.sqrt(dx * dx + dy * dy);
        if (d < best) best = d;
      }
      final close = math.max(0.0, 1 - best / 450);
      if (b.kind == ownK) {
        s += 18 * close;
      } else if (!o.continueTurn && b.kind != CrKind.queen) {
        s -= 14 * close;
      }
    }
    return s;
  }

  /// Adds the level's execution error to the chosen shot (keeps the placement).
  CrShot withExecutionNoise(CrShot s) => _rotated(s.placeX, s.dirX, s.dirY, s.power, (_rng.nextDouble() * 2 - 1) * _execNoise);

  CrShot fallback(CrMatch m) {
    final x = m.nearestPlacement(CrConfig.centerX) ?? CrConfig.centerX;
    return CrShot(placeX: x, dirX: 0, dirY: seat == 0 ? -1 : 1, power: 0.8);
  }

  /// Synchronous search (tests / server).
  CrShot choose(CrMatch m) {
    final search = CrBotSearch(this, m);
    while (!search.step(1000)) {}
    return search.best;
  }
}

/// Incremental search so the UI can spread the work over several frames.
class CrBotSearch {
  CrBotSearch(this.bot, CrMatch match)
      : _base = match.clone(),
        _cands = bot.candidates(match);

  final CrBot bot;
  final CrMatch _base;
  final List<CrShot> _cands;
  int _i = 0;
  CrShot? _best;
  double _bestScore = -1e18;

  bool get done => _i >= _cands.length;
  double get progress => _cands.isEmpty ? 1 : _i / _cands.length;

  bool step(int budget) {
    var n = 0;
    while (_i < _cands.length && n < budget) {
      final shot = _cands[_i];
      _i++;
      n++;
      final s = bot.evaluate(_base, shot);
      if (s != null && s > _bestScore) {
        _bestScore = s;
        _best = shot;
      }
    }
    return done;
  }

  CrShot get best => _best ?? bot.fallback(_base);
}
