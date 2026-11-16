import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/social_models.dart';
import 'social_repository.dart';

/// Online SOCIAL STATION on Supabase.
///
/// * `nx_communities` holds each community's document (feed posts, events + RSVPs, announcements, tournaments with
///   brackets, rules, same-device "local players") with a version number;
/// * `nx_community_members` holds the real members and their roles (owner / admin / moderator / member).
///
/// Writes go through `nx_community_save(id, data, version)`: optimistic concurrency (a stale version is refused
/// and [mutate] re-applies the change on the fresh copy) and the server keeps only the parts the caller's role may
/// change. Role changes, removals, joins and deletes are separate role-checked RPCs.
///
/// The UI identifies "me" by the explorer id, so my auth uid is swapped for [explorerId] on the way out and back on
/// the way in. Communities that were created offline on this device stay in [local] and keep working there.
class SupabaseSocialRepository implements SocialRepository {
  SupabaseSocialRepository(this.c, this.local, {required this.explorerId});

  final SupabaseClient c;
  final LocalSocialRepository local;
  final String explorerId;

  String get me => c.auth.currentUser!.id;

  final Map<String, int> _versions = <String, int>{};
  final Map<String, Community> _cache = <String, Community>{};

  static final RegExp _uuid = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');
  bool isRemote(String id) => _uuid.hasMatch(id);

  static Object? _swap(Object? v, String from, String to) {
    if (v is String) return v == from ? to : v;
    if (v is List) return v.map((Object? e) => _swap(e, from, to)).toList();
    if (v is Map)
      return <String, dynamic>{for (final MapEntry<dynamic, dynamic> e in v.entries) '${e.key}': _swap(e.value, from, to)};
    return v;
  }

  @override
  String newId(String prefix) => local.newId(prefix);

  Future<Map<String, String>> _names(List<String> ids) async {
    if (ids.isEmpty) return <String, String>{};
    final List<dynamic> rows = await c.from('profiles').select('id, username').inFilter('id', ids);
    return <String, String>{for (final dynamic r in rows) '${(r as Map)['id']}': '${r['username'] ?? 'Pilot'}'};
  }

  Future<List<Community>> _build(List<dynamic> rows) async {
    if (rows.isEmpty) return <Community>[];
    final List<String> ids = rows.map((dynamic r) => '${(r as Map)['id']}').toList();
    final List<dynamic> mem = await c.from('nx_community_members').select().inFilter('community_id', ids);
    final Map<String, String> names = await _names(mem.map((dynamic m) => '${(m as Map)['user_id']}').toSet().toList());
    final List<Community> out = <Community>[];
    for (final dynamic raw in rows) {
      final Map<String, dynamic> r = Map<String, dynamic>.from(raw as Map);
      final String id = '${r['id']}';
      final Map<String, dynamic> data = Map<String, dynamic>.from((r['data'] as Map?) ?? const <String, dynamic>{});
      final List<Map<String, dynamic>> members = <Map<String, dynamic>>[
        for (final dynamic m in mem.where((dynamic m) => '${(m as Map)['community_id']}' == id))
          <String, dynamic>{
            'id': '${(m as Map)['user_id']}',
            'name': names['${m['user_id']}'] ?? 'Pilot',
            'role': '${m['role']}',
            'joinedAt': '${m['joined_at']}',
          },
        ...((data['localMembers'] as List?) ?? const <dynamic>[]).whereType<Map>().map((Map m) => Map<String, dynamic>.from(m)),
      ];
      final Map<String, dynamic> doc = <String, dynamic>{
        ...data,
        'id': id,
        'name': r['name'],
        'kind': r['kind'],
        'badgeId': r['badge_id'],
        'ownerId': r['owner'],
        'inviteCode': r['invite_code'],
        'createdAt': r['created_at'],
        'members': members,
      };
      final Community com = Community.fromJson(Map<String, dynamic>.from(_swap(doc, me, explorerId) as Map));
      _versions[id] = (r['version'] as num?)?.toInt() ?? 1;
      _cache[id] = com;
      out.add(com);
    }
    return out;
  }

  Map<String, dynamic> _doc(Community com) {
    final Map<String, dynamic> j = Map<String, dynamic>.from(_swap(com.toJson(), explorerId, me) as Map);
    j['localMembers'] = (j['members'] as List?)?.where((dynamic m) => (m as Map)['local'] == true).toList() ?? <dynamic>[];
    j.remove('members');
    return j;
  }

