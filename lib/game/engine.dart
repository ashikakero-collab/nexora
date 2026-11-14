// NEXORA physics engine.
//
// Two gameplay profiles (MatchCfg.profile):
//  * 'stars' (DEFAULT): Soccer Stars feel on the nx8 code path (heavy low-bounce discs, pool-ball ball), see kTuneStars.
//  * 'godot': the Godot build's "nx8" model (asbiulder/Nexora_godot src/game/engine.gd @48fcadf):
//    pool/foosball physics - shot speed linear in drag (SHOT_MAX), constant cloth friction, heavy discs (36) vs a
//    light ball (2), disc-disc hits only nudge (DISC_DISC_K), time-of-impact contacts, adaptive substeps,
//    cushions E .85 with angle in = out, sharp corners + corner nudge, softer light contacts (less jitter).
//  * 'classic': the line-for-line Dart port of the RN src/game/engine.ts (bit-parity with test/parity_test.dart).
//
// Classic profile notes (port of src/game/engine.ts):
// Fixed 240 Hz sub-stepping, impulse-based circle collisions with positional correction,
// rolling 3D ball rotation, render interpolation (prev -> current).
//
// Differences from the TS file are purely structural (no behavioural change):
//  * Math.random is injectable (`rand`) so tests and lockstep online play can seed it.
//  * Events, particles and trails live in pre-allocated pools: no allocation per frame.
//  * Math.hypot is reproduced bit-for-bit with V8's algorithm (`hyp`).
import 'dart:math' as math;
import 'dart:typed_data';

import 'data.dart';
import 'fdlibm.dart';

const double K = 1.27;
const double PR = 49;
const double BR = 25.5;
const double RC = 70;
const double LMAX = 210;
const double STEP = 1 / 240;
const double POST_R = 8;
const double HV = 8, PF1 = 430, PF2 = 1.0, PV0 = 520, EPP = .62, PCAP = 190;
const double BK = 1.9, BF = 175, BFV = 140, BVMAX = 1750, BSTOP = 26;
const double PK = 1.55, PFL = 300, PFV = 230, PSTOP = 20;
const double WALL_VOUT = 820, POST_VOUT = 900;

// =====================================================================================================
// PHYSICS TUNING TABLE for the nx8-family profiles ('stars' = default, 'godot').
// Every gameplay tunable lives here. Units: world px (pitch ~775 wide x ~1330 long), px/s, px/s^2, 1/s.
// Body speed decay per substep h:  v' = v - (fric * (v < vSettle ? settleK : 1) + drag * v) * h, stop below vStop.
// Glide distance from speed v (no walls):  d = v/drag - fric/drag^2 * ln(1 + drag*v/fric)   (d = v^2/2fric if drag = 0).
// =====================================================================================================
class PhysTune {
  final String name;
  // ---- bodies ----
  final double discR, ballR; // radii (disc 0.128 x pitch width, ball ~0.07)
  final double discM, ballM; // masses: only the ratio matters (impulse split along the normal)
  // ---- shot ----
  final double shotMax; // disc launch speed at full drag (LMAX), linear in drag length
  final double discVmax; // cap after power stat / VIP multiplier
  final bool powerGodot; // power-stat curve: true 0.72..1.44 (Godot), false 0.75..1.25 (TS)
  // ---- rolling / sliding friction ----
  final double discFric, discDrag; // disc: constant decel (px/s^2) + linear drag (1/s)
  final double ballFric, ballDrag; // ball: same model, lighter
  final double vStop; // a body whose speed falls below this stops
  final double vSettle, settleK; // below vSettle friction x settleK (no creeping / jiggle)
  final double vSafe; // numerical safety clamp on any speed
  // ---- contacts (impulse along the line of centres; tangential velocity untouched) ----
  final double eDiscDisc, eDiscBall; // restitution
  final double discDiscK; // fraction of the disc-disc impulse applied (Godot foosball nudge; 1 = true physics)
  final double eSoft, vSoft; // light contacts (normal speed < vSoft) blend from eSoft up to full e: less jitter
  // ---- cushions (walls, goal frame, posts) ----
  final double eWallBall, tWallBall; // ball: normal restitution, tangential speed kept
  final double eWallDisc, tWallDisc; // disc: normal restitution, tangential speed kept
  final double postR;
  final double cornerNudge; // px/s push out of a sharp corner for a still body jammed in it
  // ---- integration / visuals ----
  final double subPx; // max travel per substep (px) -> adaptive substeps
  final int subMax, stepCap; // substep cap per 240 Hz step; physics steps per frame
  final double rollK; // visual ball roll rate (render only)
  const PhysTune({
    required this.name,
    required this.discR,
    required this.ballR,
    required this.discM,
    required this.ballM,
    required this.shotMax,
    required this.discVmax,
    required this.powerGodot,
    required this.discFric,
    required this.discDrag,
    required this.ballFric,
    required this.ballDrag,
    required this.vStop,
    required this.vSettle,
    required this.settleK,
    required this.vSafe,
    required this.eDiscDisc,
    required this.eDiscBall,
    required this.discDiscK,
    required this.eSoft,
    required this.vSoft,
    required this.eWallBall,
    required this.tWallBall,
    required this.eWallDisc,
    required this.tWallDisc,
    required this.postR,
    required this.cornerNudge,
    required this.subPx,
    required this.subMax,
    required this.stepCap,
    required this.rollK,
  });
}

/// 'godot': Nexora_godot engine.gd nx8 @48fcadf, values copied as-is.
const kTuneGodot = PhysTune(
  name: 'godot',
  discR: 49, ballR: 27,
  discM: 36, ballM: 2, // 18:1 foosball discs
  shotMax: 1900, discVmax: 2000, powerGodot: true,
  discFric: 360, discDrag: 0, ballFric: 360, ballDrag: 0, // same cloth friction for everything
  vStop: 6, vSettle: 80, settleK: 2, vSafe: 4200,
  eDiscDisc: .95, eDiscBall: .70, discDiscK: .45, eSoft: .55, vSoft: 240,
  eWallBall: .85, tWallBall: .85, eWallDisc: .85, tWallDisc: .85, // whole vector x .85 (angle in = out)
  postR: 5, cornerNudge: 70,
  subPx: 4, subMax: 16, stepCap: 14, rollK: .6,
);

/// 'stars' (DEFAULT): Soccer Stars feel - heavy low-bounce plastic pucks that stop fairly quickly, a lighter ball that
/// rolls like a pool ball (constant rolling friction + small drag, lively 0.9 cushions) and glides a little further
/// than in Soccer Stars. Reasoning per value: /workspace/work/godot_vs_flutter_physics.md.
const kTuneStars = PhysTune(
  name: 'stars',
  discR: 49, ballR: 27,
  discM: 3, ballM: 1, // disc 3x the ball: a disc striking the ball sends it off at (1+e)*3/4 = 1.43x its speed
  shotMax: 1900, discVmax: 2000, powerGodot: true, // full drag ~1120 px disc glide (~0.85 pitch length)
  discFric: 900, discDrag: .6, // pucks: strong linear decel, full shot stops in ~1.6 s
  ballFric: 380, ballDrag: .6, // ball: 2.4x less decel than a disc -> ~1.7x the glide for the same speed
  vStop: 3, vSettle: 40, settleK: 2, vSafe: 4200, // gentle settle, no abrupt stop
  eDiscDisc: .88, eDiscBall: .90, discDiscK: 1, // equal-mass head-on: target gets 94% of the momentum
  eSoft: .5, vSoft: 120, // only very light touches are damped (anti-jitter)
  eWallBall: .90, tWallBall: .98, // pool cushion: 0.9 normal, tangential nearly kept
  eWallDisc: .55, tWallDisc: .85, // plastic puck on the rail: dead-ish bounce
  postR: 5, cornerNudge: 70,
  subPx: 4, subMax: 16, stepCap: 14, rollK: .6,
);

PhysTune? tuneFor(String profile) => switch (profile) {
      'classic' => null,
      'godot' => kTuneGodot,
      _ => kTuneStars,
    };

