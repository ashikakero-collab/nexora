/// Pure-Dart data model for NEXORA Mafia (no Flutter imports).
library;

/// Every role in the game. New roles can be added here; the engine reads the
/// team / detective-appearance from the extension below.
enum MafiaRole { godfather, mafia, doctor, detective, sniper, citizen }

enum MafiaTeam { town, mafia }

/// Bot reasoning quality (mapped from the host BotDifficulty in the UI layer).
enum MafiaSkill { easy, normal, hard }

/// Why a player left the game.
enum DeathCause { nightKill, sniperShot, sniperBackfire, vote }

extension MafiaRoleX on MafiaRole {
  MafiaTeam get team {
    if (this == MafiaRole.godfather || this == MafiaRole.mafia) {
      return MafiaTeam.mafia;
    }
    return MafiaTeam.town;
  }

  bool get isMafia => team == MafiaTeam.mafia;

  /// The Godfather appears innocent to the Detective.
  bool get appearsMafiaToDetective => this == MafiaRole.mafia;

  String get labelFa {
    switch (this) {
      case MafiaRole.godfather:
        return 'پدرخوانده';
      case MafiaRole.mafia:
        return 'مافیا';
      case MafiaRole.doctor:
        return 'دکتر';
      case MafiaRole.detective:
        return 'کارآگاه';
      case MafiaRole.sniper:
        return 'تک‌تیرانداز';
      case MafiaRole.citizen:
        return 'شهروند';
    }
  }

  String get labelEn {
    switch (this) {
      case MafiaRole.godfather:
        return 'Godfather';
      case MafiaRole.mafia:
        return 'Mafia';
      case MafiaRole.doctor:
        return 'Doctor';
      case MafiaRole.detective:
        return 'Detective';
      case MafiaRole.sniper:
        return 'Sniper';
      case MafiaRole.citizen:
        return 'Citizen';
    }
  }

  String get descFa {
    switch (this) {
      case MafiaRole.godfather:
        return 'رهبر مافیا. هر شب قربانی را انتخاب می‌کنی و استعلام کارآگاه درباره‌ی تو «بی‌گناه» برمی‌گردد.';
      case MafiaRole.mafia:
        return 'عضو مافیا. هم‌تیمی‌هایت را می‌شناسی؛ شب‌ها با هم یک نفر را حذف می‌کنید و روزها شهر را گمراه می‌کنید.';
      case MafiaRole.doctor:
        return 'هر شب یک نفر را نجات بده. خودت را فقط یک بار، و یک نفر را دو شب پشت سر هم نمی‌توانی.';
      case MafiaRole.detective:
        return 'هر شب هویت یک نفر را استعلام کن. پدرخوانده را بی‌گناه نشان می‌دهد؛ زمان افشای نتایج با توست.';
      case MafiaRole.sniper:
        return 'یک گلوله داری. اگر به مافیا شلیک کنی حذف می‌شود؛ اگر به شهروند بزنی خودت از بازی خارج می‌شوی.';
      case MafiaRole.citizen:
        return 'سلاحت ذهن توست. صحبت‌ها و رأی‌ها را دنبال کن و مافیا را پیدا کن.';
    }
  }

  String get descEn {
    switch (this) {
      case MafiaRole.godfather:
        return 'Leader of the Mafia. You choose the victim each night, and the Detective sees you as innocent.';
      case MafiaRole.mafia:
        return 'Mafia member. You know your partners; at night you eliminate someone, by day you mislead the town.';
      case MafiaRole.doctor:
        return 'Save one player each night. Yourself only once, and never the same player two nights in a row.';
      case MafiaRole.detective:
        return 'Investigate one player each night. The Godfather reads innocent; when to reveal is your call.';
      case MafiaRole.sniper:
        return 'One bullet. Hit a Mafia and they fall; hit a citizen and you are out instead.';
      case MafiaRole.citizen:
        return 'Your weapon is your mind. Follow the talk and the votes, and find the Mafia.';
    }
  }
}

String teamLabel(MafiaTeam t, bool fa) {
  if (t == MafiaTeam.mafia) return fa ? 'مافیا' : 'Mafia';
  return fa ? 'شهروندان' : 'Town';
}

class MafiaConfig {
  const MafiaConfig({
    this.useSniper = true,
    this.revealRoleOnDeath = true,
    this.announceSave = true,
  });

  /// Adds the Sniper/Professional role when there are at least 7 players.
  final bool useSniper;

  /// Reveal the role of eliminated players to everyone.
  final bool revealRoleOnDeath;

  /// Announce at dawn that the Doctor saved someone (without naming them).
  final bool announceSave;
}

class MafiaPlayer {
  MafiaPlayer({required this.id, required this.name, required this.role});

  final int id;
  final String name;
  final MafiaRole role;
  bool alive = true;
  bool roleRevealed = false;
  int? diedOnDay;
  DeathCause? cause;

  bool get isMafia => role.isMafia;
}

/// The choices of one night. Null means "no action".
class NightActions {
  const NightActions({this.mafiaTarget, this.doctorSave, this.detectiveCheck, this.sniperTarget});

  final int? mafiaTarget;
  final int? doctorSave;
  final int? detectiveCheck;
  final int? sniperTarget;
}

class NightResult {
  NightResult({
    required this.day,
    required this.deaths,
    required this.causes,
    required this.savedSomeone,
    this.savedId,
    this.checkedId,
    this.checkedIsMafia,
    this.sniperFired = false,
  });

  final int day;
  final List<int> deaths;
  final Map<int, DeathCause> causes;
  final bool savedSomeone;

  /// Private: only the Doctor learns who it was.
  final int? savedId;

  /// Private: only the Detective learns this.
  final int? checkedId;
  final bool? checkedIsMafia;
  final bool sniperFired;
}

class NominationResult {
  NominationResult({required this.tally, required this.defendants, required this.skips});

  final Map<int, int> tally;
  final List<int> defendants;
  final int skips;
}

class FinalVoteResult {
  FinalVoteResult({required this.tally, required this.spares, required this.eliminated});

  final Map<int, int> tally;
  final int spares;
  final int? eliminated;
}

enum LogKind { info, death, save, vote, speech, check, phase }

class GameLogEntry {
  GameLogEntry({
    required this.day,
    required this.night,
    required this.kind,
    required this.fa,
    required this.en,
    this.visibleTo,
  });

  final int day;
  final bool night;
  final LogKind kind;
  final String fa;
  final String en;

  /// null = public; otherwise only these player ids may see it.
  final Set<int>? visibleTo;

  bool visibleFor(int viewer) => visibleTo == null || visibleTo!.contains(viewer);
}
