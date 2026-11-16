import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/assets/app_assets.dart';
import '../../../core/theme/nx_theme.dart';
import '../core/mafia_models.dart';

/// Visual language of the Mafia station: moonlit night, dawn day, glowing cards.
class MafiaStyle {
  MafiaStyle._();

  static const List<Color> nightBg = <Color>[
    Color(0xFF03041A),
    Color(0xFF0A0E33),
    Color(0xFF1B0C3B)
  ];
  static const List<Color> dayBg = <Color>[
    Color(0xFF0B2240),
    Color(0xFF1B3F66),
    Color(0xFF3E2F5E)
  ];
  static const Color blood = Color(0xFFFF3D5A);
  static const Color moon = Color(0xFFEAF0FF);

  static Color roleColor(MafiaRole r) {
    switch (r) {
      case MafiaRole.godfather:
        return NxColors.gold;
      case MafiaRole.mafia:
        return blood;
      case MafiaRole.doctor:
        return NxColors.success;
      case MafiaRole.detective:
        return NxColors.electricBlue;
      case MafiaRole.sniper:
        return const Color(0xFFFFA24C);
      case MafiaRole.citizen:
        return NxColors.turquoise;
    }
  }

  static IconData roleIcon(MafiaRole r) {
    switch (r) {
      case MafiaRole.godfather:
        return Icons.workspace_premium;
      case MafiaRole.mafia:
        return Icons.theater_comedy;
      case MafiaRole.doctor:
        return Icons.medical_services;
      case MafiaRole.detective:
        return Icons.search;
      case MafiaRole.sniper:
        return Icons.gps_fixed;
      case MafiaRole.citizen:
        return Icons.person;
    }
  }

  static Color teamColor(MafiaTeam t) =>
      t == MafiaTeam.mafia ? blood : NxColors.turquoise;
}

// ------------------------------------------------------------- background
class MoonlitBackground extends StatefulWidget {
  const MoonlitBackground(
      {super.key,
      required this.night,
      required this.animate,
      required this.child});
  final bool night;
  final bool animate;
  final Widget child;

  @override
  State<MoonlitBackground> createState() => _MoonlitBackgroundState();
}

