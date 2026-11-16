import 'dart:math' as math;

import 'carrom_config.dart';

/// Pure deterministic Carrom physics (no Flutter imports).
///
/// Determinism contract (same as Finger Soccer):
///  * fixed step dt = 1/120, semi-implicit Euler, fixed order: move -> pairs (i<j) -> cushions -> pockets.
///  * only + - * / and sqrt in the simulation (no sin/cos/pow), IEEE doubles.
///  * a piece slower than [CrConfig.stopSpeed] stops exactly (0); "settled" = all velocities exactly 0.
///  * after every shot positions are snapped to 1/1000 and velocities zeroed; [crStateHash] is FNV-1a.
///  * mirror: test/games/tools/carrom_ref.mjs (operation-for-operation) produces the golden vector.
///
/// Board geometry was measured on assets/games/carrom/board_nx_black_gold.webp with PIL:
/// cushions x 75..949, y 67..916; pocket holes centred ~(91.5|932.5, 88|895) r=54;
/// baselines through the red circles at y=186 / 797, red circle centres x=248 / 775.

enum CrKind { striker, white, black, queen }

class CrBody {
  CrBody({
    required this.id,
    required this.kind,
    required this.r,
    required this.m,
    required this.x,
    required this.y,
    this.vx = 0,
    this.vy = 0,
    this.onBoard = true,
  });

  final int id;
  final CrKind kind;
  final double r;
  final double m;
  double x;
  double y;
  double vx;
  double vy;

  /// false = pocketed (coins) or back in hand (striker between shots).
  bool onBoard;

  bool get isStriker => kind == CrKind.striker;
  bool get isQueen => kind == CrKind.queen;

  CrBody clone() => CrBody(id: id, kind: kind, r: r, m: m, x: x, y: y, vx: vx, vy: vy, onBoard: onBoard);

  Map<String, dynamic> toJson() => <String, dynamic>{'id': id, 'kind': kind.index, 'x': x, 'y': y, 'on': onBoard};
}

/// Render-only contact information (never changes a number of the simulation).
class CrImpact {
  const CrImpact({required this.x, required this.y, required this.strength, required this.wall});
  final double x;
  final double y;
  final double strength;
  final bool wall;
}

const double _k3 = 0.8660254037844386; // sqrt(3)/2 as a literal (no trig in the contract)

/// The standard break formation: queen in the centre, 6 coins around it, 12 in the outer ring
/// (hexagonal packing, 0.5 unit gaps). Body order: striker, 9 white, 9 black, queen.
List<CrBody> crInitialBodies() {
  const s = CrConfig.coinR * 2 + 0.5;
  const inner = <List<double>>[
    <double>[s, 0],
    <double>[s / 2, s * _k3],
    <double>[-s / 2, s * _k3],
    <double>[-s, 0],
    <double>[-s / 2, -s * _k3],
    <double>[s / 2, -s * _k3],
  ];
  const outer = <List<double>>[
    <double>[2 * s, 0],
    <double>[1.5 * s, s * _k3],
    <double>[s, 2 * s * _k3],
    <double>[0, 2 * s * _k3],
    <double>[-s, 2 * s * _k3],
    <double>[-1.5 * s, s * _k3],
    <double>[-2 * s, 0],
    <double>[-1.5 * s, -s * _k3],
    <double>[-s, -2 * s * _k3],
    <double>[0, -2 * s * _k3],
    <double>[s, -2 * s * _k3],
    <double>[1.5 * s, -s * _k3],
  ];
  final whites = <List<double>>[];
  final blacks = <List<double>>[];
  for (var i = 0; i < 6; i++) {
    (i % 2 == 0 ? whites : blacks).add(inner[i]);
  }
  for (var j = 0; j < 12; j++) {
    bool white;
    if (j % 2 == 0) {
      white = (j ~/ 2) % 2 == 1; // opposite colour to the inner coin on the same spoke
    } else {
      white = j == 1 || j == 5 || j == 9;
    }
    (white ? whites : blacks).add(outer[j]);
  }
  const cx = CrConfig.centerX, cy = CrConfig.centerY;
  final bs = <CrBody>[
    CrBody(id: 0, kind: CrKind.striker, r: CrConfig.strikerR, m: CrConfig.strikerMass, x: cx, y: CrConfig.baseline0, onBoard: false),
  ];
  for (var i = 0; i < 9; i++) {
    bs.add(CrBody(id: 1 + i, kind: CrKind.white, r: CrConfig.coinR, m: CrConfig.coinMass, x: cx + whites[i][0], y: cy + whites[i][1]));
  }
  for (var i = 0; i < 9; i++) {
    bs.add(CrBody(id: 10 + i, kind: CrKind.black, r: CrConfig.coinR, m: CrConfig.coinMass, x: cx + blacks[i][0], y: cy + blacks[i][1]));
  }
  bs.add(CrBody(id: 19, kind: CrKind.queen, r: CrConfig.coinR, m: CrConfig.coinMass, x: cx, y: cy));
  return bs;
}

