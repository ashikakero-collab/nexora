import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/assets/app_assets.dart';
import '../../../core/profile/profile_service.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/theme/nx_theme.dart';
import '../../../core/widgets/nx_widgets.dart';
import '../../../core/online/social_api.dart';
import '../data/orbit_shared_inbox.dart';
import '../models/arcade_refs.dart';
import '../models/orbit_models.dart';
import '../state/orbit_controller.dart';
import 'orbit_bubbles.dart';

/// Club badge ids usable as group/channel/community icons.
const List<String> kOrbitBadges = <String>[
  'badge_club_scorpion',
  'badge_club_wolf',
  'badge_club_yakuza',
  'badge_club_monster',
  'badge_club_bermuda',
  'badge_club_stone',
];

/// Quick emoji bar.
const List<String> kOrbitEmoji = <String>[
  '😀',
  '😂',
  '😍',
  '🥳',
  '😎',
  '🤔',
  '😢',
  '😡',
  '👍',
  '👏',
  '🙏',
  '🔥',
  '✨',
  '🚀',
  '🪐',
  '🌙',
  '⭐',
  '💫',
  '🎮',
  '🏆',
  '❤️',
  '💜',
  '💙',
  '🎉',
];

String orbitMyName(BuildContext context, ProfileService p) => p.username.isEmpty ? context.tx('کاوشگر', 'Explorer') : p.username;

/// Badge selector row.
class OrbitBadgePicker extends StatelessWidget {
  const OrbitBadgePicker({super.key, required this.selected, required this.onChanged});
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 70,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: kOrbitBadges.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (BuildContext c, int i) {
          final String id = i == 0 ? '' : kOrbitBadges[i - 1];
          final bool sel = id == selected;
          return GestureDetector(
            onTap: () => onChanged(id),
            child: AnimatedContainer(
              duration: NxMotion.fast,
              width: 66,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: sel ? WorldPalette.orbit.primary.withValues(alpha: 0.2) : const Color(0x14FFFFFF),
                borderRadius: BorderRadius.circular(NxRadius.md),
                border: Border.all(color: sel ? WorldPalette.orbit.primary : NxColors.glassBorder, width: sel ? 2 : 1),
              ),
              child: id.isEmpty
                  ? const Icon(Icons.block_rounded, color: NxColors.textDim)
                  : Image.asset(AppAssets.clubBadge(id),
                      cacheWidth: 150, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.shield_rounded)),
            ),
          );
        },
      ),
    );
  }
}

/// Create (or edit) a group / channel.
Future<OrbitChat?> showOrbitChatEditor(BuildContext context, {required OrbitChatKind kind, OrbitChat? editing}) {
  return showModalBottomSheet<OrbitChat>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (BuildContext c) => _ChatEditor(kind: kind, editing: editing),
  );
}

class _ChatEditor extends ConsumerStatefulWidget {
  const _ChatEditor({required this.kind, this.editing});
  final OrbitChatKind kind;
  final OrbitChat? editing;

  @override
  ConsumerState<_ChatEditor> createState() => _ChatEditorState();
}

