// Rendering of game.js build()/draw()/sprite()/aim()/drawTrail()/drawParts(), same world coordinates.
// ignore_for_file: non_constant_identifier_names
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/bm_data.dart';
import '../core/bm_engine.dart';
import 'bm_ball.dart';

class BmImages {
  ui.Image? field, goal, ball;
  final List<ui.Image?> team = <ui.Image?>[null, null];
  BmBallRenderer? ballR;
  // cached background (blurred cover + faded field), keyed by size/field
  ui.Image? bg;
  Size bgSize = Size.zero;
  int bgField = -1;
  double bgDpr = 1;

  void dispose() {
    field?.dispose();
    goal?.dispose();
    ball?.dispose();
    team[0]?.dispose();
    team[1]?.dispose();
    bg?.dispose();
    ballR?.dispose();
    field = goal = ball = bg = null;
    team[0] = team[1] = null;
    ballR = null;
  }
}

/// Screen mapping of game.js build(): world -> screen = world * s + (ox, oy).
class BmView {
  double s = 1, ox = 0, oy = 0;
  Size size = Size.zero;

  void layout(BmEngine e, Size sz) {
    size = sz;
    final BmFieldS f = e.field;
    final double W = sz.width, H = sz.height;
    if (W < 50 || H < 50) return;
    s = math.min(W / (f.R - f.L + 56 * FS), (H - 250) / ((f.B - f.T) + 2 * e.GGh + 48)) * 1.14 * 1.02;
    ox = W / 2 - e.CX * s;
    oy = H / 2 - e.CY * s;
  }

  Offset toWorld(Offset p) => Offset((p.dx - ox) / s, (p.dy - oy) / s);
}

Color _c(int argb, [double a = 1]) => Color(argb).withValues(alpha: (Color(argb).a * a).clamp(0.0, 1.0).toDouble());
Color _rgba(int r, int g, int b, double a) => Color.fromRGBO(r, g, b, a.clamp(0.0, 1.0).toDouble());

class BmPainter extends CustomPainter {
  BmPainter(this.e, this.im, this.view, this.now, this.dpr, this.fancy, {required Listenable repaint}) : super(repaint: repaint);

  final BmEngine e;
  final BmImages im;
  final BmView view;
  final double Function() now; // ms
  final double dpr;
  final bool fancy;

  @override
  void paint(Canvas canvas, Size size) {
    view.layout(e, size);
    _bg(canvas, size);
    if (e.bodies.isEmpty) return;
    final double t = now();
    final double s = view.s;
    final math.Random r = e.rnd;
    final double cs = e.cam * e.cam * 9, cx = fancy ? (r.nextDouble() - .5) * cs : 0, cy = fancy ? (r.nextDouble() - .5) * cs : 0;
    canvas.save();
    canvas.translate(view.ox + cx * s, view.oy + cy * s);
    canvas.scale(s);
    if (fancy) _drawTrail(canvas, t);
    if (e.phase == 'aim' && !e.menuOpen) {
      final double k = .5 + .5 * math.sin(t / 260);
      final List<int> c = e.turn != 0 ? <int>[255, 110, 110] : <int>[80, 170, 255];
      for (final BmBody b in e.bodies) {
        if (b.team == e.turn) {
          canvas.drawCircle(Offset(b.x, b.y), b.r + 11,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 13
                ..color = _rgba(c[0], c[1], c[2], .12 + .14 * k));
          canvas.drawCircle(Offset(b.x, b.y), b.r + 11,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 4
                ..color = _rgba(c[0], c[1], c[2], .5 + .5 * k));
        }
      }
    }
    if (fancy) _pieceTrails(canvas);
    // soft shadows (SPR.shadow)
    for (final BmBody b in e.bodies) {
      final double w = b.r * 2.6;
      final Offset c = Offset(b.x + 5, b.y + 11);
      canvas.drawCircle(
          c,
          w / 2,
          Paint()
            ..shader = ui.Gradient.radial(c, w / 2, <Color>[_rgba(0, 0, 0, .6), _rgba(0, 0, 0, .6), _rgba(0, 0, 0, 0)],
                <double>[0, .18, 1]));
    }
    for (final BmBody b in e.bodies) {
      if (b != e.ball) _sprite(canvas, b, t);
    }
    if (e.ball != null) _sprite(canvas, e.ball!, t);
    // goals (drawn over the ball: the net covers it)
    final ui.Image? gi = im.goal;
    if (gi != null) {
      for (final BmGoal g in e.GOALS) {
        final double gx = e.GGx + math.sin(t / 25) * 8 * e.shake[g.team];
        final double gy = g.d < 0 ? g.y - e.GGh - 2 : g.y + 2;
        final Rect dst = Rect.fromLTWH(gx, gy, e.GGw, e.GGh);
        final Rect src = Rect.fromLTWH(0, 0, gi.width.toDouble(), gi.height.toDouble());
        final Paint p = Paint()..filterQuality = FilterQuality.medium;
        if (g.d > 0) {
          canvas.save();
          canvas.translate(0, gy * 2 + e.GGh);
          canvas.scale(1, -1);
          canvas.drawImageRect(gi, src, dst, p);
          canvas.restore();
        } else {
          canvas.drawImageRect(gi, src, dst, p);
        }
      }
    }
    if (fancy) _drawParts(canvas);
    if (e.rings.isNotEmpty) {
      for (final BmRing rg in e.rings) {
        final double tt = 1 - rg.l / rg.m;
        canvas.drawCircle(
            Offset(rg.x, rg.y),
            rg.r * (1 + tt * 3.2 * (.6 + rg.w)),
            Paint()
              ..blendMode = BlendMode.plus
              ..style = PaintingStyle.stroke
              ..strokeWidth = 6 * (1 - tt) + 1
              ..color = _rgba(255, 255, 255, (1 - tt) * .8 * rg.w));
      }
    }
    _aim(canvas, t);
    canvas.restore();
    if (e.flash > 0) canvas.drawRect(Offset.zero & size, Paint()..color = _rgba(255, 230, 140, e.flash * .35));
  }

