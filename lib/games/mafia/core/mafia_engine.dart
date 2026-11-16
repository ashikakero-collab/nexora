import 'dart:math';

import 'mafia_models.dart';

/// Authoritative rules engine for Mafia. Pure Dart and deterministic for a
/// given Random, so the same logic can later run server-side.
///
/// Cycle: Night 1 -> Day 1 -> Night 2 -> Day 2 ...
class MafiaEngine {
  MafiaEngine._(this.players, this.config);

  /// Creates a game with shuffled roles. [names] length = player count (6..12).
  factory MafiaEngine.create({
    required List<String> names,
    required MafiaConfig config,
    required Random rng,
  }) {
    final List<MafiaRole> roles = distributeRoles(names.length, useSniper: config.useSniper);
    roles.shuffle(rng);
    final List<MafiaPlayer> ps = <MafiaPlayer>[];
    for (int i = 0; i < names.length; i++) {
      ps.add(MafiaPlayer(id: i, name: names[i], role: roles[i]));
    }
    return MafiaEngine._(ps, config);
  }

  /// Creates a game with fixed roles (tests, replays, server sync).
  factory MafiaEngine.withRoles({
    required List<String> names,
    required List<MafiaRole> roles,
    MafiaConfig config = const MafiaConfig(),
  }) {
    final List<MafiaPlayer> ps = <MafiaPlayer>[];
    for (int i = 0; i < names.length; i++) {
      ps.add(MafiaPlayer(id: i, name: names[i], role: roles[i]));
    }
    return MafiaEngine._(ps, config);
  }

  static const int minPlayers = 6;
  static const int maxPlayers = 12;

  /// Unshuffled role list for [n] players.
  static List<MafiaRole> distributeRoles(int n, {required bool useSniper}) {
    final int count = n.clamp(minPlayers, maxPlayers).toInt();
    final int mafiaCount = mafiaCountFor(count);
    final List<MafiaRole> roles = <MafiaRole>[MafiaRole.godfather];
    for (int i = 1; i < mafiaCount; i++) {
      roles.add(MafiaRole.mafia);
    }
    roles.add(MafiaRole.doctor);
    roles.add(MafiaRole.detective);
    if (useSniper && count >= 7) roles.add(MafiaRole.sniper);
    while (roles.length < count) {
      roles.add(MafiaRole.citizen);
    }
    return roles;
  }

  static int mafiaCountFor(int n) => n >= 9 ? 3 : 2;

  final List<MafiaPlayer> players;
  final MafiaConfig config;
  final List<GameLogEntry> log = <GameLogEntry>[];

  int day = 1;
  bool isNight = true;
  int? lastDoctorSave;
  bool doctorSelfSaveUsed = false;
  int sniperBullets = 1;
  MafiaTeam? winner;

  /// Detective's private results (target -> appeared mafia).
  final Map<int, bool> detectiveResults = <int, bool>{};

  // ---------------------------------------------------------------- queries
  int get playerCount => players.length;
  int get totalMafia => players.where((MafiaPlayer p) => p.isMafia).length;
  List<MafiaPlayer> get alivePlayers => players.where((MafiaPlayer p) => p.alive).toList();
  List<int> get aliveIds => alivePlayers.map((MafiaPlayer p) => p.id).toList();
  int get aliveCount => alivePlayers.length;
  int get mafiaAlive => players.where((MafiaPlayer p) => p.alive && p.isMafia).length;
  int get townAlive => players.where((MafiaPlayer p) => p.alive && !p.isMafia).length;
  bool get isOver => winner != null;

  MafiaPlayer player(int id) => players[id];

  MafiaPlayer? holderOf(MafiaRole role) {
    for (final MafiaPlayer p in players) {
      if (p.role == role) return p;
    }
    return null;
  }

  MafiaPlayer? aliveHolderOf(MafiaRole role) {
    final MafiaPlayer? p = holderOf(role);
    if (p == null || !p.alive) return null;
    return p;
  }

  List<int> mafiaIds() => players.where((MafiaPlayer p) => p.isMafia).map((MafiaPlayer p) => p.id).toList();

  /// Role confidentiality: what [viewer] is allowed to know about [target].
  MafiaRole? visibleRole(int viewer, int target) {
    final MafiaPlayer t = players[target];
    if (viewer == target) return t.role;
    if (isOver) return t.role;
    if (t.roleRevealed) return t.role;
    final MafiaPlayer v = players[viewer];
    if (v.isMafia && t.isMafia) return t.role;
    return null;
  }

