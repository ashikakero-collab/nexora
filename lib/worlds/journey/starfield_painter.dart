import 'dart:math' as math;

import 'package:flutter/material.dart';

/// میدان ستاره‌ی پروسیجرال (تا وقتی پس‌زمینه‌ی ستاره‌ای از پیش ساخته نشده).
/// [warp] بین ۰ و ۱: صفر یعنی ستاره‌های ثابت، یک یعنی کشیده‌شدن خطی (حس پرش).
/// جایگاه ستاره‌ها با seed ثابت است تا بین فریم‌ها نپرند.
class StarfieldPainter extends CustomPainter {
  StarfieldPainter({required this.count, this.warp = 0, this.seed = 7});

  final int count;
  final double warp;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rnd = math.Random(seed);
    final fill = Paint()..style = PaintingStyle.fill;
    final streak = Paint()..style = PaintingStyle.stroke;

    for (var i = 0; i < count; i++) {
      final x = rnd.nextDouble() * size.width;
      final y0 = rnd.nextDouble() * size.height;
      final radius = 0.4 + rnd.nextDouble() * 1.6;
      final depth = 0.2 + rnd.nextDouble() * 0.8; // عمق: ستاره‌ی نزدیک‌تر سریع‌تر
      final alpha = (90 + rnd.nextDouble() * 165).round();

      final shift = warp * depth * size.height;
      final y = (y0 + shift) % size.height;
      final tail = warp * depth * 42;

      if (tail > 1) {
        streak
          ..color = Color.fromARGB(alpha, 234, 246, 255)
          ..strokeWidth = radius;
        canvas.drawLine(Offset(x, y), Offset(x, y - tail), streak);
      } else {
        fill.color = Color.fromARGB(alpha, 234, 246, 255);
        canvas.drawCircle(Offset(x, y), radius, fill);
      }
    }
  }

  @override
  bool shouldRepaint(StarfieldPainter old) =>
      old.warp != warp || old.count != count || old.seed != seed;
}
