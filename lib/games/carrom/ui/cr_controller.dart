import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:nexora/games/core/game_contract.dart';
import '../core/carrom_bot.dart';
import '../core/carrom_config.dart';
import '../core/carrom_match.dart';
import '../core/carrom_physics.dart';
import 'cr_fx.dart';

const Color kCrSeat0 = Color(0xFFFFE9C2); // white / cream side
const Color kCrSeat1 =
    Color(0xFF7B8CFF); // black side accent (readable on dark UI)
const Color kCrGold = Color(0xFFFFC857);
const Color kCrDanger = Color(0xFFFF5A6E);

const List<String> kCrStrikerSkins = <String>[
  'striker_soccer',
  'striker_compass',
  'striker_eagle',
  'striker_wolf',
  'striker_lion',
  'striker_fire',
  'striker_dragon',
  'striker_galaxy',
];

String crStrikerFromCatalog(String? id) {
  if (id == null || !kCrStrikerSkins.contains(id)) return 'striker_soccer';
  return id;
}

String crOpponentStriker(String mine) =>
    mine == 'striker_compass' ? 'striker_soccer' : 'striker_compass';

/// A coin falling into a pocket (render-only animation).
class CrSinkAnim {
  CrSinkAnim(
      {required this.kind,
      required this.x,
      required this.y,
      required this.px,
      required this.py});
  final CrKind kind;
  final double x;
  final double y;
  final double px;
  final double py;
  double t = 0;
}

@immutable
class CrHudData {
  const CrHudData({
    required this.turn,
    required this.timeLeft,
    required this.pocketed0,
    required this.pocketed1,
    required this.queenCoveredBy,
    required this.queenPendingFor,
    required this.phase,
    required this.winner,
    required this.botThinking,
    required this.turnNumber,
    required this.toast,
    required this.toastColor,
  });

  final int turn;
  final int timeLeft;
  final int pocketed0;
  final int pocketed1;
  final int queenCoveredBy;
  final int queenPendingFor;
  final CrPhase phase;
  final int? winner;
  final bool botThinking;
  final int turnNumber;
  final String toast;
  final Color toastColor;

  @override
  bool operator ==(Object other) =>
      other is CrHudData &&
      other.turn == turn &&
      other.timeLeft == timeLeft &&
      other.pocketed0 == pocketed0 &&
      other.pocketed1 == pocketed1 &&
      other.queenCoveredBy == queenCoveredBy &&
      other.queenPendingFor == queenPendingFor &&
      other.phase == phase &&
      other.winner == winner &&
      other.botThinking == botThinking &&
      other.turnNumber == turnNumber &&
      other.toast == toast &&
      other.toastColor == toastColor;

  @override
  int get hashCode => Object.hash(
      turn,
      timeLeft,
      pocketed0,
      pocketed1,
      queenCoveredBy,
      queenPendingFor,
      phase,
      winner,
      botThinking,
      turnNumber,
      toast,
      toastColor);
}

enum _BotStage { idle, thinking, moving, aiming }

/// Drives a Carrom board: placement, slingshot aim, fixed-step simulation, bot, timer, juice.
/// All rules live in the pure core (CrMatch / carrom_physics).
class CrController extends ChangeNotifier {
  CrController(this.launch)
      : match = CrMatch.newBoard(),
        fx = CrFx(enabled: launch.fancyEffects && !launch.reducedMotion) {
    if (launch.vsBot) {
      bot = CrBot(
          seat: 1, level: _level(launch.difficulty), seed: launch.seed ?? 9);
    }
    strikerSkin0 = crStrikerFromCatalog(launch.skins['striker']);
    strikerSkin1 = crOpponentStriker(strikerSkin0);
    final NetLink? net = launch.net;
    if (net != null) {
      _netReady = false;
      final NetInbox inbox = NetInbox(_onNet);
      _inbox = inbox;
      net.listen(inbox.add,
          onReplayDone: () => inbox.add(const NetMove(
              seq: -1,
              seat: -1,
              kind: 'replayDone',
              data: <String, dynamic>{})));
      _say(
          net.mySeat == 0
              ? 'شروع! مهره‌های سفید مال شماست'
              : 'مهره‌های سیاه مال شماست؛ حریف شروع می‌کند',
          net.mySeat == 0
              ? 'Break! You play the white coins'
              : 'You play the black coins; your opponent breaks',
          kCrGold);
    } else {
      _say('شروع! مهره‌های سفید مال شماست', 'Break! You play the white coins',
          kCrGold);
    }
    _pushHud();
  }

