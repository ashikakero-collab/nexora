import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/storage/local_store.dart';
import '../models/orbit_models.dart';
import 'orbit_repository.dart';

/// A row of the call history (nx_calls).
class OrbitCallEntry {
  OrbitCallEntry({
    required this.id,
    required this.chatId,
    required this.callerId,
    required this.video,
    required this.at,
    this.endedAt,
  });
  final String id;
  final String chatId;
  final String callerId;
  final bool video;
  final DateTime at;
  final DateTime? endedAt;

  static OrbitCallEntry fromRow(Map<String, dynamic> r) => OrbitCallEntry(
        id: '${r['id']}',
        chatId: '${r['chat_id']}',
        callerId: '${r['caller']}',
        video: r['video'] == true,
        at: DateTime.tryParse('${r['created_at']}')?.toLocal() ?? DateTime.now(),
        endedAt: DateTime.tryParse('${r['ended_at'] ?? ''}')?.toLocal(),
      );
}

/// Member of an online chat.
class OrbitMember {
  OrbitMember({required this.id, required this.name, required this.role, this.lastReadAt, this.onlineAt});
  final String id;
  final String name;
  final String role;
  final DateTime? lastReadAt;
  final DateTime? onlineAt;
  bool get onlineNow => onlineAt != null && DateTime.now().toUtc().difference(onlineAt!.toUtc()).inMinutes < 3;
}

/// Online ORBIT NETWORK: real chats on Supabase (nx_chats / nx_chat_members / nx_messages / nx_message_stars),
/// real-time through Realtime postgres_changes. "Saved Orbit" stays on this device ([local]).
///
/// Offline fallback: when the network fails, the last server copy stays visible and outgoing messages are
/// kept in a local queue (shown as queued) that is flushed on the next successful refresh.
class SupabaseOrbitRepository implements OrbitRepository {
  SupabaseOrbitRepository(this.c, this.local, {required this.explorerId});

  final SupabaseClient c;
  final LocalOrbitRepository local;

  /// The offline identity used for Saved Orbit messages written before signing in.
  final String explorerId;

  String get me => c.auth.currentUser!.id;

  static const String kPending = 'orbit.pending.v1';

  final Map<String, OrbitChat> _chats = <String, OrbitChat>{};
  final Map<String, OrbitMessage?> _last = <String, OrbitMessage?>{};
  final Map<String, int> _unread = <String, int>{};
  final Map<String, List<OrbitMessage>> _msgs = <String, List<OrbitMessage>>{};
  final Map<String, List<OrbitMember>> _members = <String, List<OrbitMember>>{};
  final Set<String> _stars = <String>{};
  RealtimeChannel? _ch;

  bool _isLocal(String chatId) => chatId == kSavedOrbitId || !_chats.containsKey(chatId) && !_looksRemote(chatId);
  static final RegExp _uuid = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');
  bool _looksRemote(String id) => _uuid.hasMatch(id);

  // ------------------------------------------------------------------ mapping
  static DateTime _t(Object? v) => DateTime.tryParse('${v ?? ''}')?.toLocal() ?? DateTime.now();

  static OrbitChatKind _kind(String k) {
    switch (k) {
      case 'direct':
        return OrbitChatKind.direct;
      case 'channel':
        return OrbitChatKind.channel;
      default:
        return OrbitChatKind.group;
    }
  }

  static OrbitMessageKind _mkind(String k) {
    for (final OrbitMessageKind v in OrbitMessageKind.values) {
      if (v.name == k) return v;
    }
    return OrbitMessageKind.text;
  }

  OrbitMessage _msg(Map<String, dynamic> r, {List<OrbitMember>? members}) {
    final String author = '${r['author'] ?? 'system'}';
    final DateTime at = _t(r['created_at']);
    OrbitDelivery d = OrbitDelivery.delivered;
    if (author == me && members != null) {
      final bool read = members.any((OrbitMember m) => m.id != me && m.lastReadAt != null && !m.lastReadAt!.isBefore(at));
      d = read ? OrbitDelivery.read : OrbitDelivery.delivered;
    }
    return OrbitMessage(
      id: '${r['id']}',
      chatId: '${r['chat_id']}',
      authorId: r['author'] == null ? 'system' : author,
      authorName: '${r['author_name'] ?? ''}',
      kind: _mkind('${r['kind'] ?? 'text'}'),
      text: '${r['text'] ?? ''}',
      payload: r['payload'] is Map ? Map<String, dynamic>.from(r['payload'] as Map) : <String, dynamic>{},
      replyToId: r['reply_to'] as String?,
      createdAt: at,
      editedAt: r['edited_at'] == null ? null : _t(r['edited_at']),
      deleted: r['deleted'] == true,
      pinned: r['pinned'] == true,
      starred: _stars.contains('${r['id']}'),
      delivery: d,
    );
  }

