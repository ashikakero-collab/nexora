// Online match netcode (port of the protocol in src/online/OnlineMatch.tsx, extended additively).
//
// Legacy protocol (RN, unchanged, always spoken by a Flutter host):
//   {k:'s', s:Snap}   host snapshot: q, ts, hz, ph, tu, sc, ml, tl, su, c(controller uid), n(turn seq),
//                     p:[x*10, y*10, ang*100 per body], R:[9 ints *1000], ev:[[code,...]] (codes 0-7)
//   {k:'shot', b, dx, dy, n}   controller -> host       {k:'aim', b, dx, dy} / {k:'aim', b:-1}
//   {k:'res', winner, rd, score, ok}   {k:'abort'}
//
// Additive Flutter extensions (ignored by RN builds; RN rooms keep working):
//   s.lk = 1            host runs the deterministic lockstep protocol below
//   s.h  = int          FNV-1a hash of the exact rest state (sent with every rest snapshot)
//   s.x  = base64       exact Float64 x,y of every body (rest keyframes: first after each turn/reset,
//                       every 5th rest snapshot, and on request)
//   {k:'f', b, n, d}    shot broadcast: d = base64 Float64[ux, uy, v, power] -> every peer runs the same
//                       deterministic engine (fdlibm math, fixed 240 Hz sub-steps) and gets identical motion
//   shot.ux/uy/p        the shooter's final direction (accuracy deviation applied locally) so the shooter can
//                       predict its own shot with zero latency; RN hosts ignore these and use dx/dy
//   {k:'rq'}            client asks for a keyframe (reconnect / hash mismatch)
// Rate: with only Flutter peers the host sends 6 Hz while moving and 1 Hz at rest (vs 20-30 Hz / 2 Hz),
// i.e. ~4-5x fewer messages; with any RN peer present it keeps the legacy rates.
// Clients fall back to RN-style snapshot interpolation (jitter buffer ~1.7 intervals) whenever they are not
// in sync (joined mid-shot, missed a shot message, legacy host).
//
// Physics profile negotiation (additive, run 5):
//   s.pf = 'stars' | 'classic'   the engine profile the host runs (sent with every snapshot).
// The engine default is 'stars' (Soccer Stars feel), but RN and Godot peers simulate classic-like physics.
// The host picks the profile once, when the match screen opens (pickProfile): 'stars' only if every other
// room member (players AND spectators) is connected and advertises the Flutter presence capability
// (presence payload c:'fl', see link.dart); otherwise 'classic'. The choice is fixed for the whole match.
// Flutter clients do not build their engine until the first host snapshot arrives; they build it with
// snapProfile(s) - the host's pf, or 'classic' when pf is missing (legacy RN/Godot host) or unknown.
// A client whose engine profile differs from the host's never enters lockstep (snapshot interpolation only).
// Someone joining with an RN/Godot build after a 'stars' match started just interpolates the snapshots.
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../game/engine.dart';

const _tau = math.pi * 2;

List<int> encEv(EngineEvent e) => switch (e.t) {
      EvType.hit => [0, e.ball ? 1 : 0, (e.power * 100).round()],
      EvType.wall => [1, (e.power * 100).round()],
      EvType.post => [2, (e.power * 100).round()],
      EvType.goal => [3, e.team, e.nogoal ? 1 : 0],
      EvType.turn => [4, e.team],
      EvType.shot => [5, e.team],
      EvType.end => [6, e.s0, e.s1],
      EvType.clock => [7],
    };

EngineEvent decEv(List a) {
  final e = EngineEvent();
  int at(int i) => i < a.length && a[i] is num ? (a[i] as num).toInt() : 0;
  switch (at(0)) {
    case 0:
      e
        ..t = EvType.hit
        ..ball = at(1) == 1
        ..power = at(2) / 100;
    case 1:
      e
        ..t = EvType.wall
        ..power = at(1) / 100;
    case 2:
      e
        ..t = EvType.post
        ..power = at(1) / 100;
    case 3:
      e
        ..t = EvType.goal
        ..team = at(1)
        ..nogoal = at(2) == 1;
    case 4:
      e
        ..t = EvType.turn
        ..team = at(1);
    case 5:
      e
        ..t = EvType.shot
        ..team = at(1);
    case 6:
      e
        ..t = EvType.end
        ..s0 = at(1)
        ..s1 = at(2);
    default:
      e.t = EvType.clock;
  }
  return e;
}

