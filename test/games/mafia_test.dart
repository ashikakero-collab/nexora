import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/games/mafia/core/mafia_engine.dart';
import 'package:nexora/games/mafia/core/mafia_match.dart';
import 'package:nexora/games/mafia/core/mafia_models.dart';

/// 0 godfather, 1 mafia, 2 doctor, 3 detective, 4 sniper, 5..6 citizens.
MafiaEngine _seven({MafiaConfig config = const MafiaConfig()}) {
  return MafiaEngine.withRoles(
    names: <String>['A', 'B', 'C', 'D', 'E', 'F', 'G'],
    roles: <MafiaRole>[
      MafiaRole.godfather,
      MafiaRole.mafia,
      MafiaRole.doctor,
      MafiaRole.detective,
      MafiaRole.sniper,
      MafiaRole.citizen,
      MafiaRole.citizen,
    ],
    config: config,
  );
}

void main() {
  group('role distribution', () {
    for (int n = 6; n <= 12; n++) {
      for (final bool sniper in <bool>[true, false]) {
        test('$n players, sniper=$sniper', () {
          final List<MafiaRole> roles = MafiaEngine.distributeRoles(n, useSniper: sniper);
          expect(roles.length, n);
          final int mafia = roles.where((MafiaRole r) => r.isMafia).length;
          expect(mafia, n >= 9 ? 3 : 2);
          expect(roles.where((MafiaRole r) => r == MafiaRole.godfather).length, 1);
          expect(roles.where((MafiaRole r) => r == MafiaRole.doctor).length, 1);
          expect(roles.where((MafiaRole r) => r == MafiaRole.detective).length, 1);
          expect(roles.where((MafiaRole r) => r == MafiaRole.sniper).length, sniper && n >= 7 ? 1 : 0);
          expect(mafia * 2 < n, isTrue, reason: 'Mafia must start as a minority');
        });
      }
    }

    test('create shuffles but keeps the multiset', () {
      final MafiaEngine e = MafiaEngine.create(
        names: List<String>.generate(10, (int i) => 'P$i'),
        config: const MafiaConfig(),
        rng: Random(42),
      );
      final List<MafiaRole> got = e.players.map((MafiaPlayer p) => p.role).toList()
        ..sort((MafiaRole a, MafiaRole b) => a.index.compareTo(b.index));
      final List<MafiaRole> want = MafiaEngine.distributeRoles(10, useSniper: true)
        ..sort((MafiaRole a, MafiaRole b) => a.index.compareTo(b.index));
      expect(got, want);
    });
  });

  group('night', () {
    test('doctor save cancels the mafia kill', () {
      final MafiaEngine e = _seven();
      final NightResult r = e.resolveNight(const NightActions(mafiaTarget: 5, doctorSave: 5));
      expect(r.deaths, isEmpty);
      expect(r.savedSomeone, isTrue);
      expect(r.savedId, 5);
      expect(e.player(5).alive, isTrue);
    });

    test('unsaved target dies', () {
      final MafiaEngine e = _seven();
      final NightResult r = e.resolveNight(const NightActions(mafiaTarget: 5, doctorSave: 6));
      expect(r.deaths, <int>[5]);
      expect(e.player(5).alive, isFalse);
      expect(e.player(5).cause, DeathCause.nightKill);
    });

    test('doctor cannot save the same player twice in a row, self only once', () {
      final MafiaEngine e = _seven();
      e.resolveNight(const NightActions(doctorSave: 2));
      expect(e.doctorSelfSaveUsed, isTrue);
      e.startNight();
      expect(e.legalDoctorTargets().contains(2), isFalse);
      e.resolveNight(const NightActions(doctorSave: 5));
      e.startNight();
      expect(e.legalDoctorTargets().contains(5), isFalse);
      expect(e.legalDoctorTargets().contains(2), isFalse, reason: 'self save already used');
    });

    test('godfather reads innocent, mafia reads mafia', () {
      final MafiaEngine e = _seven();
      final NightResult r1 = e.resolveNight(const NightActions(detectiveCheck: 0));
      expect(r1.checkedIsMafia, isFalse);
      e.startNight();
      final NightResult r2 = e.resolveNight(const NightActions(detectiveCheck: 1));
      expect(r2.checkedIsMafia, isTrue);
      e.startNight();
      final NightResult r3 = e.resolveNight(const NightActions(detectiveCheck: 5));
      expect(r3.checkedIsMafia, isFalse);
      // The result is private to the detective.
      final List<GameLogEntry> checks = e.log.where((GameLogEntry g) => g.kind == LogKind.check).toList();
      expect(checks.length, 3);
      for (final GameLogEntry c in checks) {
        expect(c.visibleFor(3), isTrue);
        expect(c.visibleFor(5), isFalse);
        expect(c.visibleFor(0), isFalse);
      }
    });

    test('sniper hits mafia, backfires on town', () {
      final MafiaEngine e = _seven();
      final NightResult r = e.resolveNight(const NightActions(sniperTarget: 1));
      expect(r.deaths, <int>[1]);
      expect(e.sniperBullets, 0);
      expect(e.legalSniperTargets(), isEmpty);

      final MafiaEngine e2 = _seven();
      final NightResult r2 = e2.resolveNight(const NightActions(sniperTarget: 6));
      expect(r2.deaths, <int>[4]);
      expect(r2.causes[4], DeathCause.sniperBackfire);
      expect(e2.player(6).alive, isTrue);
    });

    test('illegal actions are ignored', () {
      final MafiaEngine e = _seven();
      const NightActions bad = NightActions(mafiaTarget: 1, detectiveCheck: 3);
      expect(e.isLegalNight(bad), isFalse);
      final NightResult r = e.resolveNight(bad);
      expect(r.deaths, isEmpty);
      expect(r.checkedId, isNull);
    });
  });

  group('confidentiality', () {
    test('roles are visible only to the holder, mafia partners, or after reveal', () {
      final MafiaEngine e = _seven();
      expect(e.visibleRole(5, 5), MafiaRole.citizen);
      expect(e.visibleRole(5, 0), isNull);
      expect(e.visibleRole(3, 2), isNull);
      expect(e.visibleRole(0, 1), MafiaRole.mafia);
      expect(e.visibleRole(1, 0), MafiaRole.godfather);
      expect(e.visibleRole(0, 5), isNull);
      e.resolveNight(const NightActions(mafiaTarget: 6));
      expect(e.visibleRole(5, 6), MafiaRole.citizen);
    });

    test('roles stay hidden on death when reveal is off', () {
      final MafiaEngine e = _seven(config: const MafiaConfig(revealRoleOnDeath: false));
      e.resolveNight(const NightActions(mafiaTarget: 6));
      expect(e.player(6).alive, isFalse);
      expect(e.visibleRole(5, 6), isNull);
    });
  });

  group('votes', () {
    test('nomination tie sends both to trial', () {
      final MafiaEngine e = _seven();
      e.resolveNight(const NightActions());
      final NominationResult n = e.tallyNomination(<int, int?>{0: 5, 1: 5, 2: 1, 3: 1, 4: null, 5: 1, 6: 5});
      expect(n.defendants, <int>[1, 5]);
    });

    test('final vote tie eliminates nobody', () {
      final MafiaEngine e = _seven();
      e.resolveNight(const NightActions());
      final FinalVoteResult r =
          e.resolveFinalVote(<int, int?>{0: 5, 1: 5, 2: 1, 3: 1, 4: null, 5: 1, 6: 5}, <int>[1, 5]);
      expect(r.eliminated, isNull);
      expect(e.aliveCount, 7);
    });

    test('final counts tie eliminates nobody, unique majority does', () {
      final MafiaEngine e = _seven();
      e.resolveNight(const NightActions());
      expect(e.resolveFinalCounts(<int, int>{1: 3, 5: 3}, <int>[1, 5]).eliminated, isNull);
      final FinalVoteResult r = e.resolveFinalCounts(<int, int>{1: 5, 5: 1}, <int>[1, 5]);
      expect(r.eliminated, 1);
      expect(e.player(1).alive, isFalse);
      expect(e.player(1).cause, DeathCause.vote);
    });

    test('top count must beat abstentions', () {
      final MafiaEngine e = _seven();
      e.resolveNight(const NightActions());
      final FinalVoteResult r = e.resolveFinalCounts(<int, int>{5: 3}, <int>[5]);
      expect(r.spares, 4);
      expect(r.eliminated, isNull);
    });

    test('self votes count as skips', () {
      final MafiaEngine e = _seven();
      e.resolveNight(const NightActions());
      final NominationResult n = e.tallyNomination(<int, int?>{5: 5, 6: 5});
      expect(n.skips, 1);
      expect(n.defendants, isEmpty);
    });
  });

  group('win conditions', () {
    test('town wins when every mafia is gone', () {
      final MafiaEngine e = _seven();
      e.resolveNight(const NightActions(sniperTarget: 1));
      expect(e.isOver, isFalse);
      e.resolveFinalCounts(<int, int>{0: 6}, <int>[0]);
      expect(e.winner, MafiaTeam.town);
    });

    test('mafia wins at parity', () {
      final MafiaEngine e = _seven();
      // 2 mafia vs 5 town -> remove 3 town.
      e.resolveNight(const NightActions(mafiaTarget: 5));
      expect(e.isOver, isFalse);
      e.resolveFinalCounts(<int, int>{6: 6}, <int>[6]);
      expect(e.isOver, isFalse);
      e.startNight();
      e.resolveNight(const NightActions(mafiaTarget: 4));
      expect(e.mafiaAlive, 2);
      expect(e.townAlive, 2);
      expect(e.winner, MafiaTeam.mafia);
      expect(e.checkWinnerNow(), MafiaTeam.mafia);
    });

    test('everyone sees every role once the game is over', () {
      final MafiaEngine e = _seven(config: const MafiaConfig(revealRoleOnDeath: false));
      e.resolveNight(const NightActions(sniperTarget: 1));
      e.resolveFinalCounts(<int, int>{0: 6}, <int>[0]);
      expect(e.isOver, isTrue);
      expect(e.visibleRole(5, 2), MafiaRole.doctor);
    });
  });

  group('seeded all-bot games', () {
    test('complete with zero illegal actions', () {
      int games = 0;
      int townWins = 0;
      for (int n = 6; n <= 10; n++) {
        for (final MafiaSkill skill in MafiaSkill.values) {
          for (int seed = 1; seed <= 8; seed++) {
            final MafiaMatch m = MafiaMatch.create(
              humanName: 'Bot',
              isFa: seed.isEven,
              totalPlayers: n,
              skill: skill,
              seed: seed * 97 + n,
              humanIsBot: true,
            );
            m.autoPlayToEnd(maxCycles: 80);
            games++;
            expect(m.isOver, isTrue, reason: 'n=$n skill=$skill seed=$seed');
            expect(m.illegalActions, isEmpty, reason: 'n=$n skill=$skill seed=$seed: ${m.illegalActions}');
            expect(m.engine.checkWinnerNow(), m.engine.winner, reason: 'n=$n skill=$skill seed=$seed ended naturally');
            if (m.engine.winner == MafiaTeam.town) townWins++;
          }
        }
      }
      expect(games, 5 * 3 * 8);
      // Both sides must be able to win.
      expect(townWins, greaterThan(0));
      expect(townWins, lessThan(games));
    });

    test('same seed gives the same game', () {
      MafiaMatch run() {
        final MafiaMatch m = MafiaMatch.create(
          humanName: 'Bot',
          isFa: false,
          totalPlayers: 8,
          skill: MafiaSkill.hard,
          seed: 1234,
          humanIsBot: true,
        );
        m.autoPlayToEnd();
        return m;
      }

      final MafiaMatch a = run();
      final MafiaMatch b = run();
      expect(a.engine.winner, b.engine.winner);
      expect(a.engine.day, b.engine.day);
      expect(a.engine.log.map((GameLogEntry g) => g.en).toList(), b.engine.log.map((GameLogEntry g) => g.en).toList());
    });
  });
}
