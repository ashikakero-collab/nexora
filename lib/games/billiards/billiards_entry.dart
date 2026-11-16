import 'package:flutter/widgets.dart';

import '../core/game_contract.dart';
import 'ui/billiards_game.dart';

/// NEXORA Arcade entry: 8-ball billiards (vs offline bot or pass-and-play).
Widget buildBilliardsGame(GameLaunch launch) => BilliardsGame(launch: launch);
