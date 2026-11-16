/// ORACLE CORE data models (pure Dart, no Flutter imports).
library;

enum OracleActionType { navigate, setting, none }

/// Something the UI really performs when the user taps it (or automatically,
/// when the reply was an explicit command).
class OracleAction {
  const OracleAction({
    required this.type,
    this.route,
    this.labelFa = '',
    this.labelEn = '',
    this.settingKey,
    this.settingValue,
  });

  const OracleAction.navigate(String this.route, {this.labelFa = '', this.labelEn = ''})
      : type = OracleActionType.navigate,
        settingKey = null,
        settingValue = null;

  const OracleAction.setting(String this.settingKey, String this.settingValue, {this.labelFa = '', this.labelEn = ''})
      : type = OracleActionType.setting,
        route = null;

  final OracleActionType type;

  /// go_router location for [OracleActionType.navigate].
  final String? route;
  final String labelFa;
  final String labelEn;

  /// One of [OracleSettingKeys] for [OracleActionType.setting].
  final String? settingKey;
  final String? settingValue;

  Map<String, dynamic> toJson() => <String, dynamic>{
        't': type.name,
        if (route != null) 'r': route,
        'fa': labelFa,
        'en': labelEn,
        if (settingKey != null) 'k': settingKey,
        if (settingValue != null) 'v': settingValue,
      };

  static OracleAction fromJson(Map<String, dynamic> j) {
    final String t = '${j['t'] ?? 'none'}';
    OracleActionType type = OracleActionType.none;
    for (final OracleActionType v in OracleActionType.values) {
      if (v.name == t) type = v;
    }
    return OracleAction(
      type: type,
      route: j['r'] as String?,
      labelFa: '${j['fa'] ?? ''}',
      labelEn: '${j['en'] ?? ''}',
      settingKey: j['k'] as String?,
      settingValue: j['v'] as String?,
    );
  }
}

/// Setting keys an ORACLE action can change. Values are strings.
class OracleSettingKeys {
  OracleSettingKeys._();

  /// 'true' / 'false'
  static const String reducedMotion = 'reducedMotion';

  /// 'low' / 'medium' / 'high' / 'ultra' (GraphicsQuality names)
  static const String quality = 'quality';

  /// 'fa' / 'en'
  static const String language = 'language';
}

/// ORACLE answer: bilingual text + real actions + mascot pose.
class OracleReply {
  const OracleReply({
    required this.textFa,
    required this.textEn,
    this.actions = const <OracleAction>[],
    this.pose = 'idle',
    this.intent = 'unknown',
    this.autoRun = false,
    this.followUpsFa = const <String>[],
    this.followUpsEn = const <String>[],
  });

  final String textFa;
  final String textEn;
  final List<OracleAction> actions;

  /// Oracle pose: idle / calm / confused / present / happy / cheer / alert / sleep / power / spin.
  final String pose;

  /// Machine-readable intent id (for tests / analytics).
  final String intent;

  /// True when the user gave an explicit command, so the UI performs the
  /// first action right away (and confirms only after it actually ran).
  final bool autoRun;
  final List<String> followUpsFa;
  final List<String> followUpsEn;

  /// True when ORACLE honestly says it cannot do / did not understand something.
  bool get isHonestLimit => intent == 'fallback' || intent == 'offline_limit' || intent == 'cannot_send';
}

/// Game metadata the UI passes in (from the Arcade registry).
class OracleGameInfo {
  const OracleGameInfo({
    required this.id,
    required this.nameFa,
    required this.nameEn,
    this.rulesFa = '',
    this.rulesEn = '',
  });
  final String id;
  final String nameFa;
  final String nameEn;
  final String rulesFa;
  final String rulesEn;
}

class OracleGameStat {
  const OracleGameStat({this.played = 0, this.won = 0, this.lost = 0, this.draw = 0, this.best = 0});
  final int played;
  final int won;
  final int lost;
  final int draw;
  final int best;

  /// 0..100
  int get winRate => played == 0 ? 0 : ((won * 100) / played).round();
}

class OracleAchievementHint {
  const OracleAchievementHint({required this.nameFa, required this.nameEn, this.descFa = '', this.descEn = ''});
  final String nameFa;
  final String nameEn;
  final String descFa;
  final String descEn;
}

/// Snapshot of what ORACLE may know about the user (local data only).
class OracleContext {
  const OracleContext({
    this.username = '',
    this.explorerId = '',
    this.level = 1,
    this.xp = 0,
    this.xpIntoLevel = 0,
    this.xpForNextLevel = 100,
    this.rankFa = '',
    this.rankEn = '',
    this.coins = 0,
    this.achievementsUnlocked = 0,
    this.achievementsTotal = 0,
    this.lockedAchievements = const <OracleAchievementHint>[],
    this.stats = const <String, OracleGameStat>{},
    this.canClaimDaily = false,
    this.streak = 0,
    this.reducedMotion = false,
    this.quality = 'high',
    this.languageCode = 'fa',
    this.now,
  });

  final String username;
  final String explorerId;
  final int level;
  final int xp;
  final int xpIntoLevel;
  final int xpForNextLevel;
  final String rankFa;
  final String rankEn;
  final int coins;
  final int achievementsUnlocked;
  final int achievementsTotal;
  final List<OracleAchievementHint> lockedAchievements;
  final Map<String, OracleGameStat> stats;
  final bool canClaimDaily;
  final int streak;
  final bool reducedMotion;
  final String quality;
  final String languageCode;
  final DateTime? now;

  int get totalPlayed => stats.values.fold(0, (int a, OracleGameStat s) => a + s.played);
  int get totalWon => stats.values.fold(0, (int a, OracleGameStat s) => a + s.won);
}

/// Pluggable engine. Offline today; a server LLM later.
abstract class OracleEngine {
  Future<OracleReply> ask(String input, OracleContext context);
}