  // ------------------------------------------------------------- online
  // Same deterministic physics on both phones from the same shot input; the authority posts a
  // snapshot after every shot so the boards always agree exactly.
  NetInbox? _inbox;
  bool _netReady = true;
  bool _synced = true;
  double _syncWait = 0;
  bool get online => launch.online;
  int get mySeat => launch.mySeat;

  /// Seat 1 sees the board rotated so their own baseline is at the bottom.
  bool get flipped => online && mySeat == 1;

  String _hash() => hashOf('${match.toJson()}');

  void _applySnap(Map<String, dynamic> d) {
    final dynamic m = d['m'];
    if (m is! Map) return;
    final String want = '${d['h'] ?? ''}';
    if (want.isNotEmpty && want == _hash()) return;
    launch.net?.verify(-1, want, _hash());
    match.applyJson(Map<String, dynamic>.from(m));
    trail.clear();
    _onNewTurn();
  }

  void _postSettle() {
    if (!online) return;
    final NetLink net = launch.net!;
    if (net.isAuthority) {
      net.send(<String, dynamic>{
        'a': 'snap',
        'tn': match.turnNumber,
        'm': match.toJson(),
        'h': _hash()
      }, kind: 'snap');
      _synced = true;
    } else {
      _synced = false;
      _syncWait = 0;
    }
  }

  CrShot? _shotFrom(Map<String, dynamic> d) {
    if (d['px'] == null) return null;
    return CrShot(
      placeX: (d['px'] as num).toDouble(),
      dirX: (d['x'] as num).toDouble(),
      dirY: (d['y'] as num).toDouble(),
      power: (d['p'] as num).toDouble(),
    );
  }

  Future<void> _onNet(NetMove m) async {
    if (_disposed) return;
    if (m.kind == 'replayDone') {
      _netReady = true;
      _synced = true;
      _onNewTurn();
      if (match.phase == CrPhase.finished) _onMatchOver();
      _pushHud();
      return;
    }
    final String a = '${m.data['a']}';
    final int tn = (m.data['tn'] as num?)?.toInt() ?? -1;
    if (m.replay) {
      if (a == 'shot' && tn == match.turnNumber) {
        final CrShot? shot = _shotFrom(m.data);
        if (shot != null && match.validate(shot) == null) {
          match.beginShot(shot);
          final CrSimulator sim = CrSimulator(match.bodies)..runToEnd();
          match.finishShot(sim.pocketed, sim.steps);
        }
      } else if (a == 'pass' && tn == match.turnNumber) {
        match.passTurn();
      } else if (a == 'snap' && tn == match.turnNumber) {
        _applySnap(m.data);
      }
      return;
    }
    while (!_disposed && match.phase == CrPhase.simulating) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
    if (_disposed) return;
    if (a == 'snap') {
      if (tn == match.turnNumber) _applySnap(m.data);
      _synced = true;
    } else if (a == 'shot') {
      if (tn != match.turnNumber || match.phase != CrPhase.aiming) return;
      launch.net?.verify(m.seq, m.data['h'] as String?, _hash());
      final CrShot? shot = _shotFrom(m.data);
      if (shot != null) {
        placeX[match.turn] = shot.placeX;
        startShot(shot, remote: true);
      }
    } else if (a == 'pass') {
      if (tn != match.turnNumber || match.phase != CrPhase.aiming) return;
      _doPass();
    } else if (a == 'place') {
      if (match.turn == m.seat)
        placeX[m.seat] = (m.data['px'] as num).toDouble();
    }
    _pushHud();
  }

