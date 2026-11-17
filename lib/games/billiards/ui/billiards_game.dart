import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/nx_theme.dart';
import '../../core/game_contract.dart';
import '../core/pool_bot.dart';
import '../core/pool_config.dart';
import '../core/pool_match.dart';
import '../core/pool_physics.dart';
import 'pool_hud.dart';
import 'pool_painter.dart';
import 'pool_scene.dart';
import 'pool_skins.dart';
import '../../../core/ui2/nx2_board_art.dart';

enum _Stage { aiming, striking, rolling, over }

enum _BotStage { idle, thinking, aiming, charging }

/// 8-ball billiards: Ticker drives fixed 1/120 s physics steps of the pure core,
/// CustomPainter draws, gestures become [PoolShot]s.
class BilliardsGame extends StatefulWidget {
  const BilliardsGame({super.key, required this.launch});
  final GameLaunch launch;

  @override
  State<BilliardsGame> createState() => _BilliardsGameState();
}

class _BilliardsGameState extends State<BilliardsGame>
    with SingleTickerProviderStateMixin {
  NxThemeColors _theme = NxThemeColors.gold;
  int _skin = poolSkinIndex();

  void _nextSkin() {
    setState(() => _skin = (_skin + 1) % kPoolSkins.length);
    poolSetSkin(_skin);
  }
  Color get _p0Color => _theme.accent;
  Color get _p1Color => _theme.accentSecondary;

  late final PoolMatch _match;
  late final PoolScene _scene;
  late final Ticker _ticker;
  late final math.Random _rng;
  Duration _last = Duration.zero;
  double _acc = 0;

  _Stage _stage = _Stage.aiming;
  PoolShot? _pending;
  double _strikeT = 0;

  // human input
  double _power = 0;
  double _chargeStartX = 0;
  bool _charging = false;
  bool _draggingCue = false;
  double _spin = 0;
  double _side = 0;
  bool _spinOpen = false;

  // bot
  PoolBotPlanner? _planner;
  _BotStage _botStage = _BotStage.idle;
  double _botWait = 0;
  PoolShot? _botShot;
  double _botFromAngle = 0;
  double _botToAngle = 0;
  double _botT = 0;

  // banner
  String _bannerText = '';
  Color _bannerColor = NxColors.iceWhite;
  int _bannerId = 0;
  double _bannerLeft = 0;

  bool _finished = false;
  double _endWait = -1;
  int _lastHapticMs = 0;
  final List<int> _pottedOrder = <int>[];

  // layout
  double _s = 1;

  GameLaunch get _l => widget.launch;
  bool get _motion => _l.fancyEffects && !_l.reducedMotion;
  bool get _isBotTurn => _l.vsBot && _match.current == 1;
  bool get _humanCanAct =>
      !_isBotTurn &&
      _stage == _Stage.aiming &&
      !_match.isOver &&
      !_spinOpen &&
      (!_l.online || (_netReady && _synced && _match.current == _l.mySeat));

  // ------------------------------------------------------------- online
  // Same deterministic table physics on both phones from the same cue input; the authority posts
  // a snapshot after each shot so both tables always agree.
  NetInbox? _inbox;
  bool _netReady = true;
  bool _synced = true;
  double _syncWait = 0;
  bool _remoteShot = false;

  String _hash() => hashOf('${_match.toSnap()}');

  Future<void> _onNet(NetMove m) async {
    if (!mounted) return;
    if (m.kind == 'replayDone') {
      _netReady = true;
      _synced = true;
      _scene.syncLast();
      if (_match.isOver) {
        _stage = _Stage.over;
        _endWait = 1.0;
      } else {
        _stage = _Stage.aiming;
        _prepareTurn();
      }
      _syncScene();
      setState(() {});
      return;
    }
    final String a = '${m.data['a']}';
    final int sc = (m.data['sc'] as num?)?.toInt() ?? -1;
    if (m.replay) {
      if (a == 'shot' && sc == _match.shotCount) {
        final PoolShot shot = _shotFrom(m.data);
        if (_match.beginShot(shot)) {
          int guard = 0;
          while (!_match.world.tick() && guard < 200000) {
            guard++;
          }
          _match.finishShot();
        }
      } else if (a == 'snap' && sc == _match.shotCount) {
        _match.applySnap(Map<String, dynamic>.from(m.data['m'] as Map));
      }
      return;
    }
    while (mounted && (_stage == _Stage.rolling || _stage == _Stage.striking)) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
    if (!mounted) return;
    if (a == 'snap') {
      if (sc == _match.shotCount) {
        final String want = '${m.data['h'] ?? ''}';
        if (want != _hash()) {
          _l.net?.verify(-1, want, _hash());
          _match.applySnap(Map<String, dynamic>.from(m.data['m'] as Map));
          _scene.syncLast();
          _prepareTurn();
        }
      }
      _synced = true;
      _syncScene();
      setState(() {});
    } else if (a == 'shot') {
      if (sc != _match.shotCount || _stage != _Stage.aiming || _match.isOver)
        return;
      _l.net?.verify(m.seq, m.data['h'] as String?, _hash());
      final PoolShot shot = _shotFrom(m.data);
      if (shot.cueX != null && shot.cueY != null)
        _match.placeCue(shot.cueX!, shot.cueY!);
      _scene.aimAngle = math.atan2(shot.dirY, shot.dirX);
      _remoteShot = true;
      _shoot(shot);
      _remoteShot = false;
    }
  }

  PoolShot _shotFrom(Map<String, dynamic> d) => PoolShot(
        dirX: (d['dx'] as num).toDouble(),
        dirY: (d['dy'] as num).toDouble(),
        power: (d['p'] as num).toDouble(),
        spin: (d['s'] as num?)?.toDouble() ?? 0,
        side: (d['e'] as num?)?.toDouble() ?? 0,
        cueX: (d['cx'] as num?)?.toDouble(),
        cueY: (d['cy'] as num?)?.toDouble(),
      );

  void _postSettle() {
    final NetLink? net = _l.net;
    if (net == null) return;
    if (net.isAuthority) {
      net.send(<String, dynamic>{
        'a': 'snap',
        'sc': _match.shotCount,
        'm': _match.toSnap(),
        'h': _hash()
      }, kind: 'snap');
      _synced = true;
    } else {
      _synced = false;
      _syncWait = 0;
    }
  }

  String _name(int seat) {
    final String? online = _l.netName(seat);
    if (online != null) return online;
    if (seat == 0)
      return _l.playerName.isEmpty
          ? _l.tx('بازیکن ۱', 'Player 1')
          : _l.playerName;
    if (_l.vsBot) {
      if (_l.difficulty == BotDifficulty.easy)
        return _l.tx('ربات نکسورا · آسان', 'NEXORA Bot · Easy');
      if (_l.difficulty == BotDifficulty.hard)
        return _l.tx('ربات نکسورا · سخت', 'NEXORA Bot · Hard');
      return _l.tx('ربات نکسورا · معمولی', 'NEXORA Bot · Normal');
    }
    return _l.tx('بازیکن ۲', 'Player 2');
  }

  PoolBotLevel get _botLevel {
    if (_l.difficulty == BotDifficulty.easy) return PoolBotLevel.easy;
    if (_l.difficulty == BotDifficulty.hard) return PoolBotLevel.hard;
    return PoolBotLevel.normal;
  }

  @override
  void initState() {
    super.initState();
    final int seed = _l.seed ?? DateTime.now().millisecondsSinceEpoch;
    _rng = math.Random(seed);
    final int breaker = (_l.seed != null && _l.seed!.isOdd) ? 1 : 0;
    _match = PoolMatch.newRack(breaker: breaker);
    final String cue = _l.skins['cue'] ?? 'cue_classic';
    _scene = PoolScene(_match,
        cueSkin: cue, fancy: _l.fancyEffects && !_l.reducedMotion);
    _scene.syncLast();
    _match.world.onImpact = _onImpact;
    _match.world.onPocket = _onPocket;
    _syncScene();
    _ticker = createTicker(_onTick)..start();
    _bannerText = _l.tx(
        'بریک: ${_name(_match.current)}', 'Break: ${_name(_match.current)}');
    _bannerColor = _match.current == 0 ? _p0Color : _p1Color;
    _bannerLeft = 2.2;
    _prepareTurn();
    final NetLink? net = _l.net;
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
    }
  }

  @override
  void dispose() {
    _inbox?.close();
    _ticker.dispose();
    _match.world.onImpact = null;
    _match.world.onPocket = null;
    _scene.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _theme = NxThemeColors.of(context);
  }

  // ---------------------------------------------------------------- helpers
  void _haptic(int level) {
    if (!_l.soundOn) return;
    final int now = DateTime.now().millisecondsSinceEpoch;
    if (level == 0 && now - _lastHapticMs < 90) return;
    _lastHapticMs = now;
    switch (level) {
      case 0:
        HapticFeedback.selectionClick();
        break;
      case 1:
        HapticFeedback.lightImpact();
        break;
      default:
        HapticFeedback.mediumImpact();
        break;
    }
  }

  void _onImpact(double x, double y, double strength, bool cushion) {
    if (strength < 140) return;
    _scene.spark(
        x, y, strength, cushion ? NxColors.gold : NxColors.iceWhite, _rng);
    _haptic(0);
  }

  void _onPocket(int id, int pocket) {
    _scene.flashes.add(PoolFlash(
        pocket,
        id == 0
            ? NxColors.danger
            : (id == 8 ? NxColors.violet : NxColors.electricBlue)));
    _scene.sinks.add(PoolSink(
        id, PoolConfig.pockets[pocket][0], PoolConfig.pockets[pocket][1]));
    if (id != 0) _pottedOrder.add(id);
    _haptic(1);
  }

  void _showBanner(String text, Color color, {double seconds = 2.2}) {
    setState(() {
      _bannerText = text;
      _bannerColor = color;
      _bannerId++;
      _bannerLeft = seconds;
    });
  }

  void _syncScene() {
    _scene.ballInHand =
        _match.ballInHand && _stage == _Stage.aiming && !_match.isOver;
    _scene.kitchenOnly = _match.kitchenOnly;
    _scene.showAim = _stage == _Stage.aiming &&
        !_match.isOver &&
        (!_isBotTurn ||
            _botStage == _BotStage.aiming ||
            _botStage == _BotStage.charging);
    _scene.showCue = (_stage == _Stage.aiming &&
            !_match.isOver &&
            (!_isBotTurn || _botStage != _BotStage.thinking)) ||
        _stage == _Stage.striking ||
        (_stage == _Stage.rolling && _scene.cueOpacity > 0);
  }

  void _setAimTowardNearestLegal() {
    final PoolBall c = _match.cue;
    double best = double.infinity;
    for (final int id in _match.legalTargets()) {
      final PoolBall b = _match.balls[id];
      final double dx = b.x - c.x, dy = b.y - c.y;
      final double d = dx * dx + dy * dy;
      if (d < best) {
        best = d;
        _scene.aimAngle = math.atan2(dy, dx);
      }
    }
  }

  void _prepareTurn() {
    _scene.pull = 0;
    _scene.strikeOffset = 0;
    _scene.cueOpacity = 1;
    _power = 0;
    _spin = 0;
    _side = 0;
    if (!_isBotTurn) _setAimTowardNearestLegal();
    if (_isBotTurn && !_match.isOver) {
      _botStage = _BotStage.thinking;
      _botWait = 0.7 + _rng.nextDouble() * 0.5;
      _planner = PoolBotPlanner(match: _match, level: _botLevel, rng: _rng);
      _botShot = null;
    } else {
      _botStage = _BotStage.idle;
      _planner = null;
    }
    _syncScene();
  }

  // ---------------------------------------------------------------- loop
  void _onTick(Duration elapsed) {
    double dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (dt > 0.05) dt = 0.05;
    if (dt < 0) dt = 0;

    if (_bannerLeft > 0) {
      _bannerLeft -= dt;
      if (_bannerLeft <= 0) setState(() {});
    }

    switch (_stage) {
      case _Stage.aiming:
        if (_isBotTurn) _botTick(dt);
        if (_l.online && !_synced) {
          _syncWait += dt;
          if (_syncWait > 3.5) {
            _synced = true; // authority silent: our identical simulation stands
            _syncScene();
            setState(() {});
          }
        }
        break;
      case _Stage.striking:
        _strikeT += dt / 0.11;
        final double travel = 6 + _scene.pull * 110;
        _scene.strikeOffset = travel * _strikeT.clamp(0.0, 1.0).toDouble();
        if (_strikeT >= 1) _launchPending();
        break;
      case _Stage.rolling:
        _scene.cueOpacity = math.max(0.0, _scene.cueOpacity - dt * 3.5);
        if (_scene.cueOpacity <= 0) _scene.showCue = false;
        _acc += dt;
        while (_acc >= PoolConfig.dt) {
          _acc -= PoolConfig.dt;
          if (_match.world.tick()) {
            _onShotDone();
            break;
          }
        }
        break;
      case _Stage.over:
        break;
    }

    if (_endWait > 0) {
      _endWait -= dt;
      if (_endWait <= 0) _finish();
    }

    _scene.updateRoll();
    _scene.advanceFx(dt);
    _scene.repaint();
  }

  void _botTick(double dt) {
    final PoolBotPlanner? planner = _planner;
    switch (_botStage) {
      case _BotStage.thinking:
        _botWait -= dt;
        if (planner != null && !planner.done) {
          final Stopwatch sw = Stopwatch()..start();
          while (!planner.done && sw.elapsedMicroseconds < 6000) {
            planner.step(1);
          }
        }
        if (_botWait <= 0 && (planner == null || planner.done)) {
          PoolShot shot = planner?.result() ??
              const PoolShot(dirX: 0, dirY: -1, power: 0.5);
          if (shot.cueX != null && shot.cueY != null) {
            if (!_match.placeCue(shot.cueX!, shot.cueY!)) _placeCueAnywhere();
          } else if (_match.ballInHand &&
              !_match.canPlaceCue(_match.cue.x, _match.cue.y)) {
            _placeCueAnywhere();
          }
          shot = PoolShot(
              dirX: shot.dirX,
              dirY: shot.dirY,
              power: shot.power,
              spin: shot.spin,
              side: shot.side);
          _botShot = shot;
          _botFromAngle = _scene.aimAngle;
          double to = math.atan2(shot.dirY, shot.dirX);
          while (to - _botFromAngle > math.pi) {
            to -= 2 * math.pi;
          }
          while (to - _botFromAngle < -math.pi) {
            to += 2 * math.pi;
          }
          _botToAngle = to;
          _botT = 0;
          _botStage = _BotStage.aiming;
          _scene.ballInHand = false;
          _syncScene();
          setState(() {});
        }
        break;
      case _BotStage.aiming:
        _botT += dt / 0.65;
        final double bt = _botT.clamp(0.0, 1.0).toDouble();
        final double e = bt * bt * (3 - 2 * bt);
        _scene.aimAngle = _botFromAngle + (_botToAngle - _botFromAngle) * e;
        if (_botT >= 1.25) {
          _botT = 0;
          _botStage = _BotStage.charging;
          _syncScene();
        }
        break;
      case _BotStage.charging:
        final PoolShot? queued = _botShot;
        if (queued == null) {
          _botStage = _BotStage.idle;
          break;
        }
        _botT += dt / 0.5;
        _scene.pull = queued.power * _botT.clamp(0.0, 1.0).toDouble();
        if (_botT >= 1.2) {
          _botStage = _BotStage.idle;
          _shoot(queued);
        }
        break;
      case _BotStage.idle:
        break;
    }
  }

  void _placeCueAnywhere() {
    for (double y = PoolConfig.tableH - 80; y > 80; y -= 37) {
      for (double x = PoolConfig.tableW / 2; x > 40; x -= 53) {
        if (_match.placeCue(x, y)) return;
        if (_match.placeCue(PoolConfig.tableW - x, y)) return;
      }
    }
  }

  // ---------------------------------------------------------------- shooting
  void _shoot(PoolShot shot) {
    if (_match.validate(shot) != null) return;
    if (_l.online && !_remoteShot) {
      final PoolBall c = _match.cue;
      _l.net!.send(<String, dynamic>{
        'a': 'shot',
        'sc': _match.shotCount,
        'dx': shot.dirX,
        'dy': shot.dirY,
        'p': shot.power,
        's': shot.spin,
        'e': shot.side,
        if (_match.ballInHand) 'cx': c.x,
        if (_match.ballInHand) 'cy': c.y,
        'h': _hash(),
      });
    }
    _pending = shot;
    _strikeT = 0;
    _stage = _Stage.striking;
    _scene.pull = shot.power;
    _syncScene();
    setState(() {});
  }

  void _launchPending() {
    final PoolShot? shot = _pending;
    _pending = null;
    if (shot == null || !_match.beginShot(shot)) {
      _stage = _Stage.aiming;
      _syncScene();
      return;
    }
    _haptic(2);
    if (_scene.fancy) {
      final PoolBall c = _match.cue;
      _scene.spark(
          c.x - math.cos(_scene.aimAngle) * PoolConfig.ballR,
          c.y - math.sin(_scene.aimAngle) * PoolConfig.ballR,
          shot.power * 2600,
          NxColors.electricBlue,
          _rng);
    }
    _acc = 0;
    _stage = _Stage.rolling;
    _scene.ballInHand = false;
    _scene.showAim = false;
    setState(() {});
  }

  void _onShotDone() {
    final PoolShotReport r = _match.finishShot();
    _scene.syncLast();
    _postSettle();
    if (_match.isOver) {
      _stage = _Stage.over;
      _syncScene();
      final int w = _match.winner ?? 0;
      String fa = '';
      String en = '';
      switch (_match.endReason) {
        case PoolEndReason.eightPotted:
          fa = '${_name(w)} توپ ۸ را انداخت و برنده شد!';
          en = '${_name(w)} sinks the 8 and wins!';
          break;
        case PoolEndReason.eightEarly:
          fa = 'توپ ۸ زودتر افتاد — ${_name(w)} برنده شد';
          en = '8-ball potted early — ${_name(w)} wins';
          break;
        case PoolEndReason.eightWithFoul:
          fa = 'توپ ۸ با خطا افتاد — ${_name(w)} برنده شد';
          en = '8-ball potted on a foul — ${_name(w)} wins';
          break;
        case PoolEndReason.none:
          fa = '${_name(w)} برنده شد';
          en = '${_name(w)} wins';
          break;
      }
      _showBanner(_l.tx(fa, en), w == 0 ? _p0Color : _p1Color, seconds: 3);
      _endWait = 2.0;
      return;
    }
    _stage = _Stage.aiming;
    final String next = _name(_match.current);
    final Color nextColor = _match.current == 0 ? _p0Color : _p1Color;
    if (r.isFoul) {
      String fa = '';
      String en = '';
      switch (r.foul) {
        case PoolFoul.scratch:
          fa = 'خطا: توپ سفید افتاد';
          en = 'Foul: scratch';
          break;
        case PoolFoul.noContact:
          fa = 'خطا: به هیچ توپی نخورد';
          en = 'Foul: no ball hit';
          break;
        case PoolFoul.wrongBallFirst:
          fa = 'خطا: اول به توپ اشتباه خورد';
          en = 'Foul: wrong ball first';
          break;
        case PoolFoul.noRail:
          fa = 'خطا: بعد از برخورد هیچ توپی به دیواره نخورد';
          en = 'Foul: no rail after contact';
          break;
        case PoolFoul.none:
          fa = '';
          en = '';
          break;
      }
      _showBanner(_l.tx('$fa\nتوپ در دست: $next', '$en\nBall in hand: $next'),
          NxColors.danger,
          seconds: 2.6);
    } else if (r.assigned != PoolGroup.none) {
      final bool solids = r.assigned == PoolGroup.solids;
      _showBanner(
        _l.tx(
            '${_name(r.shooter)}: ${solids ? 'ساده‌ها (۱ تا ۷)' : 'راه‌راه‌ها (۹ تا ۱۵)'}',
            '${_name(r.shooter)}: ${solids ? 'solids (1-7)' : 'stripes (9-15)'}'),
        r.shooter == 0 ? _p0Color : _p1Color,
      );
    } else if (r.eightRespotted) {
      _showBanner(
          _l.tx('توپ ۸ در بریک افتاد و برگشت',
              '8-ball potted on the break — re-spotted'),
          NxColors.violet);
    } else if (r.continues) {
      _showBanner(_l.tx('عالی! دوباره بزن', 'Nice! Shoot again'), nextColor,
          seconds: 1.4);
    } else {
      _showBanner(_l.tx('نوبت $next', "$next's turn"), nextColor, seconds: 1.5);
    }
    _prepareTurn();
    setState(() {});
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    final int w = _match.winner ?? 1;
    final int s0 = _match.pottedCount(0) + (w == 0 ? 1 : 0);
    final int s1 = _match.pottedCount(1) + (w == 1 ? 1 : 0);
    final int me = _l.mySeat;
    _l.onFinish(GameResult(
      outcome: w == me ? GameOutcome.win : GameOutcome.loss,
      score: me == 0 ? s0 : s1,
      opponentScore: me == 0 ? s1 : s0,
      winnerSeats: <int>[w],
      scores: <int>[s0, s1],
      summaryFa: '${_name(w)} برنده‌ی ایت‌بال شد · ${_match.shotCount} ضربه',
      summaryEn: '${_name(w)} won the 8-ball match · ${_match.shotCount} shots',
    ));
  }

  // ---------------------------------------------------------------- input
  Offset _toTable(Offset local) => Offset(
      local.dx / _s - PoolConfig.artClothLeft,
      local.dy / _s - PoolConfig.artClothTop);

  void _aimAt(Offset t) {
    final PoolBall c = _match.cue;
    final double dx = t.dx - c.x, dy = t.dy - c.y;
    if (dx * dx + dy * dy < 16) return;
    _scene.aimAngle = math.atan2(dy, dx);
  }

  void _onPanStart(DragStartDetails d) {
    if (!_humanCanAct) return;
    final Offset t = _toTable(d.localPosition);
    final PoolBall c = _match.cue;
    final double dx = t.dx - c.x, dy = t.dy - c.y;
    if (_match.ballInHand &&
        dx * dx + dy * dy <
            (PoolConfig.ballR * 3.2) * (PoolConfig.ballR * 3.2)) {
      _draggingCue = true;
      _scene.placing = true;
      return;
    }
    _aimAt(t);
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (!_humanCanAct) return;
    final Offset t = _toTable(d.localPosition);
    if (_draggingCue) {
      const double r = PoolConfig.ballR;
      final double x = t.dx.clamp(r, PoolConfig.tableW - r).toDouble();
      double y = t.dy.clamp(r, PoolConfig.tableH - r).toDouble();
      if (_match.kitchenOnly && y < PoolConfig.headStringY)
        y = PoolConfig.headStringY;
      _scene.placeValid = _match.placeCue(x, y);
      return;
    }
    _aimAt(t);
  }

  void _onPanEnd() {
    if (_draggingCue) {
      _draggingCue = false;
      _scene.placing = false;
      _scene.placeValid = true;
      _setAimTowardNearestLegal();
    }
  }

  void _onTapUp(TapUpDetails d) {
    if (!_humanCanAct) return;
    _aimAt(_toTable(d.localPosition));
  }

  void _powerStart(double x) {
    if (!_humanCanAct) return;
    _charging = true;
    _chargeStartX = x;
  }

  void _powerUpdate(double x, double width) {
    if (!_charging || !_humanCanAct) return;
    final double p =
        ((x - _chargeStartX).abs() / (width * 0.8)).clamp(0.0, 1.0).toDouble();
    setState(() => _power = p);
    _scene.pull = p;
  }

  void _powerEnd() {
    if (!_charging) return;
    _charging = false;
    final double p = _power;
    if (!_humanCanAct || p < 0.04) {
      setState(() => _power = 0);
      _scene.pull = 0;
      return;
    }
    final PoolShot shot = PoolShot(
      dirX: math.cos(_scene.aimAngle),
      dirY: math.sin(_scene.aimAngle),
      power: p,
      spin: _spin,
      side: _side,
    );
    setState(() => _power = 0);
    _shoot(shot);
  }

  void _setSpinFrom(Offset local, double size) {
    final double r = size / 2;
    double sx = (local.dx - r) / (r * 0.72);
    double sy = -(local.dy - r) / (r * 0.72);
    final double l = math.sqrt(sx * sx + sy * sy);
    if (l > 1) {
      sx /= l;
      sy /= l;
    }
    setState(() {
      _side = sx;
      _spin = sy;
    });
  }

  // ---------------------------------------------------------------- build
  @override
  Widget build(BuildContext context) {
    _theme = NxThemeColors.of(context);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            _theme.backgroundMid,
            _theme.background,
            scheme.surface
          ],
        ),
      ),
      child: SafeArea(
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints box) {
            const double topH = 92;
            const double trayH = 26;
            const double bottomH = 104;
            final double availW = box.maxWidth - 12;
            final double availH = box.maxHeight - topH - trayH - bottomH - 8;
            final double s = math.max(0.05,
                math.min(availW / PoolConfig.artW, availH / PoolConfig.artH));
            _s = s;
            final double tw = PoolConfig.artW * s, th = PoolConfig.artH * s;
            final double left = (box.maxWidth - tw) / 2;
            final double top = topH + math.max(0.0, (availH - th) / 2);
            return Stack(
              children: <Widget>[
                Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    height: topH,
                    child: _buildHud()),
                Positioned(
                  left: left,
                  top: top,
                  width: tw,
                  height: th,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: _onPanStart,
                    onPanUpdate: _onPanUpdate,
                    onPanEnd: (DragEndDetails d) => _onPanEnd(),
                    onPanCancel: _onPanEnd,
                    onTapUp: _onTapUp,
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        Nx2ArtCanvas(
                          asset: kPoolSkins[_skin].asset,
                          size: Size(tw, th),
                          painter: (ui.Image img) => PoolSkinPainter(img, kPoolSkins[_skin]),
                          fallback: CustomPaint(
                              painter: PoolTableFallbackPainter(accent: _theme.accent)),
                        ),
                        RepaintBoundary(
                          child: CustomPaint(
                            painter: PoolScenePainter(
                              _scene,
                              accent: _theme.accent,
                              accentSecondary: _theme.accentSecondary,
                              error: scheme.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                    left: left,
                    top: top,
                    width: tw,
                    height: th,
                    child: IgnorePointer(child: _buildBanner())),
                Positioned(
                    left: 12,
                    right: 12,
                    top: top + th + 4,
                    height: trayH - 4,
                    child: _buildTray()),
                Positioned(
                    left: 12,
                    right: 12,
                    bottom: 6,
                    height: bottomH - 8,
                    child: _buildControls()),
                if (_spinOpen) Positioned.fill(child: _buildSpinPicker()),
              ],
            );
          }),
        ),
      ),
    );
  }

  Widget _buildHud() {
    String sub(int seat) {
      final PoolGroup g = _match.groups[seat];
      if (_match.groupCleared(seat))
        return _l.tx('نوبت توپ ۸', 'On the 8-ball');
      if (g == PoolGroup.solids)
        return _l.tx('ساده‌ها · ${_match.pottedCount(seat)}/۷',
            'Solids · ${_match.pottedCount(seat)}/7');
      if (g == PoolGroup.stripes)
        return _l.tx('راه‌راه‌ها · ${_match.pottedCount(seat)}/۷',
            'Stripes · ${_match.pottedCount(seat)}/7');
      return _match.isBreak
          ? _l.tx('بریک', 'Break')
          : _l.tx('میز باز', 'Open table');
    }

    final Set<int> potted = <int>{};
    for (int i = 1; i < 16; i++) {
      if (_match.balls[i].pocketed) potted.add(i);
    }
    final bool active0 = !_match.isOver && _match.current == 0;
    final bool active1 = !_match.isOver && _match.current == 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(62, 8, 12, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: PoolPlayerCard(
              name: _name(0),
              subtitle: sub(0),
              group: _match.groups[0],
              pottedIds: potted,
              active: active0,
              accent: _p0Color,
              onEight: _match.groupCleared(0),
              alignEnd: false,
              accentSecondary: _theme.accentSecondary,
              motion: _motion,
            ),
          ),
          SizedBox(
            width: 44,
            child: Column(
              children: <Widget>[
                const SizedBox(height: 2),
                const PoolMiniBall(id: 8, size: 22),
                const SizedBox(height: 4),
                Text(
                  _isBotTurn &&
                          _stage == _Stage.aiming &&
                          _botStage == _BotStage.thinking
                      ? '…'
                      : 'VS',
                  style: const TextStyle(
                      color: NxColors.textDim,
                      fontSize: 11,
                      fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Nx2BoardButton(onTap: _nextSkin, color: kPoolSkins[_skin].glow),
              ],
            ),
          ),
          Expanded(
            child: PoolPlayerCard(
              name: _name(1),
              subtitle: sub(1),
              group: _match.groups[1],
              pottedIds: potted,
              active: active1,
              accent: _p1Color,
              onEight: _match.groupCleared(1),
              alignEnd: true,
              accentSecondary: _theme.accentSecondary,
              motion: _motion,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBanner() {
    final bool visible = _bannerLeft > 0 && _bannerText.isNotEmpty;
    return Align(
      alignment: const Alignment(0, -0.1),
      child: AnimatedSwitcher(
        duration: _motion ? const Duration(milliseconds: 240) : Duration.zero,
        transitionBuilder: (Widget child, Animation<double> a) =>
            FadeTransition(
          opacity: a,
          child: ScaleTransition(
              scale: Tween<double>(begin: 0.85, end: 1).animate(a),
              child: child),
        ),
        child: !visible
            ? const SizedBox.shrink(key: ValueKey<String>('none'))
            : Container(
                key: ValueKey<int>(_bannerId),
                margin: const EdgeInsets.symmetric(horizontal: 26),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                decoration: BoxDecoration(
                  color: _theme.surfaceRaised.withOpacity(0.96),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                      color: _bannerColor.withOpacity(0.9), width: 1.4),
                  boxShadow: _motion
                      ? <BoxShadow>[
                          BoxShadow(
                              color: _bannerColor.withOpacity(0.35),
                              blurRadius: 20)
                        ]
                      : const <BoxShadow>[],
                ),
                child: Directionality(
                  textDirection:
                      _l.isFa ? TextDirection.rtl : TextDirection.ltr,
                  child: Text(
                    _bannerText,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: _bannerColor,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        height: 1.35),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildTray() {
    final List<Widget> items = <Widget>[];
    for (final int id in _pottedOrder) {
      if (id == 0) continue;
      items.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1.5),
          child: PoolMiniBall(id: id, size: 17)));
    }
    String status;
    if (_match.isOver) {
      status = _l.tx('پایان بازی', 'Game over');
    } else if (_isBotTurn) {
      status = _botStage == _BotStage.thinking
          ? _l.tx('ربات در حال فکر…', 'Bot is thinking…')
          : _l.tx('نوبت ربات', 'Bot to shoot');
    } else if (_match.ballInHand && _stage == _Stage.aiming) {
      status = _match.kitchenOnly
          ? _l.tx('توپ سفید را پشت خط بکش', 'Drag the cue ball behind the line')
          : _l.tx('توپ در دست: سفید را جابه‌جا کن',
              'Ball in hand: drag the cue ball');
    } else {
      status = _l.tx(
          'نوبت ${_name(_match.current)}', "${_name(_match.current)}'s turn");
    }
    return Row(
      children: <Widget>[
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: true,
            child: Row(children: items),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Directionality(
            textDirection: _l.isFa ? TextDirection.rtl : TextDirection.ltr,
            child: Text(
              status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _match.current == 0 ? _p0Color : _p1Color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildControls() {
    final bool enabled = _humanCanAct && !_draggingCue;
    final String label = _power > 0
        ? _l.tx('قدرت ${(_power * 100).round()}٪',
            'Power ${(_power * 100).round()}%')
        : _l.tx('بکش و رها کن', 'Pull & release');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        GestureDetector(
          onTap: enabled ? () => setState(() => _spinOpen = true) : null,
          child: Container(
            width: 64,
            height: 88,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _theme.surfaceRaised.withOpacity(0.96),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: enabled
                      ? _theme.accent.withOpacity(0.75)
                      : _theme.border),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: PoolSpinFace(side: _side, spin: _spin, size: 44),
                  ),
                ),
                const SizedBox(height: 3),
                Text(_l.tx('اسپین', 'Spin'),
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: TextStyle(
                        color: enabled ? _theme.accent : _theme.muted,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        height: 1.1)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              PoolFineAimStrip(
                angle: _scene.aimAngle,
                enabled: enabled,
                label: _l.tx('تنظیم دقیق نشانه', 'Fine aim'),
                onDelta: (double dx) {
                  _scene.aimAngle += dx * 0.0022;
                  setState(() {});
                },
              ),
              const SizedBox(height: 8),
              PoolPowerBar(
                power: _power,
                enabled: enabled,
                label: label,
                onStart: _powerStart,
                onUpdate: _powerUpdate,
                onEnd: _powerEnd,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSpinPicker() {
    const double size = 190;
    return GestureDetector(
      onTap: () => setState(() => _spinOpen = false),
      child: Container(
        color: _theme.background.withOpacity(0.82),
        alignment: Alignment.center,
        child: GestureDetector(
          onTap: () {},
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
            decoration: BoxDecoration(
              color: _theme.surfaceRaised.withOpacity(0.98),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _theme.border.withOpacity(0.9)),
              boxShadow: _motion
                  ? <BoxShadow>[
                      BoxShadow(
                          color: _theme.accent.withOpacity(0.22),
                          blurRadius: 28)
                    ]
                  : const <BoxShadow>[],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                    _l.tx('نقطه‌ی ضربه روی توپ سفید', 'Cue-ball contact point'),
                    style: TextStyle(
                        color: _theme.text,
                        fontWeight: FontWeight.w800,
                        fontSize: 15)),
                const SizedBox(height: 4),
                Text(
                    _l.tx('بالا = فالو · پایین = برگشت · چپ/راست = انگلیسی',
                        'Top = follow · Bottom = draw · Sides = english'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _theme.muted, fontSize: 11)),
                const SizedBox(height: 14),
                GestureDetector(
                  onPanDown: (DragDownDetails d) =>
                      _setSpinFrom(d.localPosition, size),
                  onPanUpdate: (DragUpdateDetails d) =>
                      _setSpinFrom(d.localPosition, size),
                  child: PoolSpinFace(side: _side, spin: _spin, size: size),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    TextButton(
                      onPressed: () => setState(() {
                        _spin = 0;
                        _side = 0;
                      }),
                      child: Text(_l.tx('وسط', 'Center'),
                          style: TextStyle(color: _theme.muted)),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor: _theme.accent,
                          foregroundColor:
                              Theme.of(context).colorScheme.onPrimary),
                      onPressed: () => setState(() => _spinOpen = false),
                      child: Text(_l.tx('تأیید', 'Done'),
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
