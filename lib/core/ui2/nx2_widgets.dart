import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../profile/profile_service.dart';
import '../settings/app_settings.dart';
import 'nx2_assets.dart';
import 'oracle_mascot.dart';

/// NX2 colour tokens: deep cosmic violet, neon magenta/cyan, gold for legendary.
class Nx2 {
  Nx2._();
  static const Color deep = Color(0xFF07031A);
  static const Color night = Color(0xFF120A33);
  static const Color plum = Color(0xFF1E0F4D);
  static const Color violet = Color(0xFF8B3DFF);
  static const Color magenta = Color(0xFFE040FB);
  static const Color cyan = Color(0xFF35D6FF);
  static const Color gold = Color(0xFFFFC857);
  static const Color goldDeep = Color(0xFFB9772A);
  static const Color text = Color(0xFFF4F0FF);
  static const Color muted = Color(0xFFBFB3E6);
  static const Color success = Color(0xFF4BE3A0);
  static const Color danger = Color(0xFFFF5A7A);

  static const LinearGradient neon =
      LinearGradient(colors: <Color>[cyan, violet, magenta]);
  static const LinearGradient goldGrad =
      LinearGradient(colors: <Color>[Color(0xFFFFE7A3), gold, goldDeep]);

  static const TextStyle title = TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w900,
      letterSpacing: 0.8,
      color: text,
      shadows: <Shadow>[Shadow(color: Color(0xAA8B3DFF), blurRadius: 12)]);
  static const TextStyle label =
      TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: text);
}

/// The cosmic castle backdrop (main) or the room backdrop, darkened for contrast.
class Nx2Background extends StatelessWidget {
  const Nx2Background(
      {super.key, this.child, this.room = false, this.dim = 0.45});
  final Widget? child;
  final bool room;
  final double dim;

  @override
  Widget build(BuildContext context) {
    final Size s = MediaQuery.sizeOf(context);
    final int cw = (math.min(s.width, 600) * 2).round();
    return Stack(fit: StackFit.expand, children: <Widget>[
      const ColoredBox(color: Nx2.deep),
      Image.asset(room ? Nx2Assets.bgBgRoom : Nx2Assets.bgBgMain,
          fit: BoxFit.cover,
          cacheWidth: cw,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => const SizedBox.shrink()),
      IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                Nx2.deep.withValues(alpha: dim * 0.6),
                Nx2.deep.withValues(alpha: dim),
                Nx2.deep.withValues(alpha: math.min(1, dim + 0.25)),
              ],
              stops: const <double>[0, 0.55, 1],
            ),
          ),
        ),
      ),
      if (child != null) child!,
    ]);
  }
}

/// Chamfered neon frame painter shared by panels, pills and the dock.
class Nx2FramePainter extends CustomPainter {
  Nx2FramePainter({
    required this.cut,
    this.fill,
    this.border = Nx2.neon,
    this.strokeWidth = 1.4,
    this.glow = 0.35,
    this.gems = false,
  });
  final double cut;
  final Gradient? fill;
  final Gradient border;
  final double strokeWidth;
  final double glow;
  final bool gems;

