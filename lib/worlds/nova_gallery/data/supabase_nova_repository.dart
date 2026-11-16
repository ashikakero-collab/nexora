import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/nova_models.dart';
import 'nova_repository.dart';

/// Online NOVA GALLERY on Supabase: nx_posts (posts + 24 h stories), nx_post_likes, nx_post_comments,
/// nx_post_saves, nx_story_views, nx_notifications; photos in the Storage bucket `nx-media` (each user writes
/// only under `<uid>/`). Only real posts by real accounts are shown — the device-only welcome seed is not.
///
/// The UI identifies "me" by the explorer id, so my auth uid is mapped to [explorerId] in everything returned
/// (author, likes, comments) and back again on the way in. Network errors fall back to the last server copy.
class SupabaseNovaRepository implements NovaRepository {
  SupabaseNovaRepository(this.c, this.local, {required this.explorerId});

  final SupabaseClient c;
  final LocalNovaRepository local;
  final String explorerId;

  String get me => c.auth.currentUser!.id;
  String _out(String uid) => uid == me ? explorerId : uid;

  static const String bucket = 'nx-media';
  static const String _cols =
      'id, author, kind, text, visual, motion, hashtags, like_count, comment_count, created_at, edited_at, expires_at';

  List<NovaPost> _feed = <NovaPost>[];
  final Map<String, String> _names = <String, String>{};

  static DateTime _t(Object? v) => DateTime.tryParse('${v ?? ''}')?.toLocal() ?? DateTime.now();

  Future<void> _loadNames(Iterable<String> ids) async {
    final List<String> need = ids.where((String i) => !_names.containsKey(i)).toSet().toList();
    if (need.isEmpty) return;
    final List<dynamic> rows = await c.from('profiles').select('id, username').inFilter('id', need);
    for (final dynamic r in rows) {
      final Map<dynamic, dynamic> m = r as Map;
      _names['${m['id']}'] = '${m['username'] ?? 'Pilot'}';
    }
  }

  String _name(String uid) => _names[uid] ?? 'Pilot';

  /// Builds full posts (real likers + comments) from nx_posts rows.
  Future<List<NovaPost>> _hydrate(List<dynamic> rows) async {
    final List<Map<String, dynamic>> posts = rows.map((dynamic r) => Map<String, dynamic>.from(r as Map)).toList();
    if (posts.isEmpty) return <NovaPost>[];
    final List<String> ids = posts.map((Map<String, dynamic> p) => '${p['id']}').toList();
    final List<dynamic> likes = await c.from('nx_post_likes').select('post_id, user_id').inFilter('post_id', ids);
    final List<dynamic> comments = await c
        .from('nx_post_comments')
        .select('id, post_id, author, text, created_at')
        .inFilter('post_id', ids)
        .order('created_at')
        .limit(1000);
    await _loadNames(<String>[
      ...posts.map((Map<String, dynamic> p) => '${p['author']}'),
      ...comments.map((dynamic r) => '${(r as Map)['author']}'),
    ]);
    final Map<String, Set<String>> likedBy = <String, Set<String>>{};
    for (final dynamic r in likes) {
      final Map<dynamic, dynamic> m = r as Map;
      (likedBy['${m['post_id']}'] ??= <String>{}).add(_out('${m['user_id']}'));
    }
    final Map<String, List<NovaComment>> cmts = <String, List<NovaComment>>{};
    for (final dynamic r in comments) {
      final Map<dynamic, dynamic> m = r as Map;
      (cmts['${m['post_id']}'] ??= <NovaComment>[]).add(NovaComment(
        id: '${m['id']}',
        authorId: _out('${m['author']}'),
        authorName: _name('${m['author']}'),
        text: '${m['text']}',
        at: _t(m['created_at']),
      ));
    }
    return posts.map((Map<String, dynamic> p) {
      final String id = '${p['id']}';
      return NovaPost(
        id: id,
        authorId: _out('${p['author']}'),
        authorName: _name('${p['author']}'),
        text: '${p['text'] ?? ''}',
        createdAt: _t(p['created_at']),
        visual: NovaVisual.fromJson(p['visual']),
        motion: p['motion'] == true,
        editedAt: p['edited_at'] == null ? null : _t(p['edited_at']),
        likedBy: likedBy[id],
        comments: cmts[id],
      );
    }).toList();
  }

