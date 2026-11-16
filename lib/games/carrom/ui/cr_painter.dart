import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/carrom_config.dart';
import '../core/carrom_match.dart';
import '../core/carrom_physics.dart';
import 'cr_controller.dart';

/// Decoded artwork (null -> procedural fallback).
class CrImages {
  ui.Image? board;
  ui.Image? white;
  ui.Image? black;
  ui.Image? queen;
  ui.Image? striker0;
  ui.Image? striker1;
}

class CrPainter extends CustomPainter {
  CrPainter(this.c, this.images,
      {required this.accent,
      required this.accentSecondary,
      required this.error})
      : super(repaint: c);

  final CrController c;
  final CrImages images;
  final Color accent;
  final Color accentSecondary;
  final Color error;

  static final Paint _imgPaint = Paint()..filterQuality = FilterQuality.medium;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final s = math.min(size.width, size.height) / CrConfig.boardSize;
    final ox = (size.width - CrConfig.boardSize * s) / 2;
    final oy = (size.height - CrConfig.boardSize * s) / 2;
    final fancy = c.fx.enabled;

    canvas.save();
    canvas.translate(
        ox + c.fx.shakeOffset.dx * s, oy + c.fx.shakeOffset.dy * s);
    canvas.scale(s, s);
    _drawBoard(canvas, fancy);
    _drawSinking(canvas);
    final m = c.match;
    for (final b in m.bodies) {
      if (!b.onBoard || b.isStriker) continue;
      _drawCoin(canvas, b, fancy);
    }
    if (fancy) _drawTrail(canvas);
    if (m.phase == CrPhase.aiming) {
      _drawAimGuide(canvas);
      _drawStrikerAt(canvas, c.strikerX, c.strikerY, m.turn, fancy,
          aimingStriker: true);
    } else if (m.striker.onBoard) {
      _drawStrikerAt(canvas, m.striker.x, m.striker.y, m.turn, fancy,
          aimingStriker: false);
    }
    c.fx.paintParticles(canvas);
    canvas.restore();

