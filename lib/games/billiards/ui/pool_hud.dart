import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/theme/nx_theme.dart';
import '../core/pool_config.dart';
import 'pool_scene.dart';

/// Small procedural ball for HUD racks.
class PoolMiniBall extends StatelessWidget {
  const PoolMiniBall(
      {super.key, required this.id, this.size = 16, this.dim = false});
  final int id;
  final double size;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _MiniBallPainter(id, dim)),
    );
  }
}

class _MiniBallPainter extends CustomPainter {
  _MiniBallPainter(this.id, this.dim);
  final int id;
  final bool dim;

  @override
  void paint(Canvas canvas, Size size) {
    final double r = size.width / 2;
    final Offset c = Offset(r, r);
    final Color base = poolBallColor(id);
    final bool stripe = id >= 9;
    final double op = dim ? 0.28 : 1.0;
    final Color body = (stripe || id == 0) ? const Color(0xFFF7F4EA) : base;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader =
            ui.Gradient.radial(Offset(r * 0.7, r * 0.6), r * 1.4, <Color>[
          Color.lerp(body, Colors.white, 0.35)!.withOpacity(op),
          body.withOpacity(op),
          Color.lerp(body, Colors.black, 0.5)!.withOpacity(op)
        ], const <double>[
          0,
          0.5,
          1
        ]),
    );
    if (stripe) {
      canvas.save();
      canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));
      canvas.drawRect(Rect.fromLTRB(0, r * 0.5, size.width, r * 1.5),
          Paint()..color = base.withOpacity(op));
      canvas.restore();
    }
    if (id != 0) {
      canvas.drawCircle(
          c, r * 0.48, Paint()..color = Colors.white.withOpacity(op));
      final TextPainter tp = TextPainter(
        text: TextSpan(
          text: '$id',
          style: TextStyle(
              color: Colors.black.withOpacity(op),
              fontSize: r * 0.62,
              fontWeight: FontWeight.w800,
              height: 1.0),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(r - tp.width / 2, r - tp.height / 2));
    }
    canvas.drawCircle(Offset(r * 0.66, r * 0.6), r * 0.22,
        Paint()..color = Colors.white.withOpacity(0.8 * op));
  }

  @override
  bool shouldRepaint(covariant _MiniBallPainter oldDelegate) =>
      oldDelegate.id != id || oldDelegate.dim != dim;
}

/// Player card: name, active glow, group rack (remaining balls bright, potted dim).
class PoolPlayerCard extends StatelessWidget {
  const PoolPlayerCard({
    super.key,
    required this.name,
    required this.subtitle,
    required this.group,
    required this.pottedIds,
    required this.active,
    required this.accent,
    required this.onEight,
    required this.alignEnd,
    required this.accentSecondary,
    required this.motion,
  });

  final String name;
  final String subtitle;
  final PoolGroup group;
  final Set<int> pottedIds;
  final bool active;
  final Color accent;

  /// Group cleared: now shooting at the 8.
  final bool onEight;
  final bool alignEnd;
  final Color accentSecondary;
  final bool motion;

  @override
  Widget build(BuildContext context) {
    final NxThemeColors theme = NxThemeColors.of(context);
    final List<int> ids = group == PoolGroup.solids
        ? const <int>[1, 2, 3, 4, 5, 6, 7]
        : (group == PoolGroup.stripes
            ? const <int>[9, 10, 11, 12, 13, 14, 15]
            : const <int>[]);
    return AnimatedContainer(
      duration: motion ? const Duration(milliseconds: 240) : Duration.zero,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: <Color>[
            theme.surface.withOpacity(0.96),
            (active ? accent : theme.surfaceRaised)
                .withOpacity(active ? 0.42 : 0.82),
          ],
          begin: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
          end: alignEnd ? Alignment.centerLeft : Alignment.centerRight,
        ),
        border: Border.all(
            color: active ? accent : theme.border.withOpacity(0.75),
            width: active ? 1.6 : 1),
        boxShadow: active && motion
            ? <BoxShadow>[
                BoxShadow(color: accent.withOpacity(0.32), blurRadius: 14)
              ]
            : const <BoxShadow>[],
      ),
      child: Column(
        crossAxisAlignment:
            alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: active ? theme.text : theme.muted,
                fontWeight: FontWeight.w800,
                fontSize: 13,
                height: 1.2),
          ),
          const SizedBox(height: 2),
          Text(subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: (group == PoolGroup.stripes ? accentSecondary : accent)
                      .withOpacity(0.98),
                  fontSize: 10.5,
                  height: 1.2)),
          const SizedBox(height: 5),
          SizedBox(
            height: 15,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment:
                  alignEnd ? Alignment.centerRight : Alignment.centerLeft,
              child: ids.isEmpty
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List<Widget>.generate(
                          7,
                          (int i) => Container(
                                width: 10,
                                height: 10,
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 1.5),
                                decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: theme.border.withOpacity(0.75))),
                              )),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        for (final int id in ids)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 1),
                            child: PoolMiniBall(
                                id: id, size: 14, dim: pottedIds.contains(id)),
                          ),
                        if (onEight) ...<Widget>[
                          const SizedBox(width: 4),
                          const PoolMiniBall(id: 8, size: 15),
                        ],
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fine-aim wheel: drag left/right for tiny angle changes.
class PoolFineAimStrip extends StatelessWidget {
  const PoolFineAimStrip(
      {super.key,
      required this.angle,
      required this.enabled,
      required this.onDelta,
      required this.label});
  final double angle;
  final bool enabled;
  final ValueChanged<double> onDelta;
  final String label;