  @override
  Future<List<NovaPost>> feed() async {
    try {
      final List<dynamic> rows =
          await c.from('nx_posts').select(_cols).eq('kind', 'post').order('created_at', ascending: false).limit(120);
      _feed = await _hydrate(rows);
    } catch (_) {}
    return List<NovaPost>.from(_feed);
  }

  @override
  Future<NovaPost?> post(String id) async {
    try {
      final List<dynamic> rows = await c.from('nx_posts').select(_cols).eq('id', id).limit(1);
      final List<NovaPost> l = await _hydrate(rows);
      return l.isEmpty ? null : l.first;
    } catch (_) {
      for (final NovaPost p in _feed) {
        if (p.id == id) return p;
      }
      return null;
    }
  }

  @override
  Future<NovaPost> createPost({
    required String authorId,
    required String authorName,
    required String text,
    NovaVisual visual = NovaVisual.none,
    bool motion = false,
  }) async {
    final dynamic r = await c
        .from('nx_posts')
        .insert(<String, dynamic>{'author': me, 'kind': 'post', 'text': text.trim(), 'visual': visual.toJson(), 'motion': motion})
        .select(_cols)
        .single();
    _names[me] = authorName;
    final List<NovaPost> l = await _hydrate(<dynamic>[r]);
    return l.first;
  }

  @override
  Future<void> updatePost(String id, {required String text, required NovaVisual visual, required bool motion}) async {
    await c
        .from('nx_posts')
        .update(<String, dynamic>{'text': text.trim(), 'visual': visual.toJson(), 'motion': motion}).eq('id', id);
  }

  @override
  Future<void> deletePost(String id) async {
    NovaVisual? v;
    for (final NovaPost p in _feed) {
      if (p.id == id) v = p.visual;
    }
    await c.from('nx_posts').delete().eq('id', id).eq('author', me);
    final String? path = v == null ? null : _pathOf(v.url);
    if (path != null) {
      try {
        await c.storage.from(bucket).remove(<String>[path]);
      } catch (_) {}
    }
  }

  String? _pathOf(String url) {
    final int i = url.indexOf('/$bucket/');
    if (i < 0) return null;
    final String p = url.substring(i + bucket.length + 2);
    return p.startsWith('$me/') ? p : null;
  }

  @override
  Future<bool> toggleLike(String postId, String userId) async {
    final List<dynamic> mine = await c.from('nx_post_likes').select('post_id').eq('post_id', postId).eq('user_id', me);
    if (mine.isNotEmpty) {
      await c.from('nx_post_likes').delete().eq('post_id', postId).eq('user_id', me);
      return false;
    }
    await c.from('nx_post_likes').insert(<String, dynamic>{'post_id': postId, 'user_id': me});
    return true;
  }

  @override
  Future<NovaComment?> addComment(String postId,
      {required String authorId, required String authorName, required String text}) async {
    final String t = text.trim();
    if (t.isEmpty) return null;
    final dynamic r = await c
        .from('nx_post_comments')
        .insert(<String, dynamic>{'post_id': postId, 'author': me, 'text': t.length > 1000 ? t.substring(0, 1000) : t})
        .select()
        .single();
    final Map<dynamic, dynamic> m = r as Map;
    return NovaComment(
        id: '${m['id']}', authorId: explorerId, authorName: authorName, text: '${m['text']}', at: _t(m['created_at']));
  }

  @override
  Future<void> deleteComment(String postId, String commentId) async {
    await c.from('nx_post_comments').delete().eq('id', commentId);
  }

  @override
  Future<Set<String>> savedIds() async {
    try {
      final List<dynamic> rows = await c.from('nx_post_saves').select('post_id').eq('user_id', me);
      return rows.map((dynamic r) => '${(r as Map)['post_id']}').toSet();
    } catch (_) {
      return <String>{};
    }
  }