/// Shot power multiplier from the power stat (1..10): Godot 0.72..1.44, classic 0.75..1.25.
double powerMulGodot(double p) => .72 + (_min(10, _max(1, p)) - 1) / 9 * .72;

/// V8's Math.hypot for two arguments (Kahan-compensated, scaled by the max).
double hyp(double a, double b) {
  if (a.isNaN || b.isNaN) return double.nan;
  final x = a.abs(), y = b.abs();
  final m = x > y ? x : y;
  if (m == double.infinity) return double.infinity;
  if (m == 0) return 0;
  var sum = 0.0, comp = 0.0;
  var n = x / m;
  var summand = n * n - comp;
  var pre = sum + summand;
  comp = (pre - sum) - summand;
  sum = pre;
  n = y / m;
  summand = n * n - comp;
  pre = sum + summand;
  comp = (pre - sum) - summand;
  sum = pre;
  return math.sqrt(sum) * m;
}

/// V8's Math.hypot for three arguments.
double hyp3(double a, double b, double c) {
  final x = a.abs(), y = b.abs(), z = c.abs();
  var m = x > y ? x : y;
  if (z > m) m = z;
  if (m == double.infinity) return double.infinity;
  if (a.isNaN || b.isNaN || c.isNaN) return double.nan;
  if (m == 0) return 0;
  var sum = 0.0, comp = 0.0;
  var n = x / m;
  var summand = n * n - comp;
  var pre = sum + summand;
  comp = (pre - sum) - summand;
  sum = pre;
  n = y / m;
  summand = n * n - comp;
  pre = sum + summand;
  comp = (pre - sum) - summand;
  sum = pre;
  n = z / m;
  summand = n * n - comp;
  pre = sum + summand;
  comp = (pre - sum) - summand;
  sum = pre;
  return math.sqrt(sum) * m;
}

double _clamp(double v, double a, double b) => v < a ? a : (v > b ? b : v);
double _min(double a, double b) => a < b ? a : b;
double _max(double a, double b) => a > b ? a : b;

/// Math.round semantics of JS (round half up).
int jsRound(double v) => (v + 0.5).floorToDouble().toInt();

class DiscStats {
  final double power, accuracy;
  const DiscStats(this.power, this.accuracy);
  static const def = DiscStats(5, 5);
}

double powerMul(double p) => .75 + (_min(10, _max(1, p)) - 1) / 9 * .5;
double aimDevDeg(double a) => (10 - _min(10, _max(1, a))) / 9 * 4;
double aimPreview(double a) => .45 + (_min(10, _max(1, a)) - 1) / 9 * .75;

class MatchCfg {
  int field, ball;
  List<int> forms;
  bool ai;
  int aiLvl;
  int limit;
  double matchTime, turnTime;
  List<bool> vip;
  int first;
  List<DiscStats>? stats;

  /// Gameplay profile: 'stars' (default, Soccer Stars feel), 'godot' (Nexora_godot nx8 values) or 'classic' (RN TS engine).
  String profile;
  MatchCfg({
    required this.field,
    required this.ball,
    required this.forms,
    required this.ai,
    required this.aiLvl,
    required this.limit,
    required this.matchTime,
    required this.turnTime,
    required this.vip,
    required this.first,
    this.stats,
    this.profile = 'stars',
  });
}

class Goal {
  final int team;
  final double y, x1, x2;
  final int d;
  const Goal(this.team, this.y, this.x1, this.x2, this.d);
}

class Body {
  final int id;
  final int team; // 0 | 1 | 2 (ball)
  double x, y, px, py, vx = 0, vy = 0;
  final double r, im;
  double spin = 0, ang = 0;
  final Float64List R = Float64List.fromList([1, 0, 0, 0, 1, 0, 0, 0, 1]);
  double sq = 0, tvx = 0, tvy = 0, ramp = 0, boost = 0, vox = 0, voy = 0;
  Goal? gout;
  // per-disc motion trail: ring of at most 13 points (TS keeps <= 12 after shift)
  final Float64List trX = Float64List(16), trY = Float64List(16);
  int trStart = 0, trLen = 0;
  Body(this.x, this.y, this.team, this.r, double m, this.id)
      : px = x,
        py = y,
        im = 1 / m;

  void trPush(double x, double y) {
    final i = (trStart + trLen) & 15;
    trX[i] = x;
    trY[i] = y;
    trLen++;
  }

  void trShift() {
    if (trLen == 0) return;
    trStart = (trStart + 1) & 15;
    trLen--;
  }
}

enum Phase { aim, move, goal, over }

enum EvType { hit, wall, post, goal, turn, shot, end, clock }

class EngineEvent {
  EvType t = EvType.clock;
  bool ball = false;
  double power = 0;
  int team = 0;
  bool nogoal = false;
  int s0 = 0, s1 = 0;
  @override
  String toString() => '${t.name}(team:$team ball:$ball p:${power.toStringAsFixed(3)} ng:$nogoal $s0:$s1)';
}

class Drag {
  Body b;
  double sx, sy, cx, cy;
  bool ai;
  Drag(this.b, this.sx, this.sy, this.cx, this.cy, {this.ai = false});
}

class AiPlan {
  final Body b;
  final double dx, dy, l;
  double t;
  AiPlan(this.b, this.dx, this.dy, this.l, this.t);
}

class AimInfo {
  Body? b;
  double p = 0, ux = 0, uy = 0;
}

class _Cand {
  Body p;
  double dx, dy, sc, dist;
  int atk;
  _Cand(this.p, this.dx, this.dy, this.sc, this.dist, this.atk);
}

typedef Rand = double Function();

class Engine {
  late final Field f;
  double Fl = 0, Fr = 0, Ft = 0, Fb = 0;
  double CX = 0, CY = 0, KY = 0;
  late final List<Goal> goals;
  double GGw = 0, GGh = 0, GGx = 0;
  double DEPTH = 120;
  final List<Body> bodies = [];
  late Body ball;

  // ---- particles (struct of arrays) ----
  static const int maxParts = 640;
  final Float64List pX = Float64List(maxParts), pY = Float64List(maxParts), pVx = Float64List(maxParts), pVy = Float64List(maxParts);
  final Float64List pL = Float64List(maxParts), pM = Float64List(maxParts), pR = Float64List(maxParts), pG = Float64List(maxParts);
  final Int32List pC = Int32List(maxParts), pK = Int32List(maxParts);
  int nParts = 0;

  // ---- ball trail (oldest first) ----
  static const int maxTrail = 56;
  final Float64List tX = Float64List(maxTrail), tY = Float64List(maxTrail), tA = Float64List(maxTrail);
  int nTrail = 0;

  final List<int> score = [0, 0];
  int turn = 0;
  Phase phase = Phase.aim;
  int shots = 0;
  double idle = 0, pause = 0;
  int kick = 0;
  double acc = 0, slow = 0, flash = 0, cam = 0;
  final Float64List shake = Float64List(2), ripple = Float64List(2), rippleX = Float64List(2);
  double mleft = 0, tleft = 0;
  bool sudden = false;
  double aiT = 0;
  AiPlan? aiPlan;
  Drag? drag;

  // ---- events (pooled) ----
  final List<EngineEvent> _evPool = [];
  int eventCount = 0;
  EngineEvent event(int i) => _evPool[i];
  void clearEvents() => eventCount = 0;

  final MatchCfg cfg;
  double time = 0;
  int lastWho = 0;
  final List<bool> aiTeams = [false, false];
  double lastPower = 0, lastUx = 0, lastUy = 0, lastV = 0;
  Body? lastShot;

  /// Online lockstep client: run only the physics; phase/turn/score/reset come from the host.
  bool slave = false;
  final Rand rand;
  final Float64List _rs = Float64List(9);
  final AimInfo _aim = AimInfo();

  /// Tuning of the nx8-family profile in use (null for 'classic').
  late final PhysTune? _tune = tuneFor(cfg.profile);
  PhysTune get tu => _tune!;

