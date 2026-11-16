import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dart:async';

import '../../../core/online/online_service.dart';
import '../../../core/profile/profile_service.dart';
import '../../../core/storage/local_store.dart';
import '../data/orbit_repository.dart';
import '../data/supabase_orbit_repository.dart';
import '../data/orbit_shared_inbox.dart';
import '../models/orbit_models.dart';

/// Online (signed in to Supabase): real chats on the server; otherwise the device-only repository.
final orbitRepositoryProvider = Provider<OrbitRepository>((ref) {
  final OnlineService o = ref.watch(onlineProvider);
  final LocalOrbitRepository local = LocalOrbitRepository(LocalStore.instance);
  final client = o.client;
  if (o.isOnline && client != null) {
    return SupabaseOrbitRepository(client, local, explorerId: ref.read(profileProvider).explorerId);
  }
  return local;
});

final orbitControllerProvider = ChangeNotifierProvider<OrbitController>((ref) {
  final OrbitRepository repo = ref.watch(orbitRepositoryProvider);
  final OnlineService o = ref.read(onlineProvider);
  return OrbitController(
    repo,
    OrbitSharedInbox(LocalStore.instance),
    ownerId:
        repo is SupabaseOrbitRepository ? (o.uid ?? ref.read(profileProvider).explorerId) : ref.read(profileProvider).explorerId,
  );
});

class OrbitChatSummary {
  OrbitChatSummary(this.chat, this.last, this.unread);
  final OrbitChat chat;
  final OrbitMessage? last;
  final int unread;
}

/// XP rules for messages: small, capped per day so chatting can't be farmed.
class OrbitXpRules {
  OrbitXpRules._();
  static const int xpPerMessage = 2;
  static const int dailyRewardedMessages = 30;
  static const String kDay = 'orbit.xp_day';
  static const String kCount = 'orbit.xp_count';

  /// Returns true (and consumes a slot) if this message still earns XP today.
  static Future<bool> consumeSlot(LocalStore store, DateTime now) async {
    final day = '${now.year}-${now.month}-${now.day}';
    var count = store.getInt(kCount) ?? 0;
    if (store.getString(kDay) != day) {
      count = 0;
      await store.setString(kDay, day);
    }
    if (count >= dailyRewardedMessages) return false;
    await store.setInt(kCount, count + 1);
    return true;
  }
}

class OrbitController extends ChangeNotifier {
  OrbitController(this.repo, this.inbox, {required this.ownerId}) {
    final OrbitRepository r = repo;
    if (r is SupabaseOrbitRepository) {
      r.listen(onChange: _onRemoteChange, onCall: (_) {});
    }
    refresh();
  }

  /// The server-backed repository when signed in (real members, calls), else null.
  SupabaseOrbitRepository? get online => repo is SupabaseOrbitRepository ? repo as SupabaseOrbitRepository : null;
  bool get isOnline => online != null;

  Timer? _debounce;
  final Set<String> _dirty = <String>{};

