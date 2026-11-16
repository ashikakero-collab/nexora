import 'dart:math' as math;

import 'carrom_config.dart';
import 'carrom_physics.dart';

enum CrPhase { aiming, simulating, finished }

/// A shot: striker placement on the shooter's baseline + direction + power.
class CrShot {
  const CrShot({required this.placeX, required this.dirX, required this.dirY, required this.power});
  final double placeX;
  final double dirX;
  final double dirY;

  /// 0 < power <= 1
  final double power;

  Map<String, dynamic> toJson() => <String, dynamic>{'placeX': placeX, 'dirX': dirX, 'dirY': dirY, 'power': power};

  factory CrShot.fromJson(Map<String, dynamic> j) => CrShot(
        placeX: (j['placeX'] as num).toDouble(),
        dirX: (j['dirX'] as num).toDouble(),
        dirY: (j['dirY'] as num).toDouble(),
        power: (j['power'] as num).toDouble(),
      );
}

/// What a shot did, for UI messages and the bot.
class CrTurnOutcome {
  const CrTurnOutcome({
    required this.shooter,
    required this.steps,
    required this.ownPocketed,
    required this.oppPocketed,
    required this.queenPocketed,
    required this.foul,
    required this.queenCovered,
    required this.queenPending,
    required this.queenReturned,
    required this.returnedIds,
    required this.continueTurn,
    required this.matchOver,
  });

  final int shooter;
  final int steps;
  final int ownPocketed;
  final int oppPocketed;
  final bool queenPocketed;

  /// Striker pocketed.
  final bool foul;

  /// The shooter covered the queen with this shot.
  final bool queenCovered;

  /// Queen pocketed and must be covered with the next shot.
  final bool queenPending;

  /// Queen went back to the centre (not covered / foul).
  final bool queenReturned;

  /// Coins that were put back on the board (penalty or last-coin rule).
  final List<int> returnedIds;
  final bool continueTurn;
  final bool matchOver;
}

/// Authoritative Carrom state + rules (pure Dart, deterministic, server-runnable).
///
/// Rules (simplified official ICF rules, also shown in the UI):
///  * Seat 0 plays WHITE from the bottom baseline, seat 1 plays BLACK from the top baseline.
///  * Pocketing one of your coins (or the queen) = shoot again.
///  * Queen: after pocketing it you must "cover" it by pocketing one of your coins in the same
///    shot or your next shot; otherwise the queen returns to the centre.
///  * Foul = striker pocketed: coins of yours pocketed in that shot return, plus one of your
///    already pocketed coins as a penalty (if you have one); a pending queen returns; turn ends.
///  * Opponent coins you pocket stay pocketed (they count for the opponent).
///  * The last coin of a colour can't be pocketed before the queen is covered: it is returned.
///  * Win: all your 9 coins pocketed with the queen covered. Board points = opponent coins left
///    + 3 if you covered the queen. After [CrConfig.maxTurns] shots the higher tally wins
///    (pocketed coins + 3 for the queen), equal = draw.
class CrMatch {
  CrMatch._({
    required this.bodies,
    required this.turn,
    required this.turnNumber,
    required this.phase,
    required this.winner,
    required this.queenPendingFor,
    required this.queenCoveredBy,
    required this.points,
  });

  factory CrMatch.newBoard({int firstTurn = 0}) => CrMatch._(
        bodies: crInitialBodies(),
        turn: firstTurn,
        turnNumber: 0,
        phase: CrPhase.aiming,
        winner: null,
        queenPendingFor: -1,
        queenCoveredBy: -1,
        points: <int>[0, 0],
      );

  List<CrBody> bodies;
  int turn;
  int turnNumber;
  CrPhase phase;

  /// null = running, 0/1 = winner seat, -1 = draw.
  int? winner;
  int queenPendingFor;
  int queenCoveredBy;

  /// Board points (set when the board is won).
  List<int> points;

  /// Online sync: adopt a resting-state snapshot produced by [toJson].
  void applyJson(Map<String, dynamic> j) {
    final CrMatch o = CrMatch.fromJson(j);
    bodies = o.bodies;
    turn = o.turn;
    turnNumber = o.turnNumber;
    phase = o.phase;
    winner = o.winner;
    queenPendingFor = o.queenPendingFor;
    queenCoveredBy = o.queenCoveredBy;
    points = o.points;
  }

  CrBody get striker => bodies[CrConfig.strikerId];
  CrBody get queen => bodies[CrConfig.queenId];

  static CrKind kindFor(int seat) => seat == 0 ? CrKind.white : CrKind.black;
  static double baselineY(int seat) => seat == 0 ? CrConfig.baseline0 : CrConfig.baseline1;

