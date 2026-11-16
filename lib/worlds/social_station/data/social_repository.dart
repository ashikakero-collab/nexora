import 'dart:math';

import '../../../core/storage/local_store.dart';
import '../models/social_models.dart';

/// Data access for SOCIAL STATION. The UI only talks to this interface, so an
/// online (Supabase) implementation can be swapped in later.
abstract class SocialRepository {
  /// All communities on this device, newest first.
  Future<List<Community>> communities();
  Future<Community?> community(String id);

  /// Finds a community by its invite code (normalised), or null.
  Future<Community?> byInviteCode(String code);

  Future<Community> create({
    required String name,
    required CommunityKind kind,
    required String badgeId,
    required String ownerId,
    required String ownerName,
    String description = '',
    List<String> rules = const <String>[],
    String? gameId,
  });

  /// Persists a (mutated) community.
  Future<void> save(Community community);
  Future<void> delete(String id);

  /// New unique id with a prefix (posts, events, members...).
  String newId(String prefix);
}

/// Offline implementation backed by [LocalStore] (keys `social.*`).
class LocalSocialRepository implements SocialRepository {
  LocalSocialRepository(this._store, {DateTime Function()? clock, Random? rng})
      : _clock = clock ?? DateTime.now,
        _rng = rng ?? Random();

  final LocalStore _store;
  final DateTime Function() _clock;
  final Random _rng;

  static const String kCommunities = 'social.communities.v1';

  List<Community>? _cache;

  @override
  String newId(String prefix) => '${prefix}_${_clock().microsecondsSinceEpoch}_${_rng.nextInt(999999)}';

  List<Community> _read() {
    final c = _cache;
    if (c != null) return c;
    final list = (_store.getJsonList(kCommunities) ?? const <dynamic>[])
        .whereType<Map>()
        .map((Map e) => Community.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    _cache = list;
    return list;
  }

  Future<void> _write() => _store.setJson(kCommunities, _read().map((Community c) => c.toJson()).toList());

  Community? _find(String id) {
    for (final c in _read()) {
      if (c.id == id) return c;
    }
    return null;
  }

  @override
  Future<List<Community>> communities() async {
    final l = List<Community>.from(_read());
    l.sort((Community a, Community b) => b.createdAt.compareTo(a.createdAt));
    return l;
  }

  @override
  Future<Community?> community(String id) async => _find(id);

  @override
  Future<Community?> byInviteCode(String code) async {
    final n = InviteCode.normalize(code);
    if (n == null) return null;
    for (final c in _read()) {
      if (c.inviteCode == n) return c;
    }
    return null;
  }

  String _uniqueCode() {
    final used = _read().map((Community c) => c.inviteCode).toSet();
    var code = InviteCode.generate(_rng);
    while (used.contains(code)) {
      code = InviteCode.generate(_rng);
    }
    return code;
  }

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
    final now = _clock();
    final String n = name.trim().isEmpty ? 'Community' : name.trim();
    final c = Community(
      id: newId('com'),
      name: n.length > 40 ? n.substring(0, 40) : n,
      kind: kind,
      badgeId: kCommunityBadges.contains(badgeId) ? badgeId : kCommunityBadges.first,
      ownerId: ownerId,
      inviteCode: _uniqueCode(),
      createdAt: now,
      description: description.trim(),
      gameId: gameId,
      rules: rules.map((String r) => r.trim()).where((String r) => r.isNotEmpty).toList(),
      members: <CommunityMember>[
        CommunityMember(
          id: ownerId,
          name: ownerName.trim().isEmpty ? 'Explorer' : ownerName.trim(),
          role: CommunityRole.owner,
          joinedAt: now,
        ),
      ],
    );
    _read().add(c);
    await _write();
    return c;
  }

  @override
  Future<void> save(Community community) async {
    final list = _read();
    final i = list.indexWhere((Community c) => c.id == community.id);
    if (i < 0) {
      list.add(community);
    } else {
      list[i] = community;
    }
    await _write();
  }

  @override
  Future<void> delete(String id) async {
    _read().removeWhere((Community c) => c.id == id);
    await _write();
  }
}
