import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/storage/local_store.dart';
import 'package:nexora/games/backgammon/backgammon_entry.dart';
import 'package:nexora/games/backgammon/ui/bg_skins.dart';
import 'package:nexora/games/billiards/billiards_entry.dart';
import 'package:nexora/games/billiards/ui/pool_skins.dart';
import 'package:nexora/games/carrom/carrom_entry.dart';
import 'package:nexora/games/snakes_ladders/snakes_ladders_entry.dart';
import 'package:nexora/games/ludo/ludo_entry.dart';
import 'package:nexora/games/uno/uno_entry.dart';
import 'package:nexora/games/quiz/quiz_entry.dart';
import 'package:nexora/games/mafia/mafia_entry.dart';
import 'package:nexora/games/finger_soccer/finger_soccer_entry.dart';
import 'package:nexora/games/core/game_contract.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'render_util.dart';

GameLaunch launch(String id) => GameLaunch(
      gameId: id, mode: GameMode.vsBot, difficulty: BotDifficulty.normal, playerName: 'Ashkan',
      isFa: false, fancyEffects: false, reducedMotion: true, soundOn: false, seed: 2, onFinish: (_) {});

const String only = String.fromEnvironment('ONLY');
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await LocalStore.init();
    await loadFonts();
  });
  final Map<String, Widget Function(GameLaunch)> games = <String, Widget Function(GameLaunch)>{
    'carrom': buildCarromGame,
    'billiards': buildBilliardsGame,
    'backgammon': buildBackgammonGame,
    'snakes_ladders': buildSnakesLaddersGame,
    'ludo': buildLudoGame,
    'uno': buildUnoGame,
    'quiz': buildQuizGame,
    'mafia': buildMafiaGame,
    'finger_soccer': buildFingerSoccerGame,
  };
  final Map<String, int> skins = <String, int>{'carrom': 4, 'billiards': 3, 'backgammon': 3, 'snakes_ladders': 2, 'ludo': 1, 'uno': 1, 'quiz': 1, 'mafia': 1, 'finger_soccer': 1};
  for (final String g in games.keys) {
    if (only.isNotEmpty && !only.split(',').contains(g)) continue;
    for (int s = 0; s < skins[g]!; s++) {
      testWidgets('$g skin $s', (WidgetTester tester) async {
        phone(tester);
        await LocalStore.instance.setInt('$g.board_skin', s);
        await tester.pumpWidget(shotApp(games[g]!(launch(g))));
        await settle(tester, frames: 40);
        await shoot(tester, 'games/${g}_$s.png');
        if (const bool.fromEnvironment('DBG')) {
          poolDebugGeometry = true;
          bgDebugGeometry = true;
          await tester.pumpWidget(shotApp(games[g]!(launch(g))));
          await settle(tester, frames: 10);
          await shoot(tester, 'games/dbg_${g}_$s.png');
          poolDebugGeometry = false;
          bgDebugGeometry = false;
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 100));
      });
    }
  }
}
