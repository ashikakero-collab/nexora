import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/snl_rules.dart';

/// Seat colours: turquoise, violet, gold, pink.
const List<Color> kSnlSeatColors = <Color>[
  Color(0xFF2EE6D6),
  Color(0xFF9D6BFF),
  Color(0xFFFFC857),
  Color(0xFFFF4FA3),
];

/// Board layout height in cell units: 10 rows of squares + a launch pad strip.
const double kSnlBoardRows = 10.9;

/// Geometry in cell units (board 10 cells wide, [kSnlBoardRows] tall).
class SnlGeom {
  SnlGeom._();

  /// Centre of square [n] (1..100), numbered boustrophedon from bottom-left.
  static Offset cell(int n) {
    final int idx = n.clamp(1, kSnlGoal) - 1;
    final int row = idx ~/ 10;
    final int inRow = idx % 10;
    final int col = row.isEven ? inRow : 9 - inRow;
    return Offset(col + 0.5, (9 - row) + 0.5);
  }

  /// Spot on the launch pad (square 0) for [seat].
  static Offset pad(int seat) => Offset(0.75 + seat * 0.95, 10.45);

  static Offset pos(int square, int seat) =>
      square <= 0 ? pad(seat) : cell(square);

  /// Wavy body points from snake head [a] to tail [b].
  static List<Offset> snakePath(Offset a, Offset b, double phase,
      {int samples = 36}) {
    final Offset d = b - a;
    final double len = d.distance;
    if (len < 0.001) return <Offset>[a, b];
    final Offset nrm = Offset(-d.dy / len, d.dx / len);
    final double waves = max(1.5, len / 2.0);
    final List<Offset> pts = <Offset>[];
    for (int i = 0; i <= samples; i++) {
      final double t = i / samples;
      final double env = pow(max(0.0, sin(pi * t)), 0.7).toDouble();
      final double amp = 0.32 * env * min(1.0, len / 3);
      final double w = sin(t * waves * 2 * pi + phase) * amp;
      pts.add(a + d * t + nrm * w);
    }
    return pts;
  }

  /// Position at fraction [f] (0..1) along polyline [pts] by arc length.
  static Offset along(List<Offset> pts, double f) {
    if (pts.length < 2) return pts.first;
    double total = 0;
    for (int i = 0; i < pts.length - 1; i++) {
      total += (pts[i + 1] - pts[i]).distance;
    }
    double target = f.clamp(0.0, 1.0) * total;
    for (int i = 0; i < pts.length - 1; i++) {
      final double seg = (pts[i + 1] - pts[i]).distance;
      if (target <= seg || i == pts.length - 2) {
        final double k = seg <= 0 ? 0 : (target / seg).clamp(0.0, 1.0);
        return Offset.lerp(pts[i], pts[i + 1], k)!;
      }
      target -= seg;
    }
    return pts.last;
  }
}

const String _faDigits = '۰۱۲۳۴۵۶۷۸۹';
String snlNum(int v, bool fa) {
  if (!fa) return '$v';
  return v
      .toString()
      .split('')
      .map((String c) => _faDigits[int.parse(c)])
      .join();
}

// ------------------------------------------------------------------ board
/// Static board (squares, numbers, launch pad). Painted once.
class SnlBoardPainter extends CustomPainter {
  SnlBoardPainter({
    required this.fancy,
    required this.isFa,
    this.accent = const Color(0xFF2EE6D6),
    this.accentSecondary = const Color(0xFF9D6BFF),
    this.surface = const Color(0xFF0A0F2C),
  });
  final bool fancy;
  final bool isFa;
  final Color accent;
  final Color accentSecondary;
  final Color surface;

