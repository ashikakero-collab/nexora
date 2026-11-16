import 'package:flutter/widgets.dart';

import '../core/game_contract.dart';
import 'ui/uno_game_view.dart';

/// NX Cards (UNO-style card game). Game id stays 'uno'.
/// UI name: "NX Cards", subtitle "UNO-style".
Widget buildUnoGame(GameLaunch launch) => UnoGameView(launch: launch);
