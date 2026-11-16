import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexora/games/game_registry.dart';

import '../../../core/assets/app_assets.dart';
import '../../../core/profile/achievements.dart';
import '../../../core/profile/profile_service.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/theme/nx_theme.dart';
import 'po_common.dart';

// ---------------------------------------------------------------- Achievements

class AchievementsTab extends ConsumerWidget {
  const AchievementsTab({super.key});

  void _details(BuildContext context, AchievementDef a, bool unlocked) {
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(ctx.tx(a.nameFa, a.nameEn)),
        content: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          _AchievementImage(asset: a.asset, unlocked: unlocked, size: 120),
          const SizedBox(height: 12),
          Text(ctx.tx(a.descFa, a.descEn), textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            unlocked
                ? ctx.tx('باز شده', 'Unlocked')
                : poDigits(
                    ctx,
                    ctx.tx('قفل • جایزه: ${a.coinReward} سکه',
                        'Locked • reward: ${a.coinReward} coins')),
            style: TextStyle(
                fontWeight: FontWeight.w800,
                color: unlocked ? PoColors.mint(ctx) : PoColors.inkDim(ctx)),
          ),
        ]),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(ctx.tx('بستن', 'Close'))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ProfileService p = ref.watch(profileProvider);
    final NxThemeColors visual = NxThemeColors.of(context);
    final int got = kAchievements
        .where((AchievementDef a) => p.achievements.contains(a.id))
        .length;
    return CustomScrollView(slivers: <Widget>[
      SliverPadding(
        padding:
            const EdgeInsets.fromLTRB(NxSpace.md, NxSpace.sm, NxSpace.md, 0),
        sliver: SliverToBoxAdapter(
          child: PoCard(
            child: Row(children: <Widget>[
              Icon(Icons.emoji_events_rounded, color: visual.accent, size: 34),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                          poDigits(
                              context,
                              context.tx(
                                  '$got از ${kAchievements.length} دستاورد',
                                  '$got of ${kAchievements.length} achievements')),
                          style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: PoColors.ink(context),
                              fontSize: 16)),
                      const SizedBox(height: 8),
                      PoProgressBar(
                        value: kAchievements.isEmpty
                            ? 0
                            : got / kAchievements.length,
                      ),
                    ]),
              ),
            ]),
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.all(NxSpace.md),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 130,
            mainAxisSpacing: NxSpace.sm,
            crossAxisSpacing: NxSpace.sm,
            childAspectRatio: 0.78,
          ),
          delegate: SliverChildBuilderDelegate(
            (BuildContext ctx, int i) {
              final AchievementDef a = kAchievements[i];
              final bool unlocked = p.achievements.contains(a.id);
              return PoCard(
                padding: const EdgeInsets.all(8),
                color: unlocked ? visual.surfaceRaised : visual.surface,
                borderColor: unlocked
                    ? visual.accent.withValues(alpha: 0.68)
                    : PoColors.cardBorder(ctx),
                onTap: () => _details(ctx, a, unlocked),
                child: Column(children: <Widget>[
                  Expanded(
                      child: _AchievementImage(
                          asset: a.asset, unlocked: unlocked, size: 80)),
                  const SizedBox(height: 4),
                  Text(ctx.tx(a.nameFa, a.nameEn),
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: unlocked
                              ? PoColors.ink(ctx)
                              : PoColors.inkDim(ctx))),
                ]),
              );
            },
            childCount: kAchievements.length,
          ),
        ),
      ),
    ]);
  }
}

class _AchievementImage extends StatelessWidget {
  const _AchievementImage(
      {required this.asset, required this.unlocked, required this.size});
  final String asset;
  final bool unlocked;
  final double size;

  @override
  Widget build(BuildContext context) {
    final NxThemeColors visual = NxThemeColors.of(context);
    Widget img = Image.asset(
      AppAssets.achievement(asset),
      width: size,
      height: size,
      cacheWidth: (size * 2.5).round(),
      fit: BoxFit.contain,
      errorBuilder: (BuildContext _, Object __, StackTrace? ___) => Icon(
        Icons.military_tech_rounded,
        size: size * 0.7,
        color: unlocked ? visual.accent : PoColors.locked(context),
      ),
    );
    if (!unlocked) {
      img = Stack(alignment: Alignment.center, children: <Widget>[
        ColorFiltered(colorFilter: kPoGreyscale, child: img),
        Icon(Icons.lock_rounded, color: PoColors.inkDim(context), size: 22),
      ]);
    }
    return img;
  }
}

// ---------------------------------------------------------------- Stats