class _MoonlitBackgroundState extends State<MoonlitBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 40));
  late final List<_BgStar> _stars;

  @override
  void initState() {
    super.initState();
    final Random r = Random(11);
    _stars = List<_BgStar>.generate(
        110,
        (int i) => _BgStar(r.nextDouble(), r.nextDouble() * 0.75,
            0.4 + r.nextDouble() * 1.4, r.nextDouble()));
    if (widget.animate) _c.repeat();
  }

  @override
  void didUpdateWidget(covariant MoonlitBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate && !_c.isAnimating) _c.repeat();
    if (!widget.animate && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final NxThemeColors visual = NxThemeColors.of(context);
    return TweenAnimationBuilder<double>(
      tween:
          Tween<double>(begin: widget.night ? 1 : 0, end: widget.night ? 1 : 0),
      duration:
          widget.animate ? const Duration(milliseconds: 1400) : Duration.zero,
      curve: Curves.easeInOut,
      builder: (BuildContext context, double nightness, Widget? child) {
        return AnimatedBuilder(
          animation: _c,
          builder: (BuildContext context, Widget? inner) {
            return CustomPaint(
              painter: _StationPainter(
                  stars: _stars,
                  t: _c.value,
                  nightness: nightness,
                  visual: visual),
              child: inner,
            );
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _BgStar {
  _BgStar(this.x, this.y, this.size, this.phase);
  final double x;
  final double y;
  final double size;
  final double phase;
}

class _StationPainter extends CustomPainter {
  _StationPainter(
      {required this.stars,
      required this.t,
      required this.nightness,
      required this.visual});
  final List<_BgStar> stars;
  final NxThemeColors visual;
  final double t;
  final double nightness;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    final List<Color> cols = <Color>[
      for (int i = 0; i < 3; i++)
        Color.lerp(
          i == 0 ? visual.backgroundMid : visual.background,
          i == 1 ? visual.backgroundMid : visual.background,
          nightness,
        )!,
    ];
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: cols)
            .createShader(rect),
    );
    // Stars (fade at day).
    final Paint sp = Paint();
    for (final _BgStar s in stars) {
      final double tw = 0.5 + 0.5 * sin(t * 2 * pi * 4 + s.phase * 6.28);
      sp.color = Colors.white.withValues(alpha: (0.15 + 0.7 * nightness) * tw);
      canvas.drawCircle(
          Offset(s.x * size.width, s.y * size.height), s.size, sp);
    }
    // Moon with halo (night) / dawn planet glow (day).
    final double m = min(size.width, size.height);
    final Offset moonC = Offset(size.width * 0.8, size.height * 0.11);
    final double mr = m * 0.075;
    canvas.drawCircle(
      moonC,
      mr * 3.2,
      Paint()
        ..shader = RadialGradient(colors: <Color>[
          MafiaStyle.moon.withValues(alpha: 0.28 * nightness),
          MafiaStyle.moon.withValues(alpha: 0),
        ]).createShader(Rect.fromCircle(center: moonC, radius: mr * 3.2)),
    );
    canvas.drawCircle(
        moonC,
        mr,
        Paint()
          ..color = MafiaStyle.moon.withValues(alpha: 0.25 + 0.7 * nightness));
    final Paint crater = Paint()
      ..color = const Color(0xFFB8C2E0).withValues(alpha: 0.5 * nightness);
    canvas.drawCircle(moonC + Offset(-mr * 0.3, -mr * 0.2), mr * 0.18, crater);
    canvas.drawCircle(moonC + Offset(mr * 0.35, mr * 0.25), mr * 0.12, crater);
    canvas.drawCircle(moonC + Offset(-mr * 0.05, mr * 0.45), mr * 0.09, crater);
    final double day = 1 - nightness;
    if (day > 0.01) {
      final Offset sunC = Offset(size.width * 0.5, size.height * 1.05);
      canvas.drawCircle(
        sunC,
        size.width * 0.9,
        Paint()
          ..shader = RadialGradient(colors: <Color>[
            const Color(0xFFFFC27A).withValues(alpha: 0.35 * day),
            const Color(0xFFFF7FA8).withValues(alpha: 0.12 * day),
            const Color(0x00FF7FA8),
          ], stops: const <double>[
            0,
            0.5,
            1
          ]).createShader(
              Rect.fromCircle(center: sunC, radius: size.width * 0.9)),
      );
    }
    // Station ring + skyline silhouette.
    final double baseY = size.height * 0.93;
    final Paint ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = visual.accent.withValues(alpha: 0.16 + 0.1 * sin(t * 2 * pi));
    canvas.drawOval(
        Rect.fromCenter(
            center: Offset(size.width / 2, baseY),
            width: size.width * 1.3,
            height: size.height * 0.12),
        ring);
    final Paint sil = Paint()
      ..color = const Color(0xFF02030E).withValues(alpha: 0.85);
    final Paint win = Paint()
      ..color = visual.accent.withValues(alpha: 0.55 * nightness + 0.1);
    final Random r = Random(5);
    double x = 0;
    while (x < size.width) {
      final double w = 18 + r.nextDouble() * 34;
      final double h = 20 + r.nextDouble() * size.height * 0.09;
      canvas.drawRect(
          Rect.fromLTWH(x, baseY - h, w - 3, h + size.height * 0.1), sil);
      for (double wy = baseY - h + 6; wy < baseY - 4; wy += 9) {
        if (r.nextDouble() < 0.35) {
          canvas.drawRect(
              Rect.fromLTWH(x + 4 + r.nextDouble() * (w - 14), wy, 3, 3), win);
        }
      }
      x += w;
    }
  }

  @override
  bool shouldRepaint(covariant _StationPainter old) =>
      old.t != t || old.nightness != nightness || old.visual != visual;
}

// ----------------------------------------------------------------- avatar
class CrewAvatar extends StatelessWidget {
  const CrewAvatar({
    super.key,
    required this.name,
    required this.hue,
    required this.size,
    this.emblem,
    this.dead = false,
    this.glow,
  });

  final String name;
  final double hue;
  final double size;
  final String? emblem;
  final bool dead;
  final Color? glow;

  @override
  Widget build(BuildContext context) {
    final Color a = HSVColor.fromAHSV(1, hue % 360, 0.75, 0.95).toColor();
    final Color b =
        HSVColor.fromAHSV(1, (hue + 40) % 360, 0.85, 0.35).toColor();
    final String initial = name.isEmpty
        ? '?'
        : String.fromCharCode(name.runes.first).toUpperCase();
    final int cache = (size * 2).round();
    Widget inner = Center(
      child: Text(initial,
          style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: size * 0.42)),
    );
    if (emblem != null) {
      inner = Padding(
        padding: EdgeInsets.all(size * 0.12),
        child: ClipOval(
          child: Image.asset(
            AppAssets.disc(emblem!),
            cacheWidth: cache,
            cacheHeight: cache,
            fit: BoxFit.cover,
            errorBuilder: (BuildContext c, Object e, StackTrace? s) => Center(
              child: Text(initial,
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: size * 0.42)),
            ),
          ),
        ),
      );
    }
    Widget av = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
            colors: <Color>[a, b], center: const Alignment(-0.3, -0.4)),
        border: Border.all(
            color: (glow ?? Colors.white)
                .withValues(alpha: glow == null ? 0.35 : 0.95),
            width: 2),
        boxShadow: glow == null
            ? const <BoxShadow>[]
            : <BoxShadow>[
                BoxShadow(
                    color: glow!.withValues(alpha: 0.7),
                    blurRadius: 16,
                    spreadRadius: 1)
              ],
      ),
      child: inner,
    );
    if (dead) {
      av = Stack(alignment: Alignment.center, children: <Widget>[
        Opacity(
          opacity: 0.4,
          child: ColorFiltered(
            colorFilter: const ColorFilter.matrix(<double>[
              0.33, 0.33, 0.33, 0, 0, //
              0.33, 0.33, 0.33, 0, 0, //
              0.33, 0.33, 0.33, 0, 0, //
              0, 0, 0, 1, 0,
            ]),
            child: av,
          ),
        ),
        Icon(Icons.close_rounded, color: MafiaStyle.blood, size: size * 0.7),
      ]);
    }
    return av;
  }
}

