import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/nx_theme.dart';
import '../core/uno_models.dart';
import 'uno_card_widget.dart';

/// Felt table background with a soft spotlight and (optionally) stars.
class UnoTableBackground extends StatelessWidget {
  const UnoTableBackground(
      {super.key, required this.fancy, required this.accent});

  final bool fancy;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final NxThemeColors visual = NxThemeColors.of(context);
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -0.1),
              radius: 1.15,
              colors: <Color>[
                Color.lerp(visual.backgroundMid, visual.accentSecondary, 0.18)!,
                visual.backgroundMid,
                visual.background,
              ],
              stops: const <double>[0.0, 0.55, 1.0],
            ),
          ),
        ),
        if (fancy)
          const RepaintBoundary(
            child: CustomPaint(painter: _StarDustPainter()),
          ),
        Center(
          child: FractionallySizedBox(
            widthFactor: 0.96,
            heightFactor: 0.5,
            child: AnimatedContainer(
              duration: NxMotion.slow,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(400),
                gradient: RadialGradient(
                  colors: <Color>[
                    visual.accent.withValues(alpha: 0.16),
                    visual.accentSecondary.withValues(alpha: 0.10),
                    const Color(0x00000000),
                  ],
                  stops: const <double>[0.0, 0.7, 1.0],
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                      color: accent.withValues(alpha: 0.18),
                      blurRadius: 60,
                      spreadRadius: 4),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StarDustPainter extends CustomPainter {
  const _StarDustPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final math.Random r = math.Random(42);
    final Paint p = Paint();
    for (int i = 0; i < 90; i++) {
      final double x = r.nextDouble() * size.width;
      final double y = r.nextDouble() * size.height;
      final double a = 0.15 + r.nextDouble() * 0.55;
      p.color = NxColors.iceWhite.withValues(alpha: a);
      canvas.drawCircle(Offset(x, y), 0.4 + r.nextDouble() * 1.3, p);
    }
  }

  @override
  bool shouldRepaint(covariant _StarDustPainter oldDelegate) => false;
}

/// Rotating orbit ring that shows the play direction and the active colour.
class UnoDirectionRing extends StatelessWidget {
  const UnoDirectionRing({
    super.key,
    required this.animation,
    required this.direction,
    required this.color,
    required this.size,
  });

  final Animation<double> animation;
  final int direction;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        width: size,
        height: size * 0.62,
        child: AnimatedBuilder(
          animation: animation,
          builder: (BuildContext context, Widget? child) {
            return CustomPaint(
              painter: _RingPainter(
                  t: animation.value, direction: direction, color: color),
            );
          },
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.t, required this.direction, required this.color});

  final double t;
  final int direction;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect oval = (Offset.zero & size).deflate(6);
    canvas.drawOval(
      oval,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..color = color.withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawOval(
      oval,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = color.withValues(alpha: 0.7),
    );
    final Offset c = oval.center;
    final double rx = oval.width / 2;
    final double ry = oval.height / 2;
    final Paint head = Paint()..color = color;
    for (int i = 0; i < 4; i++) {
      final double ang = (t * direction + i / 4.0) * 2 * math.pi;
      final Offset p = c + Offset(math.cos(ang) * rx, math.sin(ang) * ry);
      // Tangent of the ellipse in the direction of travel.
      final Offset tan = Offset(-math.sin(ang) * rx, math.cos(ang) * ry) *
          direction.toDouble();
      final double len = tan.distance == 0 ? 1 : tan.distance;
      final Offset d = tan / len;
      final Offset nrm = Offset(-d.dy, d.dx);
      final Path path = Path()
        ..moveTo(p.dx + d.dx * 9, p.dy + d.dy * 9)
        ..lineTo(p.dx - d.dx * 6 + nrm.dx * 6, p.dy - d.dy * 6 + nrm.dy * 6)
        ..lineTo(p.dx - d.dx * 6 - nrm.dx * 6, p.dy - d.dy * 6 - nrm.dy * 6)
        ..close();
      canvas.drawPath(path, head);
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.t != t || old.direction != direction || old.color != color;
}

/// One opponent seat at the top of the table.
class UnoSeatView extends StatelessWidget {
  const UnoSeatView({
    super.key,
    required this.name,
    required this.cardCount,
    required this.active,
    required this.isBot,
    required this.nxSafe,
    required this.pulse,
    required this.seatColor,
    required this.visible,
  });

  final String name;
  final int cardCount;
  final bool active;
  final bool isBot;
  final bool nxSafe;
  final Animation<double> pulse;
  final Color seatColor;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    final int shown = math.min(cardCount, 7);
    return SizedBox(
      width: 112,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          AnimatedBuilder(
            animation: pulse,
            builder: (BuildContext context, Widget? child) {
              final double g = active
                  ? 0.45 + 0.4 * math.sin(pulse.value * 2 * math.pi).abs()
                  : 0.0;
              return Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: <Color>[
                      seatColor,
                      Color.lerp(seatColor, NxColors.navyDeep, 0.6)!
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(
                      color: active ? NxColors.iceWhite : NxColors.glassBorder,
                      width: active ? 2.2 : 1),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                        color: seatColor.withValues(alpha: g),
                        blurRadius: 18,
                        spreadRadius: 2),
                  ],
                ),
                child: child,
              );
            },
            child: Icon(isBot ? Icons.smart_toy_rounded : Icons.person_rounded,
                color: NxColors.iceWhite, size: 24),
          ),
          const SizedBox(height: 4),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: active ? FontWeight.w800 : FontWeight.w600,
              color: active ? NxColors.iceWhite : NxColors.textDim,
            ),
          ),
          const SizedBox(height: 4),
          AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: NxMotion.normal,
            child: SizedBox(
              height: 40,
              width: 104,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: <Widget>[
                  for (int i = 0; i < shown; i++)
                    Positioned(
                      left: 52 - 13 + (i - (shown - 1) / 2) * 9,
                      top: 2,
                      child: Transform.rotate(
                        angle: (i - (shown - 1) / 2) * 0.12,
                        alignment: Alignment.bottomCenter,
                        child: const UnoCardView(width: 26, faceUp: false),
                      ),
                    ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: NxColors.navyDeep.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(10),
                        border:
                            Border.all(color: seatColor.withValues(alpha: 0.8)),
                      ),
                      child: Text(
                        '$cardCount',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: NxColors.iceWhite),
                      ),
                    ),
                  ),
                  if (cardCount == 1)
                    Positioned(
                      left: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: nxSafe ? NxColors.success : NxColors.danger,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'NX!',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: NxColors.navyDeep),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-screen colour picker for wild cards.
