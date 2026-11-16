import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/profile/profile_service.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/theme/nx_theme.dart';
import '../../../core/widgets/nx_widgets.dart';
import '../models/nova_models.dart';
import '../state/nova_controller.dart';
import 'nova_composer.dart';
import 'nova_visuals.dart';

/// One post in the feed.
class NovaPostCard extends ConsumerWidget {
  const NovaPostCard({super.key, required this.post, this.onHashtag, this.onMention});
  final NovaPost post;
  final ValueChanged<String>? onHashtag;
  final ValueChanged<String>? onMention;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.watch(novaControllerProvider);
    final profile = ref.watch(profileProvider);
    final String me = profile.explorerId;
    final bool mine = post.authorId == me;
    final bool liked = post.likedByUser(me);
    final bool saved = ctrl.saved.contains(post.id);
    final String text = post.textFor(context.isFa);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: NxSpace.md, vertical: NxSpace.sm),
      child: GlassPanel(
        padding: const EdgeInsets.all(12),
        tint: post.official ? const Color(0x2200C2FF) : const Color(0x1FFFFFFF),
        borderColor: post.official ? NxColors.electricBlue.withValues(alpha: 0.5) : null,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          Row(children: <Widget>[
            NovaAvatar(name: post.authorName, official: post.official, size: 40),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Row(children: <Widget>[
                  Flexible(
                    child: Text(post.authorName,
                        overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                  if (post.official) ...<Widget>[
                    const SizedBox(width: 4),
                    const Icon(Icons.verified_rounded, size: 16, color: NxColors.electricBlue),
                  ],
                ]),
                Text(
                  [
                    novaAgo(context, post.createdAt),
                    if (post.editedAt != null) context.tx('ویرایش‌شده', 'edited'),
                    if (post.motion) context.tx('حرکتی', 'motion'),
                  ].join(' · '),
                  style: const TextStyle(color: NxColors.textDim, fontSize: 12),
                ),
              ]),
            ),
            if (post.official) NxPill(label: context.tx('رسمی', 'Official'), color: NxColors.electricBlue),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: (String v) => _menu(context, ref, v),
              itemBuilder: (BuildContext c) => <PopupMenuEntry<String>>[
                if (mine) PopupMenuItem<String>(value: 'edit', child: Text(c.tx('ویرایش', 'Edit'))),
                if (mine) PopupMenuItem<String>(value: 'delete', child: Text(c.tx('حذف', 'Delete'))),
                PopupMenuItem<String>(value: 'share', child: Text(c.tx('ارسال به Orbit', 'Share to Orbit'))),
                PopupMenuItem<String>(value: 'copy', child: Text(c.tx('کپی متن', 'Copy text'))),
              ],
            ),
          ]),
          const SizedBox(height: 10),
          if (!post.visual.isNone) ...<Widget>[
            NovaVisualView(
              visual: post.visual,
              caption: text.length <= 90 ? text : null,
              animated: post.motion,
            ),
            const SizedBox(height: 10),
          ],
          if (text.isNotEmpty)
            NovaRichText(text: text, onHashtag: onHashtag, onMention: onMention),
          const SizedBox(height: 6),
          Row(children: <Widget>[
            _ActionButton(
              icon: liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              color: liked ? const Color(0xFFFF4F8B) : NxColors.iceWhite,
              label: '${post.likeCount}',
              animateKey: liked,
              onTap: () {
                if (ref.read(settingsProvider).haptics) HapticFeedback.lightImpact();
                ctrl.toggleLike(post.id, me);
              },
            ),
            _ActionButton(
              icon: Icons.mode_comment_outlined,
              label: '${post.comments.length}',
              onTap: () => showNovaComments(context, post.id, onHashtag: onHashtag, onMention: onMention),
            ),
            _ActionButton(
              icon: Icons.send_rounded,
              label: context.tx('Orbit', 'Orbit'),
              onTap: () => shareNovaPostToOrbit(context, ref, post),
            ),
            const Spacer(),
            _ActionButton(
              icon: saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
              color: saved ? NxColors.gold : NxColors.iceWhite,
              animateKey: saved,
              onTap: () async {
                final bool s = await ctrl.toggleSave(post.id);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(s ? context.tx('ذخیره شد', 'Saved') : context.tx('از ذخیره‌ها برداشته شد', 'Removed from saved')),
                  duration: const Duration(seconds: 1),
                ));
              },
            ),
          ]),
        ]),
      ),
    );
  }

  Future<void> _menu(BuildContext context, WidgetRef ref, String v) async {
    final ctrl = ref.read(novaControllerProvider);
    switch (v) {
      case 'edit':
        await showNovaComposer(context, editing: post);
        break;
      case 'delete':
        final bool? ok = await showDialog<bool>(
          context: context,
          builder: (BuildContext c) => AlertDialog(
            title: Text(c.tx('حذف پست؟', 'Delete post?')),
            content: Text(c.tx('این پست برای همیشه از دستگاهت پاک می‌شود.', 'This post will be removed from your device for good.')),
            actions: <Widget>[
              TextButton(onPressed: () => Navigator.pop(c, false), child: Text(c.tx('انصراف', 'Cancel'))),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: NxColors.danger),
                onPressed: () => Navigator.pop(c, true),
                child: Text(c.tx('حذف', 'Delete')),
              ),
            ],
          ),
        );
        if (ok == true) await ctrl.deletePost(post.id);
        break;
      case 'share':
        if (context.mounted) await shareNovaPostToOrbit(context, ref, post);
        break;
      case 'copy':
        await Clipboard.setData(ClipboardData(text: post.textFor(context.isFa)));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tx('متن کپی شد', 'Text copied'))));
        }
        break;
    }
  }
}

