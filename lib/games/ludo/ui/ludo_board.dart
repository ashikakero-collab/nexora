import 'dart:math';

import 'package:flutter/material.dart';

import '../core/ludo_rules.dart';

/// Seat colours: turquoise, violet, gold, pink.
const List<Color> kLudoSeatColors = <Color>[
  Color(0xFF2EE6D6),
  Color(0xFF9D6BFF),
  Color(0xFFFFC857),
  Color(0xFFFF4FA3),
];

/// Board geometry in cell units (the board is 15 x 15 cells).
class LudoGeom {
  LudoGeom._();

  static final List<Offset> track = _buildTrack();

  static List<Offset> _buildTrack() {
    final List<Offset> cells = <Offset>[];
    void add(int c, int r) => cells.add(Offset(c + 0.5, r + 0.5));
    for (int x = 1; x <= 5; x++) {
      add(x, 6);
    }
    for (int y = 5; y >= 0; y--) {
      add(6, y);
    }
    add(7, 0);
    for (int y = 0; y <= 5; y++) {
      add(8, y);
    }
    for (int x = 9; x <= 14; x++) {
      add(x, 6);
    }
    add(14, 7);
    for (int x = 14; x >= 9; x--) {
      add(x, 8);
    }
    for (int y = 9; y <= 14; y++) {
      add(8, y);
    }
    add(7, 14);
    for (int y = 14; y >= 9; y--) {
      add(6, y);
    }
    for (int x = 5; x >= 0; x--) {
      add(x, 8);
    }
    add(0, 7);
    add(0, 6);
    return cells;
  }

  /// Rotates a point of the 15x15 board clockwise [k] quarter turns.
  static Offset rot(Offset p, int k) {
    Offset q = p;
    for (int i = 0; i < k % 4; i++) {
      q = Offset(15 - q.dy, q.dx);
    }
    return q;
  }

  static Offset homeCell(int corner, int i) =>
      rot(Offset(i + 0.5, 7.5), corner);

  static const List<Offset> _baseSpots = <Offset>[
    Offset(2.1, 2.1),
    Offset(3.9, 2.1),
    Offset(2.1, 3.9),
    Offset(3.9, 3.9),
  ];

  static const List<Offset> _finishSpots = <Offset>[
    Offset(6.32, 6.95),
    Offset(6.32, 8.05),
    Offset(6.85, 7.5),
    Offset(6.32, 7.5),
  ];

  static Offset baseSpot(int corner, int token) =>
      rot(_baseSpots[token], corner);

  static Offset finishSpot(int corner, int token) =>
      rot(_finishSpots[token], corner);

  static Offset cellFor(LudoState s, int seat, int token, int progress) {
    final int corner = s.corners[seat];
    if (progress == kLudoBase) return baseSpot(corner, token);
    if (progress <= kLudoLastTrack) return track[s.globalOf(seat, progress)];
    if (progress < kLudoHome) {
      return homeCell(corner, progress - kLudoLastTrack);
    }
    return finishSpot(corner, token);
  }

  static Rect rotRect(Rect r, int k) {
    final Offset a = rot(r.topLeft, k);
    final Offset b = rot(r.bottomRight, k);
    return Rect.fromPoints(a, b);
  }
}

Path ludoStarPath(Offset c, double outer, double inner) {
  final Path p = Path();
  for (int i = 0; i < 10; i++) {
    final double r = i.isEven ? outer : inner;
    final double a = -pi / 2 + i * pi / 5;
    final Offset o = c + Offset(cos(a) * r, sin(a) * r);
    if (i == 0) {
      p.moveTo(o.dx, o.dy);
    } else {
      p.lineTo(o.dx, o.dy);
    }
  }
  p.close();
  return p;
}

/// Static cosmic board. [cornerColors] holds a colour for each occupied corner.
class LudoBoardPainter extends CustomPainter {
  LudoBoardPainter({
    required this.cornerColors,
    required this.fancy,
    this.accent = const Color(0xFF2EE6D6),
    this.accentSecondary = const Color(0xFF9D6BFF),
    this.surface = const Color(0xFF0A0F2C),
  });

  final List<Color?> cornerColors;
  final bool fancy;
  final Color accent;
  final Color accentSecondary;
  final Color surface;

  static const Color _idle = Color(0xFF3A4570);

  Color _c(int corner) => cornerColors[corner] ?? _idle;

