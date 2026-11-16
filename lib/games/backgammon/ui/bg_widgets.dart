import 'dart:math';

import 'package:flutter/material.dart';

import 'package:nexora/core/assets/app_assets.dart';
import 'package:nexora/core/theme/nx_theme.dart';
import 'bg_geometry.dart';

/// One textured checker (asset with procedural fallback).
class BgChecker extends StatelessWidget {
  const BgChecker({super.key, required this.player, this.size = BgGeom.d});

  final int player;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: <BoxShadow>[
          BoxShadow(
              color: Color(0x99000000), blurRadius: 8, offset: Offset(0, 4)),
        ],
      ),
      child: Image.asset(
        player == 0
            ? AppAssets.gamesBackgammonCheckerLight
            : AppAssets.gamesBackgammonCheckerDark,
        width: size,
        height: size,
        cacheWidth: 128,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        errorBuilder: (BuildContext c, Object e, StackTrace? s) => CustomPaint(
            size: Size(size, size), painter: BgCheckerPainter(player)),
      ),
    );
  }
}

/// A die: tumbling image while [rolling] (t = 0..1), then a procedural face.
class BgDie extends StatelessWidget {
  const BgDie({
    super.key,
    required this.value,
    required this.size,
    this.used = false,
    this.rolling = false,
    this.t = 0,
    this.variant = 0,
    this.accent = const Color(0xFFFFC857),
  });

  final int value;
  final double size;
  final bool used;
  final bool rolling;
  final double t;
  final int variant;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    if (rolling) {
      final double dir = variant.isEven ? 1 : -1;
      final double bounce = (sin(t * pi * 3)).abs() * size * 0.5 * (1 - t);
      final double drift = sin(t * pi * 2 + variant) * size * 0.25 * (1 - t);
      return Transform.translate(
        offset: Offset(drift, -bounce),
        child: Transform.rotate(
          angle: dir * t * pi * 5,
          child: Image.asset(
            variant.isEven
                ? AppAssets.gamesBackgammonDieA
                : AppAssets.gamesBackgammonDieB,
            width: size * 1.1,
            height: size * 1.1,
            cacheWidth: 160,
            fit: BoxFit.contain,
            errorBuilder: (BuildContext c, Object e, StackTrace? s) =>
                CustomPaint(
              size: Size(size, size),
              painter: BgDieFacePainter(1 + ((t * 17).floor() + variant) % 6,
                  accent: accent),
            ),
          ),
        ),
      );
    }
    return AnimatedScale(
      scale: used ? 0.82 : 1.0,
      duration: const Duration(milliseconds: 220),
      child: AnimatedOpacity(
        opacity: used ? 0.45 : 1.0,
        duration: const Duration(milliseconds: 220),
        child: CustomPaint(
          size: Size(size, size),
          painter: BgDieFacePainter(value, used: used, accent: accent),
        ),
      ),
    );
  }
}

/// Cosmic backdrop with a deterministic star field.
class BgSpaceBackground extends StatelessWidget {
  const BgSpaceBackground(
      {super.key, required this.fancy, required this.visual});
  final bool fancy;
  final NxThemeColors visual;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -0.2),
          radius: 1.3,
          colors: <Color>[
            visual.backgroundMid,
            visual.background,
            visual.background
          ],
          stops: const <double>[0, 0.55, 1],
        ),
      ),
      child:
          CustomPaint(painter: _StarPainter(fancy ? 140 : 60, visual.accent)),
    );
  }
}

class _StarPainter extends CustomPainter {
  _StarPainter(this.count, this.accent);
  final int count;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final Random r = Random(7);
    final Paint p = Paint();
    for (int i = 0; i < count; i++) {
      final double x = r.nextDouble() * size.width;
      final double y = r.nextDouble() * size.height;
      final double s = r.nextDouble() * 1.6 + 0.3;
      p.color = (i % 7 == 0 ? accent : const Color(0xFFEAF6FF))
          .withValues(alpha: 0.25 + r.nextDouble() * 0.6);
      canvas.drawCircle(Offset(x, y), s, p);
    }
  }

  @override
  bool shouldRepaint(covariant _StarPainter oldDelegate) =>
      oldDelegate.count != count || oldDelegate.accent != accent;
}

/// Glassy pill button used by the HUD.
class BgButton extends StatelessWidget {
  const BgButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.color,
    this.primary = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final Color? color;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onTap != null;
    final NxThemeColors visual = NxThemeColors.of(context);
    final Color accent = color ?? visual.accent;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              gradient: primary
                  ? LinearGradient(
                      colors: <Color>[accent, accent.withValues(alpha: 0.76)])
                  : null,
              color: primary ? null : visual.surface,
              border:
                  Border.all(color: accent.withValues(alpha: 0.8), width: 1.2),
              boxShadow: primary && enabled
                  ? <BoxShadow>[
                      BoxShadow(
                          color: accent.withValues(alpha: 0.32), blurRadius: 16)
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(icon,
                    size: 18, color: primary ? visual.background : accent),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: primary ? visual.background : visual.text,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
