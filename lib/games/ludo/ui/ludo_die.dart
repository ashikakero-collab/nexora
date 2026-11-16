import 'dart:math';

import 'package:flutter/material.dart';

/// Procedural premium die: bevelled glass cube with a coloured glow.
/// While [rolling] it tumbles (t = 0..1) showing flickering faces.
class LudoDie extends StatelessWidget {
  const LudoDie({
    super.key,
    required this.value,
    required this.color,
    required this.size,
    this.rolling = false,
    this.t = 0,
    this.glow = true,
  });

  final int? value;
  final Color color;
  final double size;
  final bool rolling;
  final double t;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final int face =
        rolling ? 1 + ((t * 23).floor() * 5 + 2) % 6 : (value ?? 6);
    final double angle =
        rolling ? sin(t * pi * 4) * 0.6 * (1 - t) + t * pi * 2 : 0;
    final double hop =
        rolling ? (sin(t * pi * 3)).abs() * size * 0.35 * (1 - t) : 0;
    return AnimatedScale(
      scale: rolling ? 1.04 : 1,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutBack,
      child: Transform.translate(
        offset: Offset(0, -hop),
        child: Transform.rotate(
          angle: angle,
          child: CustomPaint(
            size: Size(size, size),
            painter: _DiePainter(
              face: face,
              color: color,
              blank: value == null && !rolling,
              glow: glow,
            ),
          ),
        ),
      ),
    );
  }
}

List<Offset> ludoPips(int v) {
  const double a = 0.28;
  const double b = 0.72;
  const double c = 0.5;
  switch (v) {
    case 1:
      return const <Offset>[Offset(c, c)];
    case 2:
      return const <Offset>[Offset(a, a), Offset(b, b)];
    case 3:
      return const <Offset>[Offset(a, a), Offset(c, c), Offset(b, b)];
    case 4:
      return const <Offset>[
        Offset(a, a),
        Offset(b, a),
        Offset(a, b),
        Offset(b, b)
      ];
    case 5:
      return const <Offset>[
        Offset(a, a),
        Offset(b, a),
        Offset(c, c),
        Offset(a, b),
        Offset(b, b)
      ];
    default:
      return const <Offset>[
        Offset(a, a),
        Offset(b, a),
        Offset(a, c),
        Offset(b, c),
        Offset(a, b),
        Offset(b, b),
      ];
  }
}

class _DiePainter extends CustomPainter {
  _DiePainter({
    required this.face,
    required this.color,
    required this.blank,
    required this.glow,
  });

  final int face;
  final Color color;
  final bool blank;
  final bool glow;

  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.width;
    final Rect body = Rect.fromLTWH(0, 0, s, s);
    final RRect rr = RRect.fromRectAndRadius(body, Radius.circular(s * 0.22));
    if (glow) {
      canvas.drawRRect(
          rr,
          Paint()
            ..color = color.withValues(alpha: 0.55)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.18));
    }
    // Depth (bottom bevel).
    canvas.drawRRect(rr.shift(Offset(0, s * 0.07)),
        Paint()..color = Color.lerp(color, Colors.black, 0.6) ?? color);
    canvas.drawRRect(rr.shift(Offset(0, s * 0.045)),
        Paint()..color = Color.lerp(color, Colors.black, 0.55) ?? color);
    canvas.drawRRect(
        rr,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              const Color(0xFFFFFFFF),
              Color.lerp(color, Colors.white, 0.75) ?? color,
              Color.lerp(color, Colors.white, 0.35) ?? color,
            ],
          ).createShader(body));
    canvas.drawRRect(
        rr.deflate(s * 0.03),
        Paint()
          ..color = color.withValues(alpha: 0.9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.04);
    // Gloss.
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(s * 0.12, s * 0.08, s * 0.76, s * 0.3),
            Radius.circular(s * 0.15)),
        Paint()..color = Colors.white.withValues(alpha: 0.35));
    if (blank) {
      final TextPainter tp = TextPainter(
        text: TextSpan(
          text: '?',
          style: TextStyle(
              color: const Color(0xFF0A0F2C),
              fontSize: s * 0.5,
              fontWeight: FontWeight.w900),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset((s - tp.width) / 2, (s - tp.height) / 2));
      return;
    }
    final double pr = s * 0.085;
    for (final Offset o in ludoPips(face)) {
      final Offset c = Offset(o.dx * s, o.dy * s);
      canvas.drawCircle(c, pr, Paint()..color = const Color(0xFF0A0F2C));
      canvas.drawCircle(c.translate(-pr * 0.3, -pr * 0.3), pr * 0.35,
          Paint()..color = color.withValues(alpha: 0.8));
    }
  }

  @override
  bool shouldRepaint(covariant _DiePainter oldDelegate) =>
      oldDelegate.face != face ||
      oldDelegate.color != color ||
      oldDelegate.blank != blank ||
      oldDelegate.glow != glow;
}
