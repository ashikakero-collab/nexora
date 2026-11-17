import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/ui2/page_turn.dart';

import '../core/profile/profile_service.dart';
import '../core/storage/local_store.dart';
import '../features/tournaments/ui/admin/tournament_manage_page.dart';
import '../features/tournaments/ui/admin/tournament_wizard_page.dart';
import '../features/tournaments/ui/tournament_detail_page.dart';
import '../features/tournaments/ui/tournament_inbox_page.dart';
import '../features/tournaments/ui/tournaments_page.dart';
import '../worlds/arcade/arcade_page.dart';
import '../worlds/arcade/game_setup_page.dart';
import '../worlds/arcade/online/leaderboard_page.dart';
import '../worlds/arcade/online/online_lobby_page.dart';
import '../worlds/hub/hub_page.dart';
import '../worlds/intro/intro_video_page.dart';
import '../worlds/nexora_exchange/exchange_page.dart';
import '../worlds/nova_gallery/nova_gallery_page.dart';
import '../worlds/onboarding/onboarding_page.dart';
import '../worlds/oracle_core/oracle_core_page.dart';
import '../worlds/orbit_network/orbit_network_page.dart';
import '../worlds/orbit_network/ui/orbit_call_page.dart';
import '../worlds/personal_orbit/personal_orbit_page.dart';
import '../worlds/settings/account_page.dart';
import '../worlds/settings/settings_page.dart';
import '../worlds/rooms/rooms_page.dart';
import '../worlds/social_hub/social_hub_page.dart';
import '../worlds/personal_orbit/rewards_page.dart';
import '../worlds/social_station/social_station_page.dart';

GoRouter buildRouter(WidgetRef ref) {
  final profile = ref.read(profileProvider);
  final String next;
  if (!profile.hasIdentity) {
    next = '/onboarding';
  } else {
    next = '/hub';
  }
  // Every launch opens with the owner's intro video, then continues to [next].
  final String initial = Uri(path: '/intro', queryParameters: <String, String>{'next': next}).toString();

  return GoRouter(
    initialLocation: initial,
    // Deep link nexora://t/<code> (Android may deliver only the path "/<code>").
    redirect: (BuildContext context, GoRouterState state) {
      final Uri u = state.uri;
      if (u.scheme == 'nexora' && u.host == 't') {
        return '/tournaments/join?code=${u.pathSegments.isNotEmpty ? u.pathSegments.first : ''}';
      }
      final RegExpMatch? m = RegExp(r'^/([A-HJ-NP-Za-hj-np-z2-9]{8})$').firstMatch(u.path);
      if (m != null && u.path != '/settings' && u.path != '/intro') {
        return '/tournaments/join?code=${m.group(1)!.toUpperCase()}';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/intro',
        pageBuilder: (context, state) => _fade(
          state,
          IntroVideoPage(next: state.uri.queryParameters['next'] ?? '/hub'),
        ),
      ),
      GoRoute(path: '/onboarding', pageBuilder: (context, state) => _fade(state, const OnboardingPage())),
      GoRoute(path: '/hub', pageBuilder: (context, state) => _fade(state, const HubPage())),
      GoRoute(path: '/rooms', pageBuilder: (context, state) => _warp(state, const RoomsPage())),
      GoRoute(path: '/social', pageBuilder: (context, state) => _warp(state, const SocialHubPage())),
      GoRoute(path: '/rewards', pageBuilder: (context, state) => _warp(state, const RewardsPage())),
      GoRoute(path: '/settings', builder: (context, state) => const SettingsPage()),
      GoRoute(path: '/account', builder: (context, state) => const AccountPage()),
      GoRoute(
        path: '/oracle',
        pageBuilder: (context, state) => _warp(
          state,
          _WorldVisit(id: 'oracle_core', child: OracleCorePage(initialQuery: state.uri.queryParameters['q'])),
        ),
      ),
      GoRoute(
        path: '/world/:id',
        pageBuilder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          return _warp(state, _WorldVisit(id: id, child: _worldPage(id)));
        },
      ),
      GoRoute(
        path: '/online/:gameId',
        builder: (context, state) => OnlineLobbyPage(
          gameId: state.pathParameters['gameId'] ?? '',
          joinCode: state.uri.queryParameters['code'],
          roomId: state.uri.queryParameters['room'],
          action: state.uri.queryParameters['action'],
        ),
      ),
      GoRoute(
        path: '/call/:chatId',
        builder: (context, state) => OrbitCallPage(
          chatId: state.pathParameters['chatId'] ?? '',
          callId: state.uri.queryParameters['call'],
          video: state.uri.queryParameters['video'] == '1',
          title: state.uri.queryParameters['title'] ?? 'NEXORA',
          startNew: false,
        ),
      ),
      GoRoute(
        path: '/leaderboard',
        builder: (context, state) => LeaderboardPage(initialGame: state.uri.queryParameters['game']),
      ),
      GoRoute(
        path: '/tournaments',
        builder: (context, state) => TournamentsPage(game: state.uri.queryParameters['game']),
      ),
      GoRoute(path: '/tournaments/new', builder: (context, state) => const TournamentWizardPage()),
      GoRoute(path: '/tournaments/inbox', builder: (context, state) => const TournamentInboxPage()),
      GoRoute(
        path: '/tournaments/join',
        builder: (context, state) => TournamentsPage(joinCode: state.uri.queryParameters['code']),
      ),
      GoRoute(
        path: '/t/:code',
        builder: (context, state) => TournamentsPage(joinCode: state.pathParameters['code']),
      ),
      GoRoute(
        path: '/tournaments/:id',
        builder: (context, state) => TournamentDetailPage(
          id: state.pathParameters['id'] ?? '',
          focusMatch: state.uri.queryParameters['match'],
        ),
      ),
      GoRoute(
        path: '/tournaments/:id/manage',
        builder: (context, state) => TournamentManagePage(id: state.pathParameters['id'] ?? ''),
      ),
      GoRoute(
        path: '/tournaments/:id/edit',
        builder: (context, state) => TournamentWizardPage(editId: state.pathParameters['id']),
      ),
      GoRoute(
        path: '/arcade/:gameId',
        builder: (context, state) => GameSetupPage(gameId: state.pathParameters['gameId'] ?? ''),
      ),
    ],
    errorBuilder: (context, state) => const HubPage(),
  );
}

