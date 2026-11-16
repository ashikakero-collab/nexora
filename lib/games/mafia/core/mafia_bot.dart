import 'dart:math';

import 'mafia_engine.dart';
import 'mafia_lines.dart';
import 'mafia_models.dart';

/// Offline AI citizen. Each brain keeps a Bayesian-ish suspicion model:
/// log-odds per player that are nudged by public events (accusations,
/// defenses, claims, votes, deaths) and private knowledge (own role,
/// investigation results, saves), then renormalised so the probabilities sum
/// to the number of Mafia that should still be among the unknown players.
///
/// Town brains use the model to find Mafia. Mafia brains run the same model as
/// a "public view" (how suspicious the town finds everyone) to pick
/// scapegoats, plus a `threat` map of who endangers their team.
class BotBrain {
  BotBrain({
    required this.selfId,
    required this.role,
    required this.skill,
    required this.personality,
    required this.playerCount,
    required this.totalMafia,
    required Set<int> teammates,
    required int seed,
  }) : _rng = Random(seed) {
    if (role.isMafia) knownMafia.addAll(teammates);
    final double prior = role.isMafia ? totalMafia / playerCount : totalMafia / (playerCount - 1);
    final double l = log(prior / (1 - prior));
    for (int i = 0; i < playerCount; i++) {
      logit[i] = l;
      threat[i] = 0;
    }
    if (!role.isMafia) knownTown.add(selfId);
  }

  final int selfId;
  final MafiaRole role;
  final MafiaSkill skill;
  final BotPersonality personality;
  final int playerCount;
  final int totalMafia;
  final Random _rng;

  final Map<int, double> logit = <int, double>{};
  final Map<int, double> threat = <int, double>{};
  final Set<int> knownMafia = <int>{};
  final Set<int> knownTown = <int>{};
  final Set<int> publicMafia = <int>{};
  final Set<int> publicTown = <int>{};
  final Set<int> dead = <int>{};
  double deadUnknownMass = 0;

  final Map<int, Set<int>> accusedBy = <int, Set<int>>{};
  final Map<int, Set<int>> defendedBy = <int, Set<int>>{};
  final Map<int, int> accusationsMade = <int, int>{};
  final Map<int, MafiaRole> claims = <int, MafiaRole>{};
  final Map<int, Map<int, bool>> claimedChecks = <int, Map<int, bool>>{};
  Map<int, int?> lastFinal = <int, int?>{};
  List<int> lastDefendants = <int>[];

  /// Detective: own results. Doctor: last save.
  final Map<int, bool> checks = <int, bool>{};
  final Set<int> reported = <int>{};
  bool revealedRole = false;

  int accusedToday = 0;
  final Set<String> saidToday = <String>{};

  bool get isMafia => role.isMafia;

  double get _w {
    switch (skill) {
      case MafiaSkill.easy:
        return 0.5;
      case MafiaSkill.normal:
        return 0.8;
      case MafiaSkill.hard:
        return 1.0;
    }
  }

  double get _noiseAmp {
    double n = 0.35;
    switch (skill) {
      case MafiaSkill.easy:
        n = 0.9;
        break;
      case MafiaSkill.normal:
        n = 0.35;
        break;
      case MafiaSkill.hard:
        n = 0.12;
        break;
    }
    if (personality == BotPersonality.hothead) n += 0.1;
    return n;
  }

  double get talkChance {
    switch (personality) {
      case BotPersonality.hothead:
        return 0.9;
      case BotPersonality.analyst:
        return 0.75;
      case BotPersonality.cautious:
        return 0.5;
      case BotPersonality.joker:
        return 0.7;
      case BotPersonality.schemer:
        return 0.7;
    }
  }

  double _noise() => (_rng.nextDouble() * 2 - 1) * _noiseAmp;

  static double _sig(double x) => 1 / (1 + exp(-x));

  void _add(int id, double delta) {
    logit[id] = ((logit[id] ?? 0) + delta).clamp(-7.0, 7.0).toDouble();
  }

