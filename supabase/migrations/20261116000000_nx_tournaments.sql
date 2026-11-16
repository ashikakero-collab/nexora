-- NEXORA (Flutter, branch nxg) · Tournaments — schema + RLS.
-- Everything lives under nx_staff / nx_tournaments / nx_t_* (the other NEXORA app's tournaments/cups tables are untouched).
-- Roles: admin (nx_staff.role='admin' or the shared is_admin()), organizer (nx_staff.role='organizer'), per-tournament
-- runners (nx_t_staff), players (everyone signed in). All writes go through SECURITY DEFINER RPCs (next migrations);
-- tables only expose SELECT policies, so a modified client can read what it may see and change nothing directly.
-- All times are timestamptz (UTC on the wire). Idempotent: safe to re-run.

create table if not exists public.nx_staff (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('admin', 'organizer')),
  granted_by uuid,
  granted_at timestamptz not null default now()
);

create table if not exists public.nx_tournaments (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(title) between 3 and 80),
  description text not null default '',
  rules text not null default '',
  game text not null default 'finger_soccer',
  created_by uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'draft'
    check (status in ('draft', 'scheduled', 'registering', 'closed', 'drawn', 'live', 'finished', 'cancelled')),
  paused boolean not null default false,
  format text not null
    check (format in ('single_elim', 'double_elim', 'two_legs', 'round_robin', 'groups_ko', 'swiss', 'custom')),
  capacity int not null check (capacity between 2 and 64),
  min_players int not null default 2 check (min_players >= 2),
  -- {bo_early, bo_semi, bo_final, third_place, rr_double, groups, advance, swiss_rounds, points_win, points_draw,
  --  ready_seconds, round_minutes, round_starts[], final_one_leg, max_game_minutes, golden_goal}
  config jsonb not null default '{}'::jsonb,
  reg_mode text not null default 'open' check (reg_mode in ('open', 'approval', 'code', 'code_approval')),
  min_level int not null default 0,
  min_xp int not null default 0,
  min_rating int not null default 0,
  fee_coins int not null default 0 check (fee_coins between 0 and 1000000),
  fee_gems int not null default 0 check (fee_gems between 0 and 100000),
  -- {fixed_coins, fixed_gems, pool_pct, fee_pct, dist:[percent per place]}
  prize jsonb not null default '{}'::jsonb,
  reg_open_at timestamptz not null,
  reg_close_at timestamptz not null,
  draw_at timestamptz not null,
  start_at timestamptz not null,
  seeding text not null default 'random' check (seeding in ('random', 'rating', 'manual')),
  seed bigint,
  stage text not null default 'main' check (stage in ('main', 'groups', 'ko')),
  escrow_coins int not null default 0 check (escrow_coins >= 0),
  escrow_gems int not null default 0 check (escrow_gems >= 0),
  paid_out boolean not null default false,
  cancel_reason text,
  winner uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  published_at timestamptz,
  drawn_at timestamptz,
  started_at timestamptz,
  finished_at timestamptz,
  constraint nx_t_times check (reg_open_at < reg_close_at and reg_close_at <= draw_at and draw_at <= start_at)
);
create index if not exists nx_tournaments_status on public.nx_tournaments(status, start_at);