  void _doPass() {
    aiming = false;
    pull = Offset.zero;
    _search = null;
    _stage = _BotStage.idle;
    _botShot = null;
    match.passTurn();
    _onNewTurn();
    _say('وقت تمام شد؛ نوبت سوخت', 'Time up — turn lost', kCrDanger);
    if (match.phase == CrPhase.finished) _onMatchOver();
  }

  final GameLaunch launch;
  final CrMatch match;
  final CrFx fx;
  CrBot? bot;
  late final String strikerSkin0;
  late final String strikerSkin1;

  /// Striker placement per seat (logical x on that seat's baseline).
  final List<double> placeX = <double>[CrConfig.centerX, CrConfig.centerX];

  CrSimulator? _sim;
  int _seenPocketed = 0;
  final List<CrImpact> _impacts = <CrImpact>[];
  final List<CrSinkAnim> sinking = <CrSinkAnim>[];
  final Map<int, double> spawnedAt = <int, double>{};
  final List<Offset> trail = <Offset>[];
  double _acc = 0;
  double clock = 0;
  double timeLeft = CrConfig.turnSeconds;
  double _hapticCooldown = 0;

  // aiming (human): pull vector in board units (finger relative to drag start)
  bool aiming = false;
  Offset _panStart = Offset.zero;
  Offset pull = Offset.zero;

  // bot
  CrBotSearch? _search;
  _BotStage _stage = _BotStage.idle;
  double _botTimer = 0;
  CrShot? _botShot;
  double _botFromX = CrConfig.centerX;

  // messages
  double bannerTime = 0;
  double bannerAge = 0;
  String bannerFa = '';
  String bannerEn = '';
  Color bannerColor = kCrGold;
  String _toastFa = '';
  String _toastEn = '';
  Color _toastColor = kCrGold;
  double _toastTime = 0;

  double _finishDelay = -1;
  bool _reported = false;
  bool _disposed = false;

  final ValueNotifier<CrHudData> hud = ValueNotifier<CrHudData>(const CrHudData(
    turn: 0,
    timeLeft: 30,
    pocketed0: 0,
    pocketed1: 0,
    queenCoveredBy: -1,
    queenPendingFor: -1,
    phase: CrPhase.aiming,
    winner: null,
    botThinking: false,
    turnNumber: 0,
    toast: '',
    toastColor: kCrGold,
  ));

  static CrBotLevel _level(BotDifficulty d) => switch (d) {
        BotDifficulty.easy => CrBotLevel.easy,
        BotDifficulty.normal => CrBotLevel.normal,
        BotDifficulty.hard => CrBotLevel.hard,
      };

  // ------------------------------------------------------------- viewport (board units 0..1024)
  Size viewSize = Size.zero;
  double get viewScale {
    if (viewSize.width <= 0 || viewSize.height <= 0) return 1;
    return math.min(viewSize.width, viewSize.height) / CrConfig.boardSize;
  }

  Offset get viewOrigin {
    final s = viewScale;
    return Offset((viewSize.width - CrConfig.boardSize * s) / 2,
        (viewSize.height - CrConfig.boardSize * s) / 2);
  }

  Offset toBoard(Offset local) {
    final s = viewScale;
    final o = viewOrigin;
    return Offset((local.dx - o.dx) / s, (local.dy - o.dy) / s);
  }

  // ------------------------------------------------------------- state helpers
  bool get isBotTurn =>
      bot != null && match.turn == bot!.seat && match.phase == CrPhase.aiming;
  bool get humanCanAim =>
      match.phase == CrPhase.aiming &&
      !isBotTurn &&
      bannerTime <= 0 &&
      (!online || (_netReady && _synced && match.turn == mySeat));
  bool get botThinking =>
      isBotTurn && (_stage == _BotStage.thinking || _stage == _BotStage.idle);
  double get strikerX => placeX[match.turn];
  double get strikerY => CrMatch.baselineY(match.turn);
  bool get placementValid => match.placementOk(strikerX);