  @override
  Future<List<Community>> communities() async {
    final List<Community> offline = await local.communities();
    try {
      final List<dynamic> mine = await c.from('nx_community_members').select('community_id').eq('user_id', me);
      final List<String> ids = mine.map((dynamic r) => '${(r as Map)['community_id']}').toList();
      _cache.clear();
      if (ids.isNotEmpty) {
        final List<dynamic> rows = await c.from('nx_communities').select().inFilter('id', ids);
        await _build(rows);
      }
    } catch (_) {
      // offline: last copy
    }
    final List<Community> out = <Community>[..._cache.values, ...offline]
      ..sort((Community a, Community b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  /// Public (non-private) communities I am not in yet, newest first, for discovery.
  Future<List<Community>> discover({String query = ''}) async {
    final String q = query.trim().replaceAll('%', '');
    final List<dynamic> mine = await c.from('nx_community_members').select('community_id').eq('user_id', me);
    final Set<String> ids = mine.map((dynamic r) => '${(r as Map)['community_id']}').toSet();
    var req = c.from('nx_communities').select().neq('kind', 'private');
    if (q.isNotEmpty) req = req.ilike('name', '%$q%');
    final List<dynamic> rows = await req.order('created_at', ascending: false).limit(40);
    final List<Community> l = await _build(rows.where((dynamic r) => !ids.contains('${(r as Map)['id']}')).toList());
    for (final Community x in l) {
      _cache.remove(x.id);
    }
    return l;
  }

  Future<Community?> _fetch(String id) async {
    final List<dynamic> rows = await c.from('nx_communities').select().eq('id', id).limit(1);
    final List<Community> l = await _build(rows);
    return l.isEmpty ? null : l.first;
  }

  @override
  Future<Community?> community(String id) async {
    if (!isRemote(id)) return local.community(id);
    try {
      return await _fetch(id);
    } catch (_) {
      return _cache[id];
    }
  }

  /// Joins by invite code (any kind) and returns the community, or null for an unknown code.
  @override
  Future<Community?> byInviteCode(String code) async {
    final Community? l = await local.byInviteCode(code);
    if (l != null) return l;
    final String? n = InviteCode.normalize(code);
    if (n == null) return null;
    try {
      final dynamic id = await c.rpc('nx_community_join', params: <String, dynamic>{'p_code': n});
      return await _fetch('$id');
    } catch (_) {
      return null;
    }
  }

  Future<bool> joinOpen(String id) async {
    await c.rpc('nx_community_join_open', params: <String, dynamic>{'p_id': id});
    return true;
  }

  Future<void> leave(String id) => c.rpc('nx_community_leave', params: <String, dynamic>{'p_id': id});

  @override
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
    final String n = name.trim().isEmpty ? 'Community' : name.trim();
    final dynamic r = await c.rpc('nx_community_create', params: <String, dynamic>{
      'p_name': n.length > 40 ? n.substring(0, 40) : n,
      'p_kind': kind.name,
      'p_badge': kCommunityBadges.contains(badgeId) ? badgeId : kCommunityBadges.first,
      'p_data': <String, dynamic>{
        'description': description.trim(),
        if (gameId != null) 'gameId': gameId,
        'rules': rules.map((String r) => r.trim()).where((String r) => r.isNotEmpty).toList(),
        'posts': <dynamic>[],
        'events': <dynamic>[],
        'announcements': <dynamic>[],
        'tournaments': <dynamic>[],
        'localMembers': <dynamic>[],
      },
    });
    final List<Community> l = await _build(<dynamic>[r]);
    return l.first;
  }

  @override
  Future<void> save(Community community) async {
    if (!isRemote(community.id)) return local.save(community);
    final dynamic v = await c.rpc('nx_community_save', params: <String, dynamic>{
      'p_id': community.id,
      'p_data': _doc(community),
      'p_version': _versions[community.id] ?? 1,
    });
    _versions[community.id] = (v as num?)?.toInt() ?? ((_versions[community.id] ?? 1) + 1);
  }

  /// Applies [change] to the freshest server copy and saves it; on a version conflict fetches again and
  /// re-applies (max 3 tries). Returns false when [change] refuses or the save keeps failing.
  Future<bool> mutate(String id, bool Function(Community c) change) async {
    if (!isRemote(id)) {
      final Community? x = await local.community(id);
      if (x == null || !change(x)) return false;
      await local.save(x);
      return true;
    }
    for (int i = 0; i < 3; i++) {
      final Community? x = await _fetch(id);
      if (x == null || !change(x)) return false;
      try {
        await save(x);
        return true;
      } on PostgrestException catch (e) {
        if (!e.message.contains('conflict')) return false;
      }
    }
    return false;
  }

  Future<bool> setRole(String id, String targetId, CommunityRole role) async {
    try {
      await c.rpc('nx_community_set_role',
          params: <String, dynamic>{'p_id': id, 'p_user': targetId == explorerId ? me : targetId, 'p_role': role.name});
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> kick(String id, String targetId) async {
    try {
      await c.rpc('nx_community_kick', params: <String, dynamic>{'p_id': id, 'p_user': targetId});
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> delete(String id) async {
    if (!isRemote(id)) return local.delete(id);
    await c.rpc('nx_community_delete', params: <String, dynamic>{'p_id': id});
    _cache.remove(id);
  }
}
