import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/games/ludo/core/ludo_bot.dart';
import 'package:nexora/games/ludo/core/ludo_rules.dart';

void main() {
  group('setup', () {
    test('seats map to corners and everyone starts in base', () {
      final LudoState s2 = LudoState.initial(2);
      expect(s2.corners, <int>[3, 1]);
      final LudoState s4 = LudoState.initial(4);
      expect(s4.corners, <int>[3, 0, 1, 2]);
      for (final List<int> t in s4.tokens) {
        expect(t.every((int p) => p == kLudoBase), isTrue);
      }
    });

    test('safe squares are starts and stars', () {
      expect(LudoRules.isSafeGlobal(0), isTrue);
      expect(LudoRules.isSafeGlobal(8), isTrue);
      expect(LudoRules.isSafeGlobal(13), isTrue);
      expect(LudoRules.isSafeGlobal(21), isTrue);
      expect(LudoRules.isSafeGlobal(5), isFalse);
    });
  });

  group('moves', () {
    test('a 6 is needed to leave base', () {
      final LudoState s = LudoState.initial(2);
      expect(LudoRules.legalMoves(s, 0, 5), isEmpty);
      final List<LudoMove> six = LudoRules.legalMoves(s, 0, 6);
      expect(six.length, 4);
      expect(six.every((LudoMove m) => m.from == kLudoBase && m.to == 0), isTrue);
    });

    test('home needs an exact roll', () {
      final LudoState s = LudoState.initial(2);
      s.tokens[0][0] = 54;
      final List<LudoMove> four = LudoRules.legalMoves(s, 0, 4);
      expect(four.any((LudoMove m) => m.token == 0), isFalse);
      final List<LudoMove> two = LudoRules.legalMoves(s, 0, 2);
      expect(two.any((LudoMove m) => m.token == 0 && m.finishes), isTrue);
    });

    test('capture sends the opponent token home to base', () {
      final LudoState s = LudoState.initial(2);
      // Seat 0 (corner 3) progress 3 -> global (39 + 3) % 52 = 42.
      s.tokens[0][0] = 3;
      // Seat 1 (corner 1) global 44 -> progress (44 - 13) = 31.
      s.tokens[1][2] = 31;
      expect(s.globalOf(1, 31), 44);
      final List<LudoMove> moves = LudoRules.legalMoves(s, 0, 2);
      final LudoMove m = moves.firstWhere((LudoMove x) => x.token == 0);
      expect(m.captures.length, 1);
      final LudoState n = LudoRules.apply(s, m);
      expect(n.tokens[1][2], kLudoBase);
      expect(LudoRules.grantsExtraTurn(m, 2), isTrue);
    });

    test('no capture on a safe star square', () {
      final LudoState s = LudoState.initial(2);
      s.tokens[0][0] = 3; // global 42
      // global 47 is a star (47 % 13 == 8). Seat 1 progress 34 -> global 47.
      s.tokens[1][0] = 34;
      expect(LudoRules.isSafeGlobal(47), isTrue);
      final LudoMove m =
          LudoRules.legalMoves(s, 0, 5).firstWhere((LudoMove x) => x.token == 0);
      expect(m.captures, isEmpty);
    });

    test('tokens in the home column cannot be captured', () {
      final LudoState s = LudoState.initial(2);
      s.tokens[0][0] = 52;
      expect(LudoRules.capturesAt(s, 1, 52), isEmpty);
      expect(LudoRules.isThreatened(s, 0, 52), isFalse);
    });
  });

  group('engine', () {
    test('rolling a 6 gives another turn', () {
      final LudoEngine e = LudoEngine(playerCount: 2, seed: 1);
      final LudoRollResult r = e.applyRoll(6);
      expect(r.moves, isNotEmpty);
      final LudoPlayResult p = e.play(r.moves.first);
      expect(p.extraTurn, isTrue);
      expect(e.state.turn, 0);
      expect(e.state.sixStreak, 1);
    });

    test('three sixes in a row forfeit the turn', () {
      final LudoEngine e = LudoEngine(playerCount: 2, seed: 1);
      e.play(e.applyRoll(6).moves.first);
      e.play(e.applyRoll(6).moves.first);
      final LudoRollResult third = e.applyRoll(6);
      expect(third.forfeited, isTrue);
      expect(e.state.turn, 1);
    });

    test('no move passes the turn', () {
      final LudoEngine e = LudoEngine(playerCount: 3, seed: 1);
      final LudoRollResult r = e.applyRoll(3);
      expect(r.passes, isTrue);
      expect(e.state.turn, 1);
    });

    test('winning when all four tokens are home', () {
      final LudoEngine e = LudoEngine(playerCount: 2, seed: 1);
      e.state.tokens[0] = <int>[kLudoHome, kLudoHome, kLudoHome, 53];
      final LudoRollResult r = e.applyRoll(3);
      final LudoPlayResult p = e.play(r.moves.first);
      expect(p.won, isTrue);
      expect(e.state.winner, 0);
    });
  });

  group('bot', () {
    test('bot prefers a capture', () {
      final LudoState s = LudoState.initial(2);
      s.tokens[0][0] = 3;
      s.tokens[0][1] = 20;
      s.tokens[1][2] = 31; // capturable by token 0 with a 2
      final List<LudoMove> moves = LudoRules.legalMoves(s, 0, 2);
      final LudoBot bot = LudoBot(level: 2, seed: 3);
      final LudoMove m = bot.choose(s, moves);
      expect(m.captures, isNotEmpty);
    });

    test('bot-only games finish for 2, 3 and 4 seats', () {
      for (int n = 2; n <= 4; n++) {
        final LudoEngine e = LudoEngine(playerCount: n, seed: 100 + n);
        final List<LudoBot> bots =
            List<LudoBot>.generate(n, (int i) => LudoBot(level: i % 3, seed: i));
        int guard = 0;
        while (e.state.winner == null && guard < 20000) {
          final int seat = e.state.turn;
          final LudoRollResult r = e.roll();
          if (r.moves.isNotEmpty) {
            e.play(bots[seat].choose(e.state, r.moves));
          }
          guard++;
        }
        expect(e.state.winner, isNotNull);
      }
    });
  });
}
