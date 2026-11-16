# DECISIONS

| # | Decision | Why | Param |
|---|---|---|---|
| D1 | Offline-first full build: every world/game runs locally; online seams via `BackendGateway` and per-world `Repository` interfaces | Owner asked for a complete offline version to put online later | P17, P22 |
| D2 | Local storage = `shared_preferences` JSON (`LocalStore`) instead of Drift/Isar | No code generation available in the build pipeline; data volume is small; keys are namespaced so a Drift migration is mechanical | P22 (deviation) |
| D3 | Repo `Ashkani25/NXG` master replaced by NEXORA; old Disc Football kept on branch `backup-disc-football-2026-11-11` | Owner: "کامل پاک کن، جدید بساز" | — |
| D4 | Android platform folder generated in CI (`flutter create`) with branding/icon copied from `branding/` | No local Flutter SDK; keeps repo small | P02, P29 |
| D5 | Flutter pinned to 3.27.1 in CI | Reproducible builds | P01 |
| D6 | Games may render with Ticker+CustomPainter instead of Flame | Full control of deterministic loop; Flame stays available | P08 (allowed variant) |
| D7 | UNO renamed in UI to "NX Cards (UNO-style)", id stays `uno` | Trademark | P30 |
| D8 | Licensed national pucks never used; only original skins | Licensing | P30 |
| D9 | XP daily cap 3000 locally, mirrored by `award_xp()` SQL | Anti-farm; server will be authoritative online | P21 |
| D10 | Asset paths generated into `AppAssets` from `assets/` | Kit layout differs from earlier menu code | — |
