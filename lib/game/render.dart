// Match renderer: port of src/game/render.ts on Flutter's Canvas (Impeller), hosted by Flame (game.dart).
//
// Frame cost is kept flat and allocation-free:
//  * the stadium background, the feathered field and the outline are baked ONCE into a single image;
//  * discs, gloss, shadows and particles are drawn from one pre-baked sprite atlas with drawRawAtlas
//    (SpriteBatch-style: 1 draw call for all shadows, 1 for all discs, 1 for gloss, 1 for particles)
//    using pre-allocated Float32List/Int32List buffers;
//  * the static goal nets are cached as Pictures and only rebuilt while a goal ripple/shake plays;
//  * the ball is a FragmentShader (shaders/ball.frag) sampling the ball texture;
//  * every Paint is a long-lived field.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

import 'data.dart';
import 'engine.dart';

class MatchView {
  final double W, H, s, ox, oy;
  final bool flipped;
  const MatchView(this.W, this.H, this.s, this.ox, this.oy, {this.flipped = false});
  Offset toWorld(double x, double y) {
    if (flipped) {
      x = W - x;
      y = H - y;
    }
    return Offset((x - ox) / s, (y - oy) / s);
  }
}

MatchView computeView(Engine e, double W, double H, double top, double bottom, {bool flipped = false}) {
  final f = e.f;
  const fs = 1.12;
  final playH = math.max(300.0, H - top - bottom);
  final s = math.min(W / (f.R - f.L + 56 * fs), playH / ((f.B - f.T) + 2 * e.GGh + 48)) * .99;
  return MatchView(W, H, s, W / 2 - e.CX * s, top + playH / 2 - e.CY * s, flipped: flipped);
}

Future<ui.Image> loadImage(String path, {int? width}) async {
  final data = await rootBundle.load(path);
  final codec = await ui.instantiateImageCodec(data.buffer.asUint8List(), targetWidth: width);
  final fr = await codec.getNextFrame();
  return fr.image;
}

/// Classic white/black soccer ball drawn with Canvas: used when the ball texture fails to load.
Future<ui.Image> proceduralBall([int size = 256]) {
  final rec = ui.PictureRecorder();
  final c = ui.Canvas(rec);
  final R = size / 2, o = ui.Offset(R, R);
  c.drawCircle(o, R, ui.Paint()..color = const ui.Color(0xfff7f8fa));
  final blk = ui.Paint()..color = const ui.Color(0xff15171c);
  final seam = ui.Paint()
    ..style = ui.PaintingStyle.stroke
    ..strokeWidth = size * .018
    ..color = const ui.Color(0xff2a2d33);
  ui.Path pent(ui.Offset ctr, double rad, double rot) {
    final p = ui.Path();
    for (var k = 0; k < 5; k++) {
      final a = rot + k * 2 * math.pi / 5 - math.pi / 2;
      final pt = ctr + ui.Offset(math.cos(a), math.sin(a)) * rad;
      k == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
    }
    return p..close();
  }

  c.drawPath(pent(o, R * .3, 0), blk);
  for (var k = 0; k < 5; k++) {
    final a = k * 2 * math.pi / 5 - math.pi / 2;
    final inner = o + ui.Offset(math.cos(a), math.sin(a)) * R * .3;
    final outer = o + ui.Offset(math.cos(a), math.sin(a)) * R * .82;
    c.drawLine(inner, outer, seam);
    c.drawPath(pent(o + ui.Offset(math.cos(a + math.pi / 5), math.sin(a + math.pi / 5)) * R * .9, R * .26, a + math.pi / 5 + math.pi), blk);
  }
  return rec.endRecording().toImage(size, size);
}

class MatchImages {
  final ui.Image field, ball, t0, t1;
  final ui.Image? headE, headS, shaftE, shaftS;
  MatchImages(this.field, this.ball, this.t0, this.t1, this.headE, this.headS, this.shaftE, this.shaftS);
  bool get hasArrow => headE != null && headS != null && shaftE != null && shaftS != null;
}

const _teamGlow = [ui.Color(0xff3bb6ff), ui.Color(0xffff5b6b)];
const double _aimMaxK = 4.0; // Godot AIM_MAX_K: arrow length beyond the rim at full power, in disc radii
const double _aimMinK = .35; // Godot AIM_MIN_K: ... at the lowest power (short stub)
const _aimC = [ui.Color(0xff3b8bff), ui.Color(0xff9b5cff), ui.Color(0xffff3b5c)];

class _ArtK {
  final double hh, join, sw, top, tail, topLen, tailLen;
  const _ArtK(this.hh, this.join, this.sw, this.top, this.tail, this.topLen, this.tailLen);
}

const _artE = _ArtK(96, .82, 124, 0, .734, 0, 46);
const _artS = _ArtK(68, .928, 32.5, 0, .704, 0, 38);

double _sstep(double a, double b, double v) {
  final k = ((v - a) / (b - a)).clamp(0.0, 1.0);
  return k * k * (3 - 2 * k);
}

class MatchRenderer {
  final Engine e;
  final MatchImages im;
  final int ballIdx;
  final bool hq;
  MatchView v;
  final double dpr;
  ui.FragmentShader? ballShader;

  // sprite atlas: [0] disc team0, [1] disc team1, [2] gloss, [3] shadow, [4] particle dot
  static const int spr = 192;
  late ui.Image atlas;
  ui.Image? bg;
  final List<ui.Picture?> _nets = [null, null];
  final math.Random _fxRand = math.Random();

