import 'dart:math';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../assets/app_assets.dart';
import '../profile/profile_service.dart';
import '../settings/app_settings.dart';
import '../theme/nx_theme.dart';
import '../ui2/nx2_widgets.dart';
import '../ui2/oracle_mascot.dart';

/// Animated cosmic background used by every world (respects quality + reduced motion).
class NxBackground extends ConsumerStatefulWidget {
  const NxBackground(
      {super.key,
      this.palette = WorldPalette.hub,
      this.child,
      this.stars = true});
  final WorldPalette palette;
  final Widget? child;
  final bool stars;

  @override
  ConsumerState<NxBackground> createState() => _NxBackgroundState();
}

class _NxBackgroundState extends ConsumerState<NxBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 60));
  List<_Star> _stars = const [];
  int _count = -1;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _ensureStars(int count) {
    if (count == _count) return;
    _count = count;
    final r = Random(7);
    _stars = List.generate(
        count,
        (_) => _Star(r.nextDouble(), r.nextDouble(), r.nextDouble() * 1.6 + 0.3,
            r.nextDouble()));
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final animate = !s.reducedMotion;
    if (animate && !_c.isAnimating) _c.repeat();
    if (!animate && _c.isAnimating) _c.stop();
    _ensureStars(widget.palette.light ? (s.starCount ~/ 3) : s.starCount);
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: widget.palette.background,
            ),
          ),
        ),
        if (widget.stars)
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: _c,
              builder: (_, __) => CustomPaint(
                painter: _StarPainter(_stars, _c.value, widget.palette),
              ),
            ),
          ),
        if (widget.child != null) widget.child!,
      ],
    );
  }
}

class _Star {
  const _Star(this.x, this.y, this.size, this.phase);
  final double x, y, size, phase;
}

class _StarPainter extends CustomPainter {
  _StarPainter(this.stars, this.t, this.palette);
  final List<_Star> stars;
  final double t;
  final WorldPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    // nebula glows
    final glow1 = Paint()
      ..shader = RadialGradient(colors: [
        palette.primary.withValues(alpha: 0.18),
        Colors.transparent
      ]).createShader(Rect.fromCircle(
          center: Offset(size.width * 0.15, size.height * 0.25),
          radius: size.width * 0.8));
    canvas.drawRect(Offset.zero & size, glow1);
    final glow2 = Paint()
      ..shader = RadialGradient(colors: [
        palette.secondary.withValues(alpha: 0.16),
        Colors.transparent
      ]).createShader(Rect.fromCircle(
          center: Offset(size.width * 0.9, size.height * 0.75),
          radius: size.width * 0.9));
    canvas.drawRect(Offset.zero & size, glow2);
    final p = Paint();
    final starColor = palette.light ? palette.secondary : Colors.white;
    for (final s in stars) {
      final tw = 0.55 + 0.45 * sin((t * 2 * pi * 6) + s.phase * 6.28);
      final dy = (s.y + t * 0.05 * s.size) % 1.0;
      p.color = starColor.withValues(alpha: (palette.light ? 0.35 : 0.85) * tw);
      canvas.drawCircle(Offset(s.x * size.width, dy * size.height), s.size, p);
    }
  }

  @override
  bool shouldRepaint(covariant _StarPainter old) =>
      old.t != t || old.stars != stars;
}

/// App surfaces backdrop (NX2: the owner's cosmic castle art, darkened for contrast).
class NxBrandBackground extends StatelessWidget {
  const NxBrandBackground({super.key, this.child, this.room = false});
  final Widget? child;
  final bool room;

  @override
  Widget build(BuildContext context) => Nx2Background(room: room, child: child);
}

/// Premium inset panel with a quiet metallic/neon rim, shared by all app worlds.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(NxSpace.md),
    this.radius = NxRadius.lg,
    this.tint,
    this.borderColor,
    this.blur = true,
    this.onTap,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? tint;
  final Color? borderColor;
  final bool blur;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // NX2: chamfered neon glass. Gold borders keep the legendary look.
    final Color? bc = borderColor;
    final bool gold = bc != null &&
        (bc.r > 0.8 && bc.g > 0.6 && bc.b < 0.5);
    final Color? t = tint?.withValues(alpha: math.min(0.35, tint!.a));
    final Widget panel = Nx2Panel(
      padding: padding,
      cut: math.min(16, math.max(8, radius * 0.6)),
      gold: gold,
      tint: t,
      borderColor: gold ? null : bc?.withValues(alpha: 1),
      child: child,
    );
    if (onTap == null) return panel;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: Nx2.violet.withValues(alpha: 0.18),
        highlightColor: Colors.transparent,
        child: panel,
      ),
    );
  }
}

