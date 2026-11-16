import 'dart:math';

import '../../../core/storage/local_store.dart';
import '../models/orbit_models.dart';

/// Messenger data access. UI talks only to this interface; an online
/// implementation (Supabase realtime + offline queue) can replace the local one.
abstract class OrbitRepository {
  /// All chats; guarantees the Saved Orbit self chat exists. Pinned first, then by activity.
  Future<List<OrbitChat>> chats({required String ownerId});
  Future<OrbitChat?> chat(String id);
  Future<OrbitChat> createChat({
    required OrbitChatKind kind,
    required String name,
    required String ownerId,
    required String ownerName,
    String description = '',
    String badgeId = '',
  });
  Future<void> updateChat(OrbitChat chat);
  /// Deletes a group/channel and its messages. Saved Orbit cannot be deleted.
  Future<bool> deleteChat(String id);

  /// Messages of a chat, oldest first.
  Future<List<OrbitMessage>> messages(String chatId);
  Future<OrbitMessage?> lastMessage(String chatId);
  Future<OrbitMessage> send({
    required String chatId,
    required String authorId,
    required String authorName,
    OrbitMessageKind kind = OrbitMessageKind.text,
    String text = '',
    Map<String, dynamic>? payload,
    String? replyToId,
  });
  Future<bool> editMessage(String chatId, String messageId, String text);
  Future<void> deleteMessage(String chatId, String messageId);
  Future<void> togglePin(String chatId, String messageId);
  Future<void> toggleStar(String chatId, String messageId);
  Future<void> markRead(String chatId);
  Future<int> unreadCount(String chatId, String myId);

  /// Full-text search across every chat (newest first).
  Future<List<OrbitMessage>> search(String query);
  Future<List<OrbitMessage>> starred();
}

