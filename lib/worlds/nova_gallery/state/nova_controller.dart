import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/online/online_service.dart';
import '../../../core/profile/profile_service.dart';
import '../../../core/storage/local_store.dart';
import '../../orbit_network/data/orbit_shared_inbox.dart';
import '../data/nova_repository.dart';
import '../data/supabase_nova_repository.dart';
import '../models/nova_models.dart';

/// Online (signed in): real posts on Supabase; otherwise the device-only gallery.
final novaRepositoryProvider = Provider<NovaRepository>((ref) {
  final OnlineService o = ref.watch(onlineProvider);
  final LocalNovaRepository local = LocalNovaRepository(LocalStore.instance);
  final client = o.client;
  if (o.isOnline && client != null) {
    return SupabaseNovaRepository(client, local, explorerId: ref.read(profileProvider).explorerId);
  }
  return local;
});

final novaControllerProvider = ChangeNotifierProvider<NovaController>((ref) => NovaController(ref.watch(novaRepositoryProvider)));

/// In-memory view state of NOVA GALLERY, kept in sync with the repository.
class NovaController extends ChangeNotifier {
  NovaController(this.repo) {
    refresh();
  }

  final NovaRepository repo;
  SupabaseNovaRepository? get online => repo is SupabaseNovaRepository ? repo as SupabaseNovaRepository : null;
  bool loading = true;
  bool _disposed = false;
  List<NovaPost> posts = <NovaPost>[];
  Set<String> saved = <String>{};
  List<NovaStory> stories = <NovaStory>[];
  List<NovaNotification> notifications = <NovaNotification>[];
  List<MapEntry<String, int>> trending = <MapEntry<String, int>>[];

  int get unreadCount => notifications.where((NovaNotification n) => !n.read).length;

  List<NovaPost> postsBy(String authorId) => posts.where((NovaPost p) => p.authorId == authorId).toList();
  List<NovaPost> get savedPosts => posts.where((NovaPost p) => saved.contains(p.id)).toList();
  List<NovaPost> get motionPosts => posts.where((NovaPost p) => p.motion).toList();

  NovaPost? byId(String id) {
    for (final p in posts) {
      if (p.id == id) return p;
    }
    return null;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> refresh() async {
    final f = await repo.feed();
    final s = await repo.savedIds();
    final st = await repo.activeStories();
    final n = await repo.notifications();
    final t = await repo.trendingHashtags();
    posts = f;
    saved = s;
    stories = st;
    notifications = n;
    trending = t;
    loading = false;
    _notify();
  }

  Future<NovaPost> createPost({
    required String authorId,
    required String authorName,
    required String text,
    required NovaVisual visual,
    required bool motion,
  }) async {
    final p = await repo.createPost(authorId: authorId, authorName: authorName, text: text, visual: visual, motion: motion);
    await refresh();
    return p;
  }

  Future<void> updatePost(String id, {required String text, required NovaVisual visual, required bool motion}) async {
    await repo.updatePost(id, text: text, visual: visual, motion: motion);
    await refresh();
  }

  Future<void> deletePost(String id) async {
    await repo.deletePost(id);
    await refresh();
  }

  Future<bool> toggleLike(String postId, String userId) async {
    final r = await repo.toggleLike(postId, userId);
    await refresh();
    return r;
  }

  Future<void> addComment(String postId, {required String authorId, required String authorName, required String text}) async {
    await repo.addComment(postId, authorId: authorId, authorName: authorName, text: text);
    await refresh();
  }

  Future<void> deleteComment(String postId, String commentId) async {
    await repo.deleteComment(postId, commentId);
    await refresh();
  }

  Future<bool> toggleSave(String postId) async {
    final r = await repo.toggleSave(postId);
    await refresh();
    return r;
  }

  Future<void> createStory(
      {required String authorId, required String authorName, required String text, required int gradient}) async {
    await repo.createStory(authorId: authorId, authorName: authorName, text: text, gradient: gradient);
    await refresh();
  }

  Future<void> markStoryViewed(String id) async {
    await repo.markStoryViewed(id);
    await refresh();
  }

  Future<void> deleteStory(String id) async {
    await repo.deleteStory(id);
    await refresh();
  }

  Future<void> markAllRead() async {
    await repo.markAllNotificationsRead();
    await refresh();
  }

  Future<void> clearNotifications() async {
    await repo.clearNotifications();
    await refresh();
  }

  Future<List<NovaPost>> search(String q) => repo.search(q);

  /// Writes the post into ORBIT NETWORK's shared inbox (cross-world share).
  Future<void> shareToOrbit(NovaPost p, bool fa) async {
    await OrbitSharedInbox(LocalStore.instance).add(SharedItem(
      type: SharedItem.novaPost,
      id: p.id,
      text: p.textFor(fa),
      at: DateTime.now(),
      extra: <String, dynamic>{
        'author': p.authorName,
        'gradient': p.visual.gradient,
        'asset': p.visual.asset,
        'visual': p.visual.kind.name,
      },
    ));
    await repo.addNotification(
      kind: NovaNotifKind.share,
      fa: 'پست به صندوق اشتراک ORBIT NETWORK فرستاده شد.',
      en: 'Post sent to the ORBIT NETWORK share inbox.',
      postId: p.id,
    );
    await refresh();
  }
}
