import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/settings/app_settings.dart';
import '../../../core/theme/nx_theme.dart';
import '../../../core/widgets/nx_widgets.dart';
import '../../orbit_network/models/arcade_refs.dart';
import '../models/social_models.dart';
import '../state/social_controller.dart';
import 'social_widgets.dart';

// ============================ actions ============================

Future<void> composeCommunityPost(BuildContext context, WidgetRef ref, Community c) async {
  final String? text = await askText(context,
      titleFa: 'پست در ${c.name}',
      titleEn: 'Post in ${c.name}',
      hintFa: 'چه خبر؟',
      hintEn: "What's up?",
      maxLength: 500,
      maxLines: 5);
  if (text == null || text.trim().isEmpty) return;
  final SocialMe me = socialMe(ref);
  await ref.read(socialControllerProvider).addPost(c.id, authorId: me.id, authorName: me.name, text: text);
}

Future<void> composeAnnouncement(BuildContext context, WidgetRef ref, Community c) async {
  final String? text = await askText(context,
      titleFa: 'اطلاعیه تازه',
      titleEn: 'New announcement',
      hintFa: 'پیام مهم برای همه اعضا',
      hintEn: 'Important message for all members',
      maxLength: 280,
      maxLines: 4);
  if (text == null || text.trim().isEmpty) return;
  final SocialMe me = socialMe(ref);
  final bool ok = await ref.read(socialControllerProvider).announce(c.id, actorId: me.id, actorName: me.name, text: text);
  if (!ok && context.mounted)
    socialSnack(context, 'فقط مالک و مدیران اطلاعیه می‌دهند.', 'Only the owner and admins can announce.');
}

Future<void> addLocalPlayer(BuildContext context, WidgetRef ref, Community c) async {
  final String? name = await askText(context,
      titleFa: 'افزودن بازیکن محلی',
      titleEn: 'Add local player',
      hintFa: 'نام بازیکن روی همین دستگاه',
      hintEn: 'Player name on this device',
      maxLength: 24);
  if (name == null || name.trim().isEmpty) return;
  final bool ok = await ref.read(socialControllerProvider).addLocalMember(c.id, socialMe(ref).id, name);
  if (!context.mounted) return;
  if (ok) {
    socialSnack(context, '«${name.trim()}» به‌عنوان بازیکن محلی اضافه شد.', '"${name.trim()}" added as a local player.');
  } else {
    socialSnack(context, 'این نام تکراری است یا اجازه نداری.', 'That name is taken or you lack permission.');
  }
}

Future<void> createCommunityEvent(BuildContext context, WidgetRef ref, Community c) async {
  final TextEditingController title = TextEditingController();
  final TextEditingController desc = TextEditingController();
  DateTime when = DateTime.now().add(const Duration(days: 1));
  when = DateTime(when.year, when.month, when.day, 20);
  String? gameId = c.gameId;
  final bool? ok = await showDialog<bool>(
    context: context,
    builder: (BuildContext dc) => StatefulBuilder(
      builder: (BuildContext sc, StateSetter set) => AlertDialog(
        title: Text(sc.tx('رویداد تازه', 'New event')),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            TextField(controller: title, maxLength: 60, decoration: InputDecoration(labelText: sc.tx('عنوان', 'Title'))),
            TextField(
              controller: desc,
              maxLength: 240,
              maxLines: 3,
              minLines: 1,
              decoration: InputDecoration(labelText: sc.tx('توضیح', 'Description')),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_month_rounded),
              title: Text(formatDateTime(when)),
              subtitle: Text(sc.tx('برای تغییر تاریخ و ساعت بزن', 'Tap to change date & time')),
              onTap: () async {
                final DateTime now = DateTime.now();
                final DateTime? d = await showDatePicker(
                  context: sc,
                  initialDate: when.isBefore(now) ? now : when,
                  firstDate: DateTime(now.year, now.month, now.day),
                  lastDate: now.add(const Duration(days: 365)),
                );
                if (d == null || !sc.mounted) return;
                final TimeOfDay? t = await showTimePicker(context: sc, initialTime: TimeOfDay.fromDateTime(when));
                if (t == null) return;
                set(() => when = DateTime(d.year, d.month, d.day, t.hour, t.minute));
              },
            ),
            DropdownButtonFormField<String?>(
              value: gameId,
              decoration: InputDecoration(labelText: sc.tx('بازی (اختیاری)', 'Game (optional)')),
              items: <DropdownMenuItem<String?>>[
                DropdownMenuItem<String?>(value: null, child: Text(sc.tx('بدون بازی', 'No game'))),
                for (final ArcadeGameRef g in kArcadeGames)
                  DropdownMenuItem<String?>(value: g.id, child: Text(sc.tx(g.nameFa, g.nameEn))),
              ],
              onChanged: (String? v) => set(() => gameId = v),
            ),
          ]),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(dc, false), child: Text(sc.tx('انصراف', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(dc, true), child: Text(sc.tx('ساخت', 'Create'))),
        ],
      ),
    ),
  );
  final String t = title.text;
  final String d = desc.text;
  title.dispose();
  desc.dispose();
  if (ok != true) return;
  if (t.trim().isEmpty) {
    if (context.mounted) socialSnack(context, 'رویداد عنوان لازم دارد.', 'An event needs a title.');
    return;
  }
  if (!when.isAfter(DateTime.now())) {
    if (context.mounted) socialSnack(context, 'زمان رویداد باید در آینده باشد.', 'The event time must be in the future.');
    return;
  }
  final bool done = await ref
      .read(socialControllerProvider)
      .addEvent(c.id, actorId: socialMe(ref).id, title: t, description: d, startsAt: when, gameId: gameId);
  if (!done && context.mounted) socialSnack(context, 'اجازه ساخت رویداد نداری.', "You can't create events here.");
}

