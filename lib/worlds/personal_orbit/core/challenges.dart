/// PERSONAL ORBIT — daily / weekly challenges (pure Dart, no Flutter imports).
///
/// Progress is REAL: it is computed from the profile's counters and activity
/// timeline. For counter based challenges a baseline is snapshotted the first
/// time the period is seen (persisted by ChallengeStore), so only progress made
/// inside the current period counts. Activity based challenges (matches played /
/// won) are counted directly from timestamped activity entries, which is exact.
///
/// Online later: the same definitions move to the server (`challenges` table)
/// and the server becomes the source of truth (STEP_13).
library;

enum ChallengePeriod { daily, weekly }

enum ChallengeSource { counter, activity }

class ChallengeDef {
  const ChallengeDef({
    required this.id,
    required this.period,
    required this.source,
    required this.key,
    required this.target,
    required this.xp,
    required this.coins,
    required this.titleFa,
    required this.titleEn,
    this.route,
  });

  final String id;
  final ChallengePeriod period;
  final ChallengeSource source;

  /// Counter key (source == counter) or activity kind pattern with `*`
  /// wildcards (source == activity), e.g. `game.*` or `game.*.win`.
  final String key;
  final int target;
  final int xp;
  final int coins;
  final String titleFa;
  final String titleEn;

  /// Where the user can go to make progress (go_router location).
  final String? route;
}

/// A timestamped activity used for activity based challenges.
class ChallengeEvent {
  const ChallengeEvent(this.at, this.kind);
  final DateTime at;
  final String kind;
}

const List<ChallengeDef> kDailyChallenges = <ChallengeDef>[
  ChallengeDef(
      id: 'd_play3',
      period: ChallengePeriod.daily,
      source: ChallengeSource.activity,
      key: 'game.*',
      target: 3,
      xp: 40,
      coins: 30,
      titleFa: 'امروز ۳ مسابقه بازی کن',
      titleEn: 'Play 3 matches today',
      route: '/world/nexora_arcade'),
  ChallengeDef(
      id: 'd_win1',
      period: ChallengePeriod.daily,
      source: ChallengeSource.activity,
      key: 'game.*.win',
      target: 1,
      xp: 40,
      coins: 35,
      titleFa: 'امروز یک بازی را ببر',
      titleEn: 'Win 1 game today',
      route: '/world/nexora_arcade'),
  ChallengeDef(
      id: 'd_post1',
      period: ChallengePeriod.daily,
      source: ChallengeSource.counter,
      key: 'nova.posts',
      target: 1,
      xp: 30,
      coins: 20,
      titleFa: 'یک پست در Nova Gallery منتشر کن',
      titleEn: 'Publish one post in Nova Gallery',
      route: '/world/nova_gallery'),
  ChallengeDef(
      id: 'd_oracle2',
      period: ChallengePeriod.daily,
      source: ChallengeSource.counter,
      key: 'oracle.asked',
      target: 2,
      xp: 20,
      coins: 15,
      titleFa: 'دو سؤال از ORACLE بپرس',
      titleEn: 'Ask ORACLE two questions',
      route: '/world/oracle_core'),
];

const List<ChallengeDef> kWeeklyChallenges = <ChallengeDef>[
  ChallengeDef(
      id: 'w_play15',
      period: ChallengePeriod.weekly,
      source: ChallengeSource.activity,
      key: 'game.*',
      target: 15,
      xp: 150,
      coins: 120,
      titleFa: 'این هفته ۱۵ مسابقه بازی کن',
      titleEn: 'Play 15 matches this week',
      route: '/world/nexora_arcade'),
  ChallengeDef(
      id: 'w_win5',
      period: ChallengePeriod.weekly,
      source: ChallengeSource.activity,
      key: 'game.*.win',
      target: 5,
      xp: 160,
      coins: 140,
      titleFa: 'این هفته ۵ برد بگیر',
      titleEn: 'Win 5 matches this week',
      route: '/world/nexora_arcade'),
  ChallengeDef(
      id: 'w_msg10',
      period: ChallengePeriod.weekly,
      source: ChallengeSource.counter,
      key: 'orbit.sent',
      target: 10,
      xp: 90,
      coins: 70,
      titleFa: '۱۰ پیام در Orbit Network بفرست',
      titleEn: 'Send 10 messages in Orbit Network',
      route: '/world/orbit_network'),
  ChallengeDef(
      id: 'w_shop1',
      period: ChallengePeriod.weekly,
      source: ChallengeSource.counter,
      key: 'shop.bought',
      target: 1,
      xp: 60,
      coins: 0,
      titleFa: 'یک آیتم از Exchange بخر',
      titleEn: 'Buy one item from the Exchange',
      route: '/world/nexora_exchange'),
];

List<ChallengeDef> challengesFor(ChallengePeriod p) =>
    p == ChallengePeriod.daily ? kDailyChallenges : kWeeklyChallenges;

String _two(int v) => v < 10 ? '0$v' : '$v';