// ------------------------------------------------------------- role card
/// Flip card: back (station sigil) -> front (role art with glow).
class RoleCard extends StatefulWidget {
  const RoleCard({
    super.key,
    required this.role,
    required this.flipped,
    required this.isFa,
    required this.animate,
    this.onTap,
    this.width = 220,
  });

  final MafiaRole role;
  final bool flipped;
  final bool isFa;
  final bool animate;
  final VoidCallback? onTap;
  final double width;

  @override
  State<RoleCard> createState() => _RoleCardState();
}

class _RoleCardState extends State<RoleCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 750),
    value: widget.flipped ? 1 : 0,
  );

  @override
  void didUpdateWidget(covariant RoleCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.flipped != widget.flipped) {
      if (!widget.animate) {
        _c.value = widget.flipped ? 1 : 0;
      } else if (widget.flipped) {
        _c.forward();
      } else {
        _c.reverse();
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double w = widget.width;
    final double h = w * 1.42;
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _c,
        builder: (BuildContext context, Widget? _) {
          final double v = Curves.easeInOutBack
              .transform(_c.value.clamp(0.0, 1.0).toDouble())
              .clamp(0.0, 1.0)
              .toDouble();
          final bool front = v >= 0.5;
          final Matrix4 m = Matrix4.identity()
            ..setEntry(3, 2, 0.0012)
            ..rotateY(pi * v);
          Widget face = front ? _front(w, h) : _back(w, h);
          if (front) {
            face = Transform(
                alignment: Alignment.center,
                transform: Matrix4.rotationY(pi),
                child: face);
          }
          return Transform(
              alignment: Alignment.center, transform: m, child: face);
        },
      ),
    );
  }

  Widget _back(double w, double h) {
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            NxThemeColors.of(context).surfaceRaised,
            NxThemeColors.of(context).surface,
            NxThemeColors.of(context).backgroundMid
          ],
        ),
        border: Border.all(
            color: NxThemeColors.of(context)
                .accentSecondary
                .withValues(alpha: 0.8),
            width: 2),
        boxShadow: <BoxShadow>[
          BoxShadow(
              color: NxThemeColors.of(context)
                  .accentSecondary
                  .withValues(alpha: 0.30),
              blurRadius: 24)
        ],
      ),
      child: Stack(children: <Widget>[
        Positioned.fill(child: CustomPaint(painter: _SigilPainter())),
        Align(
          alignment: const Alignment(0, 0.82),
          child: Text(
              widget.isFa ? 'برای دیدن نقش لمس کن' : 'Tap to reveal your role',
              style: const TextStyle(
                  color: NxColors.textDim,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }

  Widget _front(double w, double h) {
    final MafiaRole r = widget.role;
    final Color c = MafiaStyle.roleColor(r);
    return Container(
      width: w,
      height: h,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            c.withValues(alpha: 0.35),
            const Color(0xFF080B26),
            const Color(0xFF05061A)
          ],
        ),
        border: Border.all(color: c, width: 2),
        boxShadow: <BoxShadow>[
          BoxShadow(
              color: c.withValues(alpha: 0.55), blurRadius: 28, spreadRadius: 1)
        ],
      ),
      child: Column(children: <Widget>[
        Text(
            r.isMafia
                ? (widget.isFa ? 'تیم مافیا' : 'MAFIA TEAM')
                : (widget.isFa ? 'تیم شهر' : 'TOWN TEAM'),
            style: TextStyle(
                color: c,
                fontSize: 11,
                letterSpacing: 2,
                fontWeight: FontWeight.w800)),
        const Spacer(),
        Container(
          width: w * 0.42,
          height: w * 0.42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: <Color>[
              c.withValues(alpha: 0.55),
              c.withValues(alpha: 0.05)
            ]),
            boxShadow: <BoxShadow>[
              BoxShadow(color: c.withValues(alpha: 0.6), blurRadius: 30)
            ],
          ),
          child:
              Icon(MafiaStyle.roleIcon(r), color: Colors.white, size: w * 0.22),
        ),
        const SizedBox(height: 12),
        Text(widget.isFa ? r.labelFa : r.labelEn,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Text(widget.isFa ? r.descFa : r.descEn,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: NxColors.textDim, fontSize: 11.5, height: 1.35)),
        const Spacer(),
      ]),
    );
  }
}