  void _onRemoteChange(String chatId) {
    if (chatId.isNotEmpty) _dirty.add(chatId);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      if (_disposed) return;
      final List<String> open = _dirty.where(_messages.containsKey).toList();
      _dirty.clear();
      for (final String id in open) {
        await repo.markRead(id);
      }
      await refresh();
    });
  }

  /// Opens (or creates) the 1:1 chat with a real user. Online only.
  Future<String?> openDirect(String userId) async {
    final SupabaseOrbitRepository? r = online;
    if (r == null) return null;
    final String id = await r.openDirect(userId);
    await refresh();
    return id;
  }

  Future<int> addMembers(String chatId, List<String> users) async {
    final SupabaseOrbitRepository? r = online;
    if (r == null || users.isEmpty) return 0;
    final int n = await r.addMembers(chatId, users);
    await refresh();
    return n;
  }

  Future<List<OrbitMember>> members(String chatId) async => await online?.members(chatId, fresh: true) ?? <OrbitMember>[];

  final OrbitRepository repo;
  final OrbitSharedInbox inbox;
  final String ownerId;

  bool loading = true;
  bool _disposed = false;
  List<OrbitChatSummary> summaries = <OrbitChatSummary>[];
  List<SharedItem> inboxItems = <SharedItem>[];
  final Map<String, List<OrbitMessage>> _messages = <String, List<OrbitMessage>>{};

  int get totalUnread => summaries.fold<int>(0, (int a, OrbitChatSummary s) => a + s.unread);

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    online?.stop();
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  OrbitChat? chatById(String id) {
    for (final s in summaries) {
      if (s.chat.id == id) return s.chat;
    }
    return null;
  }

  List<OrbitMessage> messagesOf(String chatId) => _messages[chatId] ?? const <OrbitMessage>[];

  OrbitMessage? messageById(String chatId, String? id) {
    if (id == null) return null;
    for (final m in messagesOf(chatId)) {
      if (m.id == id) return m;
    }
    return null;
  }

  Future<void> refresh() async {
    final chats = await repo.chats(ownerId: ownerId);
    final out = <OrbitChatSummary>[];
    for (final c in chats) {
      out.add(OrbitChatSummary(c, await repo.lastMessage(c.id), await repo.unreadCount(c.id, ownerId)));
    }
    summaries = out;
    inboxItems = inbox.read();
    for (final id in _messages.keys.toList()) {
      _messages[id] = await repo.messages(id);
    }
    loading = false;
    _notify();
  }

  Future<void> openChat(String chatId) async {
    _messages[chatId] = await repo.messages(chatId);
    await repo.markRead(chatId);
    await refresh();
  }

  void closeChat(String chatId) {
    _messages.remove(chatId);
  }

  Future<OrbitMessage?> send(
    String chatId, {
    required String authorName,
    OrbitMessageKind kind = OrbitMessageKind.text,
    String text = '',
    Map<String, dynamic>? payload,
    String? replyToId,
  }) async {
    if (kind == OrbitMessageKind.text && text.trim().isEmpty) return null;
    final OrbitMessage m;
    try {
      m = await repo.send(
        chatId: chatId,
        authorId: ownerId,
        authorName: authorName,
        kind: kind,
        text: text,
        payload: payload,
        replyToId: replyToId,
      );
    } catch (e) {
      debugPrint('orbit send refused: $e');
      await refresh();
      return null;
    }
    await refresh();
    return m;
  }

  /// Bumps 'orbit.sent' and awards capped XP. Returns the award outcome.
  Future<AwardOutcome> reward(ProfileService profile) async {
    profile.bump('orbit.sent');
    final bool earns = await OrbitXpRules.consumeSlot(LocalStore.instance, DateTime.now());
    final sent = profile.counter('orbit.sent');
    if (sent == 1 || sent % 25 == 0) {
      profile.logActivity('orbit', '$sent پیام در Orbit Network', '$sent messages in Orbit Network');
    }
    return profile.award('orbit.message', xp: earns ? OrbitXpRules.xpPerMessage : 0);
  }

  Future<bool> edit(String chatId, String id, String text) async {
    final ok = await repo.editMessage(chatId, id, text);
    await refresh();
    return ok;
  }

  Future<void> delete(String chatId, String id) async {
    await repo.deleteMessage(chatId, id);
    await refresh();
  }

  Future<void> togglePin(String chatId, String id) async {
    await repo.togglePin(chatId, id);
    await refresh();
  }

  Future<void> toggleStar(String chatId, String id) async {
    await repo.toggleStar(chatId, id);
    await refresh();
  }

  Future<OrbitChat> createChat({
    required OrbitChatKind kind,
    required String name,
    required String ownerName,
    String description = '',
    String badgeId = '',
    List<String> members = const <String>[],
  }) async {
    final OrbitRepository r = repo;
    final c = r is SupabaseOrbitRepository
        ? await r.createChat(
            kind: kind,
            name: name,
            ownerId: ownerId,
            ownerName: ownerName,
            description: description,
            badgeId: badgeId,
            members: members,
          )
        : await repo.createChat(
            kind: kind,
            name: name,
            ownerId: ownerId,
            ownerName: ownerName,
            description: description,
            badgeId: badgeId,
          );
    await refresh();
    return c;
  }

  Future<void> updateChat(OrbitChat chat) async {
    await repo.updateChat(chat);
    await refresh();
  }

  Future<void> deleteChat(String id) async {
    await repo.deleteChat(id);
    _messages.remove(id);
    await refresh();
  }

  Future<List<OrbitMessage>> search(String q) => repo.search(q);
  Future<List<OrbitMessage>> starred() => repo.starred();

  /// Delivers a shared item into a chat as a rich card and removes it from the inbox.
  Future<void> deliverShared(SharedItem item, String chatId, {required String authorName}) async {
    await repo.send(
      chatId: chatId,
      authorId: ownerId,
      authorName: authorName,
      kind: item.type == SharedItem.gameInvite ? OrbitMessageKind.invite : OrbitMessageKind.shared,
      text: item.text,
      payload:
          item.type == SharedItem.gameInvite ? <String, dynamic>{'gameId': item.gameId ?? '', 'text': item.text} : item.toJson(),
    );
    await inbox.remove(item.key);
    await refresh();
  }

  Future<void> dismissShared(SharedItem item) async {
    await inbox.remove(item.key);
    await refresh();
  }
}