  /// true for the nx8-family profiles ('stars', 'godot'); false for 'classic' (TS parity).
  late final bool godot = _tune != null;

  Engine(this.cfg, {Rand? rand}) : rand = rand ?? math.Random().nextDouble {
    f = (cfg.field >= 0 && cfg.field < kFields.length) ? kFields[cfg.field] : kFields[0];
    Fl = f.L + 4.0;
    Fr = f.R - 4.0;
    Ft = f.T + 4.0;
    Fb = f.B - 4.0;
    CX = (Fl + Fr) / 2;
    CY = (Ft + Fb) / 2;
    KY = f.cs.toDouble();
    final gi = kGS[f.gs]!;
    final gw = 2 * f.g / (gi[3] - gi[2]);
    GGw = gw;
    GGh = gw * gi[1] / gi[0] * 1.28;
    GGx = CX - f.g - gi[2] * gw;
    DEPTH = math.max(120, jsRound(GGh * .98)).toDouble();
    goals = [Goal(0, Ft, CX - f.g, CX + f.g, -1), Goal(1, Fb, CX - f.g, CX + f.g, 1)];
    mleft = cfg.matchTime;
    tleft = cfg.turnTime;
    reset(cfg.first);
  }

  EngineEvent _push(EvType t) {
    if (eventCount == _evPool.length) _evPool.add(EngineEvent());
    final e = _evPool[eventCount++];
    e.t = t;
    e.ball = false;
    e.power = 0;
    e.team = 0;
    e.nogoal = false;
    return e;
  }

  Body _mk(double x, double y, int team, double r, double m, int id) => Body(x, y, team, r, m, id);

  void reset(int kickTeam) {
    final Fw = Fr - Fl, Fh = Fb - Ft;
    bodies.clear();
    nTrail = 0;
    nParts = 0;
    slow = 0;
    cam = 0;
    for (var cm = 0; cm < 2; cm++) {
      final sl = slots(cfg.forms[cm]);
      for (var i = 0; i < sl.length; i++) {
        final nx = sl[i][0], ny = sl[i][1];
        final ins = (godot ? tu.discR : PR) + (godot ? 6 : 10);
        final x = Fl + ins + nx * (Fw - 2 * ins);
        final y = cm != 0 ? Ft + ny * Fh : Fb - ny * Fh;
        bodies.add(godot ? _mk(x, y, cm, tu.discR, tu.discM, cm * 20 + i) : _mk(x, y, cm, PR, 5, cm * 20 + i));
      }
    }
    ball = godot ? _mk(CX, KY, 2, tu.ballR, tu.ballM, 99) : _mk(CX, KY, 2, BR, 1.5, 99);
    bodies.add(ball);
    turn = kickTeam;
    phase = Phase.aim;
    drag = null;
    pause = 0;
    idle = 0;
    shots = 0;
    tleft = cfg.turnTime;
    aiT = 0;
    aiPlan = null;
    _push(EvType.turn).team = turn;
  }

  bool isAiTurn() => (cfg.ai && turn == 1) || aiTeams[turn];
  bool canControl() => phase == Phase.aim && !isAiTurn();

  // ---------- input ----------
  bool pick(double x, double y) {
    if (!canControl()) return false;
    Body? f;
    var bd = 1e9;
    for (final b in bodies) {
      if (b.team == turn && !identical(b, ball)) {
        final d = hyp(x - b.x, y - b.y);
        if (d < b.r + (godot ? 30 : 34) && d < bd) {
          f = b;
          bd = d;
        }
      }
    }
    if (f == null) return false;
    drag = Drag(f, f.x, f.y, x, y);
    return true;
  }

  void move(double x, double y) {
    final d = drag;
    if (d != null && !d.ai) {
      d.cx = x;
      d.cy = y;
    }
  }

  void release() {
    final d = drag;
    if (d == null || d.ai) return;
    drag = null;
    final dx = d.sx - d.cx, dy = d.sy - d.cy, l = hyp(dx, dy);
    if (l > 18 && phase == Phase.aim) fire(d.b, dx, dy, l, true);
  }

  void cancel() {
    if (drag != null && !drag!.ai) drag = null;
  }

  /// Aim info for the renderer; returns a shared (reused) object, or null when not dragging.
  AimInfo? aimInfo() {
    final d = drag;
    if (d == null) return null;
    final dx = d.sx - d.cx, dy = d.sy - d.cy, l = hyp(dx, dy);
    _aim.b = d.b;
    if (l < 18) {
      _aim.p = 0;
      _aim.ux = 0;
      _aim.uy = 0;
      return _aim;
    }
    _aim.p = _min(l, LMAX) / LMAX;
    _aim.ux = dx / l;
    _aim.uy = dy / l;
    return _aim;
  }

  DiscStats statsOf(int team) => cfg.stats?[team] ?? DiscStats.def;

  void fire(Body b, double dx, double dy, double l, [bool human = false]) {
    final p = _min(l, LMAX) / LMAX;
    final team = b.team;
    lastPower = p;
    final v = _shotSpeed(team, p);
    var ux = dx / l, uy = dy / l;
    if (human && cfg.stats != null) {
      final dev = aimDevDeg(statsOf(team).accuracy) * math.pi / 180;
      if (dev > 0) {
        final a = fatan2(uy, ux) + (rand() + rand() - 1) * dev;
        ux = fcos(a);
        uy = fsin(a);
      }
    }
    lastUx = ux;
    lastUy = uy;
    lastV = v;
    _launch(b, ux, uy, v);
  }

  /// Launch speed for drag power p (0..1): classic TS curve, or Godot's linear SHOT_MAX * p clamped to DISC_VMAX.
  double _shotSpeed(int team, double p) {
    if (godot) {
      var v = tu.shotMax * p;
      if (cfg.stats != null) {
        v *= tu.powerGodot ? powerMulGodot(statsOf(team).power) : powerMul(statsOf(team).power);
      } else if (cfg.vip[team]) {
        v *= 1.16;
      }
      return _min(v, tu.discVmax);
    }
    var v = (260 + 1085 * fpow(p, .8)) * K * 1.32;
    if (cfg.stats != null) {
      v *= powerMul(statsOf(team).power);
    } else if (cfg.vip[team]) {
      v *= 1.16;
    }
    return v;
  }

  /// Online lockstep client: replay a shot exactly as the host launched it (direction, speed, power).
  void fireRaw(Body b, double ux, double uy, double v, double p) {
    lastPower = p;
    lastUx = ux;
    lastUy = uy;
    lastV = v;
    _launch(b, ux, uy, v);
  }

  /// Online lockstep: apply a shot whose final direction (after the shooter's accuracy deviation) and power
  /// were decided elsewhere. Same arithmetic as [fire] without randomness, so every peer gets identical motion.
  void fireVec(Body b, double ux, double uy, double p) {
    final team = b.team;
    lastPower = p;
    final v = _shotSpeed(team, p);
    lastUx = ux;
    lastUy = uy;
    lastV = v;
    _launch(b, ux, uy, v);
  }

  /// Direction a human flick will actually take (accuracy deviation applied), for client-side prediction.
  (double, double) deviate(int team, double dx, double dy, double l) {
    var ux = dx / l, uy = dy / l;
    if (cfg.stats != null) {
      final dev = aimDevDeg(statsOf(team).accuracy) * math.pi / 180;
      if (dev > 0) {
        final a = fatan2(uy, ux) + (rand() + rand() - 1) * dev;
        ux = fcos(a);
        uy = fsin(a);
      }
    }
    return (ux, uy);
  }

  void _launch(Body b, double ux, double uy, double v) {
    final vx = ux * v, vy = uy * v;
    lastShot = b;
    if (godot) {
      // nx8: the disc leaves at full speed along the aim (no ramp/boost, no spin, no camera kick)
      b.vx = vx;
      b.vy = vy;
      b.ramp = 0;
      b.boost = 0;
      b.tvx = 0;
      b.tvy = 0;
      b.spin = 0;
      if (b.team != turn) turn = b.team;
      phase = Phase.move;
      idle = 0;
      shots++;
      drag = null;
      lastWho = b.team;
      _push(EvType.shot).team = b.team;
      return;
    }
    b.tvx = vx * 1.02;
    b.tvy = vy * 1.02;
    b.ramp = .06;
    b.vx = vx * .5;
    b.vy = vy * .5;
    b.boost = .22;
    phase = Phase.move;
    idle = 0;
    shots++;
    drag = null;
    cam = _max(cam, .18);
    lastWho = b.team;
    _push(EvType.shot).team = b.team;
  }

