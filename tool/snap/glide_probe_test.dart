import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/game/engine.dart';
void main() {
  test('probe', () {
    for (final ball in [false, true]) {
      for (final v in [400.0, 800.0, 1500.0, 2200.0]) {
        final e = Engine(MatchCfg(field: 0, ball: 0, forms: [0, 0], ai: false, aiLvl: 1, limit: 99, matchTime: 0, turnTime: 0, vip: [false, false], first: 0));
        final b = ball ? e.ball : e.bodies.first;
        e.bodies..clear()..add(b);
        b.x = b.px = e.CX; b.y = b.py = e.Fb - 60; b.vx = 0; b.vy = -v;
        var t = 0.0, dist = 0.0, half = 0.0;
        for (var i = 0; i < 60 * 30 && (b.vx != 0 || b.vy != 0); i++) {
          final y0 = b.y, x0 = b.x;
          e.update(1 / 60); t += 1 / 60;
          dist += math.sqrt((b.x - x0) * (b.x - x0) + (b.y - y0) * (b.y - y0));
          if (half == 0 && math.sqrt(b.vx * b.vx + b.vy * b.vy) < v / 2) half = t;
        }
        // ignore: avoid_print
        print('${ball ? 'ball' : 'disc'} $v: path ${dist.round()} px, half-speed at ${half.toStringAsFixed(2)} s, rest at ${t.toStringAsFixed(2)} s');
      }
    }
  });
}