    if (c.fx.flash > 0) {
      canvas.drawRect(
          Offset.zero & size,
          Paint()
            ..color = c.fx.flashColor
                .withOpacity((c.fx.flash * 0.4).clamp(0.0, 1.0).toDouble()));
    }
    if (c.bannerTime > 0 && c.bannerFa.isNotEmpty) _drawBanner(canvas, size);
  }

  // ------------------------------------------------------------- board
  void _drawBoard(Canvas canvas, bool fancy) {
    const full = Rect.fromLTWH(0, 0, CrConfig.boardSize, CrConfig.boardSize);
    final img = images.board;
    if (img != null) {
      canvas.drawImageRect(
          img,
          Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
          full,
          _imgPaint);
    } else {
      _drawProceduralBoard(canvas);
    }
    // Active baseline glow for the shooter.
    if (c.match.phase == CrPhase.aiming) {
      final y = c.strikerY;
      final col = c.match.turn == 0 ? accent : accentSecondary;
      final pulse = fancy ? 0.5 + 0.5 * math.sin(c.clock * 3) : 0.5;
      final p = Paint()
        ..color = col.withOpacity(0.18 + 0.14 * pulse)
        ..strokeWidth = CrConfig.strikerR * 2
        ..strokeCap = StrokeCap.round;
      if (fancy) p.maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawLine(
          Offset(CrConfig.baseMinX, y), Offset(CrConfig.baseMaxX, y), p);
    }
  }

  void _drawProceduralBoard(Canvas canvas) {
    const full = Rect.fromLTWH(0, 0, CrConfig.boardSize, CrConfig.boardSize);
    canvas.drawRRect(RRect.fromRectAndRadius(full, const Radius.circular(40)),
        Paint()..color = const Color(0xFF1A1206));
    canvas.drawRRect(
        RRect.fromRectAndRadius(full.deflate(14), const Radius.circular(32)),
        Paint()
          ..color = accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 10);
    const play = Rect.fromLTRB(
        CrConfig.left, CrConfig.top, CrConfig.right, CrConfig.bottom);
    canvas.drawRect(
        play,
        Paint()
          ..shader = ui.Gradient.radial(
            const Offset(CrConfig.centerX, CrConfig.centerY),
            520,
            <Color>[const Color(0xFF1C1F2E), const Color(0xFF07080D)],
          ));
    final line = Paint()
      ..color = kCrGold.withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(
        const Offset(CrConfig.centerX, CrConfig.centerY), 150, line);
    canvas.drawCircle(
        const Offset(CrConfig.centerX, CrConfig.centerY), 30, line);
    for (final y in <double>[CrConfig.baseline0, CrConfig.baseline1]) {
      canvas.drawLine(Offset(CrConfig.baseMinX, y - 25),
          Offset(CrConfig.baseMaxX, y - 25), line);
      canvas.drawLine(Offset(CrConfig.baseMinX, y + 25),
          Offset(CrConfig.baseMaxX, y + 25), line);
      canvas.drawCircle(Offset(CrConfig.baseMinX, y), CrConfig.coinR,
          Paint()..color = const Color(0xFFE53935));
      canvas.drawCircle(Offset(CrConfig.baseMaxX, y), CrConfig.coinR,
          Paint()..color = const Color(0xFFE53935));
    }
    for (final x in <double>[187.5, 836.5]) {
      canvas.drawLine(Offset(x - 25, 246), Offset(x - 25, 736), line);
      canvas.drawLine(Offset(x + 25, 246), Offset(x + 25, 736), line);
    }
    for (final p in CrConfig.pockets) {
      canvas.drawCircle(Offset(p[0], p[1]), CrConfig.pocketR,
          Paint()..color = const Color(0xFF000000));
      canvas.drawCircle(
          Offset(p[0], p[1]),
          CrConfig.pocketR,
          Paint()
            ..color = kCrGold
            ..style = PaintingStyle.stroke
            ..strokeWidth = 6);
    }
  }

  // ------------------------------------------------------------- pieces
  ui.Image? _coinImage(CrKind k) => switch (k) {
        CrKind.white => images.white,
        CrKind.black => images.black,
        CrKind.queen => images.queen,
        CrKind.striker => images.striker0,
      };

  Color _coinColor(CrKind k) => switch (k) {
        CrKind.white => const Color(0xFFF3E3C3),
        CrKind.black => const Color(0xFF22252E),
        CrKind.queen => const Color(0xFFE0243C),
        CrKind.striker => const Color(0xFFEAF6FF),
      };

  void _paintDisc(
      Canvas canvas, Offset center, double r, ui.Image? img, Color fallback) {
    if (img != null) {
      canvas.drawImageRect(
          img,
          Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
          Rect.fromCircle(center: center, radius: r),
          _imgPaint);
    } else {
      canvas.drawCircle(center, r, Paint()..color = fallback);
      canvas.drawCircle(
          center,
          r * 0.62,
          Paint()
            ..color = const Color(0x33FFFFFF)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
    }
  }

  void _drawShadow(Canvas canvas, Offset center, double r, bool fancy) {
    final p = Paint()..color = const Color(0x77000000);
    if (fancy) p.maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(center + const Offset(3, 5), r * 1.02, p);
  }

  void _drawCoin(Canvas canvas, CrBody b, bool fancy) {
    var r = b.r;
    final born = c.spawnedAt[b.id];
    if (born != null) {
      final t = (c.clock - born) / 0.35;
      if (t < 1) {
        r = b.r * (0.3 + 0.7 * t + 0.25 * math.sin(t * math.pi));
        canvas.drawCircle(
            Offset(b.x, b.y),
            b.r * (1.2 + t),
            Paint()
              ..color = kCrDanger.withOpacity(0.5 * (1 - t))
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3);
      }
    }
    final center = Offset(b.x, b.y);
    _drawShadow(canvas, center, r, fancy);
    if (b.isQueen && fancy) {
      final pulse = 0.5 + 0.5 * math.sin(c.clock * 2.5);
      canvas.drawCircle(
          center,
          r + 5 + 2 * pulse,
          Paint()
            ..color = const Color(0xFFFF4F6E).withOpacity(0.25 + 0.2 * pulse)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
    }
    _paintDisc(canvas, center, r, _coinImage(b.kind), _coinColor(b.kind));
  }

  void _drawSinking(Canvas canvas) {
    for (final a in c.sinking) {
      final t = a.t.clamp(0.0, 1.0).toDouble();
      final e = t * t;
      final x = a.x + (a.px - a.x) * e;
      final y = a.y + (a.py - a.y) * e;
      final r =
          (a.kind == CrKind.striker ? CrConfig.strikerR : CrConfig.coinR) *
              (1 - 0.75 * t);
      ui.Image? img;
      if (a.kind == CrKind.striker) {
        img = c.match.turn == 0 ? images.striker0 : images.striker1;
      } else {
        img = _coinImage(a.kind);
      }
      canvas.saveLayer(Rect.fromCircle(center: Offset(x, y), radius: r + 2),
          Paint()..color = Color.fromRGBO(255, 255, 255, 1 - t));
      _paintDisc(canvas, Offset(x, y), r, img, _coinColor(a.kind));
      canvas.restore();
    }
  }

  void _drawStrikerAt(Canvas canvas, double x, double y, int seat, bool fancy,
      {required bool aimingStriker}) {
    final center = Offset(x, y);
    const r = CrConfig.strikerR;
    final valid = !aimingStriker || c.placementValid;
    if (aimingStriker) {
      final pulse = fancy ? 0.5 + 0.5 * math.sin(c.clock * 5) : 0.5;
      final col = valid ? (seat == 0 ? accent : accentSecondary) : error;
      final glow = Paint()
        ..color = col.withOpacity(0.35 + 0.3 * pulse)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5;
      if (fancy) glow.maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      canvas.drawCircle(center, r + 6 + 2 * pulse, glow);
    }
    _drawShadow(canvas, center, r, fancy);
    _paintDisc(canvas, center, r, seat == 0 ? images.striker0 : images.striker1,
        _coinColor(CrKind.striker));
    if (!valid) {
      final x1 = Paint()
        ..color = kCrDanger
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
          center + const Offset(-12, -12), center + const Offset(12, 12), x1);
      canvas.drawLine(
          center + const Offset(12, -12), center + const Offset(-12, 12), x1);
    }
  }

  void _drawTrail(Canvas canvas) {
    final t = c.trail;
    for (var i = 1; i < t.length; i++) {
      final a = i / t.length;
      canvas.drawLine(
          t[i - 1],
          t[i],
          Paint()
            ..color = accent.withOpacity(0.35 * a)
            ..strokeWidth = 16 * a
            ..strokeCap = StrokeCap.round);
    }
  }

  // ------------------------------------------------------------- aim guide (ray cast)
  void _drawAimGuide(Canvas canvas) {
    final dir = c.aimDir;
    if (dir == null) return;
    final power = c.aimPower;
    final sx = c.strikerX, sy = c.strikerY;
    const sr = CrConfig.strikerR;
    final col = Color.lerp(accent, error, power) ?? Colors.white;

    // first coin hit
    var tHit = double.infinity;
    CrBody? hit;
    for (final b in c.match.bodies) {
      if (!b.onBoard || b.isStriker) continue;
      final fx = sx - b.x, fy = sy - b.y;
      final bb = fx * dir.dx + fy * dir.dy;
      final rr = sr + b.r;
      final cc = fx * fx + fy * fy - rr * rr;
      final disc = bb * bb - cc;
      if (disc < 0) continue;
      final t = -bb - math.sqrt(disc);
      if (t > 0 && t < tHit) {
        tHit = t;
        hit = b;
      }
    }
    // cushion
    var tWall = double.infinity;
    var wallNx = 0.0, wallNy = 0.0;
    if (dir.dx > 1e-9) {
      final t = (CrConfig.right - sr - sx) / dir.dx;
      if (t < tWall) {
        tWall = t;
        wallNx = -1;
        wallNy = 0;
      }
    } else if (dir.dx < -1e-9) {
      final t = (CrConfig.left + sr - sx) / dir.dx;
      if (t < tWall) {
        tWall = t;
        wallNx = 1;
        wallNy = 0;
      }
    }
    if (dir.dy > 1e-9) {
      final t = (CrConfig.bottom - sr - sy) / dir.dy;
      if (t < tWall) {
        tWall = t;
        wallNx = 0;
        wallNy = -1;
      }
    } else if (dir.dy < -1e-9) {
      final t = (CrConfig.top + sr - sy) / dir.dy;
      if (t < tWall) {
        tWall = t;
        wallNx = 0;
        wallNy = 1;
      }
    }
    final useHit = hit != null && tHit < tWall;
    final tEnd =
        useHit ? tHit : (tWall.isFinite ? math.max(0.0, tWall) : 600.0);
    final start = Offset(sx, sy);
    final end = start + dir * tEnd;

    // dashed travel line
    final dash = Paint()
      ..color = col.withOpacity(0.85)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final total = tEnd;
    for (var d = sr + 6; d < total; d += 22) {
      final a = start + dir * d;
      final b2 = start + dir * math.min(total, d + 12);
      canvas.drawLine(a, b2, dash);
    }
    // power arc around the striker
    canvas.drawArc(
        Rect.fromCircle(center: start, radius: sr + 14),
        -math.pi / 2,
        2 * math.pi * power,
        false,
        Paint()
          ..color = col
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round);
    // ghost striker at contact
    canvas.drawCircle(
        end,
        sr,
        Paint()
          ..color = col.withOpacity(0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3);
    final target = hit;
    if (useHit && target != null) {
      var nx = target.x - end.dx, ny = target.y - end.dy;
      final nl = math.sqrt(nx * nx + ny * ny);
      if (nl > 1e-6) {
        nx /= nl;
        ny /= nl;
        final from = Offset(target.x, target.y);
        final len = 70 + 230 * power;
        canvas.drawLine(
            from,
            from + Offset(nx, ny) * len,
            Paint()
              ..color = (target.isQueen
                      ? const Color(0xFFFF4F6E)
                      : _coinColor(target.kind))
                  .withOpacity(0.9)
              ..strokeWidth = 5
              ..strokeCap = StrokeCap.round);
        canvas.drawCircle(
            from,
            target.r + 5,
            Paint()
              ..color = Colors.white.withOpacity(0.7)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3);
      }
    } else if (tWall.isFinite) {
      // reflection preview
      final dot = dir.dx * wallNx + dir.dy * wallNy;
      final rx = dir.dx - 2 * dot * wallNx, ry = dir.dy - 2 * dot * wallNy;
      canvas.drawLine(
          end,
          end + Offset(rx, ry) * (60 + 120 * power),
          Paint()
            ..color = col.withOpacity(0.45)
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round);
    }
  }

  void _drawBanner(Canvas canvas, Size size) {
    final text = c.launch.tx(c.bannerFa, c.bannerEn);
    final t = c.bannerTime;
    final grow = math.min(1.0, c.bannerAge / 0.25);
    final scale = c.launch.reducedMotion
        ? 1.0
        : (0.6 + 0.4 * grow + 0.08 * math.sin(grow * math.pi));
    final alpha = math.min(1.0, t / 0.4);
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.white.withOpacity(alpha),
          fontSize: math.min(56.0, size.width * 0.11),
          fontWeight: FontWeight.w900,
          shadows: <Shadow>[
            Shadow(color: c.bannerColor.withOpacity(alpha), blurRadius: 22),
            Shadow(
                color: Colors.black.withOpacity(0.7 * alpha),
                blurRadius: 8,
                offset: const Offset(0, 3)),
          ],
        ),
      ),
      textDirection: c.launch.isFa ? TextDirection.rtl : TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(maxWidth: size.width * 0.9);
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    if (c.flipped) canvas.rotate(math.pi);
    canvas.scale(scale, scale);
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CrPainter oldDelegate) =>
      oldDelegate.c != c ||
      oldDelegate.images != images ||
      oldDelegate.accent != accent ||
      oldDelegate.accentSecondary != accentSecondary ||
      oldDelegate.error != error;
}
