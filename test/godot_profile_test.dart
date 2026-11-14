// 'godot' profile vs the real Godot build: test/fixtures/godot_nx8.json is produced by running Nexora_godot's
// src/game/engine.gd (nx8 @48fcadf) headless with Godot 4.5.1 (tool/godot/nx8_ref.gd, Flutter field geometry):
//   cd nexora_godot_ref && /workspace/tools/godot --headless --path . -s <flutter>/tool/godot/nx8_ref.gd -- <out.json>
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/game/engine.dart';

void main() {
  final ref = (jsonDecode(File('test/fixtures/godot_nx8.json').readAsStringSync()) as List).cast<Map<String, dynamic>>();
  for (final s in ref) {
    test('godot nx8 parity ${s['name']}', () {
      final e = Engine(
          MatchCfg(
            field: s['field'], ball: 0, forms: (s['forms'] as List).cast<int>(), ai: false, aiLvl: 1, limit: 99,
            matchTime: 0, turnTime: 0, vip: [false, false], first: 0, profile: 'godot'),
          rand: math.Random(1).nextDouble);
      e.clearEvents();
      final pw = (s['pw'] as List).map((x) => (x as num).toDouble()).toList();
      final cps = (s['cps'] as List).cast<Map<String, dynamic>>();
      final evs = <String>[];
      var si = 0, ci = 0;
      var maxErr = 0.0;
      for (var fr = 0; fr < (s['frames'] as int); fr++) {
        if (e.phase == Phase.aim && si < pw.length) {
          Body? best;
          var bd = 1e18;
          for (final b in e.bodies) {
            if (b.team == e.turn && !identical(b, e.ball)) {
              final d2 = (b.x - e.ball.x) * (b.x - e.ball.x) + (b.y - e.ball.y) * (b.y - e.ball.y);
              if (d2 < bd) {
                bd = d2;
                best = b;
              }
            }
          }
          final dx = e.ball.x - best!.x, dy = e.ball.y - best.y, l = math.sqrt(dx * dx + dy * dy), L = pw[si] * LMAX;
          e.fire(best, dx / l * L, dy / l * L, L);
          si++;
        }
        e.update(1 / 60);
        for (var i = 0; i < e.eventCount; i++) {
          evs.add(e.event(i).t.name);
        }
        e.clearEvents();
        if (fr % 10 == 9) {
          final cp = cps[ci++];
          expect(cp['f'], fr);
          final bs = (cp['b'] as List).cast<List>();
          expect(e.bodies.length, bs.length);
          for (var i = 0; i < bs.length; i++) {
            final b = e.bodies[i];
            maxErr = math.max(maxErr, (b.x - (bs[i][0] as num)).abs());
            maxErr = math.max(maxErr, (b.y - (bs[i][1] as num)).abs());
          }
          expect(e.turn, cp['turn'], reason: 'turn @${cp['f']}');
          expect(e.phase.name, cp['phase'], reason: 'phase @${cp['f']}');
          expect([e.score[0], e.score[1]], (cp['score'] as List).cast<int>());
        }
      }
      // ignore: avoid_print
      print('${s['name']}: ${cps.length} checkpoints, ${evs.length} events, max position error ${maxErr.toStringAsExponential(2)}');
      expect(evs, (s['evs'] as List).cast<String>());
      expect(maxErr, lessThan(1e-3));
    });
  }
}
