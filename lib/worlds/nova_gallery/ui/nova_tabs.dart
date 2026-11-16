import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/profile/profile_service.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/theme/nx_theme.dart';
import '../../../core/widgets/nx_widgets.dart';
import '../models/nova_models.dart';
import '../state/nova_controller.dart';
import 'nova_composer.dart';
import 'nova_post_card.dart';
import 'nova_story_viewer.dart';
import 'nova_follow.dart';
import 'nova_visuals.dart';

const double _kBottomPad = 96;

// ---------------------------------------------------------------- FEED
class NovaFeedTab extends ConsumerWidget {
  const NovaFeedTab({super.key, required this.onHashtag, required this.onMention});
  final ValueChanged<String> onHashtag;
  final ValueChanged<String> onMention;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.watch(novaControllerProvider);
    if (ctrl.loading) return const Center(child: CircularProgressIndicator());
    final posts = ctrl.posts;
    return RefreshIndicator(
      onRefresh: ctrl.refresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: <Widget>[
          const SliverToBoxAdapter(child: NovaStoriesRow()),
          if (posts.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: NovaEmptyState(
                fa: 'فید خالی است. اولین پستت را منتشر کن تا گالری‌ات جان بگیرد.',
                en: 'Your feed is empty. Publish your first post to bring your gallery to life.',
                action: FilledButton.icon(
                  onPressed: () => showNovaComposer(context),
                  icon: const Icon(Icons.add_rounded),
                  label: Text(context.tx('پست تازه', 'New post')),
                ),
              ),
            )
          else
            SliverList.builder(
              itemCount: posts.length,
              itemBuilder: (BuildContext c, int i) => NovaPostCard(
                key: ValueKey<String>(posts[i].id),
                post: posts[i],
                onHashtag: onHashtag,
                onMention: onMention,
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: _kBottomPad)),
        ],
      ),
    );
  }
}

