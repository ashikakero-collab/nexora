// v4: per-disc stats really change play. Power scales the shot (+-25%), accuracy shrinks the aim deviation,
// and the per-team defaults differ deterministically (shared by every online peer).
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/game/data.dart';
import 'package:nexora/game/engine.dart';

MatchCfg _cfg(List<DiscStats> st) => MatchCfg(
    field: 0, ball: 0, forms: [0, 0], ai: false, aiLvl: 1, limit: 99, matchTime: 0, turnTime: 0,
    vip: [false, false], first: 0, stats: st);

double _shot(double power) {
  final e = Engine(_cfg([DiscStats(power, 5), DiscStats.def]), rand: math.Random(1).nextDouble);
  final b = e.bodies.firstWhere((x) => x.team == 0);
  final discs = [b, e.ball];
  e.bodies
    ..clear()
    ..addAll(discs);
  e.ball.x = e.ball.px = e.Fr - 80;
  e.ball.y = e.ball.py = e.Ft + 80;
  b.x = b.px = e.Fl + 120;
  b.y = b.py = e.Fb - 120;
  e.fire(b, 0, -1e6, 1e6); // full power straight up the pitch (dx, dy = drag vector, l = its length)
  final v0 = math.sqrt(b.vx * b.vx + b.vy * b.vy);
  final y0 = b.y;
  for (var i = 0; i < 60 * 20 && (b.vx != 0 || b.vy != 0); i++) {
    e.update(1 / 60);
  }
  // ignore: avoid_print
  print('power ${power.toStringAsFixed(1)}: launch ${v0.toStringAsFixed(0)} px/s, travel ${(y0 - b.y).toStringAsFixed(0)} px');
  return y0 - b.y;
}

void main() {
  test('higher power -> faster and farther shot', () {
    final lo = _shot(1), mid = _shot(5.5), hi = _shot(10);
    expect(hi, greaterThan(mid));
    expect(mid, greaterThan(lo));
  });

  test('power is exact and linear: launch(5) / launch(10) = 0.5, launch(8) / launch(10) = 0.8', () {
    double launch(double pw) {
      final e = Engine(_cfg([DiscStats(pw, 10), DiscStats.def]), rand: math.Random(1).nextDouble);
      final b = e.bodies.firstWhere((x) => x.team == 0);
      e.fire(b, 0, -1e6, 1e6);
      return math.sqrt(b.vx * b.vx + b.vy * b.vy);
    }

    final v10 = launch(10), v5 = launch(5), v8 = launch(8), v1 = launch(1);
    expect(v5 / v10, closeTo(.5, .005));
    expect(v8 / v10, closeTo(.8, .008));
    expect(v1, greaterThan(0));
    expect(v10, closeTo(kTuneStars.discVmax, 1e-6));
  });

  test('accuracy reduces deviation', () {
    expect(aimDevDeg(10), 0);
    expect(aimDevDeg(1), greaterThan(aimDevDeg(6)));
    expect(aimPreview(10), greaterThan(aimPreview(3)));
  });

  test('team default stats are deterministic and differ', () {
    final a = teamStatsFor('club0'), b = teamStatsFor('club1'), c = teamStatsFor('leg0');
    expect(teamStatsFor('club0'), a);
    expect(a == b && b == c, isFalse);
    for (final t in kTeams) {
      final (p, q) = teamStatsFor(t.id);
      expect(p, inInclusiveRange(1, 10));
      expect(q, inInclusiveRange(1, 10));
    }
  });
}