void _collidePair(CrBody a, CrBody b, List<CrImpact>? sink) {
  final dx = b.x - a.x, dy = b.y - a.y;
  final minD = a.r + b.r;
  final d2 = dx * dx + dy * dy;
  if (d2 >= minD * minD) return;
  double nx = 1, ny = 0, d = 0;
  if (d2 > 0) {
    d = math.sqrt(d2);
    nx = dx / d;
    ny = dy / d;
  }
  final overlap = minD - d;
  final ia = 1 / a.m, ib = 1 / b.m, isum = ia + ib;
  a.x -= nx * overlap * (ia / isum);
  a.y -= ny * overlap * (ia / isum);
  b.x += nx * overlap * (ib / isum);
  b.y += ny * overlap * (ib / isum);
  final rv = (b.vx - a.vx) * nx + (b.vy - a.vy) * ny;
  if (rv < 0) {
    final j = -(1 + CrConfig.ePiece) * rv / isum;
    a.vx -= j * ia * nx;
    a.vy -= j * ia * ny;
    b.vx += j * ib * nx;
    b.vy += j * ib * ny;
    if (sink != null) sink.add(CrImpact(x: a.x + nx * a.r, y: a.y + ny * a.r, strength: -rv, wall: false));
  }
}

void _cushions(CrBody b, List<CrImpact>? sink) {
  const e = CrConfig.eWall;
  if (b.x - b.r < CrConfig.left) {
    b.x = CrConfig.left + b.r;
    if (b.vx < 0) {
      if (sink != null) sink.add(CrImpact(x: CrConfig.left, y: b.y, strength: -b.vx, wall: true));
      b.vx = -b.vx * e;
    }
  }
  if (b.x + b.r > CrConfig.right) {
    b.x = CrConfig.right - b.r;
    if (b.vx > 0) {
      if (sink != null) sink.add(CrImpact(x: CrConfig.right, y: b.y, strength: b.vx, wall: true));
      b.vx = -b.vx * e;
    }
  }
  if (b.y - b.r < CrConfig.top) {
    b.y = CrConfig.top + b.r;
    if (b.vy < 0) {
      if (sink != null) sink.add(CrImpact(x: b.x, y: CrConfig.top, strength: -b.vy, wall: true));
      b.vy = -b.vy * e;
    }
  }
  if (b.y + b.r > CrConfig.bottom) {
    b.y = CrConfig.bottom - b.r;
    if (b.vy > 0) {
      if (sink != null) sink.add(CrImpact(x: b.x, y: CrConfig.bottom, strength: b.vy, wall: true));
      b.vy = -b.vy * e;
    }
  }
}

/// Returns the pocket index whose capture circle contains (x, y), or -1.
int crPocketAt(double x, double y) {
  const c2 = CrConfig.captureR * CrConfig.captureR;
  for (var p = 0; p < CrConfig.pockets.length; p++) {
    final dx = x - CrConfig.pockets[p][0], dy = y - CrConfig.pockets[p][1];
    if (dx * dx + dy * dy < c2) return p;
  }
  return -1;
}

