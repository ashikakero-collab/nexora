import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../core/pool_aim.dart';
import '../core/pool_config.dart';
import '../core/pool_physics.dart';
import 'pool_scene.dart';

Color _shade(Color c, double f) {
  // f < 0 darkens, f > 0 lightens
  final int r = (c.red + ((f > 0 ? 255 - c.red : c.red) * f))
      .round()
      .clamp(0, 255)
      .toInt();
  final int g = (c.green + ((f > 0 ? 255 - c.green : c.green) * f))
      .round()
      .clamp(0, 255)
      .toInt();
  final int b = (c.blue + ((f > 0 ? 255 - c.blue : c.blue) * f))
      .round()
      .clamp(0, 255)
      .toInt();
  return Color.fromARGB(c.alpha, r, g, b);
}

/// Procedural table used when the art fails to load. Paints in art space
/// (1024 x 1536 scaled to the widget size) so geometry matches the physics.
class PoolTableFallbackPainter extends CustomPainter {
  const PoolTableFallbackPainter({this.accent = const Color(0xFFF3C56B)});
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.width / PoolConfig.artW;
    canvas.save();
    canvas.scale(s, s);
    const Rect outer =
        Rect.fromLTWH(8, 8, PoolConfig.artW - 16, PoolConfig.artH - 16);
    canvas.drawRRect(
      RRect.fromRectAndRadius(outer, const Radius.circular(60)),
      Paint()
        ..shader = ui.Gradient.linear(
            outer.topLeft, outer.bottomRight, const <Color>[
          Color(0xFF8A3A12),
          Color(0xFF5C230A),
          Color(0xFF8A3A12)
        ], const <double>[
          0,
          0.5,
          1
        ]),
    );
    const Rect cloth = Rect.fromLTWH(
        PoolConfig.artClothLeft - 32,
        PoolConfig.artClothTop - 30,
        PoolConfig.tableW + 64,
        PoolConfig.tableH + 60);
    canvas.drawRect(cloth, Paint()..color = const Color(0xFF0E9E3E));
    const Rect play = Rect.fromLTWH(PoolConfig.artClothLeft,
        PoolConfig.artClothTop, PoolConfig.tableW, PoolConfig.tableH);
    canvas.drawRect(
      play,
      Paint()
        ..shader = ui.Gradient.radial(
            play.center,
            play.height * 0.6,
            const <Color>[Color(0xFF17B84E), Color(0xFF0B8A35)],
            const <double>[0, 1]),
    );
    // cushion faces
    canvas.save();
    canvas.translate(PoolConfig.artClothLeft, PoolConfig.artClothTop);
    final Paint cush = Paint()
      ..color = const Color(0xFF26D466)
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke;
    for (final List<double> sg in PoolConfig.cushions) {
      canvas.drawLine(Offset(sg[0], sg[1]), Offset(sg[2], sg[3]), cush);
    }
    final Paint gold = Paint()..color = accent;
    final Paint hole = Paint()..color = const Color(0xFF050505);
    for (int p = 0; p < PoolConfig.pockets.length; p++) {
      final Offset c =
          Offset(PoolConfig.pockets[p][0], PoolConfig.pockets[p][1]);
      canvas.drawCircle(c, 62, gold);
      canvas.drawCircle(c, 52, hole);
    }
    // diamonds
    final Paint dia = Paint()..color = const Color(0xFFFFF3D6);
    for (int i = 1; i < 4; i++) {
      final double x = PoolConfig.tableW * i / 4;
      canvas.drawCircle(Offset(x, -55), 5, dia);
      canvas.drawCircle(Offset(x, PoolConfig.tableH + 55), 5, dia);
    }
    for (int i = 1; i < 8; i++) {
      if (i == 4) continue;
      final double y = PoolConfig.tableH * i / 8;
      canvas.drawCircle(Offset(-55, y), 5, dia);
      canvas.drawCircle(Offset(PoolConfig.tableW + 55, y), 5, dia);
    }
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant PoolTableFallbackPainter oldDelegate) => false;
}

/// Draws guides, balls, cue and effects on top of the table (art space).
class PoolScenePainter extends CustomPainter {
  PoolScenePainter(this.scene,
      {required this.accent,
      required this.accentSecondary,
      required this.error})
      : super(repaint: scene);

