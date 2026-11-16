# PROGRESS (branch `nxg`)

## Online foundation (M1) — done
- Supabase project `eisstodgncimypdawisy` (shared with the other NEXORA app: same `auth.users` + `profiles`).
- New schema under `nx_` prefix: `supabase/migrations/20261115000000_nx_core.sql` (+ `_100_nx_fk_profiles.sql`), RLS on every table. Applied live.
- `lib/core/online/`: `online_service.dart` (guest = anonymous auth, upgrade to email+password keeps the uid; sign in / out),
  `cloud_profile_sync.dart` (server owns XP/coins via `nx_award` / `nx_purchase` — idempotent, daily cap 3000 XP;
  inventory/achievements/stats/decor in `nx_profiles.data`; offline queue flushes on reconnect), `SupabaseBackend` implements `BackendGateway`.
- Account page: Settings → Account (`/account`). Offline builds (no dart-define) behave exactly as before.

## Online multiplayer (M2) — all 9 games wired
- Model: every phone runs the same pure-Dart core with the same seed; players exchange inputs only. The DB (`nx_push_move`, seq = last+1,
  first writer wins) is the single ordered log → identical order everywhere. Reconnect/resync = rebuild the game and replay the log instantly.
  Pre-move state hashes are verified (`NetLink.verify`).
- Physics (finger soccer, carrom, billiards): shot input relayed, identical deterministic sim, the authority (lowest connected seat) posts a full
  snapshot after every shot; non-authority waits for it (≤3.5 s) before the next aim. Physics/tuning untouched.
- Lobby (`OnlineLobbyPage`): quick match, private/public room by code, open rooms, ready/start, invite friends (`nx_invites`, real-time banner),
  presence dots, forfeit on leave, absent players auto-forfeited by the authority (40 s on their turn / 90 s otherwise).
- Results: `nx_finish_match` → `nx_match_results`, `nx_game_stats` (rating ±), XP/coins; `/leaderboard` (per game + global XP).
- Seat 1 sees finger soccer / carrom rotated 180° (own side at the bottom).
- Mafia online: 6–10 players, seeded roles on every phone, UI shows only what that player may know (roles are hidden by the client UI, not
  cryptographically — a modified client could read them).

## Social worlds (M3) — real when signed in (online build + session); device-only otherwise
Schema: `supabase/migrations/20261115000200_nx_social.sql` (applied live). Only `nx_` tables + a `nx-media` bucket with
`nx_media_*` policies on storage.objects; nothing of the other app is changed. Friends reuse the shared `follows` /
`friend_requests` RPCs (same friendships in both apps). No seeded/fake users or content is shown online.
- **Orbit Network** (`SupabaseOrbitRepository`): 1:1 (`nx_open_direct`), groups, channels (only owner/admins post — enforced
  in `nx_send_message`), members + roles, add friends, leave/delete, edit/delete/pin (RPCs), per-user stars, read receipts
  (members' `last_read_at`), unread counts (`nx_my_chats`), server search, Realtime (`nx_messages`, `nx_chat_members`,
  `nx_calls`). Offline: last server copy stays visible, sends are queued in LocalStore and flushed on the next refresh.
  Saved Orbit and chats created offline stay on the device. Contacts tab = friends with presence, requests (accept/decline/
  cancel), username search, message/call/remove. Game invites in an online chat create a real private room and the card
  joins it (`/online/<game>?code=`).