class UnoColorPicker extends StatelessWidget {
  const UnoColorPicker(
      {super.key,
      required this.isFa,
      required this.onPick,
      required this.onCancel});

  final bool isFa;
  final ValueChanged<UnoColor> onPick;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xB3050818),
      child: Center(
        child: Container(
          width: 300,
          padding: const EdgeInsets.all(NxSpace.lg),
          decoration: BoxDecoration(
            color: NxColors.navySoft.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(NxRadius.lg),
            border: Border.all(color: NxColors.glassBorder),
            boxShadow: const <BoxShadow>[
              BoxShadow(color: Color(0x667B3FF2), blurRadius: 40)
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                isFa ? 'رنگ بعدی را انتخاب کن' : 'Choose the next colour',
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: NxColors.iceWhite),
              ),
              const SizedBox(height: NxSpace.lg),
              Wrap(
                spacing: 18,
                runSpacing: 18,
                alignment: WrapAlignment.center,
                children: <Widget>[
                  for (final UnoColor c in UnoColor.values)
                    GestureDetector(
                      onTap: () => onPick(c),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Container(
                            width: 84,
                            height: 84,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: <Color>[
                                  Color.lerp(
                                      unoColorValue(c), Colors.white, 0.35)!,
                                  unoColorValue(c),
                                  Color.lerp(unoColorValue(c),
                                      NxColors.navyDeep, 0.4)!,
                                ],
                              ),
                              boxShadow: <BoxShadow>[
                                BoxShadow(
                                    color:
                                        unoColorValue(c).withValues(alpha: 0.6),
                                    blurRadius: 22),
                              ],
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            unoColorName(c, isFa),
                            style: const TextStyle(
                                fontSize: 12,
                                color: NxColors.textDim,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: NxSpace.md),
              TextButton(
                onPressed: onCancel,
                child: Text(isFa ? 'انصراف' : 'Cancel',
                    style: const TextStyle(color: NxColors.textDim)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Glowing pill button used for NX!, Catch, Pass.
class UnoActionButton extends StatelessWidget {
  const UnoActionButton(
      {super.key,
      required this.label,
      required this.color,
      required this.onTap,
      this.icon});

  final String label;
  final Color color;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final NxThemeColors visual = NxThemeColors.of(context);
    final Color foreground =
        color.computeLuminance() < 0.38 ? Colors.white : visual.background;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
                colors: <Color>[Color.lerp(color, Colors.white, 0.25)!, color]),
            border: Border.all(color: visual.text.withValues(alpha: 0.28)),
            boxShadow: <BoxShadow>[
              BoxShadow(color: color.withValues(alpha: 0.42), blurRadius: 16)
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, size: 18, color: foreground),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: foreground,
                      letterSpacing: 0.4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