  OrbitChat _chat(Map<String, dynamic> r) {
    final OrbitChatKind k = _kind('${r['kind']}');
    return OrbitChat(
      id: '${r['id']}',
      kind: k,
      name: k == OrbitChatKind.direct ? '${r['peer_name'] ?? 'Pilot'}' : '${r['name'] ?? ''}',
      description: '${r['description'] ?? ''}',
      badgeId: '${r['badge_id'] ?? ''}',
      createdAt: _t(r['created_at']),
      ownerId: '${r['owner']}',
      pinned: r['pinned'] == true,
      muted: r['muted'] == true,
      lastReadAt: r['last_read_at'] == null ? null : _t(r['last_read_at']),
      role: '${r['role'] ?? 'member'}',
      peerId: r['peer'] as String?,
      peerName: r['peer_name'] as String?,
      peerOnlineAt: r['peer_online'] == null ? null : DateTime.tryParse('${r['peer_online']}'),
      memberCount: (r['members'] as num?)?.toInt() ?? 1,
      online: true,
    );
  }

  OrbitMessage _fromLocal(OrbitMessage m) {
    if (m.authorId != explorerId) return m;
    return OrbitMessage.fromJson(m.toJson()..['authorId'] = me);
  }

  // ------------------------------------------------------------------ realtime
  /// Calls [onChange] with the chat id whenever a message / membership in one of my chats changes,
  /// and [onCall] for a call started by someone else in one of my chats.
  void listen({required void Function(String chatId) onChange, required void Function(Map<String, dynamic> call) onCall}) {
    stop();
    _ch = c
        .channel('nxorbit:$me')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'nx_messages',
          callback: (PostgresChangePayload p) {
            final Map<String, dynamic> r = p.newRecord.isNotEmpty ? p.newRecord : p.oldRecord;
            final String id = '${r['chat_id'] ?? ''}';
            if (id.isNotEmpty) onChange(id);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'nx_chat_members',
          callback: (PostgresChangePayload p) {
            final Map<String, dynamic> r = p.newRecord.isNotEmpty ? p.newRecord : p.oldRecord;
            onChange('${r['chat_id'] ?? ''}');
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'nx_calls',
          callback: (PostgresChangePayload p) {
            if ('${p.newRecord['caller']}' != me) onCall(p.newRecord);
          },
        )
        .subscribe();
  }

  void stop() {
    final RealtimeChannel? ch = _ch;
    if (ch != null) unawaited(c.removeChannel(ch));
    _ch = null;
  }

  // ------------------------------------------------------------------ pending queue
  List<Map<String, dynamic>> _pending() => (LocalStore.instance.getJsonList(kPending) ?? const <dynamic>[])
      .whereType<Map>()
      .map((Map e) => Map<String, dynamic>.from(e))
      .toList();

  Future<void> _flush() async {
    final List<Map<String, dynamic>> q = _pending();
    if (q.isEmpty) return;
    final List<Map<String, dynamic>> left = <Map<String, dynamic>>[];
    for (final Map<String, dynamic> m in q) {
      try {
        await c.rpc('nx_send_message', params: <String, dynamic>{
          'p_chat': m['chat'],
          'p_kind': m['kind'],
          'p_text': m['text'],
          'p_payload': m['payload'] ?? <String, dynamic>{},
          'p_reply_to': m['reply'],
        });
      } on PostgrestException {
        // rejected by the server (e.g. no longer a member) → drop it
      } catch (_) {
        left.add(m);
      }
    }
    await LocalStore.instance.setJson(kPending, left);
  }

  // ------------------------------------------------------------------ chats
  @override
  Future<List<OrbitChat>> chats({required String ownerId}) async {
    final List<OrbitChat> saved = await local.chats(ownerId: explorerId); // Saved Orbit + chats made offline
    try {
      await _flush();
      final List<dynamic> rows = await c.rpc('nx_my_chats');
      _chats.clear();
      for (final dynamic raw in rows) {
        final Map<String, dynamic> r = Map<String, dynamic>.from(raw as Map);
        final OrbitChat ch = _chat(r);
        _chats[ch.id] = ch;
        _unread[ch.id] = (r['unread'] as num?)?.toInt() ?? 0;
        _last[ch.id] = r['last'] is Map ? _msg(Map<String, dynamic>.from(r['last'] as Map)) : null;
      }
    } catch (_) {
      // offline: keep the last server copy
    }
    final List<OrbitChat> out = <OrbitChat>[...saved, ..._chats.values];
    DateTime act(OrbitChat x) => (x.isSaved ? null : _last[x.id]?.createdAt) ?? x.createdAt;
    out.sort((OrbitChat a, OrbitChat b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return act(b).compareTo(act(a));
    });
    return out;
  }

  @override
  Future<OrbitChat?> chat(String id) async => _isLocal(id) ? local.chat(id) : _chats[id];

  @override
  Future<OrbitChat> createChat({
    required OrbitChatKind kind,
    required String name,
    required String ownerId,
    required String ownerName,
    String description = '',
    String badgeId = '',
    List<String> members = const <String>[],
    bool isPublic = false,
  }) async {
    final dynamic id = await c.rpc('nx_create_chat', params: <String, dynamic>{
      'p_kind': kind == OrbitChatKind.channel ? 'channel' : 'group',
      'p_name': name,
      'p_description': description,
      'p_badge': badgeId,
      'p_members': members,
      'p_public': isPublic,
    });
    await chats(ownerId: ownerId);
    return _chats['$id'] ??
        OrbitChat(id: '$id', kind: kind, name: name, createdAt: DateTime.now(), ownerId: me, online: true, badgeId: badgeId);
  }

  /// Opens (or creates) the 1:1 chat with [userId]; returns its id.
  Future<String> openDirect(String userId) async {
    final dynamic id = await c.rpc('nx_open_direct', params: <String, dynamic>{'p_user': userId});
    await chats(ownerId: me);
    return '$id';
  }

  Future<int> addMembers(String chatId, List<String> users) async {
    final dynamic n = await c.rpc('nx_add_chat_members', params: <String, dynamic>{'p_chat': chatId, 'p_users': users});
    _members.remove(chatId);
    return (n as num?)?.toInt() ?? 0;
  }

  Future<void> setRole(String chatId, String userId, String role) async {
    await c.rpc('nx_set_chat_role', params: <String, dynamic>{'p_chat': chatId, 'p_user': userId, 'p_role': role});
    _members.remove(chatId);
  }

  Future<List<OrbitMember>> members(String chatId, {bool fresh = false}) async {
    if (!fresh && _members[chatId] != null) return _members[chatId]!;
    final List<dynamic> rows = await c.from('nx_chat_members').select('user_id, role, last_read_at').eq('chat_id', chatId);
    final List<String> ids = rows.map((dynamic r) => '${(r as Map)['user_id']}').toList();
    final List<dynamic> profs =
        ids.isEmpty ? <dynamic>[] : await c.from('profiles').select('id, username, online_at').inFilter('id', ids);
    final Map<String, Map<dynamic, dynamic>> byId = <String, Map<dynamic, dynamic>>{
      for (final dynamic p in profs) '${(p as Map)['id']}': p,
    };
    final List<OrbitMember> out = rows.map((dynamic raw) {
      final Map<dynamic, dynamic> r = raw as Map;
      final Map<dynamic, dynamic>? p = byId['${r['user_id']}'];
      return OrbitMember(
        id: '${r['user_id']}',
        name: '${p?['username'] ?? 'Pilot'}',
        role: '${r['role']}',
        lastReadAt: r['last_read_at'] == null ? null : _t(r['last_read_at']),
        onlineAt: DateTime.tryParse('${p?['online_at'] ?? ''}'),
      );
    }).toList()
      ..sort((OrbitMember a, OrbitMember b) => _rank(b.role).compareTo(_rank(a.role)));
    _members[chatId] = out;
    return out;
  }

  static int _rank(String r) => r == 'owner' ? 2 : (r == 'admin' ? 1 : 0);

  @override
  Future<void> updateChat(OrbitChat chat) async {
    if (!chat.online) return local.updateChat(chat);
    _chats[chat.id] = chat;
    await c
        .from('nx_chat_members')
        .update(<String, dynamic>{'pinned': chat.pinned, 'muted': chat.muted})
        .eq('chat_id', chat.id)
        .eq('user_id', me);
    if (!chat.isDirect && chat.isAdmin) {
      await c.from('nx_chats').update(
          <String, dynamic>{'name': chat.name, 'description': chat.description, 'badge_id': chat.badgeId}).eq('id', chat.id);
    }
  }

  /// Owner deletes a group/channel for everyone; anyone else (and direct chats) just leaves it.
  @override
  Future<bool> deleteChat(String id) async {
    if (id == kSavedOrbitId) return false;
    if (_isLocal(id)) return local.deleteChat(id);
    final OrbitChat? ch = _chats[id];
    if (ch != null && ch.role == 'owner' && !ch.isDirect) {
      await c.from('nx_chats').delete().eq('id', id);
    } else {
      await c.rpc('nx_leave_chat', params: <String, dynamic>{'p_chat': id});
    }
    _chats.remove(id);
    _msgs.remove(id);
    return true;
  }

  // ------------------------------------------------------------------ messages
  @override
  Future<List<OrbitMessage>> messages(String chatId) async {
    if (_isLocal(chatId)) return (await local.messages(chatId)).map(_fromLocal).toList();
    try {
      final List<OrbitMember> mem = await members(chatId, fresh: true);
      final List<dynamic> st = await c.from('nx_message_stars').select('message_id').eq('user_id', me);
      _stars
        ..clear()
        ..addAll(st.map((dynamic r) => '${(r as Map)['message_id']}'));
      final List<dynamic> rows =
          await c.from('nx_messages').select().eq('chat_id', chatId).order('created_at', ascending: false).limit(400);
      final List<OrbitMessage> list =
          rows.reversed.map((dynamic r) => _msg(Map<String, dynamic>.from(r as Map), members: mem)).toList();
      for (final Map<String, dynamic> p in _pending().where((Map<String, dynamic> p) => p['chat'] == chatId)) {
        list.add(OrbitMessage(
          id: '${p['id']}',
          chatId: chatId,
          authorId: me,
          authorName: '${p['name'] ?? ''}',
          kind: _mkind('${p['kind']}'),
          text: '${p['text'] ?? ''}',
          payload: p['payload'] is Map ? Map<String, dynamic>.from(p['payload'] as Map) : null,
          createdAt: DateTime.fromMillisecondsSinceEpoch((p['at'] as num?)?.toInt() ?? 0),
          delivery: OrbitDelivery.queued,
        ));
      }
      _msgs[chatId] = list;
    } catch (_) {
      // offline → last copy
    }
    return List<OrbitMessage>.from(_msgs[chatId] ?? const <OrbitMessage>[]);
  }

  @override
  Future<OrbitMessage?> lastMessage(String chatId) async {
    if (_isLocal(chatId)) {
      final OrbitMessage? m = await local.lastMessage(chatId);
      return m == null ? null : _fromLocal(m);
    }
    return _last[chatId];
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
    if (_isLocal(chatId)) {
      return _fromLocal(await local.send(
        chatId: chatId,
        authorId: explorerId,
        authorName: authorName,
        kind: kind,
        text: text,
        payload: payload,
        replyToId: replyToId,
      ));
    }
    try {
      final dynamic r = await c.rpc('nx_send_message', params: <String, dynamic>{
        'p_chat': chatId,
        'p_kind': kind.name,
        'p_text': text,
        'p_payload': payload ?? <String, dynamic>{},
        'p_reply_to': replyToId,
      });
      final OrbitMessage m = _msg(Map<String, dynamic>.from(r as Map))..delivery = OrbitDelivery.sent;
      _msgs[chatId] = <OrbitMessage>[...?_msgs[chatId], m];
      _last[chatId] = m;
      return m;
    } on PostgrestException {
      rethrow; // the server refused (not a member / channel admins only)
    } catch (_) {
      // network: queue it
      final DateTime now = DateTime.now();
      final Map<String, dynamic> p = <String, dynamic>{
        'id': 'pending_${now.microsecondsSinceEpoch}',
        'chat': chatId,
        'kind': kind.name,
        'text': text.trim(),
        'payload': payload ?? <String, dynamic>{},
        'reply': replyToId,
        'name': authorName,
        'at': now.millisecondsSinceEpoch,
      };
      await LocalStore.instance.setJson(kPending, <Map<String, dynamic>>[..._pending(), p]);
      final OrbitMessage m = OrbitMessage(
        id: '${p['id']}',
        chatId: chatId,
        authorId: me,
        authorName: authorName,
        kind: kind,
        text: text.trim(),
        payload: payload,
        createdAt: now,
        delivery: OrbitDelivery.queued,
      );
      _msgs[chatId] = <OrbitMessage>[...?_msgs[chatId], m];
      return m;
    }
  }

  @override
  Future<bool> editMessage(String chatId, String messageId, String text) async {
    if (_isLocal(chatId)) return local.editMessage(chatId, messageId, text);
    final dynamic ok = await c.rpc('nx_edit_message', params: <String, dynamic>{'p_id': messageId, 'p_text': text});
    return ok == true;
  }

  @override
  Future<void> deleteMessage(String chatId, String messageId) async {
    if (_isLocal(chatId)) return local.deleteMessage(chatId, messageId);
    if (messageId.startsWith('pending_')) {
      await LocalStore.instance.setJson(kPending, _pending().where((Map<String, dynamic> p) => p['id'] != messageId).toList());
      return;
    }
    await c.rpc('nx_delete_message', params: <String, dynamic>{'p_id': messageId});
  }

  @override
  Future<void> togglePin(String chatId, String messageId) async {
    if (_isLocal(chatId)) return local.togglePin(chatId, messageId);
    await c.rpc('nx_toggle_pin_message', params: <String, dynamic>{'p_id': messageId});
  }

  @override
  Future<void> toggleStar(String chatId, String messageId) async {
    if (_isLocal(chatId)) return local.toggleStar(chatId, messageId);
    if (_stars.remove(messageId)) {
      await c.from('nx_message_stars').delete().eq('user_id', me).eq('message_id', messageId);
    } else {
      _stars.add(messageId);
      await c.from('nx_message_stars').insert(<String, dynamic>{'user_id': me, 'message_id': messageId});
    }
  }

  @override
  Future<void> markRead(String chatId) async {
    if (_isLocal(chatId)) return local.markRead(chatId);
    _unread[chatId] = 0;
    try {
      await c.rpc('nx_mark_read', params: <String, dynamic>{'p_chat': chatId});
    } catch (_) {}
  }

  @override
  Future<int> unreadCount(String chatId, String myId) async =>
      _isLocal(chatId) ? local.unreadCount(chatId, explorerId) : (_unread[chatId] ?? 0);

  @override
  Future<List<OrbitMessage>> search(String query) async {
    final List<OrbitMessage> out = (await local.search(query)).map(_fromLocal).toList();
    final String q = query.trim().replaceAll('%', '').replaceAll(',', ' ');
    if (q.length >= 2) {
      try {
        final List<dynamic> rows = await c
            .from('nx_messages')
            .select()
            .eq('deleted', false)
            .neq('kind', 'system')
            .ilike('text', '%$q%')
            .order('created_at', ascending: false)
            .limit(60);
        out.addAll(rows.map((dynamic r) => _msg(Map<String, dynamic>.from(r as Map))));
      } catch (_) {}
    }
    out.sort((OrbitMessage a, OrbitMessage b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  @override
  Future<List<OrbitMessage>> starred() async {
    final List<OrbitMessage> out = (await local.starred()).map(_fromLocal).toList();
    try {
      final List<dynamic> st = await c.from('nx_message_stars').select('message_id').eq('user_id', me);
      final List<String> ids = st.map((dynamic r) => '${(r as Map)['message_id']}').toList();
      _stars
        ..clear()
        ..addAll(ids);
      if (ids.isNotEmpty) {
        final List<dynamic> rows = await c.from('nx_messages').select().inFilter('id', ids).eq('deleted', false);
        out.addAll(rows.map((dynamic r) => _msg(Map<String, dynamic>.from(r as Map))));
      }
    } catch (_) {}
    out.sort((OrbitMessage a, OrbitMessage b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  // ------------------------------------------------------------------ calls
  Future<String> startCall(String chatId, {required bool video}) async =>
      '${await c.rpc('nx_start_call', params: <String, dynamic>{'p_chat': chatId, 'p_video': video})}';

  Future<void> endCall(String callId) async {
    try {
      await c.rpc('nx_end_call', params: <String, dynamic>{'p_call': callId});
    } catch (_) {}
  }

  Future<List<OrbitCallEntry>> callHistory() async {
    final List<dynamic> rows = await c.from('nx_calls').select().order('created_at', ascending: false).limit(60);
    return rows.map((dynamic r) => OrbitCallEntry.fromRow(Map<String, dynamic>.from(r as Map))).toList();
  }
}