  List<GameLogEntry> logFor(int viewer) => log.where((GameLogEntry e) => e.visibleFor(viewer)).toList();

  // ---------------------------------------------------------- legal targets
  List<int> legalMafiaTargets() {
    if (mafiaAlive == 0) return <int>[];
    return players.where((MafiaPlayer p) => p.alive && !p.isMafia).map((MafiaPlayer p) => p.id).toList();
  }

  List<int> legalDoctorTargets() {
    final MafiaPlayer? doc = aliveHolderOf(MafiaRole.doctor);
    if (doc == null) return <int>[];
    return players
        .where((MafiaPlayer p) =>
            p.alive && p.id != lastDoctorSave && !(p.id == doc.id && doctorSelfSaveUsed))
        .map((MafiaPlayer p) => p.id)
        .toList();
  }

  List<int> legalDetectiveTargets() {
    final MafiaPlayer? det = aliveHolderOf(MafiaRole.detective);
    if (det == null) return <int>[];
    return players.where((MafiaPlayer p) => p.alive && p.id != det.id).map((MafiaPlayer p) => p.id).toList();
  }

  List<int> legalSniperTargets() {
    final MafiaPlayer? sn = aliveHolderOf(MafiaRole.sniper);
    if (sn == null || sniperBullets <= 0) return <int>[];
    return players.where((MafiaPlayer p) => p.alive && p.id != sn.id).map((MafiaPlayer p) => p.id).toList();
  }

  List<int> legalVoteTargets(int voter) {
    if (!players[voter].alive) return <int>[];
    return players.where((MafiaPlayer p) => p.alive && p.id != voter).map((MafiaPlayer p) => p.id).toList();
  }

  bool isLegalNight(NightActions a) {
    bool ok(int? v, List<int> legal) => v == null || legal.contains(v);
    return ok(a.mafiaTarget, legalMafiaTargets()) &&
        ok(a.doctorSave, legalDoctorTargets()) &&
        ok(a.detectiveCheck, legalDetectiveTargets()) &&
        ok(a.sniperTarget, legalSniperTargets());
  }

  // ------------------------------------------------------------------ night
  /// Resolves all night actions simultaneously. Illegal choices are ignored.
  NightResult resolveNight(NightActions a) {
    final int? mt = _legalOrNull(a.mafiaTarget, legalMafiaTargets());
    final int? ds = _legalOrNull(a.doctorSave, legalDoctorTargets());
    final int? dc = _legalOrNull(a.detectiveCheck, legalDetectiveTargets());
    final int? st = _legalOrNull(a.sniperTarget, legalSniperTargets());
    final MafiaPlayer? doctor = aliveHolderOf(MafiaRole.doctor);
    final MafiaPlayer? detective = aliveHolderOf(MafiaRole.detective);
    final MafiaPlayer? sniper = aliveHolderOf(MafiaRole.sniper);

    final List<int> deaths = <int>[];
    final Map<int, DeathCause> causes = <int, DeathCause>{};
    bool saved = false;
    int? savedId;

    if (mt != null) {
      if (ds == mt) {
        saved = true;
        savedId = mt;
      } else {
        deaths.add(mt);
        causes[mt] = DeathCause.nightKill;
      }
    }
    bool fired = false;
    if (st != null && sniper != null) {
      fired = true;
      sniperBullets -= 1;
      final MafiaPlayer target = players[st];
      if (target.isMafia) {
        if (ds == st) {
          saved = true;
          savedId = st;
        } else if (!deaths.contains(st)) {
          deaths.add(st);
          causes[st] = DeathCause.sniperShot;
        }
      } else if (!deaths.contains(sniper.id)) {
        deaths.add(sniper.id);
        causes[sniper.id] = DeathCause.sniperBackfire;
      }
    }

    bool? checkedMafia;
    if (dc != null && detective != null) {
      checkedMafia = players[dc].role.appearsMafiaToDetective;
      detectiveResults[dc] = checkedMafia;
      log.add(GameLogEntry(
        day: day,
        night: true,
        kind: LogKind.check,
        fa: 'استعلام ${players[dc].name}: ${checkedMafia ? 'مافیا' : 'بی‌گناه'}',
        en: 'Investigation of ${players[dc].name}: ${checkedMafia ? 'MAFIA' : 'innocent'}',
        visibleTo: <int>{detective.id},
      ));
    }

    if (doctor != null) {
      lastDoctorSave = ds;
      if (ds != null && ds == doctor.id) doctorSelfSaveUsed = true;
      if (ds != null) {
        log.add(GameLogEntry(
          day: day,
          night: true,
          kind: LogKind.save,
          fa: 'محافظت از ${players[ds].name}${savedId == ds ? ' — حمله دفع شد!' : ''}',
          en: 'Protected ${players[ds].name}${savedId == ds ? ' — attack prevented!' : ''}',
          visibleTo: <int>{doctor.id},
        ));
      }
    }

    for (final int id in deaths) {
      _kill(id, causes[id]!);
    }
    if (deaths.isEmpty) {
      log.add(GameLogEntry(
        day: day,
        night: true,
        kind: LogKind.info,
        fa: 'شب $day بدون قربانی گذشت.',
        en: 'Night $day passed with no victim.',
      ));
    }
    if (saved && config.announceSave) {
      log.add(GameLogEntry(
        day: day,
        night: true,
        kind: LogKind.save,
        fa: 'دکتر دیشب جان یک نفر را نجات داد.',
        en: 'The Doctor saved someone last night.',
      ));
    }

    isNight = false;
    _checkWinner();
    return NightResult(
      day: day,
      deaths: deaths,
      causes: causes,
      savedSomeone: saved,
      savedId: savedId,
      checkedId: dc,
      checkedIsMafia: checkedMafia,
      sniperFired: fired,
    );
  }