  final PoolScene scene;
  final Color accent;
  final Color accentSecondary;
  final Color error;
  static final Map<int, TextPainter> _labels = <int, TextPainter>{};

  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.width / PoolConfig.artW;
    canvas.save();
    canvas.scale(s, s);
    canvas.translate(PoolConfig.artClothLeft, PoolConfig.artClothTop);
    final List<PoolBall> balls = scene.match.balls;

    _drawFlashes(canvas);
    if (scene.kitchenOnly && scene.ballInHand) _drawKitchen(canvas);
    for (final PoolSink k in scene.sinks) {
      final double f = 1 - k.t;
      canvas.save();
      canvas.translate(k.x, k.y);
      canvas.scale(0.35 + 0.65 * f, 0.35 + 0.65 * f);
      _drawBall(canvas, k.ballId, 0, 0, 0, shadow: false, opacity: f);
      canvas.restore();
    }
    // shadows first so they never overlap neighbouring balls
    final Paint sh = Paint()..color = const Color(0x59000000);
    if (scene.fancy) sh.maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    for (final PoolBall b in balls) {
      if (b.pocketed) continue;
      canvas.drawOval(
          Rect.fromCenter(
              center: Offset(b.x + 4, b.y + 6),
              width: PoolConfig.ballR * 2.1,
              height: PoolConfig.ballR * 1.9),
          sh);
    }
    if (scene.showAim && !balls[0].pocketed) _drawGuide(canvas, balls);
    for (final PoolBall b in balls) {
      if (b.pocketed) continue;
      _drawBall(canvas, b.id, b.x, b.y, scene.roll[b.id],
          shadow: false, opacity: 1);
    }
    if (scene.ballInHand && !balls[0].pocketed) _drawHandRing(canvas, balls[0]);
    _drawParticles(canvas);
    if (scene.showCue && !balls[0].pocketed && scene.cueOpacity > 0.01)
      _drawCue(canvas, balls[0]);
    canvas.restore();
  }

  // ---------------------------------------------------------------- pieces
  void _drawFlashes(Canvas canvas) {
    for (final PoolFlash f in scene.flashes) {
      final Offset c = Offset(
          PoolConfig.pockets[f.pocket][0], PoolConfig.pockets[f.pocket][1]);
      final double a = (1 - f.t).clamp(0.0, 1.0).toDouble();
      final double rad = 50 + 70 * f.t;
      canvas.drawCircle(
        c,
        rad,
        Paint()
          ..shader = ui.Gradient.radial(c, rad, <Color>[
            f.color.withOpacity(0.0),
            f.color.withOpacity(0.55 * a),
            f.color.withOpacity(0.0),
          ], const <double>[
            0.35,
            0.7,
            1
          ]),
      );
    }
  }

  void _drawKitchen(Canvas canvas) {
    final Paint p = Paint()
      ..color = const Color(0x88EAF6FF)
      ..strokeWidth = 2.5;
    const double y = PoolConfig.headStringY;
    for (double x = 0; x < PoolConfig.tableW; x += 24) {
      canvas.drawLine(
          Offset(x, y), Offset(math.min(x + 12, PoolConfig.tableW), y), p);
    }
    canvas.drawRect(
      const Rect.fromLTWH(0, PoolConfig.headStringY, PoolConfig.tableW,
          PoolConfig.tableH - PoolConfig.headStringY),
      Paint()..color = const Color(0x1400C2FF),
    );
  }

  void _drawHandRing(Canvas canvas, PoolBall c) {
    final double pulse = 0.5 + 0.5 * math.sin(scene.time * 5);
    final Color col = scene.placeValid ? accent : error;
    final Paint ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = col.withOpacity(0.55 + 0.4 * pulse);
    final double rr = PoolConfig.ballR + 8 + 5 * pulse;
    canvas.drawCircle(Offset(c.x, c.y), rr, ring);
    // four arrows = "drag me"
    final Paint ar = Paint()..color = col.withOpacity(0.9);
    for (int k = 0; k < 4; k++) {
      final double a = k * math.pi / 2;
      final double ca = math.cos(a), sa = math.sin(a);
      final double d0 = rr + 6, d1 = rr + 16;
      final Path p = Path()
        ..moveTo(c.x + ca * d1, c.y + sa * d1)
        ..lineTo(c.x + ca * d0 - sa * 6, c.y + sa * d0 + ca * 6)
        ..lineTo(c.x + ca * d0 + sa * 6, c.y + sa * d0 - ca * 6)
        ..close();
      canvas.drawPath(p, ar);
    }
  }

  void _drawGuide(Canvas canvas, List<PoolBall> balls) {
    final double dx = math.cos(scene.aimAngle), dy = math.sin(scene.aimAngle);
    final PoolAimPrediction pr = poolPredict(balls, dx, dy);
    final PoolBall c = balls[0];
    final bool legal = pr.hitBall < 0 || scene.match.isLegalTarget(pr.hitBall);
    final Color col = legal ? accent : error;
    final Paint line = Paint()
      ..color = col.withOpacity(0.85)
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;
    if (scene.fancy) {
      canvas.drawLine(
        Offset(c.x, c.y),
        Offset(pr.ghostX, pr.ghostY),
        Paint()
          ..color = accentSecondary.withOpacity(0.24)
          ..strokeWidth = 9
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }
    // dashed main line
    final double lx = pr.ghostX - c.x, ly = pr.ghostY - c.y;
    final double len = math.sqrt(lx * lx + ly * ly);
    if (len > 1) {
      final double ux = lx / len, uy = ly / len;
      final double phase = (scene.time * 40) % 22;
      for (double t = PoolConfig.ballR + phase;
          t < len - PoolConfig.ballR * 0.5;
          t += 22) {
        final double t2 = math.min(t + 12, len - PoolConfig.ballR * 0.5);
        canvas.drawLine(Offset(c.x + ux * t, c.y + uy * t),
            Offset(c.x + ux * t2, c.y + uy * t2), line);
      }
    }
    // ghost ball
    canvas.drawCircle(
      Offset(pr.ghostX, pr.ghostY),
      PoolConfig.ballR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..color = col.withOpacity(0.9),
    );
    canvas.drawCircle(Offset(pr.ghostX, pr.ghostY), PoolConfig.ballR,
        Paint()..color = col.withOpacity(0.12));
    if (pr.hitBall >= 0) {
      final PoolBall b = balls[pr.hitBall];
      if (!legal) {
        final Paint x = Paint()
          ..color = const Color(0xFFFF5A6E)
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round;
        const double k = 9;
        canvas.drawLine(Offset(pr.ghostX - k, pr.ghostY - k),
            Offset(pr.ghostX + k, pr.ghostY + k), x);
        canvas.drawLine(Offset(pr.ghostX - k, pr.ghostY + k),
            Offset(pr.ghostX + k, pr.ghostY - k), x);
        return;
      }
      final double ol = 60 + 220 * pr.cutFactor;
      canvas.drawLine(
        Offset(b.x + pr.objDirX * PoolConfig.ballR,
            b.y + pr.objDirY * PoolConfig.ballR),
        Offset(b.x + pr.objDirX * (PoolConfig.ballR + ol),
            b.y + pr.objDirY * (PoolConfig.ballR + ol)),
        Paint()
          ..color = accentSecondary.withOpacity(0.95)
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
      final double cl = 30 + 120 * (1 - pr.cutFactor);
      canvas.drawLine(
        Offset(pr.ghostX, pr.ghostY),
        Offset(pr.ghostX + pr.cueDirX * cl, pr.ghostY + pr.cueDirY * cl),
        Paint()
          ..color = accent.withOpacity(0.55)
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
    } else {
      canvas.drawLine(
        Offset(pr.ghostX, pr.ghostY),
        Offset(pr.ghostX + pr.cueDirX * 90, pr.ghostY + pr.cueDirY * 90),
        Paint()
          ..color = col.withOpacity(0.4)
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  TextPainter _label(int id) {
    final TextPainter? hit = _labels[id];
    if (hit != null) return hit;
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: '$id',
        style: const TextStyle(
            color: Color(0xFF111111),
            fontSize: 11,
            fontWeight: FontWeight.w800,
            height: 1.0),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    _labels[id] = tp;
    return tp;
  }

  void _drawBall(Canvas canvas, int id, double x, double y, double roll,
      {required bool shadow, required double opacity}) {
    const double r = PoolConfig.ballR;
    final Offset c = Offset(x, y);
    final Color base = poolBallColor(id);
    final bool stripe = id >= 9;
    final int alpha = (opacity * 255).round().clamp(0, 255).toInt();
    final Color body = stripe || id == 0 ? const Color(0xFFF7F4EA) : base;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(x - r * 0.35, y - r * 0.4),
          r * 1.45,
          <Color>[
            _shade(body, 0.35).withAlpha(alpha),
            body.withAlpha(alpha),
            _shade(body, -0.55).withAlpha(alpha)
          ],
          const <double>[0, 0.5, 1],
        ),
    );
    final double phase = roll / r;
    final double sp = math.sin(phase), cp = math.cos(phase);
    final double rdx = scene.rollDirX[id], rdy = scene.rollDirY[id];
    if (stripe) {
      canvas.save();
      canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));
      final double ang = math.atan2(rdy, rdx) + math.pi / 2;
      canvas.translate(x, y);
      canvas.rotate(ang);
      final double off = sp * r * 0.35;
      canvas.drawRect(
        Rect.fromLTRB(-r * 1.2, -r * 0.52 + off, r * 1.2, r * 0.52 + off),
        Paint()
          ..shader = ui.Gradient.linear(Offset(-r, 0), Offset(r, 0), <Color>[
            _shade(base, -0.35).withAlpha(alpha),
            base.withAlpha(alpha),
            _shade(base, -0.45).withAlpha(alpha)
          ], const <double>[
            0,
            0.45,
            1
          ]),
      );
      canvas.restore();
      // re-shade the white parts for volume
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = ui.Gradient.radial(
              Offset(x - r * 0.3, y - r * 0.35), r * 1.4, <Color>[
            const Color(0x00000000),
            Color.fromARGB((90 * opacity).round(), 0, 0, 0)
          ], const <double>[
            0.55,
            1
          ]),
      );
    }
    if (id != 0 && cp > -0.15) {
      // number disc slides with the roll direction to fake 3D rotation
      final double vis = (0.55 + 0.45 * cp).clamp(0.0, 1.0).toDouble();
      final double ox = rdx * sp * r * 0.5, oy = rdy * sp * r * 0.5;
      final Offset nc = Offset(x + ox, y + oy);
      canvas.drawCircle(
          nc,
          r * 0.5 * vis,
          Paint()
            ..color = const Color(0xFFFFFBF0).withAlpha((alpha * vis).round()));
      if (vis > 0.6) {
        final TextPainter tp = _label(id);
        final double k = vis * (r * 0.55) / 11;
        canvas.save();
        canvas.translate(nc.dx, nc.dy);
        canvas.scale(k, k);
        tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
        canvas.restore();
      }
    } else if (id == 0) {
      final double ox = rdx * sp * r * 0.55, oy = rdy * sp * r * 0.55;
      if (cp > 0) {
        canvas.drawCircle(
            Offset(x + ox, y + oy),
            r * 0.12 * cp,
            Paint()
              ..color = Color.fromARGB((150 * opacity).round(), 220, 40, 60));
      }
    }
    // specular highlight
    canvas.drawCircle(
        Offset(x - r * 0.38, y - r * 0.42),
        r * 0.26,
        Paint()
          ..color = Color.fromARGB((210 * opacity).round(), 255, 255, 255));
    canvas.drawCircle(Offset(x - r * 0.2, y - r * 0.25), r * 0.6,
        Paint()..color = Color.fromARGB((28 * opacity).round(), 255, 255, 255));
  }

  void _drawParticles(Canvas canvas) {
    if (scene.particles.isEmpty) return;
    final Paint p = Paint()..blendMode = BlendMode.plus;
    for (final PoolParticle q in scene.particles) {
      final double a = (1 - q.age / q.life).clamp(0.0, 1.0).toDouble();
      p.color = q.color.withOpacity(a);
      canvas.drawCircle(Offset(q.x, q.y), 2.2 + 2.5 * a, p);
    }
  }

  // ---------------------------------------------------------------- cue
  void _section(Canvas canvas, double x0, double x1, double hw0, double hw1,
      Color c, double op) {
    final Path p = Path()
      ..moveTo(x0, -hw0)
      ..lineTo(x1, -hw1)
      ..lineTo(x1, hw1)
      ..lineTo(x0, hw0)
      ..close();
    final double hw = math.max(hw0, hw1);
    canvas.drawPath(
      p,
      Paint()
        ..shader = ui.Gradient.linear(Offset(0, -hw), Offset(0, hw), <Color>[
          _shade(c, -0.45).withOpacity(op),
          _shade(c, 0.45).withOpacity(op),
          c.withOpacity(op),
          _shade(c, -0.6).withOpacity(op),
        ], const <double>[
          0,
          0.32,
          0.6,
          1
        ]),
    );
  }

  void _drawCue(Canvas canvas, PoolBall cue) {
    final double op = scene.cueOpacity.clamp(0.0, 1.0).toDouble();
    const double len = 760;
    final double gap = 6 + scene.pull * 110 - scene.strikeOffset;
    final double tip = PoolConfig.ballR + math.max(0.0, gap);
    canvas.save();
    canvas.translate(cue.x, cue.y);
    canvas.rotate(scene.aimAngle);
    // shadow
    final Path shadow = Path()
      ..moveTo(-tip, -3.4)
      ..lineTo(-tip - len, -7.5)
      ..lineTo(-tip - len, 7.5)
      ..lineTo(-tip, 3.4)
      ..close();
    final Paint sp = Paint()
      ..color = Color.fromARGB((70 * op).round(), 0, 0, 0);
    if (scene.fancy) sp.maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    canvas.save();
    canvas.translate(-6, 10);
    canvas.drawPath(shadow, sp);
    canvas.restore();

    double hwAt(double d) => 3.4 + (7.5 - 3.4) * (d / len);
    final double a = -tip; // tip x (cue extends toward negative x)
    void sec(double d0, double d1, Color c) =>
        _section(canvas, a - d0, a - d1, hwAt(d0), hwAt(d1), c, op);

    switch (scene.cueSkin) {
      case 'cue_neon':
        if (scene.fancy) {
          canvas.drawPath(
            shadow,
            Paint()
              ..color = const Color(0xFF00E5FF).withOpacity(0.55 * op)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
          );
        }
        sec(0, 6, const Color(0xFF00E5FF));
        sec(6, 16, const Color(0xFFEAF6FF));
        sec(16, 470, const Color(0xFF0D1B3A));
        sec(470, 478, const Color(0xFF00E5FF));
        sec(478, 690, const Color(0xFF0A1230));
        sec(690, len, const Color(0xFF00C2FF));
        final Paint core = Paint()
          ..color = const Color(0xFF7DF9FF).withOpacity(0.95 * op)
          ..strokeWidth = 1.6;
        canvas.drawLine(Offset(a - 16, 0), Offset(a - 690, 0), core);
        for (int i = 0; i < 4; i++) {
          final double d = 520.0 + i * 40;
          canvas.drawLine(
              Offset(a - d, -hwAt(d)), Offset(a - d - 14, hwAt(d + 14)), core);
        }
        break;
      case 'cue_gold':
        if (scene.fancy) {
          canvas.drawPath(
            shadow,
            Paint()
              ..color = const Color(0xFFFFC857).withOpacity(0.3 * op)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
          );
        }
        sec(0, 6, const Color(0xFF2B6CB0));
        sec(6, 16, const Color(0xFFFFF8E7));
        sec(16, 430, const Color(0xFFF3E2B3));
        sec(430, 440, const Color(0xFF1A1A1A));
        sec(440, 600, const Color(0xFFE9B949));
        sec(600, 606, const Color(0xFF1A1A1A));
        sec(606, 700, const Color(0xFF151515));
        sec(700, 708, const Color(0xFFE9B949));
        sec(708, len, const Color(0xFFC99A2E));
        final Paint gem = Paint()
          ..color = const Color(0xFFFFF3C4).withOpacity(op);
        for (int i = 0; i < 3; i++) {
          canvas.drawCircle(Offset(a - 470 - i * 50, 0), 2.2, gem);
        }
        break;
      default:
        sec(0, 6, const Color(0xFF3A6EA5));
        sec(6, 16, const Color(0xFFF8F6F0));
        sec(16, 440, const Color(0xFFE8C88C));
        sec(440, 448, const Color(0xFFCFD6DE));
        sec(448, 640, const Color(0xFF6B3417));
        sec(640, 730, const Color(0xFF1E1E1E));
        sec(730, len, const Color(0xFF3B1A0A));
        // inlay points
        final Paint inlay = Paint()
          ..color = const Color(0xFFF1DDB0).withOpacity(0.85 * op);
        for (int i = 0; i < 4; i++) {
          const double d = 460.0;
          final double w = hwAt(d) * (i.isEven ? 0.7 : -0.7);
          final Path pt = Path()
            ..moveTo(a - d, w)
            ..lineTo(a - d - 120, w * 0.2)
            ..lineTo(a - d, w * 0.4)
            ..close();
          canvas.drawPath(pt, inlay);
        }
        break;
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant PoolScenePainter oldDelegate) =>
      oldDelegate.scene != scene;
}