  @override
  void paint(Canvas canvas, Size size) {
    final double u = size.width / 10;
    final Rect board = Rect.fromLTWH(0, 0, u * 10, u * 10);
    final RRect outer = RRect.fromRectAndRadius(
        board.inflate(u * 0.08), Radius.circular(u * 0.35));
    if (fancy) {
      canvas.drawRRect(
          outer,
          Paint()
            ..color = accent.withValues(alpha: 0.32)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, u * 0.4));
    }
    canvas.drawRRect(outer, Paint()..color = surface);
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(board, Radius.circular(u * 0.3)));

    final Paint cellPaint = Paint();
    for (int n = 1; n <= kSnlGoal; n++) {
      final Offset c = SnlGeom.cell(n);
      final Rect r = Rect.fromCenter(center: c * u, width: u, height: u);
      final int row = (n - 1) ~/ 10;
      final bool alt = ((n - 1) % 10 + row).isEven;
      final double tRow = row / 9;
      final Color base =
          Color.lerp(surface, accentSecondary, 0.12 + tRow * 0.08)!;
      cellPaint.shader = ui.Gradient.linear(
        r.topLeft,
        r.bottomRight,
        <Color>[
          Color.lerp(base, Colors.white, alt ? 0.08 : 0.02)!,
          Color.lerp(base, Colors.black, alt ? 0.1 : 0.3)!,
        ],
      );
      canvas.drawRect(r.deflate(u * 0.02), cellPaint);
      // Special-square tints.
      Color? tint;
      if (kSnlLadders.containsKey(n)) tint = accent;
      if (kSnlSnakes.containsKey(n)) tint = accentSecondary;
      if (n == kSnlGoal) tint = Color.lerp(accent, Colors.white, 0.35)!;
      if (tint != null) {
        canvas.drawRect(
            r.deflate(u * 0.06),
            Paint()
              ..shader = ui.Gradient.radial(r.center, u * 0.6, <Color>[
                tint.withValues(alpha: 0.35),
                tint.withValues(alpha: 0)
              ]));
      }
      canvas.drawRect(
          r.deflate(u * 0.02),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = u * 0.015
            ..color = const Color(0x2299C8FF));
      // Number.
      final bool goal = n == kSnlGoal;
      final TextPainter tp = TextPainter(
        text: TextSpan(
          text: snlNum(n, isFa),
          style: TextStyle(
            color: goal
                ? Color.lerp(accent, Colors.white, 0.35)!
                : const Color(0x99EAF6FF),
            fontSize: u * (goal ? 0.3 : 0.22),
            fontWeight: goal ? FontWeight.w900 : FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, r.topLeft + Offset(u * 0.08, u * 0.05));
    }
    // Goal star.
    _star(canvas, SnlGeom.cell(kSnlGoal) * u + Offset(0, u * 0.08), u * 0.26,
        Color.lerp(accent, Colors.white, 0.35)!);
    canvas.restore();

    // Launch pad.
    final Rect pad = Rect.fromLTWH(u * 0.1, u * 10.12, u * 4.0, u * 0.66);
    final RRect padR = RRect.fromRectAndRadius(pad, Radius.circular(u * 0.33));
    canvas.drawRRect(
        padR,
        Paint()
          ..shader = ui.Gradient.linear(pad.topLeft, pad.bottomRight, <Color>[
            accent.withValues(alpha: 0.32),
            accentSecondary.withValues(alpha: 0.2)
          ]));
    canvas.drawRRect(
        padR,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = u * 0.03
          ..color = accent.withValues(alpha: 0.6));
    final TextPainter lp = TextPainter(
      text: TextSpan(
        text: isFa ? 'سکوی پرتاب  ←  ۱' : 'LAUNCH PAD  →  1',
        style: TextStyle(
            color: const Color(0xAAEAF6FF),
            fontSize: u * 0.22,
            fontWeight: FontWeight.w700),
      ),
      textDirection: isFa ? TextDirection.rtl : TextDirection.ltr,
    )..layout();
    lp.paint(canvas, Offset(u * 4.4, u * 10.45 - lp.height / 2));
  }

  void _star(Canvas canvas, Offset c, double r, Color col) {
    final Path p = Path();
    for (int i = 0; i < 10; i++) {
      final double a = -pi / 2 + i * pi / 5;
      final double rr = i.isEven ? r : r * 0.45;
      final Offset q = c + Offset(cos(a), sin(a)) * rr;
      if (i == 0) {
        p.moveTo(q.dx, q.dy);
      } else {
        p.lineTo(q.dx, q.dy);
      }
    }
    p.close();
    if (fancy) {
      canvas.drawPath(
          p,
          Paint()
            ..color = col.withValues(alpha: 0.7)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.5));
    }
    canvas.drawPath(p, Paint()..color = col);
  }

  @override
  bool shouldRepaint(covariant SnlBoardPainter oldDelegate) =>
      oldDelegate.fancy != fancy ||
      oldDelegate.isFa != isFa ||
      oldDelegate.accent != accent ||
      oldDelegate.accentSecondary != accentSecondary ||
      oldDelegate.surface != surface;
}

