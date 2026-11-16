// Pure-Dart models for SOCIAL STATION (mirrors the future Supabase tables
// communities / community_members / roles / events / community_rules).
// No Flutter imports: the permission matrix can run server-side later (RLS).
import 'dart:math';

import 'tournament_bracket.dart';

DateTime _time(Object? v) {
  if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
  if (v is String) return DateTime.tryParse(v) ?? DateTime.fromMillisecondsSinceEpoch(int.tryParse(v) ?? 0);
  return DateTime.fromMillisecondsSinceEpoch(0);
}

T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

List<Map<String, dynamic>> _maps(Object? raw) {
  if (raw is! List) return <Map<String, dynamic>>[];
  return raw.whereType<Map>().map((Map m) => Map<String, dynamic>.from(m)).toList();
}

Set<String> _strings(Object? raw) {
  if (raw is! List) return <String>{};
  return raw.map((dynamic e) => '$e').toSet();
}

/// Kinds of community (category used for filtering and search).
enum CommunityKind { public, private, topic, game, tournament }

/// Club badges a community can wear (AppAssets.clubBadge ids).
const List<String> kCommunityBadges = <String>[
  'badge_club_scorpion',
  'badge_club_wolf',
  'badge_club_yakuza',
  'badge_club_monster',
  'badge_club_bermuda',
  'badge_club_stone',
];

/// Roles, from most to least powerful.
enum CommunityRole { owner, admin, moderator, member }

extension CommunityRoleRank on CommunityRole {
  /// Higher = more power.
  int get rank {
    switch (this) {
      case CommunityRole.owner:
        return 3;
      case CommunityRole.admin:
        return 2;
      case CommunityRole.moderator:
        return 1;
      case CommunityRole.member:
        return 0;
    }
  }
}

/// The permission matrix (same rules the server's RLS policies will enforce).
class CommunityPermissions {
  CommunityPermissions._();

  /// Can [actor] give [target] the role [newRole]?
  /// - Nobody changes their own role, and nobody can make a second owner.
  /// - The owner's role never changes (ownership transfer is an online feature).
  /// - You can only touch members strictly below you and only grant roles strictly below yours.
  static bool canChangeRole(CommunityRole actor, CommunityRole target, CommunityRole newRole, {bool self = false}) {
    if (self) return false;
    if (target == CommunityRole.owner || newRole == CommunityRole.owner) return false;
    if (actor.rank < CommunityRole.admin.rank) return false;
    if (target.rank >= actor.rank) return false;
    if (newRole.rank >= actor.rank) return false;
    return target != newRole;
  }

  /// Can [actor] remove (kick) [target]? Moderators and up, strictly above the target, never the owner or yourself.
  static bool canRemove(CommunityRole actor, CommunityRole target, {bool self = false}) {
    if (self) return false;
    if (target == CommunityRole.owner) return false;
    if (actor.rank < CommunityRole.moderator.rank) return false;
    return actor.rank > target.rank;
  }

  static bool canAddMembers(CommunityRole actor) => actor.rank >= CommunityRole.moderator.rank;
  static bool canAnnounce(CommunityRole actor) => actor.rank >= CommunityRole.admin.rank;
  static bool canEditInfo(CommunityRole actor) => actor.rank >= CommunityRole.admin.rank;
  static bool canManageEvents(CommunityRole actor) => actor.rank >= CommunityRole.moderator.rank;
  static bool canManageTournaments(CommunityRole actor) => actor.rank >= CommunityRole.moderator.rank;
  static bool canPinPosts(CommunityRole actor) => actor.rank >= CommunityRole.moderator.rank;
  static bool canDeleteCommunity(CommunityRole actor) => actor == CommunityRole.owner;

  /// Authors may delete their own posts; moderators+ may delete anyone's.
  static bool canDeletePost(CommunityRole actor, {required bool own}) =>
      own || actor.rank >= CommunityRole.moderator.rank;
}

class CommunityMember {
  CommunityMember({
    required this.id,
    required this.name,
    required this.role,
    required this.joinedAt,
    this.local = false,
  });

  final String id;
  String name;
  CommunityRole role;
  final DateTime joinedAt;

  /// A named player on this device (for same-device tournaments), not a real online account.
  final bool local;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'role': role.name,
        'joinedAt': joinedAt.millisecondsSinceEpoch,
        'local': local,
      };

  static CommunityMember fromJson(Map<String, dynamic> j) => CommunityMember(
        id: '${j['id']}',
        name: '${j['name'] ?? ''}',
        role: _enumByName<CommunityRole>(CommunityRole.values, j['role'], CommunityRole.member),
        joinedAt: _time(j['joinedAt']),
        local: j['local'] == true,
      );
}

class CommunityPost {
  CommunityPost({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.text,
    required this.at,
    Set<String>? likedBy,
    this.pinned = false,
  }) : likedBy = likedBy ?? <String>{};

