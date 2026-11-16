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