// ---------------------------------------------------------- snakes/ladders
const List<List<Color>> _snakeColors = <List<Color>>[
  <Color>[Color(0xFFFF4FA3), Color(0xFF9D6BFF)],
  <Color>[Color(0xFF39FF9A), Color(0xFF1E7BFF)],
  <Color>[Color(0xFFFF6A3D), Color(0xFFFF4FA3)],
  <Color>[Color(0xFFB36BFF), Color(0xFF2EE6D6)],
];

/// Animated light-bridge ladders and glowing serpents. [t] is a 0..1 phase.
class SnlOverlayPainter extends CustomPainter {
  SnlOverlayPainter({
    required this.t,
    required this.fancy,
    this.accent = const Color(0xFF2EE6D6),
    this.accentSecondary = const Color(0xFF9D6BFF),
  });
  final double t;
  final bool fancy;
  final Color accent;
  final Color accentSecondary;

  static double snakePhase(double t) => t * 2 * pi;

  @override
  void paint(Canvas canvas, Size size) {
    final double u = size.width / 10;
    kSnlLadders.forEach((int a, int b) =>
        _ladder(canvas, u, SnlGeom.cell(a), SnlGeom.cell(b), a));
    int i = 0;
    kSnlSnakes.forEach((int h, int tl) {
      _snake(canvas, u, SnlGeom.cell(h), SnlGeom.cell(tl), i);
      i++;
    });
  }

