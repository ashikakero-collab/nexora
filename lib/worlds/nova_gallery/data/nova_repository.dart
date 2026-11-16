import 'dart:math';

import '../../../core/storage/local_store.dart';
import '../models/nova_models.dart';
import 'nova_seed.dart';

/// Data access for NOVA GALLERY. The UI only talks to this interface, so an
/// online (Supabase) implementation can be swapped in later.
abstract class NovaRepository {
  /// All visible posts, newest first.
  Future<List<NovaPost>> feed();
  Future<NovaPost?> post(String id);
  Future<NovaPost> createPost({
    required String authorId,
    required String authorName,
    required String text,
    NovaVisual visual = NovaVisual.none,
    bool motion = false,
  });
  Future<void> updatePost(String id, {required String text, required NovaVisual visual, required bool motion});
  Future<void> deletePost(String id);

  /// Returns the new liked state for [userId].
  Future<bool> toggleLike(String postId, String userId);
  Future<NovaComment?> addComment(String postId, {required String authorId, required String authorName, required String text});
  Future<void> deleteComment(String postId, String commentId);

  Future<Set<String>> savedIds();
  /// Returns the new saved state.
  Future<bool> toggleSave(String postId);

  /// Active (non-expired) stories, newest first. Expired ones are purged.
  Future<List<NovaStory>> activeStories();
  Future<NovaStory> createStory({required String authorId, required String authorName, required String text, required int gradient});
  Future<void> markStoryViewed(String id);
  Future<void> deleteStory(String id);

  Future<List<NovaNotification>> notifications();
  Future<void> addNotification({required String kind, required String fa, required String en, String? postId});
  Future<void> markAllNotificationsRead();
  Future<void> clearNotifications();

  /// Search by hashtag ('#tag'), mention ('@name') or free text.
  Future<List<NovaPost>> search(String query);

  /// Hashtag -> number of posts, most used first.
  Future<List<MapEntry<String, int>>> trendingHashtags({int limit = 12});
}