  final String id;
  final String authorId;
  final String authorName;
  String text;
  final DateTime at;
  final Set<String> likedBy;
  bool pinned;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'authorId': authorId,
        'authorName': authorName,
        'text': text,
        'at': at.millisecondsSinceEpoch,
        'likedBy': likedBy.toList(),
        'pinned': pinned,
      };

  static CommunityPost fromJson(Map<String, dynamic> j) => CommunityPost(
        id: '${j['id']}',
        authorId: '${j['authorId'] ?? ''}',
        authorName: '${j['authorName'] ?? ''}',
        text: '${j['text'] ?? ''}',
        at: _time(j['at']),
        likedBy: _strings(j['likedBy']),
        pinned: j['pinned'] == true,
      );
}

class CommunityEvent {
  CommunityEvent({
    required this.id,
    required this.title,
    required this.startsAt,
    required this.createdBy,
    this.description = '',
    this.gameId,
    Set<String>? going,
  }) : going = going ?? <String>{};

  final String id;
  String title;
  String description;
  DateTime startsAt;
  final String createdBy;

  /// Optional arcade game played at this event.
  String? gameId;

  /// Member ids who RSVP'd "going".
  final Set<String> going;

  bool isPast(DateTime now) => !now.isBefore(startsAt);

  /// Time left until the event (zero once started).
  Duration countdown(DateTime now) {
    final d = startsAt.difference(now);
    return d.isNegative ? Duration.zero : d;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'description': description,
        'startsAt': startsAt.millisecondsSinceEpoch,
        'createdBy': createdBy,
        if (gameId != null) 'gameId': gameId,
        'going': going.toList(),
      };

  static CommunityEvent fromJson(Map<String, dynamic> j) => CommunityEvent(
        id: '${j['id']}',
        title: '${j['title'] ?? ''}',
        description: '${j['description'] ?? ''}',
        startsAt: _time(j['startsAt']),
        createdBy: '${j['createdBy'] ?? ''}',
        gameId: j['gameId'] as String?,
        going: _strings(j['going']),
      );
}

class CommunityAnnouncement {
  CommunityAnnouncement({required this.id, required this.text, required this.authorName, required this.at});

  final String id;
  final String text;
  final String authorName;
  final DateTime at;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'text': text,
        'authorName': authorName,
        'at': at.millisecondsSinceEpoch,
      };

  static CommunityAnnouncement fromJson(Map<String, dynamic> j) => CommunityAnnouncement(
        id: '${j['id']}',
        text: '${j['text'] ?? ''}',
        authorName: '${j['authorName'] ?? ''}',
        at: _time(j['at']),
      );
}

/// A community-hosted single-elimination tournament on one arcade game.
class CommunityTournament {
  CommunityTournament({
    required this.id,
    required this.name,
    required this.gameId,
    required this.createdAt,
    required this.bracket,
  });

  final String id;
  String name;
  final String gameId;
  final DateTime createdAt;
  final TournamentBracket bracket;

  bool get finished => bracket.finished;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'gameId': gameId,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'bracket': bracket.toJson(),
      };

  static CommunityTournament fromJson(Map<String, dynamic> j) => CommunityTournament(
        id: '${j['id']}',
        name: '${j['name'] ?? ''}',
        gameId: '${j['gameId'] ?? 'finger_soccer'}',
        createdAt: _time(j['createdAt']),
        bracket: TournamentBracket.fromJson(
            j['bracket'] is Map ? Map<String, dynamic>.from(j['bracket'] as Map) : <String, dynamic>{}),
      );
}

/// Invite codes look like `NX-7KQ2MZ` (no 0/O/1/I to avoid confusion).
class InviteCode {
  InviteCode._();
  static const String _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static final RegExp pattern = RegExp(r'^NX-[A-HJ-NP-Z2-9]{6}$');

  static String generate(Random rng) {
    final b = StringBuffer('NX-');
    for (var i = 0; i < 6; i++) {
      b.write(_alphabet[rng.nextInt(_alphabet.length)]);
    }
    return b.toString();
  }

  /// Normalises user input (`nx 7kq2mz` -> `NX-7KQ2MZ`). Returns null if invalid.
  static String? normalize(String raw) {
    var s = raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (s.startsWith('NX')) s = s.substring(2);
    final code = 'NX-$s';
    return pattern.hasMatch(code) ? code : null;
  }
}

class Community {
  Community({
    required this.id,
    required this.name,
    required this.kind,
    required this.badgeId,
    required this.ownerId,
    required this.inviteCode,
    required this.createdAt,
    this.description = '',
    this.gameId,
    List<String>? rules,
    List<CommunityMember>? members,
    List<CommunityPost>? posts,
    List<CommunityEvent>? events,
    List<CommunityAnnouncement>? announcements,
    List<CommunityTournament>? tournaments,
  })  : rules = rules ?? <String>[],
        members = members ?? <CommunityMember>[],
        posts = posts ?? <CommunityPost>[],
        events = events ?? <CommunityEvent>[],
        announcements = announcements ?? <CommunityAnnouncement>[],
        tournaments = tournaments ?? <CommunityTournament>[];

