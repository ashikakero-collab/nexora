import 'dart:math' as math;

import 'pool_config.dart';

/// One billiard ball. id 0 = cue ball, 1..7 solids, 8 = eight ball, 9..15 stripes.
class PoolBall {
  PoolBall({required this.id, required this.x, required this.y, this.vx = 0, this.vy = 0, this.pocketed = false, this.pocket = -1});

  final int id;
  double x;
  double y;
  double vx;
  double vy;
  bool pocketed;

  /// Index into [PoolConfig.pockets] when pocketed, otherwise -1.
  int pocket;

  bool get isCue => id == 0;
  bool get onTable => !pocketed;
  bool get moving => vx != 0 || vy != 0;

  PoolBall clone() => PoolBall(id: id, x: x, y: y, vx: vx, vy: vy, pocketed: pocketed, pocket: pocket);

  Map<String, dynamic> toJson() => <String, dynamic>{'id': id, 'x': x, 'y': y, 'p': pocketed ? pocket : -1};
}

/// Collision callback used only by the renderer for juice (never affects results).
typedef PoolImpactListener = void Function(double x, double y, double strength, bool cushion);
typedef PoolPocketListener = void Function(int ballId, int pocket);

/// Deterministic physics world for one shot. Tracks the events the 8-ball rules need.
class PoolWorld {
  PoolWorld(this.balls);

  /// Index == ball id (always 16 balls, pocketed ones are skipped).
  final List<PoolBall> balls;

  // shot events
  int firstContact = -1;
  bool railAfterContact = false;
  bool anyRail = false;
  final List<int> pocketedThisShot = <int>[];
  final Set<int> railBalls = <int>{};

  // simple cue spin state for the current shot
  double spin = 0; // +1 follow, -1 draw
  double side = 0; // -1 left, +1 right english
  bool _spinUsed = false;

  int steps = 0;
  bool done = false;

  PoolImpactListener? onImpact;
  PoolPocketListener? onPocket;

  PoolBall get cue => balls[0];

  void resetEvents() {
    firstContact = -1;
    railAfterContact = false;
    anyRail = false;
    pocketedThisShot.clear();
    railBalls.clear();
    steps = 0;
    done = false;
    _spinUsed = false;
  }

  /// Launch the cue ball. dir must be (approximately) unit length.
  void strike(double dirX, double dirY, double power, double spinV, double sideV) {
    resetEvents();
    final double len = math.sqrt(dirX * dirX + dirY * dirY);
    final double dx = len > 0 ? dirX / len : 0;
    final double dy = len > 0 ? dirY / len : -1;
    double p = power;
    if (p > 1) p = 1;
    if (p < 0) p = 0;
    final double speed = p * PoolConfig.maxShotSpeed;
    cue.vx = dx * speed;
    cue.vy = dy * speed;
    spin = _clamp1(spinV);
    side = _clamp1(sideV);
  }

  static double _clamp1(double v) => v > 1 ? 1 : (v < -1 ? -1 : v);

  bool get settled {
    for (int i = 0; i < balls.length; i++) {
      final PoolBall b = balls[i];
      if (!b.pocketed && (b.vx != 0 || b.vy != 0)) return false;
    }
    return true;
  }

  /// One fixed step of 1/120 s. Returns true when the shot has finished.
  bool tick() {
    if (done) return true;
    for (int s = 0; s < PoolConfig.substeps; s++) {
      _substep(PoolConfig.dt / PoolConfig.substeps);
    }
    steps++;
    if (settled || steps >= PoolConfig.maxSteps) {
      if (steps >= PoolConfig.maxSteps) {
        for (int i = 0; i < balls.length; i++) {
          balls[i].vx = 0;
          balls[i].vy = 0;
        }
      }
      done = true;
    }
    return done;
  }

  void runToEnd() {
    while (!tick()) {}
  }