/// Offline implementation backed by [LocalStore].
class LocalNovaRepository implements NovaRepository {
  LocalNovaRepository(this._store, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final LocalStore _store;
  final DateTime Function() _clock;
  final Random _rng = Random();

  static const String kPosts = 'nova.posts.v1';
  static const String kSaved = 'nova.saved.v1';
  static const String kStories = 'nova.stories.v1';
  static const String kNotifs = 'nova.notifs.v1';
  static const String kSeeded = 'nova.seeded.v1';

  List<NovaPost>? _posts;

  String _id(String prefix) => '${prefix}_${_clock().microsecondsSinceEpoch}_${_rng.nextInt(999999)}';

  Future<void> _ensureSeeded() async {
    if (_store.getBool(kSeeded) == true) return;
    final now = _clock();
    final existing = _readPosts();
    final seed = buildOfficialSeed(now);
    final ids = existing.map((NovaPost p) => p.id).toSet();
    for (final p in seed) {
      if (!ids.contains(p.id)) existing.add(p);
    }
    _posts = existing;
    await _writePosts();
    final notifs = _readNotifs()..insert(0, buildWelcomeNotification(now));
    await _writeNotifs(notifs);
    await _store.setBool(kSeeded, true);
  }

  List<NovaPost> _readPosts() {
    final cached = _posts;
    if (cached != null) return cached;
    final raw = _store.getJsonList(kPosts) ?? const <dynamic>[];
    final list = raw
        .whereType<Map>()
        .map((Map e) => NovaPost.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    _posts = list;
    return list;
  }

  Future<void> _writePosts() async {
    final list = _readPosts();
    await _store.setJson(kPosts, list.map((NovaPost p) => p.toJson()).toList());
  }

  NovaPost? _find(String id) {
    for (final p in _readPosts()) {
      if (p.id == id) return p;
    }
    return null;
  }

  List<NovaPost> _sorted() {
    final list = List<NovaPost>.from(_readPosts());
    list.sort((NovaPost a, NovaPost b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  @override
  Future<List<NovaPost>> feed() async {
    await _ensureSeeded();
    return _sorted();
  }

  @override
  Future<NovaPost?> post(String id) async {
    await _ensureSeeded();
    return _find(id);
  }

  @override
  Future<NovaPost> createPost({
    required String authorId,
    required String authorName,
    required String text,
    NovaVisual visual = NovaVisual.none,
    bool motion = false,
  }) async {
    await _ensureSeeded();
    final p = NovaPost(
      id: _id('post'),
      authorId: authorId,
      authorName: authorName,
      text: text.trim(),
      visual: visual,
      motion: motion,
      createdAt: _clock(),
    );
    _readPosts().add(p);
    await _writePosts();
    await addNotification(
      kind: NovaNotifKind.post,
      fa: 'پست تو منتشر شد و روی دستگاهت ذخیره شد.',
      en: 'Your post was published and saved on your device.',
      postId: p.id,
    );
    return p;
  }

  @override
  Future<void> updatePost(String id, {required String text, required NovaVisual visual, required bool motion}) async {
    final p = _find(id);
    if (p == null || p.official) return;
    p.text = text.trim();
    p.visual = visual;
    p.motion = motion;
    p.editedAt = _clock();
    await _writePosts();
  }

  @override
  Future<void> deletePost(String id) async {
    final list = _readPosts();
    list.removeWhere((NovaPost p) => p.id == id && !p.official);
    await _writePosts();
    final saved = await savedIds();
    if (saved.remove(id)) await _store.setJson(kSaved, saved.toList());
  }

  @override
  Future<bool> toggleLike(String postId, String userId) async {
    final p = _find(postId);
    if (p == null) return false;
    final bool nowLiked;
    if (p.likedBy.contains(userId)) {
      p.likedBy.remove(userId);
      nowLiked = false;
    } else {
      p.likedBy.add(userId);
      nowLiked = true;
    }
    await _writePosts();
    if (nowLiked && !p.official) {
      await addNotification(
        kind: NovaNotifKind.like,
        fa: 'پست تو یک لایک گرفت (مجموع ${p.likeCount}).',
        en: 'Your post got a like (${p.likeCount} total).',
        postId: p.id,
      );
    }
    return nowLiked;
  }

  @override
  Future<NovaComment?> addComment(String postId, {required String authorId, required String authorName, required String text}) async {
    final p = _find(postId);
    final t = text.trim();
    if (p == null || t.isEmpty) return null;
    final c = NovaComment(id: _id('cmt'), authorId: authorId, authorName: authorName, text: t, at: _clock());
    p.comments.add(c);
    await _writePosts();
    if (!p.official) {
      final preview = t.length > 40 ? '${t.substring(0, 40)}…' : t;
      await addNotification(
        kind: NovaNotifKind.comment,
        fa: 'دیدگاه تازه روی پستت: «$preview»',
        en: 'New comment on your post: "$preview"',
        postId: p.id,
      );
    }
    return c;
  }

  @override
  Future<void> deleteComment(String postId, String commentId) async {
    final p = _find(postId);
    if (p == null) return;
    p.comments.removeWhere((NovaComment c) => c.id == commentId);
    await _writePosts();
  }

  @override
  Future<Set<String>> savedIds() async =>
      (_store.getJsonList(kSaved) ?? const <dynamic>[]).map((dynamic e) => '$e').toSet();

  @override
  Future<bool> toggleSave(String postId) async {
    final s = await savedIds();
    final bool saved;
    if (s.contains(postId)) {
      s.remove(postId);
      saved = false;
    } else {
      s.add(postId);
      saved = true;
    }
    await _store.setJson(kSaved, s.toList());
    return saved;
  }

  List<NovaStory> _readStories() => (_store.getJsonList(kStories) ?? const <dynamic>[])
      .whereType<Map>()
      .map((Map e) => NovaStory.fromJson(Map<String, dynamic>.from(e)))
      .toList();

  Future<void> _writeStories(List<NovaStory> list) =>
      _store.setJson(kStories, list.map((NovaStory s) => s.toJson()).toList());

  @override
  Future<List<NovaStory>> activeStories() async {
    final now = _clock();
    final all = _readStories();
    final active = all.where((NovaStory s) => s.isActive(now)).toList();
    if (active.length != all.length) await _writeStories(active);
    active.sort((NovaStory a, NovaStory b) => b.createdAt.compareTo(a.createdAt));
    return active;
  }

  @override
  Future<NovaStory> createStory({required String authorId, required String authorName, required String text, required int gradient}) async {
    final s = NovaStory(
      id: _id('story'),
      authorId: authorId,
      authorName: authorName,
      text: text.trim(),
      gradient: gradient,
      createdAt: _clock(),
    );
    final list = await activeStories();
    list.add(s);
    await _writeStories(list);
    await addNotification(
      kind: NovaNotifKind.story,
      fa: 'استوری‌ات تا ۲۴ ساعت دیده می‌شود.',
      en: 'Your story is live for 24 hours.',
    );
    return s;
  }

  @override
  Future<void> markStoryViewed(String id) async {
    final list = _readStories();
    var changed = false;
    for (final s in list) {
      if (s.id == id && !s.viewed) {
        s.viewed = true;
        changed = true;
      }
    }
    if (changed) await _writeStories(list);
  }

  @override
  Future<void> deleteStory(String id) async {
    final list = _readStories()..removeWhere((NovaStory s) => s.id == id);
    await _writeStories(list);
  }

  List<NovaNotification> _readNotifs() => (_store.getJsonList(kNotifs) ?? const <dynamic>[])
      .whereType<Map>()
      .map((Map e) => NovaNotification.fromJson(Map<String, dynamic>.from(e)))
      .toList();

  Future<void> _writeNotifs(List<NovaNotification> list) =>
      _store.setJson(kNotifs, list.take(150).map((NovaNotification n) => n.toJson()).toList());

  @override
  Future<List<NovaNotification>> notifications() async {
    await _ensureSeeded();
    final list = _readNotifs();
    list.sort((NovaNotification a, NovaNotification b) => b.at.compareTo(a.at));
    return list;
  }

  @override
  Future<void> addNotification({required String kind, required String fa, required String en, String? postId}) async {
    final list = _readNotifs();
    list.insert(0, NovaNotification(id: _id('ntf'), kind: kind, textFa: fa, textEn: en, at: _clock(), postId: postId));
    await _writeNotifs(list);
  }

  @override
  Future<void> markAllNotificationsRead() async {
    final list = _readNotifs();
    for (final n in list) {
      n.read = true;
    }
    await _writeNotifs(list);
  }

  @override
  Future<void> clearNotifications() => _writeNotifs(<NovaNotification>[]);

  @override
  Future<List<NovaPost>> search(String query) async {
    await _ensureSeeded();
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return _sorted();
    if (q.startsWith('#') && q.length > 1) {
      final tag = q.substring(1);
      return _sorted().where((NovaPost p) => p.hashtags.contains(tag)).toList();
    }
    if (q.startsWith('@') && q.length > 1) {
      final m = q.substring(1);
      return _sorted()
          .where((NovaPost p) => p.mentions.contains(m) || p.authorName.toLowerCase().contains(m))
          .toList();
    }
    return _sorted()
        .where((NovaPost p) =>
            p.text.toLowerCase().contains(q) ||
            (p.textEn ?? '').toLowerCase().contains(q) ||
            p.authorName.toLowerCase().contains(q))
        .toList();
  }

  @override
  Future<List<MapEntry<String, int>>> trendingHashtags({int limit = 12}) async {
    await _ensureSeeded();
    final counts = <String, int>{};
    for (final p in _readPosts()) {
      for (final t in p.hashtags) {
        counts[t] = (counts[t] ?? 0) + 1;
      }
    }
    final list = counts.entries.toList()
      ..sort((MapEntry<String, int> a, MapEntry<String, int> b) => b.value.compareTo(a.value));
    return list.take(limit).toList();
  }
}
