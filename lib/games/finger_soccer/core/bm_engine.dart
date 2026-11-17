// ignore_for_file: constant_identifier_names, non_constant_identifier_names
// BERMUDA NXG disc-football engine: a 1:1 port of www/js/game.js (physics, rules, turn flow, AI, fx state).
// Every constant and formula below is copied verbatim from the JS. Do NOT retune.
// World = the field image's own pixel space scaled by FS (see geo()).
import 'dart:math' as math;

import 'bm_data.dart';

// ---------------------------------------------------------------- constants (game.js line 4-6)
const double K = 1.27, PR = 63.8, BR = 28.8, STEP = 1 / 240, RC = 70, LMAX = 320;
const int NB = 36;
/// Mini-soccer tuning (redesign-v1.1, owner request): ball mass 1.9 -> 1.805 (x0.95) and a kick factor on the
/// ball's share of a disc->ball impulse so a disc striking the ball launches it exactly 5% faster than before
/// (the lighter mass alone gives +1.40%, BKICK supplies the rest). Nothing else changed.
const double BALL_M = 1.805;
const double BKICK = 1.05 * ((1 / 1.9) / (1 / 5 + 1 / 1.9)) / ((1 / BALL_M) / (1 / 5 + 1 / BALL_M));
const double HV = 4, PF1 = 390, PF2 = .8, PV0 = 600, EPP = .48, PCAP = 190;

/// Field size factor (game.js line 12).
const double FS = 1.12 * 1.215;

/// A field after the FS scale (game.js line 12: W,H,L,R,T,B,cs rounded, g = 169).
class BmFieldS {
  BmFieldS(BmField f)
      : id = f.id,
        name = f.name,
        gs = f.gs,
        W = _r(f.w0),
        H = _r(f.h0),
        L = _r(f.l0),
        R = _r(f.r0),
        T = _r(f.t0),
        B = _r(f.b0),
        cs = _r(f.cs0),
        g = 169;
  static double _r(int v) => (v * FS).round().toDouble(); // Math.round on positive values
  final String id, name, gs;
  final double W, H, L, R, T, B, cs, g;
}

final List<BmFieldS> kBmFields = kBmFieldsRaw.map(BmFieldS.new).toList(growable: false);

class BmTeam {
  const BmTeam(this.id, this.cat, this.name, this.asset);
  final String id, cat, name, asset;
}

/// TEAMS (game.js line 32): id = cat + index, image = assets/teams/<cat><nn>.webp
final List<BmTeam> kBmTeams = () {
  final List<BmTeam> o = <BmTeam>[];
  for (final List<Object> c in kBmCats) {
    final String k = c[0] as String;
    final List<String> l = c[2] as List<String>;
    for (int i = 0; i < l.length; i++) {
      o.add(BmTeam('$k$i', k, l[i], 'assets/games/bermuda/teams/$k${i.toString().padLeft(2, '0')}.webp'));
    }
  }
  return o;
}();

BmTeam bmTeam(String id) => kBmTeams.firstWhere((BmTeam t) => t.id == id, orElse: () => kBmTeams.first);

/// FORMS (game.js line 37): [name, label, rows [ny, count]].
const List<List<Object>> kBmForms = <List<Object>>[
  <Object>['1-2-2', 'Balanced', <List<double>>[<double>[.09, 1], <double>[.22, 2], <double>[.36, 2]]],
  <Object>['2-2-1', 'Cautious', <List<double>>[<double>[.10, 2], <double>[.24, 2], <double>[.37, 1]]],
  <Object>['3-1-1', 'Wall', <List<double>>[<double>[.10, 3], <double>[.25, 1], <double>[.37, 1]]],
  <Object>['2-1-2', 'Diamond', <List<double>>[<double>[.10, 2], <double>[.24, 1], <double>[.37, 2]]],
  <Object>['1-3-1', 'Midfield', <List<double>>[<double>[.09, 1], <double>[.23, 3], <double>[.37, 1]]],
  <Object>['1-1-3', 'Attack', <List<double>>[<double>[.09, 1], <double>[.22, 1], <double>[.36, 3]]],
];

List<List<double>> bmSlots(int fi) {
  final List<List<double>> o = <List<double>>[];
  for (final List<double> row in kBmForms[fi][2] as List<List<double>>) {
    final double ny = row[0];
    final int c = row[1].toInt();
    for (int i = 0; i < c; i++) {
      o.add(<double>[c == 1 ? .5 : c == 2 ? .27 + .46 * i : .17 + .33 * i, ny]);
    }
  }
  return o;
}

String bmBallName(int i) => '${kBmBallN[i]} Ball';

// ---------------------------------------------------------------- bodies
class BmGoal {
  BmGoal(this.team, this.y, this.x1, this.x2, this.d);
  final int team;
  final double y, x1, x2;
  final int d;
}

class BmTrailPt {
  BmTrailPt(this.x, this.y, this.v, {this.a = 1, this.h = false});
  final double x, y, v;
  double a;
  final bool h;
}

class BmBody {
  BmBody(this.x, this.y, this.team, this.r, this.m) : im = 1 / m;
  double x, y, vx = 0, vy = 0;
  final double r, m, im;
  final int team;
  double spin = 0, ang = 0, sq = 0, boost = 0;
  final List<double> R = <double>[1, 0, 0, 0, 1, 0, 0, 0, 1];
  int rv = 0;
  int cid = 0;
  BmGoal? gout;
  final List<BmTrailPt> tr = <BmTrailPt>[];
}

class BmPart {
  BmPart(this.x, this.y, this.vx, this.vy, this.l, this.r, this.c, this.k, this.g, this.rot, {double? m}) : m = m ?? l;
  double x, y, vx, vy, l;
  final double m, r, g;
  final int c, k;
  double rot;
}

class BmRing {
  BmRing(this.x, this.y, this.r, this.l, this.w) : m = l;
  final double x, y, r, m, w;
  double l;
}

class BmDrag {
  BmDrag(this.b, this.sx, this.sy, this.cx, this.cy, {this.ai = false});
  final BmBody b;
  final double sx, sy;
  double cx, cy;
  final bool ai;
}

class BmAiPlan {
  BmAiPlan(this.b, this.dx, this.dy, this.l);
  final BmBody b;
  final double dx, dy, l;
  double t = 0;
}

