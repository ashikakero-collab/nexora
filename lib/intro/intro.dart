// v4 intro cinematic (replaces the v3 "NEXORA Voyage" FragmentShader intro, which rendered blank / mis-sized on
// phones because its shaders positioned themselves with FlutterFragCoord). Pure widgets + Canvas + the owner's art,
// ~7.6 s, tap anywhere or "رد شدن" to skip:
//   0.0-2.4  fly through the cosmic background: zooming nebula, two parallax star layers, warp streaks speeding up
//   2.0-3.6  the portal background takes over, streaks peak, white flash
//   3.4-5.6  the planet rises, the NEXORA logo scales in with a glow while an orbit ring sweeps round it
//   5.0-7.6  the animated Oracle flies in, waves, tagline -> hand off to home
// It can never stay black: a navy gradient + procedural stars paint from frame one (no assets needed), every image
// is BoxFit.cover/contain (never stretched) and precached up front.
import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../core/sound.dart';
import '../core/theme.dart';
import '../oracle/avatar.dart';
import '../ui/kit.dart';
import '../ui/v4.dart';

const double kIntroLen = 7.6;

class Intro extends StatefulWidget {
  final VoidCallback onDone;
  const Intro({super.key, required this.onDone});
  @override
  State<Intro> createState() => _IntroState();
}

double _seg(double t, double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);
double _ease(double x) => Curves.easeOutCubic.transform(x.clamp(0.0, 1.0));
double _inOut(double x) => Curves.easeInOutCubic.transform(x.clamp(0.0, 1.0));

class _IntroState extends State<Intro> with SingleTickerProviderStateMixin {
  late final Ticker _tk;
  final ValueNotifier<double> t = ValueNotifier(0);
  bool done = false, _roar = false, _whoosh = false;

  @override
  void initState() {
    super.initState();
    _tk = createTicker((e) {
      final s = e.inMicroseconds / 1e6;
      t.value = s;
      if (!_whoosh && s > .3) {
        _whoosh = true;
        sfx(Snd.ui, .6);
      }
      if (!_roar && s > 3.3) {
        _roar = true;
        sfx(Snd.roar, .5);
      }
      if (s >= kIntroLen) _finish();
    })
      ..start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    for (final a in [V4.bgSpace, V4.bgPortal1, V4.heroPlanet, V4.logo]) {
      precacheImage(AssetImage(a), context).catchError((_) {});
    }
    precacheOracle(context, height: 200);
  }

  void _finish() {
    if (done) return;
    done = true;
    _tk.stop();
    widget.onDone();
  }

  @override
  void dispose() {
    _tk.dispose();
    t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ins = MediaQuery.paddingOf(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _finish,
      child: LayoutBuilder(builder: (ctx, box) {
        final w = box.maxWidth, h = box.maxHeight;
        final k = (w / 400).clamp(.85, 1.25);
        return ValueListenableBuilder<double>(
          valueListenable: t,
          builder: (_, s, __) {
            final fly = _seg(s, 0, 2.6), portal = _seg(s, 2.0, 3.6), flash = s > 3.2 && s < 3.9 ? math.sin(_seg(s, 3.2, 3.9) * math.pi) : 0.0;
            final logoIn = _ease(_seg(s, 3.5, 4.6)), ring = _seg(s, 3.8, 5.4), planet = _ease(_seg(s, 3.4, 5.0));
            final oracleIn = _ease(_seg(s, 5.0, 6.0)), outro = _seg(s, 7.1, kIntroLen);
            final speed = s < 3.4 ? .25 + _inOut(_seg(s, 0, 3.3)) * 1.6 : math.max(0.0, 1.0 - _seg(s, 3.4, 4.4)) * 1.2;
            final logoW = math.min(w * .78, 360.0);
            return Stack(fit: StackFit.expand, children: [
              const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xff04061c), Color(0xff0a0c3a), Color(0xff1c0a3e)]))),
              // nebula flythrough
              Opacity(
                opacity: (1 - portal).clamp(0.0, 1.0),
                child: Transform.scale(scale: 1.0 + _inOut(fly) * .7, child: Image.asset(V4.bgSpace, fit: BoxFit.cover, width: w, height: h, alignment: Alignment.center, gaplessPlayback: true)),
              ),
              Opacity(
                opacity: portal,
                child: Transform.scale(scale: 1.35 - _ease(portal) * .3 + _seg(s, 3.6, kIntroLen) * .08, child: Image.asset(V4.bgPortal1, fit: BoxFit.cover, width: w, height: h, alignment: Alignment.center, gaplessPlayback: true)),
              ),
              // stars + warp streaks (Canvas only)
              CustomPaint(painter: _WarpPainter(s, speed), size: Size(w, h)),
              // planet rising behind the logo
              Positioned(
                left: (w - logoW * 1.15) / 2,
                top: h * .5 - logoW * .45 + (1 - planet) * h * .35,
                child: Opacity(opacity: planet * (1 - outro * .3), child: Image.asset(V4.heroPlanet, width: logoW * 1.15, fit: BoxFit.contain)),
              ),
              // logo + orbit ring sweep
              Positioned(
                left: (w - logoW) / 2,
                top: h * .28 - logoW * .3,
                width: logoW,
                height: logoW * .75,
                child: Opacity(
                  opacity: logoIn,
                  child: Transform.scale(
                    scale: .6 + logoIn * .4 + math.sin(s * 2) * .01,
                    child: Stack(alignment: Alignment.center, children: [
                      if (hq)
                        Container(
                          width: logoW,
                          height: logoW * .7,
                          decoration: BoxDecoration(gradient: RadialGradient(colors: [N.orange.withValues(alpha: .3 * logoIn), N.orange.withValues(alpha: 0)])),
                        ),
                      CustomPaint(painter: _RingPainter(ring, s), size: Size(logoW, logoW * .75)),
                      NexoraLogo(width: logoW * .92),
                    ]),
                  ),
                ),
              ),
              // the Oracle flies in and waves
              if (s > 4.9)
                Positioned(
                  right: -w * .6 + oracleIn * (w * .6 + (w - 175 * k) / 2),
                  bottom: ins.bottom + h * .12 + math.sin(oracleIn * math.pi) * 40,
                  child: Opacity(opacity: oracleIn, child: Transform.rotate(angle: (1 - oracleIn) * -.4, child: OracleAvatar(size: 200 * k, listen: false))),
                ),
              Positioned(
                left: 24,
                right: 24,
                bottom: ins.bottom + h * .07,
                child: Opacity(
                  opacity: _ease(_seg(s, 5.6, 6.4)) * (1 - outro),
                  child: Column(children: [
                    T('FINGER SOCCER · GALAXY LEAGUE', size: 11 * k, family: F.head, weight: 700, spacing: 3, color: N.amber, align: TextAlign.center),
                    const SizedBox(height: 6),
                    T('به کهکشان نکسورا خوش آمدی', size: 16 * k, color: Colors.white, align: TextAlign.center),
                  ]),
                ),
              ),
              if (flash > 0) IgnorePointer(child: ColoredBox(color: Colors.white.withValues(alpha: flash * .85))),
              if (outro > 0) IgnorePointer(child: ColoredBox(color: N.navy.withValues(alpha: outro))),
              Positioned(
                top: ins.top + 10,
                left: 14,
                child: Press(
                  onTap: _finish,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(color: const Color(0x8c060a24), borderRadius: BorderRadius.circular(18), border: Border.all(color: N.orange.withValues(alpha: .7))),
                    child: const T('رد شدن ›', size: 12, color: Colors.white),
                  ),
                ),
              ),
            ]);
          },
        );
      }),
    );
  }
}

