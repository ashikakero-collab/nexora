import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nexora/core/profile/profile_service.dart';
import 'package:nexora/core/settings/app_settings.dart';
import 'package:nexora/core/storage/local_store.dart';
import 'package:nexora/core/theme/nx_theme.dart';
import 'package:nexora/features/tournaments/ui/tournaments_page.dart';
import 'package:nexora/worlds/arcade/arcade_page.dart';
import 'package:nexora/worlds/arcade/online/leaderboard_page.dart';
import 'package:nexora/worlds/hub/hub_page.dart';
import 'package:nexora/worlds/nexora_exchange/exchange_page.dart';
import 'package:nexora/worlds/oracle_core/oracle_core_page.dart';
import 'package:nexora/worlds/personal_orbit/personal_orbit_page.dart';
import 'package:nexora/worlds/personal_orbit/rewards_page.dart';
import 'package:nexora/worlds/rooms/rooms_page.dart';
import 'package:nexora/worlds/settings/settings_page.dart';
import 'package:nexora/worlds/social_hub/social_hub_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'render_util.dart';

const String only = String.fromEnvironment('ONLY');
void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{'settings.lang': 'en'});
    await LocalStore.init();
    await loadFonts();
  });
  final Map<String, Widget Function()> pages = <String, Widget Function()>{
    'hub': () => const HubPage(),
    'rooms': () => const RoomsPage(),
    'arcade': () => const ArcadePage(),
    'social': () => const SocialHubPage(),
    'shop': () => const ExchangePage(),
    'rewards': () => const RewardsPage(),
    'profile': () => const PersonalOrbitPage(),
    'oracle': () => const OracleCorePage(),
    'ranking': () => const LeaderboardPage(),
    'tournaments': () => const TournamentsPage(),
    'settings': () => const SettingsPage(),
  };
  for (final String lang in <String>['en', 'fa']) {
    for (final MapEntry<String, Widget Function()> e in pages.entries) {
      if (only.isNotEmpty && !only.split(',').contains(e.key)) continue;
      if (lang == 'fa' && !<String>{'hub', 'rooms', 'shop'}.contains(e.key)) continue;
      testWidgets('menu ${e.key} $lang', (WidgetTester tester) async {
        phone(tester);
        final ProviderContainer c = ProviderContainer();
        addTearDown(c.dispose);
        c.read(settingsProvider).languageCode = lang;
        final ProfileService p = c.read(profileProvider);
        if (!p.hasIdentity) p.updateProfile(name: 'Ashkan');
        final GoRouter router = GoRouter(routes: <RouteBase>[GoRoute(path: '/', builder: (_, __) => e.value())]);
        await tester.pumpWidget(UncontrolledProviderScope(
          container: c,
          child: MaterialApp.router(
            debugShowCheckedModeBanner: false,
            theme: buildNxTheme(),
            locale: Locale(lang),
            supportedLocales: const <Locale>[Locale('fa'), Locale('en')],
            localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            routerConfig: router,
            builder: (BuildContext context, Widget? child) =>
                RepaintBoundary(key: kShotKey, child: child ?? const SizedBox.shrink()),
          ),
        ));
        await settle(tester, frames: 25);
        await shoot(tester, 'menus/${e.key}_$lang.png');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
      });
    }
  }
}
