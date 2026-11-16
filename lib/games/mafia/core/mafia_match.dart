import 'dart:math';

import 'mafia_bot.dart';
import 'mafia_engine.dart';
import 'mafia_lines.dart';
import 'mafia_models.dart';

class SpeechLine {
  SpeechLine({required this.speaker, required this.fa, required this.en, required this.act, required this.day});
  final int speaker;
  final String fa;
  final String en;
  final SpeechAct act;
  final int day;
}

/// vsBot orchestration: one human (seat 0) plus AI citizens. Pure Dart; the
/// UI drives it step by step and animates the results.
class MafiaMatch {
  MafiaMatch._({
    required this.engine,
    required this.brains,
    required this.personas,
    required this.isFa,
    required this.skill,
    required this.humanIsBot,
    required Random rng,
  }) : _rng = rng;

  static const int humanId = 0;

  /// [totalPlayers] is clamped to 6..10 (values below 6 default to 8).
  factory MafiaMatch.create({
    required String humanName,
    required bool isFa,
    required int totalPlayers,
    required MafiaSkill skill,
    required int seed,
    MafiaConfig config = const MafiaConfig(),
    bool humanIsBot = false,
  }) {
    final int n = totalPlayers < 6 ? 8 : totalPlayers.clamp(6, 10).toInt();
    final Random rng = Random(seed);
    final List<BotPersona> pool = List<BotPersona>.from(kBotPersonas)..shuffle(rng);
    final Map<int, BotPersona> personas = <int, BotPersona>{};
    final List<String> names = <String>[humanName.trim().isEmpty ? (isFa ? 'تو' : 'You') : humanName.trim()];
    for (int i = 1; i < n; i++) {
      final BotPersona p = pool[(i - 1) % pool.length];
      personas[i] = p;
      names.add(isFa ? p.nameFa : p.nameEn);
    }
    final MafiaEngine engine = MafiaEngine.create(names: names, config: config, rng: Random(seed * 7 + 13));
    final Map<int, BotBrain> brains = <int, BotBrain>{};
    final Set<int> mafia = engine.mafiaIds().toSet();
    for (int i = humanIsBot ? 0 : 1; i < n; i++) {
      final MafiaRole role = engine.player(i).role;
      brains[i] = BotBrain(
        selfId: i,
        role: role,
        skill: skill,
        personality: personas[i]?.personality ?? BotPersonality.analyst,
        playerCount: n,
        totalMafia: engine.totalMafia,
        teammates: role.isMafia ? mafia : <int>{},
        seed: seed * 31 + i * 101,
      );
    }
    return MafiaMatch._(
      engine: engine,
      brains: brains,
      personas: personas,
      isFa: isFa,
      skill: skill,
      humanIsBot: humanIsBot,
      rng: rng,
    );
  }

  final MafiaEngine engine;
  final Map<int, BotBrain> brains;
  final Map<int, BotPersona> personas;
  final bool isFa;
  final MafiaSkill skill;
  final bool humanIsBot;
  final Random _rng;

  final List<SpeechLine> chat = <SpeechLine>[];
  final List<String> illegalActions = <String>[];
  bool counterClaimUsed = false;
  int round = 0;
  NightResult? lastNight;
  NominationResult? lastNomination;
  FinalVoteResult? lastFinal;

  // ---------------------------------------------------------------- helpers
  MafiaPlayer get human => engine.player(humanId);
  MafiaRole get humanRole => human.role;
  bool get humanAlive => human.alive;
  bool get isOver => engine.isOver;
  bool get humanWon => engine.winner != null && engine.winner == humanRole.team;
  String nameOf(int id) => engine.player(id).name;
  bool _controlsHuman(int id) => id == humanId && !humanIsBot;

  List<int> humanTeammates() {
    if (!humanRole.isMafia) return <int>[];
    return engine.mafiaIds().where((int i) => i != humanId).toList();
  }

  /// Night targets for the human's role (empty = nothing to do tonight).
  List<int> humanNightOptions() {
    if (!humanAlive) return <int>[];
    switch (humanRole) {
      case MafiaRole.godfather:
      case MafiaRole.mafia:
        return engine.legalMafiaTargets();
      case MafiaRole.doctor:
        return engine.legalDoctorTargets();
      case MafiaRole.detective:
        return engine.legalDetectiveTargets();
      case MafiaRole.sniper:
        return engine.legalSniperTargets();
      case MafiaRole.citizen:
        return <int>[];
    }
  }

