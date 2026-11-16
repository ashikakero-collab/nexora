import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/storage/local_store.dart';
import 'package:nexora/worlds/social_station/data/social_repository.dart';
import 'package:nexora/worlds/social_station/models/social_models.dart';
import 'package:nexora/worlds/social_station/models/tournament_bracket.dart';
import 'package:nexora/worlds/social_station/state/social_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TournamentBracket', () {
    test('5 players: byes advance, results propagate to a champion', () {
      final b = TournamentBracket.create(<String>['A', 'B', 'C', 'D', 'E']);
      expect(b.roundCount, 3);
      expect(b.totalMatches, 4);
      expect(b.playable.length, 2);
      expect(b.playable, contains(const MatchRef(0, 3)));
      expect(b.playable, contains(const MatchRef(1, 0)));
      expect(b.setWinner(0, 3, 'Z'), isFalse);
      expect(b.setWinner(0, 3, 'D'), isTrue);
      expect(b.setWinner(1, 0, 'A'), isTrue);
      expect(b.setWinner(1, 1, 'C'), isTrue);
      expect(b.finished, isFalse);
      expect(b.setWinner(2, 0, 'C'), isTrue);
      expect(b.champion, 'C');
      expect(b.playedMatches, 4);
    });

    test('correcting a result clears the path it travelled', () {
      final b = TournamentBracket.create(<String>['A', 'B', 'C', 'D', 'E']);
      b.setWinner(0, 3, 'D');
      b.setWinner(1, 0, 'A');
      b.setWinner(1, 1, 'C');
      b.setWinner(2, 0, 'C');
      expect(b.setWinner(0, 3, 'E'), isTrue);
      expect(b.rounds[1][1].b, 'E');
      expect(b.rounds[1][1].winner, isNull);
      expect(b.finalMatch.b, isNull);
      expect(b.champion, isNull);
    });

    test('rejects bad player lists and survives JSON', () {
      expect(() => TournamentBracket.create(<String>['solo']), throwsArgumentError);
      expect(() => TournamentBracket.create(<String>['Ali', 'ali']), throwsArgumentError);
      final b = TournamentBracket.create(<String>['P1', 'P2', 'P3', 'P4'], shuffle: Random(3));
      b.setWinner(0, 0, b.rounds[0][0].a!);
      final c = TournamentBracket.fromJson(b.toJson());
      expect(c.players, b.players);
      expect(c.rounds[1][0].a, b.rounds[0][0].a);
      expect(c.playable.length, 1);
    });
  });

  group('CommunityPermissions', () {
    test('role changes follow the hierarchy', () {
      expect(CommunityPermissions.canChangeRole(CommunityRole.owner, CommunityRole.member, CommunityRole.admin), isTrue);
      expect(CommunityPermissions.canChangeRole(CommunityRole.owner, CommunityRole.admin, CommunityRole.moderator), isTrue);
      expect(CommunityPermissions.canChangeRole(CommunityRole.owner, CommunityRole.member, CommunityRole.owner), isFalse);
      expect(CommunityPermissions.canChangeRole(CommunityRole.admin, CommunityRole.member, CommunityRole.moderator), isTrue);
      expect(CommunityPermissions.canChangeRole(CommunityRole.admin, CommunityRole.member, CommunityRole.admin), isFalse);
      expect(CommunityPermissions.canChangeRole(CommunityRole.admin, CommunityRole.admin, CommunityRole.member), isFalse);
      expect(CommunityPermissions.canChangeRole(CommunityRole.moderator, CommunityRole.member, CommunityRole.member), isFalse);
      expect(CommunityPermissions.canChangeRole(CommunityRole.admin, CommunityRole.owner, CommunityRole.member), isFalse);
      expect(CommunityPermissions.canChangeRole(CommunityRole.owner, CommunityRole.owner, CommunityRole.admin, self: true), isFalse);
    });

    test('removal and abilities', () {
      expect(CommunityPermissions.canRemove(CommunityRole.moderator, CommunityRole.member), isTrue);
      expect(CommunityPermissions.canRemove(CommunityRole.moderator, CommunityRole.moderator), isFalse);
      expect(CommunityPermissions.canRemove(CommunityRole.admin, CommunityRole.owner), isFalse);
      expect(CommunityPermissions.canRemove(CommunityRole.member, CommunityRole.member), isFalse);
      expect(CommunityPermissions.canRemove(CommunityRole.owner, CommunityRole.admin), isTrue);
      expect(CommunityPermissions.canRemove(CommunityRole.owner, CommunityRole.owner, self: true), isFalse);
      expect(CommunityPermissions.canAnnounce(CommunityRole.moderator), isFalse);
      expect(CommunityPermissions.canManageEvents(CommunityRole.moderator), isTrue);
      expect(CommunityPermissions.canManageTournaments(CommunityRole.member), isFalse);
      expect(CommunityPermissions.canDeletePost(CommunityRole.member, own: true), isTrue);
      expect(CommunityPermissions.canDeletePost(CommunityRole.member, own: false), isFalse);
      expect(CommunityPermissions.canDeleteCommunity(CommunityRole.admin), isFalse);
    });
  });

  group('models', () {
    test('invite codes', () {
      final rng = Random(1);
      for (var i = 0; i < 20; i++) {
        expect(InviteCode.pattern.hasMatch(InviteCode.generate(rng)), isTrue);
      }
      expect(InviteCode.normalize('nx 7kq2mz'), 'NX-7KQ2MZ');
      expect(InviteCode.normalize('7KQ2MZ'), 'NX-7KQ2MZ');
      expect(InviteCode.normalize('NX-0OOOOO'), isNull);
      expect(InviteCode.normalize('abc'), isNull);
    });

    test('event countdown and ordering', () {
      final now = DateTime(2026, 1, 1, 12);
      final e = CommunityEvent(id: 'e', title: 'Night', startsAt: now.add(const Duration(hours: 3)), createdBy: 'me');
      expect(e.countdown(now), const Duration(hours: 3));
      expect(e.isPast(now), isFalse);
      expect(e.countdown(now.add(const Duration(hours: 5))), Duration.zero);
      expect(e.isPast(now.add(const Duration(hours: 3))), isTrue);
    });
  });

  group('LocalSocialRepository + SocialController', () {
    late LocalStore store;
    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      store = await LocalStore.init();
    });

    test('community persists with members, posts, events and tournaments', () async {
      final repo = LocalSocialRepository(store);
      final c = await repo.create(
        name: '  Night Wolves ',
        kind: CommunityKind.game,
        badgeId: 'badge_club_wolf',
        ownerId: 'me',
        ownerName: 'Sara',
        rules: <String>['Be kind', '  ', 'No cheating'],
        gameId: 'carrom',
      );
      expect(c.name, 'Night Wolves');
      expect(c.rules, <String>['Be kind', 'No cheating']);
      expect(c.roleOf('me'), CommunityRole.owner);
      expect(InviteCode.pattern.hasMatch(c.inviteCode), isTrue);
      c.posts.add(CommunityPost(id: 'p1', authorId: 'me', authorName: 'Sara', text: 'hi', at: DateTime(2026)));
      c.members.add(CommunityMember(id: 'lp1', name: 'Reza', role: CommunityRole.member, joinedAt: DateTime(2026), local: true));
      c.tournaments.add(CommunityTournament(
          id: 't1', name: 'Cup', gameId: 'carrom', createdAt: DateTime(2026), bracket: TournamentBracket.create(<String>['Sara', 'Reza'])));
      await repo.save(c);

      final fresh = LocalSocialRepository(LocalStore(store.prefs));
      final list = await fresh.communities();
      expect(list.length, 1);
      final r = list.first;
      expect(r.kind, CommunityKind.game);
      expect(r.gameId, 'carrom');
      expect(r.posts.single.text, 'hi');
      expect(r.member('lp1')!.local, isTrue);
      expect(r.tournaments.single.bracket.playable.length, 1);
      expect((await fresh.byInviteCode(c.inviteCode.toLowerCase()))?.id, c.id);
      await fresh.delete(c.id);
      expect(await LocalSocialRepository(LocalStore(store.prefs)).communities(), isEmpty);
    });

    test('controller enforces permissions end to end', () async {
      final ctrl = SocialController(LocalSocialRepository(store));
      final c = await ctrl.create(name: 'Cup Club', kind: CommunityKind.tournament, badgeId: 'x', ownerId: 'me', ownerName: 'Sara');
      expect(c.badgeId, kCommunityBadges.first);
      expect(await ctrl.addLocalMember(c.id, 'me', 'Reza'), isTrue);
      expect(await ctrl.addLocalMember(c.id, 'me', 'reza'), isFalse);
      expect(await ctrl.addLocalMember(c.id, 'me', 'Mina'), isTrue);
      final reza = ctrl.byId(c.id)!.members.firstWhere((CommunityMember m) => m.name == 'Reza');
      final mina = ctrl.byId(c.id)!.members.firstWhere((CommunityMember m) => m.name == 'Mina');

      // Members cannot manage.
      expect(await ctrl.addEvent(c.id, actorId: reza.id, title: 'x', startsAt: DateTime(2030)), isFalse);
      expect(await ctrl.removeMember(c.id, reza.id, mina.id), isFalse);

      // Owner promotes Reza to moderator; moderator can remove a member but not change roles.
      expect(await ctrl.changeRole(c.id, 'me', reza.id, CommunityRole.moderator), isTrue);
      expect(await ctrl.changeRole(c.id, reza.id, mina.id, CommunityRole.moderator), isFalse);
      expect(await ctrl.addEvent(c.id, actorId: reza.id, title: 'Finals night', startsAt: DateTime(2030)), isTrue);
      expect(await ctrl.removeMember(c.id, reza.id, 'me'), isFalse);
      expect(await ctrl.removeMember(c.id, reza.id, mina.id), isTrue);

      final ev = ctrl.byId(c.id)!.events.single;
      expect(ev.going, contains(reza.id));
      expect(await ctrl.toggleRsvp(c.id, ev.id, 'me'), isTrue);
      expect(ctrl.byId(c.id)!.events.single.going.length, 2);

      expect(await ctrl.announce(c.id, actorId: reza.id, actorName: 'Reza', text: 'hey'), isFalse);
      expect(await ctrl.announce(c.id, actorId: 'me', actorName: 'Sara', text: 'Welcome!'), isTrue);

      // Tournament: create, record results, champion persisted.
      expect(await ctrl.createTournament(c.id, actorId: 'me', name: 'Cup', gameId: 'uno', players: <String>['Sara']), 'count');
      expect(await ctrl.createTournament(c.id, actorId: 'me', name: 'Cup', gameId: 'uno', players: <String>['Sara', 'Reza']), isNull);
      final t = ctrl.byId(c.id)!.tournaments.single;
      final ref = t.bracket.playable.single;
      expect(await ctrl.recordResult(c.id, t.id, 'me', ref, 'Reza'), isTrue);
      final reread = await LocalSocialRepository(LocalStore(store.prefs)).community(c.id);
      expect(reread!.tournaments.single.bracket.champion, 'Reza');
      expect(reread.roleOf(reza.id), CommunityRole.moderator);
      expect(reread.member(mina.id), isNull);
      expect(reread.announcements.single.text, 'Welcome!');

      // Only the owner can delete the community.
      expect(await ctrl.deleteCommunity(c.id, reza.id), isFalse);
      expect(await ctrl.deleteCommunity(c.id, 'me'), isTrue);
      expect(ctrl.communities, isEmpty);
    });
  });
}
