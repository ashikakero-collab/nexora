import 'package:flutter/widgets.dart';

import '../core/game_contract.dart';
import 'ui/mafia_narrator_view.dart';
import 'ui/mafia_online_view.dart';
import 'ui/mafia_vsbot_view.dart';

/// Entry point registered in game_registry.dart.
///  * GameMode.vsBot: the player against offline AI citizens.
///  * GameMode.local: narrator mode for 6..12 friends sharing one phone.
Widget buildMafiaGame(GameLaunch launch) {
  if (launch.online) {
    return MafiaOnlineView(launch: launch);
  }
  if (launch.mode == GameMode.vsBot) {
    return MafiaVsBotView(launch: launch);
  }
  return MafiaNarratorView(launch: launch);
}
