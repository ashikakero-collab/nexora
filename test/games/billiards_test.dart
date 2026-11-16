import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/games/billiards/core/pool_aim.dart';
import 'package:nexora/games/billiards/core/pool_bot.dart';
import 'package:nexora/games/billiards/core/pool_config.dart';
import 'package:nexora/games/billiards/core/pool_match.dart';
import 'package:nexora/games/billiards/core/pool_physics.dart';

/// Builds a non-break position: every object ball parked in a pocket except
/// the ones listed in [on] (id -> [x, y]; id 0 = cue ball).
PoolMatch _table(Map<int, List<double>> on, {List<PoolGroup>? groups, bool isBreak = false, int current = 0}) {
  final PoolMatch m = PoolMatch.newRack(breaker: current);
  for (int i = 1; i < 16; i++) {
    final PoolBall b = m.balls[i];
    b.pocketed = true;
    b.pocket = 0;
    b.x = PoolConfig.pockets[0][0];
    b.y = PoolConfig.pockets[0][1];
  }
  on.forEach((int id, List<double> p) {
    final PoolBall b = m.balls[id];
    b.pocketed = false;
    b.pocket = -1;
    b.x = p[0];
    b.y = p[1];
  });
  m.isBreak = isBreak;
  m.kitchenOnly = false;
  m.ballInHand = false;
  m.current = current;
  if (groups != null) m.groups = List<PoolGroup>.from(groups);
  return m;
}

PoolShot _at(PoolMatch m, double tx, double ty, double power) =>
    PoolShot(dirX: tx - m.cue.x, dirY: ty - m.cue.y, power: power);

const List<PoolGroup> _p0Solids = <PoolGroup>[PoolGroup.solids, PoolGroup.stripes];

void _expectSaneTable(PoolMatch m) {
  const double r = PoolConfig.ballR;
  for (int i = 0; i < 16; i++) {
    final PoolBall b = m.balls[i];
    expect(b.vx, 0);
    expect(b.vy, 0);
    if (b.pocketed) continue;
    expect(b.x, inInclusiveRange(-r, PoolConfig.tableW + r), reason: 'ball $i x');
    expect(b.y, inInclusiveRange(-r, PoolConfig.tableH + r), reason: 'ball $i y');
    for (int j = i + 1; j < 16; j++) {
      final PoolBall o = m.balls[j];
      if (o.pocketed) continue;
      final double dx = b.x - o.x, dy = b.y - o.y;
      expect(math.sqrt(dx * dx + dy * dy), greaterThan(2 * r - 1.5), reason: 'balls $i/$j overlap');
    }
  }
}