  List<BotBrain> _aliveMafiaBrains() => brains.values
      .where((BotBrain b) => b.isMafia && engine.player(b.selfId).alive)
      .toList();

  /// What the bot partners would kill tonight (shown to a Mafia human).
  int? mafiaSuggestion() => BotBrain.teamKill(_aliveMafiaBrains(), engine);

  BotBrain? _brainFor(MafiaRole role) {
    final MafiaPlayer? p = engine.aliveHolderOf(role);
    if (p == null) return null;
    return brains[p.id];
  }

  // ------------------------------------------------------------------ night
  NightResult playNight({int? humanChoice}) {
    int? mt;
    int? ds;
    int? dc;
    int? st;
    final bool humanActs = humanAlive && !humanIsBot;
    if (humanActs && humanRole.isMafia) {
      mt = humanChoice ?? mafiaSuggestion();
    } else {
      mt = BotBrain.teamKill(_aliveMafiaBrains(), engine);
    }
    if (humanActs && humanRole == MafiaRole.doctor) {
      ds = humanChoice;
    } else {
      ds = _brainFor(MafiaRole.doctor)?.doctorChoice(engine);
    }
    if (humanActs && humanRole == MafiaRole.detective) {
      dc = humanChoice;
    } else {
      dc = _brainFor(MafiaRole.detective)?.detectiveChoice(engine);
    }
    if (humanActs && humanRole == MafiaRole.sniper) {
      st = humanChoice;
    } else {
      st = _brainFor(MafiaRole.sniper)?.sniperChoice(engine);
    }
    final NightActions actions = NightActions(mafiaTarget: mt, doctorSave: ds, detectiveCheck: dc, sniperTarget: st);
    if (!engine.isLegalNight(actions)) {
      illegalActions.add('night ${engine.day}: m=$mt d=$ds det=$dc s=$st');
    }
    final NightResult r = engine.resolveNight(actions);

    final MafiaPlayer? det = engine.holderOf(MafiaRole.detective);
    if (det != null && r.checkedId != null && r.checkedIsMafia != null) {
      brains[det.id]?.observeOwnCheck(r.checkedId!, r.checkedIsMafia!);
    }
    final MafiaPlayer? doc = engine.holderOf(MafiaRole.doctor);
    if (doc != null && r.savedId != null && r.savedId == mt) {
      brains[doc.id]?.observeSave(r.savedId!);
    }
    for (final int d in r.deaths) {
      _broadcastDeath(d, r.causes[d]!, byVote: false);
    }
    for (final BotBrain b in brains.values) {
      b.newDay();
    }
    round = 0;
    lastNight = r;
    lastNomination = null;
    lastFinal = null;
    return r;
  }

  void _broadcastDeath(int id, DeathCause cause, {required bool byVote}) {
    final MafiaPlayer p = engine.player(id);
    final MafiaRole? revealed = p.roleRevealed ? p.role : null;
    for (final BotBrain b in brains.values) {
      b.observeDeath(id, cause, revealed, byVote: byVote);
    }
  }

  // ------------------------------------------------------------- discussion
  /// One round of bot talk (several lines). Returns the new lines in order.
  List<SpeechLine> discussionRound({int maxLines = 5}) {
    round += 1;
    final List<int> order = engine.aliveIds.where((int i) => brains.containsKey(i)).toList()..shuffle(_rng);
    final List<SpeechLine> out = <SpeechLine>[];
    for (final int id in order) {
      if (out.length >= maxLines) break;
      final List<SpeechAct> acts = brains[id]!.speak(
        engine,
        counterClaimFree: !counterClaimUsed,
        onCounterClaim: () {
          counterClaimUsed = true;
        },
        round: round,
      );
      for (final SpeechAct a in acts) {
        out.add(say(a));
      }
    }
    return out;
  }

  /// Publishes a speech act (bot or human) to the chat, log and every brain.
  SpeechLine say(SpeechAct act) {
    final BotPersonality pers = personas[act.speaker]?.personality ?? BotPersonality.analyst;
    final LinePair lp = MafiaLines.render(
      act,
      nameOf: nameOf,
      personality: pers,
      rng: _rng,
      withFlavor: act.speaker != humanId,
    );
    final SpeechLine line = SpeechLine(speaker: act.speaker, fa: lp.fa, en: lp.en, act: act, day: engine.day);
    chat.add(line);
    engine.addLog(LogKind.speech, '${nameOf(act.speaker)}: ${lp.fa}', '${nameOf(act.speaker)}: ${lp.en}');
    for (final BotBrain b in brains.values) {
      if (engine.player(b.selfId).alive) b.observeSpeech(act);
    }
    return line;
  }