  void _ladder(Canvas canvas, double u, Offset a0, Offset b0, int id) {
    final Offset a = a0 * u;
    final Offset b = b0 * u;
    final Offset d = b - a;
    final double len = d.distance;
    if (len <= 0) return;
    final Offset dir = d / len;
    final Offset nrm = Offset(-dir.dy, dir.dx) * (u * 0.17);
    final Offset a1 = a + nrm;
    final Offset a2 = a - nrm;
    final Offset b1 = b + nrm;
    final Offset b2 = b - nrm;
    final Color c1 = accent;
    final Color c2 = accentSecondary;
    if (fancy) {
      final Paint glow = Paint()
        ..color = c1.withValues(alpha: 0.45)
        ..strokeWidth = u * 0.16
        ..strokeCap = StrokeCap.round
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, u * 0.12);
      canvas.drawLine(a1, b1, glow);
      canvas.drawLine(a2, b2, glow);
    }
    final Paint rail = Paint()
      ..shader = ui.Gradient.linear(a, b, <Color>[c1, c2])
      ..strokeWidth = u * 0.065
      ..strokeCap = StrokeCap.round;
    final int rungs = max(2, (len / (u * 0.42)).floor());
    final Paint rung = Paint()
      ..strokeWidth = u * 0.045
      ..strokeCap = StrokeCap.round;
    for (int k = 1; k < rungs; k++) {
      final double f = k / rungs;
      final double shimmer =
          fancy ? 0.55 + 0.45 * sin((f * 6 - t * 2 * pi * 1.0) + id) : 0.85;
      rung.color = Color.lerp(c2, Colors.white, 0.3)!
          .withValues(alpha: shimmer.clamp(0.2, 1.0));
      canvas.drawLine(Offset.lerp(a1, b1, f)!, Offset.lerp(a2, b2, f)!, rung);
    }
    canvas.drawLine(a1, b1, rail);
    canvas.drawLine(a2, b2, rail);
    canvas.drawLine(
        a1,
        b1,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.55)
          ..strokeWidth = u * 0.02
          ..strokeCap = StrokeCap.round);
    canvas.drawLine(
        a2,
        b2,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.55)
          ..strokeWidth = u * 0.02
          ..strokeCap = StrokeCap.round);
    // Travelling light pulse.
    if (fancy) {
      final double f = (t + id * 0.13) % 1.0;
      final Offset p = Offset.lerp(a, b, f)!;
      canvas.drawCircle(
          p,
          u * 0.18,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.6)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, u * 0.12));
    }
    // Endpoint nodes.
    for (final Offset e in <Offset>[a1, a2, b1, b2]) {
      canvas.drawCircle(e, u * 0.055, Paint()..color = Colors.white);
    }
  }

  void _snake(Canvas canvas, double u, Offset h, Offset tl, int idx) {
    final List<Color> cols = _snakeColors[idx % _snakeColors.length];
    final double phase = fancy ? snakePhase(t) + idx : idx.toDouble();
    final List<Offset> pts =
        SnlGeom.snakePath(h, tl, phase).map((Offset p) => p * u).toList();
    final int n = pts.length;
    if (fancy) {
      final Path body = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (int i = 1; i < n; i++) {
        body.lineTo(pts[i].dx, pts[i].dy);
      }
      canvas.drawPath(
          body,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = u * 0.36
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..color = cols[0].withValues(alpha: 0.4)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, u * 0.16));
    }
    final Paint seg = Paint()
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (int i = n - 2; i >= 0; i--) {
      final double f = i / (n - 1);
      final double w = u * (0.07 + 0.25 * (1 - f));
      seg.strokeWidth = w;
      final Color base = Color.lerp(cols[0], cols[1], f)!;
      seg.color = i % 4 < 2 ? base : Color.lerp(base, Colors.black, 0.28)!;
      canvas.drawLine(pts[i], pts[i + 1], seg);
    }
    // Spine highlight.
    final Paint hi = Paint()
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.35);
    for (int i = 0; i < n - 1; i += 1) {
      final double f = i / (n - 1);
      hi.strokeWidth = u * (0.02 + 0.05 * (1 - f));
      canvas.drawLine(pts[i], pts[i + 1], hi);
    }
    // Head.
    final Offset hp = pts.first;
    final Offset back = pts.length > 2 ? pts[2] : pts.last;
    final double ang = atan2(hp.dy - back.dy, hp.dx - back.dx);
    canvas.save();
    canvas.translate(hp.dx, hp.dy);
    canvas.rotate(ang);
    // Tongue.
    final double flick =
        fancy ? (sin(t * 2 * pi * 3 + idx) > 0.2 ? 1.0 : 0.0) : 1.0;
    if (flick > 0) {
      final Paint tongue = Paint()
        ..color = const Color(0xFFFF2E4D)
        ..strokeWidth = u * 0.03
        ..strokeCap = StrokeCap.round;
      final Offset tip = Offset(u * 0.42, 0);
      canvas.drawLine(Offset(u * 0.2, 0), tip, tongue);
      canvas.drawLine(tip, tip + Offset(u * 0.07, -u * 0.05), tongue);
      canvas.drawLine(tip, tip + Offset(u * 0.07, u * 0.05), tongue);
    }
    final Rect headR =
        Rect.fromCenter(center: Offset.zero, width: u * 0.5, height: u * 0.38);
    canvas.drawOval(
        headR,
        Paint()
          ..shader = ui.Gradient.radial(Offset(u * 0.05, -u * 0.05), u * 0.3,
              <Color>[Color.lerp(cols[0], Colors.white, 0.35)!, cols[0]]));
    canvas.drawOval(
        headR,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = u * 0.02
          ..color = Colors.white.withValues(alpha: 0.5));
    for (final double s in <double>[-1, 1]) {
      final Offset eye = Offset(u * 0.08, s * u * 0.09);
      canvas.drawCircle(eye, u * 0.055, Paint()..color = Colors.white);
      canvas.drawCircle(eye + Offset(u * 0.015, 0), u * 0.028,
          Paint()..color = const Color(0xFF0A0F2C));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant SnlOverlayPainter oldDelegate) =>
      oldDelegate.t != t ||
      oldDelegate.fancy != fancy ||
      oldDelegate.accent != accent ||
      oldDelegate.accentSecondary != accentSecondary;
}