  // ---------- simulation ----------
  double _eN(bool bl, double vn) => bl
      ? _min(.64 - .24 * _clamp((vn - 270 * K) / (730 * K), 0, 1), WALL_VOUT * K / _max(1, vn))
      : _min(.72, WALL_VOUT * 1.4 * K / _max(1, vn));

  void _corner(Body b, double cx, double cy, double sx, double sy, bool bl) {
    if ((b.x - cx) * sx < 0 && (b.y - cy) * sy < 0) {
      final dx = b.x - cx, dy = b.y - cy, d = hyp(dx, dy), lim = RC - b.r;
      if (d > lim && d > 0) {
        final nx = dx / d, ny = dy / d, vn = b.vx * nx + b.vy * ny;
        b.x = cx + nx * lim;
        b.y = cy + ny * lim;
        if (vn > 0) {
          final ec = _eN(bl, vn);
          b.vx -= (1 + ec) * vn * nx;
          b.vy -= (1 + ec) * vn * ny;
        }
      }
    }
  }

  void _walls(Body b) {
    if (!identical(b, ball) && b.gout != null) {
      final g = b.gout!, dq = g.d * (b.y - g.y);
      if (dq > -b.r * 1.05) {
        b.vy = -g.d * 270 * K;
        b.vx *= .6;
      } else {
        b.vy = 0;
        b.vx *= .2;
        b.gout = null;
      }
    }
    final bl = identical(b, ball), r = b.r, vs = hyp(b.vx, b.vy);
    if (b.x - r < Fl) {
      b.x = Fl + r;
      if (b.vx < 0) {
        if (bl && vs > 200) _push(EvType.wall).power = vs / 1800;
        b.vx *= -_eN(bl, -b.vx);
        b.spin += b.vy / r * .05;
      }
    }
    if (b.x + r > Fr) {
      b.x = Fr - r;
      if (b.vx > 0) {
        if (bl && vs > 200) _push(EvType.wall).power = vs / 1800;
        b.vx *= -_eN(bl, b.vx);
        b.spin -= b.vy / r * .05;
      }
    }
    for (var gi = 0; gi < 2; gi++) {
      final g = goals[gi];
      final dp = g.d * (b.y - g.y);
      if (dp <= -r) continue;
      final lo = g.x1 + (bl ? 0 : r), hi = g.x2 - (bl ? 0 : r);
      final inside = bl ? (b.x > g.x1 && b.x < g.x2) : (dp > 0 || (b.x >= lo && b.x <= hi));
      if (inside) {
        final gl = phase == Phase.goal && bl;
        final eb = gl ? .2 : _eN(bl, b.vy.abs());
        final back = g.y + g.d * DEPTH;
        if (!bl && dp > r * .3 && vs < 150 * K && b.gout == null) b.gout = g;
        if (dp + r > DEPTH) {
          b.y = back - g.d * r;
          b.vy = -g.d * b.vy.abs() * eb;
          if (gl) b.vx *= .6;
        }
        if (dp > (bl ? r * .6 : 0)) {
          final ee = gl ? .3 : _eN(bl, b.vx.abs());
          if (b.x < g.x1 + r) {
            b.x = g.x1 + r;
            if (b.vx < 0) b.vx *= -ee;
          }
          if (b.x > g.x2 - r) {
            b.x = g.x2 - r;
            if (b.vx > 0) b.vx *= -ee;
          }
        }
      } else {
        if (bl && vs > 200 && g.d * b.vy > 0) _push(EvType.wall).power = vs / 1800;
        b.y = g.y - g.d * r;
        if (g.d * b.vy > 0) b.vy = -g.d * b.vy.abs() * _eN(bl, b.vy.abs());
        b.spin += g.d * b.vx / r * .05;
      }
    }
    _corner(b, Fl + RC, Ft + RC, 1, 1, bl);
    _corner(b, Fr - RC, Ft + RC, -1, 1, bl);
    _corner(b, Fl + RC, Fb - RC, 1, -1, bl);
    _corner(b, Fr - RC, Fb - RC, -1, -1, bl);
  }

  void _post(Body b, double px, double py) {
    final dx = b.x - px, dy = b.y - py, d = hyp(dx, dy), m = b.r + POST_R;
    if (d >= m || d == 0) return;
    final nx = dx / d, ny = dy / d, vn = b.vx * nx + b.vy * ny;
    b.x = px + nx * m;
    b.y = py + ny * m;
    if (vn < 0) {
      final kp = 1 + _min(.62 - .14 * _min(1, -vn / (2000 * K)), POST_VOUT * K / _max(1, -vn));
      b.vx -= kp * vn * nx;
      b.vy -= kp * vn * ny;
      if (identical(b, ball)) _push(EvType.post).power = -vn / 1800;
      if (identical(b, ball) && -vn > 900 * K) cam = _max(cam, .25);
    }
  }

  static const _hitCols = [0xffffffff, 0xff9fe8ff, 0xff5cb6ff];
  static const _goalCols = [0xffffd23a, 0xffffffff, 0xff3bd0ff, 0xffff4a7a, 0xff7bff5a];

  void _hit(Body a, Body b) {
    var dx = b.x - a.x, dy = b.y - a.y, d = hyp(dx, dy);
    final m = a.r + b.r;
    if (d >= m) return;
    if (d < 1e-4) {
      dx = 1;
      dy = 0;
      d = 1;
    }
    final ball = this.ball, nx = dx / d, ny = dy / d, sm = a.im + b.im;
    final isB = identical(a, ball) || identical(b, ball);
    var ka = isB && !identical(a, ball) ? 1 / HV : 1.0, kb = isB && !identical(b, ball) ? 1 / HV : 1.0;
    if (!isB) {
      final sa = hyp(a.vx, a.vy), sb = hyp(b.vx, b.vy);
      if (sa > sb) {
        kb = .85;
      } else {
        ka = .85;
      }
    }
    var wa = a.im / sm * ka, wb = b.im / sm * kb;
    if (isB) {
      if (identical(a, ball)) {
        wa = 1 - wb;
      } else {
        wb = 1 - wa;
      }
    }
    final pen = _max(m - d - .3, 0) * .9;
    a.x -= nx * pen * wa;
    a.y -= ny * pen * wa;
    b.x += nx * pen * wb;
    b.y += ny * pen * wb;
    a.vox = _clamp(a.vox + nx * pen * wa, -9, 9);
    a.voy = _clamp(a.voy + ny * pen * wa, -9, 9);
    b.vox = _clamp(b.vox - nx * pen * wb, -9, 9);
    b.voy = _clamp(b.voy - ny * pen * wb, -9, 9);
    final vn = (b.vx - a.vx) * nx + (b.vy - a.vy) * ny;
    if (vn >= 0) return;
    final e = vn < -40 * K ? (isB ? .68 - .12 * _clamp((-vn - 500 * K) / (1200 * K), 0, 1) : EPP) : 0.0;
    final j = -(1 + e) * vn / sm;
    final Body? pa = isB ? (identical(a, ball) ? b : a) : null;
    final pre = pa != null ? hyp(pa.vx, pa.vy) : 0.0;
    a.vx -= j * nx * a.im * ka;
    a.vy -= j * ny * a.im * ka;
    b.vx += j * nx * b.im * kb;
    b.vy += j * ny * b.im * kb;
    if (pa != null && pre < 260 * K) {
      final ps = hyp(pa.vx, pa.vy), cp = PCAP * K;
      if (ps > cp) {
        pa.vx *= cp / ps;
        pa.vy *= cp / ps;
      }
    }
    if (vn < -120 * K) {
      final ev = _push(EvType.hit);
      ev.ball = isB;
      ev.power = -vn / 1900;
      if (!isB && vn < -420 * K) {
        final q = _min(1, -vn / (1500 * K));
        a.sq = _max(a.sq, q);
        b.sq = _max(b.sq, q);
      }
    }
    if (isB) {
      ball.spin += (identical(ball, b) ? 1 : -1) * (-ny * (b.vx - a.vx) + nx * (b.vy - a.vy)) / ball.r * .3;
      ball.spin = _clamp(ball.spin, -34, 34);
      final pw = _min(1, -vn / (1700 * K));
      if (pw > .2) {
        final o = identical(ball, b) ? a : b;
        ball.sq = _max(ball.sq, pw);
        o.sq = _max(o.sq, pw * .7);
        cam = _max(cam, pw * .4);
        final cx = (a.x + b.x) / 2, cy = (a.y + b.y) / 2;
        burst(cx, cy, jsRound(6 + pw * 10), 260 + pw * 300, _hitCols, .35, 2);
      }
    }
  }