/// Offline implementation backed by [LocalStore].
class LocalOrbitRepository implements OrbitRepository {
  LocalOrbitRepository(this._store, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final LocalStore _store;
  final DateTime Function() _clock;
  final Random _rng = Random();

  static const String kChats = 'orbit.chats.v1';
  static String kMsgs(String chatId) => 'orbit.msgs.$chatId';
  static const int maxMessagesPerChat = 3000;

  List<OrbitChat>? _chats;
  final Map<String, List<OrbitMessage>> _msgCache = <String, List<OrbitMessage>>{};

  String _id(String p) => '${p}_${_clock().microsecondsSinceEpoch}_${_rng.nextInt(999999)}';

  List<OrbitChat> _readChats() {
    final c = _chats;
    if (c != null) return c;
    final list = (_store.getJsonList(kChats) ?? const <dynamic>[])
        .whereType<Map>()
        .map((Map e) => OrbitChat.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    _chats = list;
    return list;
  }

  Future<void> _writeChats() => _store.setJson(kChats, _readChats().map((OrbitChat c) => c.toJson()).toList());

  List<OrbitMessage> _readMsgs(String chatId) {
    final c = _msgCache[chatId];
    if (c != null) return c;
    final list = (_store.getJsonList(kMsgs(chatId)) ?? const <dynamic>[])
        .whereType<Map>()
        .map((Map e) => OrbitMessage.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    _msgCache[chatId] = list;
    return list;
  }

  Future<void> _writeMsgs(String chatId) async {
    final list = _readMsgs(chatId);
    if (list.length > maxMessagesPerChat) list.removeRange(0, list.length - maxMessagesPerChat);
    await _store.setJson(kMsgs(chatId), list.map((OrbitMessage m) => m.toJson()).toList());
  }

  OrbitChat? _findChat(String id) {
    for (final c in _readChats()) {
      if (c.id == id) return c;
    }
    return null;
  }

  OrbitMessage? _findMsg(String chatId, String id) {
    for (final m in _readMsgs(chatId)) {
      if (m.id == id) return m;
    }
    return null;
  }

  DateTime _activity(OrbitChat c) {
    final msgs = _readMsgs(c.id);
    return msgs.isEmpty ? c.createdAt : msgs.last.createdAt;
  }

  @override
  Future<List<OrbitChat>> chats({required String ownerId}) async {
    final list = _readChats();
    if (_findChat(kSavedOrbitId) == null) {
      list.insert(
        0,
        OrbitChat(
          id: kSavedOrbitId,
          kind: OrbitChatKind.saved,
          name: 'Saved Orbit',
          createdAt: _clock(),
          ownerId: ownerId,
          pinned: true,
        ),
      );
      await _writeChats();
    }
    final sorted = List<OrbitChat>.from(list)
      ..sort((OrbitChat a, OrbitChat b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
        return _activity(b).compareTo(_activity(a));
      });
    return sorted;
  }

  @override
  Future<OrbitChat?> chat(String id) async => _findChat(id);

  @override
  Future<OrbitChat> createChat({
    required OrbitChatKind kind,
    required String name,
    required String ownerId,
    required String ownerName,
    String description = '',
    String badgeId = '',
  }) async {
    final c = OrbitChat(
      id: _id(kind == OrbitChatKind.channel ? 'chan' : 'grp'),
      kind: kind == OrbitChatKind.saved ? OrbitChatKind.group : kind,
      name: name.trim().isEmpty ? 'Orbit' : name.trim(),
      description: description.trim(),
      badgeId: badgeId,
      createdAt: _clock(),
      ownerId: ownerId,
    );
    _readChats().add(c);
    await _writeChats();
    _readMsgs(c.id).add(OrbitMessage(
      id: _id('sys'),
      chatId: c.id,
      authorId: 'system',
      authorName: 'ORBIT',
      kind: OrbitMessageKind.system,
      text: kind == OrbitChatKind.channel ? 'channel_created' : 'group_created',
      payload: <String, dynamic>{'by': ownerName},
      createdAt: _clock(),
      delivery: OrbitDelivery.read,
    ));
    await _writeMsgs(c.id);
    return c;
  }

  @override
  Future<void> updateChat(OrbitChat chat) async {
    final list = _readChats();
    final i = list.indexWhere((OrbitChat c) => c.id == chat.id);
    if (i < 0) return;
    list[i] = chat;
    await _writeChats();
  }

  @override
  Future<bool> deleteChat(String id) async {
    if (id == kSavedOrbitId) return false;
    _readChats().removeWhere((OrbitChat c) => c.id == id);
    await _writeChats();
    _msgCache.remove(id);
    await _store.remove(kMsgs(id));
    return true;
  }

  @override
  Future<List<OrbitMessage>> messages(String chatId) async => List<OrbitMessage>.from(_readMsgs(chatId));

  @override
  Future<OrbitMessage?> lastMessage(String chatId) async {
    final l = _readMsgs(chatId);
    return l.isEmpty ? null : l.last;
  }

  @override
  Future<OrbitMessage> send({
    required String chatId,
    required String authorId,
    required String authorName,
    OrbitMessageKind kind = OrbitMessageKind.text,
    String text = '',
    Map<String, dynamic>? payload,
    String? replyToId,
  }) async {
    final chat = _findChat(chatId);
    if (chat == null) throw StateError('Unknown chat $chatId');
    if (!chat.canPost(authorId)) throw StateError('Only channel admins can post');
    final m = OrbitMessage(
      id: _id('msg'),
      chatId: chatId,
      authorId: authorId,
      authorName: authorName,
      kind: kind,
      text: text.trim(),
      payload: payload,
      replyToId: replyToId,
      createdAt: _clock(),
      // Saved Orbit is read by you on this device; anything else waits for the server.
      delivery: chat.isSaved ? OrbitDelivery.read : OrbitDelivery.queued,
    );
    _readMsgs(chatId).add(m);
    await _writeMsgs(chatId);
    chat.lastReadAt = m.createdAt;
    await _writeChats();
    return m;
  }

  @override
  Future<bool> editMessage(String chatId, String messageId, String text) async {
    final m = _findMsg(chatId, messageId);
    final t = text.trim();
    if (m == null || !m.editable || t.isEmpty) return false;
    m.text = t;
    m.editedAt = _clock();
    await _writeMsgs(chatId);
    return true;
  }

  @override
  Future<void> deleteMessage(String chatId, String messageId) async {
    final m = _findMsg(chatId, messageId);
    if (m == null) return;
    m.deleted = true;
    m.text = '';
    m.payload.clear();
    m.pinned = false;
    m.starred = false;
    await _writeMsgs(chatId);
  }

  @override
  Future<void> togglePin(String chatId, String messageId) async {
    final m = _findMsg(chatId, messageId);
    if (m == null || m.deleted) return;
    m.pinned = !m.pinned;
    await _writeMsgs(chatId);
  }

  @override
  Future<void> toggleStar(String chatId, String messageId) async {
    final m = _findMsg(chatId, messageId);
    if (m == null || m.deleted) return;
    m.starred = !m.starred;
    await _writeMsgs(chatId);
  }

  @override
  Future<void> markRead(String chatId) async {
    final c = _findChat(chatId);
    if (c == null) return;
    c.lastReadAt = _clock();
    await _writeChats();
  }

  @override
  Future<int> unreadCount(String chatId, String myId) async {
    final c = _findChat(chatId);
    if (c == null) return 0;
    final since = c.lastReadAt;
    return _readMsgs(chatId)
        .where((OrbitMessage m) =>
            m.authorId != myId && !m.deleted && (since == null || m.createdAt.isAfter(since)))
        .length;
  }

  @override
  Future<List<OrbitMessage>> search(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return <OrbitMessage>[];
    final out = <OrbitMessage>[];
    for (final c in _readChats()) {
      for (final m in _readMsgs(c.id)) {
        if (m.deleted || m.kind == OrbitMessageKind.system) continue;
        final hay = '${m.text} ${m.payload['text'] ?? ''}'.toLowerCase();
        if (hay.contains(q)) out.add(m);
      }
    }
    out.sort((OrbitMessage a, OrbitMessage b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  @override
  Future<List<OrbitMessage>> starred() async {
    final out = <OrbitMessage>[];
    for (final c in _readChats()) {
      out.addAll(_readMsgs(c.id).where((OrbitMessage m) => m.starred && !m.deleted));
    }
    out.sort((OrbitMessage a, OrbitMessage b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }
}