/// Match config (game.js startMatch cfg).
class BmConfig {
  const BmConfig({
    required this.mode,
    required this.teams,
    required this.form,
    required this.names,
    required this.field,
    required this.ball,
    this.limit = 0,
    this.matchTime = 0,
    this.turnTime = 0,
    this.ai = false,
    this.aiLvl = 1,
    this.mirror = false,
    this.first = 0,
  });
  final String mode; // 'local' | 'bot' | 'online'
  final List<String> teams; // global team ids
  final List<int> form; // global formations
  final List<String> names; // global names
  final int field, ball, limit, matchTime, first;
  final double turnTime;
  final bool ai, mirror;
  final int aiLvl;
}

/// Callbacks the engine fires (sound, haptics, toast, network, end).
abstract class BmHooks {
  void sfx(String k, [double v = 1]);
  void tone(String k);
  void vib(List<int> pattern);
  void toast(String text, bool big);
  void goalFx();
  void emit(String event, Map<String, dynamic> data);
}

const List<int> _goalCols = <int>[0xFFFFD23A, 0xFFFF4A7A, 0xFF3BD0FF, 0xFF7BFF5A, 0xFFFFFFFF];

class BmEngine {
  BmEngine(this.hooks, {math.Random? rng}) : rnd = rng ?? math.Random() {
    geo();
  }

  final BmHooks hooks;
  final math.Random rnd;
  double R_() => rnd.nextDouble();

  // SET (game.js line 13)
  int setLim = 5, setFld = 0, setBall = 0;

  // C
  String mode = 'local';
  List<String> names = <String>['', ''];
  bool mirror = false;
  int ai = -1, aiLvl = 1, mt = 0;
  double tt = 0;

  // geometry
  late double Fl, Fr, Ft, Fb, Fw, Fh, CX, CY, KY = 0, DEPTH = 112;
  late List<BmGoal> GOALS;
  late double GGw, GGh, GGx;
  BmFieldS get field => kBmFields[setFld];

  List<String> sel = <String>['club0', 'club1'];
  List<int> form = <int>[0, 0];

  List<BmBody> bodies = <BmBody>[];
  BmBody? ball;
  List<int> score = <int>[0, 0];
  int turn = 0, kick = 0, shots = 0;
  String phase = 'aim';
  BmDrag? drag;
  double pause = 0, idle = 0, flash = 0, acc = 0, freeze = 0, slow = 0, cam = 0;
  final List<double> shake = <double>[0, 0];
  List<BmTrailPt> trail = <BmTrailPt>[];
  List<BmPart> parts = <BmPart>[];
  List<BmRing> rings = <BmRing>[];
  bool menuOpen = true, inMatch = false;
  double mleft = 0;
  bool sd = false;
  double aiT = 0;
  BmAiPlan? aiPlan;
  double tleft = 0;
  bool remote = false;
  double fxAcc = 0, fxAcc2 = 0;
  bool _endEmitted = false;

  int ct(int t) => mirror ? 1 - t : t;
  String nm(int t) => names[ct(t)].isNotEmpty ? names[ct(t)] : bmTeam(sel[ct(t)]).name;
  List<int> bcol() => kBmTR[setBall % kBmTR.length].c;

  void geo() {
    final BmFieldS f = field;
    Fl = f.L + 4;
    Fr = f.R - 4;
    Ft = f.T + 4;
    Fb = f.B - 4;
    Fw = Fr - Fl;
    Fh = Fb - Ft;
    CX = (Fl + Fr) / 2;
    CY = (Ft + Fb) / 2;
    KY = f.cs;
    final List<double> gi = kBmGS[f.gs]!;
    final double gw = 2 * f.g / (gi[3] - gi[2]);
    GGw = gw;
    GGh = gw * gi[1] / gi[0];
    GGx = CX - f.g - gi[2] * gw;
    DEPTH = _mx(106, (GGh * .95).roundToDouble());
    GOALS = <BmGoal>[BmGoal(0, Ft, CX - f.g, CX + f.g, -1), BmGoal(1, Fb, CX - f.g, CX + f.g, 1)];
  }

  BmBody mk(double x, double y, int team, double r, double m) => BmBody(x, y, team, r, m);

  void reset(int k) {
    bodies = <BmBody>[];
    trail = <BmTrailPt>[];
    parts = <BmPart>[];
    rings = <BmRing>[];
    freeze = 0;
    slow = 0;
    cam = 0;
    for (int cm = 0; cm < 2; cm++) {
      final List<List<double>> sl = bmSlots(form[cm]);
      for (int i = 0; i < sl.length; i++) {
        final double nx = sl[i][0], ny = sl[i][1];
        double x = Fl + PR + 10 + nx * (Fw - 2 * (PR + 10)), y = cm != 0 ? Ft + ny * Fh : Fb - ny * Fh;
        if (mirror) {
          x = 2 * CX - x;
          y = 2 * CY - y;
        }
        final BmBody b = mk(x, y, ct(cm), PR, 5);
        b.cid = cm * 20 + i;
        b.boost = 0;
        bodies.add(b);
      }
    }
    final BmBody bl = mk(CX, mirror ? 2 * CY - KY : KY, 2, BR, BALL_M);
    bl.cid = 99;
    ball = bl;
    bodies.add(bl);
    turn = k;
    phase = 'aim';
    drag = null;
    pause = 0;
    idle = 0;
    shots = 0;
    tleft = tt;
    remote = false;
    aiT = 0;
    aiPlan = null;
    hooks.emit('turn', <String, dynamic>{'turn': ct(turn), 'mine': turn == 0});
  }

  void toast(String t, [bool big = false]) => hooks.toast(t, big);

  void burst(double x, double y, int n, double sp, List<int> cols, double life, [int k = 0]) {
    if (parts.length > 360) return;
    for (int i = 0; i < n; i++) {
      final double a = R_() * 7, v = sp * (.3 + R_());
      parts.add(BmPart(x, y, math.cos(a) * v, math.sin(a) * v, life * (.6 + R_() * .6), 2 + R_() * 3.5, cols[i % cols.length], k, 0,
          R_() * 6,
          m: life));
    }
  }

  void wallFx(double x, double y, double vs) {
    final double q = _mn(1, vs / (1500 * K));
    burst(x, y, (4 + q * 10).round(), 180 + q * 380, <int>[0xFFFFFFFF, bcol()[0], 0xFFFFD86B], .3, 5);
    if (q > .35) {
      rings.add(BmRing(x, y, 10, .26, q * .7));
      cam = _mx(cam, q * .55);
    }
  }