  /// Probability (in this brain's eyes) that [id] is Mafia. For Mafia brains
  /// this is the public view, i.e. how the town likely sees [id].
  double suspicion(int id) {
    if (publicMafia.contains(id)) return 1;
    if (publicTown.contains(id)) return 0;
    if (!isMafia) {
      if (knownMafia.contains(id)) return 1;
      if (knownTown.contains(id)) return 0;
    }
    return _sig(logit[id] ?? 0);
  }

  double _cred(int id) {
    if (id == selfId) return 1;
    return 1 - 2 * suspicion(id);
  }

  List<int> _candidates() {
    final List<int> c = <int>[];
    for (int i = 0; i < playerCount; i++) {
      if (dead.contains(i) || publicMafia.contains(i) || publicTown.contains(i)) continue;
      if (!isMafia && (knownMafia.contains(i) || knownTown.contains(i))) continue;
      c.add(i);
    }
    return c;
  }

  double _expectedMafiaAmong(List<int> cands) {
    final int pubDeadMafia = publicMafia.where((int i) => dead.contains(i)).length;
    double k = totalMafia - pubDeadMafia - deadUnknownMass;
    if (!isMafia) {
      k -= knownMafia.where((int i) => !dead.contains(i) && !publicMafia.contains(i)).length;
    }
    final int aliveMafiaPublic = publicMafia.where((int i) => !dead.contains(i)).length;
    k -= aliveMafiaPublic;
    return k;
  }

  /// Baseline probability per unknown player.
  double baseline() {
    final List<int> c = _candidates();
    if (c.isEmpty) return 0.3;
    return (_expectedMafiaAmong(c) / c.length).clamp(0.05, 0.95).toDouble();
  }

  void _normalize() {
    final List<int> c = _candidates();
    if (c.isEmpty) return;
    final double hiK = c.length - 0.05;
    double k = _expectedMafiaAmong(c);
    if (k < 0.05) k = 0.05;
    if (k > hiK) k = hiK;
    if (hiK < 0.05) return;
    double lo = -12;
    double hi = 12;
    for (int it = 0; it < 40; it++) {
      final double mid = (lo + hi) / 2;
      double s = 0;
      for (final int i in c) {
        s += _sig((logit[i] ?? 0) + mid);
      }
      if (s > k) {
        hi = mid;
      } else {
        lo = mid;
      }
    }
    final double shift = (lo + hi) / 2;
    for (final int i in c) {
      _add(i, shift);
    }
  }

  // ------------------------------------------------------------- observing
  void newDay() {
    accusedToday = 0;
    saidToday.clear();
  }

  void observeSpeech(SpeechAct a) {
    final int s = a.speaker;
    final int? t = a.target;
    switch (a.type) {
      case SpeechType.accuse:
      case SpeechType.agree:
        if (t == null) return;
        accusedBy.putIfAbsent(t, () => <int>{}).add(s);
        accusationsMade[s] = (accusationsMade[s] ?? 0) + 1;
        if (t == selfId) accusedToday++;
        if (isMafia) {
          if (knownMafia.contains(t) && s != selfId) threat[s] = (threat[s] ?? 0) + a.strength;
          if (s != selfId) _add(t, 0.5 * _w * a.strength * _cred(s));
        } else if (s != selfId) {
          if (t == selfId || knownTown.contains(t)) {
            _add(s, (t == selfId ? 0.9 : 0.5) * _w);
          } else if (knownMafia.contains(t)) {
            _add(s, -0.3 * _w);
          } else {
            _add(t, 0.5 * _w * a.strength * _cred(s));
            _add(s, 0.05);
          }
        }
        break;
      case SpeechType.defend:
        if (t == null || s == selfId) return;
        defendedBy.putIfAbsent(t, () => <int>{}).add(s);
        if (!isMafia && knownMafia.contains(t)) {
          _add(s, 1.2 * _w);
        } else if (!isMafia && t == selfId) {
          _add(s, -0.2 * _w);
        } else {
          _add(t, -0.3 * _w * _cred(s));
        }
        break;
      case SpeechType.claimRole:
        _observeClaim(s, a.role ?? MafiaRole.citizen);
        break;
      case SpeechType.reportCheck:
        if (t == null) return;
        _observeReport(s, t, a.checkMafia == true);
        break;
      case SpeechType.selfDefense:
      case SpeechType.plea:
      case SpeechType.vague:
      case SpeechType.lastWords:
        break;
    }
    _normalize();
  }