  void _rotate(Float64List R, double wx, double wy, double wz, double dt) {
    final w = hyp3(wx, wy, wz), th = w * dt;
    if (th < 1e-7) return;
    final ax = wx / w, ay = wy / w, az = wz / w, c = fcos(th), s = fsin(th), t = 1 - c;
    final m0 = t * ax * ax + c, m1 = t * ax * ay - s * az, m2 = t * ax * az + s * ay;
    final m3 = t * ax * ay + s * az, m4 = t * ay * ay + c, m5 = t * ay * az - s * ax;
    final m6 = t * ax * az - s * ay, m7 = t * ay * az + s * ax, m8 = t * az * az + c;
    final r = _rs;
    for (var i = 0; i < 9; i++) {
      r[i] = R[i];
    }
    R[0] = m0 * r[0] + m1 * r[3] + m2 * r[6];
    R[1] = m0 * r[1] + m1 * r[4] + m2 * r[7];
    R[2] = m0 * r[2] + m1 * r[5] + m2 * r[8];
    R[3] = m3 * r[0] + m4 * r[3] + m5 * r[6];
    R[4] = m3 * r[1] + m4 * r[4] + m5 * r[7];
    R[5] = m3 * r[2] + m4 * r[5] + m5 * r[8];
    R[6] = m6 * r[0] + m7 * r[3] + m8 * r[6];
    R[7] = m6 * r[1] + m7 * r[4] + m8 * r[7];
    R[8] = m6 * r[2] + m7 * r[5] + m8 * r[8];
    final l0 = hyp3(R[0], R[1], R[2]);
    R[0] /= l0;
    R[1] /= l0;
    R[2] /= l0;
  }

  void _sim(double dt) {
    if (godot) {
      _sim8(dt);
      return;
    }
    final ball = this.ball;
    for (final b in bodies) {
      if (b.ramp > 0) {
        final k = _min(1, dt / b.ramp);
        b.vx += (b.tvx - b.vx) * k;
        b.vy += (b.tvy - b.vy) * k;
        b.ramp -= dt;
        if (b.ramp <= 0) b.ramp = 0;
      }
      if (b.vox != 0 || b.voy != 0) {
        final q = 1 - _min(1, dt * 15);
        b.vox *= q;
        b.voy *= q;
        if (b.vox.abs() < .04) b.vox = 0;
        if (b.voy.abs() < .04) b.voy = 0;
      }
      b.x += b.vx * dt;
      b.y += b.vy * dt;
      final sp = hyp(b.vx, b.vy), bl = identical(b, ball);
      if (sp > 0) {
        if (bl) {
          var ns = sp * fexp(-BK * dt) - BF * K * _min(1, sp / (BFV * K)) * dt;
          if (ns < BSTOP * K) {
            b.vx = b.vy = 0;
            b.vox = b.voy = 0;
          } else {
            ns = _min(ns, BVMAX * K);
            final k = ns / sp;
            b.vx *= k;
            b.vy *= k;
          }
        } else {
          final fb = b.boost > 0 ? .35 : 1.0;
          if (b.boost > 0) b.boost -= dt;
          var ns = sp * fexp(-PK * fb * dt) - PFL * K * _min(1, sp / (PFV * K)) * fb * dt;
          if (ns < PSTOP * K && b.ramp <= 0) {
            b.vx = b.vy = 0;
          } else {
            ns = _max(0, _min(ns, 2800 * K));
            final k = ns / sp;
            b.vx *= k;
            b.vy *= k;
          }
        }
      }
      if (bl) {
        final sp2 = hyp(b.vx, b.vy);
        b.spin *= 1 - (sp2 > 0 ? 1.05 : 3.2) * dt;
        if (b.spin.abs() < .02) b.spin = 0;
        final roll = .95 / b.r;
        if (sp2 > 0 || b.spin != 0) _rotate(b.R, -b.vy * roll, b.vx * roll, b.spin * .55, dt);
        b.ang += b.spin * dt;
      } else {
        b.spin *= 1 - 2.6 * dt;
        b.ang += b.spin * dt;
      }
      b.sq *= 1 - 9 * dt;
      _walls(b);
    }
    final B = bodies, n = B.length;
    for (var it = 0; it < 2; it++) {
      for (var a = 0; a < n; a++) {
        for (var c = a + 1; c < n; c++) {
          _hit(B[a], B[c]);
        }
      }
    }
    for (var gi = 0; gi < 2; gi++) {
      final g = goals[gi];
      for (final b in B) {
        _post(b, g.x1, g.y);
        _post(b, g.x2, g.y);
      }
    }
    for (final b in B) {
      _walls(b);
    }
    if (phase == Phase.move && !slave) {
      for (var gi = 0; gi < 2; gi++) {
        final g = goals[gi];
        if (ball.x > g.x1 && ball.x < g.x2 && (g.d < 0 ? ball.y < g.y - ball.r * .8 : ball.y > g.y + ball.r * .8)) _scored(g.team);
      }
    }
  }

  // =====================================================================================================
  // nx8-family profiles ('stars', 'godot'): pool/foosball model, ported from Nexora_godot src/game/engine.gd (_sim8 & co.).
  // Uses math.sqrt (IEEE, same as GDScript sqrt) so results track the Godot build to rounding.
  // =====================================================================================================

  void _gcap(Body b) {
    final s2 = b.vx * b.vx + b.vy * b.vy;
    if (s2 > tu.vSafe * tu.vSafe) {
      final k = tu.vSafe / math.sqrt(s2);
      b.vx *= k;
      b.vy *= k;
    }
  }

