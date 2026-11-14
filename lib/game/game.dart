// Flame host for a match: owns the frame loop (Flame's ticker) and paints the
// MatchRenderer. The simulation step itself is injected (offline: Engine.update; online: the net controller).
import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flutter/widgets.dart';

import 'engine.dart';
import 'render.dart';

class MatchGame extends FlameGame {
  final Engine e;
  MatchRenderer? r;
  final void Function(double dt) onTick;
  double _t = 0;
  bool paused = false;

  // perf probes for the debug overlay
  double frameMs = 0, stepMs = 0;
  final Stopwatch _sw = Stopwatch();

  MatchGame({required this.e, required this.onTick});

  MatchView? get view => r?.v;

  @override
  ui.Color backgroundColor() => const ui.Color(0xff02040c);

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    if (!paused) {
      _sw
        ..reset()
        ..start();
      onTick(dt);
      _sw.stop();
      stepMs = stepMs * .9 + _sw.elapsedMicroseconds / 1000 * .1;
    }
    frameMs = frameMs * .9 + dt * 1000 * .1;
  }

  @override
  void render(ui.Canvas canvas) {
    super.render(canvas);
    r?.render(canvas, _t);
  }

  /// screen (logical px) -> world units
  Offset? toWorld(Offset p) => r?.v.toWorld(p.dx, p.dy);
}
