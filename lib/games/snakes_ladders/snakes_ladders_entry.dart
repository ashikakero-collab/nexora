import 'package:flutter/widgets.dart';
import 'package:nexora/games/core/game_contract.dart';

import 'ui/snl_game.dart';

/// NEXORA Snakes & Ladders: 2-4 seats on a cosmic 10x10 board, offline bots
/// (vsBot) or pass-and-play (local).
Widget buildSnakesLaddersGame(GameLaunch launch) => SnlGame(launch: launch);
