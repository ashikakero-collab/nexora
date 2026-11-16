import 'package:flutter/widgets.dart';

import '../core/game_contract.dart';
import 'ui/quiz_view.dart';

/// NEXORA Quiz: 10-round knowledge duel (vs offline bot or same-device split screen).
Widget buildQuizGame(GameLaunch launch) => QuizView(launch: launch);