class _SigilPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Offset c = Offset(size.width / 2, size.height * 0.45);
    final double r = size.width * 0.32;
    final Paint p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    for (int i = 0; i < 4; i++) {
      p.color = (i.isEven ? NxColors.violet : NxColors.electricBlue)
          .withValues(alpha: 0.55 - i * 0.1);
      canvas.drawCircle(c, r * (1 - i * 0.2), p);
    }
    canvas.drawCircle(
        c, r * 0.28, Paint()..color = MafiaStyle.moon.withValues(alpha: 0.85));
    canvas.drawCircle(c + Offset(r * 0.1, -r * 0.06), r * 0.24,
        Paint()..color = const Color(0xFF0E0B2E));
    final Paint tick = Paint()
      ..color = NxColors.gold.withValues(alpha: 0.7)
      ..strokeWidth = 2;
    for (int i = 0; i < 12; i++) {
      final double a = i * pi / 6;
      canvas.drawLine(c + Offset(cos(a), sin(a)) * r * 1.02,
          c + Offset(cos(a), sin(a)) * r * 1.12, tick);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ----------------------------------------------------------- phase banner
class PhaseBanner extends StatelessWidget {
  const PhaseBanner(
      {super.key,
      required this.title,
      required this.subtitle,
      required this.icon,
      required this.color,
      required this.animate});
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final Widget body =
        Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
      Icon(icon,
          color: color,
          size: 56,
          shadows: <Shadow>[Shadow(color: color, blurRadius: 24)]),
      const SizedBox(height: 10),
      Text(title,
          textAlign: TextAlign.center,
          style: TextStyle(
              color: NxThemeColors.of(context).text,
              fontSize: 30,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
              shadows: <Shadow>[Shadow(color: color, blurRadius: 18)])),
      const SizedBox(height: 6),
      Text(subtitle,
          textAlign: TextAlign.center,
          style:
              TextStyle(color: NxThemeColors.of(context).muted, fontSize: 14)),
    ]);
    if (!animate) return body;
    return TweenAnimationBuilder<double>(
      key: ValueKey<String>(title + subtitle),
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (BuildContext context, double v, Widget? child) {
        return Opacity(
            opacity: v,
            child: Transform.scale(scale: 0.85 + 0.15 * v, child: child));
      },
      child: body,
    );
  }
}