  int? _legalOrNull(int? v, List<int> legal) => (v != null && legal.contains(v)) ? v : null;

  void _kill(int id, DeathCause cause) {
    final MafiaPlayer p = players[id];
    if (!p.alive) return;
    p.alive = false;
    p.cause = cause;
    p.diedOnDay = day;
    p.roleRevealed = config.revealRoleOnDeath;
    final String roleFa = p.roleRevealed ? ' (${p.role.labelFa})' : '';
    final String roleEn = p.roleRevealed ? ' (${p.role.labelEn})' : '';
    String fa = '';
    String en = '';
    switch (cause) {
      case DeathCause.nightKill:
        fa = '${p.name}$roleFa در شب کشته شد.';
        en = '${p.name}$roleEn was killed in the night.';
        break;
      case DeathCause.sniperShot:
        fa = '${p.name}$roleFa با شلیک تک‌تیرانداز از پا درآمد.';
        en = '${p.name}$roleEn was taken down by the Sniper.';
        break;
      case DeathCause.sniperBackfire:
        fa = '${p.name}$roleFa به یک بی‌گناه شلیک کرد و از بازی خارج شد.';
        en = '${p.name}$roleEn shot an innocent and left the game.';
        break;
      case DeathCause.vote:
        fa = '${p.name}$roleFa با رأی شهر حذف شد.';
        en = '${p.name}$roleEn was voted out by the town.';
        break;
    }
    log.add(GameLogEntry(day: day, night: cause != DeathCause.vote, kind: LogKind.death, fa: fa, en: en));
  }

  // -------------------------------------------------------------------- day
  /// Minimum nomination votes needed to be put on trial.
  int get nominationThreshold => aliveCount <= 4 ? 1 : 2;

  /// [votes]: voter -> target (null = skip). Invalid votes count as skips.
  /// Players tied at the top (up to 3) go to defense.
  NominationResult tallyNomination(Map<int, int?> votes) {
    final Map<int, int> tally = <int, int>{};
    int skips = 0;
    votes.forEach((int voter, int? target) {
      if (!players[voter].alive) return;
      if (target == null || target == voter || !players[target].alive) {
        skips++;
        return;
      }
      tally[target] = (tally[target] ?? 0) + 1;
    });
    int top = 0;
    tally.forEach((int _, int c) {
      if (c > top) top = c;
    });
    List<int> defendants = <int>[];
    if (top >= nominationThreshold) {
      defendants = tally.keys.where((int k) => tally[k] == top).toList()..sort();
      if (defendants.length > 3) defendants = <int>[];
    }
    log.add(GameLogEntry(
      day: day,
      night: false,
      kind: LogKind.vote,
      fa: defendants.isEmpty
          ? 'رأی‌گیری اول: کسی به دفاع نرفت.'
          : 'به دفاع رفتند: ${defendants.map((int d) => players[d].name).join('، ')}',
      en: defendants.isEmpty
          ? 'First vote: nobody was put on trial.'
          : 'On trial: ${defendants.map((int d) => players[d].name).join(', ')}',
    ));
    return NominationResult(tally: tally, defendants: defendants, skips: skips);
  }

