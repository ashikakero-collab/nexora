import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/profile/profile_service.dart';
import '../../core/settings/app_settings.dart';
import '../../core/theme/nx_theme.dart';
import '../../core/widgets/nx_widgets.dart';
import 'models/social_models.dart';
import 'state/social_controller.dart';
import 'ui/community_create_sheet.dart';
import 'ui/community_detail_page.dart';
import 'ui/social_widgets.dart';

/// SOCIAL STATION — communities, events and community tournaments (offline-first).
class SocialStationPage extends ConsumerStatefulWidget {
  const SocialStationPage({super.key});

  @override
  ConsumerState<SocialStationPage> createState() => _SocialStationPageState();
}

class _SocialStationPageState extends ConsumerState<SocialStationPage> {
  String _query = '';
  CommunityKind? _filter;

  void _open(String id) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
          builder: (BuildContext c) => CommunityDetailPage(communityId: id)),
    );
  }

  Future<void> _create() async {
    final Community? c = await showCommunityEditor(context);
    if (c != null && mounted) _open(c.id);
  }

  Future<void> _discover() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (BuildContext c) => SizedBox(
        height: MediaQuery.of(c).size.height * 0.75,
        child: _DiscoverSheet(onOpen: (String id) {
          Navigator.of(c).pop();
          _open(id);
        }),
      ),
    );
  }

  Future<void> _joinByCode() async {
    final String? raw = await askText(context,
        titleFa: 'ورود با کد دعوت',
        titleEn: 'Join with invite code',
        hintFa: 'NX-XXXXXX',
        hintEn: 'NX-XXXXXX',
        maxLength: 12);
    if (raw == null || !mounted) return;
    final String? code = InviteCode.normalize(raw);
    if (code == null) {
      socialSnack(context, 'کد دعوت معتبر نیست (نمونه: NX-7KQ2MZ).',
          'Invalid invite code (e.g. NX-7KQ2MZ).');
      return;
    }
    final Community? c =
        await ref.read(socialControllerProvider).findByCode(code);
    if (!mounted) return;
    if (c != null) {
      if (ref.read(socialControllerProvider).isOnline) {
        await ref.read(socialControllerProvider).refresh();
        if (!mounted) return;
        socialSnack(
            context, 'به «${c.name}» پیوستی.', 'You joined "${c.name}".');
      } else {
        socialSnack(context, 'این جامعه روی همین دستگاه است؛ باز شد.',
            'This community lives on this device — opened.');
      }
      _open(c.id);
      return;
    }
    if (ref.read(socialControllerProvider).isOnline) {
      socialSnack(context, 'جامعه‌ای با این کد پیدا نشد.',
          'No community has this code.');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext c) => Padding(
        padding:
            const EdgeInsets.fromLTRB(NxSpace.md, 0, NxSpace.md, NxSpace.lg),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(code,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2)),
              const SizedBox(height: 12),
              const OnlineOnlyNotice(
                featureFa: 'پیوستن به جوامع دیگر کاوشگران با کد دعوت',
                featureEn:
                    "Joining other explorers' communities by invite code",
              ),
            ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final SocialController ctrl = ref.watch(socialControllerProvider);
    final ProfileService profile = ref.watch(profileProvider);
    final NxThemeColors visual = NxThemeColors.of(context);
    final List<Community> all = ctrl.communities;
    final List<Community> shown = all
        .where((Community c) =>
            (_filter == null || c.kind == _filter) && c.matches(_query))
        .toList();
    final DateTime now = DateTime.now();
    CommunityEvent? next;
    Community? nextOwner;
    for (final c in all) {
      final CommunityEvent? e = c.nextEvent(now);
      if (e != null && (next == null || e.startsAt.isBefore(next.startsAt))) {
        next = e;
        nextOwner = c;
      }
    }
    final int running = all.fold<int>(
        0,
        (int s, Community c) =>
            s +
            c.tournaments.where((CommunityTournament t) => !t.finished).length);

    return NxWorldScaffold(
      title: 'SOCIAL STATION',
      palette: kSocialPalette,
      actions: <Widget>[
        if (ctrl.isOnline)
          IconButton(
            tooltip: context.tx('کشف جوامع', 'Discover communities'),
            icon: const Icon(Icons.travel_explore_rounded),
            onPressed: _discover,
          ),
        IconButton(
          tooltip: context.tx('ورود با کد دعوت', 'Join with code'),
          icon: const Icon(Icons.vpn_key_rounded),
          onPressed: _joinByCode,
        ),
      ],
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: visual.accent,
        foregroundColor: visual.background,
        onPressed: _create,
        icon: const Icon(Icons.add_rounded),
        label: Text(context.tx('ساخت جامعه', 'New community'),
            style: const TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: ctrl.loading
          ? Center(
              child: GlassPanel(
                child:
                    Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                  CircularProgressIndicator(color: visual.accent),
                  const SizedBox(height: NxSpace.md),
                  Text(
                      context.tx('در حال آماده‌سازی ایستگاه…',
                          'Preparing your station…'),
                      style: TextStyle(color: visual.muted)),
                ]),
              ),
            )
          : CustomScrollView(slivers: <Widget>[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                    NxSpace.md, kToolbarHeight + NxSpace.sm, NxSpace.md, 0),
                sliver: SliverToBoxAdapter(
                  child: _Hero(
                    communities: all.length,
                    tournaments: running,
                    joined: profile.counter('social.joined'),
                    next: next,
                    nextCommunity: nextOwner,
                    onOpenNext:
                        nextOwner == null ? null : () => _open(nextOwner!.id),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                    NxSpace.md, NxSpace.md, NxSpace.md, 0),
                sliver: SliverToBoxAdapter(
                  child: TextField(
                    onChanged: (String v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search_rounded),
                      hintText: context.tx('جستجوی جامعه، توضیح یا کد دعوت',
                          'Search communities, descriptions or codes'),
                      filled: true,
                      fillColor: visual.surface.withValues(alpha: 0.88),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(NxRadius.md),
                          borderSide: BorderSide.none),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 54,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                        horizontal: NxSpace.md, vertical: 8),
                    children: <Widget>[
                      _chip(context, null, context.tx('همه', 'All'),
                          Icons.blur_on_rounded, kSocialPalette.primary),
                      for (final CommunityKind k in CommunityKind.values)
                        _chip(context, k, kindLabel(context, k), kindIcon(k),
                            kindColor(k)),
                    ],
                  ),
                ),
              ),
              if (shown.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: SocialEmpty(
                    icon: Icons.diversity_3_rounded,
                    fa: all.isEmpty
                        ? 'هنوز جامعه‌ای نساخته‌ای. اولین ایستگاه گردهمایی‌ات را بساز: رویداد، مسابقه و فید اختصاصی.'
                        : 'جامعه‌ای با این جستجو پیدا نشد.',
                    en: all.isEmpty
                        ? 'No communities yet. Build your first gathering station: events, tournaments and its own feed.'
                        : 'No community matches this search.',
                    action: all.isEmpty
                        ? FilledButton.icon(
                            onPressed: _create,
                            icon: const Icon(Icons.add_rounded),
                            label: Text(
                                context.tx('ساخت جامعه', 'Create community')),
                          )
                        : null,
                  ),
                )
              else
                SliverPadding(
                  padding:
                      const EdgeInsets.fromLTRB(NxSpace.md, 0, NxSpace.md, 96),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (BuildContext c, int i) => Padding(
                        padding: const EdgeInsets.only(bottom: NxSpace.md),
                        child: CommunityCard(
                            community: shown[i],
                            myId: profile.explorerId,
                            onTap: () => _open(shown[i].id)),
                      ),
                      childCount: shown.length,
                    ),
                  ),
                ),
            ]),
    );
  }

  Widget _chip(BuildContext context, CommunityKind? k, String label,
      IconData icon, Color color) {
    final bool sel = _filter == k;
    final NxThemeColors visual = NxThemeColors.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: ChoiceChip(
        selected: sel,
        onSelected: (_) => setState(() => _filter = k),
        avatar: Icon(icon, size: 16, color: sel ? visual.background : color),
        label: Text(label),
        selectedColor: visual.accent,
        labelStyle: TextStyle(
            color: sel ? visual.background : visual.text,
            fontWeight: FontWeight.w700),
        backgroundColor: color.withValues(alpha: 0.12),
        side: BorderSide(color: color.withValues(alpha: 0.5)),
        showCheckmark: false,
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.communities,
    required this.tournaments,
    required this.joined,
    required this.next,
    required this.nextCommunity,
    required this.onOpenNext,
  });
  final int communities;
  final int tournaments;
  final int joined;
  final CommunityEvent? next;
  final Community? nextCommunity;
  final VoidCallback? onOpenNext;

  @override
  Widget build(BuildContext context) {
    final CommunityEvent? e = next;
    final NxThemeColors visual = NxThemeColors.of(context);
    return GlassPanel(
      tint: visual.accent.withValues(alpha: 0.08),
      borderColor: visual.border.withValues(alpha: 0.76),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(children: <Widget>[
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                      colors: <Color>[visual.accent, visual.accentSecondary]),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                        color: visual.accent.withValues(alpha: 0.38),
                        blurRadius: 18)
                  ],
                ),
                child:
                    Icon(Icons.hub_rounded, color: visual.background, size: 30),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                          context.tx(
                              'ایستگاه گردهمایی', 'The gathering station'),
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 2),
                      Text(
                        context.tx('جامعه بساز، رویداد بچین، جام برگزار کن.',
                            'Build communities, plan events, host cups.'),
                        style: const TextStyle(
                            color: NxColors.textDim, fontSize: 12),
                      ),
                    ]),
              ),
            ]),
            const SizedBox(height: 14),
            Row(children: <Widget>[
              Expanded(
                  child: _Stat(
                      value: '$communities',
                      label: context.tx('جامعه', 'Communities'),
                      color: visual.accent)),
              Expanded(
                  child: _Stat(
                      value: '$tournaments',
                      label: context.tx('جام فعال', 'Live cups'),
                      color: visual.accentSecondary)),
              Expanded(
                  child: _Stat(
                      value: '$joined',
                      label: context.tx('ساخته‌شده', 'Founded'),
                      color: visual.text)),
            ]),
            if (e != null && nextCommunity != null) ...<Widget>[
              const SizedBox(height: 12),
              GlassPanel(
                blur: false,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                tint: const Color(0x22000000),
                onTap: onOpenNext,
                child: Row(children: <Widget>[
                  const Icon(Icons.event_available_rounded,
                      color: NxColors.gold),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(e.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800)),
                          Text(nextCommunity!.name,
                              style: const TextStyle(
                                  color: NxColors.textDim, fontSize: 12)),
                        ]),
                  ),
                  CountdownText(
                      target: e.startsAt,
                      style: const TextStyle(
                          fontWeight: FontWeight.w900, color: NxColors.gold)),
                ]),
              ),
            ],
          ]),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, required this.color});
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(children: <Widget>[
        Text(value,
            style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.w900, color: color)),
        Text(label,
            style: const TextStyle(color: NxColors.textDim, fontSize: 11)),
      ]);
}