// ============================ Feed ============================

class CommunityFeedTab extends ConsumerWidget {
  const CommunityFeedTab({super.key, required this.community});
  final Community community;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Community c = community;
    final SocialMe me = socialMe(ref);
    final CommunityRole role = c.roleOf(me.id) ?? CommunityRole.member;
    final List<CommunityPost> posts = c.sortedPosts;
    return ListView(padding: const EdgeInsets.fromLTRB(NxSpace.md, NxSpace.sm, NxSpace.md, 96), children: <Widget>[
      if (c.announcements.isNotEmpty || CommunityPermissions.canAnnounce(role))
        SocialSectionTitle(
          context.tx('اطلاعیه‌ها', 'Announcements'),
          trailing: CommunityPermissions.canAnnounce(role)
              ? IconButton(
                  tooltip: context.tx('اطلاعیه تازه', 'New announcement'),
                  icon: const Icon(Icons.campaign_rounded, color: NxColors.gold),
                  onPressed: () => composeAnnouncement(context, ref, c),
                )
              : null,
        ),
      for (final CommunityAnnouncement a in c.announcements.take(3))
        Padding(
          padding: const EdgeInsets.only(bottom: NxSpace.sm),
          child: GlassPanel(
            tint: NxColors.gold.withValues(alpha: 0.10),
            borderColor: NxColors.gold.withValues(alpha: 0.5),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              const Icon(Icons.campaign_rounded, color: NxColors.gold),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  Text(a.text, style: const TextStyle(fontWeight: FontWeight.w700, height: 1.4)),
                  const SizedBox(height: 4),
                  Text('${a.authorName} · ${formatDateTime(a.at)}',
                      style: const TextStyle(color: NxColors.textDim, fontSize: 11)),
                ]),
              ),
              if (CommunityPermissions.canAnnounce(role))
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () => ref.read(socialControllerProvider).deleteAnnouncement(c.id, a.id, me.id),
                ),
            ]),
          ),
        ),
      SocialSectionTitle(context.tx('فید جامعه', 'Community feed')),
      GlassPanel(
        onTap: () => composeCommunityPost(context, ref, c),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: <Widget>[
          CircleAvatar(
            radius: 16,
            backgroundColor: kSocialPalette.primary.withValues(alpha: 0.3),
            child: Text(me.name.characters.first.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900)),
          ),
          const SizedBox(width: 10),
          Expanded(
              child: Text(context.tx('برای جامعه بنویس…', 'Write to the community…'),
                  style: const TextStyle(color: NxColors.textDim))),
          Icon(Icons.send_rounded, color: kSocialPalette.primary),
        ]),
      ),
      const SizedBox(height: NxSpace.sm),
      if (posts.isEmpty)
        const Padding(
          padding: EdgeInsets.only(top: 40),
          child: SocialEmpty(
              icon: Icons.forum_rounded,
              fa: 'فید هنوز خالی است. اولین پست را تو بنویس.',
              en: 'The feed is empty. Write the first post.'),
        ),
      for (final CommunityPost p in posts)
        Padding(
          padding: const EdgeInsets.only(bottom: NxSpace.sm),
          child: _PostCard(community: c, post: p, me: me, role: role),
        ),
    ]);
  }
}