  String seatName(int seat) {
    final String? n = launch.netName(seat);
    if (n != null) return n;
    if (seat == 0)
      return launch.playerName.isEmpty
          ? launch.tx('شما', 'You')
          : launch.playerName;
    if (launch.vsBot) return launch.tx('ربات', 'Bot');
    return launch.tx('بازیکن ۲', 'Player 2');
  }

  /// Aim preview: direction (unit) + power, or null.
  Offset? get aimDir {
    if (_stage == _BotStage.aiming && _botShot != null)
      return Offset(_botShot!.dirX, _botShot!.dirY);
    if (!aiming) return null;
    final len = pull.distance;
    if (len < 4) return null;
    return Offset(-pull.dx / len, -pull.dy / len);
  }

  double get aimPower {
    if (_stage == _BotStage.aiming && _botShot != null) {
      final k = math.min(1.0, _botTimer / 0.35);
      return _botShot!.power * k;
    }
    return math.min(1.0, pull.distance / CrConfig.maxPull);
  }

  // ------------------------------------------------------------- input
  void setPlacement(double x) {
    if (!humanCanAim || aiming) return;
    placeX[match.turn] =
        math.max(CrConfig.baseMinX, math.min(CrConfig.baseMaxX, x));
  }

  void onPanStart(Offset local) {
    if (!humanCanAim) return;
    if (!placementValid) {
      _say('استرایکر روی مهره است؛ جابه‌جایش کن',
          'Striker overlaps a coin — slide it', kCrDanger);
      return;
    }
    aiming = true;
    _panStart = toBoard(local);
    pull = Offset.zero;
    if (launch.soundOn) HapticFeedback.selectionClick();
  }

  void onPanUpdate(Offset local) {
    if (!aiming) return;
    var v = toBoard(local) - _panStart;
    final len = v.distance;
    if (len > CrConfig.maxPull) v = v * (CrConfig.maxPull / len);
    pull = v;
  }

  void onPanEnd() {
    if (!aiming) return;
    aiming = false;
    final len = pull.distance;
    final power = len / CrConfig.maxPull;
    final p = pull;
    pull = Offset.zero;
    if (power < 0.05 || !humanCanAim) return;
    startShot(CrShot(
        placeX: strikerX,
        dirX: -p.dx / len,
        dirY: -p.dy / len,
        power: math.min(1.0, power)));
  }

  void onPanCancel() {
    aiming = false;
    pull = Offset.zero;
  }

  void startShot(CrShot shot, {bool remote = false}) {
    if (match.validate(shot) != null) return;
    if (online && !remote) {
      launch.net!.send(<String, dynamic>{
        'a': 'shot',
        'tn': match.turnNumber,
        'px': shot.placeX,
        'x': shot.dirX,
        'y': shot.dirY,
        'p': shot.power,
        'h': _hash(),
      });
    }
    match.beginShot(shot);
    _sim = CrSimulator(match.bodies, impactSink: _impacts);
    _seenPocketed = 0;
    _acc = 0;
    trail.clear();
    _stage = _BotStage.idle;
    _botShot = null;
    if (launch.soundOn) HapticFeedback.mediumImpact();
    _pushHud();
  }

  // ------------------------------------------------------------- loop
  void tick(double dt) {
    if (_disposed) return;
    clock += dt;
    fx.update(dt);
    if (_hapticCooldown > 0) _hapticCooldown -= dt;
    if (bannerTime > 0) bannerTime -= dt;
    bannerAge += dt;
    if (_toastTime > 0) _toastTime -= dt;
    for (var i = sinking.length - 1; i >= 0; i--) {
      sinking[i].t += dt / 0.4;
      if (sinking[i].t >= 1) sinking.removeAt(i);
    }
    switch (match.phase) {
      case CrPhase.aiming:
        _tickAiming(dt);
        break;
      case CrPhase.simulating:
        _tickSim(dt);
        break;
      case CrPhase.finished:
        if (_finishDelay > 0) {
          _finishDelay -= dt;
          if (_finishDelay <= 0) _report();
        }
        break;
    }
    _pushHud();
    notifyListeners();
  }