  /// time-of-impact contact: rewind the pair to first touch, apply a mass-weighted impulse, advance again.
  void _hit8(Body a, Body b, double h) {
    var dx = b.x - a.x, dy = b.y - a.y;
    var dd = dx * dx + dy * dy;
    final m = a.r + b.r;
    if (dd >= m * m) return;
    final ball = this.ball;
    final rvx = b.vx - a.vx, rvy = b.vy - a.vy;
    final dv = dx * rvx + dy * rvy;
    final sm = a.im + b.im;
    final isB = identical(a, ball) || identical(b, ball);
    var vn = 0.0;
    if (dv < 0) {
      final vv = rvx * rvx + rvy * rvy;
      var s = 0.0;
      if (vv > 1e-9) {
        s = (dv + math.sqrt(_max(0, dv * dv - vv * (dd - m * m)))) / vv;
        s = _clamp(s, 0, h);
      }
      a.x -= a.vx * s;
      a.y -= a.vy * s;
      b.x -= b.vx * s;
      b.y -= b.vy * s;
      dx = b.x - a.x;
      dy = b.y - a.y;
      var d = math.sqrt(dx * dx + dy * dy);
      if (d < 1e-4) {
        dx = 0;
        dy = -1;
        d = 1;
      }
      final nx = dx / d, ny = dy / d;
      vn = rvx * nx + rvy * ny;
      if (vn < 0) {
        final eFull = isB ? tu.eDiscBall : tu.eDiscDisc;
        final e0 = _min(tu.eSoft, eFull);
        final ee = -vn >= tu.vSoft ? eFull : e0 + (eFull - e0) * (-vn / tu.vSoft);
        var j = -(1 + ee) * vn / sm;
        if (!isB) j *= tu.discDiscK;
        a.vx -= j * nx * a.im;
        a.vy -= j * ny * a.im;
        b.vx += j * nx * b.im;
        b.vy += j * ny * b.im;
        _gcap(a);
        _gcap(b);
      }
      a.x += a.vx * s;
      a.y += a.vy * s;
      b.x += b.vx * s;
      b.y += b.vy * s;
    }
    // leftover overlap removed positionally (no velocity change)
    dx = b.x - a.x;
    dy = b.y - a.y;
    dd = dx * dx + dy * dy;
    if (dd < m * m) {
      final d2 = math.sqrt(dd);
      var ux = 0.0, uy = -1.0;
      if (d2 > 1e-4) {
        ux = dx / d2;
        uy = dy / d2;
      }
      final pen = m - d2;
      a.x -= ux * pen * a.im / sm;
      a.y -= uy * pen * a.im / sm;
      b.x += ux * pen * b.im / sm;
      b.y += uy * pen * b.im / sm;
    }
    if (vn < -150) {
      final ev = _push(EvType.hit);
      ev.ball = isB;
      ev.power = -vn / 1900;
      if (!isB && vn < -520) {
        final q = _min(1, -vn / 1900);
        a.sq = _max(a.sq, q * .5);
        b.sq = _max(b.sq, q * .5);
      }
      if (isB) {
        final pw = _min(1, -vn / 2100);
        if (pw > .2) {
          final o = identical(ball, b) ? a : b;
          ball.sq = _max(ball.sq, pw * .6);
          o.sq = _max(o.sq, pw * .25);
          if (pw > .45) burst((a.x + b.x) / 2, (a.y + b.y) / 2, jsRound(4 + pw * 8), 200 + pw * 260, _hitCols, .3, 2);
        }
      }
    }
  }

  void _post8(Body b, double px, double py) {
    final dx = b.x - px, dy = b.y - py, d = math.sqrt(dx * dx + dy * dy), m = b.r + tu.postR;
    if (d >= m || d == 0) return;
    final nx = dx / d, ny = dy / d, vn = b.vx * nx + b.vy * ny;
    b.x = px + nx * m;
    b.y = py + ny * m;
    if (vn < 0) {
      // post: normal component reversed x eWall, tangential component x tWall
      final bl = identical(b, ball), en = bl ? tu.eWallBall : tu.eWallDisc, et = bl ? tu.tWallBall : tu.tWallDisc;
      final tx = b.vx - vn * nx, ty = b.vy - vn * ny;
      b.vx = tx * et - en * vn * nx;
      b.vy = ty * et - en * vn * ny;
      if (identical(b, ball)) _push(EvType.post).power = -vn / 1800;
    }
  }

  void _cushionX(Body b, double wall, double side) {
    final over = (wall - b.x) * side;
    if (over <= 0) return;
    if (b.vx * side < 0) {
      final vs = math.sqrt(b.vx * b.vx + b.vy * b.vy);
      final bl = identical(b, ball), en = bl ? tu.eWallBall : tu.eWallDisc, et = bl ? tu.tWallBall : tu.tWallDisc;
      if (bl && vs > 200) _push(EvType.wall).power = vs / 1800;
      b.vx = -b.vx * en;
      b.vy *= et;
      b.x = wall + side * over * en;
    } else {
      b.x = wall;
    }
  }

  void _cushionY(Body b, double wall, double side) {
    final over = (wall - b.y) * side;
    if (over <= 0) return;
    if (b.vy * side < 0) {
      final vs = math.sqrt(b.vx * b.vx + b.vy * b.vy);
      final bl = identical(b, ball), en = bl ? tu.eWallBall : tu.eWallDisc, et = bl ? tu.tWallBall : tu.tWallDisc;
      if (bl && vs > 200) _push(EvType.wall).power = vs / 1800;
      b.vy = -b.vy * en;
      b.vx *= et;
      b.y = wall + side * over * en;
    } else {
      b.y = wall;
    }
  }

  /// sharp 90 degree corners: a nearly still body jammed against both walls is pushed out diagonally.
  void _cornerNudge(Body b) {
    final r = b.r;
    const gap = 1.5;
    final atL = b.x - r <= Fl + gap, atR = b.x + r >= Fr - gap;
    if (!(atL || atR)) return;
    final atT = b.y - r <= Ft + gap && (b.x < goals[0].x1 || b.x > goals[0].x2);
    final atB = b.y + r >= Fb - gap && (b.x < goals[1].x1 || b.x > goals[1].x2);
    if (!(atT || atB)) return;
    if (b.vx * b.vx + b.vy * b.vy > 90.0 * 90.0) return;
    b.vx = (atL ? 1 : -1) * tu.cornerNudge;
    b.vy = (atT ? 1 : -1) * tu.cornerNudge;
  }

  void _walls8(Body b) {
    final ball = this.ball;
    if (!identical(b, ball) && b.gout != null) {
      final g = b.gout!, dq = g.d * (b.y - g.y);
      if (dq > -b.r * 1.05) {
        b.vy = -g.d * 270 * K;
        b.vx *= .6;
      } else {
        b.vy = 0;
        b.vx *= .2;
        b.gout = null;
      }
    }
    final bl = identical(b, ball), r = b.r;
    final en = bl ? tu.eWallBall : tu.eWallDisc, et = bl ? tu.tWallBall : tu.tWallDisc;
    _cushionX(b, Fl + r, 1);
    _cushionX(b, Fr - r, -1);
    final vs = math.sqrt(b.vx * b.vx + b.vy * b.vy);
    for (var gi = 0; gi < 2; gi++) {
      final g = goals[gi];
      final dp = g.d * (b.y - g.y);
      if (dp <= -r) continue;
      final lo = g.x1 + (bl ? 0 : r), hi = g.x2 - (bl ? 0 : r);
      final inside = bl ? (b.x > g.x1 && b.x < g.x2) : (dp > 0 || (b.x >= lo && b.x <= hi));
      if (inside) {
        final gl = phase == Phase.goal && bl;
        final back = g.y + g.d * DEPTH;
        if (!bl && dp > r * .3 && vs < 150 * K && b.gout == null) b.gout = g;
        if (dp + r > DEPTH) {
          b.y = back - g.d * r;
          if (g.d * b.vy > 0) {
            b.vy = -b.vy * (gl ? .2 : en);
            b.vx *= gl ? .6 : et;
          }
        }
        if (dp > (bl ? r * .6 : 0)) {
          final ee = gl ? .3 : en, te = gl ? 1.0 : et;
          if (b.x < g.x1 + r) {
            b.x = g.x1 + r;
            if (b.vx < 0) {
              b.vx = -b.vx * ee;
              b.vy *= te;
            }
          }
          if (b.x > g.x2 - r) {
            b.x = g.x2 - r;
            if (b.vx > 0) {
              b.vx = -b.vx * ee;
              b.vy *= te;
            }
          }
        }
      } else {
        _cushionY(b, g.y - g.d * r, -g.d.toDouble());
      }
    }
    _cornerNudge(b);
  }

  /// adaptive substeps: no body travels more than tu.subPx per substep (energy bound over all bodies).
  void _sim8(double dt) {
    var e2 = 0.0, mmin = 1e9;
    for (final b in bodies) {
      final mb = 1 / _max(b.im, 1e-6);
      e2 += mb * (b.vx * b.vx + b.vy * b.vy);
      mmin = _min(mmin, mb);
    }
    final n = (math.sqrt(e2 / mmin) * dt / tu.subPx).ceil().clamp(1, tu.subMax);
    final h = dt / n;
    final ball = this.ball;
    for (var i = 0; i < n; i++) {
      _sub8(h);
      if (phase == Phase.move && !slave) {
        for (var gi = 0; gi < 2; gi++) {
          final g = goals[gi];
          if (ball.x > g.x1 && ball.x < g.x2 && (g.d < 0 ? ball.y < g.y - ball.r * .8 : ball.y > g.y + ball.r * .8)) {
            _scored(g.team);
            break;
          }
        }
      }
    }
  }

