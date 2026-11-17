import 'package:flutter/material.dart';

import '../../core/settings/app_settings.dart';
import '../../core/theme/nx_theme.dart';
import '../../core/ui2/nx2_widgets.dart';
import '../../core/widgets/nx_widgets.dart';
import 'ui/missions_tab.dart';
import 'ui/records_tabs.dart';

/// REWARDS & PACKS (dock): the real missions/daily rewards and achievements of the player.
class RewardsPage extends StatelessWidget {
  const RewardsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: NxWorldScaffold(
        title: context.tx('جایزه‌ها و پک‌ها', 'REWARDS & PACKS'),
        palette: WorldPalette.personal,
        dock: Nx2Tab.rewards,
        body: Column(children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
            child: Nx2SegmentTabs(labels: <String>[
              context.tx('مأموریت‌ها و جایزه‌ها', 'Missions & rewards'),
              context.tx('دستاوردها', 'Achievements'),
            ]),
          ),
          const Expanded(child: TabBarView(children: <Widget>[MissionsTab(), AchievementsTab()])),
        ]),
      ),
    );
  }
}