String packF64(List<double> v) => base64.encode(Float64List.fromList(v).buffer.asUint8List());
Float64List? unpackF64(Object? s) {
  if (s is! String) return null;
  try {
    final b = base64.decode(s);
    if (b.length % 8 != 0) return null;
    return Float64List.view(Uint8List.fromList(b).buffer);
  } catch (_) {
    return null;
  }
}

/// FNV-1a over the exact IEEE bits of every body position.
int stateHash(Engine e) {
  final bd = ByteData(8);
  var h = 0x811c9dc5;
  for (final b in e.bodies) {
    for (final v in [b.x, b.y]) {
      bd.setFloat64(0, v, Endian.little);
      for (var i = 0; i < 8; i++) {
        h ^= bd.getUint8(i);
        h = (h * 0x01000193) & 0xffffffff;
      }
    }
  }
  return h;
}

const kNetProfiles = {'stars', 'godot', 'classic'};

/// Host-side choice: 'stars' only when every other member is online with the Flutter capability flag.
/// [members] = every room member uid (players + spectators); [online] = presence uid -> advertises c:'fl'.
String pickProfile({required String me, required Iterable<String> members, required Map<String, bool> online}) {
  for (final e in online.entries) {
    if (e.key != me && !e.value) return 'classic';
  }
  for (final u in members) {
    if (u != me && online[u] != true) return 'classic'; // absent = unknown client, play safe
  }
  return 'stars';
}

/// Profile a host snapshot announces; legacy hosts (no pf) and unknown values mean 'classic'.
String snapProfile(Map s) {
  final pf = s['pf'];
  return pf is String && kNetProfiles.contains(pf) ? pf : 'classic';
}

/// For a raw game message: the host's profile if it is a snapshot, else null.
String? msgProfile(Map<String, dynamic> m) => m['k'] == 's' && m['s'] is Map ? snapProfile(m['s'] as Map) : null;

bool atRest(Engine e) => e.bodies.every((b) => b.vx == 0 && b.vy == 0);

class Player {
  final String uid;
  final int team, slot;
  final String disc;
  const Player(this.uid, this.team, this.slot, this.disc);
}

/// Everything the controller needs from the outside world (RoomLink in the app, a fake bus in tests).
abstract class NetPort {
  String get me;
  void send(Map<String, dynamic> m);
  bool isOnline(String uid);
  bool get allFlutter;
  int get peers;
  List<Player> get players;
  DiscStats statsFor(String disc);
}

enum NetMode { host, lockstep, interp }

class _Snap {
  final Map<String, dynamic> raw;
  final int q, ts, hz, n;
  final List<num> p;
  final List<num> R;
  _Snap(this.raw)
      : q = (raw['q'] as num?)?.toInt() ?? 0,
        ts = (raw['ts'] as num?)?.toInt() ?? 0,
        hz = (raw['hz'] as num?)?.toInt() ?? 12,
        n = (raw['n'] as num?)?.toInt() ?? 0,
        p = (raw['p'] as List?)?.whereType<num>().toList() ?? const [],
        R = (raw['R'] as List?)?.whereType<num>().toList() ?? const [];
  String get ph => raw['ph']?.toString() ?? 'aim';
}

Phase _phase(String s) => switch (s) { 'move' => Phase.move, 'goal' => Phase.goal, 'over' => Phase.over, _ => Phase.aim };

class NetMatch {
  final Engine eng;
  final bool isHost;
  final NetPort port;
  final void Function(EngineEvent ev, bool local) onEvent;

