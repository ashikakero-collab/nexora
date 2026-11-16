import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/profile/profile_service.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/storage/local_store.dart';
import '../../../core/theme/nx_theme.dart';
import '../../../core/widgets/nx_widgets.dart';
import '../core/challenge_store.dart';
import '../core/challenges.dart';
import 'po_common.dart';

/// Missions: daily reward with streak + daily / weekly challenges with real progress.
class MissionsTab extends ConsumerWidget {
  const MissionsTab({super.key});

  void _celebrate(BuildContext context, AwardOutcome o) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(poDigits(
          context,
          context.tx('+${o.xp} XP  •  +${o.coins} سکه',
              '+${o.xp} XP  •  +${o.coins} coins'))),
    ));
    showAwardOutcome(context, o);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ProfileService p = ref.watch(profileProvider);
    final DateTime now = DateTime.now();
    final ChallengeBook book =
        ChallengeStore.touch(p, store: LocalStore.instance, now: now);
    final List<ChallengeEvent> events = ChallengeStore.eventsOf(p);

    Widget section(ChallengePeriod period) {
      final List<ChallengeDef> defs = challengesFor(period);
      int done = 0;
      for (final ChallengeDef d in defs) {
        if (book.isClaimed(d)) done++;
      }
      return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            PoSectionTitle(
              period == ChallengePeriod.daily
                  ? context.tx('چالش‌های امروز', "Today's challenges")
                  : context.tx('چالش‌های هفته', 'Weekly challenges'),
              icon: period == ChallengePeriod.daily
                  ? Icons.today_rounded
                  : Icons.date_range_rounded,
              trailing: Text(poDigits(context, '$done/${defs.length}'),
                  style: TextStyle(
                      color: PoColors.inkDim(context),
                      fontWeight: FontWeight.w700)),
            ),
            for (final ChallengeDef d in defs)
              Padding(
                padding: const EdgeInsets.only(bottom: NxSpace.sm),
                child: _ChallengeCard(
                  def: d,
                  progress: book.progress(d, now, p.counters, events),
                  claimed: book.isClaimed(d),
                  claimable: book.canClaim(d, now, p.counters, events),
                  onClaim: () {
                    final AwardOutcome? o =
                        ChallengeStore.claim(p, d, store: LocalStore.instance);
                    if (o != null) _celebrate(context, o);
                  },
                ),
              ),
          ]);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          NxSpace.md, NxSpace.sm, NxSpace.md, NxSpace.xl),
      children: <Widget>[
        _DailyRewardCard(
          streak: p.streak,
          canClaim: p.canClaimDaily,
          onClaim: () {
            final AwardOutcome? o = p.claimDaily();
            if (o != null) _celebrate(context, o);
          },
        ),
        section(ChallengePeriod.daily),
        section(ChallengePeriod.weekly),
        Padding(
          padding: const EdgeInsets.only(top: NxSpace.sm),
          child: Text(
            context.tx(
                'پیشرفت فقط از فعالیت واقعی تو در دنیاهای NEXORA محاسبه می‌شود. هفته از شنبه شروع می‌شود.',
                'Progress counts only your real activity in NEXORA worlds. Weeks start on Saturday.'),
            style: TextStyle(color: PoColors.inkDim(context), fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

class _DailyRewardCard extends StatelessWidget {
  const _DailyRewardCard(
      {required this.streak, required this.canClaim, required this.onClaim});
  final int streak;
  final bool canClaim;
  final VoidCallback onClaim;

  @override
  Widget build(BuildContext context) {
    // The next claim continues the streak only if it was claimed yesterday; we
    // show the bonus for the current streak position honestly (50 + min(streak,7)*10).
    final int shownStreak = canClaim ? streak + 1 : streak;
    final int bonus = 50 + math.min(math.max(shownStreak, 1), 7) * 10;
    final NxThemeColors visual = NxThemeColors.of(context);
    return PoCard(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[visual.surfaceRaised, visual.surface],
      ),
      borderColor: visual.accent.withValues(alpha: 0.62),
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
                        color: visual.accent.withValues(alpha: 0.32),
                        blurRadius: 18)
                  ],
                ),
                child: const Icon(Icons.card_giftcard_rounded,
                    color: Colors.white, size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(context.tx('جایزه‌ی روزانه', 'Daily reward'),
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              color: PoColors.ink(context))),
                      const SizedBox(height: 2),
                      Text(
                        canClaim
                            ? poDigits(
                                context,
                                context.tx(
                                    'تا $bonus سکه و ۲۵ XP آماده‌ی دریافت',
                                    'Up to $bonus coins + 25 XP ready'))
                            : context.tx('امروز دریافت شد. فردا برگرد!',
                                'Claimed today. Come back tomorrow!'),
                        style: TextStyle(
                            color: PoColors.inkDim(context), fontSize: 12),
                      ),
                    ]),
              ),
            ]),
            const SizedBox(height: 14),
            Row(children: <Widget>[
              for (int i = 1; i <= 7; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Column(children: <Widget>[
                      Icon(
                        Icons.local_fire_department_rounded,
                        size: 22,
                        color: i <= math.min(streak, 7)
                            ? visual.accent
                            : PoColors.locked(context),
                      ),
                      Text(poDigits(context, '$i'),
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: i <= math.min(streak, 7)
                                  ? PoColors.ink(context)
                                  : PoColors.inkDim(context))),
                    ]),
                  ),
                ),
            ]),
            const SizedBox(height: 12),
            Row(children: <Widget>[
              Text(
                  poDigits(context,
                      context.tx('رکورد: $streak روز', 'Streak: $streak days')),
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: PoColors.ink(context))),
              const Spacer(),
              FilledButton.icon(
                onPressed: canClaim ? onClaim : null,
                icon:
                    Icon(canClaim ? Icons.redeem_rounded : Icons.check_rounded),
                label: Text(canClaim
                    ? context.tx('دریافت', 'Claim')
                    : context.tx('دریافت شد', 'Claimed')),
              ),
            ]),
          ]),
    );
  }
}

