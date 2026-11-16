import 'pool_config.dart';
import 'pool_physics.dart';

/// Input for one shot: everything the (future) server needs to replay it.
class PoolShot {
  const PoolShot({
    required this.dirX,
    required this.dirY,
    required this.power,
    this.spin = 0,
    this.side = 0,
    this.cueX,
    this.cueY,
  });

  final double dirX;
  final double dirY;

  /// 0..1 of [PoolConfig.maxShotSpeed].
  final double power;

  /// -1 draw .. +1 follow.
  final double spin;

  /// -1 left .. +1 right english.
  final double side;

  /// Cue ball placement when the shooter has ball-in-hand (optional).
  final double? cueX;
  final double? cueY;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'dx': dirX,
        'dy': dirY,
        'p': power,
        's': spin,
        'e': side,
        if (cueX != null) 'cx': cueX,
        if (cueY != null) 'cy': cueY,
      };
}

enum PoolPhase { aiming, simulating, over }

enum PoolFoul { none, scratch, noContact, wrongBallFirst, noRail }

/// Why the match ended.
enum PoolEndReason { none, eightPotted, eightEarly, eightWithFoul }

/// Outcome of a resolved shot, used by the HUD for messages.
class PoolShotReport {
  PoolShotReport({
    required this.shooter,
    required this.foul,
    required this.pocketed,
    required this.continues,
    required this.assigned,
    required this.wasBreak,
    required this.eightRespotted,
  });

  final int shooter;
  final PoolFoul foul;
  final List<int> pocketed;
  final bool continues;

  /// Group assigned to the shooter on this shot (none if no assignment happened).
  final PoolGroup assigned;
  final bool wasBreak;
  final bool eightRespotted;

  bool get isFoul => foul != PoolFoul.none;
}

/// Full 8-ball match state + rules. Pure Dart, deterministic.
class PoolMatch {
  PoolMatch._(this.balls, this.world);

  factory PoolMatch.newRack({int breaker = 0, bool requireRail = true}) {
    final List<PoolBall> bs = poolRackBalls();
    final PoolMatch m = PoolMatch._(bs, PoolWorld(bs));
    m.current = breaker;
    m.breaker = breaker;
    m.requireRail = requireRail;
    return m;
  }

  final List<PoolBall> balls;
  final PoolWorld world;

  int current = 0;
  int breaker = 0;
  bool requireRail = true;
  List<PoolGroup> groups = <PoolGroup>[PoolGroup.none, PoolGroup.none];
  PoolPhase phase = PoolPhase.aiming;
  bool isBreak = true;
  bool ballInHand = true;

  /// Ball in hand is restricted to the kitchen (only for the break).
  bool kitchenOnly = true;
  int? winner;
  PoolEndReason endReason = PoolEndReason.none;
  int shotCount = 0;
  PoolShotReport? lastReport;

  // per shot
  bool _groupClearedAtStart = false;
  PoolGroup _groupAtStart = PoolGroup.none;

  PoolBall get cue => balls[0];
  int get opponent => 1 - current;
  bool get isOver => phase == PoolPhase.over;

  PoolMatch clone() {
    final List<PoolBall> bs = balls.map((PoolBall b) => b.clone()).toList();
    final PoolMatch m = PoolMatch._(bs, PoolWorld(bs));
    m.current = current;
    m.breaker = breaker;
    m.requireRail = requireRail;
    m.groups = List<PoolGroup>.from(groups);
    m.phase = phase;
    m.isBreak = isBreak;
    m.ballInHand = ballInHand;
    m.kitchenOnly = kitchenOnly;
    m.winner = winner;
    m.endReason = endReason;
    m.shotCount = shotCount;
    m.lastReport = lastReport;
    m._groupAtStart = _groupAtStart;
    m._groupClearedAtStart = _groupClearedAtStart;
    return m;
  }

  /// Online sync: full resting-state snapshot (balls + rules state).
  Map<String, dynamic> toSnap() => <String, dynamic>{
        'b': <List<num>>[
          for (final PoolBall b in balls) <num>[b.x, b.y, b.pocketed ? b.pocket : -1],
        ],
        'cur': current,
        'g': <int>[groups[0].index, groups[1].index],
        'ph': phase.index,
        'brk': isBreak ? 1 : 0,
        'bih': ballInHand ? 1 : 0,
        'k': kitchenOnly ? 1 : 0,
        'w': winner,
        'er': endReason.index,
        'sc': shotCount,
      };