  // pre-allocated atlas buffers (up to 12 bodies, 640 particles)
  final Float32List _xf = Float32List(4 * 32), _rc = Float32List(4 * 32);
  final Float32List _pxf = Float32List(4 * Engine.maxParts), _prc = Float32List(4 * Engine.maxParts);
  final Int32List _pcol = Int32List(Engine.maxParts);
  final Int32List _dcol = Int32List(32);

  final ui.Paint _atlasP = ui.Paint()..filterQuality = ui.FilterQuality.medium;
  final ui.Paint _addP = ui.Paint()..blendMode = ui.BlendMode.plus;
  final ui.Paint _shadowP = ui.Paint()
    ..filterQuality = ui.FilterQuality.low
    ..color = const ui.Color(0x80ffffff);
  final ui.Paint _stroke = ui.Paint()
    ..style = ui.PaintingStyle.stroke
    ..strokeCap = ui.StrokeCap.round
    ..isAntiAlias = true;
  final ui.Paint _fill = ui.Paint()..isAntiAlias = true;
  final ui.Paint _img = ui.Paint()..filterQuality = ui.FilterQuality.medium;
  final ui.Paint _ballP = ui.Paint();
  final ui.Paint _art = ui.Paint()..filterQuality = ui.FilterQuality.medium;
  final ui.Paint _artGlow = ui.Paint()
    ..filterQuality = ui.FilterQuality.medium
    ..blendMode = ui.BlendMode.plus;
  final ui.Paint _netP = ui.Paint()
    ..style = ui.PaintingStyle.stroke
    ..strokeCap = ui.StrokeCap.round
    ..isAntiAlias = true;
  final ui.Paint _bar = ui.Paint()
    ..style = ui.PaintingStyle.stroke
    ..strokeCap = ui.StrokeCap.round;
  final ui.Path _path = ui.Path();

  // aim smoothing (render.ts aimS)
  bool _aimOn = false;
  double _aux = 0, _auy = -1, _ap = 0;

  // cached exact-length views over the pre-allocated buffers (no per-frame allocation)
  final Map<int, Float32List> _fviews = {};
  final Map<int, Int32List> _iviews = {};
  Float32List _vf(Float32List b, int n) => _fviews[identityHashCode(b) * 4096 + n] ??= b.buffer.asFloat32List(0, n);
  Int32List _vi(Int32List b, int n) => _iviews[identityHashCode(b) * 4096 + n] ??= b.buffer.asInt32List(0, n);

  MatchRenderer(this.e, this.im, this.ballIdx, this.v, {required this.dpr, this.hq = true, this.ballShader});

  Future<void> prepare() async {
    atlas = await _bakeAtlas();
    bg = await _bakeStatic();
  }

  void resize(MatchView nv) async {
    v = nv;
    bg = await _bakeStatic();
  }

  Future<ui.Image> _bakeAtlas() async {
    final rec = ui.PictureRecorder();
    final c = ui.Canvas(rec);
    const R = spr / 2.0, r = R - 2;
    for (var t = 0; t < 2; t++) {
      final logo = t == 0 ? im.t0 : im.t1;
      final ox = t * spr.toDouble();
      c.save();
      c.clipRRect(ui.RRect.fromRectAndRadius(ui.Rect.fromLTWH(ox + R - r, R - r, 2 * r, 2 * r), const ui.Radius.circular(r)));
      c.drawImageRect(logo, ui.Rect.fromLTWH(0, 0, logo.width.toDouble(), logo.height.toDouble()), ui.Rect.fromLTWH(ox + R - r, R - r, 2 * r, 2 * r), _img);
      c.restore();
    }
    // gloss
    {
      const ox = 2.0 * spr;
      final gl = ui.Paint()
        ..shader = ui.Gradient.radial(ui.Offset(ox + R - r * .38, R - r * .48), r * .9, const [ui.Color(0x42ffffff), ui.Color(0x0dffffff), ui.Color(0x00ffffff)], const [0, .45, 1]);
      c.drawCircle(const ui.Offset(ox + R, R), r * .97, gl);
      final sp = ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeCap = ui.StrokeCap.round
        ..strokeWidth = 3
        ..color = const ui.Color(0x61ffffff);
      c.drawArc(ui.Rect.fromLTWH(ox + R - r * .93, R - r * .93, r * 1.86, r * 1.86), 205 * math.pi / 180, 60 * math.pi / 180, false, sp);
    }
    // shadow
    {
      const ox = 3.0 * spr;
      final p = ui.Paint()..shader = ui.Gradient.radial(const ui.Offset(ox + R, R), R, const [ui.Color(0xff000000), ui.Color(0x80000000), ui.Color(0x00000000)], const [0, .55, 1]);
      c.drawCircle(const ui.Offset(ox + R, R), R, p);
    }
    // particle dot (soft white)
    {
      const ox = 4.0 * spr;
      final p = ui.Paint()..shader = ui.Gradient.radial(const ui.Offset(ox + R, R), R, const [ui.Color(0xffffffff), ui.Color(0xccffffff), ui.Color(0x00ffffff)], const [0, .5, 1]);
      c.drawCircle(const ui.Offset(ox + R, R), R, p);
    }
    return rec.endRecording().toImage(spr * 5, spr);
  }

