// Port of src/store.tsx: the local (offline) profile, persisted with SharedPreferences under the same key/shape.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../game/data.dart';

class Profile {
  String name = 'Pilot';
  int coins = 600, gems = 20, xp = 0, trophies = 0;
  int played = 0, wins = 0, losses = 0, draws = 0, goalsFor = 0, goalsAgainst = 0;
  String team = 'club0';
  int ball = 0, field = kDefaultField, form = 0;
  List<String> ownedTeams = [];
  List<int> ownedBalls = [];
  List<int> ownedFields = [];
  int lastDaily = 0, streak = 0;
  bool sound = true, music = true, haptics = true;
  int aiLvl = 1, limit = 3, turnTime = 15;
  int cupsWon = 0, winStreak = 0, bestStreak = 0, chests = 1, lastChest = 0;
  List<String> claimedAch = [];
  String quality = 'high';
  double volume = 1;
  bool oracle = true, oracleTour = false;
  int fieldsV = kFieldsVersion;
  // Flutter additions (additive keys; ignored by the RN build)
  bool debugOverlay = false;
  String lang = 'fa';
  // v4 additions
  int goal = 0; // goal skin index (kGoalSkins)
  List<int> ownedGoals = [0];
  bool tutorialDone = false;

  Profile();

  static List<String> get freeTeams => [for (final t in kTeams) if (teamPrice(t) == 0) t.id];
  static List<int> get freeFields => [for (var i = 0; i < kFields.length; i++) if (fieldPrice(i) == 0) i];

  factory Profile.defaults() {
    final p = Profile();
    p.ownedTeams = freeTeams;
    p.ownedBalls = [for (var i = 0; i < 36; i++) if (ballPrice(i) == 0) i];
    p.ownedFields = [...freeFields, 7];
    return p;
  }

  Map<String, dynamic> toJson() => {
        'name': name, 'coins': coins, 'gems': gems, 'xp': xp, 'trophies': trophies,
        'played': played, 'wins': wins, 'losses': losses, 'draws': draws, 'goalsFor': goalsFor, 'goalsAgainst': goalsAgainst,
        'team': team, 'ball': ball, 'field': field, 'form': form,
        'ownedTeams': ownedTeams, 'ownedBalls': ownedBalls, 'ownedFields': ownedFields,
        'lastDaily': lastDaily, 'streak': streak, 'sound': sound, 'music': music, 'haptics': haptics,
        'aiLvl': aiLvl, 'limit': limit, 'turnTime': turnTime, 'cupsWon': cupsWon, 'winStreak': winStreak, 'bestStreak': bestStreak,
        'chests': chests, 'lastChest': lastChest, 'claimedAch': claimedAch, 'quality': quality, 'volume': volume,
        'oracle': oracle, 'oracleTour': oracleTour, 'fieldsV': fieldsV, 'debugOverlay': debugOverlay, 'lang': lang,
        'goal': goal, 'ownedGoals': ownedGoals, 'tutorialV4': tutorialDone,
      };

  static Profile fromJson(Map<String, dynamic> j) {
    final p = Profile.defaults();
    int i(String k, int d) => (j[k] is num) ? (j[k] as num).toInt() : d;
    bool b(String k, bool d) => j[k] is bool ? j[k] as bool : d;
    p.name = j['name'] is String ? j['name'] : p.name;
    p.coins = i('coins', p.coins);
    p.gems = i('gems', p.gems);
    p.xp = i('xp', 0);
    p.trophies = i('trophies', 0);
    p.played = i('played', 0);
    p.wins = i('wins', 0);
    p.losses = i('losses', 0);
    p.draws = i('draws', 0);
    p.goalsFor = i('goalsFor', 0);
    p.goalsAgainst = i('goalsAgainst', 0);
    p.team = j['team'] is String ? j['team'] : 'club0';
    p.ball = i('ball', 0);
    p.field = i('field', kDefaultField);
    p.form = i('form', 0);
    if (j['ownedTeams'] is List) p.ownedTeams = (j['ownedTeams'] as List).whereType<String>().toList();
    if (j['ownedBalls'] is List) p.ownedBalls = (j['ownedBalls'] as List).whereType<num>().map((e) => e.toInt()).toList();
    if (j['ownedFields'] is List) p.ownedFields = (j['ownedFields'] as List).whereType<num>().map((e) => e.toInt()).toList();
    p.lastDaily = i('lastDaily', 0);
    p.streak = i('streak', 0);
    p.sound = b('sound', true);
    p.music = b('music', true);
    p.haptics = b('haptics', true);
    p.aiLvl = i('aiLvl', 1).clamp(0, 2);
    p.limit = i('limit', 3);
    p.turnTime = i('turnTime', 15);
    p.cupsWon = i('cupsWon', 0);
    p.winStreak = i('winStreak', 0);
    p.bestStreak = i('bestStreak', 0);
    p.chests = i('chests', 1);
    p.lastChest = i('lastChest', 0);
    if (j['claimedAch'] is List) p.claimedAch = (j['claimedAch'] as List).whereType<String>().toList();
    p.quality = j['quality'] == 'low' ? 'low' : 'high';
    p.volume = j['volume'] is num ? (j['volume'] as num).toDouble().clamp(0, 1) : 1;
    p.oracle = b('oracle', true);
    p.oracleTour = b('oracleTour', false);
    p.fieldsV = i('fieldsV', 1);
    p.debugOverlay = b('debugOverlay', false);
    p.lang = j['lang'] == 'en' ? 'en' : 'fa';
    p.goal = i('goal', 0);
    if (j['ownedGoals'] is List) p.ownedGoals = (j['ownedGoals'] as List).whereType<num>().map((e) => e.toInt()).toList();
    p.tutorialDone = b('tutorialV4', false);
    return migrate(p);
  }