  void applySnap(Map<String, dynamic> j) {
    final List<dynamic> bs = (j['b'] as List<dynamic>?) ?? const <dynamic>[];
    for (int i = 0; i < bs.length && i < balls.length; i++) {
      final List<dynamic> e = bs[i] as List<dynamic>;
      final int pk = (e[2] as num).toInt();
      balls[i]
        ..x = (e[0] as num).toDouble()
        ..y = (e[1] as num).toDouble()
        ..vx = 0
        ..vy = 0
        ..pocketed = pk >= 0
        ..pocket = pk;
    }
    current = (j['cur'] as num).toInt();
    final List<dynamic> g = (j['g'] as List<dynamic>?) ?? const <dynamic>[0, 0];
    groups = <PoolGroup>[PoolGroup.values[(g[0] as num).toInt()], PoolGroup.values[(g[1] as num).toInt()]];
    phase = PoolPhase.values[(j['ph'] as num).toInt()];
    isBreak = (j['brk'] as num).toInt() == 1;
    ballInHand = (j['bih'] as num).toInt() == 1;
    kitchenOnly = (j['k'] as num).toInt() == 1;
    winner = j['w'] == null ? null : (j['w'] as num).toInt();
    endReason = PoolEndReason.values[(j['er'] as num).toInt()];
    shotCount = (j['sc'] as num).toInt();
  }

  // ---------------------------------------------------------------- queries
  List<int> groupBalls(PoolGroup g) {
    if (g == PoolGroup.solids) return const <int>[1, 2, 3, 4, 5, 6, 7];
    if (g == PoolGroup.stripes) return const <int>[9, 10, 11, 12, 13, 14, 15];
    return const <int>[];
  }

  int remainingOf(PoolGroup g) {
    int n = 0;
    for (final int id in groupBalls(g)) {
      if (!balls[id].pocketed) n++;
    }
    return n;
  }

  int pottedCount(int player) {
    final PoolGroup g = groups[player];
    if (g == PoolGroup.none) return 0;
    return 7 - remainingOf(g);
  }

  bool groupCleared(int player) {
    final PoolGroup g = groups[player];
    return g != PoolGroup.none && remainingOf(g) == 0;
  }

  /// True if the current shooter may legally strike [id] first.
  bool isLegalTarget(int id, [int? player]) {
    final int p = player ?? current;
    if (id <= 0 || id > 15) return false;
    if (balls[id].pocketed) return false;
    final PoolGroup g = groups[p];
    if (isBreak) return true;
    if (g == PoolGroup.none) return id != 8;
    if (groupCleared(p)) return id == 8;
    return poolGroupOf(id) == g;
  }

  List<int> legalTargets([int? player]) {
    final List<int> out = <int>[];
    for (int id = 1; id <= 15; id++) {
      if (isLegalTarget(id, player)) out.add(id);
    }
    return out;
  }

  /// Can the cue ball be placed at (x, y) right now?
  bool canPlaceCue(double x, double y) {
    const double r = PoolConfig.ballR;
    if (x < r || x > PoolConfig.tableW - r || y < r || y > PoolConfig.tableH - r) return false;
    if (kitchenOnly && y < PoolConfig.headStringY) return false;
    for (int i = 1; i < balls.length; i++) {
      final PoolBall b = balls[i];
      if (b.pocketed) continue;
      final double dx = b.x - x, dy = b.y - y;
      if (dx * dx + dy * dy < (2 * r + 0.5) * (2 * r + 0.5)) return false;
    }
    return true;
  }

  bool placeCue(double x, double y) {
    if (!ballInHand || phase != PoolPhase.aiming) return false;
    if (!canPlaceCue(x, y)) return false;
    cue.x = x;
    cue.y = y;
    cue.pocketed = false;
    cue.pocket = -1;
    return true;
  }

  String? validate(PoolShot s) {
    if (phase != PoolPhase.aiming) return 'not_aiming';
    if (!(s.power > 0) || s.power > 1.0001) return 'bad_power';
    if (s.dirX.isNaN || s.dirY.isNaN || (s.dirX == 0 && s.dirY == 0)) return 'bad_dir';
    if (s.cueX != null && s.cueY != null) {
      if (!ballInHand) return 'no_ball_in_hand';
      if (!canPlaceCue(s.cueX!, s.cueY!)) return 'bad_cue_spot';
    }
    if (cue.pocketed) return 'cue_off_table';
    return null;
  }

  // ---------------------------------------------------------------- shot flow
  /// Starts a shot. After this call `world.tick()` until it returns true, then [finishShot].
  bool beginShot(PoolShot s) {
    if (validate(s) != null) return false;
    if (s.cueX != null && s.cueY != null) placeCue(s.cueX!, s.cueY!);
    _groupAtStart = groups[current];
    _groupClearedAtStart = groupCleared(current);
    double p = s.power;
    if (p < PoolConfig.minShotPower) p = PoolConfig.minShotPower;
    world.strike(s.dirX, s.dirY, p, s.spin, s.side);
    phase = PoolPhase.simulating;
    ballInHand = false;
    return true;
  }

  /// Headless helper (bot, tests, server): plays the whole shot.
  PoolShotReport? playShot(PoolShot s) {
    if (!beginShot(s)) return null;
    world.runToEnd();
    return finishShot();
  }