class StatsTab extends ConsumerWidget {
  const StatsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ProfileService p = ref.watch(profileProvider);
    int played = 0;
    int won = 0;
    int lost = 0;
    int draw = 0;
    for (final GameStats s in p.stats.values) {
      played += s.played;
      won += s.won;
      lost += s.lost;
      draw += s.draw;
    }
    final List<GameInfo> withStats = kGames
        .where((GameInfo g) => (p.stats[g.id]?.played ?? 0) > 0)
        .toList()
      ..sort((GameInfo a, GameInfo b) =>
          p.stats[b.id]!.played.compareTo(p.stats[a.id]!.played));
    final int rate = played == 0 ? 0 : (won * 100 / played).round();

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          NxSpace.md, NxSpace.sm, NxSpace.md, NxSpace.xl),
      children: <Widget>[
        Row(children: <Widget>[
          Expanded(
              child: _StatBox(
                  label: context.tx('مسابقه', 'Matches'),
                  value: poDigits(context, '$played'),
                  color: PoColors.lilac(context))),
          const SizedBox(width: NxSpace.sm),
          Expanded(
              child: _StatBox(
                  label: context.tx('برد', 'Wins'),
                  value: poDigits(context, '$won'),
                  color: PoColors.mint(context))),
          const SizedBox(width: NxSpace.sm),
          Expanded(
              child: _StatBox(
                  label: context.tx('درصد برد', 'Win rate'),
                  value: poDigits(context, '$rate%'),
                  color: NxThemeColors.of(context).accent)),
        ]),
        const SizedBox(height: NxSpace.sm),
        PoCard(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(context.tx('کل نتایج', 'All results'),
                    style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: PoColors.ink(context))),
                const SizedBox(height: 10),
                SizedBox(
                    height: 16,
                    child: CustomPaint(
                        painter:
                            WinRatePainter(won: won, draw: draw, lost: lost))),
                const SizedBox(height: 8),
                _Legend(won: won, draw: draw, lost: lost),
              ]),
        ),
        PoSectionTitle(context.tx('بر اساس بازی', 'By game'),
            icon: Icons.sports_esports_rounded),
        if (withStats.isEmpty)
          PoCard(
            child: Column(children: <Widget>[
              Icon(Icons.videogame_asset_off_rounded,
                  size: 40, color: PoColors.inkDim(context)),
              const SizedBox(height: 8),
              Text(
                  context.tx(
                      'هنوز مسابقه‌ای ثبت نشده.', 'No matches recorded yet.'),
                  style: TextStyle(color: PoColors.ink(context))),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: () => context.push('/world/nexora_arcade'),
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(context.tx('رفتن به آرکید', 'Go to the Arcade')),
              ),
            ]),
          ),
        for (final GameInfo g in withStats)
          Padding(
            padding: const EdgeInsets.only(bottom: NxSpace.sm),
            child: _GameStatCard(game: g, stats: p.stats[g.id]!),
          ),
      ],
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox(
      {required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return PoCard(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      child: Column(children: <Widget>[
        Text(value,
            style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.w900, color: color)),
        const SizedBox(height: 2),
        Text(label,
            style: TextStyle(fontSize: 12, color: PoColors.inkDim(context))),
      ]),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.won, required this.draw, required this.lost});
  final int won;
  final int draw;
  final int lost;

  Widget _dot(BuildContext context, Color c, String label, int v) =>
      Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
        Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(poDigits(context, '$label $v'),
            style: TextStyle(fontSize: 12, color: PoColors.inkDim(context))),
      ]);

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 14, runSpacing: 4, children: <Widget>[
      _dot(context, WinRatePainter.winColor, context.tx('برد', 'Won'), won),
      _dot(
          context, WinRatePainter.drawColor, context.tx('مساوی', 'Draw'), draw),
      _dot(context, WinRatePainter.lossColor, context.tx('باخت', 'Lost'), lost),
    ]);
  }
}

class _GameStatCard extends StatelessWidget {
  const _GameStatCard({required this.game, required this.stats});
  final GameInfo game;
  final GameStats stats;

  @override
  Widget build(BuildContext context) {
    final int rate =
        stats.played == 0 ? 0 : (stats.won * 100 / stats.played).round();
    return PoCard(
      onTap: () => context.push('/arcade/${game.id}'),
      padding: const EdgeInsets.all(12),
      child: Row(children: <Widget>[
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: game.accent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(NxRadius.md),
          ),
          child: Image.asset(
            AppAssets.pedestal(game.id),
            cacheWidth: 140,
            fit: BoxFit.contain,
            errorBuilder: (BuildContext _, Object __, StackTrace? ___) =>
                Icon(Icons.sports_esports_rounded, color: game.accent),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(children: <Widget>[
                  Expanded(
                    child: Text(context.tx(game.nameFa, game.nameEn),
                        style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: PoColors.ink(context))),
                  ),
                  Text(poDigits(context, '$rate%'),
                      style: TextStyle(
                          fontWeight: FontWeight.w900, color: game.accent)),
                ]),
                const SizedBox(height: 6),
                SizedBox(
                  height: 10,
                  child: CustomPaint(
                      painter: WinRatePainter(
                          won: stats.won, draw: stats.draw, lost: stats.lost)),
                ),
                const SizedBox(height: 6),
                Text(
                  poDigits(
                      context,
                      context.tx(
                          '${stats.played} بازی • ${stats.won} برد • ${stats.draw} مساوی • ${stats.lost} باخت${stats.best > 0 ? ' • بهترین امتیاز ${stats.best}' : ''}',
                          '${stats.played} played • ${stats.won} W • ${stats.draw} D • ${stats.lost} L${stats.best > 0 ? ' • best ${stats.best}' : ''}')),
                  style:
                      TextStyle(fontSize: 12, color: PoColors.inkDim(context)),
                ),
              ]),
        ),
      ]),
    );
  }
}