class _PostCard extends ConsumerWidget {
  const _PostCard({required this.community, required this.post, required this.me, required this.role});
  final Community community;
  final CommunityPost post;
  final SocialMe me;
  final CommunityRole role;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CommunityPost p = post;
    final bool liked = p.likedBy.contains(me.id);
    final CommunityRole? authorRole = community.roleOf(p.authorId);
    final bool canDelete = CommunityPermissions.canDeletePost(role, own: p.authorId == me.id);
    final bool canPin = CommunityPermissions.canPinPosts(role);
    final SocialController ctrl = ref.read(socialControllerProvider);
    return GlassPanel(
      borderColor: p.pinned ? kSocialPalette.secondary.withValues(alpha: 0.6) : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        Row(children: <Widget>[
          CircleAvatar(
            radius: 18,
            backgroundColor: kSocialPalette.secondary.withValues(alpha: 0.25),
            child: Text(p.authorName.isEmpty ? '?' : p.authorName.characters.first.toUpperCase(),
                style: const TextStyle(fontWeight: FontWeight.w900)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Row(children: <Widget>[
                Flexible(
                    child:
                        Text(p.authorName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800))),
                if (authorRole != null && authorRole != CommunityRole.member) ...<Widget>[
                  const SizedBox(width: 6),
                  Icon(Icons.verified_rounded, size: 14, color: roleColor(authorRole)),
                ],
              ]),
              Text(formatDateTime(p.at), style: const TextStyle(color: NxColors.textDim, fontSize: 11)),
            ]),
          ),
          if (p.pinned) Icon(Icons.push_pin_rounded, size: 18, color: kSocialPalette.secondary),
          if (canDelete || canPin)
            PopupMenuButton<String>(
              onSelected: (String v) async {
                if (v == 'pin') await ctrl.togglePin(community.id, p.id, me.id);
                if (v == 'del' && context.mounted) {
                  final bool yes = await confirmAction(context, fa: 'این پست حذف شود؟', en: 'Delete this post?');
                  if (yes) await ctrl.deletePost(community.id, p.id, me.id);
                }
              },
              itemBuilder: (BuildContext c) => <PopupMenuEntry<String>>[
                if (canPin)
                  PopupMenuItem<String>(
                      value: 'pin', child: Text(p.pinned ? c.tx('برداشتن سنجاق', 'Unpin') : c.tx('سنجاق کردن', 'Pin'))),
                if (canDelete) PopupMenuItem<String>(value: 'del', child: Text(c.tx('حذف', 'Delete'))),
              ],
            ),
        ]),
        const SizedBox(height: 10),
        Text(p.text, style: const TextStyle(height: 1.5)),
        const SizedBox(height: 6),
        Row(children: <Widget>[
          TextButton.icon(
            onPressed: () => ctrl.toggleLike(community.id, p.id, me.id),
            icon: Icon(liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: liked ? NxColors.pink : NxColors.textDim),
            label: Text('${p.likedBy.length}', style: TextStyle(color: liked ? NxColors.pink : NxColors.textDim)),
          ),
        ]),
      ]),
    );
  }
}

// ============================ Events ============================

