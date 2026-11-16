import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/nx_theme.dart';
import '../core/uno_models.dart';

/// NEXORA colour for each card suit.
Color unoColorValue(UnoColor c) {
  switch (c) {
    case UnoColor.turquoise:
      return NxColors.turquoise;
    case UnoColor.violet:
      return NxColors.violet;
    case UnoColor.gold:
      return NxColors.gold;
    case UnoColor.pink:
      return NxColors.pink;
  }
}

String unoColorName(UnoColor c, bool isFa) {
  switch (c) {
    case UnoColor.turquoise:
      return isFa ? 'فیروزه‌ای' : 'Turquoise';
    case UnoColor.violet:
      return isFa ? 'بنفش' : 'Violet';
    case UnoColor.gold:
      return isFa ? 'طلایی' : 'Gold';
    case UnoColor.pink:
      return isFa ? 'صورتی' : 'Pink';
  }
}

/// Card aspect ratio (width / height).
const double kUnoCardAspect = 0.68;

/// A procedurally drawn NX card (face or back).
class UnoCardView extends StatelessWidget {
  const UnoCardView({
    super.key,
    required this.width,
    this.card,
    this.faceUp = true,
    this.glow = false,
    this.dim = false,
    this.wildColor,
  });

  final double width;
  final UnoCard? card;
  final bool faceUp;
  final bool glow;
  final bool dim;

  /// Colour chosen for a wild card on the discard pile (shown as a ring).
  final UnoColor? wildColor;

  @override
  Widget build(BuildContext context) {
    final double h = width / kUnoCardAspect;
    return SizedBox(
      width: width,
      height: h,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _UnoCardPainter(
            card: card,
            faceUp: faceUp && card != null,
            glow: glow,
            dim: dim,
            wildColor: wildColor,
          ),
        ),
      ),
    );
  }
}

class _UnoCardPainter extends CustomPainter {
  _UnoCardPainter({
    required this.card,
    required this.faceUp,
    required this.glow,
    required this.dim,
    required this.wildColor,
  });

  final UnoCard? card;
  final bool faceUp;
  final bool glow;
  final bool dim;
  final UnoColor? wildColor;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    final double r = size.width * 0.12;
    final RRect rr = RRect.fromRectAndRadius(rect, Radius.circular(r));