  /// [votes]: voter -> defendant (null = spare). Defendants may not vote for
  /// themselves. A unique top defendant with more votes than spares is out.
  FinalVoteResult resolveFinalVote(Map<int, int?> votes, List<int> defendants) {
    final Map<int, int> tally = <int, int>{for (final int d in defendants) d: 0};
    int spares = 0;
    votes.forEach((int voter, int? target) {
      if (!players[voter].alive) return;
      if (target == null || target == voter || !defendants.contains(target) || !players[target].alive) {
        spares++;
        return;
      }
      tally[target] = tally[target]! + 1;
    });
    return _decideFinal(tally, spares);
  }

  /// Narrator-mode variant: raw hand counts per defendant.
  FinalVoteResult resolveFinalCounts(Map<int, int> counts, List<int> defendants) {
    final Map<int, int> tally = <int, int>{};
    int used = 0;
    for (final int d in defendants) {
      final int c = max(0, counts[d] ?? 0);
      tally[d] = c;
      used += c;
    }
    final int spares = max(0, aliveCount - used);
    return _decideFinal(tally, spares);
  }

  FinalVoteResult _decideFinal(Map<int, int> tally, int spares) {
    int top = 0;
    tally.forEach((int _, int c) {
      if (c > top) top = c;
    });
    final List<int> leaders = tally.keys.where((int k) => tally[k] == top).toList();
    int? out;
    if (top > 0 && leaders.length == 1 && top > spares) out = leaders.first;
    if (out != null) {
      _kill(out, DeathCause.vote);
      _checkWinner();
    } else {
      log.add(GameLogEntry(
        day: day,
        night: false,
        kind: LogKind.vote,
        fa: 'رأی نهایی کافی نبود؛ کسی حذف نشد.',
        en: 'The final vote fell short; nobody was eliminated.',
      ));
    }
    return FinalVoteResult(tally: tally, spares: spares, eliminated: out);
  }

  /// Ends the day and starts the next night.
  void startNight() {
    if (isOver) return;
    day += 1;
    isNight = true;
    log.add(GameLogEntry(
      day: day,
      night: true,
      kind: LogKind.phase,
      fa: 'شب $day فرا رسید.',
      en: 'Night $day falls.',
    ));
  }

  // -------------------------------------------------------------------- win
  MafiaTeam? checkWinnerNow() {
    if (mafiaAlive == 0) return MafiaTeam.town;
    if (mafiaAlive >= townAlive) return MafiaTeam.mafia;
    return null;
  }

  void _checkWinner() {
    if (winner != null) return;
    final MafiaTeam? w = checkWinnerNow();
    if (w == null) return;
    winner = w;
    log.add(GameLogEntry(
      day: day,
      night: isNight,
      kind: LogKind.phase,
      fa: w == MafiaTeam.town ? 'شهروندان پیروز شدند! همه‌ی مافیا حذف شدند.' : 'مافیا ایستگاه را تسخیر کرد!',
      en: w == MafiaTeam.town ? 'The Town wins! Every Mafia is gone.' : 'The Mafia has taken the station!',
    ));
  }

  /// Online: a player left the match. They are out of the game (role revealed) and the
  /// win condition is re-checked. Offline play never calls this.
  void leave(int id) {
    final MafiaPlayer p = players[id];
    if (!p.alive) return;
    p.alive = false;
    p.diedOnDay = day;
    p.roleRevealed = true;
    log.add(GameLogEntry(
      day: day,
      night: isNight,
      kind: LogKind.death,
      fa: '${p.name} (${p.role.labelFa}) بازی را ترک کرد.',
      en: '${p.name} (${p.role.labelEn}) left the game.',
    ));
    _checkWinner();
  }

  /// Adds a public line to the log (speech, notes).
  void addLog(LogKind kind, String fa, String en, {Set<int>? visibleTo}) {
    log.add(GameLogEntry(day: day, night: isNight, kind: kind, fa: fa, en: en, visibleTo: visibleTo));
  }
}