  @override
  Future<bool> toggleSave(String postId) async {
    final List<dynamic> mine = await c.from('nx_post_saves').select('post_id').eq('post_id', postId).eq('user_id', me);
    if (mine.isNotEmpty) {
      await c.from('nx_post_saves').delete().eq('post_id', postId).eq('user_id', me);
      return false;
    }
    await c.from('nx_post_saves').insert(<String, dynamic>{'post_id': postId, 'user_id': me});
    return true;
  }

  // ------------------------------------------------------------------ stories (24 h)
  @override
  Future<List<NovaStory>> activeStories() async {
    try {
      final List<dynamic> rows = await c
          .from('nx_posts')
          .select(_cols)
          .eq('kind', 'story')
          .gt('expires_at', DateTime.now().toUtc().toIso8601String())
          .order('created_at', ascending: false)
          .limit(60);
      final List<dynamic> seen = await c.from('nx_story_views').select('post_id').eq('user_id', me);
      final Set<String> viewed = seen.map((dynamic r) => '${(r as Map)['post_id']}').toSet();
      await _loadNames(rows.map((dynamic r) => '${(r as Map)['author']}'));
      return rows.map((dynamic raw) {
        final Map<dynamic, dynamic> r = raw as Map;
        final String author = '${r['author']}';
        final NovaVisual v = NovaVisual.fromJson(r['visual']);
        return NovaStory(
          id: '${r['id']}',
          authorId: _out(author),
          authorName: _name(author),
          text: '${r['text'] ?? ''}',
          gradient: v.gradient,
          createdAt: _t(r['created_at']),
          viewed: author == me || viewed.contains('${r['id']}'),
        );
      }).toList();
    } catch (_) {
      return <NovaStory>[];
    }
  }

  @override
  Future<NovaStory> createStory(
      {required String authorId, required String authorName, required String text, required int gradient}) async {
    final dynamic r = await c
        .from('nx_posts')
        .insert(<String, dynamic>{
          'author': me,
          'kind': 'story',
          'text': text.trim(),
          'visual': NovaVisual(kind: NovaVisualKind.gradient, gradient: gradient).toJson(),
        })
        .select(_cols)
        .single();
    final Map<dynamic, dynamic> m = r as Map;
    return NovaStory(
      id: '${m['id']}',
      authorId: explorerId,
      authorName: authorName,
      text: '${m['text']}',
      gradient: gradient,
      createdAt: _t(m['created_at']),
      viewed: true,
    );
  }

  @override
  Future<void> markStoryViewed(String id) async {
    try {
      await c.from('nx_story_views').upsert(<String, dynamic>{'post_id': id, 'user_id': me});
    } catch (_) {}
  }

  @override
  Future<void> deleteStory(String id) async {
    await c.from('nx_posts').delete().eq('id', id).eq('author', me);
  }

  // ------------------------------------------------------------------ notifications
  @override
  Future<List<NovaNotification>> notifications() async {
    final List<NovaNotification> out = <NovaNotification>[...await local.notifications()];
    try {
      final List<dynamic> rows =
          await c.from('nx_notifications').select().eq('user_id', me).order('created_at', ascending: false).limit(80);
      for (final dynamic raw in rows) {
        final Map<dynamic, dynamic> r = raw as Map;
        final String k = '${r['kind']}';
        final String t = '${r['text'] ?? ''}';
        out.add(NovaNotification(
          id: '${r['id']}',
          kind: k,
          textFa: k == 'like' ? '$t پست تو را پسندید.' : (k == 'comment' ? 'دیدگاه تازه — $t' : t),
          textEn: k == 'like' ? '$t liked your post.' : (k == 'comment' ? 'New comment — $t' : t),
          at: _t(r['created_at']),
          postId: r['post_id'] as String?,
          read: r['read'] == true,
        ));
      }
    } catch (_) {}
    out.sort((NovaNotification a, NovaNotification b) => b.at.compareTo(a.at));
    return out;
  }

  @override
  Future<void> addNotification({required String kind, required String fa, required String en, String? postId}) =>
      local.addNotification(kind: kind, fa: fa, en: en, postId: postId);

  @override
  Future<void> markAllNotificationsRead() async {
    await local.markAllNotificationsRead();
    try {
      await c.from('nx_notifications').update(<String, dynamic>{'read': true}).eq('user_id', me).eq('read', false);
    } catch (_) {}
  }