class _ChatEditorState extends ConsumerState<_ChatEditor> {
  late final TextEditingController _name = TextEditingController(text: widget.editing?.name ?? '');
  late final TextEditingController _desc = TextEditingController(text: widget.editing?.description ?? '');
  late String _badge = widget.editing?.badgeId ?? kOrbitBadges.first;
  bool _busy = false;
  final Set<String> _picked = <String>{};

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty || _busy) return;
    setState(() => _busy = true);
    final ctrl = ref.read(orbitControllerProvider);
    final editing = widget.editing;
    if (editing != null) {
      editing.name = _name.text.trim();
      editing.description = _desc.text.trim();
      editing.badgeId = _badge;
      await ctrl.updateChat(editing);
      if (mounted) Navigator.of(context).pop(editing);
      return;
    }
    final profile = ref.read(profileProvider);
    final String me = orbitMyName(context, profile);
    final chat = await ctrl.createChat(
      kind: widget.kind,
      name: _name.text,
      ownerName: me,
      description: _desc.text,
      badgeId: _badge,
      members: _picked.toList(),
    );
    profile.award(
      'orbit.create',
      xp: 10,
      fa: widget.kind == OrbitChatKind.channel ? 'ساخت کانال «${chat.name}»' : 'ساخت گروه «${chat.name}»',
      en: widget.kind == OrbitChatKind.channel ? 'Created channel "${chat.name}"' : 'Created group "${chat.name}"',
    );
    if (mounted) Navigator.of(context).pop(chat);
  }

  @override
  Widget build(BuildContext context) {
    final bool channel = widget.kind == OrbitChatKind.channel;
    final bool editing = widget.editing != null;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(NxSpace.md, 0, NxSpace.md, NxSpace.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          Text(
            editing
                ? context.tx('ویرایش', 'Edit')
                : (channel ? context.tx('کانال تازه', 'New channel') : context.tx('گروه تازه', 'New group')),
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const SizedBox(height: 4),
          Text(
            channel
                ? context.tx('در کانال فقط مدیران منتشر می‌کنند.', 'In a channel only admins publish.')
                : context.tx('گروه برای گفت‌وگوی چندنفره است.', 'Groups are for multi-person conversations.'),
            style: const TextStyle(color: NxColors.textDim, fontSize: 12),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            maxLength: 48,
            decoration: InputDecoration(labelText: context.tx('نام', 'Name')),
            onChanged: (_) => setState(() {}),
          ),
          TextField(
            controller: _desc,
            maxLength: 240,
            maxLines: 3,
            minLines: 1,
            decoration: InputDecoration(labelText: context.tx('توضیحات', 'Description')),
          ),
          Text(context.tx('نشان', 'Badge'), style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          OrbitBadgePicker(selected: _badge, onChanged: (String b) => setState(() => _badge = b)),
          const SizedBox(height: 12),
          if (!editing && ref.watch(orbitControllerProvider).isOnline)
            OrbitFriendPicker(selected: _picked, onChanged: () => setState(() {}))
          else if (!editing)
            const OnlineOnlyNotice(featureFa: 'افزودن اعضای واقعی', featureEn: 'Adding real members'),
          const SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: WorldPalette.orbit.primary),
            onPressed: _name.text.trim().isEmpty || _busy ? null : _save,
            icon: Icon(editing ? Icons.save_rounded : Icons.add_rounded),
            label: Text(editing ? context.tx('ذخیره', 'Save') : context.tx('ساختن', 'Create')),
          ),
        ]),
      ),
    );
  }
}

/// Arcade game picker for invites. Returns the chosen game id.
Future<String?> showArcadeGamePicker(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (BuildContext c) => SizedBox(
      height: MediaQuery.of(c).size.height * 0.62,
      child: Column(children: <Widget>[
        Text(c.tx('دعوت به کدام بازی؟', 'Invite to which game?'),
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(NxSpace.md),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.82,
            ),
            itemCount: kArcadeGames.length,
            itemBuilder: (BuildContext gc, int i) {
              final g = kArcadeGames[i];
              return GlassPanel(
                blur: false,
                padding: const EdgeInsets.all(6),
                onTap: () => Navigator.of(gc).pop(g.id),
                child: Column(children: <Widget>[
                  Expanded(
                    child: Image.asset(AppAssets.pedestal(g.id),
                        cacheWidth: 220,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(Icons.sports_esports_rounded, size: 36)),
                  ),
                  Text(gc.tx(g.nameFa, g.nameEn),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                ]),
              );
            },
          ),
        ),
      ]),
    ),
  );
}

