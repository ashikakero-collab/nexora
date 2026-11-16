import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/profile/profile_service.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/theme/nx_theme.dart';
import '../../../core/widgets/nx_widgets.dart';
import '../../orbit_network/models/arcade_refs.dart';
import '../models/social_models.dart';
import '../models/tournament_bracket.dart';
import '../state/social_controller.dart';
import 'social_widgets.dart';

String roundName(BuildContext context, int round, int roundCount) {
  final int fromEnd = roundCount - 1 - round;
  if (fromEnd == 0) return context.tx('فینال', 'Final');
  if (fromEnd == 1) return context.tx('نیمه‌نهایی', 'Semi-final');
  if (fromEnd == 2) return context.tx('یک‌چهارم نهایی', 'Quarter-final');
  return context.tx('دور ${round + 1}', 'Round ${round + 1}');
}

/// Sheet to create a community tournament from members (local players).
Future<void> createCommunityTournament(BuildContext context, WidgetRef ref, Community c) async {
  final TextEditingController name = TextEditingController(text: '${c.name} Cup');
  String gameId = c.gameId ?? kArcadeGames.first.id;
  final Set<String> picked = c.members.map((CommunityMember m) => m.name).toSet();
  final bool? ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: const Color(0xF20B2B33),
    builder: (BuildContext bc) => StatefulBuilder(
      builder: (BuildContext sc, StateSetter set) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(sc).viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(NxSpace.md),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
            Row(children: <Widget>[
              const Icon(Icons.emoji_events_rounded, color: NxColors.gold, size: 30),
              const SizedBox(width: 10),
              Text(sc.tx('مسابقه اختصاصی جامعه', 'Community tournament'), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
            ]),
            const SizedBox(height: 12),
            TextField(controller: name, maxLength: 40, decoration: InputDecoration(labelText: sc.tx('نام جام', 'Cup name'))),
            SocialSectionTitle(sc.tx('بازی', 'Game')),
            Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
              for (final ArcadeGameRef g in kArcadeGames)
                ChoiceChip(
                  selected: gameId == g.id,
                  onSelected: (_) => set(() => gameId = g.id),
                  label: Text(sc.tx(g.nameFa, g.nameEn)),
                  selectedColor: NxColors.gold,
                  showCheckmark: false,
                  labelStyle: TextStyle(color: gameId == g.id ? NxColors.navyDeep : NxColors.iceWhite, fontWeight: FontWeight.w700),
                ),
            ]),
            SocialSectionTitle('${sc.tx('شرکت‌کنندگان', 'Players')} (${picked.length})'),
            Text(
              sc.tx('بازی‌ها روی همین دستگاه انجام می‌شوند و نتیجه را بعد از هر بازی ثبت می‌کنی.',
                  'Matches are played on this device; you enter each result after playing.'),
              style: const TextStyle(color: NxColors.textDim, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
              for (final CommunityMember m in c.members)
                FilterChip(
                  selected: picked.contains(m.name),
                  onSelected: (bool v) => set(() {
                    if (v) {
                      picked.add(m.name);
                    } else {
                      picked.remove(m.name);
                    }
                  }),
                  label: Text(m.name),
                ),
            ]),
            if (c.members.length < 2)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  sc.tx('برای مسابقه دست‌کم ۲ عضو لازم است؛ از تب اعضا بازیکن محلی اضافه کن.',
                      'A tournament needs at least 2 members — add local players in the Members tab.'),
                  style: const TextStyle(color: NxColors.gold),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: NxColors.gold, foregroundColor: NxColors.navyDeep, padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: picked.length >= TournamentBracket.minPlayers ? () => Navigator.pop(bc, true) : null,
              icon: const Icon(Icons.account_tree_rounded),
              label: Text(sc.tx('ساخت جدول', 'Build bracket'), style: const TextStyle(fontWeight: FontWeight.w900)),
            ),
          ]),
        ),
      ),
    ),
  );
  final String n = name.text;
  name.dispose();
  if (ok != true) return;
  final String? err = await ref.read(socialControllerProvider).createTournament(
        c.id,
        actorId: socialMe(ref).id,
        name: n,
        gameId: gameId,
        players: c.members.map((CommunityMember m) => m.name).where(picked.contains).toList(),
      );
  if (!context.mounted) return;
  if (err == null) {
    socialSnack(context, 'جدول مسابقه ساخته شد.', 'Bracket created.');
  } else if (err == 'perm') {
    socialSnack(context, 'فقط ناظر به بالا مسابقه می‌سازد.', 'Only moderators and up can create tournaments.');
  } else {
    socialSnack(context, 'تعداد یا نام بازیکنان معتبر نیست.', 'Invalid player count or names.');
  }
}