class _ChallengeCard extends StatelessWidget {
  const _ChallengeCard({
    required this.def,
    required this.progress,
    required this.claimed,
    required this.claimable,
    required this.onClaim,
  });

  final ChallengeDef def;
  final int progress;
  final bool claimed;
  final bool claimable;
  final VoidCallback onClaim;

  @override
  Widget build(BuildContext context) {
    final double frac = def.target <= 0 ? 0 : progress / def.target;
    final NxThemeColors visual = NxThemeColors.of(context);
    Widget action;
    if (claimed) {
      action =
          Icon(Icons.verified_rounded, color: PoColors.mint(context), size: 28);
    } else if (claimable) {
      action = FilledButton(
          onPressed: onClaim, child: Text(context.tx('دریافت', 'Claim')));
    } else if (def.route != null) {
      action = IconButton(
        tooltip: context.tx('برو', 'Go'),
        onPressed: () => context.push(def.route!),
        icon: Icon(Icons.arrow_forward_rounded, color: PoColors.lilac(context)),
      );
    } else {
      action = const SizedBox.shrink();
    }
    return PoCard(
      color: claimed ? visual.surfaceRaised : visual.surface,
      padding: const EdgeInsets.fromLTRB(NxSpace.md, 12, NxSpace.sm, 12),
      child: Row(children: <Widget>[
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(context.tx(def.titleFa, def.titleEn),
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: PoColors.ink(context),
                      decoration: claimed ? TextDecoration.lineThrough : null,
                    )),
                const SizedBox(height: 8),
                PoProgressBar(
                  value: frac,
                  colors: claimed
                      ? <Color>[PoColors.mint(context), PoColors.mint(context)]
                      : null,
                ),
                const SizedBox(height: 6),
                Row(children: <Widget>[
                  Text(poDigits(context, '$progress/${def.target}'),
                      style: TextStyle(
                          fontSize: 12,
                          color: PoColors.inkDim(context),
                          fontWeight: FontWeight.w700)),
                  const Spacer(),
                  Text(poDigits(context, '+${def.xp} XP'),
                      style: TextStyle(
                          fontSize: 12,
                          color: PoColors.lilac(context),
                          fontWeight: FontWeight.w800)),
                  if (def.coins > 0) ...<Widget>[
                    const SizedBox(width: 8),
                    Icon(Icons.toll_rounded, size: 14, color: visual.accent),
                    const SizedBox(width: 2),
                    Text(poDigits(context, '+${def.coins}'),
                        style: TextStyle(
                            fontSize: 12,
                            color: visual.accent,
                            fontWeight: FontWeight.w800)),
                  ],
                ]),
              ]),
        ),
        const SizedBox(width: 8),
        action,
      ]),
    );
  }
}
