// Online physics profile negotiation (netcode.dart header, run 5):
// the host picks 'stars' only when every other room member advertises the Flutter presence flag,
// announces it as s.pf in every snapshot, and clients build their engine from it.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/game/engine.dart';
import 'package:nexora/online/netcode.dart';

class _Port implements NetPort {
  @override
  final String me;
  final List<Map<String, dynamic>> out = [];
  _Port(this.me);
  @override
  bool allFlutter = true;
  @override
  List<Player> get players => const [];
  @override
  void send(Map<String, dynamic> m) => out.add(jsonDecode(jsonEncode(m)) as Map<String, dynamic>);
  @override
  bool isOnline(String uid) => true;
  @override
  int get peers => 1;
  @override
  DiscStats statsFor(String disc) => const DiscStats(6, 6);
}

MatchCfg _cfg(String profile) => MatchCfg(
    field: 1, ball: 0, forms: [0, 2], ai: false, aiLvl: 1, limit: 99, matchTime: 0, turnTime: 0, vip: [false, false], first: 0,
    stats: [const DiscStats(6, 6), const DiscStats(6, 6)], profile: profile);

/// Host opens the match with [online] presence, sends one snapshot; returns (host profile, client NetMatch).
(String, NetMatch, Map<String, dynamic>) _negotiate(List<String> members, Map<String, bool> online) {
  final pf = pickProfile(me: 'H', members: members, online: online);
  final hp = _Port('H'), cp = _Port('C');
  final host = NetMatch(eng: Engine(_cfg(pf)), isHost: true, port: hp, onEvent: (_, __) {});
  host.sendSnap(0, force: true);
  final snap = hp.out.firstWhere((m) => m['k'] == 's');
  final cpf = msgProfile(snap)!; // what online_match.dart does before building the client engine
  final cli = NetMatch(eng: Engine(_cfg(cpf)), isHost: false, port: cp, onEvent: (_, __) {});
  cli.onMessage(snap, 'H', 10);
  return (pf, cli, snap);
}

void main() {
  test('mixed room (one RN/Godot peer) -> classic for everyone', () {
    final (pf, cli, snap) = _negotiate(['H', 'F', 'R'], {'H': true, 'F': true, 'R': false});
    expect(pf, 'classic');
    expect((snap['s'] as Map)['pf'], 'classic');
    expect(cli.eng.cfg.profile, 'classic');
    expect(cli.eng.godot, isFalse);
    expect(cli.lockHost, isTrue); // same profile on both sides -> lockstep allowed
  });

  test('all-Flutter room -> stars for everyone', () {
    final (pf, cli, snap) = _negotiate(['H', 'F1', 'F2', 'S'], {'H': true, 'F1': true, 'F2': true, 'S': true});
    expect(pf, 'stars');
    expect((snap['s'] as Map)['pf'], 'stars');
    expect(cli.eng.cfg.profile, 'stars');
    expect(cli.eng.godot, isTrue);
    expect(cli.lockHost, isTrue);
  });

  test('member not connected yet counts as unknown -> classic', () {
    expect(pickProfile(me: 'H', members: ['H', 'F', 'X'], online: {'H': true, 'F': true}), 'classic');
  });

  test('legacy host without pf means classic; profile mismatch disables lockstep', () {
    expect(snapProfile({'q': 1, 'lk': 1}), 'classic');
    expect(snapProfile({'pf': 'weird'}), 'classic');
    final cli = NetMatch(eng: Engine(_cfg('stars')), isHost: false, port: _Port('C'), onEvent: (_, __) {});
    cli.onMessage({
      'k': 's',
      's': {'q': 1, 'ts': 0, 'lk': 1, 'pf': 'classic'}
    }, 'H', 0);
    expect(cli.lockHost, isFalse);
  });
}