class CommunityTournamentsTab extends ConsumerWidget {
  const CommunityTournamentsTab({super.key, required this.community});
  final Community community;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Community c = community;
    final CommunityRole role = c.roleOf(socialMe(ref).id) ?? CommunityRole.member;
    if (c.tournaments.isEmpty) {
      return SocialEmpty(
        icon: Icons.emoji_events_rounded,
        fa: 'هنوز جامی برگزار نشده. اعضا را جمع کن و یک جدول حذفی بساز.',
        en: 'No cups yet. Gather members and build a knockout bracket.',
        action: CommunityPermissions.canManageTournaments(role)
            ? FilledButton.icon(
                onPressed: () => createCommunityTournament(context, ref, c),
                icon: const Icon(Icons.add_rounded),
                label: Text(context.tx('مسابقه تازه', 'New tournament')),
              )
            : null,
      );
    }
    return ListView(padding: const EdgeInsets.fromLTRB(NxSpace.md, NxSpace.sm, NxSpace.md, 96), children: <Widget>[
      for (final CommunityTournament t in c.tournaments)
        Padding(
          padding: const EdgeInsets.only(bottom: NxSpace.md),
          child: GlassPanel(
            onTap: () => Navigator.of(context).push<void>(MaterialPageRoute<void>(
              builder: (BuildContext bc) => TournamentPage(communityId: c.id, tournamentId: t.id),
            )),
            borderColor: (t.finished ? NxColors.gold : kSocialPalette.primary).withValues(alpha: 0.5),
            child: Row(children: <Widget>[
              Icon(t.finished ? Icons.emoji_events_rounded : Icons.account_tree_rounded,
                  size: 38, color: t.finished ? NxColors.gold : kSocialPalette.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  Text(t.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 2),
                  Text(
                    '${gameLabel(context, t.gameId)} · ${t.bracket.players.length} ${context.tx('بازیکن', 'players')}',
                    style: const TextStyle(color: NxColors.textDim, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      minHeight: 6,
                      value: t.bracket.totalMatches == 0 ? 1 : t.bracket.playedMatches / t.bracket.totalMatches,
                      backgroundColor: const Color(0x22FFFFFF),
                      color: t.finished ? NxColors.gold : kSocialPalette.secondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    t.finished
                        ? '${context.tx('قهرمان', 'Champion')}: ${t.bracket.champion}'
                        : '${t.bracket.playedMatches}/${t.bracket.totalMatches} ${context.tx('بازی انجام شده', 'matches played')}',
                    style: TextStyle(color: t.finished ? NxColors.gold : NxColors.textDim, fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ]),
              ),
              const Icon(Icons.chevron_right_rounded),
            ]),
          ),
        ),
    ]);
  }
}

/// Full bracket page: play in Arcade, then enter the result.
class TournamentPage extends ConsumerWidget {
  const TournamentPage({super.key, required this.communityId, required this.tournamentId});
  final String communityId;
  final String tournamentId;

