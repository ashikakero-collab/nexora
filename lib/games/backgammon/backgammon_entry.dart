import 'package:flutter/widgets.dart';
import 'package:nexora/games/core/game_contract.dart';

import 'ui/backgammon_game.dart';

/// NEXORA Backgammon: full rules (bar, bearing off, doubles, forced larger
/// die, gammon/backgammon scoring), offline bot and pass-and-play.
Widget buildBackgammonGame(GameLaunch launch) => BackgammonGame(launch: launch);