// ------------------------------------------------------------------ tokens
class SnlTokenDraw {
  const SnlTokenDraw({
    required this.pos,
    required this.color,
    this.lift = 0,
    this.scale = 1,
    this.active = false,
  });
  final Offset pos;
  final Color color;
  final double lift;
  final double scale;
  final bool active;
}

class SnlTokensPainter extends CustomPainter {
  SnlTokensPainter({
    required this.tokens,
    required this.pulse,
    required this.fancy,
    this.burstAt,
    this.burst = 0,
    this.burstColor = const Color(0xFFFFFFFF),
  });

  final List<SnlTokenDraw> tokens;
  final double pulse;
  final bool fancy;
  final Offset? burstAt;
  final double burst;
  final Color burstColor;

  @override
  void paint(Canvas canvas, Size size) {
    final double u = size.width / 10;
    final Offset? b = burstAt;
    if (b != null && burst > 0 && burst < 1) {
      final double r = u * (0.3 + burst * 1.2);
      canvas.drawCircle(
          b * u,
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = u * 0.12 * (1 - burst)
            ..color = burstColor.withValues(alpha: 1 - burst));
      final Random rnd = Random(7);
      for (int i = 0; i < 12; i++) {
        final double a = i * pi / 6 + rnd.nextDouble() * 0.3;
        canvas.drawCircle(
            b * u + Offset(cos(a), sin(a)) * r * 1.1,
            u * 0.05 * (1 - burst),
            Paint()..color = burstColor.withValues(alpha: 1 - burst));
      }
    }
    for (final SnlTokenDraw tk in tokens) {
      final double r = u * 0.31 * tk.scale;
      final Offset c = tk.pos * u - Offset(0, tk.lift * u);
      final Offset ground = tk.pos * u + Offset(0, r * 0.75);
      canvas.drawOval(
          Rect.fromCenter(
              center: ground,
              width: r * (1.6 - tk.lift * 0.5),
              height: r * (0.5 - tk.lift * 0.15)),
          Paint()..color = const Color(0x88000000));
      if (tk.active) {
        canvas.drawCircle(
            c,
            r * (1.35 + 0.2 * pulse),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = u * 0.04
              ..color = tk.color.withValues(alpha: 0.4 + 0.5 * pulse));
      }
      if (fancy) {
        canvas.drawCircle(
            c,
            r * 1.2,
            Paint()
              ..color = tk.color.withValues(alpha: 0.55)
              ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.6));
      }
      canvas.drawCircle(
          c,
          r,
          Paint()
            ..shader = ui.Gradient.radial(
                c - Offset(r * 0.35, r * 0.4), r * 1.3, <Color>[
              Colors.white,
              Color.lerp(tk.color, Colors.white, 0.25)!,
              Color.lerp(tk.color, Colors.black, 0.45)!,
            ], <double>[
              0,
              0.35,
              1
            ]));
      canvas.drawCircle(
          c,
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = u * 0.025
            ..color = Colors.white.withValues(alpha: 0.8));
      canvas.drawCircle(c, r * 0.32,
          Paint()..color = const Color(0xFF0A0F2C).withValues(alpha: 0.55));
      canvas.drawCircle(c, r * 0.18, Paint()..color = tk.color);
    }
  }

  @override
  bool shouldRepaint(covariant SnlTokensPainter oldDelegate) => true;
}