class CommunityEventsTab extends ConsumerWidget {
  const CommunityEventsTab({super.key, required this.community});
  final Community community;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Community c = community;
    final SocialMe me = socialMe(ref);
    final CommunityRole role = c.roleOf(me.id) ?? CommunityRole.member;
    final DateTime now = DateTime.now();
    final List<CommunityEvent> events = c.sortedEvents(now);
    if (events.isEmpty) {
      return SocialEmpty(
        icon: Icons.event_rounded,
        fa: 'رویدادی برنامه‌ریزی نشده. یک شب بازی یا دورهمی بچین.',
        en: 'No events yet. Plan a game night or a meetup.',
        action: CommunityPermissions.canManageEvents(role)
            ? FilledButton.icon(
                onPressed: () => createCommunityEvent(context, ref, c),
                icon: const Icon(Icons.add_rounded),
                label: Text(context.tx('رویداد تازه', 'New event')),
              )
            : null,
      );
    }
    return ListView(padding: const EdgeInsets.fromLTRB(NxSpace.md, NxSpace.sm, NxSpace.md, 96), children: <Widget>[
      for (final CommunityEvent e in events)
        Padding(
          padding: const EdgeInsets.only(bottom: NxSpace.md),
          child: _EventCard(community: c, event: e, me: me, canManage: CommunityPermissions.canManageEvents(role)),
        ),
    ]);
  }
}

class _EventCard extends ConsumerWidget {
  const _EventCard({required this.community, required this.event, required this.me, required this.canManage});
  final Community community;
  final CommunityEvent event;
  final SocialMe me;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CommunityEvent e = event;
    final bool past = e.isPast(DateTime.now());
    final bool going = e.going.contains(me.id);
    final SocialController ctrl = ref.read(socialControllerProvider);
    final Color accent = past ? NxColors.textDim : NxColors.gold;
    return GlassPanel(
      padding: EdgeInsets.zero,
      borderColor: accent.withValues(alpha: 0.5),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        // "stage" header
        Container(
          padding: const EdgeInsets.all(NxSpace.md),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: <Color>[accent.withValues(alpha: 0.28), kSocialPalette.primary.withValues(alpha: 0.10)],
            ),
          ),
          child: Row(children: <Widget>[
            Icon(past ? Icons.history_rounded : Icons.celebration_rounded, color: accent, size: 30),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text(e.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                Text(formatDateTime(e.startsAt), style: const TextStyle(color: NxColors.textDim, fontSize: 12)),
              ]),
            ),
            if (!past)
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: <Widget>[
                Text(context.tx('تا شروع', 'Starts in'), style: const TextStyle(color: NxColors.textDim, fontSize: 10)),
                CountdownText(target: e.startsAt, style: TextStyle(color: accent, fontWeight: FontWeight.w900, fontSize: 15)),
              ])
            else
              NxPill(label: context.tx('برگزار شد', 'Ended'), color: NxColors.textDim),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(NxSpace.md, NxSpace.sm, NxSpace.md, NxSpace.sm),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
            if (e.description.isNotEmpty) ...<Widget>[
              Text(e.description, style: const TextStyle(height: 1.4)),
              const SizedBox(height: 8),
            ],
            Wrap(spacing: 6, runSpacing: 6, children: <Widget>[
              NxPill(
                  label: '${e.going.length} ${context.tx('شرکت‌کننده', 'going')}',
                  icon: Icons.how_to_reg_rounded,
                  color: kSocialPalette.secondary),
              if (e.gameId != null)
                NxPill(label: gameLabel(context, e.gameId), icon: Icons.sports_esports_rounded, color: kSocialPalette.primary),
            ]),
            const SizedBox(height: 6),
            Row(children: <Widget>[
              if (!past)
                FilterChip(
                  selected: going,
                  onSelected: (_) => ctrl.toggleRsvp(community.id, e.id, me.id),
                  label: Text(going ? context.tx('شرکت می‌کنم ✓', "I'm going ✓") : context.tx('شرکت می‌کنم؟', 'Going?')),
                  selectedColor: kSocialPalette.secondary.withValues(alpha: 0.4),
                ),
              const Spacer(),
              if (e.gameId != null)
                IconButton(
                  tooltip: context.tx('بازی در آرکید', 'Play in Arcade'),
                  icon: Icon(Icons.play_circle_fill_rounded, color: kSocialPalette.primary),
                  onPressed: () => context.push('/arcade/${e.gameId}'),
                ),
              if (canManage)
                IconButton(
                  tooltip: context.tx('حذف رویداد', 'Delete event'),
                  icon: const Icon(Icons.delete_outline_rounded, color: NxColors.textDim),
                  onPressed: () async {
                    final bool yes = await confirmAction(context, fa: 'این رویداد حذف شود؟', en: 'Delete this event?');
                    if (yes) await ctrl.deleteEvent(community.id, e.id, me.id);
                  },
                ),
            ]),
          ]),
        ),
      ]),
    );
  }
}

