// Native "NEXORA Voyage" intro (replaces the old webview HTML): three FragmentProgram shaders on one
// CustomPainter driven by a single Ticker. Earth orbit -> hyperspace warp -> arrival at planet NEXORA -> logo.
// Tap anywhere (or the Skip button) to skip. If shaders fail to load it falls back to a short logo fade.
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../core/assets.dart' as assets;
import '../core/sound.dart';
import '../core/theme.dart';
import '../ui/kit.dart';

const double kIntroLen = 14.0;

class Intro extends StatefulWidget {
  final VoidCallback onDone;
  const Intro({super.key, required this.onDone});
  @override
  State<Intro> createState() => _IntroState();
}

class _Shaders {
  final ui.FragmentShader bg, warp, planet;
  _Shaders(this.bg, this.warp, this.planet);
}

class _IntroState extends State<Intro> with SingleTickerProviderStateMixin {
  late final Ticker _tk;
  final ValueNotifier<double> t = ValueNotifier(0);
  _Shaders? sh;
  bool failed = false, done = false;
  bool _whoosh = false;

  @override
  void initState() {
    super.initState();
    _load();
    _tk = createTicker((e) {
      final s = e.inMicroseconds / 1e6;
      t.value = s;
      if (!_whoosh && s > 4.2) {
        _whoosh = true;
        sfx(Snd.roar, .5);
      }
      if (s >= (failed ? 2.4 : kIntroLen)) _finish();
    })
      ..start();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([
        ui.FragmentProgram.fromAsset('shaders/intro_post.frag'),
        ui.FragmentProgram.fromAsset('shaders/intro_warp.frag'),
        ui.FragmentProgram.fromAsset('shaders/intro_planet.frag'),
      ]);
      if (mounted) setState(() => sh = _Shaders(r[0].fragmentShader(), r[1].fragmentShader(), r[2].fragmentShader()));
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
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
      child: ColoredBox(
        color: Colors.black,
        child: Stack(fit: StackFit.expand, children: [
          if (sh != null) RepaintBoundary(child: CustomPaint(painter: _VoyagePainter(sh!, t, MediaQuery.devicePixelRatioOf(context)))),
          ValueListenableBuilder<double>(
            valueListenable: t,
            builder: (_, s, __) {
              final logoIn = failed ? (s / .8).clamp(0.0, 1.0) : ((s - 10.6) / 1.2).clamp(0.0, 1.0);
              final out = failed ? 1 - ((s - 1.8) / .6).clamp(0.0, 1.0) : 1 - ((s - 13.2) / .8).clamp(0.0, 1.0);
              final title = ((s - .6) / 1).clamp(0.0, 1.0) * (1 - ((s - 3.6) / .6).clamp(0.0, 1.0));
              return Stack(fit: StackFit.expand, children: [
                if (!failed)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: MediaQuery.sizeOf(context).height * .2,
                    child: Opacity(
                      opacity: title,
                      child: Column(children: [
                        tHead('EARTH · ORBIT 01', size: 11, color: C.sky, spacing: 6),
                        const SizedBox(height: 8),
                        const T('سفر به جهان نکسورا آغاز می‌شود…', size: 15, color: Color(0xffd6e6ff)),
                      ]),
                    ),
                  ),
                Center(
                  child: Opacity(
                    opacity: (logoIn * out).clamp(0, 1),
                    child: Transform.scale(
                      scale: .85 + logoIn * .15,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Img(assets.ui('nx_logo'), w: 260, h: 182),
                        const SizedBox(height: 10),
                        tHead('YOUR UNIVERSE · YOUR CONNECTION', size: 9, color: C.cyan, spacing: 3),
                      ]),
                    ),
                  ),
                ),
                if (out < 1) IgnorePointer(child: ColoredBox(color: Colors.black.withValues(alpha: 1 - out))),
              ]);
            },
          ),
          Positioned(
            top: ins.top + 10,
            right: 14,
            child: Press(
              onTap: _finish,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(color: const Color(0x66000000), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0x55ffffff))),
                child: const T('رد کردن ›', size: 12, color: Colors.white),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

double _ss(double a, double b, double x) {
  final k = ((x - a) / (b - a)).clamp(0.0, 1.0);
  return k * k * (3 - 2 * k);
}

class _VoyagePainter extends CustomPainter {
  final _Shaders s;
  final ValueNotifier<double> t;
  final double dpr;
  final Paint _p = Paint();
  _VoyagePainter(this.s, this.t, this.dpr) : super(repaint: t);

  @override
  void paint(Canvas c, Size size) {
    final time = t.value;
    final w = size.width * dpr, h = size.height * dpr;
    final rect = Offset.zero & size;
    // scene weights: 0 earth (0-5.2), 1 warp (4.2-10.2), 2 nexora (9.2-14)
    final warp = _ss(4.2, 5.2, time) * (1 - _ss(9.2, 10.4, time));
    final arrive = _ss(9.4, 10.6, time);
    final fadeIn = _ss(0, 1.2, time);

    // space backdrop
    s.bg
      ..setFloat(0, w)
      ..setFloat(1, h)
      ..setFloat(2, time)
      ..setFloat(3, arrive)
      ..setFloat(4, fadeIn * (1 - warp * .7));
    _p.shader = s.bg;
    c.drawRect(rect, _p);

    // earth: recedes while we accelerate away
    final earthA = 1 - _ss(4.4, 5.6, time);
    if (earthA > 0) {
      final k = _ss(0, 5.2, time);
      final r = size.shortestSide * (.62 - k * .42);
      final cx = size.width * (.5 + k * .15), cy = size.height * (.62 + k * .25);
      _planet(c, cx, cy, r, time, seed: 1.3, ca: const [.04, .16, .42], cb: const [.10, .42, .16], cc: const [.55, .48, .34], atmo: const [.35, .6, 1.0], clouds: .9, city: 1, alpha: earthA);
    }
    // warp tunnel
    if (warp > 0) {
      s.warp
        ..setFloat(0, w)
        ..setFloat(1, h)
        ..setFloat(2, time)
        ..setFloat(3, _ss(4.2, 7.5, time) * (1 - _ss(8.6, 10.2, time)))
        ..setFloat(4, warp);
      _p
        ..shader = s.warp
        ..blendMode = BlendMode.plus;
      c.drawRect(rect, _p);
      _p.blendMode = BlendMode.srcOver;
    }
    // planet NEXORA: approaches and settles behind the logo
    if (arrive > 0) {
      final k = _ss(9.4, 13.0, time);
      final r = size.shortestSide * (.12 + k * .38);
      _planet(c, size.width / 2, size.height * (.56 + (1 - k) * .1), r, time,
          seed: 4.7, ca: const [.10, .04, .30], cb: const [.32, .12, .62], cc: const [.10, .55, .85], atmo: const [.55, .35, 1.0], clouds: .55, city: 1.4, alpha: arrive);
    }
  }

  void _planet(Canvas c, double cx, double cy, double r, double time,
      {required double seed, required List<double> ca, required List<double> cb, required List<double> cc, required List<double> atmo, required double clouds, required double city, required double alpha}) {
    final p = s.planet;
    var i = 0;
    for (final v in [cx * dpr, cy * dpr, r * dpr, time, seed, ...ca, ...cb, ...cc, ...atmo, clouds, city, time * .05 + seed]) {
      p.setFloat(i++, v);
    }
    _p
      ..shader = p
      ..color = Color.fromRGBO(0, 0, 0, alpha);
    final rr = r * 1.5;
    c.drawRect(Rect.fromCircle(center: Offset(cx, cy), radius: rr), _p);
    _p.color = const Color(0xff000000);
  }

  @override
  bool shouldRepaint(_VoyagePainter o) => false;
}