  int remaining(int seat) {
    final k = kindFor(seat);
    var n = 0;
    for (final b in bodies) {
      if (b.kind == k && b.onBoard) n++;
    }
    return n;
  }

  int pocketedCount(int seat) => CrConfig.coinsPerSide - remaining(seat);

  /// Tally used for the turn-limit decision.
  int tally(int seat) => pocketedCount(seat) + (queenCoveredBy == seat ? CrConfig.queenBonus : 0);

  CrMatch clone() => CrMatch._(
        bodies: bodies.map((CrBody b) => b.clone()).toList(),
        turn: turn,
        turnNumber: turnNumber,
        phase: phase,
        winner: winner,
        queenPendingFor: queenPendingFor,
        queenCoveredBy: queenCoveredBy,
        points: List<int>.from(points),
      );

  /// Is the striker allowed at [x] on the current shooter's baseline?
  bool placementOk(double x) {
    if (!x.isFinite) return false;
    if (x < CrConfig.baseMinX || x > CrConfig.baseMaxX) return false;
    return crIsFree(bodies, x, baselineY(turn), CrConfig.strikerR, CrConfig.strikerId);
  }

  /// Nearest legal placement to [x] (searching outwards in 1-unit steps), or null.
  double? nearestPlacement(double x) {
    final x0 = math.max(CrConfig.baseMinX, math.min(CrConfig.baseMaxX, x));
    for (var d = 0; d <= 540; d++) {
      final a = x0 + d;
      if (a <= CrConfig.baseMaxX && placementOk(a)) return a;
      final b = x0 - d;
      if (b >= CrConfig.baseMinX && placementOk(b)) return b;
    }
    return null;
  }

  /// Returns an error code or null when the shot is legal.
  String? validate(CrShot s) {
    if (phase != CrPhase.aiming) return 'not_aiming';
    if (!s.placeX.isFinite || !s.dirX.isFinite || !s.dirY.isFinite || !s.power.isFinite) return 'not_finite';
    if (s.placeX < CrConfig.baseMinX || s.placeX > CrConfig.baseMaxX) return 'bad_place';
    if (!placementOk(s.placeX)) return 'blocked_place';
    if (s.dirX * s.dirX + s.dirY * s.dirY < 1e-12) return 'zero_dir';
    if (s.power <= 0 || s.power > 1) return 'bad_power';
    return null;
  }

  void beginShot(CrShot s) {
    final len = math.sqrt(s.dirX * s.dirX + s.dirY * s.dirY);
    final st = striker;
    st.x = s.placeX;
    st.y = baselineY(turn);
    st.onBoard = true;
    st.vx = s.dirX / len * s.power * CrConfig.maxShotSpeed;
    st.vy = s.dirY / len * s.power * CrConfig.maxShotSpeed;
    phase = CrPhase.simulating;
  }