// ============================ Members ============================

class CommunityMembersTab extends ConsumerWidget {
  const CommunityMembersTab({super.key, required this.community});
  final Community community;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Community c = community;
    final SocialMe me = socialMe(ref);
    final CommunityRole myRole = c.roleOf(me.id) ?? CommunityRole.member;
    final List<CommunityMember> members = List<CommunityMember>.from(c.members)
      ..sort((CommunityMember a, CommunityMember b) {
        final int r = b.role.rank.compareTo(a.role.rank);
        return r != 0 ? r : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    final SocialController ctrl = ref.read(socialControllerProvider);
    final bool online = ctrl.online?.isRemote(c.id) ?? false;
    return ListView(padding: const EdgeInsets.fromLTRB(NxSpace.md, NxSpace.sm, NxSpace.md, 96), children: <Widget>[
      if (online)
        GlassPanel(
          tint: kSocialPalette.primary.withValues(alpha: 0.08),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Icon(Icons.public_rounded, color: kSocialPalette.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                context.tx(
                  'اعضا حساب‌های واقعی کاوشگران هستند و با کد دعوت یا از «کشف جوامع» می‌پیوندند. «بازیکن محلی» فقط نامی برای مسابقه‌های روی همین دستگاه است.',
                  'Members are real explorer accounts who join with the invite code or from Discover. A "local player" is only a name for same-device tournaments.',
                ),
                style: const TextStyle(height: 1.5, fontSize: 13),
              ),
            ),
          ]),
        )
      else
        GlassPanel(
          tint: kSocialPalette.primary.withValues(alpha: 0.08),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Icon(Icons.info_outline_rounded, color: kSocialPalette.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                context.tx(
                  'روی این دستگاه تو مالک جامعه هستی. اعضایی که اینجا اضافه می‌کنی «بازیکن محلی» هستند: نام‌هایی برای مسابقه‌های روی همین دستگاه، نه حساب واقعی کاوشگران دیگر.',
                  "On this device you are the owner. Members you add here are local players: names for same-device tournaments, not real accounts of other explorers.",
                ),
                style: const TextStyle(height: 1.5, fontSize: 13),
              ),
            ),
          ]),
        ),
      if (!online) const SizedBox(height: NxSpace.sm),
      if (!online)
        const OnlineOnlyNotice(
          featureFa: 'عضویت کاوشگران واقعی، درخواست عضویت و اخراج حساب‌ها',
          featureEn: 'Real explorer members, join requests and account removal',
        ),
      if (online && myRole != CommunityRole.owner)
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: NxColors.danger),
            onPressed: () async {
              final bool ok = await ctrl.leave(c.id);
              if (ok && context.mounted) Navigator.of(context).maybePop();
            },
            icon: const Icon(Icons.logout_rounded),
            label: Text(context.tx('ترک جامعه', 'Leave community')),
          ),
        ),
      SocialSectionTitle(
        '${context.tx('اعضا', 'Members')} (${members.length})',
        trailing: CommunityPermissions.canAddMembers(myRole)
            ? TextButton.icon(
                onPressed: () => addLocalPlayer(context, ref, c),
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: Text(context.tx('بازیکن محلی', 'Local player')),
              )
            : null,
      ),
      for (final CommunityMember m in members)
        Padding(
          padding: const EdgeInsets.only(bottom: NxSpace.sm),
          child: GlassPanel(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(children: <Widget>[
              CircleAvatar(
                backgroundColor: roleColor(m.role).withValues(alpha: 0.25),
                child: Text(m.name.isEmpty ? '?' : m.name.characters.first.toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.w900)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  Text(m.id == me.id ? '${m.name} (${context.tx('تو', 'you')})' : m.name,
                      overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Wrap(spacing: 6, children: <Widget>[
                    RolePill(role: m.role),
                    if (m.local)
                      NxPill(
                          label: context.tx('بازیکن محلی', 'Local player'),
                          icon: Icons.phone_android_rounded,
                          color: NxColors.textDim),
                  ]),
                ]),
              ),
              _MemberMenu(community: c, member: m, me: me, myRole: myRole, ctrl: ctrl),
            ]),
          ),
        ),
    ]);
  }
}