  static Path chamfer(Rect r, double c) {
    final double k = math.min(c, math.min(r.width, r.height) / 2);
    return Path()
      ..moveTo(r.left + k, r.top)
      ..lineTo(r.right - k, r.top)
      ..lineTo(r.right, r.top + k)
      ..lineTo(r.right, r.bottom - k)
      ..lineTo(r.right - k, r.bottom)
      ..lineTo(r.left + k, r.bottom)
      ..lineTo(r.left, r.bottom - k)
      ..lineTo(r.left, r.top + k)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final Rect r = (Offset.zero & size).deflate(strokeWidth / 2);
    final Path p = chamfer(r, cut);
    if (glow > 0) {
      canvas.drawPath(
          p,
          Paint()
            ..color = Nx2.violet.withValues(alpha: glow * 0.55)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 6
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7));
    }
    canvas.drawPath(
        p,
        Paint()
          ..shader = (fill ??
                  const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[Color(0xE62A1466), Color(0xEB100830)],
                  ))
              .createShader(r));
    // inner sheen
    canvas.save();
    canvas.clipPath(p);
    canvas.drawRect(
        Rect.fromLTWH(r.left, r.top, r.width, r.height * 0.45),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              Colors.white.withValues(alpha: 0.07),
              Colors.white.withValues(alpha: 0)
            ],
          ).createShader(r));
    canvas.restore();
    canvas.drawPath(
        p,
        Paint()
          ..shader = border.createShader(r)
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth);
    if (gems) {
      final Paint g = Paint()..shader = Nx2.neon.createShader(r);
      for (final Offset o in <Offset>[
        Offset(r.center.dx, r.top),
        Offset(r.center.dx, r.bottom)
      ]) {
        final Path d = Path()
          ..moveTo(o.dx, o.dy - 5)
          ..lineTo(o.dx + 5, o.dy)
          ..lineTo(o.dx, o.dy + 5)
          ..lineTo(o.dx - 5, o.dy)
          ..close();
        canvas.drawPath(d, g);
      }
    }
  }

  @override
  bool shouldRepaint(covariant Nx2FramePainter old) =>
      old.cut != cut ||
      old.fill != fill ||
      old.border != border ||
      old.glow != glow ||
      old.gems != gems;
}

/// Glass panel in the NX2 style (chamfered neon frame).
class Nx2Panel extends StatelessWidget {
  const Nx2Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.onTap,
    this.cut = 14,
    this.gold = false,
    this.tint,
    this.borderColor,
    this.glow = 0.35,
    this.gems = false,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double cut;
  final bool gold;
  final Color? tint;
  final Color? borderColor;
  final double glow;
  final bool gems;

  @override
  Widget build(BuildContext context) {
    final Gradient border = borderColor != null
        ? LinearGradient(colors: <Color>[
            borderColor!,
            Color.lerp(borderColor!, Nx2.magenta, 0.4) ?? borderColor!
          ])
        : (gold ? Nx2.goldGrad : Nx2.neon);
    final Gradient? fill = tint == null
        ? (gold
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[Color(0xE63A2410), Color(0xEB140A26)])
            : null)
        : LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              Color.alphaBlend(tint!, const Color(0xE62A1466)),
              Color.alphaBlend(tint!, const Color(0xEB100830)),
            ],
          );
    Widget body = CustomPaint(
      painter: Nx2FramePainter(
          cut: cut, fill: fill, border: border, glow: glow, gems: gems),
      child: Padding(padding: padding, child: child),
    );
    if (onTap != null) {
      body = _Pressable(onTap: onTap!, child: body);
    }
    return body;
  }
}

/// Scale-down-on-press with a light haptic.
class _Pressable extends StatefulWidget {
  const _Pressable({required this.onTap, required this.child});
  final VoidCallback onTap;
  final Widget child;
  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _down ? 0.96 : 1,
        duration: const Duration(milliseconds: 110),
        child: widget.child,
      ),
    );
  }
}

/// Public wrapper of the press animation for art tiles.
class Nx2Pressable extends StatelessWidget {
  const Nx2Pressable({super.key, required this.onTap, required this.child});
  final VoidCallback onTap;
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      _Pressable(onTap: onTap, child: child);
}

enum Nx2ButtonKind { pink, violet, cyan }