/// One fixed step. Ids pocketed during the step are appended to [pocketed] (in body order).
void crStep(List<CrBody> bs, List<int> pocketed, [List<CrImpact>? sink]) {
  const dt = CrConfig.dt;
  final k = math.max(0.0, 1 - CrConfig.drag * dt);
  const s2 = CrConfig.stopSpeed * CrConfig.stopSpeed;
  final n = bs.length;
  for (var i = 0; i < n; i++) {
    final b = bs[i];
    if (!b.onBoard) continue;
    b.x += b.vx * dt;
    b.y += b.vy * dt;
    b.vx *= k;
    b.vy *= k;
    if (b.vx * b.vx + b.vy * b.vy < s2) {
      b.vx = 0;
      b.vy = 0;
    }
  }
  for (var i = 0; i < n; i++) {
    final a = bs[i];
    if (!a.onBoard) continue;
    for (var j = i + 1; j < n; j++) {
      final b = bs[j];
      if (!b.onBoard) continue;
      if (a.vx == 0 && a.vy == 0 && b.vx == 0 && b.vy == 0) continue;
      _collidePair(a, b, sink);
    }
  }
  for (var i = 0; i < n; i++) {
    final b = bs[i];
    if (!b.onBoard) continue;
    _cushions(b, sink);
  }
  for (var i = 0; i < n; i++) {
    final b = bs[i];
    if (!b.onBoard) continue;
    if (crPocketAt(b.x, b.y) >= 0) {
      b.onBoard = false;
      b.vx = 0;
      b.vy = 0;
      pocketed.add(b.id);
    }
  }
}

bool crIsSettled(List<CrBody> bs) {
  for (var i = 0; i < bs.length; i++) {
    final b = bs[i];
    if (b.onBoard && (b.vx != 0 || b.vy != 0)) return false;
  }
  return true;
}

/// Incremental simulator: headless (runToEnd) or live (one tick per fixed dt).
class CrSimulator {
  CrSimulator(this.bodies, {this.impactSink});
  final List<CrBody> bodies;
  final List<CrImpact>? impactSink;
  final List<int> pocketed = <int>[];
  int steps = 0;
  bool done = false;

  bool tick() {
    if (done) return true;
    crStep(bodies, pocketed, impactSink);
    steps++;
    if (crIsSettled(bodies) || steps >= CrConfig.maxSteps) {
      done = true;
    }
    return done;
  }

  void runToEnd() {
    while (!tick()) {}
  }
}

double _snap(double v) => (v * 1000 + 0.5).floor() / 1000;

void crSnap(List<CrBody> bs) {
  for (var i = 0; i < bs.length; i++) {
    final b = bs[i];
    b.x = _snap(b.x);
    b.y = _snap(b.y);
    b.vx = 0;
    b.vy = 0;
  }
}

int crStateHash(List<CrBody> bs) {
  var h = 2166136261;
  void mix(int v) {
    h = (h ^ (v & 0xFFFFFFFF)) & 0xFFFFFFFF;
    h = (h * 16777619) & 0xFFFFFFFF;
  }

  for (var i = 0; i < bs.length; i++) {
    mix((bs[i].x * 1000 + 0.5).floor());
    mix((bs[i].y * 1000 + 0.5).floor());
    mix(bs[i].onBoard ? 1 : 0);
  }
  return h & 0xFFFFFFFF;
}

/// Is a disc of radius [r] at (x, y) clear of every on-board piece (except [ignoreId])?
bool crIsFree(List<CrBody> bs, double x, double y, double r, int ignoreId) {
  for (var i = 0; i < bs.length; i++) {
    final o = bs[i];
    if (!o.onBoard || o.id == ignoreId) continue;
    final dx = o.x - x, dy = o.y - y;
    final md = o.r + r + 1;
    if (dx * dx + dy * dy < md * md) return false;
  }
  return true;
}

/// Puts a pocketed coin back on the board: the centre if free, otherwise the nearest free point
/// of a square spiral (deterministic).
void crRespot(List<CrBody> bs, int id) {
  final b = bs[id];
  b.vx = 0;
  b.vy = 0;
  const step = CrConfig.coinR;
  for (var k = 0; k <= 18; k++) {
    for (var gy = -k; gy <= k; gy++) {
      for (var gx = -k; gx <= k; gx++) {
        if (gx.abs() != k && gy.abs() != k) continue;
        final x = CrConfig.centerX + gx * step;
        final y = CrConfig.centerY + gy * step;
        if (x - b.r < CrConfig.left + 40 || x + b.r > CrConfig.right - 40) continue;
        if (y - b.r < CrConfig.top + 40 || y + b.r > CrConfig.bottom - 40) continue;
        if (crIsFree(bs, x, y, b.r, id)) {
          b.x = x;
          b.y = y;
          b.onBoard = true;
          return;
        }
      }
    }
  }
  b.x = CrConfig.centerX;
  b.y = CrConfig.centerY;
  b.onBoard = true;
}