class _MemberMenu extends StatelessWidget {
  const _MemberMenu({required this.community, required this.member, required this.me, required this.myRole, required this.ctrl});
  final Community community;
  final CommunityMember member;
  final SocialMe me;
  final CommunityRole myRole;
  final SocialController ctrl;

  @override
  Widget build(BuildContext context) {
    final bool self = member.id == me.id;
    final List<CommunityRole> grantable = CommunityRole.values
        .where((CommunityRole r) => CommunityPermissions.canChangeRole(myRole, member.role, r, self: self))
        .toList();
    final bool canRemove = CommunityPermissions.canRemove(myRole, member.role, self: self);
    if (grantable.isEmpty && !canRemove) return const SizedBox(width: 8);
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (String v) async {
        if (v == 'remove') {
          final bool yes = await confirmAction(context, fa: '«${member.name}» حذف شود؟', en: 'Remove "${member.name}"?');
          if (yes) await ctrl.removeMember(community.id, me.id, member.id);
          return;
        }
        for (final CommunityRole r in CommunityRole.values) {
          if (r.name == v) await ctrl.changeRole(community.id, me.id, member.id, r);
        }
      },
      itemBuilder: (BuildContext c) => <PopupMenuEntry<String>>[
        for (final CommunityRole r in grantable)
          PopupMenuItem<String>(
            value: r.name,
            child: Row(children: <Widget>[
              Icon(Icons.swap_vert_rounded, size: 18, color: roleColor(r)),
              const SizedBox(width: 8),
              Text('${c.tx('نقش', 'Make')}: ${roleLabel(c, r)}'),
            ]),
          ),
        if (canRemove)
          PopupMenuItem<String>(
            value: 'remove',
            child: Row(children: <Widget>[
              const Icon(Icons.person_remove_rounded, size: 18, color: NxColors.danger),
              const SizedBox(width: 8),
              Text(c.tx('حذف از جامعه', 'Remove')),
            ]),
          ),
      ],
    );
  }
}

// ============================ About ============================