  // host state
  final List<int> turnCount = [0, 0];
  int seq = 0, _q = 0, _lastSend = 0, _restSends = 0;
  String? ctrl;
  final List<List<int>> _evs = [];
  bool _keyNext = true, _keyAsked = false;

  // client state
  final List<_Snap> _buf = [];
  final List<(int, int)> _offs = [];
  int _applied = -1, lastRecv = 0, pendingShot = 0;
  bool got = false, lockHost = false, synced = false, simulating = false;
  Float64List? _pendingKey;
  int _pendingAt = 0, _lastRq = 0, cseq = 0;
  (int, double, double, double, double)? _pred; // predicted shot: n, ux, uy, v, p
  Float64List? _prev;
  Map<String, dynamic>? result;
  int desyncs = 0, corrections = 0, resets = 0;
  int _shotSeqSeen = -1;

  NetMatch({required this.eng, required this.isHost, required this.port, required this.onEvent}) {
    if (!isHost) {
      eng.slave = true;
      eng.cfg.ai = false;
    }
  }

  NetMode get mode => isHost ? NetMode.host : (lockHost && synced ? NetMode.lockstep : NetMode.interp);
  String? get controller => isHost ? ctrl : _cctrl;
  String? _cctrl;

  List<Player> _team(int t) => port.players.where((p) => p.team == t).toList()..sort((a, b) => a.slot.compareTo(b.slot));

  String? ctrlFor(int t) {
    final team = _team(t);
    if (team.isEmpty) return null;
    final n = team.length, st0 = ((turnCount[t] - 1) % n + n) % n;
    for (var i = 0; i < n; i++) {
      final pl = team[(st0 + i) % n];
      if (pl.uid == port.me || port.isOnline(pl.uid)) return pl.uid;
    }
    return null;
  }

  /// The player in control flicks with their own equipped disc's stats.
  void _syncStats() {
    final cu = controller, st = eng.cfg.stats;
    if (cu == null || st == null) return;
    final pl = port.players.where((x) => x.uid == cu).firstOrNull;
    if (pl != null) st[eng.turn] = port.statsFor(pl.disc);
  }

  // ------------------------------------------------------------------ host
  void _hostTick(double dt, int now) {
    _syncStats();
    eng.update(dt);
    var urgent = false;
    if (eng.eventCount > 0) {
      final evs = <EngineEvent>[];
      for (var i = 0; i < eng.eventCount; i++) {
        final ev = eng.event(i);
        if (ev.t == EvType.shot) {
          final b = eng.lastShot;
          if (b != null) port.send({'k': 'f', 'b': b.id, 'n': seq, 'd': packF64([eng.lastUx, eng.lastUy, eng.lastV, eng.lastPower])});
        }
        if (ev.t == EvType.turn) {
          turnCount[ev.team]++;
          seq++;
          _keyNext = true;
        }
        if (ev.t == EvType.goal) _keyNext = true;
        _evs.add(encEv(ev));
        if (ev.t != EvType.hit && ev.t != EvType.wall && ev.t != EvType.post) urgent = true;
        evs.add(EngineEvent()
          ..t = ev.t
          ..ball = ev.ball
          ..power = ev.power
          ..team = ev.team
          ..nogoal = ev.nogoal
          ..s0 = ev.s0
          ..s1 = ev.s1);
      }
      eng.clearEvents();
      ctrl = eng.phase == Phase.over ? null : ctrlFor(eng.turn);
      for (final ev in evs) {
        onEvent(ev, true);
      }
    }
    final c = eng.phase == Phase.over ? null : ctrlFor(eng.turn);
    if (c != ctrl) {
      ctrl = c;
      urgent = true;
      if (c != port.me && eng.drag != null && !eng.drag!.ai) eng.drag = null;
    }
    final ai = c == null && eng.phase != Phase.over;
    if (eng.aiTeams[eng.turn] != ai || eng.aiTeams[1 - eng.turn]) {
      eng.aiTeams[0] = false;
      eng.aiTeams[1] = false;
      eng.aiTeams[eng.turn] = ai;
      if (!ai) {
        eng.aiPlan = null;
        if (eng.drag?.ai == true) eng.drag = null;
      }
    }
    sendSnap(now, force: urgent);
  }