// --------------------------------------------------------------------- die
/// Glass die with coloured glow; tumbles while [rolling] (t = 0..1).
class SnlDie extends StatelessWidget {
  const SnlDie({
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
        rolling ? 1 + ((t * 23).floor() * 5 + 3) % 6 : (value ?? 6);
    final double angle =
        rolling ? sin(t * pi * 4) * 0.6 * (1 - t) + t * pi * 2 : 0;
    final double hop =
        rolling ? sin(t * pi * 3).abs() * size * 0.35 * (1 - t) : 0;
    return Transform.translate(
      offset: Offset(0, -hop),
      child: Transform.rotate(
        angle: angle,
        child: CustomPaint(
          size: Size(size, size),
          painter: _SnlDiePainter(
              face: face,
              color: color,
              blank: value == null && !rolling,
              glow: glow),
        ),
      ),
    );
  }
}

List<Offset> _pips(int v) {
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
        Offset(b, b)
      ];
  }
}

class _SnlDiePainter extends CustomPainter {
  _SnlDiePainter(
      {required this.face,
      required this.color,
      required this.blank,
      required this.glow});
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
    canvas.drawRRect(rr.shift(Offset(0, s * 0.07)),
        Paint()..color = Color.lerp(color, Colors.black, 0.6)!);
    canvas.drawRRect(
        rr,
        Paint()
          ..shader = ui.Gradient.linear(body.topLeft, body.bottomRight, <Color>[
            Colors.white,
            Color.lerp(color, Colors.white, 0.75)!,
            Color.lerp(color, Colors.white, 0.35)!,
          ], <double>[
            0,
            0.5,
            1
          ]));
    canvas.drawRRect(
        rr.deflate(s * 0.03),
        Paint()
          ..color = color.withValues(alpha: 0.9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.04);
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
    for (final Offset o in _pips(face)) {
      final Offset c = Offset(o.dx * s, o.dy * s);
      canvas.drawCircle(c, pr, Paint()..color = const Color(0xFF0A0F2C));
      canvas.drawCircle(c.translate(-pr * 0.3, -pr * 0.3), pr * 0.35,
          Paint()..color = color.withValues(alpha: 0.8));
    }
  }

  @override
  bool shouldRepaint(covariant _SnlDiePainter oldDelegate) =>
      oldDelegate.face != face ||
      oldDelegate.color != color ||
      oldDelegate.blank != blank ||
      oldDelegate.glow != glow;
}

// ------------------------------------------------------------ NX2 dragon skin
/// The owner's dragon board (assets/ui/nx2/boards/snakes_dragon.webp) used as the ornate frame. The art's own
/// grid is drawn with 11 rows and repeated numbers, so the 10x10 squares are redrawn in code in the art's
/// style (marble cells, gold rims, gold numerals) at exactly [SnlGeom.cell] positions.
const String kSnlDragonAsset = 'assets/ui/nx2/boards/snakes_dragon.webp';

/// Frame margins around the 10x10 grid, in cell units.
const double kSnlFrameL = 0.55, kSnlFrameR = 0.55, kSnlFrameT = 1.35, kSnlFrameB = 1.75;

class SnlDragonFramePainter extends CustomPainter {
  SnlDragonFramePainter(this.img);
  final ui.Image img;