  void _observeClaim(int claimer, MafiaRole claimed) {
    if (claimer == selfId) return;
    int? rival;
    claims.forEach((int k, MafiaRole r) {
      if (k != claimer && r == claimed && !dead.contains(k)) rival = k;
    });
    claims[claimer] = claimed;
    if (claimed == MafiaRole.citizen) {
      _add(claimer, -0.05);
      return;
    }
    if (isMafia) {
      if (knownMafia.contains(claimer)) return;
      if (claimed == MafiaRole.detective) {
        threat[claimer] = (threat[claimer] ?? 0) + 3;
      } else {
        threat[claimer] = (threat[claimer] ?? 0) + 1.5;
      }
      _add(claimer, -0.5 * _w);
      if (rival != null) {
        _add(claimer, 1.0 * _w);
        _add(rival!, 1.0 * _w);
      }
      return;
    }
    if (claimed == role) {
      // I hold that role: the claimer is lying.
      _add(claimer, 4.5);
      return;
    }
    if (rival != null) {
      _add(claimer, 1.0 * _w);
      _add(rival!, 1.0 * _w);
    } else {
      _add(claimer, -0.6 * _w);
    }
  }

  void _observeReport(int claimer, int target, bool mafia) {
    claimedChecks.putIfAbsent(claimer, () => <int, bool>{})[target] = mafia;
    if (claimer == selfId) return;
    if (isMafia) {
      if (knownMafia.contains(target) && mafia) threat[claimer] = (threat[claimer] ?? 0) + 4;
      _add(target, (mafia ? 1.6 : -0.9) * _w * _cred(claimer));
      return;
    }
    if (target == selfId && mafia) {
      _add(claimer, 6);
      return;
    }
    if (role == MafiaRole.detective && checks.containsKey(target) && checks[target] != mafia) {
      _add(claimer, 3);
      return;
    }
    if (knownMafia.contains(target) && !mafia) {
      _add(claimer, 2.5 * _w);
      return;
    }
    final double c = _cred(claimer);
    if (mafia) {
      _add(target, 1.8 * _w * c);
    } else {
      _add(target, -(skill == MafiaSkill.hard ? 0.7 : 1.0) * _w * c);
    }
  }

  void observeNomination(Map<int, int?> votes) {
    votes.forEach((int voter, int? target) {
      if (voter == selfId || target == null) return;
      if (!isMafia && (target == selfId || knownTown.contains(target))) _add(voter, 0.35 * _w);
      if (!isMafia && knownMafia.contains(target)) _add(voter, -0.2 * _w);
      if (isMafia && knownMafia.contains(target)) threat[voter] = (threat[voter] ?? 0) + 0.4;
    });
    _normalize();
  }

  void observeFinal(Map<int, int?> votes, List<int> defendants) {
    lastFinal = Map<int, int?>.from(votes);
    lastDefendants = List<int>.from(defendants);
  }