/// Large community card for the station list.
class CommunityCard extends StatelessWidget {
  const CommunityCard(
      {super.key,
      required this.community,
      required this.myId,
      required this.onTap});
  final Community community;
  final String myId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Community c = community;
    final Color accent = kindColor(c.kind);
    final CommunityRole? role = c.roleOf(myId);
    final CommunityEvent? next = c.nextEvent(DateTime.now());
    return GlassPanel(
      onTap: onTap,
      padding: EdgeInsets.zero,
      borderColor: accent.withValues(alpha: 0.45),
      child: Stack(children: <Widget>[
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: AlignmentDirectional.topStart,
                end: AlignmentDirectional.bottomEnd,
                colors: <Color>[
                  accent.withValues(alpha: 0.20),
                  Colors.transparent
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(NxSpace.md),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(children: <Widget>[
                  Hero(
                      tag: 'badge_${c.id}',
                      child: CommunityBadge(
                          badgeId: c.badgeId, size: 64, glow: accent)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(c.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w900)),
                          const SizedBox(height: 6),
                          Wrap(spacing: 6, runSpacing: 6, children: <Widget>[
                            NxPill(
                                label: kindLabel(context, c.kind),
                                icon: kindIcon(c.kind),
                                color: accent),
                            if (role != null) RolePill(role: role),
                          ]),
                        ]),
                  ),
                ]),
                if (c.description.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 10),
                  Text(c.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: NxColors.textDim)),
                ],
                const SizedBox(height: 12),
                Row(children: <Widget>[
                  _Meta(
                      icon: Icons.people_alt_rounded,
                      text: '${c.members.length}'),
                  _Meta(icon: Icons.forum_rounded, text: '${c.posts.length}'),
                  _Meta(icon: Icons.event_rounded, text: '${c.events.length}'),
                  _Meta(
                      icon: Icons.emoji_events_rounded,
                      text: '${c.tournaments.length}'),
                  const Spacer(),
                  if (next != null) ...<Widget>[
                    const Icon(Icons.timer_rounded,
                        size: 14, color: NxColors.gold),
                    const SizedBox(width: 4),
                    CountdownText(
                        target: next.startsAt,
                        style: const TextStyle(
                            color: NxColors.gold,
                            fontWeight: FontWeight.w800,
                            fontSize: 12)),
                  ],
                ]),
              ]),
        ),
      ]),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.only(end: 12),
        child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Icon(icon, size: 15, color: NxColors.textDim),
          const SizedBox(width: 3),
          Text(text,
              style: const TextStyle(
                  color: NxColors.textDim,
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
        ]),
      );
}