  Future<void> _enterResult(BuildContext context, WidgetRef ref, CommunityTournament t, MatchRef at) async {
    final BracketMatch m = t.bracket.rounds[at.round][at.index];
    final String? a = m.a;
    final String? b = m.b;
    if (a == null || b == null) return;
    final bool wasFinished = t.finished;
    final String? winner = await showDialog<String>(
      context: context,
      builder: (BuildContext c) => SimpleDialog(
        title: Text(c.tx('برنده این بازی کیست؟', 'Who won this match?')),
        children: <Widget>[
          for (final String p in <String>[a, b])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, p),
              child: Row(children: <Widget>[
                Icon(m.winner == p ? Icons.emoji_events_rounded : Icons.person_rounded,
                    color: m.winner == p ? NxColors.gold : kSocialPalette.primary),
                const SizedBox(width: 10),
                Text(p, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ]),
            ),
        ],
      ),
    );
    if (winner == null) return;
    final SocialController ctrl = ref.read(socialControllerProvider);
    final bool ok = await ctrl.recordResult(communityId, tournamentId, socialMe(ref).id, at, winner);
    if (!context.mounted) return;
    if (!ok) {
      socialSnack(context, 'ثبت نتیجه ممکن نشد.', 'Could not record the result.');
      return;
    }
    final Community? c = ctrl.byId(communityId);
    CommunityTournament? now;
    for (final CommunityTournament x in c?.tournaments ?? const <CommunityTournament>[]) {
      if (x.id == tournamentId) now = x;
    }
    if (!wasFinished && now != null && now.finished) {
      final AwardOutcome o = ref.read(profileProvider).award(
            'social.tournament',
            xp: 40,
            coins: 15,
            fa: 'جام «${now.name}» به پایان رسید؛ قهرمان: ${now.bracket.champion}',
            en: 'Cup "${now.name}" finished — champion: ${now.bracket.champion}',
          );
      await showDialog<void>(
        context: context,
        builder: (BuildContext dc) => AlertDialog(
          icon: const Icon(Icons.emoji_events_rounded, color: NxColors.gold, size: 56),
          title: Text('${dc.tx('قهرمان', 'Champion')}: ${now!.bracket.champion}', textAlign: TextAlign.center),
          content: Text(dc.tx('+${o.xp} XP برای برگزاری مسابقه', '+${o.xp} XP for hosting the cup'), textAlign: TextAlign.center),
          actions: <Widget>[FilledButton(onPressed: () => Navigator.pop(dc), child: Text(dc.tx('عالی', 'Great')))],
        ),
      );
      if (context.mounted) await showAwardOutcome(context, o);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SocialController ctrl = ref.watch(socialControllerProvider);
    final Community? c = ctrl.byId(communityId);
    CommunityTournament? t;
    for (final CommunityTournament x in c?.tournaments ?? const <CommunityTournament>[]) {
      if (x.id == tournamentId) t = x;
    }
    if (c == null || t == null) {
      return NxWorldScaffold(
        title: 'SOCIAL STATION',
        palette: kSocialPalette,
        showWallet: false,
        body: SocialEmpty(icon: Icons.emoji_events_outlined, fa: 'این مسابقه حذف شده است.', en: 'This tournament was deleted.'),
      );
    }
    final CommunityTournament tour = t;
    final CommunityRole role = c.roleOf(socialMe(ref).id) ?? CommunityRole.member;
    final bool canManage = CommunityPermissions.canManageTournaments(role);
    final List<MatchRef> next = tour.bracket.playable;
    return NxWorldScaffold(
      title: tour.name.toUpperCase(),
      palette: kSocialPalette,
      showWallet: false,
      actions: <Widget>[
        if (canManage)
          IconButton(
            tooltip: context.tx('حذف مسابقه', 'Delete tournament'),
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () async {
              final bool yes = await confirmAction(context, fa: 'این مسابقه حذف شود؟', en: 'Delete this tournament?');
              if (!yes) return;
              await ctrl.deleteTournament(communityId, tournamentId, socialMe(ref).id);
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
      ],
      body: ListView(padding: const EdgeInsets.fromLTRB(NxSpace.md, NxSpace.sm, NxSpace.md, NxSpace.xl), children: <Widget>[
        if (tour.finished)
          GlassPanel(
            tint: NxColors.gold.withValues(alpha: 0.14),
            borderColor: NxColors.gold,
            child: Column(children: <Widget>[
              const Icon(Icons.emoji_events_rounded, color: NxColors.gold, size: 64),
              Text(context.tx('قهرمان', 'Champion'), style: const TextStyle(color: NxColors.textDim)),
              Text(tour.bracket.champion ?? '', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: NxColors.gold)),
            ]),
          )
        else
          GlassPanel(
            child: Row(children: <Widget>[
              Icon(Icons.sports_esports_rounded, color: kSocialPalette.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  context.tx('هر بازی را در آرکید روی همین دستگاه انجام بده و بعد برنده را اینجا ثبت کن.',
                      'Play each match in the Arcade on this device, then record the winner here.'),
                  style: const TextStyle(height: 1.4),
                ),
              ),
            ]),
          ),
        if (next.isNotEmpty) ...<Widget>[
          SocialSectionTitle(context.tx('بازی‌های آماده', 'Ready matches')),
          for (final MatchRef r in next)
            Padding(
              padding: const EdgeInsets.only(bottom: NxSpace.sm),
              child: GlassPanel(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
                  Text(roundName(context, r.round, tour.bracket.roundCount),
                      style: TextStyle(color: kSocialPalette.secondary, fontSize: 12, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text('${tour.bracket.rounds[r.round][r.index].a}  ⚔  ${tour.bracket.rounds[r.round][r.index].b}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  Row(children: <Widget>[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => context.push('/arcade/${tour.gameId}'),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: Text(gameLabel(context, tour.gameId), overflow: TextOverflow.ellipsis),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: canManage ? () => _enterResult(context, ref, tour, r) : null,
                        icon: const Icon(Icons.how_to_vote_rounded),
                        label: Text(context.tx('ثبت نتیجه', 'Enter result')),
                      ),
                    ),
                  ]),
                ]),
              ),
            ),
        ],
        SocialSectionTitle(context.tx('جدول حذفی', 'Bracket')),
        BracketView(
          bracket: tour.bracket,
          onMatchTap: canManage ? (MatchRef r) => _enterResult(context, ref, tour, r) : null,
        ),
      ]),
    );
  }
}

