import 'dart:math';

import 'package:flutter/material.dart';

import '../core/backgammon_rules.dart';

/// Geometry of board_nx_gold.webp measured with PIL (1536x1024 source px).
/// The whole board is laid out in this pixel space and scaled with FittedBox.
class BgGeom {
  BgGeom._();

  static const double w = 1536;
  static const double h = 1024;

  /// Point centres of the left half (outer edge -> bar).
  static const List<double> left = <double>[
    182,
    280.8,
    379.6,
    478.4,
    577.2,
    676
  ];

  /// Point centres of the right half (bar -> outer edge).
  static const List<double> right = <double>[
    861,
    959.2,
    1057.4,
    1155.6,
    1253.8,
    1352
  ];

  static const double pointW = 98;
  static const double top = 48;
  static const double bottom = 952;
  static const double mid = 500;
  static const double topTip = 342;
  static const double bottomTip = 608;
  static const double d = 86;
  static const double barX = 769;
  static const double barLeft = 728;
  static const double barRight = 810;
  static const double trayX = 1478;
  static const double trayLeft = 1424;
  static const double trayRight = 1532;
  static const double slabW = 76;
  static const double slabH = 13;
  static const double slabStep = 15;

  /// Dice area: the left half centre (over the NX emblem).
  static const Offset diceCenter = Offset(429, 500);

  static double pointX(int idx) {
    if (idx < 6) return right[5 - idx];
    if (idx < 12) return left[11 - idx];
    if (idx < 18) return left[idx - 12];
    return right[idx - 18];
  }

  static bool isTop(int idx) => idx >= 12;

  static Offset checkerCenter(int idx, int k, int count) {
    final double step = count <= 5 ? d : (4 * d) / (count - 1);
    final double x = pointX(idx);
    if (isTop(idx)) return Offset(x, top + d / 2 + 2 + k * step);
    return Offset(x, bottom - d / 2 - 2 - k * step);
  }

  static Offset barCenter(int p, int k, int count) {
    final double base = d * 0.92;
    final double step = count <= 4 ? base : (3 * base) / (count - 1);
    if (p == 0) return Offset(barX, mid + 70 + k * step);
    return Offset(barX, mid - 70 - k * step);
  }

  static Offset slabCenter(int p, int k) {
    if (p == 0) return Offset(trayX, bottom - 4 - k * slabStep);
    return Offset(trayX, top + 4 + k * slabStep);
  }

  static Rect pointRect(int idx) {
    final double x = pointX(idx);
    if (isTop(idx)) {
      return Rect.fromLTRB(x - pointW / 2, top - 10, x + pointW / 2, mid);
    }
    return Rect.fromLTRB(x - pointW / 2, mid, x + pointW / 2, bottom + 10);
  }

  static const Rect barRect = Rect.fromLTRB(barLeft, top, barRight, bottom);

  static Rect trayRect(int p) {
    if (p == 0) return const Rect.fromLTRB(trayLeft, mid + 40, trayRight, h);
    return const Rect.fromLTRB(trayLeft, 0, trayRight, mid - 40);
  }

  /// Returns a point index, [kBgBar], [kBgOff] (tray of [player]) or null.
  static int? hitTest(Offset p, int player) {
    if (trayRect(player).contains(p)) return kBgOff;
    if (barRect.contains(p)) return kBgBar;
    for (int i = 0; i < 24; i++) {
      if (pointRect(i).contains(p)) return i;
    }
    return null;
  }

  static Path trianglePath(int idx, {double inset = 0}) {
    final double x = pointX(idx);
    final double half = pointW / 2 - 3 - inset;
    final Path path = Path();
    if (isTop(idx)) {
      path.moveTo(x - half, top);
      path.lineTo(x + half, top);
      path.lineTo(x, topTip);
    } else {
      path.moveTo(x - half, bottom);
      path.lineTo(x + half, bottom);
      path.lineTo(x, bottomTip);
    }
    path.close();
    return path;
  }
}

/// Procedural board used only if the board image fails to load.
class BgFallbackBoardPainter extends CustomPainter {
  const BgFallbackBoardPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final Rect all = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(all, const Radius.circular(40)),
      Paint()
        ..shader = const LinearGradient(
          colors: <Color>[Color(0xFF2A2210), Color(0xFF0D0B05)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(all),
    );
    final Paint felt = Paint()..color = const Color(0xFF0E0E14);
    canvas.drawRect(const Rect.fromLTRB(128, 44, 730, 956), felt);
    canvas.drawRect(const Rect.fromLTRB(806, 44, 1408, 956), felt);
    final Paint gold = Paint()..color = const Color(0xFFE2B33C);
    final Paint ink = Paint()..color = const Color(0xFF26262E);
    for (int i = 0; i < 24; i++) {
      canvas.drawPath(BgGeom.trianglePath(i), i.isEven ? gold : ink);
    }
    canvas.drawRect(BgGeom.barRect, Paint()..color = const Color(0xFF15120A));
    final Paint frame = Paint()
      ..color = const Color(0xFFFFC857)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8;
    canvas.drawRRect(
        RRect.fromRectAndRadius(all.deflate(10), const Radius.circular(36)),
        frame);
  }

  @override
  bool shouldRepaint(covariant BgFallbackBoardPainter oldDelegate) => false;
}