/// Share any post into ORBIT NETWORK's shared inbox, with a shortcut to open it.
Future<void> shareNovaPostToOrbit(BuildContext context, WidgetRef ref, NovaPost post) async {
  await ref.read(novaControllerProvider).shareToOrbit(post, context.isFa);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(context.tx('در صندوق اشتراک Orbit Network قرار گرفت', 'Placed in the Orbit Network share inbox')),
    action: SnackBarAction(
      label: context.tx('باز کردن', 'Open'),
      onPressed: () => context.push('/world/orbit_network'),
    ),
  ));
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.icon, required this.onTap, this.label, this.color = NxColors.iceWhite, this.animateKey});
  final IconData icon;
  final VoidCallback onTap;
  final String? label;
  final Color color;
  final Object? animateKey;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
          AnimatedSwitcher(
            duration: NxMotion.normal,
            transitionBuilder: (Widget child, Animation<double> a) =>
                ScaleTransition(scale: CurvedAnimation(parent: a, curve: Curves.elasticOut), child: child),
            child: Icon(icon, key: ValueKey<Object?>(animateKey ?? icon), color: color, size: 22),
          ),
          if (label != null) ...<Widget>[
            const SizedBox(width: 4),
            Text(label!, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          ],
        ]),
      ),
    );
  }
}

/// Comments sheet for a post.
Future<void> showNovaComments(BuildContext context, String postId,
    {ValueChanged<String>? onHashtag, ValueChanged<String>? onMention}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (BuildContext c) => _CommentsSheet(postId: postId, onHashtag: onHashtag, onMention: onMention),
  );
}

class _CommentsSheet extends ConsumerStatefulWidget {
  const _CommentsSheet({required this.postId, this.onHashtag, this.onMention});
  final String postId;
  final ValueChanged<String>? onHashtag;
  final ValueChanged<String>? onMention;

  @override
  ConsumerState<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends ConsumerState<_CommentsSheet> {
  final TextEditingController _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _tagTap(String tag) {
    Navigator.of(context).pop();
    widget.onHashtag?.call(tag);
  }

  void _mentionTap(String m) {
    Navigator.of(context).pop();
    widget.onMention?.call(m);
  }

  Future<void> _send() async {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    final p = ref.read(profileProvider);
    await ref.read(novaControllerProvider).addComment(
          widget.postId,
          authorId: p.explorerId,
          authorName: novaMyName(context, p),
          text: t,
        );
    _text.clear();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = ref.watch(novaControllerProvider);
    final me = ref.watch(profileProvider).explorerId;
    final NovaPost? post = ctrl.byId(widget.postId);
    final comments = post?.comments ?? const <NovaComment>[];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(children: <Widget>[
          Text(context.tx('دیدگاه‌ها', 'Comments'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          const SizedBox(height: 8),
          Expanded(
            child: comments.isEmpty
                ? NovaEmptyState(
                    fa: 'هنوز دیدگاهی نیست. اولین نفر باش!',
                    en: 'No comments yet. Be the first!',
                    pose: 'happy',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: NxSpace.md),
                    itemCount: comments.length,
                    itemBuilder: (BuildContext c, int i) {
                      final cm = comments[i];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: NovaAvatar(name: cm.authorName, size: 34),
                        title: Row(children: <Widget>[
                          Flexible(child: Text(cm.authorName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13))),
                          const SizedBox(width: 6),
                          Text(novaAgo(c, cm.at), style: const TextStyle(color: NxColors.textDim, fontSize: 11)),
                        ]),
                        subtitle: NovaRichText(
                          text: cm.text,
                          style: const TextStyle(fontSize: 14, height: 1.4, color: NxColors.iceWhite),
                          onHashtag: _tagTap,
                          onMention: _mentionTap,
                        ),
                        trailing: cm.authorId == me
                            ? IconButton(
                                icon: const Icon(Icons.delete_outline_rounded, size: 20),
                                onPressed: () => ctrl.deleteComment(widget.postId, cm.id),
                              )
                            : null,
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(NxSpace.sm),
            child: Row(children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _text,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 500,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: context.tx('یک دیدگاه بنویس… (#هشتگ، @نام)', 'Write a comment… (#tag, @name)'),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(onPressed: _send, icon: const Icon(Icons.send_rounded)),
            ]),
          ),
        ]),
      ),
    );
  }
}
