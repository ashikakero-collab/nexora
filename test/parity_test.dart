// Physics parity: the Dart engine must reproduce the original TypeScript engine (run under node/tsx
// by tool/parity/run_ts.ts -> test/fixtures/parity_ts.json) on identical deterministic scenarios.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/game/engine.dart';

/// mulberry32, bit-identical to the JS version used by run_ts.ts.
double Function() mulberry32(int seed) {
  var a = seed & 0xffffffff;
  int imul(int x, int y) => ((x & 0xffffffff) * (y & 0xffffffff)) & 0xffffffff;
  return () {
    a = (a + 0x6D2B79F5) & 0xffffffff;
    var t = imul(a ^ (a >> 15), 1 | a);
    t = ((t + imul(t ^ (t >> 7), 61 | t)) & 0xffffffff) ^ t;
    return ((t ^ (t >> 14)) & 0xffffffff) / 4294967296;
  };
}

// The TS reference itself is platform dependent at the last bit (V8's fdlibm is compiled with FMA contraction on
// arm64; Hermes on phones uses the system libm), so parity is checked to a tolerance far below one pixel.
const double kTol = 1e-4; // world units (a disc is 98 units wide, one screen pixel is ~2.5 units)

void main() {
  final scen = (jsonDecode(File('tool/parity/scenarios.json').readAsStringSync()) as List).cast<Map<String, dynamic>>();
  final ref = (jsonDecode(File('test/fixtures/parity_ts.json').readAsStringSync()) as List).cast<Map<String, dynamic>>();

  for (var si = 0; si < scen.length; si++) {
    final s = scen[si];
    test('parity ${s['name']}', () {
      final rnd = mulberry32(12345);
      final stats = s['stats'] as List?;
      final cfg = MatchCfg(
        field: s['field'],
        ball: s['ball'],
        forms: (s['forms'] as List).cast<int>(),
        ai: s['ai'],
        aiLvl: s['aiLvl'],
        limit: s['limit'],
        matchTime: (s['matchTime'] as num).toDouble(),
        turnTime: (s['turnTime'] as num).toDouble(),
        vip: (s['vip'] as List).cast<bool>(),
        first: s['first'],
        stats: stats?.map((x) => DiscStats((x[0] as num).toDouble(), (x[1] as num).toDouble())).toList(),
        profile: 'classic', // parity is against the RN TypeScript engine
      );
      final e = Engine(cfg, rand: rnd);
      if (s['aiTeam0'] == true) e.aiTeams[0] = true;
      final dts = (s['dt'] as List).map((x) => (x as num).toDouble()).toList();
      final shots = (s['shots'] as List).cast<Map<String, dynamic>>();
      final human = s['human'] == true;
      final r = ref[si];
      expect(r['name'], s['name']);
      final cps = (r['cps'] as List).cast<Map<String, dynamic>>();
      final evs = <String>[];
      var ci = 0;
      var maxErr = 0.0, maxR = 0.0;
      for (var fr = 0; fr < (s['frames'] as int); fr++) {
        for (final sh in shots) {
          if (sh['f'] == fr && e.phase == Phase.aim) {
            final mine = e.bodies.where((x) => x.team == e.turn).toList();
            final idx = (sh['b'] as int) % 5;
            final b = idx < mine.length ? mine[idx] : e.bodies[0];
            final dx = (sh['dx'] as num).toDouble(), dy = (sh['dy'] as num).toDouble();
            e.fire(b, dx, dy, hyp(dx, dy), human);
          }
        }
        e.update(dts[fr % dts.length]);
        for (var i = 0; i < e.eventCount; i++) {
          final ev = e.event(i);
          final hasTeam = ev.t == EvType.goal || ev.t == EvType.turn || ev.t == EvType.shot;
          evs.add('$fr:${ev.t.name}${hasTeam ? ev.team : ''}${ev.t == EvType.goal ? (ev.nogoal ? 'n' : 'y') : ''}');
        }
        e.clearEvents();
        if (fr % 20 == 19 || fr == (s['frames'] as int) - 1) {
          final c = cps[ci++];
          expect(c['f'], fr);
          expect(e.phase.name, c['ph'], reason: 'phase @frame $fr');
          expect(e.turn, c['tu'], reason: 'turn @frame $fr');
          expect(e.score, (c['sc'] as List).cast<int>(), reason: 'score @frame $fr');
          expect(e.bodies.length, c['n']);
          expect(e.nParts, c['parts'], reason: 'particles @frame $fr');
          final bb = (c['b'] as List).map((x) => (x as num).toDouble()).toList();
          for (var i = 0; i < e.bodies.length; i++) {
            final b = e.bodies[i];
            final vals = [b.x, b.y, b.vx, b.vy, b.ang];
            for (var k = 0; k < 5; k++) {
              final err = (vals[k] - bb[i * 5 + k]).abs();
              final tol = k >= 2 && k < 4 ? kTol * 100 : kTol; // velocities are ~100x larger in magnitude
              if (err > maxErr && k < 2) maxErr = err;
              expect(err <= tol, true, reason: '${s['name']} body $i field $k @frame $fr: dart=${vals[k]} ts=${bb[i * 5 + k]}');
            }
          }
          final rr = (c['R'] as List).map((x) => (x as num).toDouble()).toList();
          for (var k = 0; k < 9; k++) {
            final er = (e.ball.R[k] - rr[k]).abs();
            if (er > maxR) maxR = er;
            // the ball's 3D orientation is visual only; it accumulates thousands of rotations
            expect(er < 1e-4, true, reason: 'ball R[$k] @frame $fr: ${e.ball.R[k]} vs ${rr[k]}');
          }
          expect(((e.acc) - (c['acc'] as num)).abs() < 1e-9, true, reason: 'accumulator @frame $fr');
        }
      }
      expect(evs, (r['evs'] as List).cast<String>(), reason: 'event stream');
      // ignore: avoid_print
      print('${s['name']}: ${cps.length} checkpoints, ${evs.length} events, max position error ${maxErr.toStringAsExponential(2)}, max ball-orientation error ${maxR.toStringAsExponential(2)}');
    });
  }
}
