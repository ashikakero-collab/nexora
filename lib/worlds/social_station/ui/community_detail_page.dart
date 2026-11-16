import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/app_settings.dart';
import '../../../core/theme/nx_theme.dart';
import '../../../core/widgets/nx_widgets.dart';
import '../models/social_models.dart';
import '../state/social_controller.dart';
import 'community_create_sheet.dart';
import 'community_tabs.dart';
import 'social_widgets.dart';
import 'tournament_bracket_view.dart';

/// The shareable invitation text for a community.
String inviteText(BuildContext context, Community c) => context.tx(
      'به جامعه «${c.name}» در NEXORA بپیوند! 🚀\nکد دعوت: ${c.inviteCode}\nدر Social Station روی «ورود با کد دعوت» بزن.',
      'Join "${c.name}" on NEXORA! 🚀\nInvite code: ${c.inviteCode}\nIn Social Station tap "Join with code".',
    );

/// Invite sheet: copy code, copy shareable text, drop the card into ORBIT NETWORK.
Future<void> showInviteSheet(BuildContext context, WidgetRef ref, Community c) {
  final String text = inviteText(context, c);
  final NxThemeColors visual = NxThemeColors.of(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: visual.surfaceRaised,
    builder: (BuildContext bc) => SingleChildScrollView(
      padding: const EdgeInsets.all(NxSpace.md),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Center(
                child: CommunityBadge(
                    badgeId: c.badgeId, size: 72, glow: kindColor(c.kind))),
            const SizedBox(height: 8),
            Text(bc.tx('دعوت به ${c.name}', 'Invite to ${c.name}'),
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            GlassPanel(
              tint: visual.accent.withValues(alpha: 0.12),
              child: SelectableText(c.inviteCode,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 4,
                      color: visual.accent)),
            ),
            const SizedBox(height: 10),
            GlassPanel(
                blur: false,
                child: Text(text, style: const TextStyle(height: 1.5))),
            const SizedBox(height: 12),
            Row(children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: c.inviteCode));
                    if (bc.mounted)
                      socialSnack(bc, 'کد کپی شد.', 'Code copied.');
                  },
                  icon: const Icon(Icons.copy_rounded),
                  label: Text(bc.tx('کپی کد', 'Copy code')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: text));
                    if (bc.mounted)
                      socialSnack(bc, 'متن دعوت کپی شد؛ هرجا خواستی بفرست.',
                          'Invite text copied — paste it anywhere.');
                  },
                  icon: const Icon(Icons.ios_share_rounded),
                  label: Text(bc.tx('کپی متن دعوت', 'Copy invite')),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: () async {
                await ref
                    .read(socialControllerProvider)
                    .shareInviteToOrbit(c, text);
                if (bc.mounted) {
                  socialSnack(
                      bc,
                      'کارت دعوت به صندوق اشتراک ORBIT NETWORK رفت.',
                      'Invite card sent to the ORBIT NETWORK share inbox.');
                }
              },
              icon: const Icon(Icons.send_rounded),
              label: Text(
                  bc.tx('ارسال به ORBIT NETWORK', 'Send to ORBIT NETWORK')),
            ),
            const SizedBox(height: 12),
            if (!(ref.read(socialControllerProvider).online?.isRemote(c.id) ??
                false))
              const OnlineOnlyNotice(
                featureFa: 'پیوستن کاوشگران دیگر با این کد',
                featureEn: 'Other explorers joining with this code',
              )
            else
              Text(
                bc.tx('هر کاوشگری با این کد به جامعه می‌پیوندد.',
                    'Any explorer can join with this code.'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: NxColors.textDim),
              ),
          ]),
    ),
  );
}

/// Community home with Feed / Events / Tournaments / Members / About tabs.
class CommunityDetailPage extends ConsumerStatefulWidget {
  const CommunityDetailPage({super.key, required this.communityId});
  final String communityId;

  @override
  ConsumerState<CommunityDetailPage> createState() =>
      _CommunityDetailPageState();
}