/// Segmented win / draw / loss bar.
class WinRatePainter extends CustomPainter {
  WinRatePainter({required this.won, required this.draw, required this.lost});
  final int won;
  final int draw;
  final int lost;

  static const Color winColor = Color(0xFF1FBF95);
  static const Color drawColor = Color(0xFFB79CFF);
  static const Color lossColor = Color(0xFFFF7A8A);

  @override
  void paint(Canvas canvas, Size size) {
    final RRect bg = RRect.fromRectAndRadius(
        Offset.zero & size, Radius.circular(size.height / 2));
    canvas.drawRRect(bg, Paint()..color = const Color(0x1F3A2C80));
    final int total = won + draw + lost;
    if (total <= 0) return;
    canvas.save();
    canvas.clipRRect(bg);
    double x = 0;
    final List<int> values = <int>[won, draw, lost];
    const List<Color> colors = <Color>[winColor, drawColor, lossColor];
    for (int i = 0; i < 3; i++) {
      final double w = size.width * values[i] / total;
      if (w <= 0) continue;
      final Rect r = Rect.fromLTWH(x, 0, w, size.height);
      canvas.drawRect(
        r,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[colors[i].withValues(alpha: 0.85), colors[i]],
          ).createShader(r),
      );
      x += w;
    }
    // Gloss highlight.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height * 0.45),
      Paint()..color = Colors.white.withValues(alpha: 0.18),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant WinRatePainter old) =>
      old.won != won || old.draw != draw || old.lost != lost;
}

// ---------------------------------------------------------------- Activity

class ActivityTab extends ConsumerWidget {
  const ActivityTab({super.key});

  static IconData _icon(String kind) {
    if (kind.startsWith('game.')) return Icons.sports_esports_rounded;
    if (kind.startsWith('challenge.')) return Icons.flag_rounded;
    switch (kind) {
      case 'achievement':
        return Icons.emoji_events_rounded;
      case 'shop':
        return Icons.shopping_bag_rounded;
      case 'daily':
        return Icons.card_giftcard_rounded;
      case 'identity':
        return Icons.badge_rounded;
      default:
        return Icons.auto_awesome_rounded;
    }
  }

  static Color _color(BuildContext context, String kind) {
    final NxThemeColors visual = NxThemeColors.of(context);
    if (kind.endsWith('.win')) return visual.accent;
    if (kind.endsWith('.loss')) return const Color(0xFFFF7A8A);
    if (kind.startsWith('game.')) return const Color(0xFF2F8CFF);
    if (kind == 'achievement' || kind == 'shop') return visual.accent;
    return visual.accentSecondary;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ProfileService p = ref.watch(profileProvider);
    final List<ActivityEntry> list = p.activity;
    if (list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(NxSpace.lg),
          child: Text(context.tx('هنوز فعالیتی ثبت نشده.', 'No activity yet.'),
              style: TextStyle(color: PoColors.inkDim(context))),
        ),
      );
    }
    final DateTime now = DateTime.now();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
          NxSpace.md, NxSpace.sm, NxSpace.md, NxSpace.xl),
      itemCount: list.length,
      itemBuilder: (BuildContext ctx, int i) {
        final ActivityEntry e = list[i];
        final Color c = _color(ctx, e.kind);
        final bool last = i == list.length - 1;
        return IntrinsicHeight(
          child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SizedBox(
                  width: 36,
                  child: Column(children: <Widget>[
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: c.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                        border: Border.all(color: c.withValues(alpha: 0.6)),
                      ),
                      child: Icon(_icon(e.kind), size: 16, color: c),
                    ),
                    if (!last)
                      Expanded(
                          child: Container(
                              width: 2, color: const Color(0x337B5CE6))),
                  ]),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: NxSpace.md),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(ctx.tx(e.textFa, e.textEn),
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: PoColors.ink(ctx))),
                          const SizedBox(height: 2),
                          Row(children: <Widget>[
                            Text(poAgo(ctx, e.at, now),
                                style: TextStyle(
                                    fontSize: 11, color: PoColors.inkDim(ctx))),
                            if (e.xp > 0) ...<Widget>[
                              const SizedBox(width: 8),
                              Text(poDigits(ctx, '+${e.xp} XP'),
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: PoColors.lilac(ctx),
                                      fontWeight: FontWeight.w800)),
                            ],
                          ]),
                        ]),
                  ),
                ),
              ]),
        );
      },
    );
  }
}