/// Horizontal stories strip (create + active stories).
class NovaStoriesRow extends ConsumerWidget {
  const NovaStoriesRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.watch(novaControllerProvider);
    final stories = ctrl.stories;
    return SizedBox(
      height: 104,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: NxSpace.md, vertical: 8),
        scrollDirection: Axis.horizontal,
        itemCount: stories.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (BuildContext c, int i) {
          if (i == 0) {
            return _StoryBubble(
              label: c.tx('استوری تو', 'Your story'),
              onTap: () => showStoryComposer(c),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0x22FFFFFF),
                  border: Border.all(color: WorldPalette.nova.primary, width: 2),
                ),
                child: Icon(Icons.add_rounded, color: WorldPalette.nova.primary, size: 30),
              ),
            );
          }
          final s = stories[i - 1];
          return _StoryBubble(
            label: s.authorName,
            onTap: () => openNovaStories(c, stories, i - 1),
            child: Opacity(
              opacity: s.viewed ? 0.55 : 1,
              child: Container(
                padding: const EdgeInsets.all(2.5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: SweepGradient(
                    colors: s.viewed
                        ? const <Color>[Colors.white38, Colors.white24, Colors.white38]
                        : const <Color>[Color(0xFFFF6FB5), Color(0xFFFFC857), Color(0xFFFF6FB5)],
                  ),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: novaGradient(s.gradient).colors),
                  ),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(6),
                  child: Text(
                    s.text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _StoryBubble extends StatelessWidget {
  const _StoryBubble({required this.label, required this.onTap, required this.child});
  final String label;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 68,
        child: Column(children: <Widget>[
          SizedBox(width: 64, height: 64, child: child),
          const SizedBox(height: 4),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- REELS
class NovaReelsTab extends ConsumerWidget {
  const NovaReelsTab({super.key, required this.onHashtag, required this.onMention});
  final ValueChanged<String> onHashtag;
  final ValueChanged<String> onMention;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.watch(novaControllerProvider);
    final me = ref.watch(profileProvider).explorerId;
    if (ctrl.loading) return const Center(child: CircularProgressIndicator());
    final reels = ctrl.motionPosts;
    if (reels.isEmpty) {
      return NovaEmptyState(
        fa: 'ریلزِ آفلاین از «پست‌های حرکتی» ساخته می‌شود: گرادیان زنده با متن تو. ویدئوی واقعی بعد از اتصال سرور.',
        en: 'Offline Reels are built from motion posts: a living gradient with your words. Real video comes with the server.',
        pose: 'spin',
        action: FilledButton.icon(
          onPressed: () => showNovaComposer(context, motion: true),
          icon: const Icon(Icons.movie_filter_rounded),
          label: Text(context.tx('ساخت پست حرکتی', 'Create motion post')),
        ),
      );
    }
    return PageView.builder(
      scrollDirection: Axis.vertical,
      itemCount: reels.length,
      itemBuilder: (BuildContext c, int i) {
        final NovaPost p = reels[i];
        final bool liked = p.likedByUser(me);
        final bool saved = ctrl.saved.contains(p.id);
        return Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 90),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(NxRadius.lg),
            child: NovaMotionCanvas(
              gradient: p.visual.gradient,
              child: Stack(children: <Widget>[
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 64, vertical: 40),
                    child: NovaRichText(
                      text: p.textFor(c.isFa),
                      textAlign: TextAlign.center,
                      onHashtag: onHashtag,
                      onMention: onMention,
                      style: const TextStyle(
                        fontSize: 24,
                        height: 1.45,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        shadows: <Shadow>[Shadow(color: Colors.black54, blurRadius: 14)],
                      ),
                    ),
                  ),
                ),
                PositionedDirectional(
                  start: 14,
                  bottom: 16,
                  end: 80,
                  child: Row(children: <Widget>[
                    NovaAvatar(name: p.authorName, official: p.official, size: 34),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(p.authorName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
                    ),
                    if (p.official) ...<Widget>[
                      const SizedBox(width: 4),
                      const Icon(Icons.verified_rounded, size: 16, color: Colors.white),
                    ],
                  ]),
                ),
                PositionedDirectional(
                  end: 10,
                  bottom: 16,
                  child: Column(children: <Widget>[
                    _ReelAction(
                      icon: liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      color: liked ? const Color(0xFFFF4F8B) : Colors.white,
                      label: '${p.likeCount}',
                      onTap: () => ctrl.toggleLike(p.id, me),
                    ),
                    _ReelAction(
                      icon: Icons.mode_comment_rounded,
                      label: '${p.comments.length}',
                      onTap: () => showNovaComments(c, p.id, onHashtag: onHashtag, onMention: onMention),
                    ),
                    _ReelAction(
                      icon: saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                      color: saved ? NxColors.gold : Colors.white,
                      label: c.tx('ذخیره', 'Save'),
                      onTap: () => ctrl.toggleSave(p.id),
                    ),
                    _ReelAction(
                      icon: Icons.send_rounded,
                      label: 'Orbit',
                      onTap: () => shareNovaPostToOrbit(c, ref, p),
                    ),
                  ]),
                ),
                PositionedDirectional(
                  top: 12,
                  start: 12,
                  child: NxPill(label: '${i + 1}/${reels.length}', icon: Icons.movie_filter_rounded, color: Colors.white),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }
}

class _ReelAction extends StatelessWidget {
  const _ReelAction({required this.icon, required this.label, required this.onTap, this.color = Colors.white});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Column(children: <Widget>[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0x33000000)),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- EXPLORE
class NovaExploreTab extends ConsumerStatefulWidget {
  const NovaExploreTab({super.key, required this.query, required this.onQuery, required this.onMention});
  final String query;
  final ValueChanged<String> onQuery;
  final ValueChanged<String> onMention;

  @override
  ConsumerState<NovaExploreTab> createState() => _NovaExploreTabState();
}

class _NovaExploreTabState extends ConsumerState<NovaExploreTab> {
  late final TextEditingController _q = TextEditingController(text: widget.query);
  List<NovaPost> _results = <NovaPost>[];
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _searching = true;
    _run(widget.query, initial: true);
  }

  @override
  void didUpdateWidget(covariant NovaExploreTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query && widget.query != _q.text) {
      _q.text = widget.query;
      _searching = true;
      _run(widget.query, initial: true);
    }
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _run(String q, {bool initial = false}) async {
    if (!initial) setState(() => _searching = true);
    final r = await ref.read(novaControllerProvider).search(q);
    if (!mounted) return;
    setState(() {
      _results = r;
      _searching = false;
    });
  }

  void _tag(String t) {
    final String q = '#$t';
    _q.text = q;
    widget.onQuery(q);
    _run(q);
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = ref.watch(novaControllerProvider);
    final bool hasQuery = _q.text.trim().isNotEmpty;
    return CustomScrollView(slivers: <Widget>[
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(NxSpace.md, NxSpace.sm, NxSpace.md, 0),
          child: TextField(
            controller: _q,
            textInputAction: TextInputAction.search,
            onSubmitted: (String v) {
              widget.onQuery(v);
              _run(v);
            },
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: context.tx('جستجو: متن، #هشتگ یا @نام', 'Search: text, #hashtag or @name'),
              suffixIcon: hasQuery
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        _q.clear();
                        widget.onQuery('');
                        _run('');
                      },
                    )
                  : null,
            ),
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(NxSpace.md),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Row(children: <Widget>[
              const Icon(Icons.local_fire_department_rounded, color: NxColors.gold, size: 18),
              const SizedBox(width: 6),
              Text(context.tx('هشتگ‌های داغ', 'Trending hashtags'), style: const TextStyle(fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
              for (final MapEntry<String, int> e in ctrl.trending)
                ActionChip(
                  avatar: const Icon(Icons.tag_rounded, size: 16),
                  label: Text('${e.key} · ${e.value}'),
                  onPressed: () => _tag(e.key),
                ),
            ]),
          ]),
        ),
      ),
      if (_searching)
        const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())))
      else if (_results.isEmpty)
        SliverToBoxAdapter(
          child: NovaEmptyState(
            pose: 'confused',
            fa: 'چیزی پیدا نشد. هشتگ دیگری امتحان کن یا خودت اولین پست با آن را بساز.',
            en: 'Nothing found. Try another hashtag or be the first to post with it.',
          ),
        )
      else
        SliverList.builder(
          itemCount: _results.length,
          itemBuilder: (BuildContext c, int i) => NovaPostCard(
            key: ValueKey<String>('x_${_results[i].id}'),
            post: ctrl.byId(_results[i].id) ?? _results[i],
            onHashtag: _tag,
            onMention: widget.onMention,
          ),
        ),
      const SliverToBoxAdapter(child: SizedBox(height: _kBottomPad)),
    ]);
  }
}