  void sendSnap(int now, {bool force = false, bool key = false}) {
    final lean = port.allFlutter;
    final rec = math.max(1, port.peers);
    final hz = lean ? 6 : (rec <= 1 ? 30 : rec <= 3 ? 25 : 20);
    final moving = eng.phase == Phase.move || eng.phase == Phase.goal;
    final restGap = lean ? 1000 : 500;
    if (!force && !key && now - _lastSend < (moving ? 1000 ~/ hz : restGap)) return;
    _lastSend = now;
    final p = <int>[];
    for (final b in eng.bodies) {
      p
        ..add((b.x * 10).round())
        ..add((b.y * 10).round())
        ..add(((((b.ang % _tau) + _tau) % _tau) * 100).round());
    }
    final s = <String, dynamic>{
      'q': ++_q, 'ts': now, 'hz': hz, 'ph': eng.phase.name, 'tu': eng.turn, 'sc': [eng.score[0], eng.score[1]],
      'ml': (eng.mleft * 10).round() / 10, 'tl': (eng.tleft * 10).round() / 10, 'su': eng.sudden ? 1 : 0, 'c': ctrl, 'n': seq,
      'p': p, 'R': [for (final v in eng.ball.R) (v * 1000).round()], 'ev': List.of(_evs), 'lk': 1,
      'pf': eng.cfg.profile,
    };
    _evs.clear();
    if (!moving && atRest(eng)) {
      s['h'] = stateHash(eng);
      _restSends++;
      if (_keyNext || key || _keyAsked || _restSends % 5 == 0) {
        s['x'] = packF64([for (final b in eng.bodies) ...[b.x, b.y]]);
        _keyNext = false;
        _keyAsked = false;
      }
    }
    port.send({'k': 's', 's': s});
  }

  // ---------------------------------------------------------------- client
  void _applyScalars(_Snap s, {required bool lock}) {
    final r = s.raw;
    eng.phase = _phase(s.ph);
    eng.turn = (r['tu'] as num?)?.toInt() == 1 ? 1 : 0;
    final sc = r['sc'] as List?;
    if (sc != null && sc.length == 2) {
      eng.score[0] = (sc[0] as num).toInt();
      eng.score[1] = (sc[1] as num).toInt();
    }
    eng.mleft = (r['ml'] as num?)?.toDouble() ?? eng.mleft;
    eng.tleft = (r['tl'] as num?)?.toDouble() ?? eng.tleft;
    eng.sudden = r['su'] == 1;
    _cctrl = r['c']?.toString();
    cseq = s.n;
    eng.aiTeams[0] = false;
    eng.aiTeams[1] = false;
    if (_cctrl == null) eng.aiTeams[eng.turn] = true;
    if (eng.phase != Phase.aim && eng.drag != null && !eng.drag!.ai) eng.drag = null;
    for (final e in (r['ev'] as List? ?? const [])) {
      if (e is! List) continue;
      final ev = decEv(e);
      // in lockstep the local engine already produced the contact sounds and the shot
      if (lock && (ev.t == EvType.hit || ev.t == EvType.wall || ev.t == EvType.post || ev.t == EvType.shot)) continue;
      if (ev.t == EvType.goal && !ev.nogoal) eng.fxGoal(ev.team);
      onEvent(ev, false);
    }
  }