  /// Applies the rules after the live/headless simulation ended. [pocketed] in pocketing order.
  CrTurnOutcome finishShot(List<int> pocketed, int steps) {
    final p = turn;
    final opp = 1 - p;
    final ownK = kindFor(p);
    final oppK = kindFor(opp);
    final ownIds = <int>[];
    final oppIds = <int>[];
    var strikerIn = false;
    var queenIn = false;
    for (final id in pocketed) {
      final k = bodies[id].kind;
      if (k == CrKind.striker) {
        strikerIn = true;
      } else if (k == CrKind.queen) {
        queenIn = true;
      } else if (k == ownK) {
        ownIds.add(id);
      } else if (k == oppK) {
        oppIds.add(id);
      }
    }
    // The striker always goes back to the shooter's hand.
    striker.onBoard = false;
    striker.vx = 0;
    striker.vy = 0;

    final returned = <int>[];
    final foul = strikerIn;
    var coveredNow = false;
    var queenBack = false;
    var cont = false;

    if (foul) {
      for (final id in ownIds) {
        crRespot(bodies, id);
        returned.add(id);
      }
      if (queenIn || queenPendingFor == p) {
        crRespot(bodies, CrConfig.queenId);
        queenBack = true;
        queenPendingFor = -1;
      }
      // Penalty: one already-pocketed coin of the shooter returns (lowest id first).
      for (final b in bodies) {
        if (b.kind == ownK && !b.onBoard) {
          crRespot(bodies, b.id);
          returned.add(b.id);
          break;
        }
      }
    } else {
      if (queenPendingFor == p) {
        if (ownIds.isNotEmpty) {
          queenCoveredBy = p;
          coveredNow = true;
        } else {
          crRespot(bodies, CrConfig.queenId);
          queenBack = true;
        }
        queenPendingFor = -1;
      }
      if (queenIn) {
        if (ownIds.isNotEmpty) {
          queenCoveredBy = p;
          coveredNow = true;
        } else {
          queenPendingFor = p;
        }
      }
      cont = ownIds.isNotEmpty || queenIn;
    }

    // Last-coin rule: a colour can't be finished while the queen is still uncovered.
    if (queenCoveredBy < 0) {
      for (var q = 0; q < 2; q++) {
        final seat = q == 0 ? p : opp;
        if (remaining(seat) != 0) continue;
        final k = kindFor(seat);
        var pick = -1;
        for (var i = pocketed.length - 1; i >= 0; i--) {
          if (bodies[pocketed[i]].kind == k) {
            pick = pocketed[i];
            break;
          }
        }
        if (pick < 0) {
          for (var i = bodies.length - 1; i >= 0; i--) {
            if (bodies[i].kind == k && !bodies[i].onBoard) {
              pick = i;
              break;
            }
          }
        }
        if (pick >= 0) {
          crRespot(bodies, pick);
          returned.add(pick);
        }
        if (seat == p) cont = false;
      }
    }
    if (!cont && queenPendingFor == p) {
      crRespot(bodies, CrConfig.queenId);
      queenPendingFor = -1;
      queenBack = true;
    }

    var over = false;
    if (queenCoveredBy >= 0) {
      if (remaining(p) == 0) {
        winner = p;
      } else if (remaining(opp) == 0) {
        winner = opp;
      }
      final w = winner;
      if (w != null && w >= 0) {
        over = true;
        points[w] = remaining(1 - w) + (queenCoveredBy == w ? CrConfig.queenBonus : 0);
      }
    }
    turnNumber += 1;
    if (!over && turnNumber >= CrConfig.maxTurns) {
      over = true;
      _decideByTally();
    }
    if (!over && !cont) turn = opp;
    crSnap(bodies);
    phase = over ? CrPhase.finished : CrPhase.aiming;
    return CrTurnOutcome(
      shooter: p,
      steps: steps,
      ownPocketed: ownIds.length,
      oppPocketed: oppIds.length,
      queenPocketed: queenIn,
      foul: foul,
      queenCovered: coveredNow,
      queenPending: queenPendingFor == p,
      queenReturned: queenBack,
      returnedIds: returned,
      continueTurn: !over && cont,
      matchOver: over,
    );
  }

  void _decideByTally() {
    final t0 = tally(0), t1 = tally(1);
    winner = t0 == t1 ? -1 : (t0 > t1 ? 0 : 1);
    final w = winner;
    if (w != null && w >= 0) points[w] = (t0 - t1).abs();
  }

  /// Headless shot (server, tests, bot search). Throws StateError on illegal shots.
  CrTurnOutcome playShot(CrShot s) {
    final err = validate(s);
    if (err != null) throw StateError(err);
    beginShot(s);
    final sim = CrSimulator(bodies)..runToEnd();
    return finishShot(sim.pocketed, sim.steps);
  }

  /// Turn timer expired: the shooter loses the turn (a pending queen returns).
  void passTurn() {
    if (phase != CrPhase.aiming) return;
    if (queenPendingFor == turn) {
      crRespot(bodies, CrConfig.queenId);
      queenPendingFor = -1;
      crSnap(bodies);
    }
    turn = 1 - turn;
    turnNumber += 1;
    if (turnNumber >= CrConfig.maxTurns) {
      phase = CrPhase.finished;
      _decideByTally();
    }
  }

  int stateHash() => crStateHash(bodies);

  Map<String, dynamic> toJson() => <String, dynamic>{
        'bodies': bodies.map((CrBody b) => b.toJson()).toList(),
        'turn': turn,
        'turnNumber': turnNumber,
        'phase': phase.index,
        'winner': winner,
        'queenPendingFor': queenPendingFor,
        'queenCoveredBy': queenCoveredBy,
        'points': points,
      };

  factory CrMatch.fromJson(Map<String, dynamic> j) {
    final fresh = crInitialBodies();
    final list = (j['bodies'] as List<dynamic>).cast<Map<String, dynamic>>();
    for (final m in list) {
      final id = (m['id'] as num).toInt();
      final b = fresh[id];
      b.x = (m['x'] as num).toDouble();
      b.y = (m['y'] as num).toDouble();
      b.onBoard = m['on'] == true;
    }
    return CrMatch._(
      bodies: fresh,
      turn: (j['turn'] as num).toInt(),
      turnNumber: (j['turnNumber'] as num).toInt(),
      phase: CrPhase.values[(j['phase'] as num).toInt()],
      winner: j['winner'] == null ? null : (j['winner'] as num).toInt(),
      queenPendingFor: (j['queenPendingFor'] as num).toInt(),
      queenCoveredBy: (j['queenCoveredBy'] as num).toInt(),
      points: (j['points'] as List<dynamic>).map((dynamic e) => (e as num).toInt()).toList(),
    );
  }
}
