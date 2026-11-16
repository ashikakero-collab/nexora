import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/assets/app_assets.dart';
import '../../core/profile/profile_service.dart';
import '../../core/settings/app_settings.dart';
import '../../core/theme/nx_theme.dart';
import '../../core/ui2/nx2_assets.dart';
import '../../core/ui2/nx2_widgets.dart';
import '../../core/ui2/oracle_mascot.dart';
import '../../core/widgets/nx_widgets.dart';
import '../../games/game_registry.dart';

/// NEXORA ARCADE lobby (STEP_18): game pedestals, records, quick play.
class ArcadePage extends ConsumerWidget {
  const ArcadePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(profileProvider);
    final visual = NxThemeColors.of(context);
    return DefaultTabController(
      length: 2,
      child: NxWorldScaffold(
        title: context.tx('آرکید NEXORA', 'NEXORA ARCADE'),
        palette: WorldPalette.arcade,
        dock: Nx2Tab.games,
        body: Column(children: [
          TabBar(
            indicatorColor: visual.accent,
            labelColor: visual.accent,
            unselectedLabelColor: visual.muted,
            dividerColor: Colors.transparent,
            tabs: [
              Tab(text: context.tx('بازی‌ها', 'Games')),
              Tab(text: context.tx('رکوردها', 'Records')),
            ],
          ),
          Expanded(
            child: TabBarView(children: [
              _GamesGrid(profile: p),
              _Records(profile: p),
            ]),
          ),
        ]),
      ),
    );
  }
}

const Map<String, int> _kGameGroup = <String, int>{
  'finger_soccer': 1,
  'carrom': 1,
  'billiards': 1,
  'backgammon': 2,
  'ludo': 2,
  'snakes_ladders': 2,
  'uno': 3,
  'quiz': 3,
  'mafia': 3,
};

class _GamesGrid extends StatefulWidget {
  const _GamesGrid({required this.profile});
  final ProfileService profile;

  @override
  State<_GamesGrid> createState() => _GamesGridState();
}

class _GamesGridState extends State<_GamesGrid> {
  int _group = 0;

  @override
  Widget build(BuildContext context) {
    final ProfileService profile = widget.profile;
    final List<GameInfo> games = kGames
        .where((GameInfo g) => _group == 0 || _kGameGroup[g.id] == _group)
        .toList();
    final List<(String, String)> groups = <(String, String)>[
      ('همه', 'All'),
      ('ورزشی', 'Sports'),
      ('تخته‌ای', 'Board'),
      ('پارتی', 'Party'),
    ];
    return CustomScrollView(slivers: [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Nx2Panel(
            gems: true,
            padding: const EdgeInsets.fromLTRB(8, 8, 14, 8),
            child: Row(children: [
              const OracleMascot(mood: OracleMood.play, size: 92),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          context.tx('بیا یه دست بزنیم!', "Let's play a round!"),
                          style: Nx2.title.copyWith(fontSize: 16)),
                      const SizedBox(height: 4),
                      Text(
                          context.tx(
                              '${profile.totalGamesPlayed} بازی · ${profile.totalWins} برد',
                              '${profile.totalGamesPlayed} played · ${profile.totalWins} wins'),
                          style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 12.5,
                              color: Nx2.gold)),
                      const SizedBox(height: 2),
                      Text(
                        context.tx(
                            'با بات هوشمند، دو نفره روی یک گوشی یا آنلاین.',
                            'Smart bots, two on one phone, or online.'),
                        style: const TextStyle(
                            color: Nx2.muted, fontSize: 11.5, height: 1.35),
                      ),
                    ]),
              ),
            ]),
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            children: [
              for (int i = 0; i < groups.length; i++)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _group = i),
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 180),
                      opacity: _group == i ? 1 : 0.7,
                      child: NxPill(
                        label: context.tx(groups[i].$1, groups[i].$2),
                        color: _group == i ? Nx2.magenta : Nx2.violet,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.70,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, i) => _GameTile(
                game: games[i],
                stats: profile.stats[games[i].id],
                frame: i),
            childCount: games.length,
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: Nx2Panel(
            gold: true,
            onTap: () => context.push('/tournaments'),
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Image.asset(Nx2Assets.badgesTrophyGold,
                  width: 48, height: 58, cacheWidth: 140),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(context.tx('تورنمنت‌های آنلاین', 'Online tournaments'),
                          style: const TextStyle(
                              fontWeight: FontWeight.w900, color: Nx2.gold)),
                      Text(
                          context.tx('حذفی، لیگ، گروهی و سوئیسی با جایزه',
                              'Knockout, league, groups and swiss with prizes'),
                          style:
                              const TextStyle(color: Nx2.muted, fontSize: 12)),
                    ]),
              ),
              const Icon(Icons.chevron_right_rounded, color: Nx2.gold),
            ]),
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
          child: Nx2Panel(
            onTap: () => context.push('/world/social_station'),
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Image.asset(Nx2Assets.badgesMedalCrown,
                  width: 44, height: 44, cacheWidth: 130),
              const SizedBox(width: 10),
              Expanded(
                child: Text(context.tx(
                    'مسابقه و لیگ با دوستان در ایستگاه اجتماعی',
                    'Tournaments & leagues with friends in Social Station')),
              ),
              const Icon(Icons.chevron_right_rounded),
            ]),
          ),
        ),
      ),
    ]);
  }
}

