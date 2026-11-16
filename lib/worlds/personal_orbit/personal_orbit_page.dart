import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/profile/profile_service.dart';
import '../../core/settings/app_settings.dart';
import '../../core/storage/local_store.dart';
import '../../core/theme/nx_theme.dart';
import '../../core/ui2/nx2_widgets.dart';
import '../../core/widgets/nx_widgets.dart';
import 'core/challenge_store.dart';
import 'ui/identity_tab.dart';
import 'ui/missions_tab.dart';
import 'ui/records_tabs.dart';
import 'ui/space_tab.dart';
import 'ui/wardrobe_tab.dart';

/// PERSONAL ORBIT (STEP_09 + STEP_14): the user's own home in NEXORA.
/// Premium dark world: identity & avatar, missions, wardrobe, 2.5D room,
/// achievements, stats and activity. Everything is local-first (LocalStore).
class PersonalOrbitPage extends ConsumerStatefulWidget {
  const PersonalOrbitPage({super.key});

  @override
  ConsumerState<PersonalOrbitPage> createState() => _PersonalOrbitPageState();
}

class _PersonalOrbitPageState extends ConsumerState<PersonalOrbitPage> {
  @override
  void initState() {
    super.initState();
    // Start challenge baselines as soon as the world is opened.
    try {
      ChallengeStore.touch(ref.read(profileProvider),
          store: LocalStore.instance);
    } catch (_) {
      // Store not ready (tests without LocalStore): missions tab will retry.
    }
  }

  ThemeData _worldTheme(BuildContext context) {
    final ThemeData base = Theme.of(context);
    final NxThemeColors visual = NxThemeColors.of(context);
    return base.copyWith(
      colorScheme: base.colorScheme.copyWith(
        primary: visual.accent,
        secondary: visual.accentSecondary,
        surface: visual.surfaceRaised,
        onSurface: visual.text,
      ),
      scaffoldBackgroundColor: visual.background,
      textTheme: base.textTheme
          .apply(bodyColor: visual.text, displayColor: visual.text),
      iconTheme: IconThemeData(color: visual.text),
      sliderTheme: base.sliderTheme
          .copyWith(activeTrackColor: visual.accent, thumbColor: visual.accent),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        labelStyle: TextStyle(color: visual.muted),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(settingsProvider);
    final NxThemeColors visual = NxThemeColors.of(context);
    final List<_TabDef> tabs = <_TabDef>[
      _TabDef(Icons.badge_rounded, context.tx('هویت', 'Identity'),
          const IdentityTab()),
      _TabDef(Icons.flag_rounded, context.tx('مأموریت‌ها', 'Missions'),
          const MissionsTab()),
      _TabDef(Icons.checkroom_rounded, context.tx('کمد لباس', 'Wardrobe'),
          const WardrobeTab()),
      _TabDef(Icons.chair_rounded, context.tx('فضای من', 'My Space'),
          const SpaceTab()),
      _TabDef(Icons.emoji_events_rounded,
          context.tx('دستاوردها', 'Achievements'), const AchievementsTab()),
      _TabDef(Icons.insights_rounded, context.tx('آمار', 'Stats'),
          const StatsTab()),
      _TabDef(Icons.timeline_rounded, context.tx('فعالیت‌ها', 'Activity'),
          const ActivityTab()),
    ];
    return Theme(
      data: _worldTheme(context),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: visual.text),
        child: DefaultTabController(
          length: tabs.length,
          child: NxWorldScaffold(
            title: context.tx('پروفایل · مدار شخصی', 'PROFILE · PERSONAL ORBIT'),
            palette: WorldPalette.personal,
            dock: Nx2Tab.profile,
            body: Column(children: <Widget>[
              Container(
                margin: const EdgeInsets.fromLTRB(
                    NxSpace.sm, NxSpace.xs, NxSpace.sm, 0),
                decoration: BoxDecoration(
                  color: visual.surface.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(NxRadius.lg),
                  border:
                      Border.all(color: visual.border.withValues(alpha: 0.66)),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 18,
                        offset: const Offset(0, 6)),
                  ],
                ),
                child: TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  dividerColor: Colors.transparent,
                  labelColor: visual.accent,
                  unselectedLabelColor: visual.muted,
                  indicatorColor: visual.accent,
                  indicatorSize: TabBarIndicatorSize.label,
                  labelStyle: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 13),
                  tabs: <Widget>[
                    for (final _TabDef t in tabs)
                      Tab(
                        height: 44,
                        child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Icon(t.icon, size: 18),
                              const SizedBox(width: 6),
                              Text(t.label),
                            ]),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  // Swiping is off so dragging decor in My Space never fights the tab pager.
                  physics: const NeverScrollableScrollPhysics(),
                  children: <Widget>[for (final _TabDef t in tabs) t.body],
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _TabDef {
  const _TabDef(this.icon, this.label, this.body);
  final IconData icon;
  final String label;
  final Widget body;
}