  void spawn(double x, double y, double vx, double vy, double l, double r, int c, [int k = 0, double g = 0]) {
    if (parts.length > 360) return;
    parts.add(BmPart(x, y, vx, vy, l, r, c, k, g, R_() * 6));
  }

  void scored(int t, [bool fromRemote = false]) {
    final bool ng = shots <= 1;
    if (!fromRemote && mode == 'online') hooks.emit('goal', <String, dynamic>{'team': ct(t), 'nogoal': ng});
    if (ng) {
      phase = 'goal';
      pause = 1.4;
      kick = turn;
      toast('No goal');
      return;
    }
    score[t]++;
    pause = 1.8;
    flash = 1;
    shake[t] = .6;
    phase = 'goal';
    kick = 1 - t;
    hooks.goalFx();
    final BmBody b = ball!;
    final List<int> bc = kBmTR[setBall % kBmTR.length].c;
    burst(b.x, GOALS[t].y, 70, 700, <int>[0xFFFFD23A, 0xFFFFFFFF, bc[0], bc[1]], 1.3);
    burst(b.x, GOALS[t].y, 46, 520, <int>[...bc, 0xFFFFFFFF], 1.6, 1);
    hooks.sfx('goal');
    hooks.vib(<int>[60, 40, 120]);
    slow = 1.1;
    cam = 1.4;
    rings.add(BmRing(b.x, GOALS[t].y, 20, .7, 1));
    for (int w = 0; w < 3; w++) {
      _later(.25 + w * .3, () {
        if (inMatch) {
          burst(Fl + R_() * (Fr - Fl), GOALS[t].y + (GOALS[t].d < 0 ? 60 : -60), 26, 420, _goalCols, 1.4, 3);
          burst(Fl + R_() * (Fr - Fl), GOALS[t].y, 18, 300, _goalCols, 1.2, 1);
        }
      });
    }
    hooks.emit('scored', <String, dynamic>{
      'team': ct(t),
      'score': <int>[score[ct(0)], score[ct(1)]],
      'mine': t == 0
    });
  }

  // setTimeout replacement driven by frame() (wall-clock seconds).
  final List<MapEntry<double, void Function()>> _timers = <MapEntry<double, void Function()>>[];
  double _clock = 0;
  void _later(double sec, void Function() f) => _timers.add(MapEntry<double, void Function()>(_clock + sec, f));

  double _eN(bool bl, double vn) => bl ? .84 - .22 * _mn(1, _mx(0, (vn - 270 * K) / (1350 * K))) : .82;