/// Art button (sliced from the owner's panels/buttons sheet), 9-slice stretched.
class Nx2Button extends StatelessWidget {
  const Nx2Button({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.kind = Nx2ButtonKind.violet,
    this.height = 52,
    this.fontSize = 16,
  });
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final Nx2ButtonKind kind;
  final double height;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final String asset = switch (kind) {
      Nx2ButtonKind.pink => Nx2Assets.framesBtnPink,
      Nx2ButtonKind.violet => Nx2Assets.framesBtnViolet,
      Nx2ButtonKind.cyan => Nx2Assets.framesBtnCyan,
    };
    // Source buttons are ~460x170 px; keep their rounded ends, stretch the middle.
    final double scale = 170 / height;
    final Widget face = Opacity(
      opacity: onTap == null ? 0.45 : 1,
      child: Container(
        height: height,
        padding: EdgeInsets.symmetric(horizontal: height * 0.45),
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage(asset),
            centerSlice: const Rect.fromLTRB(76, 56, 384, 112),
            scale: scale,
          ),
        ),
        alignment: Alignment.center,
        child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, color: Colors.white, size: fontSize + 4),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: fontSize,
                        letterSpacing: 0.8,
                        shadows: const <Shadow>[
                          Shadow(color: Color(0x99000000), blurRadius: 6)
                        ])),
              ),
            ]),
      ),
    );
    if (onTap == null) return face;
    return _Pressable(onTap: onTap!, child: face);
  }
}

/// Ornate title banner (winged violet plate) with centred text.
class Nx2Banner extends StatelessWidget {
  const Nx2Banner(
      {super.key, required this.text, this.height = 58, this.wings = false});
  final String text;
  final double height;
  final bool wings;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Stack(alignment: Alignment.center, children: <Widget>[
        Positioned.fill(
          child: Image.asset(
              wings ? Nx2Assets.framesBannerWingsViolet : Nx2Assets.framesBannerViolet,
              fit: BoxFit.fill,
              cacheWidth: 700,
              errorBuilder: (_, __, ___) => const SizedBox.shrink()),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: height * 1.1),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(text, style: Nx2.title.copyWith(fontSize: height * 0.3)),
          ),
        ),
      ]),
    );
  }
}

/// Avatar inside the winged crystal ring.
class Nx2AvatarRing extends StatelessWidget {
  const Nx2AvatarRing(
      {super.key, this.size = 64, this.initial = '?', this.purple = false});
  final double size;
  final String initial;
  final bool purple;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size * 1.12,
      height: size,
      child: Stack(alignment: Alignment.center, children: <Widget>[
        Positioned.fill(
          child: Image.asset(
              purple ? Nx2Assets.framesRingWingsPurple : Nx2Assets.framesRingWingsBlue,
              fit: BoxFit.contain,
              cacheWidth: (size * 3).round(),
              errorBuilder: (_, __, ___) => const SizedBox.shrink()),
        ),
        Container(
          width: size * 0.46,
          height: size * 0.46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const RadialGradient(
                colors: <Color>[Color(0xFF4A35B5), Color(0xFF160C40)]),
            border: Border.all(color: Nx2.cyan.withValues(alpha: 0.6)),
          ),
          alignment: Alignment.center,
          child: Text(initial,
              style: TextStyle(
                  fontSize: size * 0.22,
                  fontWeight: FontWeight.w900,
                  color: Nx2.text)),
        ),
      ]),
    );
  }
}

