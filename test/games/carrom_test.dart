import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/games/carrom/core/carrom_bot.dart';
import 'package:nexora/games/carrom/core/carrom_config.dart';
import 'package:nexora/games/carrom/core/carrom_match.dart';
import 'package:nexora/games/carrom/core/carrom_physics.dart';

/// Simulates the end of a shot by [m.turn] where [ids] fell into pockets.
CrTurnOutcome fakeShot(CrMatch m, List<int> ids) {
  final x = m.nearestPlacement(CrConfig.centerX) ?? CrConfig.centerX;
  m.beginShot(CrShot(placeX: x, dirX: 0, dirY: m.turn == 0 ? -1 : 1, power: 0.1));
  for (final b in m.bodies) {
    b.vx = 0;
    b.vy = 0;
  }
  for (final id in ids) {
    m.bodies[id].onBoard = false;
  }
  return m.finishShot(ids, 1);
}

void main() {
  test('rack: 9 white, 9 black, 1 queen, no overlaps', () {
    final bs = crInitialBodies();
    expect(bs.length, CrConfig.bodyCount);
    expect(bs.where((CrBody b) => b.kind == CrKind.white).length, 9);
    expect(bs.where((CrBody b) => b.kind == CrKind.black).length, 9);
    expect(bs.where((CrBody b) => b.kind == CrKind.queen).length, 1);
    expect(bs[CrConfig.queenId].isQueen, isTrue);
    expect(bs[CrConfig.strikerId].isStriker, isTrue);
    for (var i = 1; i < bs.length; i++) {
      for (var j = i + 1; j < bs.length; j++) {
        final d = math.sqrt(math.pow(bs[i].x - bs[j].x, 2) + math.pow(bs[i].y - bs[j].y, 2));
        expect(d, greaterThanOrEqualTo(bs[i].r + bs[j].r - 1e-6), reason: 'bodies $i and $j overlap');
      }
    }
  });

  test('simulation is deterministic (same shot twice -> same hash)', () {
    int run() {
      final m = CrMatch.newBoard();
      m.playShot(const CrShot(placeX: 512, dirX: 0.03, dirY: -1, power: 1));
      final x = m.nearestPlacement(m.turn == 0 ? 300 : 700) ?? CrConfig.centerX;
      m.playShot(CrShot(placeX: x, dirX: -0.4, dirY: m.turn == 0 ? -1 : 1, power: 0.75));
      return m.stateHash();
    }

    expect(run(), run());
  });

  test('golden vector matches JS reference (carrom_ref.mjs)', () {
    final m = CrMatch.newBoard();
    final o1 = m.playShot(const CrShot(placeX: 512, dirX: 0.03, dirY: -1, power: 1));
    expect(o1.steps, 433);
    expect(o1.foul, isFalse);
    expect(m.stateHash(), 3664971594);
    expect(m.turn, 1);
    expect(m.queen.x, closeTo(469.47, 1e-9));
    expect(m.queen.y, closeTo(322.211, 1e-9));
    expect(o1.oppPocketed, 1); // body 16 (black)
    expect(m.bodies[16].onBoard, isFalse);
    // Note: the JS reference's shot 2 (placeX 700) is not a legal placement in the Dart
    // rules engine (striker overlaps a coin), so parity is asserted on shot 1 only.
    expect(m.placementOk(700), isFalse);
  });

  test('pocketing an own coin continues the turn, opponent coin does not', () {
    final m = CrMatch.newBoard();
    final o = fakeShot(m, <int>[1]);
    expect(o.continueTurn, isTrue);
    expect(m.turn, 0);
    expect(m.pocketedCount(0), 1);
    final o2 = fakeShot(m, <int>[10]);
    expect(o2.continueTurn, isFalse);
    expect(m.turn, 1);
    expect(m.pocketedCount(1), 1);
  });

  test('foul: striker pocketed returns own coins plus a penalty coin', () {
    final m = CrMatch.newBoard();
    fakeShot(m, <int>[1]); // seat 0 pockets white 1, keeps turn
    expect(m.pocketedCount(0), 1);
    final o = fakeShot(m, <int>[2, CrConfig.strikerId]);
    expect(o.foul, isTrue);
    expect(m.pocketedCount(0), 0);
    expect(o.returnedIds, containsAll(<int>[1, 2]));
    expect(m.turn, 1);
    expect(m.phase, CrPhase.aiming);
  });

  test('queen: covered in the same shot', () {
    final m = CrMatch.newBoard();
    final o = fakeShot(m, <int>[CrConfig.queenId, 3]);
    expect(o.queenCovered, isTrue);
    expect(m.queenCoveredBy, 0);
    expect(m.turn, 0);
  });

  test('queen: covered on the next shot, or returned when not covered', () {
    final m = CrMatch.newBoard();
    final o = fakeShot(m, <int>[CrConfig.queenId]);
    expect(o.queenPending, isTrue);
    expect(m.queenPendingFor, 0);
    expect(m.turn, 0);
    final o2 = fakeShot(m, <int>[4]);
    expect(o2.queenCovered, isTrue);
    expect(m.queenCoveredBy, 0);

    final n = CrMatch.newBoard();
    fakeShot(n, <int>[CrConfig.queenId]);
    final miss = fakeShot(n, <int>[]);
    expect(miss.queenReturned, isTrue);
    expect(n.queen.onBoard, isTrue);
    expect(n.queenCoveredBy, -1);
    expect(n.turn, 1);
  });

  test('last coin before the queen is returned; win after queen covered', () {
    final m = CrMatch.newBoard();
    // seat 0 pockets all 9 whites while the queen is uncovered: last one comes back
    fakeShot(m, <int>[1, 2, 3, 4, 5, 6, 7, 8, 9]);
    expect(m.remaining(0), 1);
    expect(m.winner, isNull);

    final w = CrMatch.newBoard();
    fakeShot(w, <int>[CrConfig.queenId, 1]);
    expect(w.queenCoveredBy, 0);
    final o = fakeShot(w, <int>[2, 3, 4, 5, 6, 7, 8, 9]);
    expect(o.matchOver, isTrue);
    expect(w.winner, 0);
    expect(w.phase, CrPhase.finished);
    expect(w.points[0], 9 + CrConfig.queenBonus);
  });

  test('striker placement validation', () {
    final m = CrMatch.newBoard();
    expect(m.validate(const CrShot(placeX: 100, dirX: 0, dirY: -1, power: 1)), isNotNull);
    expect(m.validate(const CrShot(placeX: 512, dirX: 0, dirY: 0, power: 1)), isNotNull);
    expect(m.validate(const CrShot(placeX: 512, dirX: 0, dirY: -1, power: 1.5)), isNotNull);
    expect(m.validate(const CrShot(placeX: 512, dirX: 0, dirY: -1, power: 0.5)), isNull);
  });

  test('bot returns a legal shot at every level', () {
    for (final lvl in CrBotLevel.values) {
      final m = CrMatch.newBoard(firstTurn: 1);
      final bot = CrBot(seat: 1, level: lvl, seed: 3);
      final s = bot.choose(m);
      expect(m.validate(s), isNull, reason: 'level $lvl');
      final noisy = bot.withExecutionNoise(s);
      expect(noisy.power, greaterThan(0));
      expect(m.validate(bot.fallback(m)), isNull);
      m.playShot(s);
    }
  });
}