  // ------------------------------------------------------------ background (build())
  void _bg(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF03060D));
    final ui.Image? fi = im.field;
    if (fi == null) return;
    if (im.bg == null || im.bgSize != size || im.bgField != e.setFld || im.bgDpr != dpr) {
      im.bg?.dispose();
      final double d = dpr;
      final ui.PictureRecorder rec = ui.PictureRecorder();
      final Canvas b = Canvas(rec);
      b.scale(d);
      final BmFieldS f = e.field;
      final double W = size.width, H = size.height;
      b.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF03060D));
      final Rect src = Rect.fromLTWH(0, 0, fi.width.toDouble(), fi.height.toDouble());
      final double c = math.max(W / f.W, H / f.H);
      b.saveLayer(Offset.zero & size, Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: 8 / d * 1.0, sigmaY: 8 / d * 1.0));
      b.drawImageRect(fi, src, Rect.fromLTWH((W - f.W * c) / 2, (H - f.H * c) / 2, f.W * c, f.H * c),
          Paint()..filterQuality = FilterQuality.low);
      b.restore();
      b.drawRect(Offset.zero & size, Paint()..color = _rgba(0, 0, 0, .5));
      final Rect fr = Rect.fromLTWH(view.ox, view.oy, f.W * view.s, f.H * view.s);
      b.saveLayer(Offset.zero & size, Paint());
      b.drawImageRect(fi, src, fr, Paint()..filterQuality = FilterQuality.high);
      b.drawRect(
          Offset.zero & size,
          Paint()
            ..blendMode = BlendMode.dstIn
            ..shader = ui.Gradient.linear(Offset(0, fr.top), Offset(0, fr.bottom), const <Color>[
              Color(0x00000000),
              Color(0xFF000000),
              Color(0xFF000000),
              Color(0x00000000)
            ], const <double>[0, .07, .93, 1]));
      b.drawRect(
          Offset.zero & size,
          Paint()
            ..blendMode = BlendMode.dstIn
            ..shader = ui.Gradient.linear(Offset(fr.left, 0), Offset(fr.right, 0), const <Color>[
              Color(0x00000000),
              Color(0xFF000000),
              Color(0xFF000000),
              Color(0x00000000)
            ], const <double>[0, .04, .96, 1]));
      b.restore();
      final ui.Picture pic = rec.endRecording();
      im.bg = pic.toImageSync(math.max(1, (size.width * d).round()), math.max(1, (size.height * d).round()));
      pic.dispose();
      im.bgSize = size;
      im.bgField = e.setFld;
      im.bgDpr = dpr;
    }
    final ui.Image bg = im.bg!;
    canvas.drawImageRect(bg, Rect.fromLTWH(0, 0, bg.width.toDouble(), bg.height.toDouble()), Offset.zero & size, Paint());
  }

  // ------------------------------------------------------------ sprite()
  void _sprite(Canvas canvas, BmBody b, double t) {
    final bool isBall = b == e.ball;
    final ui.Image? sp = isBall ? im.ball : im.team[b.team == 0 ? 0 : 1];
    if (sp == null) {
      canvas.drawCircle(Offset(b.x, b.y), b.r, Paint()..color = isBall ? Colors.white : (b.team != 0 ? const Color(0xFFFF5B5B) : const Color(0xFF3B9BFF)));
      return;
    }
    final Rect src = Rect.fromLTWH(0, 0, sp.width.toDouble(), sp.height.toDouble());
    final Rect dst = Rect.fromLTWH(-b.r, -b.r, b.r * 2, b.r * 2);
    canvas.save();
    double drawY = b.y;
    if (isBall) {
      final double sv = math.sqrt(b.vx * b.vx + b.vy * b.vy), fast = math.min(1.0, sv / (1700 * K));
      final BmBallRenderer? br = im.ballR;
      if (br != null && br.ready) br.update(b.R, b.rv);
      // halo (SPR.h0 / SPR.h1)
      if (fancy) {
        final double R = b.r * (2.15 + fast * .5);
        final bool hot = fast > .55;
        final double ga = hot ? (.18 + .22 * fast) / .4 : 1;
        final Offset c = Offset(b.x, drawY);
        final Color c0 = hot ? _rgba(255, 170, 70, .4) : _rgba(80, 155, 255, .26);
        canvas.drawCircle(
            c,
            R,
            Paint()
              ..shader = ui.Gradient.radial(c, R, <Color>[
                c0.withValues(alpha: c0.a * ga.clamp(0.0, 1.0).toDouble()),
                c0.withValues(alpha: c0.a * ga.clamp(0.0, 1.0).toDouble()),
                _rgba(100, 130, 160, .15 * ga.clamp(0.0, 1.0).toDouble()),
                _rgba(40, 50, 65, 0)
              ], const <double>[0, .116, .4536, 1]));
      }
      final double so = b.r * (.55 + .25 * fast);
      canvas.drawOval(Rect.fromCenter(center: Offset(b.x + so * .35, b.y + so), width: b.r * .86 * 2, height: b.r * .34 * 2),
          Paint()..color = _rgba(8, 14, 24, .42 * .8));
      canvas.translate(b.x, b.y);
      if (sv > 40) {
        final double a = math.atan2(b.vy, b.vx), st = math.min(.16, fast * .12) + b.sq * .12, sq = b.sq * .1;
        canvas.rotate(a);
        canvas.scale(1 + st - sq, 1 - st * .55 + sq);
        canvas.rotate(-a);
      }
      final ui.Image? rendered = br?.image;
      if (rendered != null) {
        canvas.drawImageRect(rendered, Rect.fromLTWH(0, 0, rendered.width.toDouble(), rendered.height.toDouble()), dst,
            Paint()..filterQuality = FilterQuality.medium);
      } else {
        canvas.rotate(b.ang);
        canvas.drawImageRect(sp, src, dst, Paint()..filterQuality = FilterQuality.medium);
      }
      canvas.restore();
      return;
    }
    final double ph = b.cid * 1.7;
    drawY += math.sin(t / 1000 * 1.6 + ph) * 1.6 * (b.vx != 0 || b.vy != 0 ? 0 : 1);
    canvas.translate(b.x, drawY);
    final double sv = math.sqrt(b.vx * b.vx + b.vy * b.vy);
    if (sv > 60 || b.sq > .02) {
      final double a = math.atan2(b.vy, b.vx), st = math.min(.1, sv / (1800 * K) * .1) + b.sq * .1, sq = b.sq * .14;
      canvas.rotate(a);
      canvas.scale(1 + st - sq, 1 - st * .6 + sq);
      canvas.rotate(-a);
    }
    final Paint dark = Paint()
      ..filterQuality = FilterQuality.medium
      ..colorFilter = const ColorFilter.mode(Color.fromRGBO(6, 8, 24, .66), BlendMode.srcATop);
    for (int k = 4; k >= 1; k--) {
      canvas.drawImageRect(sp, src, dst.shift(Offset(0, b.r * .052 * k)), dark);
    }
    canvas.drawImageRect(sp, src, dst, Paint()..filterQuality = FilterQuality.medium);
    canvas.restore();
  }

  // ------------------------------------------------------------ piece trails
  void _pieceTrails(Canvas canvas) {
    for (final BmBody b in e.bodies) {
      if (b == e.ball || b.tr.length < 3) continue;
      final List<BmTrailPt> T = b.tr;
      final int n = T.length;
      final List<int> rgb = b.team != 0 ? <int>[255, 90, 90] : <int>[70, 160, 255];
      final double q = math.min(1.0, T[n - 1].v / (1500 * K));
      for (int i = 1; i < n; i++) {
        final double f = i / n;
        canvas.drawLine(
            Offset(T[i - 1].x, T[i - 1].y),
            Offset(T[i].x, T[i].y),
            Paint()
              ..blendMode = BlendMode.plus
              ..strokeCap = StrokeCap.round
              ..strokeWidth = b.r * 1.7 * f
              ..color = _rgba(rgb[0], rgb[1], rgb[2], f * .5 * (.4 + .6 * q)));
      }
      for (int i = 1; i < n; i++) {
        final double f = i / n;
        canvas.drawLine(
            Offset(T[i - 1].x, T[i - 1].y),
            Offset(T[i].x, T[i].y),
            Paint()
              ..blendMode = BlendMode.plus
              ..strokeCap = StrokeCap.round
              ..strokeWidth = b.r * .35 * f
              ..color = _rgba(255, 255, 255, f * .35 * q));
      }
    }
  }

  // ------------------------------------------------------------ drawParts()
  void _drawParts(Canvas canvas) {
    if (e.parts.isEmpty) return;
    for (final BmPart p in e.parts) {
      final double a = math.max(0, p.l / p.m);
      final Color col = _c(p.c, a);
      final double r = p.r * (p.k == 4 ? 1 : (.5 + .5 * a));
      final Paint paint = Paint()
        ..blendMode = BlendMode.plus
        ..color = col;
      switch (p.k) {
        case 1:
          canvas.save();
          canvas.translate(p.x, p.y);
          canvas.rotate(p.rot);
          final double q = r * 1.8;
          final Path path = Path()
            ..moveTo(0, -q)
            ..quadraticBezierTo(0, 0, q, 0)
            ..quadraticBezierTo(0, 0, 0, q)
            ..quadraticBezierTo(0, 0, -q, 0)
            ..quadraticBezierTo(0, 0, 0, -q);
          canvas.drawPath(path, paint);
          canvas.restore();
          break;
        case 2:
          canvas.save();
          canvas.translate(p.x, p.y);
          canvas.rotate(p.rot);
          canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: r * 3, height: r * 1.4), paint);
          canvas.restore();
          break;
        case 3:
          canvas.save();
          canvas.translate(p.x, p.y);
          canvas.rotate(p.rot);
          canvas.drawRect(Rect.fromLTWH(-r, -r, r * 2, r * 2), paint);
          canvas.restore();
          break;
        case 4:
          paint
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.8;
          canvas.drawCircle(Offset(p.x, p.y), math.max(0.01, r * (1.4 - a * .4)), paint);
          break;
        case 5:
          final double l0 = math.sqrt(p.vx * p.vx + p.vy * p.vy), l = l0 == 0 ? 1 : l0, k = math.min(26.0, l * .07);
          paint
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1.0, r * .8)
            ..strokeCap = StrokeCap.round;
          canvas.drawLine(Offset(p.x, p.y), Offset(p.x - p.vx / l * k, p.y - p.vy / l * k), paint);
          break;
        default:
          canvas.drawCircle(Offset(p.x, p.y), math.max(0.01, r), paint);
      }
    }
  }

  // ------------------------------------------------------------ drawTrail()
  void _drawTrail(Canvas canvas, double now) {
    final List<BmTrailPt> trail = e.trail;
    final int n = trail.length;
    if (n < 2) return;
    final BmTrail st = kBmTR[e.setBall % kBmTR.length];
    final List<int> c = st.c;
    const double BW = BR;
    final BmFa fa = kBmFA[e.field.id] ?? kBmFA['stadium']!;
    void seg(int i, double w, double al, int col, [double ox = 0, double oy = 0, BlendMode bm = BlendMode.plus]) {
      final BmTrailPt p = trail[i - 1], q = trail[i];
      final double ga = math.max(0, math.min(1.0, al * q.a));
      canvas.drawLine(
          Offset(p.x + ox, p.y + oy),
          Offset(q.x + ox, q.y + oy),
          Paint()
            ..blendMode = bm
            ..strokeCap = StrokeCap.round
            ..strokeWidth = math.max(.6, w * q.a)
            ..color = _c(col, ga));
    }

    List<double> nrm(int i) {
      final BmTrailPt p = trail[math.max(0, i - 1)], q = trail[math.min(n - 1, i)];
      final double dx = q.x - p.x, dy = q.y - p.y;
      double l = math.sqrt(dx * dx + dy * dy);
      if (l == 0) l = 1;
      return <double>[-dy / l, dx / l];
    }

    void base(double w0, double a0) {
      for (int i = 1; i < n; i++) {
        seg(i, BW * 2.2 * w0, .14 * a0, c[0]);
        seg(i, BW * 1.1 * w0, .42 * a0, c[1]);
        seg(i, BW * .4 * w0, .95 * a0, c.length > 2 ? c[2] : 0xFFFFFFFF);
      }
    }

    int hsl(double h, double l) => bmHsl(h, l);
    switch (st.k) {
      case 'bolt':
        base(.55, .8);
        for (final List<Object> wc in <List<Object>>[
          <Object>[4.2, c[1], .55],
          <Object>[1.7, c[2], .95]
        ]) {
          final double w = wc[0] as double;
          final Path path = Path();
          int m = 0;
          for (int i = 0; i < n; i++) {
            final BmTrailPt q = trail[i];
            if (q.a < .12) continue;
            final List<double> nn = nrm(i);
            final double a = (math.sin(i * 91.7 + now * .07 + w) * BW * 1.1) * q.a;
            if (m++ == 0) {
              path.moveTo(q.x + nn[0] * a, q.y + nn[1] * a);
            } else {
              path.lineTo(q.x + nn[0] * a, q.y + nn[1] * a);
            }
          }
          canvas.drawPath(
              path,
              Paint()
                ..blendMode = BlendMode.plus
                ..style = PaintingStyle.stroke
                ..strokeJoin = StrokeJoin.round
                ..strokeCap = StrokeCap.round
                ..strokeWidth = w
                ..color = _c(wc[1] as int, wc[2] as double));
        }
        break;
      case 'prism':
        for (int i = 1; i < n; i++) {
          seg(i, BW * 1.9, .4, hsl(i * 14 + now * .25, 58));
          seg(i, BW * .9, .7, hsl(i * 14 + now * .25 + 40, 70));
          seg(i, BW * .32, .95, 0xFFFFFFFF);
        }
        break;
      case 'wave':
        base(.4, .7);
        for (int i = 1; i < n; i++) {
          final List<double> nn = nrm(i);
          final double o = math.sin(i * .55 + now * .02) * BW * 1.0 * trail[i].a;
          seg(i, BW * .55, .85, c[0], nn[0] * o, nn[1] * o);
          seg(i, BW * .55, .85, c[1], -nn[0] * o, -nn[1] * o);
        }
        break;
      case 'star':
        base(.7, .9);
        break;
      case 'smoke':
        for (int i = 0; i < n; i += 2) {
          final BmTrailPt q = trail[i];
          final double g = 1 - q.a;
          canvas.drawCircle(Offset(q.x + math.sin(i * 3.1) * g * 14, q.y + math.cos(i * 2.7) * g * 14), BW * (.9 + g * 2.4),
              Paint()..color = _c(c[1], q.a * .2));
        }
        for (int i = 1; i < n; i++) {
          seg(i, BW * .45, .7, c[2]);
        }
        break;
      case 'rainbow':
        for (int b = 0; b < 6; b++) {
          for (int i = 1; i < n; i++) {
            final List<double> nn = nrm(i);
            final double o = (b - 2.5) * BW * .34 * trail[i].a;
            seg(i, BW * .42, .8, hsl(b * 60.0, 60), nn[0] * o, nn[1] * o);
          }
        }
        break;
      case 'neon':
        for (int i = 1; i < n; i++) {
          seg(i, BW * 1.9, .2, c[0]);
          seg(i, BW * .75, .9, c[1]);
          seg(i, BW * .24, 1, c[2]);
        }
        break;
      case 'yin':
        for (int i = 1; i < n; i++) {
          final List<double> nn = nrm(i);
          final double o = math.sin(i * .42 + now * .016) * BW * .85 * trail[i].a;
          seg(i, BW * .7, .9, c[0], nn[0] * o, nn[1] * o);
          seg(i, BW * .7, .85, c[1], -nn[0] * o, -nn[1] * o);
          seg(i, BW * 1.8, .1, c[1]);
        }
        break;
      case 'fire':
        for (int i = 1; i < n; i++) {
          seg(i, BW * 2.2, .22, c[0]);
          seg(i, BW * 1.2, .55, c[1]);
          seg(i, BW * .45, .95, c[2]);
        }
        break;
      case 'blade':
        final Path path = Path();
        final List<Offset> R = <Offset>[];
        for (int i = 0; i < n; i++) {
          final List<double> nn = nrm(i);
          final double w = BW * 1.5 * math.pow(i / (n - 1), 1.3).toDouble() * trail[i].a;
          if (i == 0) {
            path.moveTo(trail[i].x + nn[0] * w, trail[i].y + nn[1] * w);
          } else {
            path.lineTo(trail[i].x + nn[0] * w, trail[i].y + nn[1] * w);
          }
          R.add(Offset(trail[i].x - nn[0] * w, trail[i].y - nn[1] * w));
        }
        for (int i = n - 1; i >= 0; i--) {
          path.lineTo(R[i].dx, R[i].dy);
        }
        path.close();
        canvas.drawPath(
            path,
            Paint()
              ..blendMode = BlendMode.plus
              ..color = _c(c[0], .75));
        for (int i = 1; i < n; i++) {
          seg(i, BW * .3, .95, c[2]);
        }
        break;
      case 'ghost':
        for (int i = 1; i < n; i++) {
          seg(i, BW * .5, .5, c[1]);
        }
        for (int i = 0; i < n; i += 4) {
          final BmTrailPt q = trail[i];
          final double rr = BR * (.6 + .4 * q.a);
          canvas.drawCircle(
              Offset(q.x, q.y),
              rr,
              Paint()
                ..blendMode = BlendMode.plus
                ..style = PaintingStyle.stroke
                ..strokeWidth = 3
                ..color = _c(c[1], q.a * .4));
          canvas.drawCircle(
              Offset(q.x, q.y),
              rr,
              Paint()
                ..blendMode = BlendMode.plus
                ..color = _c(c[0], q.a * .08));
        }
        break;
      case 'ember':
        for (int i = 1; i < n; i++) {
          seg(i, BW * 1.2, .2, c[0]);
          seg(i, BW * .55, .6, c[1]);
          seg(i, BW * .2, 1, c[2]);
        }
        break;
      case 'plasma':
        for (int i = 1; i < n; i++) {
          final double k = 1 + .3 * math.sin(now * .03 + i * .35);
          final List<double> nn = nrm(i);
          final double o = math.sin(i * .5 - now * .025) * BW * .5 * trail[i].a;
          seg(i, BW * 2.8 * k, .2, c[0]);
          seg(i, BW * 1.4 * k, .5, c[1]);
          seg(i, BW * .45, 1, c[2]);
          seg(i, BW * .3, .7, c[1], nn[0] * o, nn[1] * o);
        }
        break;
    }
    for (int i = 1; i < n; i++) {
      seg(i, BW * .8, .2, fa.c[0]);
    }
    final BmTrailPt last = trail[n - 1];
    final BmBody? ball = e.ball;
    if (ball != null && last.v > 1800 * K) {
      final double ux = ball.vx / last.v, uy = ball.vy / last.v;
      for (int k = -1; k <= 1; k++) {
        canvas.drawLine(
            Offset(ball.x - ux * BR * 1.4 - uy * k * BR * .9, ball.y - uy * BR * 1.4 + ux * k * BR * .9),
            Offset(ball.x - ux * BR * 7 - uy * k * BR * .9, ball.y - uy * BR * 7 + ux * k * BR * .9),
            Paint()
              ..blendMode = BlendMode.plus
              ..strokeWidth = 2
              ..color = _c(c[1], .35));
      }
    }
  }

  // ------------------------------------------------------------ aim()
  void _aim(Canvas canvas, double now) {
    final BmDrag? d = e.drag;
    if (d == null) return;
    final BmBody b = d.b;
    final double dx = d.sx - d.cx, dy = d.sy - d.cy, l = math.sqrt(dx * dx + dy * dy);
    if (l < 18) return;
    final double p = math.min(l, LMAX) / LMAX, ux = dx / l, uy = dy / l;
    double t = 1200;
    for (final BmBody o in e.bodies) {
      if (o == b) continue;
      final double R = b.r + o.r, qx = o.x - b.x, qy = o.y - b.y, u = qx * ux + qy * uy;
      if (u <= 0) continue;
      final double D = u * u - (qx * qx + qy * qy - R * R);
      if (D >= 0) {
        final double h = u - math.sqrt(D);
        if (h > 0 && h < t) t = h;
      }
    }
    if (ux < 0) t = math.min(t, (e.Fl + b.r - b.x) / ux);
    if (ux > 0) t = math.min(t, (e.Fr - b.r - b.x) / ux);
    if (uy < 0) t = math.min(t, (e.Ft + b.r - b.y) / uy);
    if (uy > 0) t = math.min(t, (e.Fb - b.r - b.y) / uy);
    t = math.max(t, 0);
    final double hue = 135 - 135 * p;
    final Color col = Color(bmHslColor(hue, .95, .58)), col2 = Color(bmHslColor((hue + 35) % 360, 1, .76));
    final double sx = b.x + ux * b.r, sy = b.y + uy * b.r, ex = b.x + ux * t, ey = b.y + uy * t;
    final List<int> tm = b.team != 0 ? <int>[255, 110, 110] : <int>[90, 175, 255];
    // drag band (dashed)
    final Offset p0 = Offset(d.sx, d.sy), pc = Offset(d.cx, d.cy);
    _dashed(canvas, p0, pc, 2, 9,
        Paint()
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..color = _rgba(tm[0], tm[1], tm[2], .35));
    canvas.drawCircle(pc, 9 + p * 4, Paint()..color = _rgba(tm[0], tm[1], tm[2], .55));
    canvas.drawCircle(
        pc,
        9 + p * 4,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white);
    // prediction line
    final Offset s0 = Offset(sx, sy), e0 = Offset(ex, ey);
    final ui.Gradient g = ui.Gradient.linear(s0, e0 == s0 ? s0 + const Offset(0, 1) : e0, <Color>[col, _rgba(255, 255, 255, .2)]);
    _gline(canvas, s0, e0, g, 16, .16);
    _gline(canvas, s0, e0, g, 3, .85);
    // moving chevrons
    const double step = 44;
    final double off = (now / 12) % step;
    for (double dd = b.r + 14 + off; dd < t - b.r * .5; dd += step) {
      final double x = b.x + ux * dd, y = b.y + uy * dd, a = math.max(0, 1 - dd / t * .75);
      final Path ch = Path()
        ..moveTo(x - uy * 9 - ux * 8, y + ux * 9 - uy * 8)
        ..lineTo(x + ux * 5, y + uy * 5)
        ..lineTo(x + uy * 9 - ux * 8, y - ux * 9 - uy * 8);
      canvas.drawPath(
          ch,
          Paint()
            ..blendMode = BlendMode.plus
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..strokeWidth = 4
            ..color = col2.withValues(alpha: a.clamp(0.0, 1.0).toDouble()));
    }
    // wall bounce preview
    {
      double rx = ux, ry = uy;
      bool hit = false;
      const double eps = 2;
      if (ex <= e.Fl + b.r + eps && ux < 0) {
        rx = -ux;
        hit = true;
      } else if (ex >= e.Fr - b.r - eps && ux > 0) {
        rx = -ux;
        hit = true;
      } else if (ey <= e.Ft + b.r + eps && uy < 0) {
        ry = -uy;
        hit = true;
      } else if (ey >= e.Fb - b.r - eps && uy > 0) {
        ry = -uy;
        hit = true;
      }
      if (hit) {
        final Offset a = Offset(ex, ey), z = Offset(ex + rx * 170, ey + ry * 170);
        _dashed(
            canvas,
            a,
            z,
            8,
            10,
            Paint()
              ..blendMode = BlendMode.plus
              ..strokeWidth = 3
              ..strokeCap = StrokeCap.round
              ..shader = ui.Gradient.linear(a, z, <Color>[_rgba(255, 255, 255, .55), _rgba(255, 255, 255, 0)]),
            phase: (now / 30) % 18);
      }
    }
    // impact point: pulsing ring + sight ticks
    {
      final double pu = .5 + .5 * math.sin(now / 140), R = b.r * (1 + .12 * pu);
      canvas.drawCircle(
          e0,
          R,
          Paint()
            ..blendMode = BlendMode.plus
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.5
            ..color = col2.withValues(alpha: .9));
      for (int k = 0; k < 4; k++) {
        final double a = k * 1.5708 + now / 700, ca = math.cos(a), sa = math.sin(a);
        canvas.drawLine(
            Offset(ex + ca * (R + 4), ey + sa * (R + 4)),
            Offset(ex + ca * (R + 13), ey + sa * (R + 13)),
            Paint()
              ..blendMode = BlendMode.plus
              ..strokeWidth = 2.5
              ..strokeCap = StrokeCap.round
              ..color = col2.withValues(alpha: (.5 + .4 * pu).clamp(0.0, 1.0).toDouble()));
      }
      canvas.drawCircle(
          e0,
          R * .55,
          Paint()
            ..blendMode = BlendMode.plus
            ..color = col.withValues(alpha: .25));
    }
    // power ring: 30 segments
    {
      const int N = 30;
      final double r1 = b.r + 20;
      for (int k = 0; k < N; k++) {
        final double a0 = -1.5708 + k / N * 6.2832 + .03;
        final bool lit = k / N < p;
        canvas.drawArc(
            Rect.fromCircle(center: Offset(b.x, b.y), radius: r1),
            a0,
            6.2832 / N - .07,
            false,
            Paint()
              ..blendMode = BlendMode.plus
              ..style = PaintingStyle.stroke
              ..strokeWidth = 4
              ..color = lit ? Color(bmHslColor(135 - 135 * (k / N), .95, .58)) : _rgba(255, 255, 255, .18));
      }
    }
    // main neon arrow
    {
      final double base = b.r + 30, Lh = 34 + p * 92, hl = 24 + p * 16, sw = 3.5 + p * 5, hw = 14 + p * 9;
      final double tipx = b.x + ux * (base + Lh), tipy = b.y + uy * (base + Lh), nx = -uy, ny = ux;
      final double bx = b.x + ux * base, by = b.y + uy * base, jx = b.x + ux * (base + Lh - hl), jy = b.y + uy * (base + Lh - hl);
      final Path arrow = Path()
        ..moveTo(bx + nx * sw * .3, by + ny * sw * .3)
        ..lineTo(jx + nx * sw, jy + ny * sw)
        ..lineTo(jx + nx * hw, jy + ny * hw)
        ..lineTo(tipx, tipy)
        ..lineTo(jx - nx * hw, jy - ny * hw)
        ..lineTo(jx - nx * sw, jy - ny * sw)
        ..lineTo(bx - nx * sw * .3, by - ny * sw * .3)
        ..close();
      final ui.Gradient fg = ui.Gradient.linear(Offset(bx, by), Offset(tipx, tipy), <Color>[_rgba(255, 255, 255, .15), col, Colors.white], <double>[0, .55, 1]);
      canvas.drawPath(
          arrow,
          Paint()
            ..blendMode = BlendMode.plus
            ..color = col
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 11));
      canvas.drawPath(
          arrow,
          Paint()
            ..blendMode = BlendMode.plus
            ..shader = fg);
      canvas.drawPath(
          arrow,
          Paint()
            ..blendMode = BlendMode.plus
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.8
            ..color = _rgba(255, 255, 255, .9));
      final int nCh = 1 + (p > .35 ? 1 : 0) + (p > .7 ? 1 : 0);
      for (int k = 1; k <= nCh; k++) {
        final double dd = base - k * 13, x = b.x + ux * dd, y = b.y + uy * dd;
        final Path ch = Path()
          ..moveTo(x - uy * (10 + p * 5) - ux * 7, y + ux * (10 + p * 5) - uy * 7)
          ..lineTo(x + ux * 2, y + uy * 2)
          ..lineTo(x + uy * (10 + p * 5) - ux * 7, y - ux * (10 + p * 5) - uy * 7);
        canvas.drawPath(
            ch,
            Paint()
              ..blendMode = BlendMode.plus
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3.5
              ..strokeCap = StrokeCap.round
              ..strokeJoin = StrokeJoin.round
              ..color = col2.withValues(alpha: .75 / k));
      }
      // power percent
      final TextPainter tp = TextPainter(
        text: TextSpan(
          text: '${(p * 100).round()}%',
          style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w900,
              shadows: <Shadow>[Shadow(color: col, blurRadius: 10)]),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final double tx = b.x - ux * (b.r + 44), ty = b.y - uy * (b.r + 44) - (uy > .5 ? -4 : 0);
      tp.paint(canvas, Offset(tx - tp.width / 2, ty - tp.height / 2));
    }
  }

  void _gline(Canvas canvas, Offset a, Offset b, ui.Gradient g, double w, double alpha) {
    canvas.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, alpha));
    canvas.drawLine(
        a,
        b,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = g
          ..strokeCap = StrokeCap.round
          ..strokeWidth = w);
    canvas.restore();
  }

  void _dashed(Canvas canvas, Offset a, Offset b, double on, double off, Paint p, {double phase = 0}) {
    final Offset d = b - a;
    final double len = d.distance;
    if (len <= 0) return;
    final Offset u = d / len;
    double pos = -phase;
    while (pos < len) {
      final double s0 = math.max(0, pos), s1 = math.min(len, pos + on);
      if (s1 > s0) canvas.drawLine(a + u * s0, a + u * s1, p);
      pos += on + off;
    }
  }

  @override
  bool shouldRepaint(covariant BmPainter oldDelegate) => true;
}
