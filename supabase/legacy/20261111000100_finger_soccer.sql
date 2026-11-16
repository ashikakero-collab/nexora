-- Finger Soccer: server-authoritative matches. Clients NEVER write these tables directly.
create table if not exists public.fs_matches (
  id uuid primary key default gen_random_uuid(),
  player0 uuid not null references auth.users(id),
  player1 uuid references auth.users(id),            -- null while waiting / vs bot
  state jsonb not null,                               -- FsMatch.toJson() (bodies, score, turnTeam, turnNumber, phase, winner)
  state_hash bigint not null,
  turn_deadline timestamptz,
  status text not null default 'waiting' check (status in ('waiting','live','finished','abandoned')),
  winner smallint,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.fs_shots (
  id bigint generated always as identity primary key,
  match_id uuid not null references public.fs_matches(id) on delete cascade,
  turn_number int not null,
  team smallint not null,
  body_id smallint not null,
  dir_x double precision not null,
  dir_y double precision not null,
  power double precision not null,
  result_hash bigint not null,
  scorer smallint,
  created_at timestamptz not null default now(),
  unique (match_id, turn_number)                      -- idempotency: one shot per turn
);

alter table public.fs_matches enable row level security;
alter table public.fs_shots   enable row level security;

create policy fs_matches_read on public.fs_matches for select
  using (auth.uid() = player0 or auth.uid() = player1);
create policy fs_shots_read on public.fs_shots for select
  using (exists (select 1 from public.fs_matches m where m.id = match_id and (auth.uid() = m.player0 or auth.uid() = m.player1)));
-- no insert/update/delete policies: only the Edge Function (service role) writes.

alter publication supabase_realtime add table public.fs_matches;
alter publication supabase_realtime add table public.fs_shots;
