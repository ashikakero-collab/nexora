import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/games/backgammon/core/backgammon_bot.dart';
import 'package:nexora/games/backgammon/core/backgammon_rules.dart';

BgState _empty() =>
    BgState(points: List<int>.filled(24, 0), bar: <int>[0, 0], off: <int>[0, 0]);

int _total(BgState s, int p) => s.checkersOnBoard(p) + s.off[p];

void main() {
  group('setup', () {
    test('initial position has 15 checkers each and pip 167', () {
      final BgState s = BgState.initial();
      expect(_total(s, 0), 15);
      expect(_total(s, 1), 15);
      expect(s.pip(0), 167);
      expect(s.pip(1), 167);
    });
  });

  group('moves', () {
    test('opening 3-1 can make the 5 point', () {
      final BgState s = BgState.initial();
      final List<BgPlay> plays = BgRules.enumeratePlays(s, 0, <int>[3, 1]);
      expect(plays.every((BgPlay p) => p.moves.length == 2), isTrue);
      final bool makesFive = plays.any((BgPlay p) => p.state.own(0, 4) == 2);
      expect(makesFive, isTrue);
    });

    test('doubles give four moves', () {
      final BgState s = BgState.initial();
      final List<BgPlay> plays = BgRules.enumeratePlays(s, 0, <int>[6, 6]);
      expect(plays, isNotEmpty);
      expect(plays.every((BgPlay p) => p.moves.length == 4), isTrue);
    });

    test('cannot land on a point held by 2+ opponent checkers', () {
      final BgState s = BgState.initial();
      // From the 24-point (idx 23) a 5 lands on idx 18 (5 dark checkers).
      final List<BgMove> m = BgRules.singleMoves(s, 0, 5);
      expect(m.any((BgMove x) => x.from == 23 && x.to == 18), isFalse);
    });

    test('hitting a blot sends it to the bar', () {
      final BgState s = _empty();
      s.points[10] = 1;
      s.points[7] = -1;
      s.points[20] = -14;
      s.points[0] = 14;
      final BgMove hit = BgRules.singleMoves(s, 0, 3)
          .firstWhere((BgMove m) => m.from == 10 && m.to == 7);
      expect(hit.hit, isTrue);
      final BgState n = BgRules.apply(s, 0, hit);
      expect(n.bar[1], 1);
      expect(n.own(0, 7), 1);
      expect(_total(n, 1), 15);
    });

    test('checker on the bar must enter first', () {
      final BgState s = BgState.initial();
      s.points[5] -= 1; // move one light checker to the bar
      s.bar[0] = 1;
      final List<BgMove> m = BgRules.singleMoves(s, 0, 4);
      expect(m.length, 1);
      expect(m.first.from, kBgBar);
      expect(m.first.to, 20);
    });

    test('entry blocked when the point is made', () {
      final BgState s = BgState.initial();
      s.points[5] -= 1;
      s.bar[0] = 1;
      // die 6 enters on idx 18 which holds 5 dark checkers.
      expect(BgRules.singleMoves(s, 0, 6), isEmpty);
    });

    test('must use both dice when possible', () {
      final BgState s = _empty();
      // Light: one checker on idx 12. Dark wall leaves exactly one path that
      // uses both dice: 12 -> 10 (die 2) -> 5 (die 5). Playing the 5 first
      // lands on idx 7 which is blocked.
      s.points[12] = 1;
      s.points[0] = 14;
      s.points[7] = -2;
      s.points[3] = -2;
      s.points[20] = -11;
      final List<BgPlay> plays = BgRules.enumeratePlays(s, 0, <int>[5, 2]);
      expect(plays.every((BgPlay p) => p.moves.length == 2), isTrue);
    });

    test('larger die rule when only one die can be played', () {
      final BgState s = _empty();
      s.points[12] = 1;
      s.points[0] = 14;
      // 12-6=6 open, 12-4=8 open, but 6-4=2 and 8-6=2 blocked -> only one die.
      s.points[2] = -2;
      s.points[20] = -13;
      final BgTurnTracker t = BgTurnTracker(s, 0, <int>[6, 4]);
      expect(t.total, 1);
      final List<BgMove> legal = t.legalMoves();
      expect(legal, isNotEmpty);
      expect(legal.every((BgMove m) => m.die == 6), isTrue);
    });
  });

  group('bearing off', () {
    test('exact and higher-die bear off', () {
      final BgState s = _empty();
      s.points[0] = 2; // 1-point
      s.points[2] = 3; // 3-point
      s.off[0] = 10;
      s.points[20] = -15;
      final List<BgMove> six = BgRules.singleMoves(s, 0, 6);
      // No checker above 3 -> a 6 bears off from the 3 point only.
      expect(six.any((BgMove m) => m.from == 2 && m.to == kBgOff), isTrue);
      expect(six.any((BgMove m) => m.from == 0 && m.to == kBgOff), isFalse);
      final List<BgMove> three = BgRules.singleMoves(s, 0, 3);
      expect(three.any((BgMove m) => m.from == 2 && m.to == kBgOff), isTrue);
    });

    test('cannot bear off while a checker is outside home', () {
      final BgState s = _empty();
      s.points[0] = 14;
      s.points[8] = 1;
      s.points[20] = -15;
      final List<BgMove> m = BgRules.singleMoves(s, 0, 1);
      expect(m.any((BgMove x) => x.to == kBgOff), isFalse);
    });

    test('gammon and backgammon scoring', () {
      final BgState s = _empty();
      s.off[0] = 15;
      s.points[20] = -15;
      expect(BgRules.resultMultiplier(s, 0), 2);
      s.off[1] = 1;
      s.points[20] = -14;
      expect(BgRules.resultMultiplier(s, 0), 1);
      final BgState b = _empty();
      b.off[0] = 15;
      b.points[3] = -1; // dark checker stuck in light home board
      b.points[20] = -14;
      expect(BgRules.resultMultiplier(b, 0), 3);
    });
  });

  group('turn tracker', () {
    test('play and undo keep checker counts', () {
      final BgTurnTracker t = BgTurnTracker(BgState.initial(), 0, <int>[6, 5]);
      final List<BgMove> legal = t.legalMoves();
      expect(legal, isNotEmpty);
      t.play(legal.first);
      expect(t.played.length, 1);
      t.undo();
      expect(t.played, isEmpty);
      expect(t.state.key, BgState.initial().key);
    });
  });

  group('bot', () {
    test('bot plays a full legal sequence for every level', () {
      for (int level = 0; level < 3; level++) {
        final BgBot bot = BgBot(level: level, seed: 42);
        final BgState s = BgState.initial();
        final List<BgMove> moves = bot.choose(s, 1, <int>[4, 2]);
        expect(moves.length, 2);
        final BgTurnTracker t = BgTurnTracker(s, 1, <int>[4, 2]);
        for (final BgMove m in moves) {
          expect(t.play(m), isNotNull);
        }
        expect(t.complete, isTrue);
      }
    });

    test('a full bot-vs-bot game finishes with a winner', () {
      BgState s = BgState.initial();
      final BgDice dice = BgDice(123);
      final List<BgBot> bots = <BgBot>[BgBot(level: 2, seed: 1), BgBot(level: 1, seed: 2)];
      int turn = 0;
      int guard = 0;
      while (s.winner == null && guard < 2000) {
        final List<int> roll = <int>[dice.roll(), dice.roll()];
        final List<BgMove> moves = bots[turn].choose(s, turn, roll);
        for (final BgMove m in moves) {
          s = BgRules.apply(s, turn, m);
        }
        expect(_total(s, 0), 15);
        expect(_total(s, 1), 15);
        turn = 1 - turn;
        guard++;
      }
      expect(s.winner, isNotNull);
    });
  });
}
