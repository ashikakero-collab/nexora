import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/online/online_service.dart';
import '../../../core/profile/profile_service.dart';
import '../../../core/storage/local_store.dart';
import '../../orbit_network/data/orbit_shared_inbox.dart';
import '../data/social_repository.dart';
import '../data/supabase_social_repository.dart';
import '../models/social_models.dart';
import '../models/tournament_bracket.dart';

/// Online (signed in): real communities on Supabase; otherwise device-only.
final socialRepositoryProvider = Provider<SocialRepository>((ref) {
  final OnlineService o = ref.watch(onlineProvider);
  final LocalSocialRepository local = LocalSocialRepository(LocalStore.instance);
  final client = o.client;
  if (o.isOnline && client != null) {
    return SupabaseSocialRepository(client, local, explorerId: ref.read(profileProvider).explorerId);
  }
  return local;
});

final socialControllerProvider =
    ChangeNotifierProvider<SocialController>((ref) => SocialController(ref.watch(socialRepositoryProvider)));

/// In-memory view state of SOCIAL STATION, kept in sync with the repository.
/// Every mutation is permission-checked with [CommunityPermissions].
class SocialController extends ChangeNotifier {
  SocialController(this.repo, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now {
    refresh();
  }

  final SocialRepository repo;
  SupabaseSocialRepository? get online => repo is SupabaseSocialRepository ? repo as SupabaseSocialRepository : null;
  bool get isOnline => online != null;
  final DateTime Function() _clock;
  bool loading = true;
  bool _disposed = false;
  List<Community> communities = <Community>[];

  Community? byId(String id) {
    for (final c in communities) {
      if (c.id == id) return c;
    }
    return null;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> refresh() async {
    communities = await repo.communities();
    loading = false;
    _notify();
  }

  Future<bool> _mutate(String communityId, bool Function(Community c) change) async {
    final SupabaseSocialRepository? on = online;
    if (on != null) {
      final bool ok = await on.mutate(communityId, change);
      await refresh();
      return ok;
    }
    final Community? c = await repo.community(communityId);
    if (c == null) return false;
    final bool ok = change(c);
    if (ok) {
      await repo.save(c);
      await refresh();
    }
    return ok;
  }

  // ---- communities ----

  Future<Community> create({
    required String name,
    required CommunityKind kind,
    required String badgeId,
    required String ownerId,
    required String ownerName,
    String description = '',
    List<String> rules = const <String>[],
    String? gameId,
  }) async {
    final c = await repo.create(
      name: name,
      kind: kind,
      badgeId: badgeId,
      ownerId: ownerId,
      ownerName: ownerName,
      description: description,
      rules: rules,
      gameId: gameId,
    );
    await refresh();
    return c;
  }

  Future<bool> editInfo(
    String communityId,
    String actorId, {
    required String name,
    required CommunityKind kind,
    required String badgeId,
    required String description,
    required List<String> rules,
    String? gameId,
  }) =>
      _mutate(communityId, (Community c) {
        final role = c.roleOf(actorId);
        if (role == null || !CommunityPermissions.canEditInfo(role)) return false;
        if (name.trim().isNotEmpty) c.name = name.trim();
        c.kind = kind;
        if (kCommunityBadges.contains(badgeId)) c.badgeId = badgeId;
        c.description = description.trim();
        c.gameId = gameId;
        c.rules
          ..clear()
          ..addAll(rules.map((String r) => r.trim()).where((String r) => r.isNotEmpty));
        return true;
      });

  Future<bool> deleteCommunity(String communityId, String actorId) async {
    final Community? c = await repo.community(communityId);
    final role = c?.roleOf(actorId);
    if (c == null || role == null || !CommunityPermissions.canDeleteCommunity(role)) return false;
    await repo.delete(communityId);
    await refresh();
    return true;
  }

  Future<Community?> findByCode(String code) => repo.byInviteCode(code);

  /// Drops a community invite card into ORBIT NETWORK's shared inbox.
  Future<void> shareInviteToOrbit(Community c, String text) => OrbitSharedInbox(LocalStore.instance).add(SharedItem(
        type: SharedItem.communityInvite,
        id: c.id,
        text: text,
        at: _clock(),
        extra: <String, dynamic>{
          'code': c.inviteCode,
          'name': c.name,
          'badge': c.badgeId,
          if (c.gameId != null) 'gameId': c.gameId
        },
      ));

  // ---- feed ----

  Future<bool> addPost(String communityId, {required String authorId, required String authorName, required String text}) {
    final t = text.trim();
    if (t.isEmpty) return Future<bool>.value(false);
    return _mutate(communityId, (Community c) {
      if (c.roleOf(authorId) == null) return false;
      c.posts.add(CommunityPost(id: repo.newId('cp'), authorId: authorId, authorName: authorName, text: t, at: _clock()));
      return true;
    });
  }

  Future<bool> toggleLike(String communityId, String postId, String userId) => _mutate(communityId, (Community c) {
        for (final p in c.posts) {
          if (p.id == postId) {
            if (!p.likedBy.remove(userId)) p.likedBy.add(userId);
            return true;
          }
        }
        return false;
      });

  Future<bool> togglePin(String communityId, String postId, String actorId) => _mutate(communityId, (Community c) {
        final role = c.roleOf(actorId);
        if (role == null || !CommunityPermissions.canPinPosts(role)) return false;
        for (final p in c.posts) {
          if (p.id == postId) {
            p.pinned = !p.pinned;
            return true;
          }
        }
        return false;
      });

  Future<bool> deletePost(String communityId, String postId, String actorId) => _mutate(communityId, (Community c) {
        final role = c.roleOf(actorId);
        if (role == null) return false;
        final int i = c.posts.indexWhere((CommunityPost p) => p.id == postId);
        if (i < 0) return false;
        if (!CommunityPermissions.canDeletePost(role, own: c.posts[i].authorId == actorId)) return false;
        c.posts.removeAt(i);
        return true;
      });

  Future<bool> announce(String communityId, {required String actorId, required String actorName, required String text}) {
    final t = text.trim();
    if (t.isEmpty) return Future<bool>.value(false);
    return _mutate(communityId, (Community c) {
      final role = c.roleOf(actorId);
      if (role == null || !CommunityPermissions.canAnnounce(role)) return false;
      c.announcements.insert(0, CommunityAnnouncement(id: repo.newId('ann'), text: t, authorName: actorName, at: _clock()));
      return true;
    });
  }

  Future<bool> deleteAnnouncement(String communityId, String id, String actorId) => _mutate(communityId, (Community c) {
        final role = c.roleOf(actorId);
        if (role == null || !CommunityPermissions.canAnnounce(role)) return false;
        final int before = c.announcements.length;
        c.announcements.removeWhere((CommunityAnnouncement a) => a.id == id);
        return c.announcements.length != before;
      });

  // ---- events ----

  Future<bool> addEvent(
    String communityId, {
    required String actorId,
    required String title,
    required DateTime startsAt,
    String description = '',
    String? gameId,
  }) {
    final t = title.trim();
    if (t.isEmpty) return Future<bool>.value(false);
    return _mutate(communityId, (Community c) {
      final role = c.roleOf(actorId);
      if (role == null || !CommunityPermissions.canManageEvents(role)) return false;
      c.events.add(CommunityEvent(
        id: repo.newId('ev'),
        title: t,
        description: description.trim(),
        startsAt: startsAt,
        createdBy: actorId,
        gameId: gameId,
        going: <String>{actorId},
      ));
      return true;
    });
  }

  Future<bool> toggleRsvp(String communityId, String eventId, String memberId) => _mutate(communityId, (Community c) {
        if (c.member(memberId) == null) return false;
        for (final e in c.events) {
          if (e.id == eventId) {
            if (!e.going.remove(memberId)) e.going.add(memberId);
            return true;
          }
        }
        return false;
      });

  Future<bool> deleteEvent(String communityId, String eventId, String actorId) => _mutate(communityId, (Community c) {
        final role = c.roleOf(actorId);
        if (role == null || !CommunityPermissions.canManageEvents(role)) return false;
        final int before = c.events.length;
        c.events.removeWhere((CommunityEvent e) => e.id == eventId);
        return c.events.length != before;
      });

  // ---- members ----

  /// Adds a named local (same-device) player. Not a real online account.
  Future<bool> addLocalMember(String communityId, String actorId, String name) {
    final n = name.trim();
    if (n.isEmpty || n.length > 24) return Future<bool>.value(false);
    return _mutate(communityId, (Community c) {
      final role = c.roleOf(actorId);
      if (role == null || !CommunityPermissions.canAddMembers(role)) return false;
      if (c.hasMemberNamed(n)) return false;
      c.members.add(CommunityMember(id: repo.newId('lp'), name: n, role: CommunityRole.member, joinedAt: _clock(), local: true));
      return true;
    });
  }

  /// Real members: role-checked RPC on the server; local (same-device) players: the document.
  Future<bool> changeRole(String communityId, String actorId, String targetId, CommunityRole role) async {
    final SupabaseSocialRepository? on = online;
    final Community? c = byId(communityId);
    final CommunityMember? t = c?.member(targetId);
    if (on != null && on.isRemote(communityId) && t != null && !t.local) {
      final Community probe = Community.fromJson(c!.toJson());
      if (!probe.changeRole(actorId, targetId, role)) return false;
      final bool ok = await on.setRole(communityId, targetId, role);
      await refresh();
      return ok;
    }
    return _mutate(communityId, (Community c) => c.changeRole(actorId, targetId, role));
  }

  Future<bool> removeMember(String communityId, String actorId, String targetId) async {
    final SupabaseSocialRepository? on = online;
    final Community? c = byId(communityId);
    final CommunityMember? t = c?.member(targetId);
    if (on != null && on.isRemote(communityId) && t != null && !t.local) {
      final Community probe = Community.fromJson(c!.toJson());
      if (!probe.removeMember(actorId, targetId)) return false;
      final bool ok = await on.kick(communityId, targetId);
      if (ok)
        await _mutate(communityId, (Community x) {
          for (final e in x.events) {
            e.going.remove(targetId);
          }
          return true;
        });
      await refresh();
      return ok;
    }
    return _mutate(communityId, (Community c) => c.removeMember(actorId, targetId));
  }

  /// Leave a community (not the owner). Online only.
  Future<bool> leave(String communityId) async {
    final SupabaseSocialRepository? on = online;
    if (on == null) return false;
    try {
      await on.leave(communityId);
    } catch (_) {
      return false;
    }
    await refresh();
    return true;
  }

  Future<List<Community>> discover({String query = ''}) async {
    final SupabaseSocialRepository? on = online;
    if (on == null) return <Community>[];
    try {
      return await on.discover(query: query);
    } catch (_) {
      return <Community>[];
    }
  }

  Future<bool> joinOpen(String communityId) async {
    final SupabaseSocialRepository? on = online;
    if (on == null) return false;
    try {
      await on.joinOpen(communityId);
    } catch (_) {
      return false;
    }
    await refresh();
    return true;
  }

  // ---- tournaments ----

  /// Creates a bracket from member names. Returns null on success or an error key
  /// ('perm', 'count', 'dup').
  Future<String?> createTournament(
    String communityId, {
    required String actorId,
    required String name,
    required String gameId,
    required List<String> players,
    bool shuffle = true,
  }) async {
    final Community? c = await repo.community(communityId);
    if (c == null) return 'perm';
    final role = c.roleOf(actorId);
    if (role == null || !CommunityPermissions.canManageTournaments(role)) return 'perm';
    final clean = players.map((String p) => p.trim()).where((String p) => p.isNotEmpty).toList();
    if (clean.length < TournamentBracket.minPlayers || clean.length > TournamentBracket.maxPlayers) return 'count';
    if (clean.map((String p) => p.toLowerCase()).toSet().length != clean.length) return 'dup';
    if (shuffle) clean.shuffle();
    final TournamentBracket bracket = TournamentBracket.create(clean);
    final CommunityTournament t = CommunityTournament(
      id: repo.newId('tour'),
      name: name.trim().isEmpty ? 'Cup' : name.trim(),
      gameId: gameId,
      createdAt: _clock(),
      bracket: bracket,
    );
    final bool ok = await _mutate(communityId, (Community x) {
      x.tournaments.insert(0, t);
      return true;
    });
    return ok ? null : 'perm';
  }

  Future<bool> recordResult(String communityId, String tournamentId, String actorId, MatchRef ref, String winner) =>
      _mutate(communityId, (Community c) {
        final role = c.roleOf(actorId);
        if (role == null || !CommunityPermissions.canManageTournaments(role)) return false;
        for (final t in c.tournaments) {
          if (t.id == tournamentId) return t.bracket.setWinner(ref.round, ref.index, winner);
        }
        return false;
      });

  Future<bool> deleteTournament(String communityId, String tournamentId, String actorId) => _mutate(communityId, (Community c) {
        final role = c.roleOf(actorId);
        if (role == null || !CommunityPermissions.canManageTournaments(role)) return false;
        final int before = c.tournaments.length;
        c.tournaments.removeWhere((CommunityTournament t) => t.id == tournamentId);
        return c.tournaments.length != before;
      });
}