  final String id;
  String name;
  CommunityKind kind;
  String badgeId;
  String description;

  /// Main arcade game for game/tournament communities.
  String? gameId;
  final String ownerId;
  final String inviteCode;
  final DateTime createdAt;
  final List<String> rules;
  final List<CommunityMember> members;
  final List<CommunityPost> posts;
  final List<CommunityEvent> events;
  final List<CommunityAnnouncement> announcements;
  final List<CommunityTournament> tournaments;

  CommunityMember? member(String id) {
    for (final m in members) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// Role of [userId], or null if not a member.
  CommunityRole? roleOf(String userId) => member(userId)?.role;

  bool hasMemberNamed(String name) {
    final n = name.trim().toLowerCase();
    return members.any((CommunityMember m) => m.name.trim().toLowerCase() == n);
  }

  /// Posts with pinned first, then newest first.
  List<CommunityPost> get sortedPosts {
    final l = List<CommunityPost>.from(posts);
    l.sort((CommunityPost a, CommunityPost b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.at.compareTo(a.at);
    });
    return l;
  }

  /// Upcoming events (soonest first), then past ones (most recent first).
  List<CommunityEvent> sortedEvents(DateTime now) {
    final up = events.where((CommunityEvent e) => !e.isPast(now)).toList()
      ..sort((CommunityEvent a, CommunityEvent b) => a.startsAt.compareTo(b.startsAt));
    final past = events.where((CommunityEvent e) => e.isPast(now)).toList()
      ..sort((CommunityEvent a, CommunityEvent b) => b.startsAt.compareTo(a.startsAt));
    return <CommunityEvent>[...up, ...past];
  }

  CommunityEvent? nextEvent(DateTime now) {
    final up = sortedEvents(now).where((CommunityEvent e) => !e.isPast(now));
    return up.isEmpty ? null : up.first;
  }

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return name.toLowerCase().contains(q) ||
        description.toLowerCase().contains(q) ||
        inviteCode.toLowerCase() == q ||
        kind.name.contains(q);
  }

  // ---- permission-checked mutations (return false when not allowed) ----

  bool changeRole(String actorId, String targetId, CommunityRole newRole) {
    final actor = roleOf(actorId);
    final target = member(targetId);
    if (actor == null || target == null) return false;
    if (!CommunityPermissions.canChangeRole(actor, target.role, newRole, self: actorId == targetId)) return false;
    target.role = newRole;
    return true;
  }

  bool removeMember(String actorId, String targetId) {
    final actor = roleOf(actorId);
    final target = member(targetId);
    if (actor == null || target == null) return false;
    if (!CommunityPermissions.canRemove(actor, target.role, self: actorId == targetId)) return false;
    members.remove(target);
    for (final e in events) {
      e.going.remove(targetId);
    }
    return true;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'kind': kind.name,
        'badgeId': badgeId,
        'description': description,
        if (gameId != null) 'gameId': gameId,
        'ownerId': ownerId,
        'inviteCode': inviteCode,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'rules': rules,
        'members': members.map((CommunityMember m) => m.toJson()).toList(),
        'posts': posts.map((CommunityPost p) => p.toJson()).toList(),
        'events': events.map((CommunityEvent e) => e.toJson()).toList(),
        'announcements': announcements.map((CommunityAnnouncement a) => a.toJson()).toList(),
        'tournaments': tournaments.map((CommunityTournament t) => t.toJson()).toList(),
      };

  static Community fromJson(Map<String, dynamic> j) => Community(
        id: '${j['id']}',
        name: '${j['name'] ?? ''}',
        kind: _enumByName<CommunityKind>(CommunityKind.values, j['kind'], CommunityKind.public),
        badgeId: '${j['badgeId'] ?? kCommunityBadges.first}',
        description: '${j['description'] ?? ''}',
        gameId: j['gameId'] as String?,
        ownerId: '${j['ownerId'] ?? ''}',
        inviteCode: '${j['inviteCode'] ?? ''}',
        createdAt: _time(j['createdAt']),
        rules: (j['rules'] is List) ? (j['rules'] as List).map((dynamic e) => '$e').toList() : <String>[],
        members: _maps(j['members']).map(CommunityMember.fromJson).toList(),
        posts: _maps(j['posts']).map(CommunityPost.fromJson).toList(),
        events: _maps(j['events']).map(CommunityEvent.fromJson).toList(),
        announcements: _maps(j['announcements']).map(CommunityAnnouncement.fromJson).toList(),
        tournaments: _maps(j['tournaments']).map(CommunityTournament.fromJson).toList(),
      );
}