  void observeDeath(int id, DeathCause cause, MafiaRole? revealed, {bool byVote = false}) {
    if (dead.contains(id)) return;
    final double pBefore = suspicion(id);
    dead.add(id);
    bool? wasMafia;
    if (revealed != null) {
      wasMafia = revealed.isMafia;
    } else if (cause == DeathCause.nightKill || cause == DeathCause.sniperBackfire) {
      wasMafia = false;
    } else if (cause == DeathCause.sniperShot) {
      wasMafia = true;
    }
    if (wasMafia == true) {
      publicMafia.add(id);
      for (final int d in defendedBy[id] ?? <int>{}) {
        _add(d, 0.8 * _w);
      }
      for (final int a in accusedBy[id] ?? <int>{}) {
        _add(a, -0.4 * _w);
      }
      if (byVote) {
        lastFinal.forEach((int voter, int? v) {
          if (v == id) _add(voter, -0.3 * _w);
          if (v == null && lastDefendants.contains(id)) _add(voter, 0.3 * _w);
        });
      }
      claimedChecks.forEach((int claimer, Map<int, bool> m) {
        if (!m.containsKey(id)) return;
        if (m[id] == true) {
          _add(claimer, -2.5 * _w);
        } else {
          _add(claimer, (revealed == MafiaRole.godfather ? 0.3 : 2.0) * _w);
        }
      });
    } else if (wasMafia == false) {
      publicTown.add(id);
      if (byVote) {
        lastFinal.forEach((int voter, int? v) {
          if (v == id) _add(voter, 0.45 * _w);
        });
        for (final int a in accusedBy[id] ?? <int>{}) {
          _add(a, 0.35 * _w);
        }
        for (final int d in defendedBy[id] ?? <int>{}) {
          _add(d, -0.2 * _w);
        }
      }
      if (cause == DeathCause.nightKill) {
        // The victim was a threat to the Mafia: their suspects look worse.
        accusedBy.forEach((int target, Set<int> accusers) {
          if (accusers.contains(id) && !dead.contains(target)) _add(target, 0.3 * _w);
        });
      }
      claimedChecks.forEach((int claimer, Map<int, bool> m) {
        if (!m.containsKey(id)) return;
        _add(claimer, m[id] == true ? 2.5 * _w : -0.4 * _w);
      });
      if (revealed != null && revealed != MafiaRole.citizen) {
        claims.forEach((int claimer, MafiaRole r) {
          if (claimer != id && r == revealed) _add(claimer, 5);
        });
      }
    } else {
      deadUnknownMass += pBefore;
    }
    if (isMafia) threat[id] = 0;
    _normalize();
  }

  /// Detective private result.
  void observeOwnCheck(int target, bool mafia) {
    checks[target] = mafia;
    if (mafia) {
      knownMafia.add(target);
    } else if (skill == MafiaSkill.hard) {
      // Could still be the Godfather.
      if ((logit[target] ?? 0) > -2.2) logit[target] = -2.2;
    } else {
      knownTown.add(target);
    }
    _normalize();
  }

  /// Doctor private result: an attack on [id] was prevented, so [id] is town.
  void observeSave(int id) {
    if (!isMafia) knownTown.add(id);
    _normalize();
  }

  // ------------------------------------------------------------- decisions
  int? _argmax(List<int> ids, double Function(int id) score) {
    if (ids.isEmpty) return null;
    int best = ids.first;
    double bs = -1e9;
    for (final int i in ids) {
      final double s = score(i);
      if (s > bs) {
        bs = s;
        best = i;
      }
    }
    return best;
  }

  /// Mafia: how much this brain wants [target] dead tonight.
  double killScore(int target) {
    double s = (threat[target] ?? 0) * 0.6;
    final MafiaRole? c = claims[target];
    if (c == MafiaRole.detective) s += 3;
    if (c == MafiaRole.doctor || c == MafiaRole.sniper) s += 1.5;
    s += (0.5 - suspicion(target)) * 1.2;
    s += (accusationsMade[target] ?? 0) * 0.1;
    return s + _noise() * 2;
  }

  /// Coordinated Mafia kill: every living Mafia brain scores the legal
  /// targets, the Godfather's opinion weighs more.
  static int? teamKill(List<BotBrain> mafiaBrains, MafiaEngine e) {
    final List<int> legal = e.legalMafiaTargets();
    if (legal.isEmpty || mafiaBrains.isEmpty) return null;
    final Map<int, double> total = <int, double>{for (final int t in legal) t: 0};
    for (final BotBrain b in mafiaBrains) {
      final double wgt = b.role == MafiaRole.godfather ? 1.5 : 1.0;
      for (final int t in legal) {
        total[t] = total[t]! + b.killScore(t) * wgt;
      }
    }
    int best = legal.first;
    for (final int t in legal) {
      if (total[t]! > total[best]!) best = t;
    }
    return best;
  }