/// Neon XP/progress bar in a chamfered track.
class Nx2Progress extends StatelessWidget {
  const Nx2Progress(
      {super.key, required this.value, this.height = 9, this.gold = false});
  final double value;
  final double height;
  final bool gold;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: _BarPainter(value.clamp(0.0, 1.0), gold),
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter(this.v, this.gold);
  final double v;
  final bool gold;
  @override
  void paint(Canvas canvas, Size size) {
    final Rect r = Offset.zero & size;
    final double c = size.height / 2;
    final Path track = Nx2FramePainter.chamfer(r, c);
    canvas.drawPath(track, Paint()..color = const Color(0xCC0A0524));
    canvas.drawPath(
        track,
        Paint()
          ..color = Nx2.violet.withValues(alpha: 0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1);
    if (v <= 0) return;
    final Rect f = Rect.fromLTWH(r.left + 1.5, r.top + 1.5,
        math.max(c * 2, (r.width - 3) * v), r.height - 3);
    final Path fill = Nx2FramePainter.chamfer(f, c - 1.5);
    canvas.drawPath(
        fill,
        Paint()
          ..shader = (gold
                  ? Nx2.goldGrad
                  : const LinearGradient(
                      colors: <Color>[Nx2.violet, Nx2.cyan]))
              .createShader(f));
    canvas.drawPath(
        fill,
        Paint()
          ..color = (gold ? Nx2.gold : Nx2.cyan).withValues(alpha: 0.45)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
  }

  @override
  bool shouldRepaint(covariant _BarPainter old) =>
      old.v != v || old.gold != gold;
}

/// Coin / level pill in the HUD.
class Nx2Stat extends StatelessWidget {
  const Nx2Stat(
      {super.key,
      required this.value,
      this.icon = Icons.toll_rounded,
      this.color = Nx2.gold,
      this.onTap,
      this.wiggle});
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  /// When it ticks, the pill gives a little shake (Oracle pokes the coins).
  final Listenable? wiggle;

  @override
  Widget build(BuildContext context) {
    final Widget pill = CustomPaint(
      painter: Nx2FramePainter(
          cut: 9,
          glow: 0.2,
          border: LinearGradient(colors: <Color>[
            color,
            Color.lerp(color, Nx2.magenta, 0.5) ?? color
          ]),
          fill: const LinearGradient(
              colors: <Color>[Color(0xF0180B40), Color(0xF00B0522)])),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 5, 10, 5),
        child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: <Color>[
                Color.lerp(color, Colors.white, 0.45) ?? color,
                color,
              ]),
              boxShadow: <BoxShadow>[
                BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 8)
              ],
            ),
            child: Icon(icon, size: 13, color: const Color(0xFF2A1700)),
          ),
          const SizedBox(width: 6),
          Text(value,
              style: const TextStyle(
                  fontWeight: FontWeight.w900, fontSize: 13, color: Nx2.text)),
        ]),
      ),
    );
    Widget w = pill;
    if (wiggle != null) {
      w = _Wiggle(listenable: wiggle!, child: pill);
    }
    if (onTap != null) w = _Pressable(onTap: onTap!, child: w);
    return w;
  }
}

class _Wiggle extends StatefulWidget {
  const _Wiggle({required this.listenable, required this.child});
  final Listenable listenable;
  final Widget child;
  @override
  State<_Wiggle> createState() => _WiggleState();
}

class _WiggleState extends State<_Wiggle> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 600));
  @override
  void initState() {
    super.initState();
    widget.listenable.addListener(_go);
  }

  void _go() {
    if (mounted) _c.forward(from: 0);
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_go);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, Widget? child) {
        final double t = _c.value;
        final double a = math.sin(t * math.pi * 6) * (1 - t) * 0.18;
        return Transform.rotate(
            angle: a,
            child: Transform.scale(
                scale: 1 + 0.12 * math.sin(t * math.pi), child: child));
      },
      child: widget.child,
    );
  }
}

/// Art tile from the owner's icon sheets with a label underneath.
class Nx2Tile extends StatelessWidget {
  const Nx2Tile({
    super.key,
    required this.asset,
    required this.label,
    required this.onTap,
    this.badge = false,
    this.size = 74,
  });
  final String asset;
  final String label;
  final VoidCallback onTap;
  final bool badge;
  final double size;

  @override
  Widget build(BuildContext context) {
    return _Pressable(
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        SizedBox(
          width: size,
          height: size,
          child: Stack(clipBehavior: Clip.none, children: <Widget>[
            Positioned.fill(
              child: Image.asset(asset,
                  fit: BoxFit.contain,
                  cacheWidth: (size * 2.6).round(),
                  errorBuilder: (_, __, ___) => const Icon(
                      Icons.blur_on_rounded,
                      color: Nx2.cyan,
                      size: 40)),
            ),
            if (badge)
              PositionedDirectional(
                top: 2,
                end: 2,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: Nx2.danger,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 4),
        Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Nx2.label),
      ]),
    );
  }
}