void main() {
  group('rack & config', () {
    test('rack has 16 balls on table, no overlaps, 8 in the middle', () {
      final PoolMatch m = PoolMatch.newRack();
      expect(m.balls.length, 16);
      expect(m.balls.every((PoolBall b) => !b.pocketed), isTrue);
      expect(m.isBreak, isTrue);
      expect(m.ballInHand, isTrue);
      expect(m.kitchenOnly, isTrue);
      _expectSaneTable(m);
      expect(m.balls[8].x, closeTo(PoolConfig.footSpotX, 1e-9));
      expect(m.canPlaceCue(PoolConfig.breakCueX, PoolConfig.breakCueY), isTrue);
      expect(m.canPlaceCue(PoolConfig.tableW / 2, PoolConfig.tableH / 2), isFalse, reason: 'kitchen only on break');
    });

    test('groups helpers', () {
      expect(poolGroupOf(3), PoolGroup.solids);
      expect(poolGroupOf(12), PoolGroup.stripes);
      expect(poolGroupOf(8), PoolGroup.none);
      expect(poolOtherGroup(PoolGroup.solids), PoolGroup.stripes);
    });
  });

  group('rules', () {
    test('open table: first potted ball assigns groups and shooter continues', () {
      final PoolMatch m = _table(<int, List<double>>{
        0: <double>[300, 300],
        3: <double>[150, 150],
        12: <double>[600, 1000],
        8: <double>[400, 700],
      });
      final PoolShotReport? r = m.playShot(_at(m, 150, 150, 0.3));
      expect(r, isNotNull);
      expect(r!.foul, PoolFoul.none);
      expect(r.pocketed, contains(3));
      expect(r.assigned, PoolGroup.solids);
      expect(m.groups[0], PoolGroup.solids);
      expect(m.groups[1], PoolGroup.stripes);
      expect(r.continues, isTrue);
      expect(m.current, 0);
      expect(m.ballInHand, isFalse);
      expect(m.isOver, isFalse);
      _expectSaneTable(m);
    });

    test('scratch is a foul: opponent gets ball in hand anywhere', () {
      final PoolMatch m = _table(<int, List<double>>{
        0: <double>[300, 300],
        3: <double>[600, 1100],
        12: <double>[600, 1000],
        8: <double>[400, 700],
      }, groups: _p0Solids);
      final PoolShotReport r = m.playShot(_at(m, 14, 14, 0.4))!;
      expect(r.foul, PoolFoul.scratch);
      expect(m.current, 1);
      expect(m.ballInHand, isTrue);
      expect(m.kitchenOnly, isFalse);
      expect(m.cue.pocketed, isFalse);
      expect(m.canPlaceCue(200, 500), isTrue, reason: 'ball in hand is no longer kitchen-only');
      expect(m.placeCue(200, 400), isTrue);
      expect(m.validate(const PoolShot(dirX: 0, dirY: 1, power: 0.3)), isNull);
      _expectSaneTable(m);
    });

    test('hitting the opponent group first is a foul with ball in hand', () {
      final PoolMatch m = _table(<int, List<double>>{
        0: <double>[400, 1000],
        12: <double>[400, 700],
        3: <double>[100, 200],
        8: <double>[650, 300],
      }, groups: _p0Solids);
      final PoolShotReport r = m.playShot(_at(m, 400, 700, 0.3))!;
      expect(r.foul, PoolFoul.wrongBallFirst);
      expect(m.current, 1);
      expect(m.ballInHand, isTrue);
      expect(m.isOver, isFalse);
    });

    test('no rail after contact (nothing potted) is a foul', () {
      final PoolMatch m = _table(<int, List<double>>{
        0: <double>[400, 800],
        3: <double>[400, 700],
        12: <double>[100, 200],
        8: <double>[650, 300],
      }, groups: _p0Solids);
      final PoolShotReport r = m.playShot(_at(m, 400, 700, 0.05))!;
      expect(m.world.firstContact, 3);
      expect(m.world.anyRail, isFalse);
      expect(r.foul, PoolFoul.noRail);
      expect(m.current, 1);
      expect(m.ballInHand, isTrue);
    });

    test('missing everything is a foul (no contact)', () {
      final PoolMatch m = _table(<int, List<double>>{
        0: <double>[400, 800],
        3: <double>[100, 200],
        12: <double>[700, 200],
        8: <double>[650, 300],
      }, groups: _p0Solids);
      final PoolShotReport r = m.playShot(const PoolShot(dirX: 0, dirY: 1, power: 0.2))!;
      expect(r.foul, PoolFoul.noContact);
      expect(m.current, 1);
      expect(m.ballInHand, isTrue);
    });

    test('legal miss (rail hit, nothing potted) passes the turn without ball in hand', () {
      final PoolMatch m = _table(<int, List<double>>{
        0: <double>[400, 1000],
        3: <double>[400, 700],
        12: <double>[100, 200],
        8: <double>[650, 300],
      }, groups: _p0Solids);
      final PoolShotReport r = m.playShot(_at(m, 400, 700, 0.35))!;
      expect(r.foul, PoolFoul.none);
      expect(r.continues, isFalse);
      expect(m.current, 1);
      expect(m.ballInHand, isFalse);
    });

    test('potting the 8 before clearing the group loses', () {
      final PoolMatch m = _table(<int, List<double>>{
        0: <double>[300, 300],
        8: <double>[150, 150],
        3: <double>[600, 1100],
        12: <double>[600, 1000],
      }, groups: _p0Solids);
      final PoolShotReport r = m.playShot(_at(m, 150, 150, 0.3))!;
      expect(r.pocketed, contains(8));
      expect(m.isOver, isTrue);
      expect(m.winner, 1);
      expect(m.endReason, PoolEndReason.eightEarly);
      expect(r.continues, isFalse);
    });

    test('potting the 8 on an open table loses', () {
      final PoolMatch m = _table(<int, List<double>>{
        0: <double>[300, 300],
        8: <double>[150, 150],
        3: <double>[600, 1100],
        12: <double>[600, 1000],
      });
      m.playShot(_at(m, 150, 150, 0.3));
      expect(m.isOver, isTrue);
      expect(m.winner, 1);
      expect(m.endReason, PoolEndReason.eightEarly);
    });

    test('potting the 8 after clearing the group wins', () {
      final PoolMatch m = _table(<int, List<double>>{
        0: <double>[300, 300],
        8: <double>[150, 150],
        12: <double>[600, 1000],
      }, groups: _p0Solids);
      expect(m.groupCleared(0), isTrue);
      expect(m.legalTargets(), <int>[8]);
      final PoolShotReport r = m.playShot(_at(m, 150, 150, 0.3))!;
      expect(r.foul, PoolFoul.none);
      expect(m.isOver, isTrue);
      expect(m.winner, 0);
      expect(m.endReason, PoolEndReason.eightPotted);
      expect(m.validate(const PoolShot(dirX: 0, dirY: -1, power: 0.5)), 'not_aiming');
    });

    test('potting the 8 together with a scratch loses even after clearing', () {
      final PoolMatch m = _table(<int, List<double>>{
        0: <double>[300, 300],
        8: <double>[150, 150],
        12: <double>[600, 1000],
      }, groups: _p0Solids);
      // heavy follow drives the cue ball after the 8 into the same pocket
      final PoolShotReport r = m.playShot(const PoolShot(dirX: -1, dirY: -1, power: 0.5, spin: 1))!;
      if (r.pocketed.contains(0)) {
        expect(m.winner, 1);
        expect(m.endReason, PoolEndReason.eightWithFoul);
      } else {
        expect(m.winner, 0);
      }
    });

    test('8 potted on the break is re-spotted and play continues', () {
      final PoolMatch m = _table(<int, List<double>>{
        0: <double>[300, 300],
        8: <double>[150, 150],
        3: <double>[600, 1100],
        12: <double>[600, 1000],
      }, isBreak: true);
      final PoolShotReport r = m.playShot(_at(m, 150, 150, 0.3))!;
      expect(r.wasBreak, isTrue);
      expect(r.eightRespotted, isTrue);
      expect(m.isOver, isFalse);
      expect(m.balls[8].pocketed, isFalse);
      expect(m.balls[8].x, closeTo(PoolConfig.footSpotX, 1e-9));
      expect(m.isBreak, isFalse);
      expect(m.groups[0], PoolGroup.none);
      _expectSaneTable(m);
    });

    test('clone is independent and keeps the last report', () {
      final PoolMatch m = PoolMatch.newRack();
      final PoolBall apex = m.balls[1];
      m.playShot(_at(m, apex.x, apex.y, 1));
      final PoolMatch c = m.clone();
      expect(c.lastReport, same(m.lastReport));
      expect(c.stateHash, m.stateHash);
      expect(c.current, m.current);
      c.balls[5].x += 10;
      expect(c.stateHash, isNot(m.stateHash));
    });
  });

  group('physics', () {
    test('break settles before the safety cap and is deterministic', () {
      int run() {
        final PoolMatch m = PoolMatch.newRack();
        final PoolBall apex = m.balls[1];
        final PoolShotReport? r = m.playShot(_at(m, apex.x + 3, apex.y, 1));
        expect(r, isNotNull);
        expect(m.world.done, isTrue);
        expect(m.world.steps, lessThan(PoolConfig.maxSteps));
        expect(m.world.settled, isTrue);
        _expectSaneTable(m);
        return m.stateHash;
      }

      final int a = run();
      final int b = run();
      expect(a, b);
    });

    test('same shot on a clone gives the same hash; a different shot does not', () {
      final PoolMatch base = PoolMatch.newRack();
      final PoolBall apex = base.balls[1];
      final PoolMatch a = base.clone();
      final PoolMatch b = base.clone();
      final PoolShot s = PoolShot(dirX: apex.x - base.cue.x, dirY: apex.y - base.cue.y, power: 0.9, spin: -0.4, side: 0.3);
      a.playShot(s);
      b.playShot(s);
      expect(a.stateHash, b.stateHash);
      final PoolMatch c = base.clone();
      c.playShot(PoolShot(dirX: apex.x - base.cue.x + 9, dirY: apex.y - base.cue.y, power: 0.9));
      expect(c.stateHash, isNot(a.stateHash));
    });

    test('a slow shot into empty space stops and never leaves the table', () {
      final PoolMatch m = _table(<int, List<double>>{0: <double>[400, 700], 3: <double>[100, 100], 8: <double>[700, 100]},
          groups: _p0Solids);
      m.playShot(const PoolShot(dirX: 0.3, dirY: 1, power: 1));
      _expectSaneTable(m);
    });

    test('aim prediction finds the first ball on the line', () {
      final PoolMatch m = _table(<int, List<double>>{
        0: <double>[400, 1000],
        3: <double>[400, 700],
        12: <double>[400, 400],
      });
      final PoolAimPrediction p = poolPredict(m.balls, 0, -1);
      expect(p.hitBall, 3);
      expect(p.ghostY, closeTo(700 + 2 * PoolConfig.ballR, 1e-6));
      expect(p.cutFactor, closeTo(1, 1e-6));
      final PoolAimPrediction w = poolPredict(m.balls, 1, 0);
      expect(w.hitBall, -1);
    });
  });

  group('bot', () {
    for (final PoolBotLevel level in PoolBotLevel.values) {
      test('${level.name}: break and follow-up shots are valid and quick', () {
        final PoolMatch m = PoolMatch.newRack();
        final math.Random rng = math.Random(42);
        for (int i = 0; i < 4 && !m.isOver; i++) {
          final Stopwatch sw = Stopwatch()..start();
          final PoolBotPlanner planner = PoolBotPlanner(match: m, level: level, rng: rng);
          final PoolShot shot = planner.plan();
          sw.stop();
          expect(sw.elapsedMilliseconds, lessThan(15000), reason: 'bot too slow (${sw.elapsedMilliseconds} ms)');
          expect(m.validate(shot), isNull, reason: 'invalid bot shot at shot $i');
          expect(shot.power, inInclusiveRange(0.0, 1.0));
          expect(m.playShot(shot), isNotNull);
          _expectSaneTable(m);
        }
      });
    }

    test('hard bot pots a simple straight-in ball', () {
      final PoolMatch m = _table(<int, List<double>>{
        0: <double>[300, 300],
        3: <double>[150, 150],
        12: <double>[600, 1000],
        8: <double>[400, 700],
      }, groups: _p0Solids);
      final PoolShot shot = PoolBotPlanner(match: m, level: PoolBotLevel.hard, rng: math.Random(3)).plan();
      final PoolShotReport r = m.playShot(shot)!;
      expect(r.foul, PoolFoul.none);
      expect(r.pocketed, contains(3));
    });

    test('bot with ball in hand places the cue legally', () {
      final PoolMatch m = _table(<int, List<double>>{
        0: <double>[400, 1000],
        3: <double>[200, 400],
        5: <double>[600, 900],
        12: <double>[400, 600],
        8: <double>[650, 300],
      }, groups: _p0Solids);
      m.ballInHand = true;
      final PoolShot shot = PoolBotPlanner(match: m, level: PoolBotLevel.normal, rng: math.Random(5)).plan();
      expect(m.validate(shot), isNull);
      if (shot.cueX != null) expect(m.canPlaceCue(shot.cueX!, shot.cueY!), isTrue);
      expect(m.playShot(shot), isNotNull);
    });

    test('bot vs bot match keeps a valid table and makes progress', () {
      final PoolMatch m = PoolMatch.newRack();
      final math.Random rng = math.Random(9);
      int shots = 0;
      while (!m.isOver && shots < 60) {
        final PoolShot shot = PoolBotPlanner(match: m, level: PoolBotLevel.easy, rng: rng).plan();
        expect(m.validate(shot), isNull, reason: 'shot $shots invalid');
        final PoolShotReport? r = m.playShot(shot);
        expect(r, isNotNull);
        shots++;
        if (!m.isOver) {
          expect(m.phase, PoolPhase.aiming);
          expect(m.cue.pocketed, isFalse);
          _expectSaneTable(m);
        }
      }
      final int potted = List<int>.generate(15, (int i) => i + 1).where((int id) => m.balls[id].pocketed).length;
      expect(m.isOver || potted >= 3, isTrue, reason: 'bots made no progress in $shots shots');
    });
  });
}
