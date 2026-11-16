import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

/// Render-only juice for Carrom: particles, camera shake and screen flash.
/// Nothing here touches the deterministic simulation.
class CrParticle {
  CrParticle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.life,
    required this.size,
    required this.color,
  }) : maxLife = life;

  double x;
  double y;
  double vx;
  double vy;
  double life;
  final double maxLife;
  final double size;
  final Color color;

  double get t => maxLife <= 0 ? 0 : (life / maxLife);
}

class CrFx {
  CrFx({required this.enabled});

  /// fancyEffects: particles + shake. The goal flash/banner always show (lighter when off).
  final bool enabled;
  final List<CrParticle> particles = <CrParticle>[];
  final math.Random _rng = math.Random(11);

  double _shake = 0;
  double flash = 0;
  Color flashColor = const Color(0xFFFFFFFF);
  Offset shakeOffset = Offset.zero;

  void burst(double x, double y,
      {int count = 10,
      double speed = 260,
      Color color = const Color(0xFFFFFFFF),
      double size = 5,
      double life = 0.5}) {
    if (!enabled) return;
    if (particles.length > 260) return;
    for (var i = 0; i < count; i++) {
      final a = _rng.nextDouble() * math.pi * 2;
      final s = speed * (0.35 + _rng.nextDouble() * 0.65);
      particles.add(CrParticle(
        x: x,
        y: y,
        vx: math.cos(a) * s,
        vy: math.sin(a) * s,
        life: life * (0.6 + _rng.nextDouble() * 0.4),
        size: size * (0.5 + _rng.nextDouble() * 0.7),
        color: color,
      ));
    }
  }

  void shake(double amount) {
    if (!enabled) return;
    if (amount > _shake) _shake = amount;
  }

  void doFlash(Color c, double strength) {
    flashColor = c;
    flash = enabled ? strength : strength * 0.45;
  }

  void update(double dt) {
    for (var i = particles.length - 1; i >= 0; i--) {
      final p = particles[i];
      p.life -= dt;
      if (p.life <= 0) {
        particles.removeAt(i);
        continue;
      }
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.vx *= 0.93;
      p.vy *= 0.93;
    }
    if (_shake > 0.05) {
      shakeOffset = Offset((_rng.nextDouble() * 2 - 1) * _shake,
          (_rng.nextDouble() * 2 - 1) * _shake);
      _shake *= math.pow(0.0025, dt).toDouble();
    } else {
      _shake = 0;
      shakeOffset = Offset.zero;
    }
    if (flash > 0) {
      flash -= dt * 1.6;
      if (flash < 0) flash = 0;
    }
  }

  void paintParticles(Canvas canvas) {
    if (particles.isEmpty) return;
    final paint = Paint();
    for (final p in particles) {
      final a = p.t;
      paint.color = p.color.withOpacity((a * 0.95).clamp(0.0, 1.0).toDouble());
      canvas.drawCircle(Offset(p.x, p.y), p.size * (0.4 + 0.6 * a), paint);
    }
  }
}

/// Decodes an asset into a dart:ui image at a reduced size (memory friendly).
Future<ui.Image?> crLoadImage(String asset, int targetWidth) async {
  try {
    final ByteData data = await rootBundle.load(asset);
    final ui.Codec codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(),
        targetWidth: targetWidth);
    final ui.FrameInfo frame = await codec.getNextFrame();
    return frame.image;
  } catch (_) {
    return null;
  }
}