  @override
  Future<void> clearNotifications() async {
    await local.clearNotifications();
    try {
      await c.from('nx_notifications').delete().eq('user_id', me);
    } catch (_) {}
  }

  // ------------------------------------------------------------------ search
  @override
  Future<List<NovaPost>> search(String query) async {
    final String q = query.trim();
    if (q.isEmpty) return <NovaPost>[];
    try {
      List<dynamic> rows;
      if (q.startsWith('#')) {
        final String tag = q.substring(1).toLowerCase();
        rows = await c
            .from('nx_posts')
            .select(_cols)
            .eq('kind', 'post')
            .contains('hashtags', <String>[tag])
            .order('created_at', ascending: false)
            .limit(60);
      } else if (q.startsWith('@')) {
        final String name = q.substring(1).replaceAll('%', '');
        final List<dynamic> users = await c.from('profiles').select('id').ilike('username', '%$name%').limit(20);
        final List<String> ids = users.map((dynamic r) => '${(r as Map)['id']}').toList();
        rows = ids.isEmpty
            ? <dynamic>[]
            : await c
                .from('nx_posts')
                .select(_cols)
                .eq('kind', 'post')
                .inFilter('author', ids)
                .order('created_at', ascending: false)
                .limit(60);
      } else {
        rows = await c
            .from('nx_posts')
            .select(_cols)
            .eq('kind', 'post')
            .ilike('text', '%${q.replaceAll('%', '')}%')
            .order('created_at', ascending: false)
            .limit(60);
      }
      return await _hydrate(rows);
    } catch (_) {
      return <NovaPost>[];
    }
  }

  @override
  Future<List<MapEntry<String, int>>> trendingHashtags({int limit = 12}) async {
    final Map<String, int> n = <String, int>{};
    try {
      final List<dynamic> rows = await c
          .from('nx_posts')
          .select('hashtags')
          .eq('kind', 'post')
          .gt('created_at', DateTime.now().toUtc().subtract(const Duration(days: 30)).toIso8601String())
          .limit(500);
      for (final dynamic r in rows) {
        for (final dynamic t in ((r as Map)['hashtags'] as List?) ?? const <dynamic>[]) {
          n['$t'] = (n['$t'] ?? 0) + 1;
        }
      }
    } catch (_) {}
    final List<MapEntry<String, int>> l = n.entries.toList()
      ..sort((MapEntry<String, int> a, MapEntry<String, int> b) => b.value.compareTo(a.value));
    return l.take(limit).toList();
  }

  // ------------------------------------------------------------------ media
  /// Uploads a photo to `nx-media/<uid>/<time>.<ext>` and returns its public URL.
  Future<String> uploadPhoto(Uint8List bytes, {required String ext}) async {
    final String e = ext.toLowerCase().replaceAll('.', '');
    final String mime = e == 'png' ? 'image/png' : (e == 'webp' ? 'image/webp' : (e == 'gif' ? 'image/gif' : 'image/jpeg'));
    final String path = '$me/${DateTime.now().millisecondsSinceEpoch}.${e.isEmpty ? 'jpg' : e}';
    await c.storage.from(bucket).uploadBinary(path, bytes, fileOptions: FileOptions(contentType: mime, upsert: false));
    return c.storage.from(bucket).getPublicUrl(path);
  }

  // ------------------------------------------------------------------ follows (shared `follows` table)
  Future<({int followers, int following})> followCounts(String uid) async {
    final List<dynamic> a = await c.from('follows').select('follower').eq('followee', uid);
    final List<dynamic> b = await c.from('follows').select('followee').eq('follower', uid);
    return (followers: a.length, following: b.length);
  }

  Future<bool> isFollowing(String uid) async =>
      (await c.from('follows').select('followee').eq('follower', me).eq('followee', uid)).isNotEmpty;

  Future<void> setFollow(String uid, bool on) async {
    if (on) {
      await c.from('follows').insert(<String, dynamic>{'follower': me, 'followee': uid});
    } else {
      await c.from('follows').delete().eq('follower', me).eq('followee', uid);
    }
  }

  /// Real uid for an id coming from the UI (my explorer id maps back to my uid).
  String uidOf(String id) => id == explorerId ? me : id;
}