class _GameTile extends StatelessWidget {
  const _GameTile({required this.game, required this.stats, required this.frame});
  final GameInfo game;
  final GameStats? stats;
  final int frame;

  @override
  Widget build(BuildContext context) {
    final String art = switch (frame % 3) {
      0 => Nx2Assets.framesTilePurple,
      1 => Nx2Assets.framesTileBlue,
      _ => Nx2Assets.framesTileGold,
    };
    void open() {
      HapticFeedback.selectionClick();
      context.push('/arcade/${game.id}');
    }

    return Nx2Pressable(
      onTap: open,
      child: Nx2Panel(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
        borderColor: Color.lerp(game.accent, Nx2.violet, 0.35),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: Stack(fit: StackFit.expand, children: [
              Opacity(
                opacity: 0.55,
                child: Image.asset(art,
                  fit: BoxFit.fill,
                  cacheWidth: 360,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink()),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 16, 14, 18),
                child: Hero(
                  tag: 'pedestal_${game.id}',
                  child: Image.asset(AppAssets.pedestal(game.id),
                      cacheWidth: 360,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Icon(Icons.sports_esports,
                          size: 60, color: game.accent)),
                ),
              ),
              if (game.supportsOnline)
                const PositionedDirectional(
                  top: 6,
                  start: 6,
                  child: NxPill(
                      label: 'ONLINE',
                      icon: Icons.public_rounded,
                      color: Nx2.cyan),
                ),
            ]),
          ),
          const SizedBox(height: 6),
          Text(context.tx(game.nameFa, game.nameEn),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontWeight: FontWeight.w900, fontSize: 14, color: Nx2.text)),
          Row(children: [
            const Icon(Icons.people_alt_rounded, size: 13, color: Nx2.muted),
            const SizedBox(width: 3),
            Text(
                game.minPlayers == game.maxPlayers
                    ? '${game.minPlayers}'
                    : '${game.minPlayers}-${game.maxPlayers}',
                style: const TextStyle(fontSize: 11, color: Nx2.muted)),
            const Spacer(),
            if (stats != null)
              Text('${stats!.won}/${stats!.played}',
                  style: const TextStyle(fontSize: 11, color: Nx2.gold)),
          ]),
          const SizedBox(height: 6),
          Nx2Button(
            label: context.tx('بازی', 'PLAY'),
            kind: frame.isEven ? Nx2ButtonKind.pink : Nx2ButtonKind.violet,
            height: 36,
            fontSize: 13,
            onTap: open,
          ),
        ]),
      ),
    );
  }
}

class _Records extends StatelessWidget {
  const _Records({required this.profile});
  final ProfileService profile;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(NxSpace.md),
      children: [
        Nx2Button(
          onTap: () => context.push('/leaderboard'),
          icon: Icons.leaderboard_rounded,
          kind: Nx2ButtonKind.cyan,
          label: context.tx('رتبه‌بندی جهانی', 'Global rankings'),
        ),
        const SizedBox(height: NxSpace.md),
        for (final g in kGames)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GlassPanel(
              child: Row(children: [
                Image.asset(AppAssets.pedestal(g.id),
                    width: 46, cacheWidth: 140),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(context.tx(g.nameFa, g.nameEn),
                            style: TextStyle(
                                fontWeight: FontWeight.w800, color: g.accent)),
                        Builder(builder: (context) {
                          final s = profile.stats[g.id];
                          if (s == null) {
                            return Text(
                                context.tx(
                                    'هنوز بازی نکرده‌ای', 'Not played yet'),
                                style: const TextStyle(
                                    color: NxColors.textDim, fontSize: 12));
                          }
                          final rate = s.played == 0
                              ? 0
                              : (s.won * 100 / s.played).round();
                          return Text(
                            context.tx(
                                'بازی ${s.played} · برد ${s.won} · باخت ${s.lost} · مساوی ${s.draw} · ٪$rate',
                                'Played ${s.played} · W ${s.won} · L ${s.lost} · D ${s.draw} · $rate%'),
                            style: const TextStyle(
                                color: NxColors.textDim, fontSize: 12),
                          );
                        }),
                      ]),
                ),
                if ((profile.stats[g.id]?.best ?? 0) > 0)
                  NxPill(
                      label:
                          '${context.tx('بهترین', 'Best')} ${profile.stats[g.id]!.best}',
                      color: NxColors.gold),
              ]),
            ),
          ),
      ],
    );
  }
}