/// Stars that stream outward from the centre; their streak length grows with [speed] (warp).
class _WarpPainter extends CustomPainter {
  final double t, speed;
  _WarpPainter(this.t, this.speed);
  static final List<(double, double, double)> _stars = () {
    final r = math.Random(11);
    return [for (var i = 0; i < 170; i++) (r.nextDouble() * 2 * math.pi, r.nextDouble(), .4 + r.nextDouble() * 1.6)];
  }();
  final Paint _p = Paint()
    ..strokeCap = StrokeCap.round
    ..isAntiAlias = true;
  @override
  void paint(Canvas c, Size s) {
    final cx = s.width / 2, cy = s.height * .42, R = math.sqrt(s.width * s.width + s.height * s.height) * .6;
    for (var i = 0; i < _stars.length; i++) {
      final (a, d0, sz) = _stars[i];
      final d = (d0 + t * (.08 + speed * .35) * (.6 + sz * .4)) % 1.0;
      final dd = d * d;
      final x = cx + math.cos(a) * dd * R, y = cy + math.sin(a) * dd * R;
      final len = (speed * 60 + 2) * dd;
      final al = (dd * 1.6).clamp(0.0, 1.0);
      _p
        ..strokeWidth = sz * (.6 + dd)
        ..color = (i % 6 == 0 ? const Color(0xffffc58a) : i % 4 == 0 ? const Color(0xff9fc2ff) : Colors.white).withValues(alpha: al);
      c.drawLine(Offset(x, y), Offset(x - math.cos(a) * len, y - math.sin(a) * len), _p);
    }
  }

  @override
  bool shouldRepaint(_WarpPainter o) => o.t != t || o.speed != speed;
}

/// Tilted orbit ring around the logo; [p] 0..1 sweeps the bright arc round once, then it keeps a slow drift.
class _RingPainter extends CustomPainter {
  final double p, t;
  _RingPainter(this.p, this.t);
  @override
  void paint(Canvas c, Size s) {
    if (p <= 0) return;
    final rect = Rect.fromCenter(center: Offset(s.width / 2, s.height * .52), width: s.width * .98, height: s.height * .36);
    c.save();
    c.translate(rect.center.dx, rect.center.dy);
    c.rotate(-.18);
    c.translate(-rect.center.dx, -rect.center.dy);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = N.orange.withValues(alpha: .35 * p);
    c.drawArc(rect, 0, 2 * math.pi * _ease(p), false, base);
    final head = -math.pi / 2 + 2 * math.pi * _ease(p) + t * .4;
    final sweep = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3.5
      ..shader = SweepGradient(colors: const [Color(0x00ff8a2a), Color(0xffffc27a), Color(0xffff4f9a)], stops: const [0, .8, 1], transform: GradientRotation(head - 1.4)).createShader(rect);
    c.drawArc(rect, head - 1.4, 1.4, false, sweep);
    c.restore();
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.p != p || o.t != t;
}
