import 'dart:math';

/// One match in a single-elimination bracket. `null` player = bye (round 1) or TBD (later rounds).
class BracketMatch {
  BracketMatch({this.a, this.b, this.winner});
  String? a;
  String? b;
  String? winner;

  bool get ready => a != null && b != null;
  bool get done => winner != null;
  bool get playable => ready && !done;

  Map<String, dynamic> toJson() => <String, dynamic>{'a': a, 'b': b, 'w': winner};
  static BracketMatch fromJson(Map<String, dynamic> j) =>
      BracketMatch(a: j['a'] as String?, b: j['b'] as String?, winner: j['w'] as String?);
}

/// Address of a match.
class MatchRef {
  const MatchRef(this.round, this.index);
  final int round;
  final int index;

  @override
  bool operator ==(Object other) => other is MatchRef && other.round == round && other.index == index;

  @override
  int get hashCode => round * 1000 + index;
}

/// Pure single-elimination bracket for local (same-device) tournaments.
/// Results are entered after playing on this device; online tournaments
/// will be validated server-side (Vision §8).
class TournamentBracket {
  TournamentBracket._(this.players, this.rounds);

  static const int minPlayers = 2;
  static const int maxPlayers = 32;

  final List<String> players;
  final List<List<BracketMatch>> rounds;

  /// Builds a bracket. Names are trimmed and must be unique (case-insensitive).
  /// Byes go to the first seeds and advance automatically.
  static TournamentBracket create(List<String> rawPlayers, {Random? shuffle}) {
    final players = rawPlayers.map((String p) => p.trim()).where((String p) => p.isNotEmpty).toList();
    if (players.length < minPlayers) throw ArgumentError('At least $minPlayers players are needed');
    if (players.length > maxPlayers) throw ArgumentError('At most $maxPlayers players');
    final lower = players.map((String p) => p.toLowerCase()).toSet();
    if (lower.length != players.length) throw ArgumentError('Player names must be unique');
    if (shuffle != null) players.shuffle(shuffle);

    var size = 1;
    while (size < players.length) {
      size *= 2;
    }
    final int byes = size - players.length;
    final int firstCount = size ~/ 2;
    final rounds = <List<BracketMatch>>[];
    final first = <BracketMatch>[];
    var idx = 0;
    for (var i = 0; i < firstCount; i++) {
      if (i < byes) {
        final p = players[idx++];
        first.add(BracketMatch(a: p, b: null, winner: p));
      } else {
        final pa = players[idx++];
        final pb = players[idx++];
        first.add(BracketMatch(a: pa, b: pb));
      }
    }
    rounds.add(first);
    var count = firstCount ~/ 2;
    while (count >= 1) {
      rounds.add(List<BracketMatch>.generate(count, (_) => BracketMatch()));
      count ~/= 2;
    }
    final b = TournamentBracket._(List<String>.unmodifiable(players), rounds);
    for (var i = 0; i < first.length; i++) {
      final w = first[i].winner;
      if (w != null) b._place(0, i, w);
    }
    return b;
  }

  int get roundCount => rounds.length;
  BracketMatch get finalMatch => rounds.last.first;
  String? get champion => finalMatch.winner;
  bool get finished => champion != null;

  List<MatchRef> get playable {
    final out = <MatchRef>[];
    for (var r = 0; r < rounds.length; r++) {
      for (var i = 0; i < rounds[r].length; i++) {
        if (rounds[r][i].playable) out.add(MatchRef(r, i));
      }
    }
    return out;
  }

  /// Number of real (non-bye) matches.
  int get totalMatches => players.length - 1;
  int get playedMatches {
    var n = 0;
    for (var r = 0; r < rounds.length; r++) {
      for (final m in rounds[r]) {
        if (m.done && m.ready) n++;
      }
    }
    return n;
  }

  void _place(int round, int index, String winner) {
    if (round + 1 >= rounds.length) return;
    final next = rounds[round + 1][index ~/ 2];
    if (index.isEven) {
      next.a = winner;
    } else {
      next.b = winner;
    }
  }

  /// Clears the path a result travelled through (when a result is corrected).
  void _clearPath(int round, int index) {
    var r = round;
    var i = index;
    while (r + 1 < rounds.length) {
      final next = rounds[r + 1][i ~/ 2];
      if (i.isEven) {
        next.a = null;
      } else {
        next.b = null;
      }
      final bool had = next.winner != null;
      next.winner = null;
      if (!had) break;
      r++;
      i = i ~/ 2;
    }
  }

  /// Records (or corrects) the winner of a match. Returns false if invalid.
  bool setWinner(int round, int index, String winner) {
    if (round < 0 || round >= rounds.length) return false;
    if (index < 0 || index >= rounds[round].length) return false;
    final m = rounds[round][index];
    if (!m.ready) return false;
    if (winner != m.a && winner != m.b) return false;
    if (m.winner == winner) return true;
    if (m.winner != null) _clearPath(round, index);
    m.winner = winner;
    _place(round, index, winner);
    return true;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'players': players,
        'rounds': rounds.map((List<BracketMatch> r) => r.map((BracketMatch m) => m.toJson()).toList()).toList(),
      };

  static TournamentBracket fromJson(Map<String, dynamic> j) {
    final players = ((j['players'] as List?) ?? const <dynamic>[]).map((dynamic e) => '$e').toList();
    final rounds = ((j['rounds'] as List?) ?? const <dynamic>[])
        .whereType<List>()
        .map((List r) => r.whereType<Map>().map((Map m) => BracketMatch.fromJson(Map<String, dynamic>.from(m))).toList())
        .toList();
    return TournamentBracket._(List<String>.unmodifiable(players), rounds);
  }
}
