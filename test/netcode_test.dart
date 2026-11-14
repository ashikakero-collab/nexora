// Lockstep netcode test: a host and a client NetMatch talk through a fake broadcast bus with latency.
// The client only receives shot vectors ('f') and low-rate snapshots, simulates locally, and must land on
// the host's exact rest state (bit-identical hash) after every shot. Also checks the shooter prediction
// path and the bandwidth reduction versus the legacy RN rates.
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/game/engine.dart';
import 'package:nexora/online/netcode.dart';

class Bus {
  final List<(int, String, Map<String, dynamic>)> q = [];
  int bytes = 0, msgs = 0;
}

class FakePort implements NetPort {
  @override
  final String me;
  final Bus bus;
  final int latency;
  @override
  bool allFlutter = true;
  @override
  List<Player> players;
  int now = 0;
  FakePort(this.me, this.bus, this.latency, this.players);
  @override
  void send(Map<String, dynamic> m) {
    final j = jsonEncode(m);
    bus.bytes += j.length;
    bus.msgs++;
    bus.q.add((now + latency, me, jsonDecode(j) as Map<String, dynamic>));
  }

  @override
  bool isOnline(String uid) => players.any((p) => p.uid == uid);
  @override
  int get peers => 1;
  @override
  DiscStats statsFor(String disc) => const DiscStats(6, 6);
}

MatchCfg cfg() => MatchCfg(field: 1, ball: 0, forms: [0, 2], ai: false, aiLvl: 1, limit: 99, matchTime: 0, turnTime: 0, vip: [false, false], first: 0, stats: [const DiscStats(6, 6), const DiscStats(6, 6)]);

void main() {
  test('lockstep client stays bit-identical with the host (bot vs bot, 25 shots)', () {
    final bus = Bus();
    final hp = FakePort('H', bus, 0, const []), cp = FakePort('C', bus, 0, const []);
    final he = Engine(cfg(), rand: _rng(7)), ce = Engine(cfg());
    final host = NetMatch(eng: he, isHost: true, port: hp, onEvent: (_, __) {});
    final cli = NetMatch(eng: ce, isHost: false, port: cp, onEvent: (_, __) {});
    var t = 0, keys = 0, shots = 0, checked = 0;
    const dt = 1 / 60;
    while (he.shots < 25 && t < 60 * 60 * 1000) {
      t += 16;
      hp.now = t;
      cp.now = t;
      host.tick(dt, t);
      // deliver with 70 ms one-way latency
      for (final m in bus.q.where((e) => e.$1 + 70 <= t).toList()) {
        bus.q.remove(m);
        if (m.$2 == 'H') {
          if (m.$3['k'] == 'f') shots++;
          if (m.$3['k'] == 's' && (m.$3['s'] as Map)['x'] != null) keys++;
          cli.onMessage(m.$3, 'H', t);
        } else {
          host.onMessage(m.$3, 'C', t);
        }
      }
      cli.tick(dt, t);
      if (cli.mode == NetMode.lockstep && he.phase == Phase.aim && atRest(he) && atRest(ce) && !cli.simulating && ce.phase == Phase.aim && cli.cseq == host.seq) {
        expect(stateHash(ce), stateHash(he), reason: 'diverged after ${he.shots} shots');
        checked++;
      }
    }
    // ignore: avoid_print
    print('shots=$shots keyframes=$keys checks=$checked desyncs=${cli.desyncs} corrections=${cli.corrections} resets=${cli.resets} msgs=${bus.msgs} bytes=${bus.bytes}');
    expect(he.shots, greaterThanOrEqualTo(25));
    expect(cli.desyncs, 0);
    expect(checked, greaterThan(100));
    // no soft correction may ever be needed: every keyframe must already match the local result
    expect(cli.corrections, 0);
  });

  test('shooter prediction matches the host shot exactly', () {
    final bus = Bus();
    final pl = [const Player('H', 0, 0, 'club0'), const Player('C', 1, 0, 'club0')];
    final hp = FakePort('H', bus, 0, pl), cp = FakePort('C', bus, 0, pl);
    final he = Engine(cfg()..first = 1), ce = Engine(cfg()..first = 1);
    final host = NetMatch(eng: he, isHost: true, port: hp, onEvent: (_, __) {});
    final cli = NetMatch(eng: ce, isHost: false, port: cp, onEvent: (_, __) {});
    var t = 0;
    void pump(int ms) {
      for (var i = 0; i < ms ~/ 16; i++) {
        t += 16;
        hp.now = t;
        cp.now = t;
        host.tick(1 / 60, t);
        for (final m in bus.q.where((e) => e.$1 + 50 <= t).toList()) {
          bus.q.remove(m);
          m.$2 == 'H' ? cli.onMessage(m.$3, 'H', t) : host.onMessage(m.$3, 'C', t);
        }
        cli.tick(1 / 60, t);
      }
    }

    pump(2500);
    expect(cli.mode, NetMode.lockstep);
    expect(cli.controller, 'C');
    expect(cli.canAct(t), isTrue);
    final b = ce.bodies.firstWhere((x) => x.team == 1 && !identical(x, ce.ball));
    cli.release(t, Drag(b, b.x, b.y, b.x - 40, b.y - 160));
    expect(cli.simulating, isTrue);
    pump(9000);
    expect(he.shots, 1);
    expect(cli.desyncs, 0);
    expect(stateHash(ce), stateHash(he));
  });

  test('lean (all-Flutter) snapshot rate is far below the legacy RN rate', () {
    int run(bool lean) {
      final bus = Bus();
      final hp = FakePort('H', bus, 0, const [])..allFlutter = lean;
      final he = Engine(cfg(), rand: _rng(3));
      final host = NetMatch(eng: he, isHost: true, port: hp, onEvent: (_, __) {});
      for (var t = 16; t < 60000; t += 16) {
        hp.now = t;
        host.tick(1 / 60, t);
      }
      return bus.msgs;
    }

    final lean = run(true), legacy = run(false);
    // ignore: avoid_print
    print('60 s of bot play: legacy=$legacy msgs, lean=$lean msgs (${(legacy / lean).toStringAsFixed(1)}x fewer)');
    expect(lean * 3, lessThan(legacy));
  });
}

double Function() _rng(int seed) {
  final r = math.Random(seed);
  return r.nextDouble;
}
