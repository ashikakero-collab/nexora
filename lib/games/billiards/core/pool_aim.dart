import 'dart:math' as math;

import 'pool_config.dart';
import 'pool_physics.dart';

/// Result of casting the cue ball along an aim direction (ghost-ball guide).
class PoolAimPrediction {
  const PoolAimPrediction({
    required this.hitBall,
    required this.ghostX,
    required this.ghostY,
    required this.objDirX,
    required this.objDirY,
    required this.cueDirX,
    required this.cueDirY,
    required this.cutFactor,
  });

  /// Ball id of the first contact or -1 when the cue reaches a cushion first.
  final int hitBall;

  /// Cue-ball centre at the moment of contact (ghost ball) or at the cushion.
  final double ghostX;
  final double ghostY;

  /// Object-ball travel direction after impact (unit) — zero when no ball hit.
  final double objDirX;
  final double objDirY;

  /// Cue deflection (tangent line, unit) or the cushion reflection when no ball hit.
  final double cueDirX;
  final double cueDirY;

  /// 1 = full ball hit, 0 = thinnest cut. Scales the guide lengths.
  final double cutFactor;
}

/// Casts a ray of radius ballR from the cue ball. Pure geometry (no simulation).
PoolAimPrediction poolPredict(List<PoolBall> balls, double dirX, double dirY) {
  final PoolBall c = balls[0];
  final double len = math.sqrt(dirX * dirX + dirY * dirY);
  final double dx = len > 0 ? dirX / len : 0, dy = len > 0 ? dirY / len : -1;
  const double r = PoolConfig.ballR;
  double bestT = double.infinity;
  int best = -1;
  for (int i = 1; i < balls.length; i++) {
    final PoolBall b = balls[i];
    if (b.pocketed) continue;
    final double ox = b.x - c.x, oy = b.y - c.y;
    final double proj = ox * dx + oy * dy;
    if (proj <= 0) continue;
    final double perp2 = ox * ox + oy * oy - proj * proj;
    const double rr = 4 * r * r;
    if (perp2 >= rr) continue;
    final double t = proj - math.sqrt(rr - perp2);
    if (t < bestT && t >= -0.5) {
      bestT = t;
      best = i;
    }
  }
  // cushion (rectangle inset by r; ignores pocket mouths — guide only)
  double wallT = double.infinity;
  double wnx = 0, wny = 0;
  if (dx > 0) {
    final double t = (PoolConfig.tableW - r - c.x) / dx;
    if (t < wallT) {
      wallT = t;
      wnx = -1;
      wny = 0;
    }
  } else if (dx < 0) {
    final double t = (r - c.x) / dx;
    if (t < wallT) {
      wallT = t;
      wnx = 1;
      wny = 0;
    }
  }
  if (dy > 0) {
    final double t = (PoolConfig.tableH - r - c.y) / dy;
    if (t < wallT) {
      wallT = t;
      wnx = 0;
      wny = -1;
    }
  } else if (dy < 0) {
    final double t = (r - c.y) / dy;
    if (t < wallT) {
      wallT = t;
      wnx = 0;
      wny = 1;
    }
  }
  if (wallT < 0) wallT = 0;
  if (best >= 0 && bestT <= wallT) {
    final double t = bestT < 0 ? 0 : bestT;
    final double gx = c.x + dx * t, gy = c.y + dy * t;
    final PoolBall b = balls[best];
    double nx = b.x - gx, ny = b.y - gy;
    final double nl = math.sqrt(nx * nx + ny * ny);
    if (nl > 0) {
      nx /= nl;
      ny /= nl;
    }
    final double along = dx * nx + dy * ny; // cos of cut angle
    double tx = dx - along * nx, ty = dy - along * ny;
    final double tl = math.sqrt(tx * tx + ty * ty);
    if (tl > 1e-9) {
      tx /= tl;
      ty /= tl;
    } else {
      tx = 0;
      ty = 0;
    }
    return PoolAimPrediction(
      hitBall: best,
      ghostX: gx,
      ghostY: gy,
      objDirX: nx,
      objDirY: ny,
      cueDirX: tx,
      cueDirY: ty,
      cutFactor: along < 0 ? 0 : along,
    );
  }
  final double gx = c.x + dx * wallT, gy = c.y + dy * wallT;
  final double vn = dx * wnx + dy * wny;
  final double rx = dx - 2 * vn * wnx, ry = dy - 2 * vn * wny;
  return PoolAimPrediction(
    hitBall: -1,
    ghostX: gx,
    ghostY: gy,
    objDirX: 0,
    objDirY: 0,
    cueDirX: rx,
    cueDirY: ry,
    cutFactor: 0,
  );
}