  void _substep(double h) {
    const double s2 = PoolConfig.stopSpeed * PoolConfig.stopSpeed;
    final double dec = PoolConfig.rollDecel * h;
    final double drag = PoolConfig.linearDrag * h;
    // 1) integrate + friction
    for (int i = 0; i < balls.length; i++) {
      final PoolBall b = balls[i];
      if (b.pocketed) continue;
      if (b.vx == 0 && b.vy == 0) continue;
      b.x += b.vx * h;
      b.y += b.vy * h;
      final double sp2 = b.vx * b.vx + b.vy * b.vy;
      final double sp = math.sqrt(sp2);
      final double ns = sp - dec - drag * sp;
      if (ns <= 0 || ns * ns < s2) {
        b.vx = 0;
        b.vy = 0;
      } else {
        final double k = ns / sp;
        b.vx *= k;
        b.vy *= k;
      }
    }
    // 2) ball-ball pairs (i < j)
    for (int i = 0; i < balls.length; i++) {
      final PoolBall a = balls[i];
      if (a.pocketed) continue;
      for (int j = i + 1; j < balls.length; j++) {
        final PoolBall b = balls[j];
        if (b.pocketed) continue;
        _pair(a, b);
      }
    }
    // 3) cushions
    final List<List<double>> segs = PoolConfig.cushions;
    for (int i = 0; i < balls.length; i++) {
      final PoolBall b = balls[i];
      if (b.pocketed) continue;
      for (int k = 0; k < segs.length; k++) {
        final List<double> sg = segs[k];
        _segment(b, sg[0], sg[1], sg[2], sg[3]);
      }
    }
    // 4) pockets
    for (int i = 0; i < balls.length; i++) {
      final PoolBall b = balls[i];
      if (b.pocketed) continue;
      _pocketCheck(b);
    }
  }

  void _pair(PoolBall a, PoolBall b) {
    final double dx = b.x - a.x, dy = b.y - a.y;
    const double minD = PoolConfig.ballR * 2;
    final double d2 = dx * dx + dy * dy;
    if (d2 >= minD * minD) return;
    double nx = 1, ny = 0, d = 0;
    if (d2 > 0) {
      d = math.sqrt(d2);
      nx = dx / d;
      ny = dy / d;
    }
    final double overlap = minD - d;
    a.x -= nx * overlap * 0.5;
    a.y -= ny * overlap * 0.5;
    b.x += nx * overlap * 0.5;
    b.y += ny * overlap * 0.5;
    final double rv = (b.vx - a.vx) * nx + (b.vy - a.vy) * ny;
    if (rv >= 0) return;
    // the cue ball's first contact
    if (firstContact < 0) {
      if (a.id == 0) {
        firstContact = b.id;
      } else if (b.id == 0) {
        firstContact = a.id;
      }
    }
    PoolBall? cueBall;
    double cvx = 0, cvy = 0, csp = 0;
    if (!_spinUsed && spin != 0 && (a.id == 0 || b.id == 0)) {
      cueBall = a.id == 0 ? a : b;
      cvx = cueBall.vx;
      cvy = cueBall.vy;
      csp = math.sqrt(cvx * cvx + cvy * cvy);
    }
    // equal masses
    final double j = -(1 + PoolConfig.eBall) * rv * 0.5;
    a.vx -= j * nx;
    a.vy -= j * ny;
    b.vx += j * nx;
    b.vy += j * ny;
    if (cueBall != null && csp > 0) {
      _spinUsed = true;
      final double add = spin * PoolConfig.followFactor * csp;
      cueBall.vx += cvx / csp * add;
      cueBall.vy += cvy / csp * add;
      _capSpeed(cueBall);
    }
    final PoolImpactListener? l = onImpact;
    if (l != null) l(a.x + nx * PoolConfig.ballR, a.y + ny * PoolConfig.ballR, -rv, false);
  }

  void _segment(PoolBall b, double x1, double y1, double x2, double y2) {
    final double ex = x2 - x1, ey = y2 - y1;
    final double el2 = ex * ex + ey * ey;
    double t = el2 > 0 ? ((b.x - x1) * ex + (b.y - y1) * ey) / el2 : 0;
    if (t < 0) t = 0;
    if (t > 1) t = 1;
    final double qx = x1 + ex * t, qy = y1 + ey * t;
    final double dx = b.x - qx, dy = b.y - qy;
    final double d2 = dx * dx + dy * dy;
    const double r = PoolConfig.ballR;
    if (d2 >= r * r || d2 == 0) return;
    final double d = math.sqrt(d2);
    final double nx = dx / d, ny = dy / d;
    b.x = qx + nx * r;
    b.y = qy + ny * r;
    final double vn = b.vx * nx + b.vy * ny;
    if (vn >= 0) return;
    b.vx -= (1 + PoolConfig.eCushion) * vn * nx;
    b.vy -= (1 + PoolConfig.eCushion) * vn * ny;
    if (b.id == 0 && side != 0) {
      // tangent (rotate normal 90 degrees); english bends the rebound.
      final double tx = -ny, ty = nx;
      final double add = side * PoolConfig.sideFactor * (-vn);
      b.vx += tx * add;
      b.vy += ty * add;
      side = side * 0.5;
      _capSpeed(b);
    }
    anyRail = true;
    railBalls.add(b.id);
    if (firstContact >= 0) railAfterContact = true;
    final PoolImpactListener? l = onImpact;
    if (l != null) l(qx, qy, -vn, true);
  }