/// Public communities of other explorers (online) — join with one tap.
class _DiscoverSheet extends ConsumerStatefulWidget {
  const _DiscoverSheet({required this.onOpen});
  final void Function(String id) onOpen;

  @override
  ConsumerState<_DiscoverSheet> createState() => _DiscoverSheetState();
}

class _DiscoverSheetState extends ConsumerState<_DiscoverSheet> {
  List<Community>? _list;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final List<Community> l =
        await ref.read(socialControllerProvider).discover(query: _q);
    if (mounted) setState(() => _list = l);
  }

  @override
  Widget build(BuildContext context) {
    final List<Community>? l = _list;
    return Padding(
      padding: const EdgeInsets.fromLTRB(NxSpace.md, 0, NxSpace.md, NxSpace.md),
      child: Column(children: <Widget>[
        Text(context.tx('کشف جوامع', 'Discover communities'),
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
        const SizedBox(height: 8),
        TextField(
          decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: context.tx('نام جامعه…', 'Community name…')),
          onChanged: (String v) {
            _q = v;
            _load();
          },
        ),
        const SizedBox(height: 8),
        Expanded(
          child: l == null
              ? const Center(child: CircularProgressIndicator())
              : l.isEmpty
                  ? Center(
                      child: Text(
                          context.tx('جامعه‌ی عمومی تازه‌ای پیدا نشد.',
                              'No new public communities found.'),
                          style: const TextStyle(color: NxColors.textDim)),
                    )
                  : ListView(children: <Widget>[
                      for (final Community c in l)
                        ListTile(
                          leading:
                              Icon(kindIcon(c.kind), color: kindColor(c.kind)),
                          title: Text(c.name,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800)),
                          subtitle: Text(
                            '${kindLabel(context, c.kind)} · ${c.members.where((CommunityMember m) => !m.local).length} ${context.tx('عضو', 'members')}'
                            '${c.description.isEmpty ? '' : ' · ${c.description}'}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: FilledButton(
                            onPressed: () async {
                              final bool ok = await ref
                                  .read(socialControllerProvider)
                                  .joinOpen(c.id);
                              if (ok) widget.onOpen(c.id);
                            },
                            child: Text(context.tx('پیوستن', 'Join')),
                          ),
                        ),
                    ]),
        ),
      ]),
    );
  }
}
