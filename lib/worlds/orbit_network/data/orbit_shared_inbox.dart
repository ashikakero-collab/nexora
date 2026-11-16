import '../../../core/storage/local_store.dart';

/// One item another world shared into ORBIT NETWORK (cross-world EventBus, offline form).
///
/// Contract (LocalStore key [OrbitSharedInbox.key], JSON list of maps):
///   `{type: 'nova_post' | 'game_invite' | 'community_invite' | ..., id, text, at, ...extra}`
/// `at` is milliseconds since epoch (ISO strings are tolerated when reading).
class SharedItem {
  SharedItem({required this.type, required this.id, required this.text, required this.at, Map<String, dynamic>? extra})
      : extra = extra ?? <String, dynamic>{};

  final String type;
  final String id;
  final String text;
  final DateTime at;
  /// Any additional fields (e.g. gameId, gradient, asset, author).
  final Map<String, dynamic> extra;

  static const String novaPost = 'nova_post';
  static const String gameInvite = 'game_invite';
  static const String communityInvite = 'community_invite';

  /// Key used to de-duplicate (same post shared twice stays one card).
  String get key => '$type:$id';

  String? get gameId {
    final g = extra['gameId'];
    if (g is String && g.isNotEmpty) return g;
    if (type == gameInvite) return id;
    return null;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        ...extra,
        'type': type,
        'id': id,
        'text': text,
        'at': at.millisecondsSinceEpoch,
      };

  static SharedItem? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    final type = m['type'];
    final id = m['id'];
    if (type is! String || id == null) return null;
    final atRaw = m['at'];
    DateTime at = DateTime.now();
    if (atRaw is num) {
      at = DateTime.fromMillisecondsSinceEpoch(atRaw.toInt());
    } else if (atRaw is String) {
      at = DateTime.tryParse(atRaw) ?? DateTime.fromMillisecondsSinceEpoch(int.tryParse(atRaw) ?? 0);
    }
    final extra = Map<String, dynamic>.from(m)
      ..remove('type')
      ..remove('id')
      ..remove('text')
      ..remove('at');
    return SharedItem(type: type, id: '$id', text: '${m['text'] ?? ''}', at: at, extra: extra);
  }
}

/// Reads/writes the shared inbox that every world can drop items into.
class OrbitSharedInbox {
  OrbitSharedInbox(this._store);
  final LocalStore _store;

  static const String key = 'orbit.shared_inbox';
  static const int maxItems = 100;

  List<SharedItem> read() {
    final raw = _store.getJsonList(key) ?? const <dynamic>[];
    final out = <SharedItem>[];
    for (final e in raw) {
      final it = SharedItem.fromJson(e);
      if (it != null) out.add(it);
    }
    out.sort((SharedItem a, SharedItem b) => b.at.compareTo(a.at));
    return out;
  }

  /// Adds an item (replacing an older one with the same type+id).
  Future<void> add(SharedItem item) async {
    final raw = List<dynamic>.from(_store.getJsonList(key) ?? const <dynamic>[]);
    raw.removeWhere((dynamic e) {
      final it = SharedItem.fromJson(e);
      return it != null && it.key == item.key;
    });
    raw.add(item.toJson());
    while (raw.length > maxItems) {
      raw.removeAt(0);
    }
    await _store.setJson(key, raw);
  }

  /// Removes an item once it has been delivered into a chat (or dismissed).
  Future<void> remove(String itemKey) async {
    final raw = List<dynamic>.from(_store.getJsonList(key) ?? const <dynamic>[]);
    raw.removeWhere((dynamic e) {
      final it = SharedItem.fromJson(e);
      return it == null || it.key == itemKey;
    });
    await _store.setJson(key, raw);
  }

  Future<void> clear() => _store.remove(key);
}
