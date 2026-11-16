import 'package:flutter/widgets.dart';

import 'package:nexora/games/core/game_contract.dart';
import 'ui/bm_view.dart';

/// NEXORA Arcade entry for Finger Soccer: the BERMUDA NXG disc-football game (1:1 port of its JS engine).
/// Pure engine in core/ (bm_engine.dart, bm_data.dart), rendering + UI + online wiring in ui/.
Widget buildFingerSoccerGame(GameLaunch launch) => BermudaView(launch: launch);
