// 'stars' (default) profile: Soccer Stars feel with a pool-ball ball. Checks the feel contract from the brief.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/game/engine.dart';

MatchCfg _cfg({bool ai = false}) => MatchCfg(
    field: 0, ball: 0, forms: [0, 0], ai: ai, aiLvl: 1, limit: 99, matchTime: 0, turnTime: 0,
    vip: [false, false], first: 0); // profile omitted on purpose: 'stars' must be the default

/// Engine with only [keep] discs plus the ball (parked far away when not used).
Engine _lab(int keep) {
  final e = Engine(_cfg(), rand: math.Random(3).nextDouble);
  final discs = e.bodies.where((b) => !identical(b, e.ball)).take(keep).toList();
  e.bodies
    ..clear()
    ..addAll(discs)
    ..add(e.ball);
  for (final b in e.bodies) {
    b.vx = b.vy = 0;
  }
  e.ball.x = e.Fr - 120;
  e.ball.y = e.CY;
  return e;
}

void _place(Body b, double x, double y, double vx, double vy) {
  b.x = b.px = x;
  b.y = b.py = y;
  b.vx = vx;
  b.vy = vy;
}

double _spd(Body b) => math.sqrt(b.vx * b.vx + b.vy * b.vy);

/// run until [b] stops, return the distance it travelled
double _glide(Engine e, Body b) {
  final x0 = b.x, y0 = b.y;
  for (var i = 0; i < 60 * 30 && (b.vx != 0 || b.vy != 0); i++) {
    e.update(1 / 60);
  }
  expect(_spd(b), 0);
  return math.sqrt((b.x - x0) * (b.x - x0) + (b.y - y0) * (b.y - y0));
}

void main() {
  test('stars is the default profile', () {
    final e = Engine(_cfg());
    expect(e.cfg.profile, 'stars');
    expect(e.tu, same(kTuneStars));
    expect(1 / e.ball.im, lessThan(1 / e.bodies.first.im)); // ball lighter than a disc
  });

  test('ball glides further than a disc (same speed, and same impulse)', () {
    for (final (dv, bv) in [(800.0, 800.0), (300.0, 300.0 * kTuneStars.discM / kTuneStars.ballM)]) {
      final e1 = _lab(1), d = e1.bodies.first;
      _place(d, e1.Fl + 150, e1.Fb - 150, 0, -dv);
      final dd = _glide(e1, d);
      final e2 = _lab(0);
      _place(e2.ball, e2.Fl + 150, e2.Fb - 150, 0, -bv);
      final bd = _glide(e2, e2.ball);
      // ignore: avoid_print
      print('glide: disc ${dv.round()} px/s -> ${dd.toStringAsFixed(1)} px, ball ${bv.round()} px/s -> ${bd.toStringAsFixed(1)} px');
      expect(bd, greaterThan(dd * 1.4));
    }
  });

  test('ball-cushion rebound keeps ~0.9 of the normal speed, tangential kept', () {
    final e = _lab(0), b = e.ball;
    _place(b, e.Fl + 200, e.CY, -1200, 300);
    var pre = (0.0, 0.0);
    for (var i = 0; i < 120; i++) {
      final before = (b.vx, b.vy);
      e.update(1 / 60);
      if (before.$1 < 0 && b.vx > 0) {
        pre = before;
        break;
      }
    }
    expect(pre.$1, lessThan(0), reason: 'ball never reached the wall');
    final rn = b.vx / -pre.$1, rt = b.vy / pre.$2;
    // ignore: avoid_print
    print('cushion: normal ${rn.toStringAsFixed(3)}, tangential ${rt.toStringAsFixed(3)} (incl. one frame of rolling friction)');
    expect(rn, inInclusiveRange(.85, .92));
    expect(rt, greaterThan(.93));
  });

  test('head-on equal-mass disc collision transfers ~all momentum', () {
    final e = _lab(2), a = e.bodies[0], c = e.bodies[1];
    _place(a, e.CX - 150, e.CY + 200, 0, -1000);
    _place(c, e.CX - 150, e.CY - 20, 0, 0);
    var hit = false;
    double va = 0;
    for (var i = 0; i < 60 && !hit; i++) {
      va = -a.vy;
      e.update(1 / 60);
      hit = c.vy != 0;
    }
    expect(hit, isTrue);
    final pa = -a.vy, pc = -c.vy, frac = pc / (pa + pc);
    // ignore: avoid_print
    print('head-on: striker ${va.toStringAsFixed(0)} -> ${pa.toStringAsFixed(1)}, target -> ${pc.toStringAsFixed(1)}, share ${frac.toStringAsFixed(3)}');
    expect(frac, greaterThan(.9));
    expect(c.vx.abs() + a.vx.abs(), lessThan(1e-9)); // pure normal impulse on a centred hit
  });

  test('deterministic: same inputs -> identical outputs (AI vs AI, 3000 frames)', () {
    List<double> run() {
      final e = Engine(_cfg(ai: true), rand: math.Random(42).nextDouble);
      e.aiTeams[0] = true;
      final out = <double>[];
      for (var f = 0; f < 3000; f++) {
        e.update(f % 3 == 0 ? 1 / 50 : 1 / 60);
        if (f % 25 == 0) {
          for (final b in e.bodies) {
            out..add(b.x)..add(b.y)..add(b.vx)..add(b.vy);
          }
          out..add(e.score[0].toDouble())..add(e.score[1].toDouble())..add(e.shots.toDouble());
        }
      }
      return out;
    }

    final a = run(), b = run();
    expect(a.length, b.length);
    for (var i = 0; i < a.length; i++) {
      expect(a[i], b[i]); // bit-identical
    }
    expect(a.any((v) => v.isNaN), isFalse);
  });
}
