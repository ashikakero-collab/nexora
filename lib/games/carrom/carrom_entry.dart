import 'package:flutter/widgets.dart';

import '../core/game_contract.dart';
import 'ui/carrom_view.dart';

Widget buildCarromGame(GameLaunch launch) => CarromView(launch: launch);