/// Section header: neon bar + title + optional action.
class Nx2SectionHeader extends StatelessWidget {
  const Nx2SectionHeader(
      {super.key, required this.title, this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(children: <Widget>[
      Container(
        width: 4,
        height: 18,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[Nx2.cyan, Nx2.magenta]),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(title,
            style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 15,
                letterSpacing: 0.6,
                color: Nx2.text)),
      ),
      if (action != null)
        GestureDetector(
          onTap: onAction,
          child: Text(action!,
              style: const TextStyle(
                  color: Nx2.cyan, fontWeight: FontWeight.w800, fontSize: 12)),
        ),
    ]);
  }
}

/// Destinations of the bottom dock.
enum Nx2Tab { home, games, oracle, chat, profile }

String nx2TabPath(Nx2Tab t) => switch (t) {
      Nx2Tab.home => '/hub',
      Nx2Tab.games => '/world/nexora_arcade',
      Nx2Tab.oracle => '/oracle',
      Nx2Tab.chat => '/world/orbit_network',
      Nx2Tab.profile => '/world/personal_orbit',
    };

/// Goes to a dock destination: Home is the root; other tabs replace each other on top of it.
void nx2GoTab(BuildContext context, Nx2Tab tab, Nx2Tab? current) {
  if (tab == current) return;
  final String path = nx2TabPath(tab);
  if (tab == Nx2Tab.home) {
    context.go(path);
  } else if (current == null || current == Nx2Tab.home) {
    context.push(path);
  } else {
    context.pushReplacement(path);
  }
}

/// Bottom dock: four neon tabs and the raised ORACLE orb in the middle.
class Nx2Dock extends StatelessWidget {
  const Nx2Dock({super.key, required this.current});
  final Nx2Tab? current;

