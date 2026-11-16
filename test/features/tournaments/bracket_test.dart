import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/features/tournaments/domain/bracket.dart';
import 'package:nexora/features/tournaments/domain/prize_split.dart';

int better(BMatch m, int a, int b) => a < b ? a : b;

void main() {
  group('seed order', () {
    test('standard order keeps 1 and 2 apart', () {
      expect(BracketGen.seedOrder(2), <int>[1, 2]);
      expect(BracketGen.seedOrder(4), <int>[1, 4, 2, 3]);
      expect(BracketGen.seedOrder(8), <int>[1, 8, 4, 5, 2, 7, 3, 6]);
      for (final int p in <int>[2, 4, 8, 16, 32, 64]) {
        final List<int> o = BracketGen.seedOrder(p);
        expect(o.toSet().length, p);
        // every first-round pair sums to p + 1
        for (int i = 0; i < p; i += 2) {
          expect(o[i] + o[i + 1], p + 1);
        }
        // 1 in the top half, 2 in the bottom half
        expect(o.indexOf(1) < p ~/ 2, isTrue);
        expect(o.indexOf(2) >= p ~/ 2, isTrue);
      }
    });
  });

  group('single elimination with byes', () {
    test('2..64 players: P-1 matches, byes to top seeds, favourite wins', () {
      for (int n = 2; n <= 64; n++) {
        final Bracket b = BracketGen.singleElim(n);
        final int p = 1 << BracketGen.roundsFor(n);
        expect(b.length, p - 1, reason: 'n=$n');
        final List<BMatch> byes = b.matches.where((BMatch m) => m.status == 'bye').toList();
        expect(byes.length, p - n, reason: 'byes n=$n');
        for (final BMatch m in byes) {
          expect(m.round, 1);
          expect(m.winner, lessThanOrEqualTo(p - n), reason: 'bye goes to a top seed (n=$n)');
        }
        b.simulate(better);
        expect(b.finished, isTrue);
        expect(b.champion, 1, reason: 'n=$n');
        if (n >= 2) {
          final BMatch fin = b.where('W').firstWhere((BMatch m) => m.round == BracketGen.roundsFor(n));
          expect(fin.loser, 2, reason: 'seed 2 reaches the final (n=$n)');
        }
      }
    });

    test('random upsets: every player except the champion loses exactly once', () {
      final math.Random rnd = math.Random(7);
      for (int n = 2; n <= 64; n++) {
        final Bracket b = BracketGen.singleElim(n, thirdPlace: true);
        b.simulate((BMatch m, int a, int c) => rnd.nextBool() ? a : c);
        final Map<int, int> losses = <int, int>{};
        for (final BMatch m in b.where('W')) {
          if (m.loser != null) losses[m.loser!] = (losses[m.loser!] ?? 0) + 1;
        }
        expect(losses.length, n - 1, reason: 'n=$n');
        expect(losses.values.every((int v) => v == 1), isTrue);
        expect(losses.containsKey(b.champion), isFalse);
        if (n >= 3) {
          final BMatch p3 = b.where('P3').single;
          expect(p3.isFinal, isTrue, reason: 'third-place match resolved (n=$n)');
        }
      }
    });

    test('best-of per round: early / semi / final', () {
      final Bracket b = BracketGen.singleElim(16, bo: const BestOf(early: 1, semi: 3, finalRound: 5));
      expect(b.where('W').where((BMatch m) => m.round == 4).single.bestOf, 5);
      expect(b.where('W').where((BMatch m) => m.round == 3).every((BMatch m) => m.bestOf == 3), isTrue);
      expect(b.where('W').where((BMatch m) => m.round <= 2).every((BMatch m) => m.bestOf == 1), isTrue);
    });

    test('two legs: every tie is an aggregate over 2 games (optional single-leg final)', () {
      final Bracket b = BracketGen.singleElim(8, bo: const BestOf(twoLegs: true, finalOneLeg: true));
      for (final BMatch m in b.where('W')) {
        if (m.round == 3) {
          expect(m.bestOf, 1);
          expect(m.aggregate, isFalse);
        } else {
          expect(m.bestOf, 2);
          expect(m.aggregate, isTrue);
        }
      }
    });

    test('elimination places', () {
      expect(BracketGen.elimPlace(3, 3), 2);
      expect(BracketGen.elimPlace(3, 2), 3);
      expect(BracketGen.elimPlace(3, 1), 5);
      expect(BracketGen.elimPlace(6, 1), 33);
    });
  });

  group('double elimination', () {
    test('2..64 players finish; eliminated players lose twice; reset only when the LB champion wins GF', () {
      final math.Random rnd = math.Random(11);
      for (int n = 2; n <= 64; n++) {
        for (int trial = 0; trial < 3; trial++) {
          final Bracket b = BracketGen.doubleElim(n);
          b.simulate((BMatch m, int a, int c) => trial == 0 ? better(m, a, c) : (rnd.nextBool() ? a : c));
          expect(b.finished, isTrue, reason: 'n=$n trial=$trial');
          final int? champ = b.champion;
          expect(champ, isNotNull);
          final Map<int, int> losses = <int, int>{};
          for (final BMatch m in b.matches) {
            if (m.status == 'done' && m.loser != null) losses[m.loser!] = (losses[m.loser!] ?? 0) + 1;
          }
          for (int s = 1; s <= n; s++) {
            if (s == champ) {
              expect(losses[s] ?? 0, lessThanOrEqualTo(1), reason: 'champion n=$n');
            } else {
              expect(losses[s], 2, reason: 'seed $s loses twice (n=$n trial=$trial)');
            }
          }
          final BMatch gf = b.where('GF').single;
          final BMatch gf2 = b.where('GF2').single;
          if (gf.winner == gf.p1) {
            expect(gf2.status, 'skipped');
          } else {
            expect(gf2.status, 'done');
          }
          if (trial == 0) expect(champ, 1);
        }
      }
    });

    test('losers bracket size', () {
      // 8 players: LB rounds 2,2,1,1
      expect(<int>[for (int m = 1; m <= 4; m++) BracketGen.lbCount(8, m)], <int>[2, 2, 1, 1]);
      // 16 players: 4,4,2,2,1,1
      expect(<int>[for (int m = 1; m <= 6; m++) BracketGen.lbCount(16, m)], <int>[4, 4, 2, 2, 1, 1]);
      expect(BracketGen.doubleElim(8).where('L').length, 6);
    });
  });

  group('round robin', () {
    test('single: every pair exactly once, nobody twice per round', () {
      for (int n = 2; n <= 20; n++) {
        final List<List<(int, int)>> rounds = BracketGen.roundRobin(n);
        expect(rounds.length, n.isEven ? n - 1 : n, reason: 'rounds n=$n');
        final Set<String> seen = <String>{};
        for (final List<(int, int)> r in rounds) {
          final Set<int> inRound = <int>{};
          for (final (int a, int b) in r) {
            expect(inRound.add(a) && inRound.add(b), isTrue, reason: 'n=$n');
            expect(seen.add(BracketGen.pairKey(a, b)), isTrue, reason: 'repeat n=$n');
          }
        }
        expect(seen.length, n * (n - 1) ~/ 2);
      }
    });

    test('double: each pair twice with home and away swapped', () {
      for (int n = 2; n <= 12; n++) {
        final Map<String, int> count = <String, int>{};
        final Set<String> directed = <String>{};
        for (final List<(int, int)> r in BracketGen.roundRobin(n, double: true)) {
          for (final (int a, int b) in r) {
            count[BracketGen.pairKey(a, b)] = (count[BracketGen.pairKey(a, b)] ?? 0) + 1;
            directed.add('$a>$b');
          }
        }
        expect(count.values.every((int v) => v == 2), isTrue, reason: 'n=$n');
        expect(directed.length, n * (n - 1), reason: 'home/away swapped n=$n');
      }
    });

    test('league table order: points, goal difference, goals, wins, seed', () {
      final List<LeagueRow> t = LeagueRow.table(<int>[1, 2, 3], <(int, int?, int, int)>[
        (1, 2, 1, 1),
        (2, 3, 3, 0),
        (3, 1, 1, 0),
      ]);
      expect(t.map((LeagueRow r) => r.player).toList(), <int>[2, 3, 1]);
      expect(t.first.points(), 4);
      final List<LeagueRow> d = LeagueRow.table(<int>[1, 2], <(int, int?, int, int)>[(1, 2, 2, 2)], win: 3, draw: 1);
      expect(d.map((LeagueRow r) => r.points()).toList(), <int>[1, 1]);
      expect(d.first.player, 1, reason: 'seed breaks a full tie');
      final List<LeagueRow> bye = LeagueRow.table(<int>[1, 2, 3], <(int, int?, int, int)>[(3, null, 0, 0)]);
      expect(bye.first.player, 3, reason: 'a bye counts as a win');
    });
  });

  group('groups → knockout', () {
    test('snake groups are balanced and seeds spread', () {
      for (int n = 4; n <= 64; n++) {
        for (int g = 1; g <= 8; g++) {
          final List<List<int>> gs = BracketGen.snakeGroups(n, g);
          final List<int> sizes = gs.map((List<int> x) => x.length).toList();
          expect(sizes.reduce(math.max) - sizes.reduce(math.min), lessThanOrEqualTo(1), reason: 'n=$n g=$g');
          expect(gs.expand((List<int> x) => x).toSet().length, n);
          for (int i = 0; i < gs.length; i++) {
            expect(gs[i].first, i + 1, reason: 'top seeds head the groups');
          }
        }
      }
      expect(BracketGen.snakeGroups(8, 2), <List<int>>[
        <int>[1, 4, 5, 8],
        <int>[2, 3, 6, 7],
      ]);
    });

    test('advancers never meet a group mate in the first knockout round', () {
      for (final int groups in <int>[2, 4, 8]) {
        final List<List<String>> ranked = <List<String>>[
          for (int g = 0; g < groups; g++) <String>['G${g}A', 'G${g}B', 'G${g}C'],
        ];
        // use indexes as seeds for the bracket
        final List<List<int>> asInts = <List<int>>[
          for (int g = 0; g < groups; g++) <int>[g * 10 + 1, g * 10 + 2],
        ];
        final List<int> adv = BracketGen.groupAdvancers(asInts, 2);
        expect(adv.length, groups * 2);
        expect(ranked.length, groups);
        final Bracket ko = BracketGen.singleElim(adv.length);
        for (final BMatch m in ko.where('W').where((BMatch m) => m.round == 1)) {
          final int a = adv[m.p1! - 1];
          final int b = adv[m.p2! - 1];
          expect(a ~/ 10 == b ~/ 10, isFalse, reason: 'groups=$groups $a vs $b');
        }
      }
    });

    test('match count preview', () {
      expect(BracketGen.matchCount(TFormat.groupsKo, 8, groups: 2, advance: 2), 12 + 3);
      expect(BracketGen.matchCount(TFormat.singleElim, 5, thirdPlace: true), 8);
      expect(BracketGen.matchCount(TFormat.roundRobin, 5, rrDouble: true), 20);
    });
  });

  group('swiss', () {
    test('round 1 pairs top half against bottom half; odd → lowest seed gets the bye', () {
      final r = BracketGen.swissRound(1, <int>[1, 2, 3, 4, 5, 6, 7], <String>{}, <int>{});
      expect(r.bye, 7);
      expect(r.pairs, <(int, int)>[(1, 4), (2, 5), (3, 6)]);
    });

    test('no rematches while avoidable and the bye rotates', () {
      const int n = 8;
      final Set<String> played = <String>{};
      final Set<int> hadBye = <int>{};
      final Map<int, int> pts = <int, int>{for (int i = 1; i <= n + 1; i++) i: 0};
      for (int round = 1; round <= 3; round++) {
        final List<int> order = pts.keys.toList()..sort((int a, int b) => pts[b]!.compareTo(pts[a]!) != 0 ? pts[b]!.compareTo(pts[a]!) : a.compareTo(b));
        final r = BracketGen.swissRound(round, order, played, hadBye);
        expect(r.bye, isNotNull, reason: '9 players → one bye');
        expect(hadBye.add(r.bye!), isTrue, reason: 'bye rotates (round $round)');
        pts[r.bye!] = pts[r.bye!]! + 3;
        for (final (int a, int b) in r.pairs) {
          expect(played.add(BracketGen.pairKey(a, b)), isTrue, reason: 'rematch $a-$b round $round');
          pts[a < b ? a : b] = pts[a < b ? a : b]! + 3;
        }
      }
      expect(BracketGen.swissRounds(9), 4);
      expect(BracketGen.swissRounds(2), 1);
      expect(BracketGen.swissRounds(8, 12), 7);
    });
  });

  group('series', () {
    test('Bo3: first to two wins; Bo1 knockout draw → golden-goal decider', () {
      final Series s = Series(bestOf: 3);
      expect(s.add(1, 0, 1), SeriesOutcome.more);
      expect(s.add(0, 2, 2), SeriesOutcome.more);
      expect(s.add(3, 1, 1), SeriesOutcome.p1);
      final Series d = Series(bestOf: 1);
      expect(d.add(1, 1, 0), SeriesOutcome.more);
      expect(d.nextIsGolden, isTrue);
      expect(d.add(0, 1, 2), SeriesOutcome.p2);
    });

    test('league Bo1 draw is a draw; Bo2 split is a draw in a league', () {
      expect(Series(bestOf: 1, knockout: false).add(2, 2, 0), SeriesOutcome.draw);
      final Series s = Series(bestOf: 2, knockout: false);
      expect(s.add(1, 0, 1), SeriesOutcome.more);
      expect(s.add(0, 1, 2), SeriesOutcome.draw);
    });

    test('two legs: aggregate goals, tie → golden goal', () {
      final Series s = Series(bestOf: 2, aggregate: true);
      expect(s.add(2, 1, 1), SeriesOutcome.more);
      expect(s.add(0, 2, 2), SeriesOutcome.p2);
      final Series t = Series(bestOf: 2, aggregate: true);
      t.add(1, 0, 1);
      expect(t.add(0, 1, 2), SeriesOutcome.more);
      expect(t.nextIsGolden, isTrue);
      expect(t.add(1, 0, 1), SeriesOutcome.p1);
    });
  });

  group('prize split', () {
    test('fee pool with house fee (same numbers the server paid in the live test)', () {
      const PrizeConfig c = PrizeConfig(poolPct: 100, feePct: 10, dist: <int>[70, 30]);
      expect(PrizeSplit.total(c, 500), 450);
      expect(PrizeSplit.houseFee(500, 100, 10), 50);
      expect(PrizeSplit.perPlace(450, <int>[70, 30]), <int>[315, 135]);
    });

    test('fixed + partial pool, shared places and remainder to the champion', () {
      const PrizeConfig c = PrizeConfig(fixed: 100, poolPct: 50, feePct: 0, dist: <int>[50, 30, 10, 10]);
      final int total = PrizeSplit.total(c, 333); // 100 + 166
      expect(total, 266);
      final Map<String, int> s = PrizeSplit.split(total, c.dist, <String, int>{'a': 1, 'b': 2, 'c': 3, 'd': 3},
          order: <String>['a', 'b', 'c', 'd']);
      // c and d share places 3+4 = 20% → 26 each; remainder to a
      expect(s['c'], 26);
      expect(s['d'], 26);
      expect(s['b'], 79);
      expect(s.values.reduce((int x, int y) => x + y), 266);
      expect(s['a'], 266 - 79 - 52);
    });

    test('never pays more than the total and ignores places outside the distribution', () {
      final math.Random rnd = math.Random(3);
      for (int i = 0; i < 200; i++) {
        final int total = rnd.nextInt(100000);
        final List<int> dist = <int>[50, 25, 15, 10];
        final int n = 2 + rnd.nextInt(30);
        final Map<String, int> places = <String, int>{for (int p = 1; p <= n; p++) 'u$p': p};
        final Map<String, int> s = PrizeSplit.split(total, dist, places);
        final int sum = s.values.fold<int>(0, (int a, int b) => a + b);
        expect(sum, lessThanOrEqualTo(total));
        expect(sum, total * 100 ~/ 100);
        expect(s.keys.every((String k) => places[k]! <= 4), isTrue);
      }
    });

    test('zero total pays nothing', () {
      expect(PrizeSplit.split(0, <int>[100], <String, int>{'a': 1}), isEmpty);
      expect(PrizeSplit.total(const PrizeConfig(), 1000), 0);
    });
  });
}