  int? doctorChoice(MafiaEngine e) {
    final List<int> legal = e.legalDoctorTargets();
    if (legal.isEmpty) return null;
    if (skill == MafiaSkill.easy && _rng.nextDouble() < 0.5) return legal[_rng.nextInt(legal.length)];
    return _argmax(legal, (int t) {
      double s = (1 - suspicion(t));
      final MafiaRole? c = claims[t];
      if (c == MafiaRole.detective && suspicion(t) < 0.5) s += 3;
      if (c == MafiaRole.sniper) s += 1;
      if (t == selfId) s += revealedRole ? 1.4 : 0.5;
      s += (accusationsMade[t] ?? 0) * 0.3;
      if (knownTown.contains(t)) s += 0.4;
      return s + _noise();
    });
  }

  int? detectiveChoice(MafiaEngine e) {
    final List<int> legal = e.legalDetectiveTargets();
    if (legal.isEmpty) return null;
    List<int> fresh = legal.where((int t) => !checks.containsKey(t) && !publicTown.contains(t)).toList();
    if (fresh.isEmpty) fresh = legal;
    if (skill == MafiaSkill.easy) return fresh[_rng.nextInt(fresh.length)];
    return _argmax(fresh, (int t) => suspicion(t) + (accusedBy[t]?.length ?? 0) * 0.03 + _noise() * 0.5);
  }

  int? sniperChoice(MafiaEngine e) {
    final List<int> legal = e.legalSniperTargets();
    if (legal.isEmpty) return null;
    final List<int> sure = legal.where((int t) => knownMafia.contains(t) || publicMafia.contains(t)).toList();
    if (sure.isNotEmpty) return sure.first;
    final List<int> opts = legal.where((int t) => !knownTown.contains(t) && !publicTown.contains(t)).toList();
    final int? best = _argmax(opts, (int t) => suspicion(t) + _noise() * 0.2);
    if (best == null || e.day < 2) return null;
    double thr = 0.74;
    switch (skill) {
      case MafiaSkill.easy:
        thr = 0.62;
        break;
      case MafiaSkill.normal:
        thr = 0.74;
        break;
      case MafiaSkill.hard:
        thr = 0.82;
        break;
    }
    if (suspicion(best) >= thr) return best;
    if (skill == MafiaSkill.easy && _rng.nextDouble() < 0.08) return best;
    return null;
  }

  int? nominationVote(MafiaEngine e) {
    final List<int> legal = e.legalVoteTargets(selfId);
    if (legal.isEmpty) return null;
    if (isMafia) {
      if (skill == MafiaSkill.hard) {
        for (final int m in legal.where((int t) => knownMafia.contains(t))) {
          if (suspicion(m) > 0.85 && _rng.nextDouble() < 0.5) return m; // bus a doomed partner
        }
      }
      final List<int> town = legal.where((int t) => !knownMafia.contains(t)).toList();
      return _argmax(town, (int t) => suspicion(t) + (threat[t] ?? 0) * 0.15 + _noise());
    }
    final List<int> sure = legal.where((int t) => knownMafia.contains(t) || publicMafia.contains(t)).toList();
    if (sure.isNotEmpty) return sure.first;
    final List<int> opts = legal.where((int t) => !knownTown.contains(t) && !publicTown.contains(t)).toList();
    final int? best = _argmax(opts, (int t) => suspicion(t) + _noise() * 0.6);
    if (best == null) return null;
    final double need = max(0.25, baseline() * 1.2);
    final double skipChance = personality == BotPersonality.cautious ? 0.6 : 0.3;
    if (suspicion(best) < need && _rng.nextDouble() < skipChance) return null;
    return best;
  }