  void _placeBodies(_Snap a, _Snap? b, double k, double dt) {
    final n = eng.bodies.length;
    if (a.p.length < n * 3) return;
    if (_prev == null || _prev!.length != n * 2) _prev = Float64List(n * 2);
    final pv = _prev!;
    for (var i = 0; i < n; i++) {
      final bd = eng.bodies[i];
      var x = a.p[i * 3] / 10, y = a.p[i * 3 + 1] / 10, ang = a.p[i * 3 + 2] / 100;
      if (b != null && b.p.length >= n * 3) {
        x += (b.p[i * 3] / 10 - x) * k;
        y += (b.p[i * 3 + 1] / 10 - y) * k;
        var da = b.p[i * 3 + 2] / 100 - ang;
        if (da > math.pi) {
          da -= _tau;
        } else if (da < -math.pi) {
          da += _tau;
        }
        ang += da * k;
      }
      final px = pv[i * 2], py = pv[i * 2 + 1];
      bd.vx = got ? (x - px) / math.max(dt, 1e-3) : 0;
      bd.vy = got ? (y - py) / math.max(dt, 1e-3) : 0;
      if (bd.vx.abs() < 4) bd.vx = 0;
      if (bd.vy.abs() < 4) bd.vy = 0;
      bd.x = bd.px = x;
      bd.y = bd.py = y;
      bd.ang = ang;
      bd.vox = 0;
      bd.voy = 0;
      pv[i * 2] = x;
      pv[i * 2 + 1] = y;
    }
    final src = (b != null && k > .5 ? b : a).R;
    if (src.length == 9) {
      for (var j = 0; j < 9; j++) {
        eng.ball.R[j] = src[j] / 1000;
      }
    }
    got = true;
    eng.acc = 0;
  }

  /// Snap to the host's exact rest state; small differences blend through the visual offset.
  void _applyKey(Float64List x) {
    final n = eng.bodies.length;
    if (x.length < n * 2) return;
    var maxd = 0.0;
    for (var i = 0; i < n; i++) {
      final b = eng.bodies[i];
      final dx = b.x - x[i * 2], dy = b.y - x[i * 2 + 1];
      maxd = math.max(maxd, math.max(dx.abs(), dy.abs()));
    }
    if (maxd > 0 && maxd < 30 && synced) corrections++;
    if (maxd >= 30) resets++;
    for (var i = 0; i < n; i++) {
      final b = eng.bodies[i];
      final nx = x[i * 2], ny = x[i * 2 + 1];
      if (maxd < 30 && synced) {
        b.vox += b.x - nx;
        b.voy += b.y - ny;
      } else {
        b.vox = 0;
        b.voy = 0;
      }
      b.x = b.px = nx;
      b.y = b.py = ny;
      b.vx = 0;
      b.vy = 0;
      b.tvx = 0;
      b.tvy = 0;
      b.ramp = 0;
      b.boost = 0;
      b.gout = null;
    }
    synced = true;
    simulating = false;
    got = true;
    _pendingKey = null;
  }

  void _clientTick(double dt, int now) {
    _syncStats();
    if (lockHost && synced) {
      // local deterministic physics
      eng.update(dt);
      for (var i = 0; i < eng.eventCount; i++) {
        final ev = eng.event(i);
        if (ev.t == EvType.hit || ev.t == EvType.wall || ev.t == EvType.post || ev.t == EvType.shot) {
          onEvent(EngineEvent()
            ..t = ev.t
            ..ball = ev.ball
            ..power = ev.power
            ..team = ev.team, true);
        }
      }
      eng.clearEvents();
      if (simulating && atRest(eng)) simulating = false;
      // scalars arrive with a small delay buffer so banners line up with what is on screen
      final owd = 60;
      for (final s in _buf) {
        if (s.q > _applied && now - (s.raw['_rx'] as int) >= owd) {
          _applied = s.q;
          _applyScalars(s, lock: true);
          final x = unpackF64(s.raw['x']);
          final h = (s.raw['h'] as num?)?.toInt();
          if (x != null) {
            _pendingKey = x;
            _pendingAt = now;
          } else if (h != null && !simulating && atRest(eng) && _pendingKey == null && stateHash(eng) != h) {
            desyncs++;
            _askKey(now);
          }
        }
      }
      if (_buf.length > 8) _buf.removeRange(0, _buf.length - 8);
      if (_pendingKey != null && (atRest(eng) || now - _pendingAt > 450)) _applyKey(_pendingKey!);
      // local timers between (1 Hz) snapshots
      if (eng.phase == Phase.aim && eng.cfg.turnTime > 0) eng.tleft = math.max(0, eng.tleft - dt);
      if (eng.cfg.matchTime > 0 && !eng.sudden && eng.phase != Phase.over && eng.phase != Phase.goal) eng.mleft = math.max(0, eng.mleft - dt);
    } else {
      _interp(dt, now);
      eng.tickFx(dt);
    }
  }