  void _sub8(double h) {
    final ball = this.ball, B = bodies;
    for (final b in B) {
      if (b.vox != 0 || b.voy != 0) {
        final q = 1 - _min(1, h * 15);
        b.vox *= q;
        b.voy *= q;
        if (b.vox.abs() < .04) b.vox = 0;
        if (b.voy.abs() < .04) b.voy = 0;
      }
      b.x += b.vx * h;
      b.y += b.vy * h;
      final sp = math.sqrt(b.vx * b.vx + b.vy * b.vy);
      if (sp > 0) {
        // rolling friction along the current direction (straight lines): constant decel + small linear drag
        final bl = identical(b, ball);
        final fr = bl ? tu.ballFric : tu.discFric, kd = bl ? tu.ballDrag : tu.discDrag;
        final ns = sp - (fr * (sp < tu.vSettle ? tu.settleK : 1) + kd * sp) * h;
        if (ns < tu.vStop) {
          b.vx = 0;
          b.vy = 0;
        } else {
          final k2 = _min(ns, tu.vSafe) / sp;
          b.vx *= k2;
          b.vy *= k2;
        }
      }
      b.spin = 0;
      if (identical(b, ball)) {
        b.sq *= 1 - 9 * h;
        if (b.vx != 0 || b.vy != 0) {
          final roll = tu.rollK / b.r;
          _rotate(b.R, -b.vy * roll, b.vx * roll, 0, h);
        }
      }
      _walls8(b);
    }
    final n = B.length;
    for (var it = 0; it < 2; it++) {
      for (var a = 0; a < n; a++) {
        final ba = B[a];
        for (var c = a + 1; c < n; c++) {
          final bc = B[c];
          final mm = ba.r + bc.r;
          final ddx = bc.x - ba.x;
          if (ddx >= mm || ddx <= -mm) continue;
          final ddy = bc.y - ba.y;
          if (ddy >= mm || ddy <= -mm) continue;
          _hit8(ba, bc, it == 0 ? h : 0);
        }
      }
    }
    for (var gi = 0; gi < 2; gi++) {
      final g = goals[gi];
      _post8(ball, g.x1, g.y);
      _post8(ball, g.x2, g.y);
    }
    for (final b in B) {
      _walls8(b);
    }
  }

  void _scored(int t) {
    final nogoal = shots <= 1;
    final ev = _push(EvType.goal);
    ev.team = t;
    ev.nogoal = nogoal;
    if (nogoal) {
      phase = Phase.goal;
      pause = 1.4;
      kick = turn;
      return;
    }
    ripple[t] = 1;
    rippleX[t] = ball.x;
    score[t]++;
    pause = godot ? 1.8 : 2.0;
    flash = 1;
    shake[t] = .6;
    phase = Phase.goal;
    kick = 1 - t;
    slow = 1.1;
    cam = 1.4;
    final g = goals[t];
    burst(ball.x, g.y, 80, 760, _goalCols, 1.4, 1);
    burst(ball.x, g.y, 50, 520, _goalCols, 1.8, 3);
  }

  void burst(double x, double y, int n, double sp, List<int> cols, double life, [int k = 0]) {
    if (nParts > 420) return;
    for (var i = 0; i < n; i++) {
      final a = rand() * math.pi * 2, v = sp * (.3 + rand());
      final l = life * (.6 + rand() * .6);
      final r = 2 + rand() * 3.5;
      if (nParts >= maxParts) continue;
      final j = nParts++;
      pX[j] = x;
      pY[j] = y;
      pVx[j] = fcos(a) * v;
      pVy[j] = fsin(a) * v;
      pL[j] = l;
      pM[j] = life;
      pC[j] = cols[i % cols.length];
      pR[j] = r;
      pK[j] = k;
      pG[j] = k == 3 ? 600 : 0;
    }
  }

  void _finishTurn() {
    turn = 1 - turn;
    phase = Phase.aim;
    tleft = cfg.turnTime;
    aiT = 0;
    aiPlan = null;
    _push(EvType.turn).team = turn;
  }

  void _end() {
    phase = Phase.over;
    final e = _push(EvType.end);
    e.s0 = score[0];
    e.s1 = score[1];
  }

  // ---------- main step (call once per frame) ----------
  void update(double rdt) {
    final dt = _min(rdt, .05);
    time += dt;
    if (phase == Phase.over) {
      tickFx(dt);
      return;
    }
    if (cfg.matchTime > 0 && !sudden && mleft > 0 && !slave) mleft = _max(0, mleft - dt);
    var ts = 1.0;
    if (slow > 0) {
      slow -= dt;
      ts = godot ? .32 + .68 * fpow(1 - _max(0, slow) / 1.1, 2) : .3 + .7 * fpow(1 - _max(0, slow) / 1.1, 2);
    }
    acc += dt * ts;
    var n = 0;
    if (godot) {
      // Godot loop: at most tu.stepCap physics steps per frame, the backlog is dropped beyond that
      while (acc >= STEP) {
        if (n >= tu.stepCap) {
          n++;
          break;
        }
        n++;
        for (final b in bodies) {
          b.px = b.x;
          b.py = b.y;
        }
        _sim(STEP);
        acc -= STEP;
      }
      if (n > tu.stepCap) acc = 0;
      if (slave) {
        tickFx(dt);
        return;
      }
    } else if (slave) {
      while (acc >= STEP && n++ < 16) {
        for (final b in bodies) {
          b.px = b.x;
          b.py = b.y;
        }
        _sim(STEP);
        acc -= STEP;
      }
      if (n > 16) acc = 0;
      tickFx(dt);
      return;
    }
    if (!godot) {
      while (acc >= STEP && n++ < 16) {
        for (final b in bodies) {
          b.px = b.x;
          b.py = b.y;
        }
        _sim(STEP);
        acc -= STEP;
      }
      if (n > 16) acc = 0;
    }
    if (phase == Phase.move) {
      var moving = false;
      for (final b in bodies) {
        if (b.vx != 0 || b.vy != 0 || (!godot && b.ramp > 0)) {
          moving = true;
          break;
        }
      }
      idle = moving ? 0 : idle + dt;
      if (idle > (godot ? .25 : .15)) _finishTurn();
    } else if (phase == Phase.aim) {
      if (cfg.matchTime > 0 && !sudden && mleft <= 0) {
        if (score[0] != score[1]) {
          _end();
          return;
        }
        sudden = true;
        _push(EvType.clock);
      }
      if (cfg.turnTime > 0) {
        tleft -= dt;
        if (tleft <= 0) {
          drag = null;
          aiPlan = null;
          _finishTurn();
          if (godot) {
            tickFx(dt);
            return;
          }
        }
      }
      if (isAiTurn()) _aiTick(dt);
    } else if (phase == Phase.goal) {
      pause -= dt;
      if (pause <= 0) {
        if (cfg.matchTime > 0) {
          if (sudden || (mleft <= 0 && score[0] != score[1])) {
            _end();
          } else {
            if (mleft <= 0) sudden = true;
            reset(kick);
          }
        } else if (score[0] >= cfg.limit || score[1] >= cfg.limit) {
          _end();
        } else {
          reset(kick);
        }
      }
    }
    tickFx(dt);
  }

  /// online clients: visual-only goal feedback (the host owns the score)
  void fxGoal(int t) {
    ripple[t] = 1;
    rippleX[t] = ball.x;
    flash = 1;
    shake[t] = .6;
    cam = 1.4;
    final g = goals[t];
    burst(ball.x, g.y, 80, 760, _goalCols, 1.4, 1);
    burst(ball.x, g.y, 50, 520, _goalCols, 1.8, 3);
  }