  void _tickAiming(double dt) {
    if (bannerTime > 0) return;
    if (online) {
      if (!_netReady) return;
      if (!_synced) {
        _syncWait += dt;
        if (_syncWait > 3.5) _synced = true;
        return;
      }
      timeLeft -= dt;
      final NetLink net = launch.net!;
      if (match.turn == mySeat && timeLeft <= 0) {
        net.send(<String, dynamic>{'a': 'pass', 'tn': match.turnNumber});
        _doPass();
      } else if (match.turn != mySeat && timeLeft <= -8 && net.isAuthority) {
        net.send(<String, dynamic>{'a': 'pass', 'tn': match.turnNumber},
            kind: 'timeout', asSeat: match.turn);
        _doPass();
      }
      return;
    }
    timeLeft -= dt;
    if (timeLeft <= 0) {
      aiming = false;
      pull = Offset.zero;
      _search = null;
      _stage = _BotStage.idle;
      _botShot = null;
      match.passTurn();
      _onNewTurn();
      _say('وقت تمام شد؛ نوبت سوخت', 'Time up — turn lost', kCrDanger);
      if (match.phase == CrPhase.finished) _onMatchOver();
      return;
    }
    if (!isBotTurn) return;
    final b = bot;
    if (b == null) return;
    switch (_stage) {
      case _BotStage.idle:
        _search = CrBotSearch(b, match);
        _stage = _BotStage.thinking;
        _botTimer = 0;
        break;
      case _BotStage.thinking:
        _botTimer += dt;
        final search = _search;
        if (search == null) {
          _stage = _BotStage.idle;
          break;
        }
        final finished = search.step(4);
        if (finished && _botTimer > 0.65) {
          var shot = b.withExecutionNoise(search.best);
          if (match.validate(shot) != null) shot = search.best;
          if (match.validate(shot) != null) shot = b.fallback(match);
          _botShot = shot;
          _botFromX = placeX[b.seat];
          _search = null;
          _stage = _BotStage.moving;
          _botTimer = 0;
        }
        break;
      case _BotStage.moving:
        _botTimer += dt;
        final moveShot = _botShot;
        if (moveShot == null) {
          _stage = _BotStage.idle;
          break;
        }
        final k = math.min(1.0, _botTimer / 0.45);
        final e = k * k * (3 - 2 * k);
        placeX[b.seat] = _botFromX + (moveShot.placeX - _botFromX) * e;
        if (k >= 1) {
          placeX[b.seat] = moveShot.placeX;
          _stage = _BotStage.aiming;
          _botTimer = 0;
        }
        break;
      case _BotStage.aiming:
        _botTimer += dt;
        final aimShot = _botShot;
        if (aimShot == null) {
          _stage = _BotStage.idle;
          break;
        }
        if (_botTimer > 0.55) startShot(aimShot);
        break;
    }
  }

  void _tickSim(double dt) {
    _acc += math.min(dt, 0.05);
    final sim = _sim;
    if (sim == null) return;
    while (_acc >= CrConfig.dt) {
      _acc -= CrConfig.dt;
      final finished = sim.tick();
      _drainImpacts();
      _drainPockets(sim);
      final st = match.striker;
      if (fx.enabled && st.onBoard && sim.steps % 2 == 0) {
        trail.add(Offset(st.x, st.y));
        if (trail.length > 14) trail.removeAt(0);
      }
      if (finished) {
        final out = match.finishShot(sim.pocketed, sim.steps);
        _sim = null;
        _afterShot(out);
        _postSettle();
        break;
      }
    }
  }