- **Calls (M4)**: Edge Function `nx-call-token` (source `supabase/functions/nx-call-token`, verify_jwt) — only members of the
  chat get a 15-min LiveKit token for room `nxg-call-<chat id>` (channel listeners can't publish). `OrbitCallPage` (livekit_client):
  voice/video/group, mute/camera/speaker, speaking glow. `nx_start_call` logs the call + a call message; `CallWatcher` rings
  anywhere in the app (snackbar → `/call/:chatId`). Calls tab = real history.
- **Nova Gallery** (`SupabaseNovaRepository`): posts, 24 h stories (+ views), likes, comments, saves, notifications (likes/comments
  by others, via triggers), hashtags (derived server-side), `#tag` / `@user` / text search, trending, photo posts uploaded to
  `nx-media/<uid>/…` (RLS: write only your own folder; public read), follow / followers on `follows`. My uid is shown to the UI
  as the explorer id so ownership checks keep working.
- **Social Station** (`SupabaseSocialRepository`): `nx_communities` (document + version) + `nx_community_members` (real roles).
  `nx_community_save` refuses stale versions (client re-applies the change, ≤3 tries) and keeps only what the caller's role may
  change (member: posts + events/RSVP; moderator: + tournaments/local players; admin/owner: all). Role change / kick / delete /
  join-by-code / join-public / leave are role-checked RPCs. Discover sheet lists public communities.
  Known limit: within the parts a role may edit, a modified client could rewrite others' posts (no per-post server check).

## ORACLE remote (M5)
- `RemoteOracleEngine` → existing `oracle-chat` Edge Function (unchanged). Contract: POST `{messages, ctx}` with the user JWT →
  `{message:{content, tool_calls?}}`. Its tools belong to the other app: the client answers them with
  `not_available_in_this_app` once and asks again. App-aware intents (navigation, settings, rules, stats…) stay on the offline
  brain; open conversation goes online; any error → offline reply.
- As of 2026-11-15 the function's LLM provider (apinex.bond) answers 402 "insufficient balance / daily check-in", so ORACLE
  currently always falls back to the offline brain. Topping up that provider (or setting another key in its config) turns it on
  with no app change.

## Remaining / next
- Media in Orbit chats (photos/voice notes) — Nova photo upload exists and can be reused.
- Push notifications for messages/calls when the app is closed (calls ring only while the app is open).
- ORACLE voice (the notice stays; `oracle-chat` supports audio but needs the provider balance first).
- No device testing possible from the build agent: SQL/RPC/RLS/Storage/Edge Functions verified live with guest accounts
  (test data removed); UI verified by analyzer + CI build.

## Tournaments (M6) — `lib/features/tournaments` + `supabase/migrations/20261116000*_nx_tournaments*.sql`
No extra server: everything runs in the existing Supabase project (Postgres RPCs + RLS + pg_cron + Realtime).
- **Roles (RBAC in Postgres)**: admin (`nx_staff.role='admin'` or the shared `is_admin()`), organizer (`nx_staff.role='organizer'`),
  per-tournament runner (`nx_t_staff`), player. Tables are read-only for clients (RLS); every write is a role-checked
  SECURITY DEFINER RPC (`nx_t_save`, `nx_t_admin`, `nx_t_register`, `nx_t_join_code`, `nx_t_withdraw`, `nx_t_decide`,
  `nx_t_remove_entry`, `nx_t_set_seed`, `nx_t_code_create/revoke`, `nx_t_ready`, `nx_t_report`, `nx_t_dispute`,
  `nx_t_admin_match`, `nx_t_set_staff`, `nx_t_set_runner`, `nx_t_standings`, `nx_t_logs`). Engine functions `_nx_t_*` and
  `nx_t_tick` are not executable by clients. Only admins can set fixed (minted) prizes.
- **Formats** (2–64 players, automatic byes): single elimination (+3rd place), double elimination (grand final + reset),
  two legs (aggregate, optional single-leg final), round robin (single/double), groups → knockout (snake groups, configurable
  groups/advancers, A1-vs-other-group seeding), swiss (N rounds, no rematches while avoidable, rotating bye), custom (organizer adds
  matches). Best-of per round kind (early / semis / final: Bo1/2/3/5). Knockout draws: finger soccer (BERMUDA port) already ends ties
  with its own golden goal; if any game still reports a draw, the server opens a decider game (`settings.golden_goal`) and after
  4 extra games the better seed advances. Leagues award draw points.
- **Registration**: open / approval / code / code+approval; 8-char codes (no 0/O/1/I) with max uses, expiry, revoke,
  requires-approval; deep link `nexora://t/<code>`; 5 wrong codes per 15 min per account. Min level / XP / rating, entry fee in
  coins and gems (escrowed in the tournament row + immutable `nx_t_ledger`), waitlist with automatic promotion, withdraw with
  refund before registration closes, one registration per account.
- **Scheduler**: pg_cron job `nx_t_tick` every minute: idempotent `nx_t_jobs` (open/close registration, draw, start, 10-minute
  reminders), ready checks (default 5 min) → both ready creates the private room + online match through the same
  `nx_rooms`/`nx_matches` the lobby uses (settings.tmatch), no-shows → walkover (double no-show: better seed in knockouts, void in
  leagues), 60 s reconnect grace (`settings.grace_sec` in `SupabaseMatchLink`), result acceptance, finish + payout.
- **Results**: only server-side. Forfeits are server facts; normal ends need both players' `nx_t_report` to agree (one report +
  90 s silence, or the server row alone after 3 min, is accepted); disagreement → dispute; organizer fixes or replays with an
  audit trail (`nx_t_audit`, append-only). Corrections re-seat downstream players if the next match has not started.
- **Prizes**: fixed + pool % of entry fees − house fee %, split by place percentages (shared places split, remainder to the champion),
  paid once in one transaction with idempotency keys (`payout:<t>:<user>:<currency>`). Cancel = full refund.
- **Notifications**: `nx_t_notifications` (in-app inbox + Realtime banner) for approved/rejected/waitlist/promoted, drawn, starting
  soon, match soon, match ready, result, advanced/eliminated, walkover, dispute, prize, time changed, cancelled, refund. No FCM in
  this app → device notifications via flutter_local_notifications (shown when a notification arrives in the background, and the
  10-minute reminders are scheduled on the device so they fire with the app closed).
- **UI**: Tournaments (tabs registering/upcoming/live/finished/mine, filters, countdowns), detail (overview, prize pool, rules,
  schedule local + UTC, register/code/withdraw, my next match with READY, live bracket with pan/zoom, league tables, matches,
  players), inbox, organizer wizard (info → format → times → match rules → prizes → registration/codes → review/publish) and
  manage panel (controls, approvals, players/seeds, codes, match tools, logs/jobs/ledger, staff). Entry points: Hub quick row
  (Cups), Arcade, and the game setup page of every 1-vs-1 online game (incl. finger soccer).
- Verified live against the project with guest accounts (SE/DE/two legs/RR/groups/swiss/custom paths, byes, golden-goal cap,
  codes + rate limit, approvals, waitlist, refunds, cancel, payout maths, disputes, admin correction, forfeits, cron-driven run,
  RLS from the REST API). Pure-Dart mirror + tests: `test/features/tournaments/bracket_test.dart`.
