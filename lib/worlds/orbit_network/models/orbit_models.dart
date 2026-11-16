// Pure-Dart models for ORBIT NETWORK (message contract shared with the future
// Supabase tables conversations / conversation_members / messages / message_reads).

DateTime _time(Object? v) {
  if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
  if (v is String) return DateTime.tryParse(v) ?? DateTime.fromMillisecondsSinceEpoch(int.tryParse(v) ?? 0);
  return DateTime.fromMillisecondsSinceEpoch(0);
}

DateTime? _timeOrNull(Object? v) => v == null ? null : _time(v);

T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

/// The self chat id ("Saved Orbit").
const String kSavedOrbitId = 'saved_orbit';

/// [direct] = 1:1 chat with a real user (online only).
enum OrbitChatKind { saved, group, channel, direct }

/// Delivery state of a message. Offline, group/channel messages stay [queued]
/// until the server exists; Saved Orbit messages are [read] by you on this device.
enum OrbitDelivery { queued, sent, delivered, read }

enum OrbitMessageKind { text, art, shared, invite, system, call }

class OrbitChat {
  OrbitChat({
    required this.id,
    required this.kind,
    required this.name,
    required this.createdAt,
    required this.ownerId,
    this.description = '',
    this.badgeId = '',
    this.pinned = false,
    this.muted = false,
    this.lastReadAt,
    this.role = 'owner',
    this.peerId,
    this.peerName,
    this.peerOnlineAt,
    this.memberCount = 1,
    this.online = false,
  });

  final String id;
  final OrbitChatKind kind;

  /// Online: my role in this chat ('owner' | 'admin' | 'member').
  String role;

  /// Direct chats: the other person.
  final String? peerId;
  final String? peerName;
  final DateTime? peerOnlineAt;
  int memberCount;

  /// Lives on the server (real members) rather than only on this device.
  final bool online;
  String name;
  String description;

  /// Club badge id (AppAssets.clubBadge), empty for none.
  String badgeId;
  final DateTime createdAt;
  final String ownerId;
  bool pinned;
  bool muted;
  DateTime? lastReadAt;

  bool get isSaved => kind == OrbitChatKind.saved;
  bool get isChannel => kind == OrbitChatKind.channel;
  bool get isDirect => kind == OrbitChatKind.direct;
  bool get isAdmin => role == 'owner' || role == 'admin';
  bool get peerOnlineNow => peerOnlineAt != null && DateTime.now().toUtc().difference(peerOnlineAt!.toUtc()).inMinutes < 3;

  /// Channels: only the owner/admins publish.
  bool canPost(String userId) => kind != OrbitChatKind.channel || userId == ownerId || (online && isAdmin);

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'kind': kind.name,
        'name': name,
        'description': description,
        'badgeId': badgeId,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'ownerId': ownerId,
        'pinned': pinned,
        'muted': muted,
        if (lastReadAt != null) 'lastReadAt': lastReadAt!.millisecondsSinceEpoch,
      };

  static OrbitChat fromJson(Map<String, dynamic> j) => OrbitChat(
        id: '${j['id']}',
        kind: _enumByName<OrbitChatKind>(OrbitChatKind.values, j['kind'], OrbitChatKind.group),
        name: '${j['name'] ?? ''}',
        description: '${j['description'] ?? ''}',
        badgeId: '${j['badgeId'] ?? ''}',
        createdAt: _time(j['createdAt']),
        ownerId: '${j['ownerId'] ?? ''}',
        pinned: j['pinned'] == true,
        muted: j['muted'] == true,
        lastReadAt: _timeOrNull(j['lastReadAt']),
      );
}

class OrbitMessage {
  OrbitMessage({
    required this.id,
    required this.chatId,
    required this.authorId,
    required this.authorName,
    required this.kind,
    required this.createdAt,
    this.text = '',
    Map<String, dynamic>? payload,
    this.replyToId,
    this.editedAt,
    this.deleted = false,
    this.pinned = false,
    this.starred = false,
    this.delivery = OrbitDelivery.queued,
  }) : payload = payload ?? <String, dynamic>{};

  final String id;
  final String chatId;
  final String authorId;
  final String authorName;
  final OrbitMessageKind kind;
  String text;

  /// Kind-specific data: art {asset}, invite {gameId}, shared {SharedItem json}.
  final Map<String, dynamic> payload;
  final String? replyToId;
  final DateTime createdAt;
  DateTime? editedAt;
  bool deleted;
  bool pinned;
  bool starred;
  OrbitDelivery delivery;

  bool get editable => !deleted && kind == OrbitMessageKind.text;

  /// Short text for chat list previews and reply quotes.
  String preview({required bool fa}) {
    if (deleted) return fa ? 'پیام حذف شد' : 'Message deleted';
    switch (kind) {
      case OrbitMessageKind.text:
      case OrbitMessageKind.system:
        return text;
      case OrbitMessageKind.art:
        return (fa ? '🖼 اثر هنری ' : '🖼 Art ') + (text.isEmpty ? '' : '· $text');
      case OrbitMessageKind.shared:
        return (fa ? '🔗 اشتراک: ' : '🔗 Shared: ') + '${payload['text'] ?? text}';
      case OrbitMessageKind.invite:
        return fa ? '🎮 دعوت به آرکید' : '🎮 Arcade invite';
      case OrbitMessageKind.call:
        return payload['video'] == true ? (fa ? '📹 تماس تصویری' : '📹 Video call') : (fa ? '📞 تماس صوتی' : '📞 Voice call');
    }
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'chatId': chatId,
        'authorId': authorId,
        'authorName': authorName,
        'kind': kind.name,
        'text': text,
        'payload': payload,
        if (replyToId != null) 'replyToId': replyToId,
        'createdAt': createdAt.millisecondsSinceEpoch,
        if (editedAt != null) 'editedAt': editedAt!.millisecondsSinceEpoch,
        'deleted': deleted,
        'pinned': pinned,
        'starred': starred,
        'delivery': delivery.name,
      };

  static OrbitMessage fromJson(Map<String, dynamic> j) => OrbitMessage(
        id: '${j['id']}',
        chatId: '${j['chatId'] ?? ''}',
        authorId: '${j['authorId'] ?? ''}',
        authorName: '${j['authorName'] ?? ''}',
        kind: _enumByName<OrbitMessageKind>(OrbitMessageKind.values, j['kind'], OrbitMessageKind.text),
        text: '${j['text'] ?? ''}',
        payload: j['payload'] is Map ? Map<String, dynamic>.from(j['payload'] as Map) : <String, dynamic>{},
        replyToId: j['replyToId'] as String?,
        createdAt: _time(j['createdAt']),
        editedAt: _timeOrNull(j['editedAt']),
        deleted: j['deleted'] == true,
        pinned: j['pinned'] == true,
        starred: j['starred'] == true,
        delivery: _enumByName<OrbitDelivery>(OrbitDelivery.values, j['delivery'], OrbitDelivery.queued),
      );
}