  int? finalVote(MafiaEngine e, List<int> defendants) {
    final List<int> opts = defendants.where((int d) => d != selfId && e.player(d).alive).toList();
    if (opts.isEmpty) return null;
    if (isMafia) {
      final List<int> town = opts.where((int d) => !knownMafia.contains(d)).toList();
      if (town.isNotEmpty) return _argmax(town, (int d) => suspicion(d) + _noise() * 0.3);
      for (final int m in opts) {
        if (skill == MafiaSkill.hard && suspicion(m) > 0.8 && _rng.nextDouble() < 0.5) return m;
      }
      return null;
    }
    final List<int> sure = opts.where((int d) => knownMafia.contains(d) || publicMafia.contains(d)).toList();
    if (sure.isNotEmpty) return sure.first;
    final List<int> unknown = opts.where((int d) => !knownTown.contains(d) && !publicTown.contains(d)).toList();
    final int? best = _argmax(unknown, (int d) => suspicion(d) + _noise() * 0.4);
    if (best == null) return null;
    final double thr = skill == MafiaSkill.easy ? 0.22 : max(0.3, baseline() * 1.25);
    if (suspicion(best) >= thr) return best;
    return _rng.nextDouble() < 0.25 ? best : null;
  }

  // ---------------------------------------------------------------- speech
  bool _shouldRevealDetective(MafiaEngine e) {
    if (checks.isEmpty) return false;
    final bool foundMafia = checks.values.any((bool v) => v);
    switch (skill) {
      case MafiaSkill.easy:
        return true;
      case MafiaSkill.normal:
        return foundMafia || e.aliveCount <= 5 || accusedToday >= 2;
      case MafiaSkill.hard:
        return (foundMafia && (e.day >= 2 || _rng.nextDouble() < 0.5)) || e.aliveCount <= 5 || accusedToday >= 2;
    }
  }

  List<SpeechAct> _detectiveReports(MafiaEngine e, int maxCount) {
    final List<SpeechAct> out = <SpeechAct>[];
    final List<int> order = checks.keys.where((int t) => !reported.contains(t)).toList()
      ..sort((int a, int b) => (checks[b]! ? 1 : 0) - (checks[a]! ? 1 : 0));
    for (final int t in order) {
      if (out.length >= maxCount) break;
      if (!checks[t]! && !e.player(t).alive) {
        reported.add(t);
        continue;
      }
      reported.add(t);
      out.add(SpeechAct(speaker: selfId, type: SpeechType.reportCheck, target: t, checkMafia: checks[t]));
    }
    return out;
  }

  bool _fresh(String key) {
    if (saidToday.contains(key)) return false;
    saidToday.add(key);
    return true;
  }

  /// One discussion turn. [counterClaimFree] lets one Mafia bot fake a
  /// Detective claim per game; [onCounterClaim] marks it used.
  List<SpeechAct> speak(MafiaEngine e, {required bool counterClaimFree, required void Function() onCounterClaim, required int round}) {
    final List<int> others = e.aliveIds.where((int i) => i != selfId).toList();
    if (others.isEmpty) return <SpeechAct>[];
    if (role == MafiaRole.detective) {
      if (!revealedRole && _shouldRevealDetective(e)) {
        revealedRole = true;
        return <SpeechAct>[
          SpeechAct(speaker: selfId, type: SpeechType.claimRole, role: MafiaRole.detective),
          ..._detectiveReports(e, 2),
        ];
      }
      if (revealedRole) {
        final List<SpeechAct> r = _detectiveReports(e, 1);
        if (r.isNotEmpty) return r;
      }
    }
    if (accusedToday >= 2 && _fresh('self')) {
      final int? accuser = _argmax(
          (accusedBy[selfId] ?? <int>{}).where((int a) => !dead.contains(a)).toList(), (int a) => suspicion(a));
      return <SpeechAct>[SpeechAct(speaker: selfId, type: SpeechType.selfDefense, target: accuser)];
    }
    if (isMafia) return _mafiaSpeech(e, others, counterClaimFree, onCounterClaim);
    if (_rng.nextDouble() > talkChance) return <SpeechAct>[];
    final List<int> opts = others.where((int t) => !knownTown.contains(t) && !publicTown.contains(t)).toList();
    final int? s = _argmax(opts, (int t) => suspicion(t) + _noise() * 0.3);
    final double base = baseline();
    if (s != null) {
      final double ps = suspicion(s);
      if ((ps > 0.65 || knownMafia.contains(s)) && _fresh('acc$s')) {
        return <SpeechAct>[SpeechAct(speaker: selfId, type: SpeechType.accuse, target: s, strength: 0.85)];
      }
      if (ps > base * 1.35 && _fresh('acc$s')) {
        final Set<int> acc = accusedBy[s] ?? <int>{};
        final List<int> allies = acc.where((int a) => a != selfId && suspicion(a) < base).toList();
        if (allies.isNotEmpty) {
          return <SpeechAct>[
            SpeechAct(speaker: selfId, type: SpeechType.agree, target: s, secondary: allies.first, strength: 0.55)
          ];
        }
        return <SpeechAct>[SpeechAct(speaker: selfId, type: SpeechType.accuse, target: s, strength: 0.5)];
      }
    }
    for (final int t in others) {
      final bool underFire = (accusedBy[t]?.length ?? 0) > 0;
      if (underFire && (knownTown.contains(t) || suspicion(t) < base * 0.5) && _fresh('def$t')) {
        return <SpeechAct>[SpeechAct(speaker: selfId, type: SpeechType.defend, target: t)];
      }
    }
    if (e.day == 1 && personality == BotPersonality.hothead && _rng.nextDouble() < 0.4) {
      final int t = others[_rng.nextInt(others.length)];
      if (_fresh('acc$t')) return <SpeechAct>[SpeechAct(speaker: selfId, type: SpeechType.accuse, target: t, strength: 0.4)];
    }
    if (_fresh('vague$round')) return <SpeechAct>[SpeechAct(speaker: selfId, type: SpeechType.vague)];
    return <SpeechAct>[];
  }