  Profile copy() => fromJson(jsonDecode(jsonEncode(toJson())));
}

/// Same rules as store.tsx `migrate`.
Profile migrate(Profile n) {
  if (n.fieldsV < 2) {
    final old = n.field;
    n.ownedFields = n.ownedFields.map((i) => i + 1).toList();
    n.field = old == 6 ? kDefaultField : old + 1;
    n.fieldsV = 2;
  }
  n.ownedFields = {...Profile.freeFields, 7, ...n.ownedFields}.where((i) => i >= 0 && i < kFields.length).toList();
  if (!(n.field >= 0 && n.field < kFields.length) || !n.ownedFields.contains(n.field)) n.field = kDefaultField;
  n.ownedTeams = {...Profile.freeTeams, ...n.ownedTeams}.toList();
  if (!kTeams.any((t) => t.id == n.team)) n.team = 'club0';
  if (n.ball < 0 || n.ball > 35) n.ball = 0;
  if (n.form < 0 || n.form >= kForms.length) n.form = 0;
  return n;
}

class Lvl {
  final int level, cur, need;
  const Lvl(this.level, this.cur, this.need);
}

Lvl level(int xp) {
  var l = 1, need = 100, x = xp;
  while (x >= need) {
    x -= need;
    l++;
    need = (need * 1.25).round();
  }
  return Lvl(l, x, need);
}

const kLeagues = [('BRONZE', 0), ('SILVER', 300), ('GOLD', 800), ('PLATINUM', 1600), ('DIAMOND', 3000), ('NEXORA', 5000)];
const kLeagueFa = {'BRONZE': 'برنز', 'SILVER': 'نقره', 'GOLD': 'طلا', 'PLATINUM': 'پلاتین', 'DIAMOND': 'الماس', 'NEXORA': 'نکسورا'};

class LeagueInfo {
  final String name;
  final int idx, from, to;
  const LeagueInfo(this.name, this.idx, this.from, this.to);
}

LeagueInfo league(int t) {
  var i = 0;
  while (i + 1 < kLeagues.length && t >= kLeagues[i + 1].$2) {
    i++;
  }
  return LeagueInfo(kLeagues[i].$1, i, kLeagues[i].$2, i + 1 < kLeagues.length ? kLeagues[i + 1].$2 : kLeagues[i].$2 + 2000);
}

class Store extends ChangeNotifier {
  Store._();
  static final Store i = Store._();
  static const key = 'nexora.profile.v1';
  Profile p = Profile.defaults();
  bool ready = false;
  SharedPreferences? _prefs;
  Timer? _save;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final s = _prefs!.getString(key);
    if (s != null) {
      try {
        p = Profile.fromJson(jsonDecode(s) as Map<String, dynamic>);
      } catch (_) {}
    }
    ready = true;
    notifyListeners();
  }

  void set(void Function(Profile p) fn) {
    fn(p);
    notifyListeners();
    _save?.cancel();
    _save = Timer(const Duration(milliseconds: 250), () => _prefs?.setString(key, jsonEncode(p.toJson())));
  }

  void reset() {
    p = Profile.defaults();
    _prefs?.remove(key);
    notifyListeners();
  }
}