  @override
  Widget build(BuildContext context) {
    final NxThemeColors theme = NxThemeColors.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate:
          enabled ? (DragUpdateDetails d) => onDelta(d.delta.dx) : null,
      child: Container(
        height: 30,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: theme.surfaceRaised.withOpacity(0.96),
          border: Border.all(color: theme.border.withOpacity(0.8)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              CustomPaint(painter: _RidgePainter(angle, enabled, theme.accent)),
              Center(
                child: Text(label,
                    style: TextStyle(
                        color: enabled ? theme.muted : theme.border,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RidgePainter extends CustomPainter {
  _RidgePainter(this.angle, this.enabled, this.accent);
  final double angle;
  final bool enabled;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    const double gap = 9;
    final double off = (angle * 400) % gap;
    final Paint p = Paint()..strokeWidth = 1.4;
    for (double x = -gap + off; x < size.width + gap; x += gap) {
      final double edge = 1 -
          ((x - size.width / 2).abs() / (size.width / 2))
              .clamp(0.0, 1.0)
              .toDouble();
      p.color = (enabled ? accent : const Color(0xFF637188))
          .withOpacity(0.15 + 0.55 * edge);
      canvas.drawLine(Offset(x, 6), Offset(x, size.height - 6), p);
    }
  }

  @override
  bool shouldRepaint(covariant _RidgePainter oldDelegate) =>
      oldDelegate.angle != angle ||
      oldDelegate.enabled != enabled ||
      oldDelegate.accent != accent;
}

/// Pull-back power bar: drag (either direction) from where you touched; release to shoot.
class PoolPowerBar extends StatelessWidget {
  const PoolPowerBar({
    super.key,
    required this.power,
    required this.enabled,
    required this.label,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
  });

  final double power;
  final bool enabled;
  final String label;
  final ValueChanged<double> onStart;
  final void Function(double dx, double width) onUpdate;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final NxThemeColors theme = NxThemeColors.of(context);
    return LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
      final double w = c.maxWidth;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: enabled
            ? (DragStartDetails d) => onStart(d.localPosition.dx)
            : null,
        onHorizontalDragUpdate: enabled
            ? (DragUpdateDetails d) => onUpdate(d.localPosition.dx, w)
            : null,
        onHorizontalDragEnd: enabled ? (DragEndDetails d) => onEnd() : null,
        onHorizontalDragCancel: enabled ? onEnd : null,
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: theme.surfaceRaised.withOpacity(0.96),
            border: Border.all(
                color: enabled ? theme.accent.withOpacity(0.78) : theme.border,
                width: 1.2),
            boxShadow: enabled && power > 0
                ? <BoxShadow>[
                    BoxShadow(
                        color: Color.lerp(
                                theme.accent, theme.accentSecondary, power)!
                            .withOpacity(0.38),
                        blurRadius: 16)
                  ]
                : const <BoxShadow>[],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: Stack(
              children: <Widget>[
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: w * power,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                          colors: <Color>[theme.accent, theme.accentSecondary]),
                    ),
                  ),
                ),
                // tick marks
                for (int i = 1; i < 10; i++)
                  Positioned(
                    left: w * i / 10,
                    top: i == 5 ? 8 : 14,
                    bottom: i == 5 ? 8 : 14,
                    width: 1,
                    child: Container(color: Colors.white.withOpacity(0.18)),
                  ),
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(Icons.keyboard_double_arrow_left_rounded,
                          size: 18,
                          color:
                              Colors.white.withOpacity(enabled ? 0.85 : 0.3)),
                      const SizedBox(width: 6),
                      Text(label,
                          style: TextStyle(
                              color: Colors.white
                                  .withOpacity(enabled ? 0.95 : 0.35),
                              fontWeight: FontWeight.w800,
                              fontSize: 13)),
                      const SizedBox(width: 6),
                      Icon(Icons.keyboard_double_arrow_right_rounded,
                          size: 18,
                          color:
                              Colors.white.withOpacity(enabled ? 0.85 : 0.3)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

/// Cue-ball spin indicator / picker face.
class PoolSpinFace extends StatelessWidget {
  const PoolSpinFace(
      {super.key, required this.side, required this.spin, this.size = 48});
  final double side;
  final double spin;
  final double size;

  @override
  Widget build(BuildContext context) {
    final NxThemeColors theme = NxThemeColors.of(context);
    return SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _SpinPainter(side, spin, theme.accent)));
  }
}

class _SpinPainter extends CustomPainter {
  _SpinPainter(this.side, this.spin, this.accent);
  final double side;
  final double spin;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final double r = size.width / 2;
    final Offset c = Offset(r, r);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = ui.Gradient.radial(
            Offset(r * 0.7, r * 0.6), r * 1.5, const <Color>[
          Color(0xFFFFFFFF),
          Color(0xFFE9E5D8),
          Color(0xFF8E8A80)
        ], const <double>[
          0,
          0.55,
          1
        ]),
    );
    final Paint guide = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, r * 0.03)
      ..color = const Color(0x55000000);
    canvas.drawLine(Offset(r, r * 0.2), Offset(r, r * 1.8), guide);
    canvas.drawLine(Offset(r * 0.2, r), Offset(r * 1.8, r), guide);
    canvas.drawCircle(c, r * 0.5, guide);
    final Offset dot = Offset(r + side * r * 0.72, r - spin * r * 0.72);
    canvas.drawCircle(dot, r * 0.16, Paint()..color = accent);
    canvas.drawCircle(
        dot,
        r * 0.16,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.0, r * 0.04)
          ..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _SpinPainter oldDelegate) =>
      oldDelegate.side != side ||
      oldDelegate.spin != spin ||
      oldDelegate.accent != accent;
}