class CommunityAboutTab extends ConsumerWidget {
  const CommunityAboutTab({super.key, required this.community, required this.onShareInvite, required this.onDeleted});
  final Community community;
  final VoidCallback onShareInvite;
  final VoidCallback onDeleted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Community c = community;
    final SocialMe me = socialMe(ref);
    final CommunityRole myRole = c.roleOf(me.id) ?? CommunityRole.member;
    return ListView(padding: const EdgeInsets.fromLTRB(NxSpace.md, NxSpace.sm, NxSpace.md, 96), children: <Widget>[
      GlassPanel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          Text(c.description.isEmpty ? context.tx('بدون توضیح.', 'No description.') : c.description,
              style: const TextStyle(height: 1.5)),
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: <Widget>[
            NxPill(label: kindLabel(context, c.kind), icon: kindIcon(c.kind), color: kindColor(c.kind)),
            if (c.gameId != null)
              NxPill(label: gameLabel(context, c.gameId), icon: Icons.sports_esports_rounded, color: kSocialPalette.secondary),
            NxPill(label: formatDateTime(c.createdAt).split(' ').first, icon: Icons.cake_rounded, color: NxColors.textDim),
          ]),
        ]),
      ),
      SocialSectionTitle(context.tx('قوانین جامعه', 'Community rules')),
      if (c.rules.isEmpty)
        Text(context.tx('قانونی ثبت نشده.', 'No rules set.'), style: const TextStyle(color: NxColors.textDim))
      else
        GlassPanel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
            for (int i = 0; i < c.rules.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: kSocialPalette.primary.withValues(alpha: 0.25)),
                    child: Text('${i + 1}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(c.rules[i], style: const TextStyle(height: 1.4))),
                ]),
              ),
          ]),
        ),
      SocialSectionTitle(context.tx('دعوت و اتاق چت', 'Invite & chat room')),
      GlassPanel(
        onTap: onShareInvite,
        child: Row(children: <Widget>[
          const Icon(Icons.qr_code_2_rounded, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text(c.inviteCode, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 2)),
              Text(context.tx('کپی کد یا ارسال به ORBIT NETWORK', 'Copy the code or send it to ORBIT NETWORK'),
                  style: const TextStyle(color: NxColors.textDim, fontSize: 12)),
            ]),
          ),
          const Icon(Icons.ios_share_rounded),
        ]),
      ),
      const SizedBox(height: NxSpace.sm),
      GlassPanel(
        onTap: () => context.push('/world/orbit_network'),
        child: Row(children: <Widget>[
          const Icon(Icons.chat_bubble_rounded, color: NxColors.turquoise),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              context.tx('اتاق چت جامعه را در ORBIT NETWORK به‌صورت گروه بساز و کارت دعوت را آنجا بفرست.',
                  'Create the community chat room as a group in ORBIT NETWORK and drop the invite card there.'),
              style: const TextStyle(height: 1.4),
            ),
          ),
          const Icon(Icons.chevron_right_rounded),
        ]),
      ),
      SocialSectionTitle(context.tx('مجوزهای نقش‌ها', 'Role permissions')),
      const _PermissionMatrix(),
      if (CommunityPermissions.canDeleteCommunity(myRole)) ...<Widget>[
        const SizedBox(height: NxSpace.lg),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: NxColors.danger, side: const BorderSide(color: NxColors.danger)),
          onPressed: () async {
            final bool yes = await confirmAction(context,
                fa: 'جامعه «${c.name}» با همه پست‌ها، رویدادها و مسابقه‌ها حذف شود؟',
                en: 'Delete "${c.name}" with all its posts, events and tournaments?');
            if (!yes) return;
            final bool ok = await ref.read(socialControllerProvider).deleteCommunity(c.id, me.id);
            if (ok) onDeleted();
          },
          icon: const Icon(Icons.delete_forever_rounded),
          label: Text(context.tx('حذف جامعه', 'Delete community')),
        ),
      ],
    ]);
  }
}

class _PermissionMatrix extends StatelessWidget {
  const _PermissionMatrix();

  @override
  Widget build(BuildContext context) {
    final List<_Perm> perms = <_Perm>[
      _Perm(context.tx('ویرایش اطلاعات', 'Edit info'), CommunityPermissions.canEditInfo),
      _Perm(context.tx('اطلاعیه', 'Announce'), CommunityPermissions.canAnnounce),
      _Perm(context.tx('رویداد', 'Events'), CommunityPermissions.canManageEvents),
      _Perm(context.tx('مسابقه', 'Tournaments'), CommunityPermissions.canManageTournaments),
      _Perm(context.tx('سنجاق پست', 'Pin posts'), CommunityPermissions.canPinPosts),
      _Perm(context.tx('افزودن عضو', 'Add members'), CommunityPermissions.canAddMembers),
      _Perm(
          context.tx('اخراج عضو', 'Remove member'), (CommunityRole r) => CommunityPermissions.canRemove(r, CommunityRole.member)),
    ];
    return GlassPanel(
      padding: const EdgeInsets.all(NxSpace.sm),
      child: Table(
        columnWidths: const <int, TableColumnWidth>{0: FlexColumnWidth(2.2)},
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: <TableRow>[
          TableRow(children: <Widget>[
            const SizedBox(),
            for (final CommunityRole r in CommunityRole.values)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(roleLabel(context, r),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: roleColor(r), fontSize: 11, fontWeight: FontWeight.w800)),
              ),
          ]),
          for (final _Perm p in perms)
            TableRow(children: <Widget>[
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6), child: Text(p.label, style: const TextStyle(fontSize: 12))),
              for (final CommunityRole r in CommunityRole.values)
                Icon(
                  p.allowed(r) ? Icons.check_circle_rounded : Icons.remove_circle_outline_rounded,
                  size: 18,
                  color: p.allowed(r) ? kSocialPalette.secondary : NxColors.textDim.withValues(alpha: 0.5),
                ),
            ]),
        ],
      ),
    );
  }
}

class _Perm {
  const _Perm(this.label, this.allowed);
  final String label;
  final bool Function(CommunityRole) allowed;
}