  /// Applies the 8-ball rules to the finished simulation.
  PoolShotReport finishShot() {
    world.snap();
    shotCount++;
    final int shooter = current;
    final List<int> potted = List<int>.from(world.pocketedThisShot);
    final bool cuePotted = potted.contains(0);
    final bool eightPotted = potted.contains(8);
    final int first = world.firstContact;
    final bool wasBreak = isBreak;

    // ---- foul detection
    PoolFoul foul = PoolFoul.none;
    if (cuePotted) {
      foul = PoolFoul.scratch;
    } else if (first < 0) {
      foul = PoolFoul.noContact;
    } else if (!wasBreak && !_firstContactLegal(first)) {
      foul = PoolFoul.wrongBallFirst;
    } else if (!wasBreak && requireRail) {
      final bool objectPotted = potted.any((int id) => id != 0);
      if (!objectPotted && !world.railAfterContact) foul = PoolFoul.noRail;
    }

    PoolGroup assigned = PoolGroup.none;
    bool continues = false;
    bool eightRespotted = false;

    if (eightPotted) {
      if (wasBreak) {
        // 8 on the break: re-spot it and carry on.
        _respotEight();
        eightRespotted = true;
      } else if (!_groupClearedAtStart || _groupAtStart == PoolGroup.none) {
        _end(opponent, PoolEndReason.eightEarly);
      } else if (foul != PoolFoul.none) {
        _end(opponent, PoolEndReason.eightWithFoul);
      } else {
        _end(shooter, PoolEndReason.eightPotted);
      }
    }

    if (phase != PoolPhase.over) {
      final List<int> objects = potted.where((int id) => id != 0 && id != 8).toList();
      if (foul == PoolFoul.none) {
        if (wasBreak) {
          continues = objects.isNotEmpty;
        } else if (_groupAtStart == PoolGroup.none) {
          if (objects.isNotEmpty) {
            assigned = poolGroupOf(objects.first);
            groups[shooter] = assigned;
            groups[1 - shooter] = poolOtherGroup(assigned);
            continues = true;
          }
        } else {
          continues = objects.any((int id) => poolGroupOf(id) == _groupAtStart);
        }
      }

      if (cuePotted) {
        cue.pocketed = false;
        cue.pocket = -1;
        _spotCueSomewhere();
      }

      isBreak = false;
      kitchenOnly = false;
      if (foul != PoolFoul.none) {
        current = 1 - shooter;
        ballInHand = true;
      } else if (!continues) {
        current = 1 - shooter;
        ballInHand = false;
      } else {
        ballInHand = false;
      }
      phase = PoolPhase.aiming;
    }

    final PoolShotReport r = PoolShotReport(
      shooter: shooter,
      foul: foul,
      pocketed: potted,
      continues: continues && phase != PoolPhase.over,
      assigned: assigned,
      wasBreak: wasBreak,
      eightRespotted: eightRespotted,
    );
    lastReport = r;
    return r;
  }

  bool _firstContactLegal(int id) {
    if (id == 8) return _groupAtStart != PoolGroup.none && _groupClearedAtStart;
    if (_groupAtStart == PoolGroup.none) return true;
    if (_groupClearedAtStart) return false;
    return poolGroupOf(id) == _groupAtStart;
  }

  void _end(int win, PoolEndReason why) {
    winner = win;
    endReason = why;
    phase = PoolPhase.over;
    ballInHand = false;
  }

  void _respotEight() {
    final PoolBall e = balls[8];
    e.pocketed = false;
    e.pocket = -1;
    double y = PoolConfig.footSpotY;
    const double x = PoolConfig.footSpotX;
    while (y > PoolConfig.ballR && !_free(x, y, 8)) {
      y -= 2;
    }
    if (!_free(x, y, 8)) {
      y = PoolConfig.footSpotY;
      while (y < PoolConfig.tableH - PoolConfig.ballR && !_free(x, y, 8)) {
        y += 2;
      }
    }
    e.x = x;
    e.y = y;
  }

  /// After a scratch the cue is parked on the head spot area (it will be moved by
  /// the opponent's ball-in-hand anyway); ensures it never overlaps a ball.
  void _spotCueSomewhere() {
    double y = PoolConfig.breakCueY;
    const double x = PoolConfig.breakCueX;
    while (y > PoolConfig.ballR && !_free(x, y, 0)) {
      y -= 2;
    }
    cue.x = x;
    cue.y = y;
  }

  bool _free(double x, double y, int self) {
    const double r = PoolConfig.ballR;
    for (int i = 0; i < balls.length; i++) {
      if (i == self) continue;
      final PoolBall b = balls[i];
      if (b.pocketed) continue;
      final double dx = b.x - x, dy = b.y - y;
      if (dx * dx + dy * dy < (2 * r + 0.5) * (2 * r + 0.5)) return false;
    }
    return true;
  }

  int get stateHash => poolStateHash(balls);
}