  void _interp(double dt, int now) {
    final off = _offs.isEmpty ? 0 : _offs.map((o) => o.$2).reduce(math.min);
    final hz = _buf.isNotEmpty ? (_buf.last.hz == 0 ? 12 : _buf.last.hz) : 12;
    final rt = now - off - 1700 / hz;
    bool apply(_Snap s) {
      _applied = s.q;
      _applyScalars(s, lock: false);
      final x = unpackF64(s.raw['x']);
      if (x != null && lockHost) {
        _applyKey(x); // now in sync: switch to lockstep from the next shot
        return true;
      }
      return false;
    }

    for (final s in _buf) {
      if (s.q > _applied && s.ts <= rt && apply(s)) return;
    }
    if (_buf.isEmpty) return;
    var i = 0;
    while (i + 1 < _buf.length && _buf[i + 1].ts <= rt) {
      i++;
    }
    final a = _buf[i], b = i + 1 < _buf.length ? _buf[i + 1] : null;
    final k = b != null ? ((rt - a.ts) / math.max(1, b.ts - a.ts)).clamp(0.0, 1.0) : 0.0;
    if (a.ts <= rt || !got) {
      if (_applied < a.q && !got && apply(a)) return;
      final pv = i > 0 ? _buf[i - 1] : null;
      if (b == null && pv != null && (a.ph == 'move' || a.ph == 'goal') && rt > a.ts) {
        _placeBodies(pv, a, 1 + math.min(120, rt - a.ts) / math.max(1, a.ts - pv.ts), dt);
      } else {
        _placeBodies(a, b, k, dt);
      }
    }
    if (i > 3) _buf.removeRange(0, i - 3);
  }

  void _askKey(int now) {
    if (now - _lastRq < 1000) return;
    _lastRq = now;
    port.send({'k': 'rq'});
  }

  /// Called by the screen after a reconnect.
  void resync(int now) {
    if (isHost) {
      sendSnap(now, key: true);
    } else {
      synced = false;
      _askKey(now - 2000);
    }
  }

