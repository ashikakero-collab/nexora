import 'package:flutter/widgets.dart';
import 'package:nexora/games/core/game_contract.dart';

import 'ui/ludo_game.dart';

/// NEXORA Ludo: 2-4 seats, classic rules, offline bots and pass-and-play.
Widget buildLudoGame(GameLaunch launch) => LudoGame(launch: launch);