  /// Background + feathered field + neon outline, baked once per view size.
  Future<ui.Image> _bakeStatic() async {
    final w = (v.W * dpr).round(), h = (v.H * dpr).round();
    final rec = ui.PictureRecorder();
    final c = ui.Canvas(rec);
    c.scale(dpr);
    final f = e.f, fld = im.field;
    c.drawRect(ui.Rect.fromLTWH(0, 0, v.W, v.H), ui.Paint()..color = const ui.Color(0xff02040c));
    final k = math.max(v.W / f.W, v.H / f.H) * 1.05;
    final src = ui.Rect.fromLTWH(0, 0, fld.width.toDouble(), fld.height.toDouble());
    // blurred, darkened stadium fill (blur costs nothing per frame: it is baked)
    c.drawImageRect(fld, src, ui.Rect.fromLTWH((v.W - f.W * k) / 2, (v.H - f.H * k) / 2, f.W * k, f.H * k),
        ui.Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14, tileMode: ui.TileMode.clamp));
    c.drawRect(ui.Rect.fromLTWH(0, 0, v.W, v.H), ui.Paint()..color = const ui.Color(0x9e02040e));
    c.save();
    if (v.flipped) {
      c.translate(v.W, v.H);
      c.rotate(math.pi);
    }
    c.translate(v.ox, v.oy);
    c.scale(v.s);
    final fr = ui.Rect.fromLTWH(0, 0, f.W.toDouble(), f.H.toDouble());
    c.saveLayer(fr.inflate(40), ui.Paint());
    c.drawImageRect(fld, src, fr, ui.Paint()..filterQuality = ui.FilterQuality.medium);
    final m = ui.Paint()..blendMode = ui.BlendMode.dstIn;
    m.shader = ui.Gradient.linear(ui.Offset.zero, ui.Offset(0, f.H.toDouble()), const [ui.Color(0x00000000), ui.Color(0xff000000), ui.Color(0xff000000), ui.Color(0x00000000)], const [0, .06, .94, 1]);
    c.drawRect(fr, m);
    m.shader = ui.Gradient.linear(ui.Offset.zero, ui.Offset(f.W.toDouble(), 0), const [ui.Color(0x00000000), ui.Color(0xff000000), ui.Color(0xff000000), ui.Color(0x00000000)], const [0, .05, .95, 1]);
    c.drawRect(fr, m);
    c.restore();
    final o = ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = const ui.Color(0x5978dcff)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 4);
    c.drawRRect(ui.RRect.fromRectAndRadius(ui.Rect.fromLTRB(e.Fl, e.Ft, e.Fr, e.Fb), const ui.Radius.circular(70)), o);
    c.restore();
    _nets[0] = null;
    _nets[1] = null;
    return rec.endRecording().toImage(w, h);
  }

  // ---------------- frame ----------------
  void render(ui.Canvas c, double t) {
    if (bg != null) {
      c.save();
      c.scale(1 / dpr);
      c.drawImage(bg!, ui.Offset.zero, _img);
      c.restore();
    }
    final cam = e.cam;
    final shx = cam > .05 && hq ? (_fxRand.nextDouble() - .5) * cam * 7 : 0.0;
    final shy = cam > .05 && hq ? (_fxRand.nextDouble() - .5) * cam * 7 : 0.0;
    c.save();
    if (v.flipped) {
      c.translate(v.W, v.H);
      c.rotate(math.pi);
    }
    c.translate(v.ox + shx, v.oy + shy);
    c.scale(v.s);
    final al = e.alpha();
    _drawNets(c, t);
    _drawBodies(c, t, al);
    _drawTrail(c);
    _drawBall(c, al, shx, shy);
    _drawFrames(c, t);
    final d = e.drag;
    if (d != null) {
      _drawAim(c, t, d.b.px + (d.b.x - d.b.px) * al + d.b.vox, d.b.py + (d.b.y - d.b.py) * al + d.b.voy);
    } else {
      _aimOn = false;
    }
    _drawParts(c);
    c.restore();
    if (e.flash > 0) {
      _fill.color = ui.Color.fromRGBO(255, 255, 255, e.flash * .28);
      c.drawRect(ui.Rect.fromLTWH(0, 0, v.W, v.H), _fill);
    }
  }

  void _drawBodies(ui.Canvas c, double t, double al) {
    final aimTeam = e.phase == Phase.aim ? e.turn : -1;
    final aiTurn = e.isAiTurn();
    var n = 0;
    // shadows (1 atlas call), discs (1 call), dark tint, gloss (1 call)
    for (final b in e.bodies) {
      if (identical(b, e.ball)) continue;
      final x = b.px + (b.x - b.px) * al + b.vox, y = b.py + (b.y - b.py) * al + b.voy;
      final r = b.r * (1 + b.sq * .07), R = r * 1.3;
      final sc = 2 * R / spr;
      _set(_xf, n, sc, 0, x + r * .14 - R, y + r * .26 - R);
      _rect(_rc, n, 3);
      n++;
    }
    c.drawRawAtlas(atlas, _vf(_xf, n * 4), _vf(_rc, n * 4), null, null, null, _shadowP);
    // active glow ring (only the player on turn)
    final pulse = .5 + .5 * math.sin(t * 4);
    for (final b in e.bodies) {
      if (identical(b, e.ball)) continue;
      final active = b.team == aimTeam && !(e.drag != null && !identical(e.drag!.b, b)) && !aiTurn;
      if (!active) continue;
      final x = b.px + (b.x - b.px) * al + b.vox, y = b.py + (b.y - b.py) * al + b.voy;
      final r = b.r * (1 + b.sq * .07);
      _stroke
        ..strokeWidth = hq ? 6 : 4
        ..color = _teamGlow[b.team].withValues(alpha: .18 + .2 * pulse)
        ..blendMode = ui.BlendMode.plus;
      c.drawCircle(ui.Offset(x, y), r + 3, _stroke);
      _stroke
        ..strokeWidth = 2.5
        ..color = _teamGlow[b.team].withValues(alpha: .35 + .3 * pulse);
      c.drawCircle(ui.Offset(x, y), r + 2.5, _stroke);
      _stroke.blendMode = ui.BlendMode.srcOver;
    }
    n = 0;
    for (final b in e.bodies) {
      if (identical(b, e.ball)) continue;
      final x = b.px + (b.x - b.px) * al + b.vox, y = b.py + (b.y - b.py) * al + b.voy;
      final r = b.r * (1 + b.sq * .07);
      final sc = 2 * r / spr;
      final cs = math.cos(b.ang) * sc, sn = math.sin(b.ang) * sc;
      // RSTransform rotating about the sprite centre
      _xf[n * 4] = cs;
      _xf[n * 4 + 1] = sn;
      _xf[n * 4 + 2] = x - cs * spr / 2 + sn * spr / 2;
      _xf[n * 4 + 3] = y - sn * spr / 2 - cs * spr / 2;
      _rect(_rc, n, b.team == 0 ? 0 : 1);
      _dcol[n] = (e.phase == Phase.aim && b.team != e.turn) ? 0xffc8c9d0 : 0xffffffff;
      n++;
    }
    c.drawRawAtlas(atlas, _vf(_xf, n * 4), _vf(_rc, n * 4), _vi(_dcol, n), ui.BlendMode.modulate, null, _atlasP);
    n = 0;
    for (final b in e.bodies) {
      if (identical(b, e.ball)) continue;
      final x = b.px + (b.x - b.px) * al + b.vox, y = b.py + (b.y - b.py) * al + b.voy;
      final r = b.r * (1 + b.sq * .07);
      _set(_xf, n, 2 * r / spr, 0, x - r, y - r);
      _rect(_rc, n, 2);
      n++;
    }
    c.drawRawAtlas(atlas, _vf(_xf, n * 4), _vf(_rc, n * 4), null, null, null, _atlasP);
  }

  void _set(Float32List xf, int i, double scos, double ssin, double tx, double ty) {
    xf[i * 4] = scos;
    xf[i * 4 + 1] = ssin;
    xf[i * 4 + 2] = tx;
    xf[i * 4 + 3] = ty;
  }

  void _rect(Float32List rc, int i, int cell) {
    rc[i * 4] = cell * spr.toDouble();
    rc[i * 4 + 1] = 0;
    rc[i * 4 + 2] = (cell + 1) * spr.toDouble();
    rc[i * 4 + 3] = spr.toDouble();
  }

  /// v4: the ball is ALWAYS drawn with plain Canvas calls (image + gradients). v3 drew it with a FragmentShader that
  /// positions itself by FlutterFragCoord (physical pixels of the render target): on phones the match is composited
  /// into an offscreen layer (route fade / RepaintBoundary), so the centre uniform pointed outside the layer and the
  /// shader discarded every pixel -> invisible ball. The shader path stays available only behind [useBallShader].
  static bool useBallShader = false;

  void _drawBall(ui.Canvas c, double al, double shx, double shy) {
    final b = e.ball;
    final x = b.px + (b.x - b.px) * al + b.vox, y = b.py + (b.y - b.py) * al + b.voy;
    final r = math.max(4.0, b.r * (1 + b.sq * .08));
    final ctr = ui.Offset(x, y);
    // soft gray halo ring so the ball reads on any pitch (dark balls on dark fields too)
    _fill.shader = ui.Gradient.radial(ctr, r * 1.75, const [ui.Color(0x00c4c8d0), ui.Color(0x00c4c8d0), ui.Color(0x99c4c8d0), ui.Color(0x409ca3ad), ui.Color(0x00909090)],
        const [0, .5, .58, .78, 1]);
    c.drawCircle(ctr, r * 1.75, _fill);
    // drop shadow (offset down-right, like the discs)
    _fill.shader = ui.Gradient.radial(ctr.translate(r * .22, r * .32), r * 1.22, const [ui.Color(0x8c000000), ui.Color(0x40000000), ui.Color(0x00000000)], const [0, .6, 1]);
    c.drawCircle(ctr.translate(r * .22, r * .32), r * 1.22, _fill);
    _fill.shader = null;
    final sh = ballShader;
    if (useBallShader && sh != null) {
      _drawBallShader(c, sh, x, y, r, shx, shy);
      return;
    }
    // body: texture rotated with the ball's in-plane orientation, clipped to a circle
    final Rm = b.R;
    final rot = math.atan2(Rm[3], Rm[0]) + b.ang;
    c.save();
    _path
      ..reset()
      ..addOval(ui.Rect.fromCircle(center: ctr, radius: r));
    c.clipPath(_path);
    _fill.color = const ui.Color(0xfff4f6fa);
    c.drawCircle(ctr, r, _fill); // white base: never transparent even if the texture has holes
    c.translate(x, y);
    c.rotate(rot);
    final bi = im.ball;
    c.drawImageRect(bi, ui.Rect.fromLTWH(0, 0, bi.width.toDouble(), bi.height.toDouble()), ui.Rect.fromCircle(center: ui.Offset.zero, radius: r * 1.04), _img);
    c.restore();
    // sphere shading: darker rim, light from top-left, specular
    _fill.shader = ui.Gradient.radial(ctr.translate(-r * .3, -r * .35), r * 1.45, const [ui.Color(0x00000000), ui.Color(0x00000000), ui.Color(0x47000000), ui.Color(0x8c000000)], const [0, .45, .8, 1]);
    c.drawCircle(ctr, r, _fill);
    _fill.shader = ui.Gradient.radial(ctr.translate(-r * .38, -r * .42), r * .55, const [ui.Color(0xb3ffffff), ui.Color(0x26ffffff), ui.Color(0x00ffffff)], const [0, .45, 1]);
    c.drawCircle(ctr.translate(-r * .38, -r * .42), r * .55, _fill);
    _fill.shader = null;
    _stroke
      ..blendMode = ui.BlendMode.srcOver
      ..strokeWidth = math.max(.8, r * .07)
      ..color = const ui.Color(0x8c1a1d24);
    c.drawCircle(ctr, r, _stroke);
  }

  void _drawBallShader(ui.Canvas c, ui.FragmentShader sh, double x, double y, double r, double shx, double shy) {
    final b = e.ball;
    var sx = v.ox + shx + x * v.s, sy = v.oy + shy + y * v.s;
    final Rm = b.R;
    if (v.flipped) {
      sx = v.W - sx;
      sy = v.H - sy;
    }
    sh
      ..setFloat(0, sx * dpr)
      ..setFloat(1, sy * dpr)
      ..setFloat(2, r * v.s * dpr)
      ..setFloat(3, v.flipped ? -Rm[0] : Rm[0])
      ..setFloat(4, v.flipped ? -Rm[3] : Rm[3])
      ..setFloat(5, Rm[6])
      ..setFloat(6, v.flipped ? -Rm[1] : Rm[1])
      ..setFloat(7, v.flipped ? -Rm[4] : Rm[4])
      ..setFloat(8, Rm[7])
      ..setFloat(9, v.flipped ? -Rm[2] : Rm[2])
      ..setFloat(10, v.flipped ? -Rm[5] : Rm[5])
      ..setFloat(11, Rm[8])
      ..setFloat(12, math.min(.2, 1.6 / (r * v.s * dpr)))
      ..setImageSampler(0, im.ball);
    _ballP.shader = sh;
    c.drawCircle(ui.Offset(x, y), r, _ballP);
  }

  void _drawTrail(ui.Canvas c) {
    final n = e.nTrail;
    if (n < 2) return;
    final cs = kTrails[ballIdx % kTrails.length].c;
    final bw = e.ball.r;
    _stroke.blendMode = ui.BlendMode.plus;
    const layers = [(2.2, .16, 0), (1.1, .42, 1), (.42, .95, 2)];
    for (final (w, a, ci) in layers) {
      if (!hq && ci == 0) continue;
      final cc = ui.Color(ci < cs.length ? cs[ci] : 0xffffffff);
      for (var i = 1; i < n; i++) {
        final k = i / n, qa = e.tA[i];
        _stroke
          ..strokeWidth = math.max(.6, bw * w * k * qa)
          ..color = cc.withValues(alpha: math.min(1, a * qa * (.35 + .65 * k)));
        c.drawLine(ui.Offset(e.tX[i - 1], e.tY[i - 1]), ui.Offset(e.tX[i], e.tY[i]), _stroke);
      }
    }
    _stroke.blendMode = ui.BlendMode.srcOver;
  }

  void _drawParts(ui.Canvas c) {
    final n = e.nParts;
    if (n == 0) return;
    final cap = hq ? n : math.min(n, 40);
    for (var i = 0; i < cap; i++) {
      final k = math.max(0.0, e.pL[i] / e.pM[i]);
      final rr = e.pR[i] * (e.pK[i] == 3 ? 1.3 : .6 + k * .8) * 1.6;
      final sc = 2 * rr / spr;
      _pxf[i * 4] = sc;
      _pxf[i * 4 + 1] = 0;
      _pxf[i * 4 + 2] = e.pX[i] - rr;
      _pxf[i * 4 + 3] = e.pY[i] - rr;
      _prc[i * 4] = 4.0 * spr;
      _prc[i * 4 + 1] = 0;
      _prc[i * 4 + 2] = 5.0 * spr;
      _prc[i * 4 + 3] = spr.toDouble();
      final a = (math.min(1, k * 1.2) * 255).round();
      _pcol[i] = (a << 24) | (e.pC[i] & 0xffffff);
    }
    c.drawRawAtlas(atlas, _vf(_pxf, cap * 4), _vf(_prc, cap * 4), _vi(_pcol, cap), ui.BlendMode.modulate, null, _addP);
  }

  // ---- goals ----
  void _drawNets(ui.Canvas c, double t) {
    for (var i = 0; i < 2; i++) {
      final animating = e.ripple[i] > 0 || e.shake[i] > 0;
      if (!animating) {
        _nets[i] ??= () {
          final rec = ui.PictureRecorder();
          _netInto(ui.Canvas(rec), i, t, false);
          return rec.endRecording();
        }();
        c.drawPicture(_nets[i]!);
      } else {
        _netInto(c, i, t, true);
      }
    }
  }

  // v4 goals with HEIGHT: a top-down camera above the centre spot sees raised parts lean outward, so the crossbar,
  // the back bar and the post tops are drawn lifted by [_goalH] along the goal's outward direction (render only; the
  // collision geometry of e.goals is untouched). Posts cast shadows on the grass, the net has a floor, side walls,
  // a back wall and a raised roof.
  static const double _goalH = 30;
  ui.Offset _lift(double x, double y, double d, double h) => ui.Offset(x + (x - e.CX) * h * .0022, y + d * h);

  void _netInto(ui.Canvas c, int i, double t, bool anim) {
    final g = e.goals[i];
    final d = g.d.toDouble(), x1 = g.x1 - POST_R, x2 = g.x2 + POST_R, D = e.DEPTH + 6, y0 = g.y, yb = g.y + d * D;
    final inset = (x2 - x1) * .045, bx1 = x1 + inset, bx2 = x2 - inset;
    final sx = anim ? math.sin(t * 40) * 6 * e.shake[i] : 0.0;
    final rp = anim ? e.ripple[i] : 0.0, rx = e.rippleX[i];
    const H = _goalH, HB = _goalH * .82;
    double bulge(double x, double k) => rp > 0 ? d * rp * 16 * k * math.exp(-math.pow((x - rx) / 70, 2)) * (1 + .35 * math.sin(t * 22)) : 0;
    c.save();
    c.translate(sx, 0);
    // floor
    _path
      ..reset()
      ..moveTo(x1, y0)
      ..lineTo(x2, y0)
      ..lineTo(bx2, yb)
      ..lineTo(bx1, yb)
      ..close();
    _fill.shader = ui.Gradient.linear(ui.Offset(0, y0), ui.Offset(0, yb), const [ui.Color(0x38000000), ui.Color(0x8c000000)]);
    c.drawPath(_path, _fill);
    _fill.shader = null;
    // frame shadow cast on the grass (light from the top-left -> shadow to the bottom-right)
    const shx = H * .55, shy = H * .42;
    _netP
      ..strokeWidth = POST_R * 1.6
      ..color = const ui.Color(0x6b000000);
    c.drawLine(ui.Offset(x1 + shx, y0 + shy), ui.Offset(x2 + shx, y0 + shy), _netP);
    c.drawLine(ui.Offset(x1, y0), ui.Offset(x1 + shx, y0 + shy), _netP);
    c.drawLine(ui.Offset(x2, y0), ui.Offset(x2 + shx, y0 + shy), _netP);
    // raised outline points
    final f1 = _lift(x1, y0, d, H), f2 = _lift(x2, y0, d, H), r1 = _lift(bx1, yb, d, HB), r2 = _lift(bx2, yb, d, HB);
    // side walls + back wall (translucent panels)
    _fill.color = const ui.Color(0x1fffffff);
    for (final q in [
      [ui.Offset(x1, y0), f1, r1, ui.Offset(bx1, yb)],
      [ui.Offset(x2, y0), f2, r2, ui.Offset(bx2, yb)],
      [ui.Offset(bx1, yb), r1, r2, ui.Offset(bx2, yb)],
    ]) {
      _path
        ..reset()
        ..addPolygon(q, true);
      c.drawPath(_path, _fill);
    }
    _netP
      ..strokeWidth = 1.1
      ..color = const ui.Color(0x38ffffff);
    // back-wall verticals
    final nb = math.max(6, ((bx2 - bx1) / 22).round());
    for (var k = 0; k <= nb; k++) {
      final u = k / nb, gx = bx1 + (bx2 - bx1) * u;
      c.drawLine(ui.Offset(gx, yb), ui.Offset.lerp(r1, r2, u)!, _netP);
    }
    // side-wall diagonals
    for (var j = 1; j < 6; j++) {
      final vv = j / 6;
      c.drawLine(ui.Offset(x1 + (bx1 - x1) * vv, y0 + (yb - y0) * vv), ui.Offset.lerp(f1, r1, vv)!, _netP);
      c.drawLine(ui.Offset(x2 + (bx2 - x2) * vv, y0 + (yb - y0) * vv), ui.Offset.lerp(f2, r2, vv)!, _netP);
    }
    // raised roof mesh
    final n = math.max(8, ((x2 - x1) / 18).round());
    _netP
      ..strokeWidth = 1.3
      ..color = const ui.Color(0x4dffffff);
    for (var k = 0; k <= n; k++) {
      final u = k / n, fa = ui.Offset.lerp(f1, f2, u)!, ra = ui.Offset.lerp(r1, r2, u)!;
      _path
        ..reset()
        ..moveTo(fa.dx, fa.dy);
      for (var j = 1; j <= 6; j++) {
        final vv = j / 6, p = ui.Offset.lerp(fa, ra, vv)!;
        _path.lineTo(p.dx, p.dy + bulge(p.dx, math.sin(vv * math.pi)));
      }
      c.drawPath(_path, _netP);
    }
    for (var j = 1; j <= 7; j++) {
      final vv = math.pow(j / 7, .85).toDouble(), pa = ui.Offset.lerp(f1, r1, vv)!, pb = ui.Offset.lerp(f2, r2, vv)!;
      _path
        ..reset()
        ..moveTo(pa.dx, pa.dy);
      for (var k = 1; k <= 12; k++) {
        final p = ui.Offset.lerp(pa, pb, k / 12)!;
        _path.lineTo(p.dx, p.dy + bulge(p.dx, math.sin(vv * math.pi)));
      }
      c.drawPath(_path, _netP);
    }
    // roof edges + back bar (raised) and the ground back line
    _netP
      ..strokeWidth = 3
      ..color = const ui.Color(0x8cffffff);
    c.drawLine(f1, r1, _netP);
    c.drawLine(f2, r2, _netP);
    _netP
      ..strokeWidth = 2
      ..color = const ui.Color(0x59ffffff);
    c.drawLine(ui.Offset(bx1, yb), ui.Offset(bx2, yb), _netP);
    c.drawLine(ui.Offset(bx1, yb), r1, _netP);
    c.drawLine(ui.Offset(bx2, yb), r2, _netP);
    _netP
      ..strokeWidth = 4.5
      ..color = const ui.Color(0xbfe8edf5);
    c.drawLine(r1, r2, _netP);
    c.restore();
  }

  void _drawFrames(ui.Canvas c, double t) {
    const W = POST_R * 1.7, H = _goalH;
    for (var i = 0; i < 2; i++) {
      final g = e.goals[i];
      final d = g.d.toDouble();
      final sx = math.sin(t * 40) * 6 * e.shake[i], y = g.y, x1 = g.x1 + sx, x2 = g.x2 + sx;
      final t1 = _lift(x1, y, d, H), t2 = _lift(x2, y, d, H);
      // contact shadow at the post bases
      _fill.color = const ui.Color(0x66000000);
      c.drawCircle(ui.Offset(x1 + 3, y + 3), POST_R * 1.25, _fill);
      c.drawCircle(ui.Offset(x2 + 3, y + 3), POST_R * 1.25, _fill);
      // posts: base -> raised top, shaded across their width (light from the left)
      for (final (b0, tp) in [(ui.Offset(x1, y), t1), (ui.Offset(x2, y), t2)]) {
        _bar
          ..strokeWidth = W
          ..shader = ui.Gradient.linear(ui.Offset(b0.dx - W / 2, 0), ui.Offset(b0.dx + W / 2, 0),
              const [ui.Color(0xff7a8292), ui.Color(0xffffffff), ui.Color(0xffd9dee7), ui.Color(0xff596173)], const [0, .3, .62, 1]);
        c.drawLine(b0, tp, _bar);
        _fill.shader = ui.Gradient.radial(b0.translate(-POST_R * .3, -POST_R * .3), POST_R * 1.2, const [ui.Color(0xffd0d6df), ui.Color(0xff8e96a6), ui.Color(0xff4a5162)], const [0, .55, 1]);
        c.drawCircle(b0, POST_R, _fill);
      }
      // crossbar (raised), with a bright highlight line on its upper edge
      _bar.shader = ui.Gradient.linear(ui.Offset(0, t1.dy - W / 2), ui.Offset(0, t1.dy + W / 2),
          const [ui.Color(0xff8d96a6), ui.Color(0xffffffff), ui.Color(0xffdfe5ee), ui.Color(0xff6c7484)], const [0, .35, .6, 1]);
      c.drawLine(t1, t2, _bar);
      _bar
        ..shader = null
        ..strokeWidth = 1.6
        ..color = const ui.Color(0xe6ffffff);
      c.drawLine(t1.translate(0, -W * .22), t2.translate(0, -W * .22), _bar);
      for (final tp in [t1, t2]) {
        _fill.shader = ui.Gradient.radial(tp.translate(-POST_R * .35, -POST_R * .4), POST_R * 1.25, const [ui.Color(0xffffffff), ui.Color(0xffd5dbe5), ui.Color(0xff5d6575)], const [0, .5, 1]);
        c.drawCircle(tp, POST_R + 1, _fill);
      }
      _fill.shader = null;
    }
  }

  // ---- aim ----
  ui.Color _mix(ui.Color a, ui.Color b, double k) => ui.Color.lerp(a, b, k)!;
  ui.Color _powerCol(double p) => p < .5 ? _mix(_aimC[0], _aimC[1], p / .5) : _mix(_aimC[1], _aimC[2], (p - .5) / .5);

  void _drawAim(ui.Canvas c, double t, double x, double y) {
    final a = e.aimInfo();
    if (a == null || a.p <= 0) {
      _aimOn = false;
      return;
    }
    if (!_aimOn) {
      _aux = a.ux;
      _auy = a.uy;
      _ap = a.p;
      _aimOn = true;
    } else {
      _aux += (a.ux - _aux) * .55;
      _auy += (a.uy - _auy) * .55;
      _ap += (a.p - _ap) * .6;
    }
    var ul = math.sqrt(_aux * _aux + _auy * _auy);
    if (ul == 0) ul = 1;
    final b = a.b!, team = b.team, r = b.r;
    // v4: low accuracy -> the arrow wobbles (visual only; the real deviation is rolled in Engine.fire)
    final wob = e.cfg.stats != null ? aimDevDeg(e.statsOf(team).accuracy) * .45 * math.pi / 180 * math.sin(t * 7.3) * (.4 + .6 * _ap) : 0.0;
    final cw = math.cos(wob), sw = math.sin(wob);
    final ux = (_aux * cw - _auy * sw) / ul, uy = (_aux * sw + _auy * cw) / ul, pw = _ap;
    // Nexora_godot (0c5c3a9): the arrow beyond the rim grows LINEARLY with power from a short stub
    // (AIM_MIN_K x r) to AIM_MAX_K x r; classic keeps the RN lengths.
    final shortLong = e.godot;
    final Lg = r + 4 + r * (_aimMinK + (_aimMaxK - _aimMinK) * pw.clamp(0.0, 1.0));
    double L;
    if (im.hasArrow) {
      L = _arrowArt(c, t, x, y, ux, uy, r, pw, shortLong ? Lg : null);
    } else {
      final nx = -uy, ny = ux;
      final l0 = r + 6, lmax = r + 250;
      L = shortLong ? Lg : r + 34 + pw * 216;
      // short arrows get a proportionally smaller head so the stub still reads as an arrow
      final hs = shortLong ? math.min(20 + pw * 8, (L - l0) * .6) : 20 + pw * 8;
      final w0 = 9 + pw * 5, w1 = 3.0, neck = L - hs;
      _path
        ..reset()
        ..moveTo(x + ux * l0 + nx * w0, y + uy * l0 + ny * w0)
        ..lineTo(x + ux * neck + nx * w1, y + uy * neck + ny * w1)
        ..lineTo(x + ux * neck + nx * hs * .62, y + uy * neck + ny * hs * .62)
        ..lineTo(x + ux * L, y + uy * L)
        ..lineTo(x + ux * neck - nx * hs * .62, y + uy * neck - ny * hs * .62)
        ..lineTo(x + ux * neck - nx * w1, y + uy * neck - ny * w1)
        ..lineTo(x + ux * l0 - nx * w0, y + uy * l0 - ny * w0)
        ..close();
      _fill.shader = ui.Gradient.linear(ui.Offset(x + ux * l0, y + uy * l0), ui.Offset(x + ux * lmax, y + uy * lmax), _aimC, const [0, .5, 1]);
      c.drawPath(_path, _fill);
      _fill.shader = null;
    }
    final pc = _powerCol(pw);
    _stroke
      ..strokeWidth = 4
      ..color = pc.withValues(alpha: .9);
    c.drawArc(ui.Rect.fromCircle(center: ui.Offset(x, y), radius: r + 9), -math.pi / 2, 2 * math.pi * pw, false, _stroke);
    final steps = shortLong
        ? math.max(2, ((3 + pw * 4) * (e.cfg.stats != null ? aimPreview(e.statsOf(team).accuracy) : 1)).round())
        : math.max(2, ((5 + pw * 6) * (e.cfg.stats != null ? aimPreview(e.statsOf(team).accuracy) : 1)).round());
    for (var i = 1; i <= steps; i++) {
      final d = L + 8 + i * (shortLong ? 12 : 22), k = 1 - i / (steps + 1);
      if (shortLong && d > L + r * .7) break; // Godot: accuracy dots stay just past the tip
      _addP.color = pc.withValues(alpha: .6 * k);
      c.drawCircle(ui.Offset(x + ux * d, y + uy * d), 2.2 + 2 * k, _addP);
    }
    _addP.color = const ui.Color(0xffffffff);
    _stroke
      ..strokeWidth = 2.5
      ..color = const ui.Color(0x2effffff);
    c.drawLine(ui.Offset(x - ux * r, y - uy * r), ui.Offset(x - ux * (r + 18 + pw * 60), y - uy * (r + 18 + pw * 60)), _stroke);
  }

  double _arrowArt(ui.Canvas c, double t, double x, double y, double ux, double uy, double r, double pw, [double? lOverride]) {
    final l0 = r + 3, L = lOverride ?? r + 70 + pw * 110;
    final ae = _sstep(.66, .72, pw), as_ = 1 - _sstep(.7, .75, pw);
    c.save();
    c.translate(x, y);
    c.rotate(math.atan2(uy, ux) + math.pi / 2);
    if (as_ > 0) {
      _art.color = ui.Color.fromRGBO(255, 255, 255, as_);
      _slices(c, im.headS!, im.shaftS!, _artS, l0, L, _art);
    }
    if (ae > 0) {
      _art.color = ui.Color.fromRGBO(255, 255, 255, ae);
      _slices(c, im.headE!, im.shaftE!, _artE, l0, L, _art);
      final pulse = .5 + .5 * math.sin(t * (6 + pw * 8));
      _artGlow.color = ui.Color.fromRGBO(255, 255, 255, (ae * (.06 + .16 * pulse) * pw).clamp(0, 1));
      _slices(c, im.headE!, im.shaftE!, _artE, l0, L, _artGlow);
    }
    c.restore();
    return L;
  }

  void _slices(ui.Canvas c, ui.Image head, ui.Image shaft, _ArtK k, double l0, double L, ui.Paint p) {
    final hw = k.hh * head.width / head.height, sh = shaft.height.toDouble(), sW = shaft.width.toDouble();
    final y0 = sh * k.top, y1 = sh * k.tail, x0 = -k.sw / 2;
    final neck = L - k.hh * k.join;
    final len = math.max(2.0, neck - l0);
    var topL = k.topLen, tailL = k.tailLen;
    if (topL + tailL > len * .8) {
      final f = len * .8 / (topL + tailL);
      topL *= f;
      tailL *= f;
    }
    final mid = len - topL - tailL;
    void draw(double sy0, double sy1, double dy, double dh) => c.drawImageRect(shaft, ui.Rect.fromLTWH(0, sy0, sW, sy1 - sy0), ui.Rect.fromLTWH(x0, dy, k.sw, dh), p);
    draw(y1, sh, -l0 - tailL, tailL);
    if (mid > 0) draw(y0, y1, -neck + topL, mid);
    if (topL > 0) draw(0, y0, -neck, topL);
    c.drawImageRect(head, ui.Rect.fromLTWH(0, 0, head.width.toDouble(), head.height.toDouble()), ui.Rect.fromLTWH(-hw / 2, -L, hw, k.hh), p);
  }
}