  @override
  void paint(Canvas canvas, Size size) {
    final double u = size.width / 15;
    final Rect all = Offset.zero & size;
    final RRect outer = RRect.fromRectAndRadius(all, Radius.circular(u * 0.8));

    // Board slab.
    if (fancy) {
      canvas.drawRRect(
          outer.inflate(u * 0.15),
          Paint()
            ..color = accentSecondary.withValues(alpha: 0.42)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, u * 0.6));
    }
    canvas.drawRRect(
        outer,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              Color.lerp(surface, accentSecondary, 0.18)!,
              surface,
              Color.lerp(surface, accent, 0.1)!
            ],
          ).createShader(all));
    canvas.drawRRect(
        outer.deflate(2),
        Paint()
          ..color = accent.withValues(alpha: 0.42)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);

    // Bases.
    for (int k = 0; k < 4; k++) {
      final Color col = _c(k);
      final Rect base = LudoGeom.rotRect(const Rect.fromLTRB(0, 0, 6, 6), k);
      final Rect r = Rect.fromLTRB(
              base.left * u, base.top * u, base.right * u, base.bottom * u)
          .deflate(u * 0.25);
      final RRect rr = RRect.fromRectAndRadius(r, Radius.circular(u * 0.7));
      canvas.drawRRect(
          rr,
          Paint()
            ..shader = RadialGradient(
              colors: <Color>[
                col.withValues(alpha: 0.55),
                col.withValues(alpha: 0.12)
              ],
            ).createShader(r));
      canvas.drawRRect(
          rr,
          Paint()
            ..color = col.withValues(alpha: 0.9)
            ..style = PaintingStyle.stroke
            ..strokeWidth = u * 0.08);
      final RRect inner = RRect.fromRectAndRadius(
          r.deflate(u * 0.75), Radius.circular(u * 0.5));
      canvas.drawRRect(inner, Paint()..color = const Color(0xCC070B22));
      for (int t = 0; t < 4; t++) {
        final Offset c = LudoGeom.baseSpot(k, t) * u;
        canvas.drawCircle(
            c, u * 0.48, Paint()..color = col.withValues(alpha: 0.18));
        canvas.drawCircle(
            c,
            u * 0.48,
            Paint()
              ..color = col.withValues(alpha: 0.7)
              ..style = PaintingStyle.stroke
              ..strokeWidth = u * 0.05);
      }
    }

    // Main track.
    final Paint cellFill = Paint()..color = const Color(0x1AEAF6FF);
    final Paint cellLine = Paint()
      ..color = accent.withValues(alpha: 0.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (int g = 0; g < kLudoTrackLen; g++) {
      final Offset c = LudoGeom.track[g] * u;
      final RRect cell = RRect.fromRectAndRadius(
          Rect.fromCenter(center: c, width: u, height: u).deflate(u * 0.06),
          Radius.circular(u * 0.18));
      final int corner = g ~/ 13;
      if (g % 13 == 0) {
        final Color col = _c(corner);
        canvas.drawRRect(cell, Paint()..color = col.withValues(alpha: 0.75));
        _arrow(canvas, c, u, corner, col);
      } else {
        canvas.drawRRect(cell, cellFill);
      }
      canvas.drawRRect(cell, cellLine);
      if (g % 13 == 8) {
        final Path star = ludoStarPath(c, u * 0.34, u * 0.15);
        if (fancy) {
          canvas.drawPath(
              star,
              Paint()
                ..color = const Color(0xFFFFC857).withValues(alpha: 0.6)
                ..maskFilter = MaskFilter.blur(BlurStyle.normal, u * 0.15));
        }
        canvas.drawPath(
            star, Paint()..color = Color.lerp(accent, Colors.white, 0.58)!);
      }
    }

    // Home columns.
    for (int k = 0; k < 4; k++) {
      final Color col = _c(k);
      for (int i = 1; i <= 5; i++) {
        final Offset c = LudoGeom.homeCell(k, i) * u;
        final RRect cell = RRect.fromRectAndRadius(
            Rect.fromCenter(center: c, width: u, height: u).deflate(u * 0.06),
            Radius.circular(u * 0.18));
        canvas.drawRRect(
            cell, Paint()..color = col.withValues(alpha: 0.25 + i * 0.1));
        canvas.drawRRect(cell, cellLine);
      }
    }

    // Centre home: four triangles + glowing core.
    final Offset centre = const Offset(7.5, 7.5) * u;
    for (int k = 0; k < 4; k++) {
      final Offset a = LudoGeom.rot(const Offset(6, 6), k) * u;
      final Offset b = LudoGeom.rot(const Offset(6, 9), k) * u;
      final Path tri = Path()
        ..moveTo(a.dx, a.dy)
        ..lineTo(b.dx, b.dy)
        ..lineTo(centre.dx, centre.dy)
        ..close();
      final Color col = _c(k);
      canvas.drawPath(
          tri,
          Paint()
            ..shader = LinearGradient(
              colors: <Color>[
                col.withValues(alpha: 0.95),
                col.withValues(alpha: 0.35)
              ],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ).createShader(Rect.fromPoints(a, b).inflate(u)));
      canvas.drawPath(
          tri,
          Paint()
            ..color = const Color(0x66FFFFFF)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2);
    }
    if (fancy) {
      canvas.drawCircle(
          centre,
          u * 0.9,
          Paint()
            ..color = const Color(0xFFEAF6FF).withValues(alpha: 0.35)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, u * 0.5));
    }
    canvas.drawCircle(
        centre, u * 0.32, Paint()..color = const Color(0xFFEAF6FF));
  }

  void _arrow(Canvas canvas, Offset c, double u, int corner, Color col) {
    // Small chevron pointing along the direction of travel.
    final Offset next = LudoGeom.track[(corner * 13 + 1) % kLudoTrackLen] * u;
    final Offset dir = next - c;
    final double len = dir.distance == 0 ? 1 : dir.distance;
    final Offset d = dir / len;
    final Offset n = Offset(-d.dy, d.dx);
    final Offset tip = c + d * (u * 0.22);
    final Path p = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo((c - d * (u * 0.12) + n * (u * 0.18)).dx,
          (c - d * (u * 0.12) + n * (u * 0.18)).dy)
      ..lineTo((c - d * (u * 0.12) - n * (u * 0.18)).dx,
          (c - d * (u * 0.12) - n * (u * 0.18)).dy)
      ..close();
    canvas.drawPath(
        p, Paint()..color = const Color(0xFF0A0F2C).withValues(alpha: 0.75));
  }

  @override
  bool shouldRepaint(covariant LudoBoardPainter oldDelegate) =>
      oldDelegate.fancy != fancy ||
      oldDelegate.cornerColors != cornerColors ||
      oldDelegate.accent != accent ||
      oldDelegate.accentSecondary != accentSecondary ||
      oldDelegate.surface != surface;
}