  @override
  void paint(Canvas canvas, Size size) {
    // size covers the frame: grid origin at (kSnlFrameL, kSnlFrameT) cells.
    final double u = size.width / (10 + kSnlFrameL + kSnlFrameR);
    final double sx = img.width / 1020, sy = img.height / 1532; // art measured on the 1020x1532 original
    final List<double> ax = <double>[0, 60 * sx, 960 * sx, img.width.toDouble()];
    final List<double> dx = <double>[0, kSnlFrameL * u, (kSnlFrameL + 10) * u, size.width];
    final List<double> ay = <double>[0, 248 * sy, 1328 * sy, img.height.toDouble()];
    final List<double> dy = <double>[0, kSnlFrameT * u, (kSnlFrameT + 10) * u, size.height];
    final Paint p = Paint()..filterQuality = FilterQuality.medium;
    for (int i = 0; i < 3; i++) {
      for (int j = 0; j < 3; j++) {
        if (i == 1 && j == 1) continue; // grid area is redrawn below
        canvas.drawImageRect(img, Rect.fromLTRB(ax[i], ay[j], ax[i + 1], ay[j + 1]),
            Rect.fromLTRB(dx[i], dy[j], dx[i + 1] + 0.5, dy[j + 1] + 0.5), p);
      }
    }
    // the art's grid texture, softly, under the new cells
    canvas.drawImageRect(img, Rect.fromLTRB(ax[1], ay[1], ax[2], ay[2]),
        Rect.fromLTRB(dx[1], dy[1], dx[2], dy[2]), p..color = const Color(0x55FFFFFF));
  }

  @override
  bool shouldRepaint(covariant SnlDragonFramePainter old) => old.img != img;
}

/// Squares + numbers in the dragon-board style (grid space: 10 x [kSnlBoardRows] cells).
class SnlDragonCellsPainter extends CustomPainter {
  SnlDragonCellsPainter({required this.isFa});
  final bool isFa;

  @override
  void paint(Canvas canvas, Size size) {
    final double u = size.width / 10;
    const Color gold = Color(0xFFF2B640);
    for (int n = 1; n <= kSnlGoal; n++) {
      final Rect r = Rect.fromCenter(center: SnlGeom.cell(n) * u, width: u, height: u).deflate(u * 0.045);
      final RRect rr = RRect.fromRectAndRadius(r, Radius.circular(u * 0.16));
      Color tint = const Color(0xFF3A1C66);
      if (kSnlLadders.containsKey(n)) tint = const Color(0xFF1F4E7A);
      if (kSnlSnakes.containsKey(n)) tint = const Color(0xFF6A1A4C);
      if (n == kSnlGoal) tint = const Color(0xFF7A5512);
      canvas.drawRRect(
          rr,
          Paint()
            ..shader = ui.Gradient.radial(r.center, u * 0.7, <Color>[
              Color.lerp(tint, Colors.white, 0.08)!.withValues(alpha: 0.92),
              const Color(0xF0120A22),
            ]));
      canvas.drawRRect(
          rr,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = u * 0.045
            ..shader = ui.Gradient.linear(r.topLeft, r.bottomRight,
                const <Color>[Color(0xFFFFE08A), Color(0xFFB0741C), Color(0xFFFFD36B)], const <double>[0, 0.5, 1]));
      final TextPainter tp = TextPainter(
        text: TextSpan(
          text: snlNum(n, isFa),
          style: TextStyle(
            fontFamily: 'ChakraPetch',
            fontFamilyFallback: const <String>['Estedad'],
            color: gold,
            fontSize: u * (n == kSnlGoal ? 0.3 : 0.27),
            fontWeight: FontWeight.w900,
            shadows: const <Shadow>[Shadow(color: Color(0xFF000000), blurRadius: 3, offset: Offset(0, 1))],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, r.center - Offset(tp.width / 2, tp.height / 2 + u * 0.06));
      // little diamond under the number, as on the art
      final Offset d = r.center + Offset(0, u * 0.24);
      final Path dp = Path()
        ..moveTo(d.dx, d.dy - u * 0.05)
        ..lineTo(d.dx + u * 0.035, d.dy)
        ..lineTo(d.dx, d.dy + u * 0.05)
        ..lineTo(d.dx - u * 0.035, d.dy)
        ..close();
      canvas.drawPath(dp, Paint()..color = gold.withValues(alpha: 0.8));
    }
  }

  @override
  bool shouldRepaint(covariant SnlDragonCellsPainter old) => old.isFa != isFa;
}