/// Glow overlay: legal destinations, movable sources, selection, tray.
class BgHighlightPainter extends CustomPainter {
  BgHighlightPainter({
    required this.state,
    required this.accent,
    required this.accentSecondary,
    required this.player,
    required this.destinations,
    required this.destOff,
    required this.sources,
    required this.selected,
    required this.pulse,
    required this.fancy,
  }) : super(repaint: pulse);

  final BgState state;
  final Color accent;
  final Color accentSecondary;
  final int player;
  final Set<int> destinations;
  final bool destOff;
  final Set<int> sources;
  final int? selected;
  final Animation<double> pulse;
  final bool fancy;

  Offset _top(int place) {
    if (place == kBgBar) {
      final int c = state.bar[player];
      return BgGeom.barCenter(player, max(0, c - 1), max(1, c));
    }
    final int c = state.own(player, place);
    return BgGeom.checkerCenter(place, max(0, c - 1), max(1, c));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final double t = pulse.value;
    final Color glow = accent;
    for (final int idx in destinations) {
      final Path tri = BgGeom.trianglePath(idx, inset: 2);
      canvas.drawPath(
          tri, Paint()..color = glow.withValues(alpha: 0.18 + 0.22 * t));
      final Paint stroke = Paint()
        ..color = accentSecondary.withValues(alpha: 0.65 + 0.35 * t)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5;
      if (fancy) {
        canvas.drawPath(
            tri,
            Paint()
              ..color = glow.withValues(alpha: 0.5 * t)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 16
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
      }
      canvas.drawPath(tri, stroke);
      // Landing marker where the checker would arrive.
      final int c = state.own(player, idx);
      final Offset at = BgGeom.checkerCenter(idx, c, c + 1);
      canvas.drawCircle(
          at,
          BgGeom.d / 2 - 6,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.25 + 0.2 * t)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4);
    }
    if (destOff) {
      final Rect r = BgGeom.trayRect(player).deflate(6);
      final RRect rr = RRect.fromRectAndRadius(r, const Radius.circular(22));
      canvas.drawRRect(
          rr, Paint()..color = glow.withValues(alpha: 0.16 + 0.2 * t));
      canvas.drawRRect(
          rr,
          Paint()
            ..color = accentSecondary.withValues(alpha: 0.7 + 0.3 * t)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5);
    }
    for (final int s in sources) {
      if (s == selected) continue;
      canvas.drawCircle(
          _top(s),
          BgGeom.d / 2 + 3,
          Paint()
            ..color = accent.withValues(alpha: 0.35 + 0.45 * t)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4);
    }
    if (selected != null) {
      final Offset c = _top(selected!);
      if (fancy) {
        canvas.drawCircle(
            c,
            BgGeom.d / 2 + 8,
            Paint()
              ..color = glow.withValues(alpha: 0.6)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14));
      }
      canvas.drawCircle(
          c,
          BgGeom.d / 2 + 4,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 6);
    }
  }

  @override
  bool shouldRepaint(covariant BgHighlightPainter oldDelegate) => true;
}

/// Pip layout (unit square) for die faces.
List<Offset> bgPipLayout(int v) {
  const double a = 0.27;
  const double b = 0.73;
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

/// Ivory die face with carved pips (procedural: the die images only show
/// fixed faces, so they are used for the tumbling animation instead).
class BgDieFacePainter extends CustomPainter {
  const BgDieFacePainter(this.value,
      {this.used = false, this.accent = const Color(0xFFFFC857)});
  final int value;
  final bool used;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect r = Offset.zero & size;
    final RRect rr =
        RRect.fromRectAndRadius(r, Radius.circular(size.width * 0.2));
    canvas.drawRRect(
        rr.shift(Offset(0, size.height * 0.06)),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.45)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    canvas.drawRRect(
        rr,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: used
                ? const <Color>[Color(0xFF8C8578), Color(0xFF5E584E)]
                : const <Color>[Color(0xFFFFFBEF), Color(0xFFE8DCC0)],
          ).createShader(r));
    canvas.drawRRect(
        rr.deflate(1.5),
        Paint()
          ..color = accent.withValues(alpha: used ? 0.2 : 0.82)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
    final double pr = size.width * 0.09;
    for (final Offset o in bgPipLayout(value)) {
      final Offset c = Offset(o.dx * size.width, o.dy * size.height);
      canvas.drawCircle(c, pr, Paint()..color = const Color(0xFF15110B));
      canvas.drawCircle(c.translate(-pr * 0.3, -pr * 0.3), pr * 0.35,
          Paint()..color = Colors.white.withValues(alpha: 0.18));
    }
  }

  @override
  bool shouldRepaint(covariant BgDieFacePainter oldDelegate) =>
      oldDelegate.value != value ||
      oldDelegate.used != used ||
      oldDelegate.accent != accent;
}

/// Procedural checker used only if the checker images fail to load.
class BgCheckerPainter extends CustomPainter {
  const BgCheckerPainter(this.player);
  final int player;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset c = size.center(Offset.zero);
    final double r = size.width / 2;
    final List<Color> cols = player == 0
        ? const <Color>[Color(0xFFF3D39A), Color(0xFFB98543)]
        : const <Color>[Color(0xFF7A4429), Color(0xFF2E160B)];
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(colors: cols)
              .createShader(Rect.fromCircle(center: c, radius: r)));
    canvas.drawCircle(
        c,
        r * 0.7,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3);
  }

  @override
  bool shouldRepaint(covariant BgCheckerPainter oldDelegate) =>
      oldDelegate.player != player;
}