-- Per-tournament runners (besides the creator).
create table if not exists public.nx_t_staff (
  tournament_id uuid not null references public.nx_tournaments(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  added_by uuid,
  created_at timestamptz not null default now(),
  primary key (tournament_id, user_id)
);

create table if not exists public.nx_t_codes (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references public.nx_tournaments(id) on delete cascade,
  code text not null unique check (code ~ '^[A-HJ-NP-Z2-9]{8}$'),
  max_uses int not null default 1 check (max_uses between 1 and 1000),
  uses int not null default 0,
  expires_at timestamptz,
  revoked boolean not null default false,
  requires_approval boolean not null default false,
  created_by uuid,
  created_at timestamptz not null default now()
);
create index if not exists nx_t_codes_t on public.nx_t_codes(tournament_id);

-- Wrong-code attempts (rate limit: 5 wrong per 15 minutes per account).
create table if not exists public.nx_t_code_attempts (
  id bigserial primary key,
  user_id uuid not null,
  code text not null,
  ok boolean not null,
  created_at timestamptz not null default now()
);
create index if not exists nx_t_code_attempts_user on public.nx_t_code_attempts(user_id, created_at desc);

create table if not exists public.nx_t_entries (
  tournament_id uuid not null references public.nx_tournaments(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  status text not null check (status in ('pending', 'approved', 'rejected', 'waitlist', 'withdrawn', 'removed')),
  seed int,
  group_no int,
  rating int not null default 1000,
  paid_coins int not null default 0,
  paid_gems int not null default 0,
  fee_ref bigint,
  code_id uuid,
  note text,
  place int,
  decided_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (tournament_id, user_id)
);
create index if not exists nx_t_entries_user on public.nx_t_entries(user_id, created_at desc);

create table if not exists public.nx_t_matches (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references public.nx_tournaments(id) on delete cascade,
  stage text not null default 'main',
  bracket text not null check (bracket in ('W', 'L', 'GF', 'GF2', 'P3', 'RR', 'G', 'SW', 'C')),
  round int not null,
  idx int not null default 0,
  tslot int not null default 1,
  group_no int,
  label text,
  p1 uuid references public.profiles(id) on delete set null,
  p2 uuid references public.profiles(id) on delete set null,
  p1_set boolean not null default false,
  p2_set boolean not null default false,
  win_to uuid references public.nx_t_matches(id) on delete set null,
  win_slot smallint,
  lose_to uuid references public.nx_t_matches(id) on delete set null,
  lose_slot smallint,
  best_of smallint not null default 1 check (best_of in (1, 2, 3, 5)),
  aggregate boolean not null default false,
  status text not null default 'pending'
    check (status in ('pending', 'scheduled', 'ready_check', 'playing', 'done', 'walkover', 'bye', 'disputed', 'void', 'skipped')),
  scheduled_at timestamptz,
  ready_deadline timestamptz,
  p1_ready boolean not null default false,
  p2_ready boolean not null default false,
  games int not null default 0,
  w1 int not null default 0,
  w2 int not null default 0,
  g1 int not null default 0,
  g2 int not null default 0,
  winner uuid,
  loser uuid,
  is_draw boolean not null default false,
  game_match uuid,
  result_note text,
  finished_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists nx_t_matches_t on public.nx_t_matches(tournament_id, bracket, round, idx);
create index if not exists nx_t_matches_due on public.nx_t_matches(status, scheduled_at);
create index if not exists nx_t_matches_p1 on public.nx_t_matches(p1);
create index if not exists nx_t_matches_p2 on public.nx_t_matches(p2);

-- One row per online game (nx_matches) played inside a tournament match (series / legs / golden-goal deciders).
create table if not exists public.nx_t_games (
  game_match uuid primary key references public.nx_matches(id) on delete cascade,
  tmatch uuid not null references public.nx_t_matches(id) on delete cascade,
  n int not null,
  home uuid not null,
  away uuid not null,
  golden boolean not null default false,
  ended_at timestamptz,
  srv_winner uuid,
  srv_s_home int,
  srv_s_away int,
  accepted boolean not null default false,
  disputed boolean not null default false,
  winner uuid,
  s_home int,
  s_away int,
  source text,
  created_at timestamptz not null default now()
);
create index if not exists nx_t_games_tm on public.nx_t_games(tmatch, n);

-- Each player's own report of a game (both must agree, otherwise dispute).
create table if not exists public.nx_t_reports (
  game_match uuid not null references public.nx_t_games(game_match) on delete cascade,
  user_id uuid not null,
  winner uuid,
  s_home int not null,
  s_away int not null,
  created_at timestamptz not null default now(),
  primary key (game_match, user_id)
);

-- Immutable money ledger (entry fees in escrow, refunds, payouts, house fee). idem_key = never twice.
create table if not exists public.nx_t_ledger (
  id bigserial primary key,
  tournament_id uuid not null references public.nx_tournaments(id) on delete restrict,
  user_id uuid,
  kind text not null check (kind in ('entry_fee', 'refund', 'payout', 'house_fee')),
  currency text not null check (currency in ('coins', 'gems')),
  amount int not null,
  place int,
  idem_key text not null unique,
  created_at timestamptz not null default now()
);
create index if not exists nx_t_ledger_t on public.nx_t_ledger(tournament_id, created_at);
create index if not exists nx_t_ledger_user on public.nx_t_ledger(user_id, created_at desc);

create or replace function public._nx_t_ledger_immutable() returns trigger language plpgsql as $$
begin
  raise exception '% is append-only', tg_table_name;
end $$;
drop trigger if exists nx_t_ledger_immutable on public.nx_t_ledger;
create trigger nx_t_ledger_immutable before update or delete on public.nx_t_ledger
  for each row execute function public._nx_t_ledger_immutable();

create table if not exists public.nx_t_audit (
  id bigserial primary key,
  tournament_id uuid,
  actor uuid,
  action text not null,
  data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists nx_t_audit_t on public.nx_t_audit(tournament_id, created_at desc);
drop trigger if exists nx_t_audit_immutable on public.nx_t_audit;
create trigger nx_t_audit_immutable before update or delete on public.nx_t_audit
  for each row execute function public._nx_t_ledger_immutable();

create table if not exists public.nx_t_notifications (
  id bigserial primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  tournament_id uuid references public.nx_tournaments(id) on delete cascade,
  tmatch uuid,
  kind text not null,
  data jsonb not null default '{}'::jsonb,
  read boolean not null default false,
  dedup text,
  created_at timestamptz not null default now(),
  unique (user_id, dedup)
);
create index if not exists nx_t_notifications_user on public.nx_t_notifications(user_id, created_at desc);

-- Idempotent scheduled jobs (pg_cron → nx_t_tick every minute).
create table if not exists public.nx_t_jobs (
  id bigserial primary key,
  kind text not null,
  tournament_id uuid references public.nx_tournaments(id) on delete cascade,
  ref uuid,
  run_at timestamptz not null,
  done_at timestamptz,
  attempts int not null default 0,
  last_error text,
  idem_key text not null unique,
  created_at timestamptz not null default now()
);
create index if not exists nx_t_jobs_due on public.nx_t_jobs(run_at) where done_at is null;

-- ---------------------------------------------------------------------------
-- Role helpers
-- ---------------------------------------------------------------------------
create or replace function public.nx_t_is_admin(u uuid default auth.uid()) returns boolean
language plpgsql stable security definer set search_path = public as $$
begin
  if u is null then return false; end if;
  if exists (select 1 from nx_staff where user_id = u and role = 'admin') then return true; end if;
  begin
    return coalesce(is_admin(u), false);
  exception when others then
    return false;
  end;
end $$;

create or replace function public.nx_t_is_organizer(u uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = public as $$
  select u is not null and (nx_t_is_admin(u) or exists (select 1 from nx_staff where user_id = u and role = 'organizer'))
$$;

create or replace function public.nx_t_can_manage(t uuid, u uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = public as $$
  select u is not null and (
    nx_t_is_admin(u)
    or exists (select 1 from nx_tournaments x where x.id = t and x.created_by = u and nx_t_is_organizer(u))
    or exists (select 1 from nx_t_staff s where s.tournament_id = t and s.user_id = u)
  )
$$;

create or replace function public.nx_t_visible(t uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from nx_tournaments x where x.id = t and x.status <> 'draft') or nx_t_can_manage(t)
$$;

-- ---------------------------------------------------------------------------
-- RLS: read-only for clients, all writes via RPC
-- ---------------------------------------------------------------------------
alter table public.nx_staff enable row level security;
alter table public.nx_tournaments enable row level security;
alter table public.nx_t_staff enable row level security;
alter table public.nx_t_codes enable row level security;
alter table public.nx_t_code_attempts enable row level security;
alter table public.nx_t_entries enable row level security;
alter table public.nx_t_matches enable row level security;
alter table public.nx_t_games enable row level security;
alter table public.nx_t_reports enable row level security;
alter table public.nx_t_ledger enable row level security;
alter table public.nx_t_audit enable row level security;
alter table public.nx_t_notifications enable row level security;
alter table public.nx_t_jobs enable row level security;

drop policy if exists nx_staff_read on public.nx_staff;
create policy nx_staff_read on public.nx_staff for select to authenticated using (user_id = auth.uid() or nx_t_is_admin());

drop policy if exists nx_tournaments_read on public.nx_tournaments;
create policy nx_tournaments_read on public.nx_tournaments for select to authenticated
  using (status <> 'draft' or nx_t_can_manage(id));

drop policy if exists nx_t_staff_read on public.nx_t_staff;
create policy nx_t_staff_read on public.nx_t_staff for select to authenticated using (nx_t_visible(tournament_id));

drop policy if exists nx_t_codes_read on public.nx_t_codes;
create policy nx_t_codes_read on public.nx_t_codes for select to authenticated using (nx_t_can_manage(tournament_id));

drop policy if exists nx_t_entries_read on public.nx_t_entries;
create policy nx_t_entries_read on public.nx_t_entries for select to authenticated
  using (user_id = auth.uid() or (status in ('approved', 'waitlist') and nx_t_visible(tournament_id))
         or nx_t_can_manage(tournament_id));

drop policy if exists nx_t_matches_read on public.nx_t_matches;
create policy nx_t_matches_read on public.nx_t_matches for select to authenticated using (nx_t_visible(tournament_id));

drop policy if exists nx_t_games_read on public.nx_t_games;
create policy nx_t_games_read on public.nx_t_games for select to authenticated
  using (exists (select 1 from nx_t_matches m where m.id = tmatch and nx_t_visible(m.tournament_id)));

drop policy if exists nx_t_reports_read on public.nx_t_reports;
create policy nx_t_reports_read on public.nx_t_reports for select to authenticated
  using (user_id = auth.uid() or exists (select 1 from nx_t_games g join nx_t_matches m on m.id = g.tmatch
                                          where g.game_match = nx_t_reports.game_match and nx_t_can_manage(m.tournament_id)));

drop policy if exists nx_t_ledger_read on public.nx_t_ledger;
create policy nx_t_ledger_read on public.nx_t_ledger for select to authenticated
  using (user_id = auth.uid() or nx_t_can_manage(tournament_id));

drop policy if exists nx_t_audit_read on public.nx_t_audit;
create policy nx_t_audit_read on public.nx_t_audit for select to authenticated using (nx_t_can_manage(tournament_id));

drop policy if exists nx_t_notif_read on public.nx_t_notifications;
create policy nx_t_notif_read on public.nx_t_notifications for select to authenticated using (user_id = auth.uid());
drop policy if exists nx_t_notif_upd on public.nx_t_notifications;
create policy nx_t_notif_upd on public.nx_t_notifications for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists nx_t_notif_del on public.nx_t_notifications;
create policy nx_t_notif_del on public.nx_t_notifications for delete to authenticated using (user_id = auth.uid());

-- Clients may only flip `read` on their own notifications.
create or replace function public._nx_t_notif_guard() returns trigger language plpgsql as $$
begin
  new.user_id := old.user_id; new.tournament_id := old.tournament_id; new.tmatch := old.tmatch; new.kind := old.kind;
  new.data := old.data; new.dedup := old.dedup; new.created_at := old.created_at;
  return new;
end $$;
drop trigger if exists nx_t_notif_guard on public.nx_t_notifications;
create trigger nx_t_notif_guard before update on public.nx_t_notifications
  for each row execute function public._nx_t_notif_guard();