/// Pick a chat to deliver something into.
Future<String?> showOrbitChatPicker(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (BuildContext c) => Consumer(builder: (BuildContext cc, WidgetRef ref, Widget? _) {
      final ctrl = ref.watch(orbitControllerProvider);
      final chats = ctrl.summaries.where((OrbitChatSummary s) => s.chat.canPost(ctrl.ownerId)).toList();
      return SizedBox(
        height: MediaQuery.of(cc).size.height * 0.6,
        child: Column(children: <Widget>[
          Text(cc.tx('ارسال به…', 'Send to…'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          Expanded(
            child: ListView.builder(
              itemCount: chats.length,
              itemBuilder: (BuildContext lc, int i) {
                final OrbitChat chat = chats[i].chat;
                return ListTile(
                  leading: OrbitChatAvatar(chat: chat, size: 40),
                  title: Text(orbitChatTitle(lc, chat)),
                  onTap: () => Navigator.of(lc).pop(chat.id),
                );
              },
            ),
          ),
        ]),
      );
    }),
  );
}

String orbitChatTitle(BuildContext context, OrbitChat chat) => chat.isSaved
    ? context.tx('مدار ذخیره (Saved Orbit)', 'Saved Orbit')
    : (chat.isDirect ? (chat.peerName ?? chat.name) : chat.name);

/// Multi-select of my real friends (mutual follows). Online only.
class OrbitFriendPicker extends ConsumerStatefulWidget {
  const OrbitFriendPicker({super.key, required this.selected, required this.onChanged, this.exclude = const <String>{}});
  final Set<String> selected;
  final VoidCallback onChanged;
  final Set<String> exclude;

  @override
  ConsumerState<OrbitFriendPicker> createState() => _OrbitFriendPickerState();
}

class _OrbitFriendPickerState extends ConsumerState<OrbitFriendPicker> {
  List<NxUser>? _friends;

  @override
  void initState() {
    super.initState();
    final repo = ref.read(orbitControllerProvider).online;
    if (repo != null) {
      SocialApi(repo.c).friends().then((List<NxUser> f) {
        if (mounted) setState(() => _friends = f.where((NxUser u) => !widget.exclude.contains(u.id)).toList());
      }, onError: (Object _) {
        if (mounted) setState(() => _friends = <NxUser>[]);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<NxUser>? f = _friends;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      Text(context.tx('اعضا از میان دوستانت', 'Members from your friends'), style: const TextStyle(fontWeight: FontWeight.w800)),
      if (f == null)
        const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()))
      else if (f.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            context.tx('هنوز دوستی نداری؛ از بخش «مخاطبان» دوست پیدا کن.', 'No friends yet — find some in Contacts.'),
            style: const TextStyle(color: NxColors.textDim, fontSize: 12),
          ),
        )
      else
        for (final NxUser u in f)
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: widget.selected.contains(u.id),
            title: Text(u.username),
            subtitle: Text('Lv ${u.level}${u.isOnlineNow ? ' · ●' : ''}'),
            onChanged: (bool? v) {
              if (v == true) {
                widget.selected.add(u.id);
              } else {
                widget.selected.remove(u.id);
              }
              widget.onChanged();
              setState(() {});
            },
          ),
    ]);
  }
}

/// Lists items other worlds shared. If [chatId] is given, tapping delivers there;
/// otherwise the user picks a chat.
Future<void> showSharedInbox(BuildContext context, {String? chatId}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (BuildContext c) => _SharedInboxSheet(chatId: chatId),
  );
}

class _SharedInboxSheet extends ConsumerWidget {
  const _SharedInboxSheet({this.chatId});
  final String? chatId;

  Future<void> _deliver(BuildContext context, WidgetRef ref, SharedItem item) async {
    final ctrl = ref.read(orbitControllerProvider);
    String? target = chatId;
    target ??= await showOrbitChatPicker(context);
    if (target == null || !context.mounted) return;
    final profile = ref.read(profileProvider);
    await ctrl.deliverShared(item, target, authorName: orbitMyName(context, profile));
    final outcome = await ctrl.reward(profile);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tx('ارسال شد', 'Sent'))));
    await showAwardOutcome(context, outcome);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.watch(orbitControllerProvider);
    final items = ctrl.inboxItems;
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Column(children: <Widget>[
        Text(context.tx('اشتراک‌ها از دنیاهای دیگر', 'Shared from other worlds'),
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        const SizedBox(height: 6),
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(NxSpace.lg),
                    child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                      const OracleAvatar(pose: 'present', size: 90),
                      const SizedBox(height: 10),
                      Text(
                        context.tx('چیزی در صف نیست. در Nova Gallery روی «ارسال به Orbit» بزن تا پست اینجا بیاید.',
                            'Nothing waiting. Tap "Share to Orbit" on a Nova Gallery post and it lands here.'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: NxColors.textDim),
                      ),
                    ]),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(NxSpace.md),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (BuildContext c, int i) {
                    final it = items[i];
                    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                      Expanded(child: OrbitSharedCard(payload: it.toJson(), compact: true)),
                      const SizedBox(width: 8),
                      Column(children: <Widget>[
                        IconButton.filled(
                          tooltip: c.tx('ارسال', 'Send'),
                          onPressed: () => _deliver(c, ref, it),
                          icon: const Icon(Icons.send_rounded),
                        ),
                        IconButton(
                          tooltip: c.tx('رد کردن', 'Dismiss'),
                          onPressed: () => ctrl.dismissShared(it),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ]),
                    ]);
                  },
                ),
        ),
      ]),
    );
  }
}