  // ------------------------------------------------------------------ votes
  Map<int, int?> collectNominationVotes({int? humanVote}) {
    final Map<int, int?> votes = <int, int?>{};
    for (final int id in engine.aliveIds) {
      int? v;
      if (_controlsHuman(id)) {
        v = humanVote;
      } else {
        v = brains[id]?.nominationVote(engine);
      }
      if (v != null && !engine.legalVoteTargets(id).contains(v)) {
        illegalActions.add('nomination ${engine.day}: $id->$v');
        v = null;
      }
      votes[id] = v;
    }
    return votes;
  }

  NominationResult nominate(Map<int, int?> votes) {
    final NominationResult r = engine.tallyNomination(votes);
    for (final BotBrain b in brains.values) {
      b.observeNomination(votes);
    }
    lastNomination = r;
    return r;
  }

  List<SpeechLine> defenseSpeeches(List<int> defendants) {
    final List<SpeechLine> out = <SpeechLine>[];
    for (final int d in defendants) {
      if (_controlsHuman(d)) continue;
      final BotBrain? b = brains[d];
      if (b == null || !engine.player(d).alive) continue;
      for (final SpeechAct a in b.defenseSpeech(engine)) {
        out.add(say(a));
      }
    }
    return out;
  }

  Map<int, int?> collectFinalVotes(List<int> defendants, {int? humanVote}) {
    final Map<int, int?> votes = <int, int?>{};
    for (final int id in engine.aliveIds) {
      int? v;
      if (_controlsHuman(id)) {
        v = humanVote;
      } else {
        v = brains[id]?.finalVote(engine, defendants);
      }
      if (v != null && (v == id || !defendants.contains(v))) {
        illegalActions.add('final ${engine.day}: $id->$v');
        v = null;
      }
      votes[id] = v;
    }
    return votes;
  }

  FinalVoteResult finalVote(Map<int, int?> votes, List<int> defendants) {
    for (final BotBrain b in brains.values) {
      b.observeFinal(votes, defendants);
    }
    final FinalVoteResult r = engine.resolveFinalVote(votes, defendants);
    if (r.eliminated != null) _broadcastDeath(r.eliminated!, DeathCause.vote, byVote: true);
    lastFinal = r;
    return r;
  }

  /// Parting words of an eliminated bot (rendered, not broadcast as evidence).
  SpeechLine? lastWords(int id) {
    if (!brains.containsKey(id) || _controlsHuman(id)) return null;
    final SpeechAct act = SpeechAct(speaker: id, type: SpeechType.lastWords);
    final LinePair lp = MafiaLines.render(
      act,
      nameOf: nameOf,
      personality: personas[id]?.personality ?? BotPersonality.analyst,
      rng: _rng,
      withFlavor: false,
    );
    final SpeechLine line = SpeechLine(speaker: id, fa: lp.fa, en: lp.en, act: act, day: engine.day);
    chat.add(line);
    return line;
  }

  void startNight() => engine.startNight();

  // --------------------------------------------------------------- autoplay
  /// Plays one full day with bots only (the human is dead or a bot).
  void autoDay() {
    if (isOver || engine.isNight) return;
    discussionRound();
    discussionRound();
    final NominationResult n = nominate(collectNominationVotes());
    if (n.defendants.isNotEmpty) {
      defenseSpeeches(n.defendants);
      finalVote(collectFinalVotes(n.defendants), n.defendants);
    }
  }

  /// Fast-forwards to the end of the game (used when the human is out).
  void autoPlayToEnd({int maxCycles = 60}) {
    int cycles = 0;
    while (!isOver && cycles < maxCycles) {
      cycles++;
      if (engine.isNight) {
        playNight();
      } else {
        autoDay();
        if (!isOver) startNight();
      }
    }
    if (!isOver) {
      engine.winner = engine.checkWinnerNow() ??
          (engine.mafiaAlive * 2 >= engine.aliveCount ? MafiaTeam.mafia : MafiaTeam.town);
    }
  }
}