  void tickFx(double dt) {
    flash = _max(0, flash - dt * 2);
    cam = _max(0, cam - dt * 3.2);
    shake[0] = _max(0, shake[0] - dt);
    ripple[0] = _max(0, ripple[0] - dt * .8);
    ripple[1] = _max(0, ripple[1] - dt * .8);
    shake[1] = _max(0, shake[1] - dt);
    final ball = this.ball;
    final sp = hyp(ball.vx, ball.vy);
    if (sp > 60) {
      if (nTrail == maxTrail) _trailDrop(1);
      tX[nTrail] = ball.x;
      tY[nTrail] = ball.y;
      tA[nTrail] = _min(1, sp / 900);
      nTrail++;
    }
    var k = 0;
    for (var i = 0; i < nTrail; i++) {
      final a = tA[i] - dt * (godot ? 3.0 : 3.2);
      if (a > 0) {
        tX[k] = tX[i];
        tY[k] = tY[i];
        tA[k] = a;
        k++;
      }
    }
    nTrail = k;
    final tmax = godot ? 54 : 40;
    if (nTrail > tmax) _trailDrop(nTrail - tmax);
    for (final b in bodies) {
      if (!identical(b, ball)) {
        if (godot && b.sq != 0) b.sq = b.sq > .02 ? b.sq - dt * 5 : 0;
        final s = hyp(b.vx, b.vy);
        if (s > 140 * K) {
          b.trPush(b.x, b.y);
        } else if (b.trLen > 0) {
          b.trShift();
        }
        if (b.trLen > 12) b.trShift();
      }
    }
    k = 0;
    for (var i = 0; i < nParts; i++) {
      pX[i] += pVx[i] * dt;
      pY[i] += pVy[i] * dt;
      pVx[i] *= .965;
      pVy[i] = pVy[i] * .965 + pG[i] * dt;
      pL[i] -= dt;
      if (pL[i] > 0) {
        if (k != i) {
          pX[k] = pX[i];
          pY[k] = pY[i];
          pVx[k] = pVx[i];
          pVy[k] = pVy[i];
          pL[k] = pL[i];
          pM[k] = pM[i];
          pR[k] = pR[i];
          pG[k] = pG[i];
          pC[k] = pC[i];
          pK[k] = pK[i];
        }
        k++;
      }
    }
    nParts = k;
  }

  void _trailDrop(int c) {
    for (var i = c; i < nTrail; i++) {
      tX[i - c] = tX[i];
      tY[i - c] = tY[i];
      tA[i - c] = tA[i];
    }
    nTrail -= c;
  }

  /// interpolation factor for rendering between physics steps
  double alpha() => _clamp(acc / STEP, 0, 1);

  // ---------- AI ----------
  void _aiTick(double dt) {
    if (aiPlan == null) {
      aiT += dt;
      if (aiT < .7 + rand() * (godot ? .7 : .5)) return;
      final p = _aiDecide();
      if (p == null) return;
      aiPlan = p;
      drag = Drag(p.b, p.b.x, p.b.y, p.b.x, p.b.y, ai: true);
      return;
    }
    final pl = aiPlan!;
    pl.t += dt;
    final k = _min(1, pl.t / .75), e = k * k * (3 - 2 * k);
    final d = drag;
    if (d != null) {
      d.cx = pl.b.x - pl.dx * pl.l * e;
      d.cy = pl.b.y - pl.dy * pl.l * e;
    }
    if (k >= 1) {
      drag = null;
      aiPlan = null;
      fire(pl.b, pl.dx * pl.l, pl.dy * pl.l, pl.l);
    }
  }

  static double _segDist(double px, double py, double ax, double ay, double bx, double by) {
    final vx = bx - ax, vy = by - ay;
    var l2 = vx * vx + vy * vy;
    if (l2 == 0) l2 = 1;
    var t = ((px - ax) * vx + (py - ay) * vy) / l2;
    t = _clamp(t, 0, 1);
    return hyp(px - (ax + vx * t), py - (ay + vy * t));
  }

  bool _clear(Body p, double x, double y) {
    for (final o in bodies) {
      if (identical(o, p) || identical(o, ball)) continue;
      if (_segDist(o.x, o.y, p.x, p.y, x, y) < p.r + o.r - 6) return false;
    }
    return true;
  }

  static const _offs = [-.55, 0.0, .55];

  AiPlan? _aiDecide() {
    final me = turn, ball = this.ball, B = bodies;
    final mine = <Body>[for (final b in B) if (b.team == me && !identical(b, ball)) b];
    final og = goals[1 - me];
    final target = goals[me == 1 ? 1 : 0];
    final lvl = cfg.aiLvl;
    final sg = const [.14, .06, .016][lvl];
    final gw = (target.x2 - target.x1) / 2;
    final cands = <_Cand>[];
    for (final p in mine) {
      for (final ox in _offs) {
        final tx = CX + ox * gw, ty = target.y;
        var ux = tx - ball.x, uy = ty - ball.y;
        var ul = hyp(ux, uy);
        if (ul == 0) ul = 1;
        ux /= ul;
        uy /= ul;
        final cx = ball.x - ux * (p.r + ball.r + 1), cy = ball.y - uy * (p.r + ball.r + 1);
        var vx = cx - p.x, vy = cy - p.y;
        final dist = hyp(vx, vy);
        if (dist < 8) continue;
        vx /= dist;
        vy /= dist;
        final al = vx * ux + vy * uy;
        if (al < .2 || !_clear(p, cx, cy)) continue;
        var blk = 0;
        for (final o in B) {
          if (o.team == me || identical(o, ball)) continue;
          if (_segDist(o.x, o.y, ball.x, ball.y, tx, ty) < ball.r + o.r + 6) blk++;
        }
        cands.add(_Cand(p, vx, vy, 100 * al - dist * .03 - blk * 28 + ((ball.y - ty).abs() < 420 ? 25 : 0), dist, 1));
      }
      var vx = ball.x - p.x, vy = ball.y - p.y;
      final dist = hyp(vx, vy);
      if (dist > 8) {
        vx /= dist;
        vy /= dist;
        if (_clear(p, ball.x, ball.y)) {
          final toOwn = (vy * (og.y - ball.y) > 0) ? vy.abs() : 0.0;
          cands.add(_Cand(p, vx, vy, 10 - dist * .04 - toOwn * 55, dist, 0));
        }
      }
    }
    if (cands.isEmpty) {
      final sorted = List<Body>.of(mine);
      _stableSort<Body>(sorted, (a, b) => hyp(a.x - ball.x, a.y - ball.y) - hyp(b.x - ball.x, b.y - ball.y));
      if (sorted.isEmpty) return null;
      final p = sorted[0];
      final vx = ball.x - p.x, vy = ball.y - p.y;
      var d = hyp(vx, vy);
      if (d == 0) d = 1;
      cands.add(_Cand(p, vx / d, vy / d, 0, d, 0));
    }
    _stableSort<_Cand>(cands, (a, b) => b.sc - a.sc);
    final take = const [4, 2, 1][lvl];
    final poolN = cands.length < take ? cands.length : take;
    final c = cands[(rand() * poolN).floor()];
    double gauss() => (rand() + rand() + rand() - 1.5) * 1.15;
    final ang = fatan2(c.dy, c.dx) + gauss() * sg;
    var pw = lvl == 2 ? _min(1, .66 + c.dist / 1000) : _min(1, .5 + c.dist / 1100);
    if (lvl == 0) pw *= .7 + rand() * .3;
    if (c.atk != 0 && lvl > 0) pw = _max(pw, .78);
    return AiPlan(c.p, fcos(ang), fsin(ang), _max(.3, pw) * LMAX, 0);
  }

  /// Stable sort with a JS-style numeric comparator (V8's Array.prototype.sort is stable).
  static void _stableSort<T>(List<T> a, double Function(T, T) cmp) {
    for (var i = 1; i < a.length; i++) {
      final x = a[i];
      var j = i - 1;
      while (j >= 0 && cmp(a[j], x) > 0) {
        a[j + 1] = a[j];
        j--;
      }
      a[j + 1] = x;
    }
  }
}