  void _capSpeed(PoolBall b) {
    final double s2 = b.vx * b.vx + b.vy * b.vy;
    const double m = PoolConfig.maxShotSpeed;
    if (s2 > m * m) {
      final double k = m / math.sqrt(s2);
      b.vx *= k;
      b.vy *= k;
    }
  }

  void _pocketCheck(PoolBall b) {
    const double r = PoolConfig.ballR;
    int hit = -1;
    for (int p = 0; p < PoolConfig.pockets.length; p++) {
      final List<double> pc = PoolConfig.pockets[p];
      final double dx = b.x - pc[0], dy = b.y - pc[1];
      final double cr = PoolConfig.captureR(p);
      if (dx * dx + dy * dy < cr * cr) {
        hit = p;
        break;
      }
    }
    if (hit < 0) {
      // safety: a ball that slipped past the jaws is pocketed in the nearest pocket.
      if (b.x < -r || b.x > PoolConfig.tableW + r || b.y < -r || b.y > PoolConfig.tableH + r) {
        hit = nearestPocket(b.x, b.y);
      }
    }
    if (hit < 0) return;
    b.pocketed = true;
    b.pocket = hit;
    b.vx = 0;
    b.vy = 0;
    b.x = PoolConfig.pockets[hit][0];
    b.y = PoolConfig.pockets[hit][1];
    pocketedThisShot.add(b.id);
    final PoolPocketListener? l = onPocket;
    if (l != null) l(b.id, hit);
  }

  static int nearestPocket(double x, double y) {
    int best = 0;
    double bd = double.infinity;
    for (int p = 0; p < PoolConfig.pockets.length; p++) {
      final double dx = x - PoolConfig.pockets[p][0], dy = y - PoolConfig.pockets[p][1];
      final double d = dx * dx + dy * dy;
      if (d < bd) {
        bd = d;
        best = p;
      }
    }
    return best;
  }

  /// Round positions to 1/1000 and zero velocities (end of every shot).
  void snap() {
    for (int i = 0; i < balls.length; i++) {
      final PoolBall b = balls[i];
      b.x = (b.x * 1000 + 0.5).floor() / 1000;
      b.y = (b.y * 1000 + 0.5).floor() / 1000;
      b.vx = 0;
      b.vy = 0;
    }
  }
}

/// FNV-1a over rounded positions + pocket flags (client/server match check).
int poolStateHash(List<PoolBall> bs) {
  int h = 2166136261;
  void mix(int v) {
    h = (h ^ (v & 0xFFFFFFFF)) & 0xFFFFFFFF;
    h = (h * 16777619) & 0xFFFFFFFF;
  }

  for (int i = 0; i < bs.length; i++) {
    mix((bs[i].x * 1000 + 0.5).floor());
    mix((bs[i].y * 1000 + 0.5).floor());
    mix(bs[i].pocketed ? bs[i].pocket + 1 : 0);
  }
  return h & 0xFFFFFFFF;
}

/// Standard rack: apex on the foot spot pointing at the breaker, 8 in the centre,
/// one solid and one stripe on the back corners.
List<PoolBall> poolRackBalls() {
  const double r = PoolConfig.ballR + 0.15;
  const double rowH = r * 1.7320508075688772;
  const List<List<int>> rows = <List<int>>[
    <int>[1],
    <int>[9, 2],
    <int>[10, 8, 3],
    <int>[11, 7, 14, 4],
    <int>[5, 13, 15, 6, 12],
  ];
  final List<PoolBall> out = List<PoolBall>.generate(16, (int i) => PoolBall(id: i, x: 0, y: 0));
  out[0].x = PoolConfig.breakCueX;
  out[0].y = PoolConfig.breakCueY;
  for (int i = 0; i < rows.length; i++) {
    for (int j = 0; j < rows[i].length; j++) {
      final PoolBall b = out[rows[i][j]];
      b.x = PoolConfig.footSpotX + (j * 2 - i) * r;
      b.y = PoolConfig.footSpotY - i * rowH;
    }
  }
  return out;
}