  // --------------------------------------------------------------- messages
  void onMessage(Map<String, dynamic> m, String? from, int now) {
    final k = m['k'];
    if (k == 's' && !isHost) {
      final raw = m['s'];
      if (raw is! Map) return;
      final s = _Snap(Map<String, dynamic>.from(raw)..['_rx'] = now);
      lastRecv = now;
      // lockstep only makes sense when both sides run the same physics profile
      lockHost = s.raw['lk'] == 1 && snapProfile(s.raw) == eng.cfg.profile;
      _offs.add((now, now - s.ts));
      while (_offs.isNotEmpty && now - _offs.first.$1 > 4000) {
        _offs.removeAt(0);
      }
      if (_buf.isEmpty || s.q > _buf.last.q) {
        _buf.add(s);
      } else {
        _buf
          ..add(s)
          ..sort((a, b) => a.q.compareTo(b.q));
      }
      if (_buf.length > 60) _buf.removeRange(0, _buf.length - 60);
    } else if (k == 'f' && !isHost) {
      lastRecv = now;
      final d = unpackF64(m['d']);
      final n = (m['n'] as num?)?.toInt() ?? -1;
      final bid = (m['b'] as num?)?.toInt() ?? -1;
      if (d == null || d.length < 4) return;
      if (n == _shotSeqSeen) return;
      _shotSeqSeen = n;
      final pr = _pred;
      if (pr != null && pr.$1 == n) {
        _pred = null;
        if (pr.$2 == d[0] && pr.$3 == d[1] && pr.$4 == d[2] && pr.$5 == d[3]) return; // our prediction was exact
        desyncs++;
        synced = false; // fall back to interpolation until the next keyframe
        return;
      }
      if (!synced || !lockHost) return;
      final b = eng.bodies.where((x) => x.id == bid).firstOrNull;
      if (b == null) return;
      if (!atRest(eng)) {
        // still finishing the previous shot locally: we cannot start from the same state
        synced = false;
        _askKey(now);
        return;
      }
      eng.drag = null;
      eng.fireRaw(b, d[0], d[1], d[2], d[3]);
      eng.phase = Phase.move;
      simulating = true;
    } else if (k == 'shot' && isHost) {
      if (from != ctrl || eng.phase != Phase.aim || (m['n'] as num?)?.toInt() != seq) return;
      final b = eng.bodies.where((x) => x.id == (m['b'] as num?)?.toInt() && x.team == eng.turn).firstOrNull;
      if (b == null) return;
      final ux = (m['ux'] as num?)?.toDouble(), uy = (m['uy'] as num?)?.toDouble(), p = (m['p'] as num?)?.toDouble();
      if (ux != null && uy != null && p != null && p > 0 && p <= 1 && ((ux * ux + uy * uy) - 1).abs() < 1e-6) {
        eng.fireVec(b, ux, uy, p);
        return;
      }
      final dx = (m['dx'] as num?)?.toDouble() ?? 0, dy = (m['dy'] as num?)?.toDouble() ?? 0, l = math.sqrt(dx * dx + dy * dy);
      if (l > 18 && l < 5000) eng.fire(b, dx, dy, l, true);
    } else if (k == 'aim') {
      if (from != controller || from == port.me) return;
      final bid = (m['b'] as num?)?.toInt() ?? -1;
      if (bid < 0) {
        if (eng.drag?.ai == true && !eng.isAiTurn()) eng.drag = null;
        return;
      }
      if (eng.phase != Phase.aim) return;
      final b = eng.bodies.where((x) => x.id == bid).firstOrNull;
      if (b == null) return;
      eng.drag = Drag(b, b.x, b.y, b.x - ((m['dx'] as num?)?.toDouble() ?? 0), b.y - ((m['dy'] as num?)?.toDouble() ?? 0), ai: true);
    } else if (k == 'rq' && isHost) {
      _keyAsked = true;
      sendSnap(now, key: true);
    } else if (k == 'res' && !isHost) {
      result = m;
    }
  }

  void tick(double dt, int now) => isHost ? _hostTick(dt, now) : _clientTick(dt, now);

  // ------------------------------------------------------------------ input
  bool canAct(int now) {
    if (isHost) return eng.phase == Phase.aim && ctrl == port.me && !eng.isAiTurn();
    if (eng.phase != Phase.aim || _cctrl != port.me || now - pendingShot < 1500) return false;
    if (mode == NetMode.lockstep) return !simulating && _pendingKey == null && atRest(eng);
    return true;
  }

  /// A local flick release. Host fires directly; clients send the shot (and predict it in lockstep).
  void release(int now, Drag d) {
    if (isHost) {
      eng.release();
      port.send({'k': 'aim', 'b': -1});
      return;
    }
    eng.drag = null;
    port.send({'k': 'aim', 'b': -1});
    final dx = d.sx - d.cx, dy = d.sy - d.cy, l = math.sqrt(dx * dx + dy * dy);
    if (l <= 18 || !canAct(now)) return;
    pendingShot = now;
    final msg = <String, dynamic>{'k': 'shot', 'b': d.b.id, 'dx': (dx * 10).round() / 10, 'dy': (dy * 10).round() / 10, 'n': cseq};
    if (mode == NetMode.lockstep) {
      final (ux, uy) = eng.deviate(d.b.team, dx, dy, l);
      final p = math.min(l, LMAX) / LMAX;
      msg['ux'] = ux;
      msg['uy'] = uy;
      msg['p'] = p;
      eng.fireVec(d.b, ux, uy, p);
      _pred = (cseq, ux, uy, eng.lastV, p);
      eng.phase = Phase.move;
      simulating = true;
    }
    port.send(msg);
  }
}