// ---------------------------------------------------------------- NOTIFICATIONS
class NovaNotificationsTab extends ConsumerWidget {
  const NovaNotificationsTab({super.key, required this.onOpenPost});
  final ValueChanged<String> onOpenPost;

  IconData _icon(String kind) {
    switch (kind) {
      case NovaNotifKind.like:
        return Icons.favorite_rounded;
      case NovaNotifKind.comment:
        return Icons.mode_comment_rounded;
      case NovaNotifKind.share:
        return Icons.send_rounded;
      case NovaNotifKind.story:
        return Icons.bolt_rounded;
      case NovaNotifKind.post:
        return Icons.rocket_launch_rounded;
      default:
        return Icons.auto_awesome;
    }
  }

  Color _color(String kind) {
    switch (kind) {
      case NovaNotifKind.like:
        return const Color(0xFFFF4F8B);
      case NovaNotifKind.comment:
        return NxColors.turquoise;
      case NovaNotifKind.share:
        return NxColors.electricBlue;
      case NovaNotifKind.story:
        return NxColors.gold;
      default:
        return WorldPalette.nova.primary;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.watch(novaControllerProvider);
    final list = ctrl.notifications;
    return Column(children: <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(NxSpace.md, NxSpace.sm, NxSpace.md, 0),
        child: Row(children: <Widget>[
          Text(context.tx('اعلان‌ها', 'Notifications'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          const Spacer(),
          if (ctrl.unreadCount > 0)
            TextButton(onPressed: ctrl.markAllRead, child: Text(context.tx('همه خوانده شد', 'Mark all read'))),
          if (list.isNotEmpty)
            IconButton(
              tooltip: context.tx('پاک کردن', 'Clear'),
              onPressed: ctrl.clearNotifications,
              icon: const Icon(Icons.delete_sweep_rounded),
            ),
        ]),
      ),
      Expanded(
        child: list.isEmpty
            ? const NovaEmptyState(
                pose: 'sleep',
                fa: 'اعلانی نیست. لایک‌ها و دیدگاه‌های پست‌هایت اینجا می‌آیند.',
                en: 'No notifications. Likes and comments on your posts show up here.',
              )
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(NxSpace.md, NxSpace.sm, NxSpace.md, _kBottomPad),
                itemCount: list.length,
                itemBuilder: (BuildContext c, int i) {
                  final n = list[i];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: GlassPanel(
                      blur: false,
                      padding: const EdgeInsets.all(12),
                      tint: n.read ? const Color(0x14FFFFFF) : const Color(0x26FF6FB5),
                      onTap: n.postId == null ? null : () => onOpenPost(n.postId!),
                      child: Row(children: <Widget>[
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: _color(n.kind).withValues(alpha: 0.2),
                          child: Icon(_icon(n.kind), color: _color(n.kind), size: 18),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                            Text(c.tx(n.textFa, n.textEn), style: const TextStyle(height: 1.35)),
                            const SizedBox(height: 2),
                            Text(novaAgo(c, n.at), style: const TextStyle(color: NxColors.textDim, fontSize: 11)),
                          ]),
                        ),
                        if (!n.read)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(shape: BoxShape.circle, color: WorldPalette.nova.primary),
                          ),
                      ]),
                    ),
                  );
                },
              ),
      ),
    ]);
  }
}

// ---------------------------------------------------------------- PROFILE
class NovaProfileTab extends ConsumerStatefulWidget {
  const NovaProfileTab({super.key, required this.onOpenPost});
  final ValueChanged<String> onOpenPost;