    // Drop shadow.
    canvas.drawRRect(
      rr.shift(Offset(0, size.height * 0.025)),
      Paint()
        ..color = const Color(0x66000000)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.width * 0.05),
    );

    final UnoCard? maybe = faceUp ? card : null;
    final UnoColor? suit = maybe?.color;
    if (glow) {
      final Color gc = suit == null ? NxColors.iceWhite : unoColorValue(suit);
      canvas.drawRRect(
        rr.inflate(size.width * 0.03),
        Paint()
          ..color = gc.withValues(alpha: 0.75)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.width * 0.09),
      );
    }
    if (maybe == null) {
      _paintBack(canvas, size, rr);
      return;
    }
    final UnoCard c = maybe;
    final Color base = suit == null ? const Color(0xFF151B3E) : unoColorValue(suit);

    // White frame.
    canvas.drawRRect(rr, Paint()..color = const Color(0xFFF4F8FF));
    final RRect inner = rr.deflate(size.width * 0.055);
    final Color light = Color.lerp(base, Colors.white, 0.35)!;
    final Color dark = Color.lerp(base, const Color(0xFF050818), 0.45)!;
    canvas.drawRRect(
      inner,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: c.color == null
              ? const <Color>[Color(0xFF1B2250), Color(0xFF070A20)]
              : <Color>[light, base, dark],
        ).createShader(inner.outerRect),
    );

    // Orbit ring (NEXORA motif) behind the central symbol.
    final Offset center = rect.center;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-math.pi / 7);
    final Rect oval = Rect.fromCenter(center: Offset.zero, width: size.width * 0.78, height: size.height * 0.52);
    if (c.isWild) {
      canvas.drawOval(
        oval,
        Paint()
          ..shader = const SweepGradient(
            colors: <Color>[
              NxColors.turquoise,
              NxColors.violet,
              NxColors.pink,
              NxColors.gold,
              NxColors.turquoise,
            ],
          ).createShader(oval),
      );
      canvas.drawOval(
        oval.deflate(size.width * 0.06),
        Paint()..color = const Color(0xE6070A20),
      );
    } else {
      canvas.drawOval(oval, Paint()..color = const Color(0xF2FFFFFF));
      canvas.drawOval(
        oval.deflate(size.width * 0.035),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * 0.012
          ..color = base.withValues(alpha: 0.55),
      );
    }
    canvas.restore();

    // Gloss highlight.
    final Path gloss = Path()
      ..moveTo(inner.left, inner.top + inner.height * 0.30)
      ..quadraticBezierTo(inner.center.dx, inner.top + inner.height * 0.18, inner.right, inner.top)
      ..lineTo(inner.left + inner.tlRadiusX, inner.top)
      ..close();
    canvas.save();
    canvas.clipRRect(inner);
    canvas.drawPath(gloss, Paint()..color = const Color(0x22FFFFFF));
    canvas.restore();

    // Central symbol.
    final Color symColor = c.isWild ? NxColors.iceWhite : dark;
    _paintSymbol(canvas, c, center, size.width * 0.40, symColor, true);

    // Corner indices.
    final double cs = size.width * 0.17;
    _paintSymbol(canvas, c, Offset(size.width * 0.2, size.height * 0.15), cs, Colors.white, false);
    canvas.save();
    canvas.translate(size.width * 0.8, size.height * 0.85);
    canvas.rotate(math.pi);
    _paintSymbol(canvas, c, Offset.zero, cs, Colors.white, false);
    canvas.restore();

    if (wildColor != null && c.isWild) {
      canvas.drawRRect(
        inner.deflate(size.width * 0.01),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * 0.045
          ..color = unoColorValue(wildColor!),
      );
    }

    if (dim) {
      canvas.drawRRect(rr, Paint()..color = const Color(0x8C050818));
    }
  }

  void _paintBack(Canvas canvas, Size size, RRect rr) {
    canvas.drawRRect(rr, Paint()..color = const Color(0xFFF4F8FF));
    final RRect inner = rr.deflate(size.width * 0.05);
    canvas.drawRRect(
      inner,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0xFF1B1060), Color(0xFF0A0F2C), Color(0xFF041A33)],
        ).createShader(inner.outerRect),
    );
    final Offset c = rr.center;
    canvas.save();
    canvas.clipRRect(inner);
    // Starry dots (deterministic).
    final Paint dot = Paint()..color = const Color(0x88EAF6FF);
    for (int i = 0; i < 14; i++) {
      final double x = inner.left + ((i * 37) % 100) / 100.0 * inner.width;
      final double y = inner.top + ((i * 61 + 13) % 100) / 100.0 * inner.height;
      canvas.drawCircle(Offset(x, y), size.width * (0.008 + (i % 3) * 0.004), dot);
    }
    canvas.translate(c.dx, c.dy);
    canvas.rotate(-math.pi / 7);
    final Rect oval = Rect.fromCenter(center: Offset.zero, width: size.width * 0.82, height: size.height * 0.44);
    canvas.drawOval(
      oval,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.03
        ..shader = const SweepGradient(
          colors: <Color>[NxColors.turquoise, NxColors.violet, NxColors.pink, NxColors.gold, NxColors.turquoise],
        ).createShader(oval),
    );
    canvas.drawOval(
      oval.deflate(size.width * 0.06),
      Paint()
        ..color = const Color(0x557B3FF2)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.width * 0.05),
    );
    canvas.restore();
    _text(canvas, 'NX', c, size.width * 0.30, NxColors.iceWhite, FontWeight.w900, shadow: NxColors.electricBlue);
  }

  void _paintSymbol(Canvas canvas, UnoCard c, Offset at, double s, Color color, bool big) {
    switch (c.kind) {
      case UnoKind.number:
        _text(canvas, '${c.number}', at, s * (big ? 1.25 : 1.0), color, FontWeight.w900,
            shadow: big ? const Color(0x33000000) : const Color(0x66000000));
        if (c.number == 6 || c.number == 9) {
          final double w = s * 0.42;
          final Offset u = at + Offset(0, s * (big ? 0.78 : 0.62));
          canvas.drawLine(
            u - Offset(w / 2, 0),
            u + Offset(w / 2, 0),
            Paint()
              ..color = color
              ..strokeWidth = s * 0.08
              ..strokeCap = StrokeCap.round,
          );
        }
        break;
      case UnoKind.skip:
        final double rad = s * 0.42;
        final Paint p = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.13
          ..strokeCap = StrokeCap.round
          ..color = color;
        canvas.drawCircle(at, rad, p);
        final Offset d = Offset(math.cos(math.pi / 4), math.sin(math.pi / 4)) * rad;
        canvas.drawLine(at - Offset(d.dx, -d.dy), at + Offset(d.dx, -d.dy), p);
        break;
      case UnoKind.reverse:
        _paintReverse(canvas, at, s, color);
        break;
      case UnoKind.drawTwo:
        _text(canvas, '+2', at, s * (big ? 0.95 : 0.8), color, FontWeight.w900);
        break;
      case UnoKind.wild:
        _paintWildDiamond(canvas, at, s * (big ? 0.9 : 0.75));
        break;
      case UnoKind.wildDrawFour:
        if (big) {
          _paintWildDiamond(canvas, at - Offset(0, s * 0.18), s * 0.6);
          _text(canvas, '+4', at + Offset(0, s * 0.42), s * 0.6, NxColors.iceWhite, FontWeight.w900,
              shadow: const Color(0xAA000000));
        } else {
          _text(canvas, '+4', at, s * 0.8, color, FontWeight.w900);
        }
        break;
    }
  }

  void _paintReverse(Canvas canvas, Offset at, double s, Color color) {
    final Paint p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.12
      ..strokeCap = StrokeCap.round
      ..color = color;
    final double rad = s * 0.36;
    final Rect arc = Rect.fromCircle(center: at, radius: rad);
    canvas.drawArc(arc, -math.pi * 0.95, math.pi * 0.75, false, p);
    canvas.drawArc(arc, math.pi * 0.05, math.pi * 0.75, false, p);
    final Paint fill = Paint()..color = color;
    void head(double ang, double dir) {
      final Offset tip = at + Offset(math.cos(ang), math.sin(ang)) * rad;
      final Offset tangent = Offset(-math.sin(ang), math.cos(ang)) * dir;
      final Offset normal = Offset(math.cos(ang), math.sin(ang));
      final double hs = s * 0.2;
      final Path path = Path()
        ..moveTo(tip.dx + tangent.dx * hs, tip.dy + tangent.dy * hs)
        ..lineTo(tip.dx + normal.dx * hs * 0.7, tip.dy + normal.dy * hs * 0.7)
        ..lineTo(tip.dx - normal.dx * hs * 0.7, tip.dy - normal.dy * hs * 0.7)
        ..close();
      canvas.drawPath(path, fill);
    }

    head(-math.pi * 0.2, 1);
    head(math.pi * 0.8, 1);
  }

  void _paintWildDiamond(Canvas canvas, Offset at, double s) {
    const List<Color> cols = <Color>[NxColors.turquoise, NxColors.violet, NxColors.gold, NxColors.pink];
    final double h = s * 0.55;
    final List<Offset> pts = <Offset>[
      at + Offset(0, -h),
      at + Offset(h * 0.8, 0),
      at + Offset(0, h),
      at + Offset(-h * 0.8, 0),
    ];
    for (int i = 0; i < 4; i++) {
      final Path tri = Path()
        ..moveTo(at.dx, at.dy)
        ..lineTo(pts[i].dx, pts[i].dy)
        ..lineTo(pts[(i + 1) % 4].dx, pts[(i + 1) % 4].dy)
        ..close();
      canvas.drawPath(tri, Paint()..color = cols[i]);
    }
    final Path outline = Path()..addPolygon(pts, true);
    canvas.drawPath(
      outline,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.05
        ..color = Colors.white,
    );
  }

  void _text(Canvas canvas, String t, Offset center, double fontSize, Color color, FontWeight w,
      {Color? shadow}) {
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: t,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: w,
          color: color,
          height: 1.0,
          shadows: shadow == null
              ? null
              : <Shadow>[Shadow(color: shadow, blurRadius: fontSize * 0.12, offset: Offset(0, fontSize * 0.04))],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _UnoCardPainter old) =>
      old.card != card || old.faceUp != faceUp || old.glow != glow || old.dim != dim || old.wildColor != wildColor;
}