Widget _worldPage(String id) {
  switch (id) {
    case 'nova_gallery':
      return const NovaGalleryPage();
    case 'orbit_network':
      return const OrbitNetworkPage();
    case 'nexora_arcade':
      return const ArcadePage();
    case 'oracle_core':
      return const OracleCorePage();
    case 'personal_orbit':
      return const PersonalOrbitPage();
    case 'social_station':
      return const SocialStationPage();
    case 'nexora_exchange':
      return const ExchangePage();
    default:
      return const HubPage();
  }
}

CustomTransitionPage<void> _fade(GoRouterState state, Widget child) => CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 450),
      transitionsBuilder: (context, animation, secondary, child) =>
          FadeTransition(opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut), child: child),
    );

/// Paper page-turn into a world (see NxPageTurn). Reduced motion -> plain fade.
CustomTransitionPage<void> _warp(GoRouterState state, Widget child) => CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 620),
      reverseTransitionDuration: const Duration(milliseconds: 420),
      transitionsBuilder: (context, animation, secondary, child) =>
          NxPageTurn(animation: animation, secondary: secondary, child: child),
    );

/// Records the first visit to each world (for the World Traveler achievement).
class _WorldVisit extends ConsumerStatefulWidget {
  const _WorldVisit({required this.id, required this.child});
  final String id;
  final Widget child;

  @override
  ConsumerState<_WorldVisit> createState() => _WorldVisitState();
}

class _WorldVisitState extends ConsumerState<_WorldVisit> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final store = LocalStore.instance;
      final visited = (store.getJsonList('hub.visited') ?? const []).map((e) => '$e').toSet();
      if (visited.add(widget.id)) {
        store.setJson('hub.visited', visited.toList());
        final p = ref.read(profileProvider);
        p.bump('worlds.visited');
        p.award('world.first_visit.${widget.id}', xp: 20, coins: 10);
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
