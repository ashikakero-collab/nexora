import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/games/snakes_ladders/core/snl_rules.dart';

void main() {
  group('Snakes & Ladders rules', () {
    test('layout is valid', () {
      expect(SnlRules.isValidLayout(), isTrue);
    });

    test('ladders lift and snakes drop', () {
      kSnlLadders.forEach((int a, int b) {
        expect(SnlRules.resolve(a), b);
        expect(b, greaterThan(a));
      });
      kSnlSnakes.forEach((int h, int t) {
        expect(SnlRules.resolve(h), t);
        expect(t, lessThan(h));
      });
      expect(SnlRules.resolve(2), 2);
      expect(SnlRules.resolve(28), 84);
      expect(SnlRules.resolve(98), 78);
    });

    test('walk visits every square in order', () {
      expect(SnlRules.walk(0, 3), <int>[1, 2, 3]);
      expect(SnlRules.walk(40, 5), <int>[41, 42, 43, 44, 45]);
    });

    test('overshoot bounces back from 100', () {
      expect(SnlRules.walk(97, 5), <int>[98, 99, 100, 99, 98]);
      final SnlEngine e = SnlEngine(playerCount: 2, seed: 1);
      e.positions[0] = 97;
      final SnlMoveResult r = e.move(5);
      expect(r.landed, 98);
      expect(r.finalPos, 78); // 98 is a snake head
      expect(r.won, isFalse);
      expect(e.winner, isNull);
    });

    test('exact 100 wins', () {
      final SnlEngine e = SnlEngine(playerCount: 3, seed: 2);
      e.positions[0] = 97;
      final SnlMoveResult r = e.move(3);
      expect(r.finalPos, 100);
      expect(r.won, isTrue);
      expect(e.winner, 0);
      expect(r.extraTurn, isFalse);
    });

    test('ladder on 80 reaches 100 and wins', () {
      final SnlEngine e = SnlEngine(playerCount: 2, seed: 3);
      e.positions[0] = 78;
      final SnlMoveResult r = e.move(2);
      expect(r.landed, 80);
      expect(r.climbed, isTrue);
      expect(r.won, isTrue);
    });

    test('six gives an extra roll, other rolls pass the turn', () {
      final SnlEngine e = SnlEngine(playerCount: 4, seed: 4);
      e.positions[0] = 40;
      final SnlMoveResult six = e.move(6);
      expect(six.extraTurn, isTrue);
      expect(e.turn, 0);
      final SnlMoveResult two = e.move(2);
      expect(two.extraTurn, isFalse);
      expect(e.turn, 1);
      e.move(3);
      e.move(3);
      e.move(3);
      expect(e.turn, 0);
    });

    test('player count is clamped to 2..4', () {
      expect(SnlEngine(playerCount: 1).playerCount, 2);
      expect(SnlEngine(playerCount: 9).playerCount, 4);
    });

    test('seeded full games finish and are deterministic', () {
      for (int seed = 0; seed < 25; seed++) {
        for (int players = 2; players <= 4; players++) {
          final List<int> rollsA = <int>[];
          final SnlEngine a = SnlEngine(playerCount: players, seed: seed);
          int guard = 0;
          while (a.winner == null && guard < 20000) {
            final int roll = a.rollDie();
            expect(roll, inInclusiveRange(1, 6));
            rollsA.add(roll);
            final SnlMoveResult r = a.move(roll);
            expect(r.finalPos, inInclusiveRange(1, 100));
            guard++;
          }
          expect(a.winner, isNotNull);
          expect(a.positions[a.winner!], kSnlGoal);
          final SnlEngine b = SnlEngine(playerCount: players, seed: seed);
          for (final int roll in rollsA) {
            expect(b.rollDie(), roll);
            b.move(roll);
          }
          expect(b.winner, a.winner);
        }
      }
    });
  });
}