/// Glowing primary action button.
class GlowButton extends StatelessWidget {
  const GlowButton(
      {super.key,
      required this.label,
      required this.onTap,
      this.color = NxColors.electricBlue,
      this.icon});
  final String label;
  final VoidCallback? onTap;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final NxThemeColors visual = NxThemeColors.of(context);
    final bool enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: enabled
                    ? <Color>[
                        Color.lerp(color, visual.accent, 0.12)!,
                        color.withValues(alpha: 0.78)
                      ]
                    : <Color>[visual.surfaceRaised, visual.surface],
              ),
              boxShadow: enabled
                  ? <BoxShadow>[
                      BoxShadow(
                          color: color.withValues(alpha: 0.45), blurRadius: 16)
                    ]
                  : const <BoxShadow>[],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, size: 18, color: NxColors.navyDeep),
                const SizedBox(width: 6)
              ],
              Flexible(
                child: Text(label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: NxColors.navyDeep,
                        fontWeight: FontWeight.w900,
                        fontSize: 14)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Small translucent outline button.
class GhostButton extends StatelessWidget {
  const GhostButton(
      {super.key,
      required this.label,
      required this.onTap,
      this.color = NxColors.iceWhite,
      this.icon});
  final String label;
  final VoidCallback? onTap;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final NxThemeColors visual = NxThemeColors.of(context);
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: onTap == null
                  ? visual.surface
                  : color.withValues(alpha: 0.10),
              border: Border.all(
                  color: onTap == null
                      ? visual.border
                      : color.withValues(alpha: 0.62)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 5)
              ],
              Text(label,
                  style: TextStyle(
                      color: color, fontWeight: FontWeight.w700, fontSize: 13)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Dark glass panel used throughout the game.
class MafiaPanel extends StatelessWidget {
  const MafiaPanel(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(14),
      this.accent});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final NxThemeColors visual = NxThemeColors.of(context);
    final Color edge = accent ?? visual.accent;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[visual.surfaceRaised, visual.surface]),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: edge.withValues(alpha: 0.52)),
        boxShadow: <BoxShadow>[
          BoxShadow(color: edge.withValues(alpha: 0.12), blurRadius: 20)
        ],
      ),
      child: child,
    );
  }
}