  void walls(BmBody b) {
    final bool bl = b == ball;
    if (!bl && b.gout != null) {
      final BmGoal g = b.gout!;
      final double dq = g.d * (b.y - g.y);
      if (dq > -b.r * 1.05) {
        b.vy = -g.d * 270 * K;
        b.vx *= .6;
      } else {
        b.vy = 0;
        b.vx *= .2;
        b.gout = null;
      }
    }
    final double r = b.r, vs = math.sqrt(b.vx * b.vx + b.vy * b.vy);
    if (b.x - r < Fl) {
      b.x = Fl + r;
      if (b.vx < 0) {
        if (bl && vs > 200) {
          hooks.sfx('wall', vs / 1800);
          wallFx(Fl, b.y, vs);
        }
        b.vx *= -_eN(bl, -b.vx);
        b.spin += b.vy / r * .05;
      }
    }
    if (b.x + r > Fr) {
      b.x = Fr - r;
      if (b.vx > 0) {
        if (bl && vs > 200) {
          hooks.sfx('wall', vs / 1800);
          wallFx(Fr, b.y, vs);
        }
        b.vx *= -_eN(bl, b.vx);
        b.spin -= b.vy / r * .05;
      }
    }
    for (final BmGoal g in GOALS) {
      final double dp = g.d * (b.y - g.y);
      if (dp <= -r) continue;
      final double lo = g.x1 + (bl ? 0 : r), hi = g.x2 - (bl ? 0 : r);
      final bool inside = bl ? (b.x > g.x1 && b.x < g.x2) : (dp > 0 || (b.x >= lo && b.x <= hi));
      if (inside) {
        final bool gl = phase == 'goal' && bl;
        final double eb = gl ? .2 : _eN(bl, b.vy.abs()), back = g.y + g.d * DEPTH;
        if (!bl && dp > r * .3 && vs < 150 * K && b.gout == null) b.gout = g;
        if (dp + r > DEPTH) {
          b.y = back - g.d * r;
          b.vy = -g.d * b.vy.abs() * eb;
          if (gl) b.vx *= .6;
        }
        if (dp > (bl ? r * .6 : 0)) {
          final double ee = gl ? .3 : _eN(bl, b.vx.abs());
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
        if (bl && vs > 200) {
          hooks.sfx('wall', vs / 1800);
          wallFx(b.x, g.y, vs);
        }
        b.y = g.y - g.d * r;
        if (g.d * b.vy > 0) b.vy = -g.d * b.vy.abs() * _eN(bl, b.vy.abs());
        b.spin += g.d * b.vx / r * .05;
      }
    }
    for (final List<double> c in <List<double>>[
      <double>[Fl + RC, Ft + RC, 1, 1],
      <double>[Fr - RC, Ft + RC, -1, 1],
      <double>[Fl + RC, Fb - RC, 1, -1],
      <double>[Fr - RC, Fb - RC, -1, -1],
    ]) {
      final double cx = c[0], cy = c[1], sx = c[2], sy = c[3];
      if ((b.x - cx) * sx < 0 && (b.y - cy) * sy < 0) {
        final double dx = b.x - cx, dy = b.y - cy, d = math.sqrt(dx * dx + dy * dy), lim = RC - r;
        if (d > lim && d > 0) {
          final double nx = dx / d, ny = dy / d, vn = b.vx * nx + b.vy * ny;
          b.x = cx + nx * lim;
          b.y = cy + ny * lim;
          if (vn > 0) {
            final double ec = _eN(bl, vn);
            b.vx -= (1 + ec) * vn * nx;
            b.vy -= (1 + ec) * vn * ny;
          }
        }
      }
    }
  }

  void post(BmBody b, double px, double py) {
    final double dx = b.x - px, dy = b.y - py, d = math.sqrt(dx * dx + dy * dy), m = b.r + 5;
    if (d >= m || d == 0) return;
    final double nx = dx / d, ny = dy / d, vn = b.vx * nx + b.vy * ny;
    b.x = px + nx * m;
    b.y = py + ny * m;
    if (vn < 0) {
      final double kp = b == ball ? 1.7 - .16 * _mn(1, -vn / (2000 * K)) : 1.7;
      b.vx -= kp * vn * nx;
      b.vy -= kp * vn * ny;
      if (b == ball) {
        hooks.sfx('post', -vn / 1800);
        if (-vn > 900 * K) {
          toast('Post!');
          burst(b.x, b.y, 16, 380, <int>[0xFFFFFFFF, 0xFFFFD86B], .4, 5);
          rings.add(BmRing(px, py, 10, .3, .8));
          cam = _mx(cam, .7);
        }
      }
      hooks.tone('post');
    }
  }

  void hit(BmBody a, BmBody b) {
    double dx = b.x - a.x, dy = b.y - a.y, d = math.sqrt(dx * dx + dy * dy);
    final double m = a.r + b.r;
    if (d >= m) return;
    if (d < 1e-4) {
      dx = 1;
      dy = 0;
      d = 1;
    }
    final BmBody bl = ball!;
    final double nx = dx / d, ny = dy / d, sm = a.im + b.im;
    final bool isB = a == bl || b == bl;
    double ka = isB && a != bl ? 1 / HV : 1, kb = isB && b != bl ? 1 / HV : 1;
    if (!isB) {
      final double sa = math.sqrt(a.vx * a.vx + a.vy * a.vy), sb = math.sqrt(b.vx * b.vx + b.vy * b.vy);
      if (sa > sb) {
        kb = .85;
      } else {
        ka = .85;
      }
    }
    double wa = a.im / sm * ka, wb = b.im / sm * kb;
    if (isB) {
      if (a == bl) {
        wa = 1 - wb;
      } else {
        wb = 1 - wa;
      }
    }
    final double pen = _mx(m - d - .3, 0) * .9;
    a.x -= nx * pen * wa;
    a.y -= ny * pen * wa;
    b.x += nx * pen * wb;
    b.y += ny * pen * wb;
    final double vn = (b.vx - a.vx) * nx + (b.vy - a.vy) * ny;
    if (vn >= 0) return;
    final double e = vn < -40 * K ? (isB ? .61 - .12 * _mn(1, _mx(0, (-vn - 500 * K) / (1200 * K))) : EPP) : 0,
        j = -(1 + e) * vn / sm;
    final BmBody? pa = isB ? (a == bl ? b : a) : null;
    final double pre = pa != null ? math.sqrt(pa.vx * pa.vx + pa.vy * pa.vy) : 0;
    if (pa != null) {
      // disc strikes the ball (disc faster than ball): ball launch x1.05 overall (see BKICK).
      final double bs = math.sqrt(bl.vx * bl.vx + bl.vy * bl.vy);
      if (pre > bs) {
        if (a == bl) {
          ka *= BKICK;
        } else {
          kb *= BKICK;
        }
      }
    }
    a.vx -= j * nx * a.im * ka;
    a.vy -= j * ny * a.im * ka;
    b.vx += j * nx * b.im * kb;
    b.vy += j * ny * b.im * kb;
    if (pa != null && pre < 260 * K) {
      final double ps = math.sqrt(pa.vx * pa.vx + pa.vy * pa.vy), cp = PCAP * K;
      if (ps > cp) {
        pa.vx *= cp / ps;
        pa.vy *= cp / ps;
      }
    }
    if (vn < -120 * K) {
      hooks.sfx(isB ? 'hitb' : 'hitp', -vn / 1900);
      if (vn < -420 * K) {
        final double q = _mn(1, -vn / (1500 * K));
        burst(a.x + nx * a.r, a.y + ny * a.r, (4 + q * 8).round(), 260 + q * 300, <int>[0xFFFFFFFF, 0xFF9FE0FF, 0xFFFFD86B], .3, 5);
        if (!isB) {
          a.sq = _mx(a.sq, q);
          b.sq = _mx(b.sq, q);
          rings.add(BmRing(a.x + nx * a.r, a.y + ny * a.r, 12, .3, q * .8));
          cam = _mx(cam, q * .6);
        }
        hooks.vib(<int>[12]);
      }
    }
    if (isB) {
      bl.spin += (bl == b ? 1 : -1) * (-ny * (b.vx - a.vx) + nx * (b.vy - a.vy)) / bl.r * .3;
      bl.spin = _mx(-34, _mn(34, bl.spin));
      final double pw = _mn(1, -vn / (1700 * K));
      if (pw > .2) {
        final BmBody o = bl == b ? a : b;
        final int sg = bl == b ? -1 : 1;
        bl.sq = _mx(bl.sq, pw);
        cam = _mx(cam, pw * .9);
        o.sq = _mx(o.sq, pw);
        if (pw > .75 && freeze <= 0) freeze = .04;
        rings.add(BmRing(bl.x, bl.y, bl.r, .34, pw));
        burst(bl.x + nx * sg * bl.r * .2, bl.y + ny * sg * bl.r * .2, (6 + pw * 18).round(), 260 + pw * 520,
            pw > .7 ? <int>[...bcol(), 0xFFFFFFFF] : bcol(), .32 + .2 * pw);
        hooks.vib(pw > .7 ? <int>[18, 14, 30] : <int>[16]);
      }
    }
  }

  // 3D ball rotation (game.js rot)
  final List<double> _M = List<double>.filled(9, 0);
  void rot(List<double> R, double wx, double wy, double wz, double dt) {
    final double w = math.sqrt(wx * wx + wy * wy + wz * wz), th = w * dt;
    if (th < 1e-7) return;
    final double nx = wx / w, ny = wy / w, nz = wz / w, c = math.cos(th), sn = math.sin(th), C = 1 - c;
    final List<double> M = _M;
    M[0] = c + nx * nx * C;
    M[1] = nx * ny * C - nz * sn;
    M[2] = nx * nz * C + ny * sn;
    M[3] = ny * nx * C + nz * sn;
    M[4] = c + ny * ny * C;
    M[5] = ny * nz * C - nx * sn;
    M[6] = nz * nx * C - ny * sn;
    M[7] = nz * ny * C + nx * sn;
    M[8] = c + nz * nz * C;
    for (int q = 0; q < 3; q++) {
      final double a = R[q], b = R[3 + q], d = R[6 + q];
      R[q] = M[0] * a + M[1] * b + M[2] * d;
      R[3 + q] = M[3] * a + M[4] * b + M[5] * d;
      R[6 + q] = M[6] * a + M[7] * b + M[8] * d;
    }
  }

  void sim(double dt) {
    final BmBody? bal = ball;
    for (final BmBody b in bodies) {
      b.x += b.vx * dt;
      b.y += b.vy * dt;
      final double sp = math.sqrt(b.vx * b.vx + b.vy * b.vy);
      final bool bl = b == bal;
      if (sp > 0) {
        if (bl) {
          final double f = 570 * K * _mn(1, sp / (480 * K)) + sp * .1, ns = sp - f * dt;
          if (ns < 12 * K) {
            b.vx = 0;
            b.vy = 0;
          } else {
            final double m = _mx(-34, _mn(34, b.spin)) * .034 * dt, cs = math.cos(m), sn = math.sin(m);
            final double vx = b.vx * cs - b.vy * sn, vy = b.vx * sn + b.vy * cs, k = _mn(ns, 2500 * K) / sp;
            b.vx = vx * k;
            b.vy = vy * k;
          }
        } else {
          final double fb = b.boost > 0 ? .35 : 1;
          if (b.boost > 0) b.boost -= dt;
          final double ns = sp - (PF1 * K * _mn(1, sp / (PV0 * K)) + sp * PF2) * fb * dt;
          if (ns < 8 * K) {
            b.vx = 0;
            b.vy = 0;
          } else {
            final double k = _mn(ns, 2800 * K) / sp;
            b.vx *= k;
            b.vy *= k;
          }
        }
      }
      if (bl) {
        final double sp2 = math.sqrt(b.vx * b.vx + b.vy * b.vy);
        b.spin *= 1 - (sp2 > 0 ? 1.05 : 3.2) * dt;
        if (b.spin.abs() < .02) b.spin = 0;
        b.sq *= 1 - 9 * dt;
        final double roll = .95 / b.r, wx = -b.vy * roll, wy = b.vx * roll, wz = b.spin * .55;
        if (sp2 > 0 || wz != 0) {
          rot(b.R, wx, wy, wz, dt);
          b.rv++;
        }
        b.ang += b.spin * dt;
      } else {
        b.spin *= 1 - 2.6 * dt;
        b.ang += b.spin * dt;
      }
      walls(b);
    }
    for (int i = 0; i < 2; i++) {
      for (int a = 0; a < bodies.length; a++) {
        for (int c = a + 1; c < bodies.length; c++) {
          hit(bodies[a], bodies[c]);
        }
      }
    }
    if (bal != null) {
      for (final BmGoal g in GOALS) {
        post(bal, g.x1, g.y);
        post(bal, g.x2, g.y);
      }
    }
    for (final BmBody b in bodies) {
      walls(b);
    }
    if (phase == 'move' && !remote && bal != null) {
      for (final BmGoal g in GOALS) {
        if (bal.x > g.x1 && bal.x < g.x2 && (g.d < 0 ? bal.y < g.y - bal.r * .8 : bal.y > g.y + bal.r * .8)) {
          scored(g.team);
        }
      }
    }
  }

  // ---------------------------------------------------------------- flow
  void end() {
    hooks.sfx('fin');
    phase = 'over';
    if (_endEmitted) return;
    _endEmitted = true;
    hooks.emit('end', <String, dynamic>{
      'score': <int>[score[ct(0)], score[ct(1)]],
      'local': List<int>.from(score),
    });
  }

  void restart(int k) {
    score = <int>[0, 0];
    _endEmitted = false;
    mleft = mt.toDouble();
    sd = false;
    reset(ct(k));
  }

  bool canCtl() => !menuOpen && phase == 'aim' && !remote && turn != ai && !(mode == 'online' && turn != 0);

  void launch(BmBody b, double vx, double vy, bool fromRemote) {
    b.vx = vx;
    b.vy = vy;
    b.boost = .22;
    if (b.team != turn) turn = b.team;
    phase = 'move';
    idle = 0;
    shots++;
    remote = fromRemote;
    drag = null;
    hooks.tone('launch');
    burst(b.x, b.y, 10, 300, bcol(), .35);
    cam = _mx(cam, .25);
  }

  void fire(BmBody b, double dx, double dy, double l) {
    final double p = _mn(l, LMAX) / LMAX, v = (260 + 1085 * math.pow(p, .8).toDouble()) * K * 1.32, vx = dx / l * v, vy = dy / l * v;
    launch(b, vx, vy, false);
    final int sg = mirror ? -1 : 1;
    hooks.emit('shot', <String, dynamic>{'cid': b.cid, 'vx': vx * sg, 'vy': vy * sg, 'team': ct(b.team)});
  }

  void finishTurn(bool emitSnap) {
    turn = 1 - turn;
    phase = 'aim';
    tleft = tt;
    remote = false;
    aiT = 0;
    aiPlan = null;
    if (emitSnap && mode == 'online') hooks.emit('settled', <String, dynamic>{'snap': snapshot(), 'mt': mleft});
    hooks.emit('turn', <String, dynamic>{'turn': ct(turn), 'mine': turn == 0});
  }

  void skipTurn() {
    if (phase != 'aim') return;
    drag = null;
    aiPlan = null;
    toast('Time up');
    finishTurn(false);
  }

  Map<String, dynamic> snapshot() {
    List<double> f(double x, double y) => mirror ? <double>[2 * CX - x, 2 * CY - y] : <double>[x, y];
    return <String, dynamic>{
      'b': bodies.map((BmBody b) {
        final List<double> p = f(b.x, b.y);
        return <num>[b.cid, double.parse(p[0].toStringAsFixed(1)), double.parse(p[1].toStringAsFixed(1))];
      }).toList(),
      'sc': <int>[score[ct(0)], score[ct(1)]],
      'tn': ct(turn),
    };
  }

  void applySnapshot(Map<String, dynamic>? s) {
    if (s == null || s['b'] is! List) return;
    for (final dynamic e in s['b'] as List<dynamic>) {
      final List<dynamic> q = e as List<dynamic>;
      final int cid = (q[0] as num).toInt();
      final double x = (q[1] as num).toDouble(), y = (q[2] as num).toDouble();
      BmBody? b;
      for (final BmBody o in bodies) {
        if (o.cid == cid) b = o;
      }
      if (b == null) continue;
      b.x = mirror ? 2 * CX - x : x;
      b.y = mirror ? 2 * CY - y : y;
      b.vx = 0;
      b.vy = 0;
    }
  }

  // ---------------------------------------------------------------- remote API (game.js public API)
  void remoteShot(Map<String, dynamic> m) {
    final int cid = (m['cid'] as num).toInt();
    BmBody? b;
    for (final BmBody o in bodies) {
      if (o.cid == cid) b = o;
    }
    if (b == null) return;
    final int sg = mirror ? -1 : 1;
    launch(b, (m['vx'] as num).toDouble() * sg, (m['vy'] as num).toDouble() * sg, true);
  }

  void remoteSettled(Map<String, dynamic> m) {
    if (phase != 'move' && phase != 'aim') return;
    final Map<String, dynamic>? snap = (m['snap'] as Map?)?.cast<String, dynamic>();
    applySnapshot(snap);
    final num? mtv = m['mt'] as num?;
    if (mtv != null) syncClock(mtv.toDouble());
    // JS flips the turn here; when the local fallback (idle > 3 s) already flipped it, only adopt the snapshot.
    final num? tn = snap?['tn'] as num?;
    if (phase == 'aim' && tn != null && ct(turn) == tn.toInt()) return;
    finishTurn(false);
  }

  void remoteGoal(Map<String, dynamic> m) {
    if (phase == 'move' || phase == 'aim') scored(ct((m['team'] as num).toInt()), true);
  }

  void remoteTimeout(Map<String, dynamic> m) {
    final num? seat = m['seat'] as num?;
    if (seat != null && ct(turn) != seat.toInt()) return;
    skipTurn();
  }

  void syncClock(double sec) {
    if (mt > 0 && !sd && (mleft - sec).abs() > 1.2) mleft = _mx(0, sec);
  }

  // ---------------------------------------------------------------- timer + AI
  void timeCheck() {
    if (!(mt > 0) || sd || mleft > 0) return;
    if (score[0] != score[1]) {
      end();
    } else {
      sd = true;
      toast('Golden goal!');
      hooks.sfx('whs');
    }
  }

  void tick(double dt) {
    if (phase == 'aim') timeCheck();
    if (phase != 'aim') return;
    if (tt > 0) {
      tleft -= dt;
      if (tleft <= 0) {
        if (mode == 'online') {
          if (turn == 0) {
            hooks.emit('timeout', <String, dynamic>{'team': ct(0)});
            skipTurn();
          } else if (tleft < -4) {
            skipTurn();
          }
        } else {
          skipTurn();
        }
        return;
      }
    }
    if (turn == ai) aiTick(dt);
  }

  void aiTick(double dt) {
    if (phase != 'aim') return;
    if (aiPlan == null) {
      aiT += dt;
      if (aiT < .7 + R_() * .7) return;
      final BmAiPlan? p = aiDecide();
      aiPlan = p;
      if (p == null) return;
      p.t = 0;
      drag = BmDrag(p.b, p.b.x, p.b.y, p.b.x, p.b.y, ai: true);
      return;
    }
    final BmAiPlan p = aiPlan!;
    p.t += dt;
    final double k = _mn(1, p.t / .75), e = k * k * (3 - 2 * k);
    drag?.cx = p.b.x - p.dx * p.l * e;
    drag?.cy = p.b.y - p.dy * p.l * e;
    if (k >= 1) {
      drag = null;
      aiPlan = null;
      fire(p.b, p.dx * p.l, p.dy * p.l, p.l);
    }
  }

  static double segDist(double px, double py, double ax, double ay, double bx, double by) {
    final double vx = bx - ax, vy = by - ay;
    double l2 = vx * vx + vy * vy;
    if (l2 == 0) l2 = 1;
    double t = ((px - ax) * vx + (py - ay) * vy) / l2;
    t = _mx(0, _mn(1, t));
    final double qx = px - (ax + vx * t), qy = py - (ay + vy * t);
    return math.sqrt(qx * qx + qy * qy);
  }

  double gauss() => (R_() + R_() + R_() - 1.5) * 1.15;

  BmAiPlan? aiDecide() {
    final int me = turn;
    final BmBody bal = ball!;
    final List<BmBody> mine = bodies.where((BmBody b) => b.team == me && b != bal).toList();
    final BmGoal tg = GOALS[me], og = GOALS[1 - me];
    final int lvl = aiLvl;
    final double sg = <double>[.14, .06, .016][lvl], gw = (tg.x2 - tg.x1) / 2;
    final List<_Cand> cands = <_Cand>[];
    bool clear(BmBody p, double x, double y) {
      for (final BmBody o in bodies) {
        if (o == p || o == bal) continue;
        if (segDist(o.x, o.y, p.x, p.y, x, y) < p.r + o.r - 6) return false;
      }
      return true;
    }

    for (final BmBody p in mine) {
      for (final double ox in <double>[-.55, 0, .55]) {
        final double Tx = CX + ox * gw, Ty = tg.y;
        double ux = Tx - bal.x, uy = Ty - bal.y;
        double ul = math.sqrt(ux * ux + uy * uy);
        if (ul == 0) ul = 1;
        ux /= ul;
        uy /= ul;
        final double cx = bal.x - ux * (p.r + bal.r + 1), cy = bal.y - uy * (p.r + bal.r + 1);
        double vx = cx - p.x, vy = cy - p.y;
        final double dist = math.sqrt(vx * vx + vy * vy);
        if (dist < 8) continue;
        vx /= dist;
        vy /= dist;
        final double al = vx * ux + vy * uy;
        if (al < .2) continue;
        if (!clear(p, cx, cy)) continue;
        int blk = 0;
        for (final BmBody o in bodies) {
          if (o.team == me || o == bal) continue;
          if (segDist(o.x, o.y, bal.x, bal.y, Tx, Ty) < bal.r + o.r + 6) blk++;
        }
        cands.add(_Cand(p, vx, vy, 100 * al - dist * .03 - blk * 28 + ((bal.y - Ty).abs() < 420 ? 25 : 0), dist, true));
      }
      double vx = bal.x - p.x, vy = bal.y - p.y;
      final double dist = math.sqrt(vx * vx + vy * vy);
      if (dist > 8) {
        vx /= dist;
        vy /= dist;
        if (clear(p, bal.x, bal.y)) {
          final double toOwn = (vy * (og.y - bal.y) > 0) ? vy.abs() : 0;
          cands.add(_Cand(p, vx, vy, 10 - dist * .04 - toOwn * 55, dist, false));
        }
      }
    }
    if (cands.isEmpty) {
      final List<BmBody> s = List<BmBody>.from(mine)
        ..sort((BmBody a, BmBody b) =>
            _h(a.x - bal.x, a.y - bal.y).compareTo(_h(b.x - bal.x, b.y - bal.y)));
      if (s.isEmpty) return null;
      final BmBody p = s.first;
      final double vx = bal.x - p.x, vy = bal.y - p.y;
      double d = _h(vx, vy);
      if (d == 0) d = 1;
      cands.add(_Cand(p, vx / d, vy / d, 0, d, false));
    }
    cands.sort((_Cand a, _Cand b) => b.sc.compareTo(a.sc));
    final List<_Cand> pool = cands.sublist(0, math.min<int>(cands.length, <int>[4, 2, 1][lvl]));
    final _Cand c = pool[(R_() * pool.length).floor()];
    final double ang = math.atan2(c.dy, c.dx) + gauss() * sg;
    double pw = lvl == 2 ? _mn(1, .66 + c.dist / 1000) : _mn(1, .5 + c.dist / 1100);
    if (lvl == 0) pw *= .7 + R_() * .3;
    if (c.atk && lvl > 0) pw = _mx(pw, .78);
    return BmAiPlan(c.p, math.cos(ang), math.sin(ang), _mx(.3, pw) * LMAX);
  }

  static double _h(double x, double y) => math.sqrt(x * x + y * y);

  // ---------------------------------------------------------------- fx state (game.js fx())
  void fx(double dt) {
    final BmBody? bal = ball;
    for (final BmBody b in bodies) {
      if (b == bal) continue;
      final double sp = _h(b.vx, b.vy);
      if (sp > 140 * K) {
        b.tr.add(BmTrailPt(b.x, b.y, sp));
      } else if (b.tr.isNotEmpty) {
        b.tr.removeAt(0);
      }
      if (b.tr.length > 14) b.tr.removeAt(0);
      if (sp > 420 * K && R_() < dt * 34 && parts.length < 300) {
        final double ux = b.vx / sp, uy = b.vy / sp, o = (R_() - .5) * b.r * 1.6;
        spawn(b.x - ux * b.r * .8 - uy * o, b.y - uy * b.r * .8 + ux * o, -ux * 260, -uy * 260, .22, 2.2,
            b.team != 0 ? 0xFFFF9A9A : 0xFF9FD0FF, 5);
      }
    }
    for (final BmBody b in bodies) {
      if (b != bal && b.sq != 0) b.sq = b.sq > .02 ? b.sq - dt * 5 : 0;
    }
    if (bal != null && phase != 'over') {
      final double sp = _h(bal.vx, bal.vy);
      if (sp > 350 * K) trail.add(BmTrailPt(bal.x, bal.y, sp, h: sp > 1250 * K));
      if (sp > 300 * K && !menuOpen) {
        final double f = _mn(1, sp / (2300 * K));
        final BmTrail st = kBmTR[setBall % kBmTR.length];
        final List<int> c = st.c;
        final BmFa fa = kBmFA[field.id] ?? kBmFA['stadium']!;
        final double bx = bal.x, by = bal.y, ux = bal.vx / sp, uy = bal.vy / sp;
        fxAcc += dt * (26 + 70 * f);
        while (fxAcc >= 1) {
          fxAcc--;
          final double o = (R_() - .5) * BR * 1.4, px = bx - ux * BR * .6 - uy * o, py = by - uy * BR * .6 + ux * o;
          final double sx = (R_() - .5) * 260 - ux * 120, sy = (R_() - .5) * 260 - uy * 120;
          switch (st.k) {
            case 'bolt':
              spawn(px, py, sx * 1.6, sy * 1.6, .28, 2.2, R_() < .5 ? c[1] : c[2], 5);
              break;
            case 'prism':
              spawn(px, py, sx * .4, sy * .4, .5, 4 + R_() * 3, bmHsl(R_() * 360, 65), 0);
              break;
            case 'wave':
              spawn(px, py, sx * .3, sy * .3 - 40, .6, 3 + R_() * 3, c[R_() < .5 ? 0 : 1], 4, -60);
              break;
            case 'star':
              spawn(px, py, sx * .4, sy * .4, .7, 5 + R_() * 6, R_() < .4 ? c[2] : c[1], 1);
              break;
            case 'smoke':
              break;
            case 'rainbow':
              spawn(px, py, sx * .5, sy * .5, .6, 3 + R_() * 3, bmHsl(R_() * 360, 62), 3, 60);
              break;
            case 'neon':
              spawn(px, py, sx * .5, sy * .5, .45, 3 + R_() * 3, R_() < .5 ? c[0] : c[1], 3);
              break;
            case 'yin':
              spawn(px, py, sx * .4, sy * .4, .55, 3 + R_() * 4, R_() < .5 ? 0xFFFFFFFF : 0xFFA066FF, 0);
              break;
            case 'fire':
              spawn(px, py, sx * .35, sy * .35 - 90, .55, 6 + R_() * 7, c[R_() < .5 ? 0 : 1], 2, -260);
              break;
            case 'blade':
              spawn(px, py, -ux * 600 + sx * .2, -uy * 600 + sy * .2, .22, 2.2, c[R_() < .5 ? 0 : 1], 5);
              break;
            case 'ghost':
              if (R_() < .3) spawn(px, py, sx * .2, sy * .2, .7, 4, c[1], 1);
              break;
            case 'ember':
              spawn(px, py, sx * .5, sy * .5 - 60, .8, 2.5 + R_() * 2.5, c[R_() < .5 ? 0 : 1], 0, -150);
              break;
            case 'plasma':
              final double a = R_() * 6.28;
              spawn(px + math.cos(a) * 12, py + math.sin(a) * 12, math.cos(a) * 90 + sx * .2, math.sin(a) * 90 + sy * .2, .45,
                  3 + R_() * 3, c[R_() < .5 ? 0 : 1], 0);
              break;
          }
        }
        fxAcc2 += dt * (14 + 44 * f);
        while (fxAcc2 >= 1) {
          fxAcc2--;
          final double o = (R_() - .5) * BR * 2.4, px = bx - ux * BR - uy * o, py = by - uy * BR + ux * o;
          spawn(px, py, (R_() - .5) * 150, (R_() - .5) * 150, .55 + R_() * .5, (fa.k == 0 ? 2.2 : 4) + R_() * 4,
              fa.c[(R_() * fa.c.length).floor()], fa.k, fa.g);
        }
      }
    }
  }

  // ---------------------------------------------------------------- main loop (game.js loop)
  void frame(double rawDt) {
    final double dt = _mn(rawDt <= 0 ? .016 : rawDt, .05);
    _clock += dt;
    if (_timers.isNotEmpty) {
      final List<MapEntry<double, void Function()>> due =
          _timers.where((MapEntry<double, void Function()> e) => e.key <= _clock).toList();
      _timers.removeWhere((MapEntry<double, void Function()> e) => e.key <= _clock);
      for (final MapEntry<double, void Function()> e in due) {
        e.value();
      }
    }
    if (!menuOpen && bodies.isNotEmpty) {
      if (mt > 0 && !sd && phase != 'over' && mleft > 0) mleft = _mx(0, mleft - dt);
      double ts = 1;
      if (freeze > 0) {
        freeze -= dt;
        ts = 0;
      } else if (slow > 0) {
        slow -= dt;
        ts = .32 + .68 * math.pow(1 - _mx(0, slow) / 1.1, 2).toDouble();
      }
      acc += dt * ts;
      int n = 0;
      if (phase != 'over') {
        while (acc >= STEP && n++ < 14) {
          sim(STEP);
          acc -= STEP;
        }
        if (n > 14) acc = 0;
      }
      if (phase == 'move') {
        idle = bodies.any((BmBody b) => b.vx != 0 || b.vy != 0) ? 0 : idle + dt;
        if (idle > .25) {
          if (!remote) {
            finishTurn(true);
          } else if (idle > 3) {
            finishTurn(false);
          }
        }
      } else if (phase == 'aim') {
        tick(dt);
      } else if (phase == 'goal') {
        pause -= dt;
        if (pause <= 0) {
          if (mt > 0) {
            if (sd || (mleft <= 0 && score[0] != score[1])) {
              end();
            } else {
              if (mleft <= 0) sd = true;
              reset(kick);
            }
          } else if (score[0] >= setLim || score[1] >= setLim) {
            end();
          } else {
            reset(kick);
          }
        }
      }
      fx(dt);
    }
    flash = _mx(0, flash - dt * 2);
    cam = _mx(0, cam - dt * 3.2);
    for (final BmRing r in rings) {
      r.l -= dt;
    }
    rings.removeWhere((BmRing r) => r.l <= 0);
    shake[0] = _mx(0, shake[0] - dt);
    shake[1] = _mx(0, shake[1] - dt);
    for (final BmTrailPt p in trail) {
      p.a -= dt * 3;
    }
    trail.removeWhere((BmTrailPt p) => p.a <= 0);
    for (final BmPart p in parts) {
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.vx *= .97;
      p.vy = p.vy * .97 + p.g * dt;
      p.rot += dt * 4;
      p.l -= dt;
    }
    parts.removeWhere((BmPart p) => p.l <= 0);
  }

  // ---------------------------------------------------------------- start
  void startMatch(BmConfig cfg) {
    _later(.25, () => hooks.sfx('whs'));
    mode = cfg.mode;
    names = List<String>.from(cfg.names);
    mirror = cfg.mirror;
    ai = cfg.ai ? 1 : -1;
    aiLvl = cfg.aiLvl;
    tt = cfg.turnTime;
    mt = cfg.matchTime;
    mleft = mt.toDouble();
    sd = false;
    sel = List<String>.from(cfg.teams);
    form = List<int>.from(cfg.form);
    setFld = cfg.field;
    setBall = cfg.ball;
    setLim = cfg.matchTime > 0 ? 9999 : (cfg.limit == 0 ? 5 : cfg.limit);
    geo();
    score = <int>[0, 0];
    _endEmitted = false;
    reset(ct(cfg.first));
    inMatch = true;
    menuOpen = false;
  }

  void stop() {
    inMatch = false;
    phase = 'over';
    bodies = <BmBody>[];
    menuOpen = true;
  }

  // ---------------------------------------------------------------- touch input (world coords)
  void pointerDown(double px, double py) {
    if (!canCtl()) return;
    BmBody? f;
    double bd = 1e9;
    for (final BmBody b in bodies) {
      if (b.team == turn && b != ball) {
        final double d = _h(px - b.x, py - b.y);
        if (d < b.r + 30 && d < bd) {
          f = b;
          bd = d;
        }
      }
    }
    if (f == null) return;
    drag = BmDrag(f, px, py, px, py);
  }

  void pointerMove(double px, double py) {
    final BmDrag? d = drag;
    if (d != null && !d.ai) {
      d.cx = px;
      d.cy = py;
    }
  }

  void pointerUp() {
    final BmDrag? d = drag;
    if (d == null || d.ai) return;
    final double dx = d.sx - d.cx, dy = d.sy - d.cy, l = _h(dx, dy);
    drag = null;
    if (l > 18) fire(d.b, dx, dy, l);
  }

  void pointerCancel() {
    if (drag != null && !drag!.ai) drag = null;
  }
}

class _Cand {
  _Cand(this.p, this.dx, this.dy, this.sc, this.dist, this.atk);
  final BmBody p;
  final double dx, dy, sc, dist;
  final bool atk;
}

/// hsl(h, 100%, l%) as ARGB (game.js hsl()).
int bmHsl(double h, [double l = 60]) => bmHslColor(((h % 360) + 360) % 360, 1, l / 100);

int bmHslColor(double h, double s, double l) {
  final double c = (1 - (2 * l - 1).abs()) * s, hp = (h.floorToDouble() % 360) / 60, x = c * (1 - (hp % 2 - 1).abs()), m = l - c / 2;
  double r = 0, g = 0, b = 0;
  if (hp < 1) {
    r = c;
    g = x;
  } else if (hp < 2) {
    r = x;
    g = c;
  } else if (hp < 3) {
    g = c;
    b = x;
  } else if (hp < 4) {
    g = x;
    b = c;
  } else if (hp < 5) {
    r = x;
    b = c;
  } else {
    r = c;
    b = x;
  }
  int q(double v) => ((v + m) * 255).round().clamp(0, 255).toInt();
  return 0xFF000000 | (q(r) << 16) | (q(g) << 8) | q(b);
}


double _mn(double a, double b) => a < b ? a : b;
double _mx(double a, double b) => a > b ? a : b;