  List<SpeechAct> _mafiaSpeech(
      MafiaEngine e, List<int> others, bool counterClaimFree, void Function() onCounterClaim) {
    // Counter-claim a Detective who exposed one of us.
    if (counterClaimFree && skill != MafiaSkill.easy) {
      int? realDet;
      claimedChecks.forEach((int claimer, Map<int, bool> m) {
        if (knownMafia.contains(claimer) || dead.contains(claimer)) return;
        m.forEach((int t, bool v) {
          if (v && knownMafia.contains(t)) realDet = claimer;
        });
      });
      if (realDet != null && _rng.nextDouble() < (skill == MafiaSkill.hard ? 0.85 : 0.5)) {
        onCounterClaim();
        revealedRole = true;
        return <SpeechAct>[
          SpeechAct(speaker: selfId, type: SpeechType.claimRole, role: MafiaRole.detective),
          SpeechAct(speaker: selfId, type: SpeechType.reportCheck, target: realDet, checkMafia: true),
        ];
      }
    }
    if (_rng.nextDouble() > talkChance) return <SpeechAct>[];
    final List<int> town = others.where((int t) => !knownMafia.contains(t) && !publicTown.contains(t)).toList();
    final int? goat = _argmax(town, (int t) => suspicion(t) + (threat[t] ?? 0) * 0.2 + _noise() * 0.5);
    final double base = baseline();
    if (goat != null && suspicion(goat) > base * 1.1 && _fresh('acc$goat')) {
      final List<int> allies = (accusedBy[goat] ?? <int>{}).where((int a) => a != selfId).toList();
      if (allies.isNotEmpty && _rng.nextDouble() < 0.5) {
        return <SpeechAct>[
          SpeechAct(speaker: selfId, type: SpeechType.agree, target: goat, secondary: allies.first, strength: 0.6)
        ];
      }
      return <SpeechAct>[SpeechAct(speaker: selfId, type: SpeechType.accuse, target: goat, strength: 0.75)];
    }
    final double defendChance = skill == MafiaSkill.easy ? 0.7 : (skill == MafiaSkill.normal ? 0.35 : 0.15);
    for (final int m in others.where((int t) => knownMafia.contains(t))) {
      if ((accusedBy[m]?.length ?? 0) > 0 && _rng.nextDouble() < defendChance && _fresh('def$m')) {
        return <SpeechAct>[SpeechAct(speaker: selfId, type: SpeechType.defend, target: m)];
      }
    }
    final int? danger = _argmax(town, (int t) => (threat[t] ?? 0) + _noise() * 0.2);
    if (danger != null && (threat[danger] ?? 0) > 0.5 && _rng.nextDouble() < 0.5 && _fresh('acc$danger')) {
      return <SpeechAct>[SpeechAct(speaker: selfId, type: SpeechType.accuse, target: danger, strength: 0.5)];
    }
    if (_fresh('vague')) return <SpeechAct>[SpeechAct(speaker: selfId, type: SpeechType.vague)];
    return <SpeechAct>[];
  }