String dayKey(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

/// Start of the current period in local time. Weeks start on Saturday
/// (the Iranian calendar week), the default audience of NEXORA.
DateTime periodStart(ChallengePeriod p, DateTime now) {
  if (p == ChallengePeriod.daily) return DateTime(now.year, now.month, now.day);
  // DateTime.weekday: Monday = 1 ... Saturday = 6, Sunday = 7.
  final int sinceSaturday = (now.weekday + 1) % 7;
  return DateTime(now.year, now.month, now.day - sinceSaturday);
}

String periodKey(ChallengePeriod p, DateTime now) =>
    '${p == ChallengePeriod.daily ? 'd' : 'w'}:${dayKey(periodStart(p, now))}';

/// Glob-like matcher: `*` matches any run of characters.
bool matchesKind(String pattern, String kind) {
  if (!pattern.contains('*')) return pattern == kind;
  final List<String> parts = pattern.split('*');
  if (!kind.startsWith(parts.first)) return false;
  if (!kind.endsWith(parts.last)) return false;
  int index = parts.first.length;
  final int endLimit = kind.length - parts.last.length;
  if (endLimit < index) return false;
  for (int i = 1; i < parts.length - 1; i++) {
    final String part = parts[i];
    if (part.isEmpty) continue;
    final int found = kind.indexOf(part, index);
    if (found < 0 || found + part.length > endLimit) return false;
    index = found + part.length;
  }
  return true;
}

/// State of one period (daily or weekly).
class ChallengeState {
  ChallengeState({required this.key, Map<String, int>? baseline, Set<String>? claimed})
      : baseline = baseline ?? <String, int>{},
        claimed = claimed ?? <String>{};

  final String key;
  final Map<String, int> baseline;
  final Set<String> claimed;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'key': key,
        'base': baseline,
        'claimed': claimed.toList(),
      };

  static ChallengeState fromJson(Map<String, dynamic> j) {
    final Map<String, int> base = <String, int>{};
    final Object? rawBase = j['base'];
    if (rawBase is Map) {
      rawBase.forEach((Object? k, Object? v) {
        if (v is num) base['$k'] = v.toInt();
      });
    }
    final Set<String> claimed = <String>{};
    final Object? rawClaimed = j['claimed'];
    if (rawClaimed is List) {
      for (final Object? c in rawClaimed) {
        claimed.add('$c');
      }
    }
    return ChallengeState(key: '${j['key'] ?? ''}', baseline: base, claimed: claimed);
  }
}

/// Holds daily + weekly state and computes progress.
class ChallengeBook {
  ChallengeBook({ChallengeState? daily, ChallengeState? weekly})
      : _daily = daily,
        _weekly = weekly;

  ChallengeState? _daily;
  ChallengeState? _weekly;

  ChallengeState? stateFor(ChallengePeriod p) => p == ChallengePeriod.daily ? _daily : _weekly;

  void _setState(ChallengePeriod p, ChallengeState s) {
    if (p == ChallengePeriod.daily) {
      _daily = s;
    } else {
      _weekly = s;
    }
  }

  /// Makes sure both periods are current. When a period rolls over, baselines
  /// are snapshotted from the current counters. Returns true if anything changed
  /// (so the caller persists).
  bool roll(DateTime now, Map<String, int> counters) {
    bool changed = false;
    for (final ChallengePeriod p in ChallengePeriod.values) {
      final String key = periodKey(p, now);
      ChallengeState? s = stateFor(p);
      if (s == null || s.key != key) {
        s = ChallengeState(key: key);
        _setState(p, s);
        changed = true;
      }
      for (final ChallengeDef def in challengesFor(p)) {
        if (def.source != ChallengeSource.counter) continue;
        if (!s.baseline.containsKey(def.key)) {
          s.baseline[def.key] = counters[def.key] ?? 0;
          changed = true;
        }
      }
    }
    return changed;
  }

  /// Raw progress (0..target). Call [roll] first.
  int progress(ChallengeDef def, DateTime now, Map<String, int> counters, List<ChallengeEvent> events) {
    int value;
    if (def.source == ChallengeSource.counter) {
      final ChallengeState? s = stateFor(def.period);
      final int current = counters[def.key] ?? 0;
      final int base = s?.baseline[def.key] ?? current;
      value = current - base;
    } else {
      final DateTime start = periodStart(def.period, now);
      value = 0;
      for (final ChallengeEvent e in events) {
        if (e.at.isBefore(start)) continue;
        if (e.at.isAfter(now)) continue;
        if (matchesKind(def.key, e.kind)) value++;
      }
    }
    if (value < 0) value = 0;
    if (value > def.target) value = def.target;
    return value;
  }

  bool isComplete(ChallengeDef def, DateTime now, Map<String, int> counters, List<ChallengeEvent> events) =>
      progress(def, now, counters, events) >= def.target;

  bool isClaimed(ChallengeDef def) => stateFor(def.period)?.claimed.contains(def.id) ?? false;

  bool canClaim(ChallengeDef def, DateTime now, Map<String, int> counters, List<ChallengeEvent> events) {
    final ChallengeState? s = stateFor(def.period);
    if (s == null || s.key != periodKey(def.period, now)) return false;
    return !isClaimed(def) && isComplete(def, now, counters, events);
  }

  /// Marks as claimed. Returns false when not claimable (so rewards are given once).
  bool claim(ChallengeDef def, DateTime now, Map<String, int> counters, List<ChallengeEvent> events) {
    if (!canClaim(def, now, counters, events)) return false;
    stateFor(def.period)!.claimed.add(def.id);
    return true;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        if (_daily != null) 'daily': _daily!.toJson(),
        if (_weekly != null) 'weekly': _weekly!.toJson(),
      };

  static ChallengeBook fromJson(Map<String, dynamic>? j) {
    if (j == null) return ChallengeBook();
    ChallengeState? d;
    ChallengeState? w;
    final Object? rd = j['daily'];
    final Object? rw = j['weekly'];
    if (rd is Map) d = ChallengeState.fromJson(Map<String, dynamic>.from(rd));
    if (rw is Map) w = ChallengeState.fromJson(Map<String, dynamic>.from(rw));
    return ChallengeBook(daily: d, weekly: w);
  }
}