  void _drainImpacts() {
    if (_impacts.isEmpty) return;
    for (final im in _impacts) {
      final s = im.strength;
      if (s < 160) continue;
      final k = math.min(1.0, s / 2200);
      fx.burst(im.x, im.y,
          count: 3 + (k * 9).round(),
          speed: 110 + 300 * k,
          color: im.wall ? const Color(0xFFFFD98A) : const Color(0xFFEAF6FF),
          size: 3 + 3 * k,
          life: 0.3 + 0.25 * k);
      if (s > 1300) fx.shake(2 + 6 * k);
      if (launch.soundOn && _hapticCooldown <= 0 && s > 380) {
        _hapticCooldown = 0.08;
        HapticFeedback.lightImpact();
      }
    }
    _impacts.clear();
  }

  void _drainPockets(CrSimulator sim) {
    while (_seenPocketed < sim.pocketed.length) {
      final id = sim.pocketed[_seenPocketed];
      _seenPocketed++;
      final b = match.bodies[id];
      final p = _nearestPocket(b.x, b.y);
      sinking.add(CrSinkAnim(kind: b.kind, x: b.x, y: b.y, px: p.dx, py: p.dy));
      final Color c = switch (b.kind) {
        CrKind.queen => const Color(0xFFFF4F6E),
        CrKind.striker => kCrDanger,
        CrKind.white => kCrSeat0,
        CrKind.black => kCrSeat1,
      };
      fx.burst(p.dx, p.dy, count: 22, speed: 300, color: c, size: 6, life: 0.7);
      fx.burst(p.dx, p.dy,
          count: 10, speed: 200, color: kCrGold, size: 4, life: 0.6);
      if (launch.soundOn) HapticFeedback.mediumImpact();
    }
  }

  Offset _nearestPocket(double x, double y) {
    var best = 0;
    var bd = 1e18;
    for (var i = 0; i < CrConfig.pockets.length; i++) {
      final dx = x - CrConfig.pockets[i][0], dy = y - CrConfig.pockets[i][1];
      final d = dx * dx + dy * dy;
      if (d < bd) {
        bd = d;
        best = i;
      }
    }
    return Offset(CrConfig.pockets[best][0], CrConfig.pockets[best][1]);
  }

  void _afterShot(CrTurnOutcome o) {
    trail.clear();
    for (final id in o.returnedIds) {
      spawnedAt[id] = clock;
    }
    if (o.queenReturned) spawnedAt[CrConfig.queenId] = clock;
    final mine =
        online ? o.shooter == mySeat : (launch.vsBot ? o.shooter == 0 : true);
    if (o.foul) {
      _say('خطا! استرایکر افتاد — یک مهره برگشت',
          'Foul! Striker pocketed — a coin returns', kCrDanger);
      fx.doFlash(kCrDanger, 0.35);
      if (launch.soundOn) HapticFeedback.heavyImpact();
    } else if (o.queenCovered) {
      _banner('ملکه پوشش داده شد!', 'Queen covered!', kCrGold);
      fx.doFlash(kCrGold, 0.45);
      fx.shake(8);
      fx.burst(CrConfig.centerX, CrConfig.centerY,
          count: 40, speed: 520, color: kCrGold, size: 7, life: 1.0);
      if (launch.soundOn) HapticFeedback.heavyImpact();
    } else if (o.queenPending) {
      _say(
          'ملکه افتاد! حالا با یک مهره‌ی خودی پوشش بده',
          'Queen pocketed! Cover it with one of your coins',
          const Color(0xFFFF4F6E));
    } else if (o.queenReturned) {
      _say('ملکه پوشش داده نشد و به مرکز برگشت',
          'Queen not covered — back to the centre', kCrDanger);
    } else if (o.returnedIds.isNotEmpty) {
      _say('آخرین مهره قبل از ملکه مجاز نیست — برگشت',
          'Last coin before the queen — returned', kCrDanger);
    } else if (o.continueTurn) {
      _say(
          mine ? 'عالی! دوباره بزن' : 'حریف دوباره می‌زند',
          mine ? 'Nice! Shoot again' : 'Opponent shoots again',
          const Color(0xFF3DDC97));
    } else if (o.oppPocketed > 0) {
      _say('مهره‌ی حریف افتاد — به نفع حریف',
          'Opponent coin pocketed — counts for them', kCrDanger);
    }
    if (o.matchOver) {
      _onMatchOver();
      return;
    }
    _onNewTurn();
  }