  /// Speech when put on trial.
  List<SpeechAct> defenseSpeech(MafiaEngine e) {
    switch (role) {
      case MafiaRole.detective:
        revealedRole = true;
        return <SpeechAct>[
          SpeechAct(speaker: selfId, type: SpeechType.claimRole, role: MafiaRole.detective),
          ..._detectiveReports(e, 2),
        ];
      case MafiaRole.doctor:
        if (skill == MafiaSkill.easy && _rng.nextDouble() < 0.5) {
          return <SpeechAct>[SpeechAct(speaker: selfId, type: SpeechType.plea)];
        }
        revealedRole = true;
        return <SpeechAct>[SpeechAct(speaker: selfId, type: SpeechType.claimRole, role: MafiaRole.doctor)];
      case MafiaRole.sniper:
        if (_rng.nextDouble() < 0.6) {
          return <SpeechAct>[SpeechAct(speaker: selfId, type: SpeechType.claimRole, role: MafiaRole.sniper)];
        }
        return <SpeechAct>[SpeechAct(speaker: selfId, type: SpeechType.plea)];
      case MafiaRole.citizen:
        return <SpeechAct>[
          SpeechAct(speaker: selfId, type: SpeechType.claimRole, role: MafiaRole.citizen),
          SpeechAct(speaker: selfId, type: SpeechType.plea),
        ];
      case MafiaRole.godfather:
      case MafiaRole.mafia:
        final bool doctorClaimed = claims.values.contains(MafiaRole.doctor);
        if (skill == MafiaSkill.hard && !doctorClaimed && _rng.nextDouble() < 0.4) {
          return <SpeechAct>[SpeechAct(speaker: selfId, type: SpeechType.claimRole, role: MafiaRole.doctor)];
        }
        if (_rng.nextDouble() < 0.5) {
          return <SpeechAct>[
            SpeechAct(speaker: selfId, type: SpeechType.claimRole, role: MafiaRole.citizen),
            SpeechAct(speaker: selfId, type: SpeechType.plea),
          ];
        }
        return <SpeechAct>[SpeechAct(speaker: selfId, type: SpeechType.selfDefense)];
    }
  }
}

/// Cosmic crew identities for bots.
class BotPersona {
  const BotPersona(this.nameFa, this.nameEn, this.personality, this.emblem, this.hue);
  final String nameFa;
  final String nameEn;
  final BotPersonality personality;

  /// Disc asset id (AppAssets.disc) used as the avatar emblem.
  final String emblem;

  /// Avatar glow hue in degrees.
  final double hue;
}

const List<BotPersona> kBotPersonas = <BotPersona>[
  BotPersona('نوا', 'Nova', BotPersonality.hothead, 'emblem_fireball', 12),
  BotPersona('اوریون', 'Orion', BotPersonality.analyst, 'striker_compass', 205),
  BotPersona('وگا', 'Vega', BotPersonality.cautious, 'striker_galaxy', 265),
  BotPersona('لیرا', 'Lyra', BotPersonality.joker, 'disc_cream_star', 320),
  BotPersona('سیریوس', 'Sirius', BotPersonality.schemer, 'striker_wolf', 180),
  BotPersona('نیکس', 'Nyx', BotPersonality.schemer, 'disc_black_star_gold', 285),
  BotPersona('اطلس', 'Atlas', BotPersonality.analyst, 'emblem_eagle_shield', 40),
  BotPersona('ریگل', 'Rigel', BotPersonality.hothead, 'striker_dragon', 0),
  BotPersona('الکترا', 'Electra', BotPersonality.joker, 'striker_eagle', 160),
  BotPersona('کپلر', 'Kepler', BotPersonality.cautious, 'emblem_lion_king', 95),
  BotPersona('آلتائیر', 'Altair', BotPersonality.analyst, 'striker_lion', 230),
];
