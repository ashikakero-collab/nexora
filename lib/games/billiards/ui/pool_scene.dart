import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../core/pool_match.dart';

/// Short-lived spark drawn on impacts (only with fancyEffects).
class PoolParticle {
  PoolParticle(this.x, this.y, this.vx, this.vy, this.life, this.color);
  double x;
  double y;
  double vx;
  double vy;
  double life;
  final Color color;
  double age = 0;
}

/// Glow ring on a pocket when a ball drops.
class PoolFlash {
  PoolFlash(this.pocket, this.color);
  final int pocket;
  final Color color;
  double t = 0;
}

/// A ball shrinking into a pocket.
class PoolSink {
  PoolSink(this.ballId, this.x, this.y);
  final int ballId;
  final double x;
  final double y;
  double t = 0;
}

/// Mutable render state shared by the game state and the painter. Physics/rules
/// live in [PoolMatch]; this only holds what is needed to draw a frame.
class PoolScene extends ChangeNotifier {
  PoolScene(this.match, {required this.cueSkin, required this.fancy});

  PoolMatch match;
  final String cueSkin;
  final bool fancy;

  double aimAngle = -math.pi / 2;
  bool showAim = false;
  bool showCue = false;

  /// 0..1 visual pull-back of the cue while charging.
  double pull = 0;

  /// Distance the cue tip travels during the strike animation (0 = resting).
  double strikeOffset = 0;
  double cueOpacity = 1;

  bool ballInHand = false;
  bool placing = false;
  bool placeValid = true;
  bool kitchenOnly = false;

  /// Highlight colour of the guide (legal / illegal first contact).
  double time = 0;

  final List<double> roll = List<double>.filled(16, 0);
  final List<double> rollDirX = List<double>.filled(16, 0);
  final List<double> rollDirY = List<double>.filled(16, -1);
  final List<double> lastX = List<double>.filled(16, 0);
  final List<double> lastY = List<double>.filled(16, 0);

  final List<PoolParticle> particles = <PoolParticle>[];
  final List<PoolFlash> flashes = <PoolFlash>[];
  final List<PoolSink> sinks = <PoolSink>[];

  void syncLast() {
    for (int i = 0; i < 16; i++) {
      lastX[i] = match.balls[i].x;
      lastY[i] = match.balls[i].y;
    }
  }

  /// Accumulates the visual rolling phase from ball displacement.
  void updateRoll() {
    for (int i = 0; i < 16; i++) {
      final double dx = match.balls[i].x - lastX[i];
      final double dy = match.balls[i].y - lastY[i];
      final double d2 = dx * dx + dy * dy;
      if (d2 > 1e-6 && d2 < 10000 && !match.balls[i].pocketed) {
        final double d = math.sqrt(d2);
        rollDirX[i] = dx / d;
        rollDirY[i] = dy / d;
        roll[i] += d;
      }
      lastX[i] = match.balls[i].x;
      lastY[i] = match.balls[i].y;
    }
  }

  void advanceFx(double dt) {
    time += dt;
    for (int i = particles.length - 1; i >= 0; i--) {
      final PoolParticle p = particles[i];
      p.age += dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.vx *= 0.9;
      p.vy *= 0.9;
      if (p.age >= p.life) particles.removeAt(i);
    }
    for (int i = flashes.length - 1; i >= 0; i--) {
      flashes[i].t += dt / 0.7;
      if (flashes[i].t >= 1) flashes.removeAt(i);
    }
    for (int i = sinks.length - 1; i >= 0; i--) {
      sinks[i].t += dt / 0.35;
      if (sinks[i].t >= 1) sinks.removeAt(i);
    }
  }

  void spark(
      double x, double y, double strength, Color color, math.Random rng) {
    if (!fancy) return;
    final int n = strength > 1600 ? 9 : (strength > 700 ? 6 : 3);
    for (int k = 0; k < n; k++) {
      final double a = rng.nextDouble() * math.pi * 2;
      final double sp = 60 +
          rng.nextDouble() * (strength * 0.12).clamp(40.0, 260.0).toDouble();
      particles.add(PoolParticle(x, y, math.cos(a) * sp, math.sin(a) * sp,
          0.25 + rng.nextDouble() * 0.3, color));
    }
    if (particles.length > 120)
      particles.removeRange(0, particles.length - 120);
  }

  void repaint() => notifyListeners();
}

/// Ball palette (index = ball id, 9..15 reuse 1..7).
const List<Color> kPoolBallColors = <Color>[
  Color(0xFFF7F4EA), // cue
  Color(0xFFF6C21C), // 1 yellow
  Color(0xFF1F56D6), // 2 blue
  Color(0xFFE0262B), // 3 red
  Color(0xFF6A2BB8), // 4 purple
  Color(0xFFF57A12), // 5 orange
  Color(0xFF14935A), // 6 green
  Color(0xFF8E1F28), // 7 maroon
  Color(0xFF151518), // 8 black
  Color(0xFFF6C21C),
  Color(0xFF1F56D6),
  Color(0xFFE0262B),
  Color(0xFF6A2BB8),
  Color(0xFFF57A12),
  Color(0xFF14935A),
  Color(0xFF8E1F28),
];

Color poolBallColor(int id) => kPoolBallColors[(id < 0 || id > 15) ? 0 : id];