  void _onNewTurn() {
    timeLeft = CrConfig.turnSeconds;
    _stage = _BotStage.idle;
    _botShot = null;
    _search = null;
    final seat = match.turn;
    if (!match.placementOk(placeX[seat])) {
      final x = match.nearestPlacement(placeX[seat]);
      if (x != null) placeX[seat] = x;
    }
  }

  void _onMatchOver() {
    final w = match.winner;
    if (w == -1) {
      _banner('مساوی', 'Draw', kCrGold);
    } else if (online) {
      final bool won = w == mySeat;
      _banner(won ? 'بردی!' : 'باختی', won ? 'You win!' : 'You lose',
          won ? kCrGold : kCrSeat1);
      if (won)
        fx.burst(CrConfig.centerX, CrConfig.centerY,
            count: 60, speed: 700, color: kCrGold, size: 8, life: 1.3);
    } else if (w == 0) {
      _banner(launch.vsBot ? 'بردی!' : '${seatName(0)} برد',
          launch.vsBot ? 'You win!' : '${seatName(0)} wins', kCrGold);
      fx.burst(CrConfig.centerX, CrConfig.centerY,
          count: 60, speed: 700, color: kCrGold, size: 8, life: 1.3);
    } else {
      _banner(launch.vsBot ? 'باختی' : '${seatName(1)} برد',
          launch.vsBot ? 'You lose' : '${seatName(1)} wins', kCrSeat1);
    }
    bannerTime = 2.6;
    _finishDelay = 2.5;
  }

  void _banner(String fa, String en, Color c) {
    bannerFa = fa;
    bannerEn = en;
    bannerColor = c;
    bannerAge = 0;
    if (bannerTime < 1.3) bannerTime = 1.3;
  }

  void _say(String fa, String en, Color c) {
    _toastFa = fa;
    _toastEn = en;
    _toastColor = c;
    _toastTime = 3.2;
  }

  void _report() {
    if (_reported) return;
    _reported = true;
    final w = match.winner;
    final int me = mySeat;
    final GameOutcome outcome = w == null || w == -1
        ? GameOutcome.draw
        : (w == me ? GameOutcome.win : GameOutcome.loss);
    final p0 = match.pocketedCount(me), p1 = match.pocketedCount(1 - me);
    final pts = (w != null && w >= 0) ? match.points[w] : 0;
    final queenFa = match.queenCoveredBy == me
        ? ' · ملکه با شما'
        : (match.queenCoveredBy == 1 - me ? ' · ملکه با حریف' : '');
    final queenEn = match.queenCoveredBy == me
        ? ' · queen: yours'
        : (match.queenCoveredBy == 1 - me ? ' · queen: opponent' : '');
    launch.onFinish(GameResult(
      outcome: outcome,
      score: p0,
      opponentScore: p1,
      winnerSeats: w == null || w < 0 ? <int>[] : <int>[w],
      scores: <int>[match.pocketedCount(0), match.pocketedCount(1)],
      summaryFa: 'کارم: $p0 مهره در برابر $p1$queenFa · امتیاز تخته $pts',
      summaryEn: 'Carrom: $p0 coins vs $p1$queenEn · board points $pts',
    ));
  }

  void _pushHud() {
    hud.value = CrHudData(
      turn: match.turn,
      timeLeft: math.max(0, timeLeft.ceil()),
      pocketed0: match.pocketedCount(0),
      pocketed1: match.pocketedCount(1),
      queenCoveredBy: match.queenCoveredBy,
      queenPendingFor: match.queenPendingFor,
      phase: match.phase,
      winner: match.winner,
      botThinking: botThinking,
      turnNumber: match.turnNumber,
      toast: _toastTime > 0 ? launch.tx(_toastFa, _toastEn) : '',
      toastColor: _toastColor,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _inbox?.close();
    hud.dispose();
    super.dispose();
  }
}
