import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/storage/local_store.dart';
import 'package:nexora/games/core/game_contract.dart';
import 'package:nexora/games/quiz/quiz_entry.dart';
import 'package:shared_preferences/shared_preferences.dart';

GameLaunch _launch(List<GameResult> results, GameMode mode, bool isFa) => GameLaunch(
      gameId: 'quiz',
      mode: mode,
      difficulty: BotDifficulty.hard,
      playerName: 'Tester',
      isFa: isFa,
      fancyEffects: false,
      reducedMotion: true,
      soundOn: false,
      seed: 3,
      onFinish: results.add,
    );

Future<void> _run(WidgetTester tester, GameMode mode, bool isFa) async {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final List<GameResult> results = <GameResult>[];
  final void Function(FlutterErrorDetails)? old = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails d) {
    for (final String line in d.toString().split('\n').take(30)) {
      // ignore: avoid_print
      print('Error: QUIZ $line');
    }
    old?.call(d);
  };
  addTearDown(() => FlutterError.onError = old);
  await tester.pumpWidget(ProviderScope(
    child: MaterialApp(home: Scaffold(body: buildQuizGame(_launch(results, mode, isFa)))),
  ));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(find.text(isFa ? 'ترکیبی' : 'Mixed'));
  for (int i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  // Answer once with the first option on the (bottom) player's pane.
  await tester.tap(find.text('A').last, warnIfMissed: false);
  // Play the whole match out on timers.
  // Unanswered rounds run to the 15 s limit + 2.3 s reveal: ~175 s for 10 rounds.
  for (int i = 0; i < 420; i++) {
    await tester.pump(const Duration(milliseconds: 500));
  }
  final Finder finish = find.text(isFa ? 'ثبت نتیجه' : 'Finish');
  if (finish.evaluate().isEmpty) {
    // ignore: avoid_print
    print('Error: QUIZ no finish button; texts: ${find.byType(Text).evaluate().take(12).map((Element e) => (e.widget as Text).data).join(' | ')}');
  }
  expect(finish, findsOneWidget);
  await tester.tap(finish);
  await tester.pump(const Duration(milliseconds: 300));
  expect(results.length, 1);
  await tester.pumpWidget(const SizedBox());
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await LocalStore.init();
  });

  testWidgets('quiz vs bot plays a full match on 360x640 (fa)', (WidgetTester tester) async {
    await _run(tester, GameMode.vsBot, true);
  });

  testWidgets('quiz local split screen plays a full match on 360x640 (en)', (WidgetTester tester) async {
    await _run(tester, GameMode.local, false);
  });
}
