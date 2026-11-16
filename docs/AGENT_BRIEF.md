# NEXORA build brief for sub-agents (read fully)

Project root: /workspace/work/nexora  (Flutter Android app, package name `nexora`, import as `package:nexora/...`).
Product vision (MUST read): docs/kit/01_VISION_AND_CONTEXT.md. Steps for your part: docs/kit/steps/STEP_xx.md. Assets guide: docs/kit/03_ASSET_GUIDE.md.

## Goal of this build
A complete OFFLINE version of NEXORA: every world and every game must truly work on one device with no server
(local-first storage, offline AI bots, same-device multiplayer). Online (Supabase/LiveKit) is wired later by the owner, so
keep logic in pure-Dart cores that could later run server-side, and where something genuinely needs the internet
(calls, real other users), show an honest notice (`OnlineOnlyNotice` widget) instead of faking it. Nothing fake.
Quality bar: premium, cosmic, futuristic, juicy (animations, glow, particles when `fancyEffects`), not a basic prototype.
Persian (fa, RTL) is default UI language, English supported: every user-visible string bilingual.

## Toolchain (IMPORTANT: there is NO Flutter/Dart compiler in this sandbox)
CI compiles with Flutter 3.27.1 stable (Dart 3.6). Allowed packages ONLY: flutter, flutter_riverpod ^2.6.1, go_router ^14.6.2,
shared_preferences ^2.3.3, flame ^1.22.0, flutter_test. No other packages, no code generation.
Because you cannot compile, write conservative, explicitly-typed, null-safe Dart. Double-check every import, every API
signature, every `const` usage, every switch exhaustiveness, every override signature. Avoid APIs newer than Flutter 3.27.
`Color.withValues(alpha: x)` is OK (or withOpacity). Do not use records/patterns in ways you are unsure about. No `part` files.
Keep each file < ~900 lines. Run `node`/python only for your own sanity checks if useful.
`flutter analyze` must have no errors (warnings tolerated but avoid unused imports/variables).

## Core APIs you can use (already written, do NOT modify these files)
- lib/core/theme/nx_theme.dart: `NxColors` (navy, electricBlue, violet, iceWhite, turquoise, gold, pink, danger, success, glass, glassBorder, textDim), `WorldPalette` (hub, nova, orbit, arcade, oracle, personal(light), social, exchange; fields primary, secondary, background(List<Color>), light), `NxSpace`, `NxRadius`, `NxMotion`.
- lib/core/settings/app_settings.dart: `settingsProvider` (ChangeNotifierProvider<AppSettings>: quality, reducedMotion, isFa, fancyEffects, starCount, sound, haptics) and extension `context.tx('فارسی', 'English')` / `context.isFa`.
- lib/core/profile/profile_service.dart: `profileProvider` (ChangeNotifierProvider<ProfileService>). Fields: explorerId, username, bio, avatarCore, xp, coins, level, levelProgress, rankTitleFa/En, equipped (Map slot->itemId), inventory (Set), achievements (Set ids), stats (Map gameId->GameStats played/won/lost/draw/best), activity (List<ActivityEntry> at/kind/textFa/textEn/xp), counters, decorLayout (Map decorId->{x,y,s}), orbitTheme, streak, canClaimDaily, createdAt.
  Methods: `award(event, xp:, coins:, fa:, en:) -> AwardOutcome`, `bump(counter,[by])` (call notify via award/logActivity), `counter(key)`, `recordGame(...)` (host does this, games don't), `purchase(itemId, price, nameFa:, nameEn:) -> bool`, `grantItem`, `equip(slot,itemId)`, `unequip(slot)`, `owns(id)`, `setOrbitTheme`, `placeDecor(id,x,y,scale)`, `removeDecor(id)`, `logActivity(kind, fa, en)`, `updateProfile(name:, newBio:)`, `claimDaily()`, `resetAll()`.
  Achievement counters to bump: 'nova.posts', 'orbit.sent', 'social.joined', 'oracle.asked', 'worlds.visited'(host does).
- lib/core/profile/achievements.dart: `kAchievements` list of AchievementDef(id, asset, nameFa/En, descFa/En, coinReward).
- lib/core/catalog/catalog.dart: `kCatalog` (CatalogItem id, category ItemCategory{avatarGear, decor, puck, striker, cue, theme, frame, badge}, nameFa/En, price, asset path ('' => draw procedurally), slot, minLevel, rarity) and `catalogItem(id)`.
- lib/core/storage/local_store.dart: `LocalStore.instance` with getJson/setJson/getJsonList/getString/setString/getBool/setBool/getInt/setInt/remove. Prefix your keys with your module id.
- lib/core/assets/app_assets.dart: `AppAssets` constants for every asset (generated: e.g. AppAssets.gamesCarromBoardNxBlackGold) + helpers portal(id), pedestal(gameId), gear(id), decor(id), achievement(id), clubBadge(id), oraclePose(pose), disc(id), puckTop(skin)/puckIso/puckThumb (skin WITHOUT 'puck_' prefix). Never hardcode raw asset paths. Decode images with cacheWidth/cacheHeight.
- lib/core/widgets/nx_widgets.dart: `NxBackground(palette:, child:)` animated starfield, `GlassPanel(child:, padding:, radius:, tint:, borderColor:, onTap:)`, `NxPill(label:, icon:, color:)`, `WalletChip()`, `XpBar()`, `NxWorldScaffold(title:, palette:, body:, actions:, floatingActionButton:, bottomNavigationBar:)`, `OracleAvatar(pose:, size:)`, `showAwardOutcome(context, outcome)`, `OnlineOnlyNotice(featureFa:, featureEn:)`.
- Navigation (go_router): `context.push('/world/<worldId>')`, `context.push('/arcade/<gameId>')` (opens game setup), `context.push('/settings')`, `context.go('/hub')`, `context.push('/oracle?q=<text>')`. World ids: nova_gallery, orbit_network, nexora_arcade, oracle_core, personal_orbit, social_station, nexora_exchange. Game ids: finger_soccer, carrom, billiards, backgammon, ludo, snakes_ladders, uno, quiz, mafia.

## Games contract (lib/games/core/game_contract.dart — read it)
Entry: `Widget buildXxxGame(GameLaunch launch)` in lib/games/<id>/<id>_entry.dart. Pure rules in lib/games/<id>/core/ (no Flutter imports),
render/UI in lib/games/<id>/ui/. The host page (not you) provides the Scaffold, exit button (top-start 56px corner — keep it free),
result screen, XP and rematch. Your widget fills the whole screen (use your own background), handles both `GameMode.vsBot`
(AI with BotDifficulty easy/normal/hard, AI thinks with a small natural delay) and `GameMode.local` (pass-and-play), uses
`launch.playerCount` where the game supports >2 seats, respects `launch.fancyEffects` / `reducedMotion`, uses `launch.tx(fa,en)`
for text, and calls `launch.onFinish(GameResult(outcome:, score:, opponentScore:, summaryFa:, summaryEn:))` exactly once.
Wrap board geometry in `Directionality(textDirection: TextDirection.ltr, ...)` so RTL doesn't mirror boards.
Sound: none required (no audio packages); use HapticFeedback from flutter/services if `launch.soundOn` for impact feel.
Unit tests: test/games/<id>_test.dart using `package:flutter_test/flutter_test.dart`, testing the pure core (rules, bot legal moves, win detection).

## When done
Reply with: files created, entry function / class names, what is fully working, any known risk spots in the code you are unsure compile.
Do not edit files outside your assigned folders (and your test files).
