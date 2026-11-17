# NX2 redesign (branch `online-redesign`)

New cosmic-neon game UI built from the owner's art (30 reference images + batch2).

## Kit
- `assets/ui/nx2/` — sliced, transparent WebP assets (q≈85, ≤1024 px): `bars/`, `frames/` (panels, buttons,
  rings, banners, tiles, dock platform, crystal border), `badges/` (medals, rank badges, trophies), `chests/`
  (standard/rare/epic/legendary, closed/open), `tiles/` (shop/settings/inventory/ranking/formation/item/disc/ball),
  `oracle/` (blue robot moods + orange soccer robot frames), `bg/` (main + room backgrounds, hero planet),
  `boards/` (carrom/billiards/backgammon table art, for the game-skin milestone).
- Paths: `lib/core/ui2/nx2_assets.dart` (generated). Widgets: `lib/core/ui2/nx2_widgets.dart`
  (`Nx2Background`, `Nx2Panel`, `Nx2Button` (9-slice art), `Nx2Banner`, `Nx2AvatarRing`, `Nx2Progress`,
  `Nx2Stat`, `Nx2Tile`, `Nx2SectionHeader`, `Nx2Dock`, `Nx2TopBar`, `Nx2Bubble`).
- The shared `NxBrandBackground`, `GlassPanel`, `NxPill`, `WalletChip`, `XpBar`, `NxWorldScaffold` and
  `OracleAvatar` now render the NX2 look, so every page that used them is re-skinned. The old Gold/Neon
  theme switch is removed; the app always uses the NX2 cosmic neon theme.

## ORACLE mascot
`lib/core/ui2/oracle_mascot.dart`: `OracleMascot(mood:)` — float/bob, blink, glow pulse, head tilt,
moods (idle, greet, happy, think, error, win, play, curious, …), tap reactions (giggle → spin → wink).
`OracleMischief` peeks in from the screen edge or pokes the coin counter now and then (off with reduced motion).

## Music + intro
- `lib/core/audio/music_service.dart`: loops `assets/media/bgm_main.ogg` on menus, fades out while a game
  (`GameHostPage`, `OnlineMatchPage`) is open, pauses in background. Settings → Sound & music (on/off + volume).
- `lib/worlds/intro/intro_video_page.dart`: `assets/media/intro_app.mp4` full screen (cover) with its own
  sound on every launch, Skip after 1 s, then the normal start route; music starts after it.

Gameplay (physics, boards, rules) is untouched in this milestone.

# redesign-v1.1

## App shell
- Old first-launch "journey" intro (lib/worlds/journey, its route, settings/hub/search entries, the cruiser ship and
  command-desk art) removed. Launch = `intro_app.mp4` (Skip after 1 s) -> onboarding (first run) or Home.
- Fonts (bundled, OFL): Chakra Petch (Latin/digits, HUD), Estedad (Persian body), Lalezar (Persian headings), wired via
  `nxGameTextTheme` (fontFamilyFallback). Persian glyphs fall back from Chakra Petch to Estedad/Lalezar.
- Dock: CHAT+MEDIA, ORACLE | big raised GAME button (centre) | SHOP, TOURNAMENTS, REWARDS & PACKS.
  GAME -> `/rooms`, CHAT+MEDIA -> `/social` (Feed & stories / Messages / Friends tabs), REWARDS -> `/rewards`.
- Page transitions: paper page-turn (`lib/core/ui2/page_turn.dart`) for world routes and every MaterialPageRoute.
- Rooms (`/rooms`): real open rooms from `nx_rooms` (all games), Quick Play / New Room pick a game and open its lobby
  with `?action=quick|create` (real `nx_quick` / `nx_create_room`), offline state points to the offline arcade.
- `nova_seed.dart` (local "NEXORA Official" tip posts + welcome notification) removed; old copies are purged once.
- Backgrounds `bg_main.webp` / `bg_room.webp` replaced with the batch3 art.

## Game boards (art fitted to the existing geometry; physics untouched)
Shared helper `lib/core/ui2/nx2_board_art.dart` (`Nx2ArtMap` knot maps: art coordinate -> geometry coordinate,
piecewise-linear, optional quarter turn). In-game board button (`Nx2BoardButton`) cycles boards, saved per game.
- Carrom: wood / black-green / silver NX2 boards + classic black-gold, fitted by the 4 pocket centres.
- Billiards: NX2 neon green + neon orange (landscape art turned 90°; knots on corner + side pockets) + classic.
- Backgammon: NX2 walnut + silver (knots on all 24 triangle tips, field edges, hinge = bar; frame strips redrawn with
  their own map so the plaques keep their shape) + classic black-gold.
- Snakes & Ladders: NX2 dragon board frame + art-style cells (the supplied art has 11 rows and repeated numbers, so
  its grid cannot be used as-is; the 10x10 squares/numbers are drawn in code at `SnlGeom` positions) + neon classic.
- Render checks: `test_render/games_render_test.dart` (`--dart-define=DBG=true` overlays cushions/pockets/points).

## Mini-soccer physics exception (owner request)
`lib/games/finger_soccer/core/bm_engine.dart`:
- Ball mass `1.9` -> `BALL_M = 1.805` (x0.95).
- `BKICK = 1.05 * ((1/1.9)/(1/5+1/1.9)) / ((1/1.805)/(1/5+1/1.805)) = 1.035543…` multiplies the ball's share of a
  disc->ball impulse (only when the disc is the faster body). Net effect: a disc striking the ball launches it exactly
  5% faster than before (lighter mass alone +1.396%). Restitution, friction, damping, discs unchanged.
