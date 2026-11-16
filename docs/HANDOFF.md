# HANDOFF
- Contract for games: `lib/games/core/game_contract.dart`; registry `lib/games/game_registry.dart`.
- Worlds registry: `lib/worlds/world_registry.dart`; routes in `lib/app/router.dart` (`/world/<id>`, `/arcade/<gameId>`, `/oracle?q=`).
- Progress events: `ProfileService.award(event, xp, coins)`, counters `nova.posts`, `orbit.sent`, `social.joined`, `oracle.asked`, `worlds.visited`, `shop.bought`, `games.played`, `games.won`.
- Going online: see `docs/ONLINE_SETUP.md`.
