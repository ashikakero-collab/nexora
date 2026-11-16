import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexora/games/core/game_contract.dart';
import 'package:nexora/games/finger_soccer/ui/bm_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/games/finger_soccer/core/bm_engine.dart';

class _Hooks implements BmHooks {
  final List<String> events = <String>[];
  @override
  void sfx(String k, [double v = 1]) {}
  @override
  void tone(String k) {}
  @override
  void vib(List<int> pattern) {}
  @override
  void toast(String text, bool big) {}
  @override
  void goalFx() {}
  @override
  void emit(String event, Map<String, dynamic> data) => events.add(event);
}

BmConfig _cfg({bool mirror = false, String mode = 'bot'}) => BmConfig(
      mode: mode,
      teams: const <String>['club0', 'club1'],
      form: const <int>[0, 3],
      names: const <String>['A', 'B'],
      field: 6,
      ball: 0,
      matchTime: 300,
      ai: mode == 'bot',
      aiLvl: 2,
      mirror: mirror,
    );

void main() {
  test('BERMUDA constants and field geometry are copied 1:1', () {
    expect(K, 1.27);
    expect(PR, 63.8);
    expect(BR, 28.8);
    expect(STEP, 1 / 240);
    expect(kBmFields.length, 29);
    final BmFieldS f = kBmFields[0]; // forest
    expect(f.W, (1086 * FS).roundToDouble());
    expect(f.L, (195 * FS).roundToDouble());
    expect(f.g, 169);
    final BmEngine e = BmEngine(_Hooks(), rng: math.Random(1));
    e.startMatch(_cfg());
    expect(e.bodies.length, 11);
    expect(e.ball!.r, BR);
    expect(e.ball!.m, 1.9);
    expect(e.bodies.first.m, 5);
    expect(e.GOALS[0].x2 - e.GOALS[0].x1, 338);
  });

  test('bot vs bot plays a long match without escaping the pitch', () {
    final _Hooks h = _Hooks();
    final BmEngine e = BmEngine(h, rng: math.Random(7));
    e.startMatch(_cfg());
    int shots = 0;
    for (int f = 0; f < 60 * 120 && e.phase != 'over'; f++) {
      if (e.phase == 'aim' && e.turn == 0 && e.drag == null) {
        final BmAiPlan? p = e.aiDecide();
        if (p != null) {
          e.fire(p.b, p.dx * p.l, p.dy * p.l, p.l);
          shots++;
        }
      }
      e.frame(1 / 60);
      for (final BmBody b in e.bodies) {
        expect(b.x.isFinite && b.y.isFinite, isTrue);
        expect(b.x, inInclusiveRange(e.Fl - 1, e.Fr + 1));
        expect(b.y, inInclusiveRange(e.Ft - e.DEPTH - 1, e.Fb + e.DEPTH + 1));
      }
    }
    expect(shots, greaterThan(5));
    expect(h.events.contains('shot'), isTrue);
  });

  test('mirrored snapshot maps back to the same global positions', () {
    final BmEngine host = BmEngine(_Hooks(), rng: math.Random(3))..startMatch(_cfg(mode: 'online'));
    final BmEngine guest = BmEngine(_Hooks(), rng: math.Random(3))..startMatch(_cfg(mode: 'online', mirror: true));
    final Map<String, dynamic> s = host.snapshot();
    guest.applySnapshot(s);
    expect(guest.snapshot()['b'], s['b']);
    expect(guest.ct(guest.turn), host.ct(host.turn));
  });

  testWidgets('BERMUDA match vs bot renders and plays 20 s on a phone screen', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final List<GameResult> results = <GameResult>[];
    final GameLaunch launch = GameLaunch(
      gameId: 'finger_soccer',
      mode: GameMode.vsBot,
      difficulty: BotDifficulty.hard,
      playerName: 'Tester',
      isFa: false,
      fancyEffects: true,
      reducedMotion: false,
      soundOn: false,
      seed: 3,
      onFinish: results.add,
    );
    await tester.pumpWidget(ProviderScope(child: MaterialApp(home: Scaffold(body: BermudaView(launch: launch, autoStart: true)))));
    for (int i = 0; i < 20 * 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
  });
}