/// Small rounded label.
class NxPill extends StatelessWidget {
  const NxPill({super.key, required this.label, this.icon, this.color});
  final String label;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final Color pillColor = color ?? Nx2.cyan;
    return CustomPaint(
      painter: Nx2FramePainter(
        cut: 7,
        glow: 0,
        strokeWidth: 1.1,
        fill: LinearGradient(colors: <Color>[
          pillColor.withValues(alpha: 0.22),
          const Color(0xE6120A33),
        ]),
        border: LinearGradient(colors: <Color>[
          pillColor,
          pillColor.withValues(alpha: 0.5),
        ]),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: pillColor),
            const SizedBox(width: 4)
          ],
          Text(label,
              style: TextStyle(
                  color: Color.lerp(pillColor, Colors.white, 0.35),
                  fontWeight: FontWeight.w800,
                  fontSize: 12)),
        ]),
      ),
    );
  }
}

/// Coins + level chip for app bars.
class WalletChip extends ConsumerWidget {
  const WalletChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(profileProvider);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Nx2Stat(value: '${p.coins}'),
      const SizedBox(width: 6),
      Nx2Stat(value: '${p.level}', icon: Icons.bolt_rounded, color: Nx2.cyan),
    ]);
  }
}

/// XP progress bar.
class XpBar extends ConsumerWidget {
  const XpBar({super.key, this.height = 10});
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(profileProvider);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Text('${context.tx('سطح', 'Level')} ${p.level}',
            style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(width: 8),
        Text(context.tx(p.rankTitleFa, p.rankTitleEn),
            style: const TextStyle(color: NxColors.textDim, fontSize: 12)),
        const Spacer(),
        Text('${p.xpIntoLevel}/${ProfileService.xpForLevel(p.level)} XP',
            style: const TextStyle(color: NxColors.textDim, fontSize: 12)),
      ]),
      const SizedBox(height: 6),
      Nx2Progress(value: p.levelProgress, height: height),
    ]);
  }
}

/// Standard world page scaffold (NX2 top bar, cosmic backdrop, optional bottom dock).
class NxWorldScaffold extends StatelessWidget {
  const NxWorldScaffold({
    super.key,
    required this.title,
    required this.palette,
    required this.body,
    this.actions,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.showWallet = true,
    this.dock,
    this.room = false,
  });
  final String title;
  final WorldPalette palette;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final bool showWallet;

  /// When set, the NX2 bottom dock is shown with this tab highlighted.
  final Nx2Tab? dock;
  final bool room;

  @override
  Widget build(BuildContext context) {
    final Widget? bottom = bottomNavigationBar ??
        (dock != null ? Nx2Dock(current: dock) : null);
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Nx2.deep,
      appBar: Nx2TopBar(title: title, actions: actions, showWallet: showWallet),
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottom,
      body: NxBrandBackground(
        room: room,
        child: SafeArea(
          bottom: bottom == null,
          child: body,
        ),
      ),
    );
  }
}

/// ORACLE mascot (NX2 animated robot). Legacy pose names map to moods.
class OracleAvatar extends StatelessWidget {
  const OracleAvatar({super.key, this.pose = 'idle', this.size = 90});
  final String pose;
  final double size;

  @override
  Widget build(BuildContext context) => OracleMascot(
      mood: oracleMoodFromLegacy(pose), size: size, interactive: true);
}

/// Shows level-up / achievement celebration (short, skippable).
Future<void> showAwardOutcome(BuildContext context, AwardOutcome o) async {
  if (!o.levelUp && o.unlocked.isEmpty) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Row(children: [
        const Icon(Icons.auto_awesome, color: NxColors.gold),
        const SizedBox(width: 8),
        Expanded(
            child: Text(o.levelUp
                ? ctx.tx('ارتقای سطح!', 'Level up!')
                : ctx.tx('دستاورد جدید!', 'New achievement!'))),
      ]),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        if (o.levelUp)
          Text('${ctx.tx('سطح', 'Level')} ${o.newLevel}',
              style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: NxColors.turquoise)),
        for (final a in o.unlocked)
          ListTile(
            leading: Image.asset(AppAssets.achievement(a.asset),
                width: 44, cacheWidth: 120),
            title: Text(ctx.tx(a.nameFa, a.nameEn)),
            subtitle: Text('${ctx.tx(a.descFa, a.descEn)}  +${a.coinReward}'),
          ),
      ]),
      actions: [
        FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(ctx.tx('عالی', 'Great')))
      ],
    ),
  );
}

/// Honest "needs online" notice for features that can't work offline yet.
class OnlineOnlyNotice extends StatelessWidget {
  const OnlineOnlyNotice(
      {super.key, required this.featureFa, required this.featureEn});
  final String featureFa;
  final String featureEn;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      tint: const Color(0x14FFC857),
      borderColor: NxColors.gold.withValues(alpha: 0.5),
      child: Row(children: [
        const Icon(Icons.cloud_off_rounded, color: NxColors.gold),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            context.tx(
                '$featureFa به اتصال آنلاین نیاز دارد و بعد از اتصال سرور فعال می‌شود.',
                '$featureEn needs the online server and turns on once it is connected.'),
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ]),
    );
  }
}