  @override
  Widget build(BuildContext context) {
    final double bottom = MediaQuery.paddingOf(context).bottom;
    Widget item(Nx2Tab t, IconData icon, String fa, String en) {
      final bool on = t == current;
      return Expanded(
        child: _Pressable(
          onTap: () => nx2GoTab(context, t, current),
          child: Semantics(
            selected: on,
            button: true,
            label: context.tx(fa, en),
            child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: on
                      ? <BoxShadow>[
                          BoxShadow(
                              color: Nx2.cyan.withValues(alpha: 0.55),
                              blurRadius: 16)
                        ]
                      : const <BoxShadow>[],
                ),
                child: ShaderMask(
                  shaderCallback: (Rect r) => (on
                          ? const LinearGradient(
                              colors: <Color>[Nx2.cyan, Nx2.magenta])
                          : const LinearGradient(
                              colors: <Color>[Nx2.muted, Nx2.muted]))
                      .createShader(r),
                  child: Icon(icon, size: 24, color: Colors.white),
                ),
              ),
              Text(context.tx(fa, en),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: on ? Nx2.text : Nx2.muted)),
            ]),
          ),
        ),
      );
    }

    return SizedBox(
      height: 74 + bottom + 18,
      child: Stack(clipBehavior: Clip.none, children: <Widget>[
        Positioned(
          left: 8,
          right: 8,
          bottom: bottom + 6,
          height: 70,
          child: CustomPaint(
            painter: Nx2FramePainter(
                cut: 18,
                glow: 0.5,
                gems: false,
                fill: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[Color(0xFF2A1468), Color(0xFF0C0529)])),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Row(children: <Widget>[
                item(Nx2Tab.home, Icons.home_rounded, 'خانه', 'Home'),
                item(Nx2Tab.games, Icons.sports_esports_rounded, 'بازی‌ها',
                    'Games'),
                const Expanded(child: SizedBox.shrink()),
                item(Nx2Tab.chat, Icons.forum_rounded, 'پیام‌ها', 'Chat'),
                item(Nx2Tab.profile, Icons.person_rounded, 'پروفایل',
                    'Profile'),
              ]),
            ),
          ),
        ),
        Positioned(
          bottom: bottom + 22,
          left: 0,
          right: 0,
          child: Center(
            child: _Pressable(
              onTap: () => nx2GoTab(context, Nx2Tab.oracle, current),
              child: Semantics(
                button: true,
                label: 'ORACLE',
                child: SizedBox(
                  width: 82,
                  height: 82,
                  child: Stack(alignment: Alignment.center, children: <Widget>[
                    Container(
                      width: 62,
                      height: 62,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const RadialGradient(colors: <Color>[
                          Color(0xFF3A1C9A),
                          Color(0xFF0D0630)
                        ]),
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                              color: (current == Nx2Tab.oracle
                                      ? Nx2.cyan
                                      : Nx2.violet)
                                  .withValues(alpha: 0.7),
                              blurRadius: 20),
                        ],
                      ),
                    ),
                    Image.asset(Nx2Assets.framesRingGold,
                        width: 82,
                        height: 82,
                        cacheWidth: 240,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                    const OracleMascot(
                        size: 46, mood: OracleMood.happy, interactive: false),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Top bar for world pages: ornate back button, title plate and wallet.
class Nx2TopBar extends ConsumerWidget implements PreferredSizeWidget {
  const Nx2TopBar(
      {super.key, required this.title, this.actions, this.showWallet = true});
  final String title;
  final List<Widget>? actions;
  final bool showWallet;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ProfileService p = ref.watch(profileProvider);
    final bool canPop = Navigator.of(context).canPop();
    return SafeArea(
      bottom: false,
      child: SizedBox(
        height: 64,
        child: Row(children: <Widget>[
          const SizedBox(width: 6),
          if (canPop)
            _RoundIcon(
              icon: Directionality.of(context) == TextDirection.rtl
                  ? Icons.arrow_forward_rounded
                  : Icons.arrow_back_rounded,
              tooltip: context.tx('بازگشت', 'Back'),
              onTap: () => Navigator.of(context).maybePop(),
            )
          else
            _RoundIcon(
                icon: Icons.home_rounded,
                tooltip: context.tx('خانه', 'Home'),
                onTap: () => context.go('/hub')),
          const SizedBox(width: 6),
          Expanded(
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Nx2.title.copyWith(fontSize: 17)),
          ),
          ...?actions,
          if (showWallet) ...<Widget>[
            const SizedBox(width: 4),
            Nx2Stat(value: '${p.coins}'),
          ],
          const SizedBox(width: 10),
        ]),
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon(
      {required this.icon, required this.onTap, required this.tooltip});
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: _Pressable(
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: CustomPaint(
            painter: Nx2FramePainter(cut: 12, glow: 0.3),
            child: Icon(icon, color: Nx2.text, size: 22),
          ),
        ),
      ),
    );
  }
}

/// Small round icon button in the NX2 style (public).
class Nx2IconButton extends StatelessWidget {
  const Nx2IconButton(
      {super.key,
      required this.icon,
      required this.onTap,
      required this.tooltip});
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  @override
  Widget build(BuildContext context) =>
      _RoundIcon(icon: icon, onTap: onTap, tooltip: tooltip);
}

/// Speech bubble for the mascot.
class Nx2Bubble extends StatelessWidget {
  const Nx2Bubble({super.key, required this.text, this.maxWidth = 220});
  final String text;
  final double maxWidth;
  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Nx2Panel(
        cut: 10,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        borderColor: Nx2.cyan,
        child: Text(text,
            style: const TextStyle(
                fontSize: 12.5, height: 1.35, color: Nx2.text)),
      ),
    );
  }
}