class _CommunityDetailPageState extends ConsumerState<CommunityDetailPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 5, vsync: this);

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging && mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Widget? _fab(Community c, CommunityRole role) {
    final NxThemeColors visual = NxThemeColors.of(context);
    switch (_tabs.index) {
      case 0:
        return FloatingActionButton(
          backgroundColor: visual.accent,
          foregroundColor: visual.background,
          tooltip: context.tx('پست تازه', 'New post'),
          onPressed: () => composeCommunityPost(context, ref, c),
          child: const Icon(Icons.edit_rounded),
        );
      case 1:
        if (!CommunityPermissions.canManageEvents(role)) return null;
        return FloatingActionButton(
          backgroundColor: visual.accentSecondary,
          foregroundColor: visual.background,
          tooltip: context.tx('رویداد تازه', 'New event'),
          onPressed: () => createCommunityEvent(context, ref, c),
          child: const Icon(Icons.event_rounded),
        );
      case 2:
        if (!CommunityPermissions.canManageTournaments(role)) return null;
        return FloatingActionButton(
          backgroundColor: visual.accentSecondary,
          foregroundColor: visual.background,
          tooltip: context.tx('مسابقه تازه', 'New tournament'),
          onPressed: () => createCommunityTournament(context, ref, c),
          child: const Icon(Icons.emoji_events_rounded),
        );
      case 3:
        if (!CommunityPermissions.canAddMembers(role)) return null;
        return FloatingActionButton(
          backgroundColor: visual.accent,
          foregroundColor: visual.background,
          tooltip: context.tx('بازیکن محلی', 'Local player'),
          onPressed: () => addLocalPlayer(context, ref, c),
          child: const Icon(Icons.person_add_alt_1_rounded),
        );
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final SocialController ctrl = ref.watch(socialControllerProvider);
    final Community? c = ctrl.byId(widget.communityId);
    if (c == null) {
      return NxWorldScaffold(
        title: 'SOCIAL STATION',
        palette: kSocialPalette,
        showWallet: false,
        body: ctrl.loading
            ? const Center(child: CircularProgressIndicator())
            : SocialEmpty(
                icon: Icons.group_off_rounded,
                fa: 'این جامعه دیگر وجود ندارد.',
                en: 'This community no longer exists.',
                action: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(context.tx('بازگشت', 'Back'))),
              ),
      );
    }
    final SocialMe me = socialMe(ref);
    final CommunityRole role = c.roleOf(me.id) ?? CommunityRole.member;
    final NxThemeColors visual = NxThemeColors.of(context);
    final Color accent = kindColor(c.kind);
    return NxWorldScaffold(
      title: 'SOCIAL STATION',
      palette: kSocialPalette,
      showWallet: false,
      actions: <Widget>[
        IconButton(
          tooltip: context.tx('دعوت', 'Invite'),
          icon: const Icon(Icons.person_add_rounded),
          onPressed: () => showInviteSheet(context, ref, c),
        ),
        if (CommunityPermissions.canEditInfo(role))
          IconButton(
            tooltip: context.tx('ویرایش', 'Edit'),
            icon: const Icon(Icons.tune_rounded),
            onPressed: () => showCommunityEditor(context, existing: c),
          ),
      ],
      floatingActionButton: _fab(c, role),
      body: Column(children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
              NxSpace.md, kToolbarHeight + NxSpace.sm, NxSpace.md, 0),
          child: GlassPanel(
            tint: accent.withValues(alpha: 0.10),
            borderColor: accent.withValues(alpha: 0.45),
            padding: const EdgeInsets.all(12),
            child: Row(children: <Widget>[
              Hero(
                  tag: 'badge_${c.id}',
                  child: CommunityBadge(
                      badgeId: c.badgeId, size: 72, glow: accent)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(c.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 6),
                      Wrap(spacing: 6, runSpacing: 6, children: <Widget>[
                        NxPill(
                            label: kindLabel(context, c.kind),
                            icon: kindIcon(c.kind),
                            color: accent),
                        RolePill(role: role),
                        NxPill(
                            label: '${c.members.length}',
                            icon: Icons.people_alt_rounded,
                            color: NxColors.textDim),
                      ]),
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: () async {
                          await Clipboard.setData(
                              ClipboardData(text: c.inviteCode));
                          if (context.mounted)
                            socialSnack(context, 'کد دعوت کپی شد.',
                                'Invite code copied.');
                        },
                        child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Icon(Icons.vpn_key_rounded,
                                  size: 14, color: kSocialPalette.primary),
                              const SizedBox(width: 4),
                              Text(c.inviteCode,
                                  style: TextStyle(
                                      color: kSocialPalette.primary,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.5)),
                              const SizedBox(width: 4),
                              const Icon(Icons.copy_rounded,
                                  size: 13, color: NxColors.textDim),
                            ]),
                      ),
                    ]),
              ),
            ]),
          ),
        ),
        TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: visual.accent,
          labelColor: visual.accent,
          unselectedLabelColor: visual.muted,
          indicatorSize: TabBarIndicatorSize.label,
          dividerColor: Colors.transparent,
          tabs: <Widget>[
            Tab(
                icon: const Icon(Icons.dynamic_feed_rounded, size: 20),
                text: context.tx('فید', 'Feed')),
            Tab(
                icon: const Icon(Icons.event_rounded, size: 20),
                text: context.tx('رویدادها', 'Events')),
            Tab(
                icon: const Icon(Icons.emoji_events_rounded, size: 20),
                text: context.tx('مسابقه‌ها', 'Tournaments')),
            Tab(
                icon: const Icon(Icons.groups_rounded, size: 20),
                text: context.tx('اعضا', 'Members')),
            Tab(
                icon: const Icon(Icons.info_rounded, size: 20),
                text: context.tx('درباره', 'About')),
          ],
        ),
        Expanded(
          child: TabBarView(controller: _tabs, children: <Widget>[
            CommunityFeedTab(community: c),
            CommunityEventsTab(community: c),
            CommunityTournamentsTab(community: c),
            CommunityMembersTab(community: c),
            CommunityAboutTab(
              community: c,
              onShareInvite: () => showInviteSheet(context, ref, c),
              onDeleted: () {
                if (mounted) Navigator.of(context).pop();
              },
            ),
          ]),
        ),
      ]),
    );
  }
}