  @override
  ConsumerState<NovaProfileTab> createState() => _NovaProfileTabState();
}

class _NovaProfileTabState extends ConsumerState<NovaProfileTab> {
  bool _showSaved = false;

  @override
  Widget build(BuildContext context) {
    final ctrl = ref.watch(novaControllerProvider);
    final profile = ref.watch(profileProvider);
    final mine = ctrl.postsBy(profile.explorerId);
    final int likes = mine.fold<int>(0, (int a, NovaPost p) => a + p.likeCount);
    final grid = _showSaved ? ctrl.savedPosts : mine;
    final String name = novaMyName(context, profile);
    return CustomScrollView(slivers: <Widget>[
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(NxSpace.md),
          child: GlassPanel(
            child: Column(children: <Widget>[
              Row(children: <Widget>[
                NovaAvatar(name: name, size: 72, ring: true),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                    Text(name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text(profile.explorerId, style: const TextStyle(color: NxColors.textDim, letterSpacing: 1.2)),
                    if (profile.bio.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(profile.bio, maxLines: 2, overflow: TextOverflow.ellipsis),
                    ],
                  ]),
                ),
              ]),
              const SizedBox(height: 14),
              Row(children: <Widget>[
                _Stat(value: '${mine.length}', label: context.tx('پست', 'Posts')),
                _Stat(value: '$likes', label: context.tx('لایک', 'Likes')),
                _Stat(value: '${ctrl.saved.length}', label: context.tx('ذخیره', 'Saved')),
                _Stat(
                  value: '${ctrl.stories.where((NovaStory s) => s.authorId == profile.explorerId).length}',
                  label: context.tx('استوری', 'Stories'),
                ),
              ]),
              const SizedBox(height: 12),
              const XpBar(height: 8),
              const SizedBox(height: 10),
              if (ctrl.online != null)
                NovaFollowBar(uid: ctrl.online!.me, self: true)
              else
                const OnlineOnlyNotice(featureFa: 'دنبال‌کردن و دنبال‌کننده‌ها', featureEn: 'Following and followers'),
            ]),
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: NxSpace.md),
          child: SegmentedButton<bool>(
            segments: <ButtonSegment<bool>>[
              ButtonSegment<bool>(
                  value: false, icon: const Icon(Icons.grid_view_rounded), label: Text(context.tx('پست‌ها', 'Posts'))),
              ButtonSegment<bool>(
                  value: true, icon: const Icon(Icons.bookmark_rounded), label: Text(context.tx('ذخیره‌ها', 'Saved'))),
            ],
            selected: <bool>{_showSaved},
            onSelectionChanged: (Set<bool> s) => setState(() => _showSaved = s.first),
          ),
        ),
      ),
      if (grid.isEmpty)
        SliverToBoxAdapter(
          child: NovaEmptyState(
            fa: _showSaved ? 'هنوز چیزی ذخیره نکرده‌ای. روی نشان ذخیره‌ی هر پست بزن.' : 'هنوز پستی نداری. دکمه‌ی + را بزن.',
            en: _showSaved ? 'Nothing saved yet. Tap the bookmark on any post.' : 'No posts yet. Tap the + button.',
          ),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.all(NxSpace.md),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
            ),
            itemCount: grid.length,
            itemBuilder: (BuildContext c, int i) => _GridTile(post: grid[i], onTap: () => widget.onOpenPost(grid[i].id)),
          ),
        ),
      const SliverToBoxAdapter(child: SizedBox(height: _kBottomPad)),
    ]);
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(children: <Widget>[
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          Text(label, style: const TextStyle(color: NxColors.textDim, fontSize: 12)),
        ]),
      );
}

class _GridTile extends StatelessWidget {
  const _GridTile({required this.post, required this.onTap});
  final NovaPost post;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String text = post.textFor(context.isFa);
    return GestureDetector(
      onTap: onTap,
      child: Stack(fit: StackFit.expand, children: <Widget>[
        if (post.visual.isNone)
          Container(
            decoration: BoxDecoration(
              color: const Color(0x22FFFFFF),
              borderRadius: BorderRadius.circular(NxRadius.sm),
              border: Border.all(color: NxColors.glassBorder),
            ),
            padding: const EdgeInsets.all(8),
            child: Text(text, maxLines: 5, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
          )
        else
          NovaVisualView(
            visual: post.visual,
            caption: text.length <= 40 ? text : null,
            height: 140,
            radius: NxRadius.sm,
          ),
        if (post.motion)
          const PositionedDirectional(
            top: 4,
            end: 4,
            child: Icon(Icons.movie_filter_rounded, size: 16, color: Colors.white),
          ),
      ]),
    );
  }
}