/// Horizontally scrolling bracket: one column per round.
class BracketView extends StatelessWidget {
  const BracketView({super.key, required this.bracket, this.onMatchTap});
  final TournamentBracket bracket;
  final ValueChanged<MatchRef>? onMatchTap;

  static const double _cardH = 64;
  static const double _gap = 14;
  static const double _colW = 168;

  @override
  Widget build(BuildContext context) {
    final int first = bracket.rounds.isEmpty ? 0 : bracket.rounds.first.length;
    final double height = first * (_cardH + _gap) + 30;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        height: height.clamp(120.0, 2400.0),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            for (int r = 0; r < bracket.rounds.length; r++)
              SizedBox(
                width: _colW + 18,
                child: Column(children: <Widget>[
                  SizedBox(
                    height: 26,
                    child: Text(roundName(context, r, bracket.roundCount),
                        style: TextStyle(color: kSocialPalette.primary, fontWeight: FontWeight.w900, fontSize: 12)),
                  ),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: <Widget>[
                        for (int i = 0; i < bracket.rounds[r].length; i++)
                          _MatchCard(
                            match: bracket.rounds[r][i],
                            width: _colW,
                            height: _cardH,
                            onTap: onMatchTap == null || !bracket.rounds[r][i].ready
                                ? null
                                : () => onMatchTap!(MatchRef(r, i)),
                          ),
                      ],
                    ),
                  ),
                ]),
              ),
          ]),
        ),
      ),
    );
  }
}

class _MatchCard extends StatelessWidget {
  const _MatchCard({required this.match, required this.width, required this.height, this.onTap});
  final BracketMatch match;
  final double width;
  final double height;
  final VoidCallback? onTap;

  Widget _slot(BuildContext context, String? name, bool bye) {
    final bool won = name != null && match.winner == name && match.ready;
    final String label = name ?? (bye ? context.tx('استراحت', 'bye') : '—');
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.centerLeft,
        color: won ? NxColors.gold.withValues(alpha: 0.22) : Colors.transparent,
        child: Row(children: <Widget>[
          Expanded(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: won ? FontWeight.w900 : FontWeight.w600,
                  color: name == null ? NxColors.textDim : (won ? NxColors.gold : NxColors.iceWhite),
                  fontSize: 13,
                )),
          ),
          if (won) const Icon(Icons.emoji_events_rounded, size: 14, color: NxColors.gold),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool live = match.playable;
    final bool bye = match.done && !match.ready;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(NxRadius.sm),
          child: Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: const Color(0x1AFFFFFF),
              borderRadius: BorderRadius.circular(NxRadius.sm),
              border: Border.all(
                color: live ? kSocialPalette.secondary : (match.done ? NxColors.gold.withValues(alpha: 0.5) : NxColors.glassBorder),
                width: live ? 1.6 : 1,
              ),
              boxShadow: live ? <BoxShadow>[BoxShadow(color: kSocialPalette.secondary.withValues(alpha: 0.35), blurRadius: 10)] : null,
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(children: <Widget>[
              _slot(context, match.a, false),
              Container(height: 1, color: NxColors.glassBorder),
              _slot(context, match.b, bye),
            ]),
          ),
        ),
      ),
    );
  }
}