/// One token to draw (cell units).
class LudoTokenDraw {
  const LudoTokenDraw({
    required this.pos,
    required this.color,
    this.scale = 1,
    this.lift = 0,
    this.movable = false,
  });
  final Offset pos;
  final Color color;
  final double scale;
  final double lift;
  final bool movable;
}

class LudoTokensPainter extends CustomPainter {
  LudoTokensPainter({
    required this.tokens,
    required this.pulse,
    required this.fancy,
    this.flashAt,
    this.flash = 0,
  });

  final List<LudoTokenDraw> tokens;
  final double pulse;
  final bool fancy;
  final Offset? flashAt;
  final double flash;

  @override
  void paint(Canvas canvas, Size size) {
    final double u = size.width / 15;
    final Offset? fa = flashAt;
    if (fa != null && flash > 0 && flash < 1) {
      final Offset c = fa * u;
      canvas.drawCircle(
          c,
          u * (0.5 + 2.2 * flash),
          Paint()
            ..color =
                const Color(0xFFFF4FA3).withValues(alpha: 0.6 * (1 - flash))
            ..style = PaintingStyle.stroke
            ..strokeWidth = u * 0.18 * (1 - flash));
    }
    // Draw lower tokens first so lifted ones sit on top.
    final List<LudoTokenDraw> sorted = List<LudoTokenDraw>.from(tokens)
      ..sort((LudoTokenDraw a, LudoTokenDraw b) {
        final int l = a.lift.compareTo(b.lift);
        if (l != 0) return l;
        return a.pos.dy.compareTo(b.pos.dy);
      });
    for (final LudoTokenDraw t in sorted) {
      final Offset c = t.pos * u;
      final double r = u * 0.37 * t.scale * (1 + t.lift * 0.35);
      final Offset body = c - Offset(0, t.lift * u);
      // Shadow.
      canvas.drawOval(
          Rect.fromCenter(
              center: c + Offset(0, r * 0.55),
              width: r * 1.9 * (1 - t.lift * 0.3),
              height: r * 0.8 * (1 - t.lift * 0.3)),
          Paint()
            ..color = Colors.black.withValues(alpha: 0.45)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.25));
      if (t.movable) {
        final double gr = r * (1.35 + 0.25 * pulse);
        if (fancy) {
          canvas.drawCircle(
              body,
              gr,
              Paint()
                ..color = t.color.withValues(alpha: 0.35 + 0.3 * pulse)
                ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.5));
        }
        canvas.drawCircle(
            body,
            gr,
            Paint()
              ..color = Colors.white.withValues(alpha: 0.5 + 0.5 * pulse)
              ..style = PaintingStyle.stroke
              ..strokeWidth = u * 0.06);
      }
      // Pedestal ring.
      canvas.drawCircle(body.translate(0, r * 0.18), r,
          Paint()..color = Color.lerp(t.color, Colors.black, 0.55) ?? t.color);
      // Body.
      canvas.drawCircle(
          body,
          r,
          Paint()
            ..shader = RadialGradient(
              center: const Alignment(-0.35, -0.45),
              colors: <Color>[
                Color.lerp(t.color, Colors.white, 0.65) ?? t.color,
                t.color,
                Color.lerp(t.color, Colors.black, 0.35) ?? t.color,
              ],
              stops: const <double>[0, 0.55, 1],
            ).createShader(Rect.fromCircle(center: body, radius: r)));
      canvas.drawCircle(
          body,
          r * 0.52,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.75)
            ..style = PaintingStyle.stroke
            ..strokeWidth = r * 0.12);
      canvas.drawCircle(
          body, r * 0.2, Paint()..color = Colors.white.withValues(alpha: 0.9));
    }
  }

  @override
  bool shouldRepaint(covariant LudoTokensPainter oldDelegate) => true;
}
