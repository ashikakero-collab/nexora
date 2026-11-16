-- NEXORA (Flutter, branch nxg) · core online schema.
-- Shares auth.users + public.profiles (username, xp, coins) with the other NEXORA app on this project.
-- Everything NEXORA-Flutter-specific lives under the nx_ prefix. Idempotent; never drops existing data.

-- ---------------------------------------------------------------------------
-- 1. Extended profile (inventory, achievements, stats, decor, theme ...)
-- ---------------------------------------------------------------------------
create table if not exists public.nx_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  explorer_id text,
  avatar_core text not null default 'hero_front',
  data jsonb not null default '{}'::jsonb,
  imported boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.nx_profiles enable row level security;
drop policy if exists nx_profiles_read on public.nx_profiles;
create policy nx_profiles_read on public.nx_profiles for select to authenticated using (true);
drop policy if exists nx_profiles_ins on public.nx_profiles;
create policy nx_profiles_ins on public.nx_profiles for insert to authenticated with check (id = auth.uid());
drop policy if exists nx_profiles_upd on public.nx_profiles;
create policy nx_profiles_upd on public.nx_profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

-- Idempotent XP/coin event log (server is source of truth for xp/coins in public.profiles).
create table if not exists public.nx_xp_events (
  id bigserial primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  idem_key text not null,
  event text not null,
  xp int not null default 0,
  coins int not null default 0,
  created_at timestamptz not null default now(),
  unique (user_id, idem_key)
);
create index if not exists nx_xp_events_user_day on public.nx_xp_events(user_id, created_at);
alter table public.nx_xp_events enable row level security;
drop policy if exists nx_xp_events_read on public.nx_xp_events;
create policy nx_xp_events_read on public.nx_xp_events for select to authenticated using (user_id = auth.uid());

create table if not exists public.nx_catalog (
  item_id text primary key,
  price int not null,
  min_level int not null default 1
);
alter table public.nx_catalog enable row level security;
drop policy if exists nx_catalog_read on public.nx_catalog;
create policy nx_catalog_read on public.nx_catalog for select using (true);

-- Server-side XP/coin award: per-event caps, 3000 XP/day cap (D9), idempotent.
create or replace function public.nx_award(p_event text, p_xp int, p_coins int, p_key text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  today_xp int;
  gx int; gc int;
  r record;
begin
  if me is null then raise exception 'not signed in'; end if;
  if p_key is null or length(p_key) < 4 then raise exception 'bad key'; end if;
  if exists (select 1 from nx_xp_events where user_id = me and idem_key = p_key) then
    select xp, coins into r from profiles where id = me;
    return jsonb_build_object('xp', r.xp, 'coins', r.coins, 'granted_xp', 0, 'granted_coins', 0, 'dup', true);
  end if;
  gx := greatest(0, least(coalesce(p_xp, 0), 300));
  gc := greatest(0, least(coalesce(p_coins, 0), case when p_event like 'achievement.%' then 1000 else 300 end));
  select coalesce(sum(xp), 0) into today_xp from nx_xp_events
   where user_id = me and created_at >= date_trunc('day', now());
  gx := greatest(0, least(gx, 3000 - today_xp));
  insert into nx_xp_events(user_id, idem_key, event, xp, coins) values (me, p_key, left(p_event, 120), gx, gc);
  update profiles set xp = xp + gx, coins = coins + gc, level = level_for_xp(xp + gx) where id = me
    returning xp, coins into r;
  if gx > 0 then insert into xp_events(user_id, amount, reason) values (me, gx, 'nexora:' || left(p_event, 100)); end if;
  return jsonb_build_object('xp', r.xp, 'coins', r.coins, 'granted_xp', gx, 'granted_coins', gc, 'dup', false);
end $$;

-- Purchase validated against the server catalog price.
create or replace function public.nx_purchase(p_item text, p_price int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); cat int; c int; d jsonb;
begin
  if me is null then raise exception 'not signed in'; end if;
  select price into cat from nx_catalog where item_id = p_item;
  if cat is null then
    if p_price is null or p_price < 1 or p_price > 5000 then raise exception 'bad price'; end if;
    cat := p_price;
  end if;
  select data into d from nx_profiles where id = me;
  if d is not null and (d->'inv') ? p_item then
    select coins into c from profiles where id = me;
    return jsonb_build_object('ok', true, 'coins', c, 'owned', true);
  end if;
  update profiles set coins = coins - cat where id = me and coins >= cat returning coins into c;
  if c is null then
    select coins into c from profiles where id = me;
    return jsonb_build_object('ok', false, 'coins', c);
  end if;
  insert into nx_profiles(id, data) values (me, jsonb_build_object('inv', jsonb_build_array(p_item)))
  on conflict (id) do update set
    data = jsonb_set(nx_profiles.data, '{inv}', coalesce(nx_profiles.data->'inv', '[]'::jsonb) || to_jsonb(p_item)),
    updated_at = now();
  return jsonb_build_object('ok', true, 'coins', c, 'price', cat);
end $$;

-- One-time import of offline progress when a device links to a brand-new account (capped).
create or replace function public.nx_import_local(p_xp int, p_coins int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); done boolean; r record;
begin
  if me is null then raise exception 'not signed in'; end if;
  insert into nx_profiles(id) values (me) on conflict (id) do nothing;
  select imported into done from nx_profiles where id = me for update;
  if not done then
    update profiles set
      xp = greatest(xp, least(greatest(coalesce(p_xp, 0), 0), 60000)),
      coins = greatest(coins, least(greatest(coalesce(p_coins, 0), 0), 20000))
     where id = me;
    update profiles set level = level_for_xp(xp) where id = me;
    update nx_profiles set imported = true, updated_at = now() where id = me;
  end if;
  select xp, coins, username into r from profiles where id = me;
  return jsonb_build_object('xp', r.xp, 'coins', r.coins, 'username', r.username, 'imported_now', not done);
end $$;

-- Set the shared username (unique across both apps).
create or replace function public.nx_set_username(p_name text)
returns text language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); n text := trim(coalesce(p_name, ''));
begin
  if me is null then raise exception 'not signed in'; end if;
  if char_length(n) < 2 or char_length(n) > 24 then raise exception 'bad name'; end if;
  if exists (select 1 from profiles where lower(username) = lower(n) and id <> me) then return 'taken'; end if;
  update profiles set username = n where id = me;
  return 'ok';
end $$;

-- ---------------------------------------------------------------------------
-- 2. Online multiplayer (Dart cores on the phones; the DB is the move sequencer)
-- ---------------------------------------------------------------------------
create table if not exists public.nx_rooms (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  game text not null,
  host uuid not null references auth.users(id) on delete cascade,
  seats int not null default 2 check (seats between 2 and 12),
  status text not null default 'lobby' check (status in ('lobby', 'playing', 'closed')),
  is_private boolean not null default false,
  quick boolean not null default false,
  settings jsonb not null default '{}'::jsonb,
  match_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists nx_rooms_open on public.nx_rooms(game, status, quick, created_at);

create table if not exists public.nx_room_players (
  room_id uuid not null references public.nx_rooms(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  seat int not null,
  ready boolean not null default false,
  joined_at timestamptz not null default now(),
  last_seen timestamptz not null default now(),
  primary key (room_id, user_id),
  unique (room_id, seat)
);

create table if not exists public.nx_matches (
  id uuid primary key default gen_random_uuid(),
  room_id uuid references public.nx_rooms(id) on delete set null,
  game text not null,
  players uuid[] not null,
  names text[] not null default '{}',
  seed bigint not null,
  settings jsonb not null default '{}'::jsonb,
  status text not null default 'playing' check (status in ('playing', 'finished', 'abandoned')),
  winner_seats int[],
  scores int[],
  reason text,
  last_seq int not null default 0,
  state_hash text,
  started_at timestamptz not null default now(),
  ended_at timestamptz
);
create index if not exists nx_matches_room on public.nx_matches(room_id, started_at desc);

create table if not exists public.nx_match_moves (
  match_id uuid not null references public.nx_matches(id) on delete cascade,
  seq int not null,
  seat int not null,
  by_user uuid not null,
  kind text not null default 'move',
  move jsonb not null,
  hash text,
  created_at timestamptz not null default now(),
  primary key (match_id, seq)
);

-- Per-player secrets (e.g. Mafia roles): only the addressee can read.
create table if not exists public.nx_match_secrets (
  match_id uuid not null references public.nx_matches(id) on delete cascade,
  user_id uuid not null,
  slot text not null default 'role',
  data jsonb not null,
  created_at timestamptz not null default now(),
  primary key (match_id, user_id, slot)
);

create table if not exists public.nx_match_results (
  match_id uuid not null references public.nx_matches(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  game text not null,
  seat int not null,
  outcome text not null check (outcome in ('win', 'loss', 'draw')),
  score int not null default 0,
  rating_delta int not null default 0,
  created_at timestamptz not null default now(),
  primary key (match_id, user_id)
);

create table if not exists public.nx_game_stats (
  user_id uuid not null references auth.users(id) on delete cascade,
  game text not null,
  played int not null default 0,
  won int not null default 0,
  lost int not null default 0,
  draw int not null default 0,
  rating int not null default 1000,
  best int not null default 0,
  updated_at timestamptz not null default now(),
  primary key (user_id, game)
);

create table if not exists public.nx_invites (
  id bigserial primary key,
  from_user uuid not null references auth.users(id) on delete cascade,
  to_user uuid not null references auth.users(id) on delete cascade,
  kind text not null default 'game',
  room_id uuid references public.nx_rooms(id) on delete cascade,
  payload jsonb not null default '{}'::jsonb,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'declined', 'expired')),
  created_at timestamptz not null default now()
);
create index if not exists nx_invites_to on public.nx_invites(to_user, status, created_at desc);

alter table public.nx_rooms enable row level security;
alter table public.nx_room_players enable row level security;
alter table public.nx_matches enable row level security;
alter table public.nx_match_moves enable row level security;
alter table public.nx_match_secrets enable row level security;
alter table public.nx_match_results enable row level security;
alter table public.nx_game_stats enable row level security;
alter table public.nx_invites enable row level security;

create or replace function public.nx_in_room(r uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from nx_room_players where room_id = r and user_id = auth.uid())
$$;
create or replace function public.nx_in_match(m uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from nx_matches where id = m and auth.uid() = any(players))
$$;

drop policy if exists nx_rooms_read on public.nx_rooms;
create policy nx_rooms_read on public.nx_rooms for select to authenticated
  using (not is_private or host = auth.uid() or nx_in_room(id));
drop policy if exists nx_room_players_read on public.nx_room_players;
create policy nx_room_players_read on public.nx_room_players for select to authenticated
  using (exists (select 1 from nx_rooms r where r.id = room_id and (not r.is_private or nx_in_room(r.id))));
drop policy if exists nx_matches_read on public.nx_matches;
create policy nx_matches_read on public.nx_matches for select to authenticated using (true);
drop policy if exists nx_match_moves_read on public.nx_match_moves;
create policy nx_match_moves_read on public.nx_match_moves for select to authenticated using (nx_in_match(match_id));
drop policy if exists nx_match_secrets_read on public.nx_match_secrets;
create policy nx_match_secrets_read on public.nx_match_secrets for select to authenticated using (user_id = auth.uid());
drop policy if exists nx_match_results_read on public.nx_match_results;
create policy nx_match_results_read on public.nx_match_results for select to authenticated using (true);
drop policy if exists nx_game_stats_read on public.nx_game_stats;
create policy nx_game_stats_read on public.nx_game_stats for select using (true);
drop policy if exists nx_invites_read on public.nx_invites;
create policy nx_invites_read on public.nx_invites for select to authenticated using (to_user = auth.uid() or from_user = auth.uid());
drop policy if exists nx_invites_upd on public.nx_invites;
create policy nx_invites_upd on public.nx_invites for update to authenticated using (to_user = auth.uid()) with check (to_user = auth.uid());

create or replace function public.nx_gen_code() returns text language plpgsql as $$
declare c text; alphabet text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; i int;
begin
  loop
    c := '';
    for i in 1..6 loop c := c || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1); end loop;
    exit when not exists (select 1 from nx_rooms where code = c);
  end loop;
  return c;
end $$;

create or replace function public.nx_game_bounds(p_game text, out min_seats int, out max_seats int)
language sql immutable as $$
  select case p_game when 'ludo' then 2 when 'snakes_ladders' then 2 when 'uno' then 2 when 'quiz' then 2
                     when 'mafia' then 6 else 2 end,
         case p_game when 'ludo' then 4 when 'snakes_ladders' then 4 when 'uno' then 4 when 'quiz' then 2
                     when 'mafia' then 10 else 2 end
$$;

-- Leave every other open NEXORA room before entering a new one.
create or replace function public._nx_leave_all(me uuid) returns void
language plpgsql security definer set search_path = public as $$
declare r record;
begin
  for r in select rp.room_id from nx_room_players rp join nx_rooms x on x.id = rp.room_id
            where rp.user_id = me and x.status = 'lobby' loop
    perform nx_leave_room(r.room_id);
  end loop;
end $$;

create or replace function public.nx_create_room(p_game text, p_seats int, p_private boolean, p_quick boolean default false,
                                                 p_settings jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); b record; s int; rid uuid; c text;
begin
  if me is null then raise exception 'not signed in'; end if;
  select * into b from nx_game_bounds(p_game);
  if p_game not in ('finger_soccer','carrom','billiards','backgammon','ludo','snakes_ladders','uno','quiz','mafia') then
    raise exception 'unknown game'; end if;
  s := greatest(b.min_seats, least(coalesce(p_seats, b.min_seats), b.max_seats));
  perform _nx_leave_all(me);
  c := nx_gen_code();
  insert into nx_rooms(code, game, host, seats, is_private, quick, settings)
  values (c, p_game, me, s, coalesce(p_private, false), coalesce(p_quick, false), coalesce(p_settings, '{}'::jsonb))
  returning id into rid;
  insert into nx_room_players(room_id, user_id, seat, ready) values (rid, me, 0, true);
  return jsonb_build_object('room_id', rid, 'code', c, 'seats', s);
end $$;

create or replace function public.nx_join_room(p_code text default null, p_room uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); r nx_rooms; s int;
begin
  if me is null then raise exception 'not signed in'; end if;
  if p_room is not null then select * into r from nx_rooms where id = p_room for update;
  else select * into r from nx_rooms where code = upper(trim(p_code)) for update; end if;
  if r.id is null then raise exception 'room not found'; end if;
  if exists (select 1 from nx_room_players where room_id = r.id and user_id = me) then
    update nx_room_players set last_seen = now() where room_id = r.id and user_id = me;
    return jsonb_build_object('room_id', r.id, 'code', r.code, 'rejoined', true, 'status', r.status, 'match_id', r.match_id);
  end if;
  if r.status <> 'lobby' then raise exception 'room already started'; end if;
  perform _nx_leave_all(me);
  select min(g) into s from generate_series(0, r.seats - 1) g
   where not exists (select 1 from nx_room_players where room_id = r.id and seat = g);
  if s is null then raise exception 'room full'; end if;
  insert into nx_room_players(room_id, user_id, seat) values (r.id, me, s);
  update nx_rooms set updated_at = now() where id = r.id;
  return jsonb_build_object('room_id', r.id, 'code', r.code, 'seat', s, 'status', r.status);
end $$;

create or replace function public.nx_leave_room(p_room uuid)
returns void language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); r nx_rooms; nh uuid;
begin
  select * into r from nx_rooms where id = p_room for update;
  if r.id is null then return; end if;
  if r.status = 'playing' and r.match_id is not null then
    perform nx_forfeit(r.match_id);
  end if;
  delete from nx_room_players where room_id = p_room and user_id = me;
  if not exists (select 1 from nx_room_players where room_id = p_room) then
    update nx_rooms set status = 'closed', updated_at = now() where id = p_room;
  elsif r.host = me then
    select user_id into nh from nx_room_players where room_id = p_room order by seat limit 1;
    update nx_rooms set host = nh, updated_at = now() where id = p_room;
  end if;
end $$;

create or replace function public.nx_set_ready(p_room uuid, p_ready boolean)
returns void language sql security definer set search_path = public as $$
  update nx_room_players set ready = p_ready, last_seen = now() where room_id = p_room and user_id = auth.uid();
  update nx_rooms set updated_at = now() where id = p_room;
$$;

create or replace function public.nx_update_room(p_room uuid, p_seats int, p_settings jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare r nx_rooms; b record; n int;
begin
  select * into r from nx_rooms where id = p_room for update;
  if r.host <> auth.uid() then raise exception 'host only'; end if;
  if r.status <> 'lobby' then raise exception 'already started'; end if;
  select * into b from nx_game_bounds(r.game);
  select count(*) into n from nx_room_players where room_id = p_room;
  update nx_rooms set seats = greatest(n, greatest(b.min_seats, least(coalesce(p_seats, r.seats), b.max_seats))),
         settings = coalesce(p_settings, settings), updated_at = now() where id = p_room;
end $$;

-- Host starts the match: seats compacted in seat order, shared seed for every deterministic core.
create or replace function public.nx_start_match(p_room uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); r nx_rooms; b record; ids uuid[]; nm text[]; mid uuid; sd bigint; n int;
begin
  select * into r from nx_rooms where id = p_room for update;
  if r.id is null then raise exception 'room not found'; end if;
  if r.host <> me and not r.quick then raise exception 'host only'; end if;
  if r.status = 'playing' and r.match_id is not null then
    return jsonb_build_object('match_id', r.match_id, 'already', true);
  end if;
  select * into b from nx_game_bounds(r.game);
  select array_agg(rp.user_id order by rp.seat), array_agg(coalesce(p.username, 'Pilot') order by rp.seat), count(*)
    into ids, nm, n
    from nx_room_players rp left join profiles p on p.id = rp.user_id where rp.room_id = p_room;
  if n < b.min_seats then raise exception 'need % players', b.min_seats; end if;
  sd := floor(random() * 2147483646)::bigint + 1;
  insert into nx_matches(room_id, game, players, names, seed, settings) values (p_room, r.game, ids, nm, sd, r.settings)
  returning id into mid;
  update nx_rooms set status = 'playing', match_id = mid, updated_at = now() where id = p_room;
  return jsonb_build_object('match_id', mid, 'seed', sd);
end $$;

-- Quick match: join the oldest open quick room for this game/seat count, otherwise open one.
create or replace function public.nx_quick(p_game text, p_seats int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); rid uuid; res jsonb; n int; s int; r nx_rooms;
begin
  if me is null then raise exception 'not signed in'; end if;
  update nx_rooms set status = 'closed' where status = 'lobby' and quick and updated_at < now() - interval '10 minutes';
  select x.id into rid from nx_rooms x
   where x.game = p_game and x.status = 'lobby' and x.quick and not x.is_private and x.seats = p_seats
     and not exists (select 1 from nx_room_players rp where rp.room_id = x.id and rp.user_id = me)
     and (select count(*) from nx_room_players rp where rp.room_id = x.id) < x.seats
   order by x.created_at limit 1 for update skip locked;
  if rid is null then
    res := nx_create_room(p_game, p_seats, false, true, '{}'::jsonb);
    return res || jsonb_build_object('created', true);
  end if;
  res := nx_join_room(null, rid);
  select * into r from nx_rooms where id = rid;
  select count(*) into n from nx_room_players where room_id = rid;
  if n >= r.seats then
    res := res || nx_start_match_quick(rid);
  end if;
  return res;
end $$;

create or replace function public.nx_start_match_quick(p_room uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r nx_rooms; ids uuid[]; nm text[]; mid uuid; sd bigint;
begin
  select * into r from nx_rooms where id = p_room for update;
  if r.status <> 'lobby' then return jsonb_build_object('match_id', r.match_id); end if;
  select array_agg(rp.user_id order by rp.seat), array_agg(coalesce(p.username, 'Pilot') order by rp.seat)
    into ids, nm from nx_room_players rp left join profiles p on p.id = rp.user_id where rp.room_id = p_room;
  sd := floor(random() * 2147483646)::bigint + 1;
  insert into nx_matches(room_id, game, players, names, seed, settings) values (p_room, r.game, ids, nm, sd, r.settings)
  returning id into mid;
  update nx_rooms set status = 'playing', match_id = mid, updated_at = now() where id = p_room;
  return jsonb_build_object('match_id', mid, 'seed', sd);
end $$;

-- The ordered move log. seq must be last_seq+1 (first writer wins) → every phone applies the same order.
create or replace function public.nx_push_move(p_match uuid, p_seq int, p_kind text, p_move jsonb, p_hash text, p_seat int default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); m nx_matches; s int;
begin
  select * into m from nx_matches where id = p_match for update;
  if m.id is null then raise exception 'match not found'; end if;
  s := array_position(m.players, me) - 1;
  if s is null then raise exception 'not a player'; end if;
  if m.status <> 'playing' then return jsonb_build_object('ok', false, 'reason', 'over', 'last_seq', m.last_seq); end if;
  if p_seq <> m.last_seq + 1 then return jsonb_build_object('ok', false, 'reason', 'seq', 'last_seq', m.last_seq); end if;
  -- the authority (host side) may post on behalf of a disconnected seat (timeouts/forfeits) and snapshots
  if p_seat is not null and p_seat <> s and p_kind not in ('snap', 'timeout', 'forfeit', 'system') then
    raise exception 'seat mismatch'; end if;
  insert into nx_match_moves(match_id, seq, seat, by_user, kind, move, hash)
  values (p_match, p_seq, coalesce(p_seat, s), me, left(coalesce(p_kind, 'move'), 16), coalesce(p_move, '{}'::jsonb), p_hash);
  update nx_matches set last_seq = p_seq, state_hash = coalesce(p_hash, state_hash) where id = p_match;
  return jsonb_build_object('ok', true, 'seq', p_seq);
end $$;

create or replace function public.nx_put_secret(p_match uuid, p_user uuid, p_slot text, p_data jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare m nx_matches;
begin
  select * into m from nx_matches where id = p_match;
  if m.id is null or m.players[1] <> auth.uid() then raise exception 'authority only'; end if;
  if not (p_user = any(m.players)) then raise exception 'not a player'; end if;
  insert into nx_match_secrets(match_id, user_id, slot, data) values (p_match, p_user, p_slot, p_data)
  on conflict (match_id, user_id, slot) do update set data = excluded.data, created_at = now();
end $$;

create or replace function public._nx_apply_result(m nx_matches, p_winners int[], p_scores int[])
returns void language plpgsql security definer set search_path = public as $$
declare i int; uid uuid; oc text; sc int; v_xp int; v_co int; rd int; n int := array_length(m.players, 1);
begin
  for i in 1..n loop
    uid := m.players[i];
    if p_winners is null or array_length(p_winners, 1) is null then oc := 'draw';
    elsif (i - 1) = any(p_winners) then oc := case when array_length(p_winners, 1) = n then 'draw' else 'win' end;
    else oc := 'loss'; end if;
    sc := coalesce(p_scores[i], 0);
    rd := case oc when 'win' then 16 when 'loss' then -12 else 0 end;
    insert into nx_match_results(match_id, user_id, game, seat, outcome, score, rating_delta)
    values (m.id, uid, m.game, i - 1, oc, sc, rd) on conflict do nothing;
    if found then
      insert into nx_game_stats(user_id, game, played, won, lost, draw, rating, best)
      values (uid, m.game, 1, (oc = 'win')::int, (oc = 'loss')::int, (oc = 'draw')::int, greatest(0, 1000 + rd), sc)
      on conflict (user_id, game) do update set
        played = nx_game_stats.played + 1,
        won = nx_game_stats.won + (excluded.won),
        lost = nx_game_stats.lost + (excluded.lost),
        draw = nx_game_stats.draw + (excluded.draw),
        rating = greatest(0, nx_game_stats.rating + rd),
        best = greatest(nx_game_stats.best, excluded.best),
        updated_at = now();
      v_xp := case oc when 'win' then 80 when 'draw' then 40 else 20 end;
      v_co := case oc when 'win' then 50 when 'draw' then 20 else 8 end;
      insert into nx_xp_events(user_id, idem_key, event, xp, coins)
      values (uid, 'match:' || m.id::text, 'online.' || m.game || '.' || oc, v_xp, v_co) on conflict do nothing;
      if found then
        update profiles p set xp = p.xp + v_xp, coins = p.coins + v_co, level = level_for_xp(p.xp + v_xp) where p.id = uid;
      end if;
    end if;
  end loop;
end $$;

-- Result is reported by a player of the match; first report is final (all phones computed the same state).
create or replace function public.nx_finish_match(p_match uuid, p_winners int[], p_scores int[], p_hash text default null,
                                                  p_reason text default 'finished')
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); m nx_matches;
begin
  select * into m from nx_matches where id = p_match for update;
  if m.id is null then raise exception 'match not found'; end if;
  if not (me = any(m.players)) then raise exception 'not a player'; end if;
  if m.status <> 'playing' then
    return jsonb_build_object('ok', true, 'already', true, 'winners', m.winner_seats);
  end if;
  update nx_matches set status = 'finished', winner_seats = p_winners, scores = p_scores, reason = left(p_reason, 40),
         state_hash = coalesce(p_hash, state_hash), ended_at = now() where id = p_match returning * into m;
  perform _nx_apply_result(m, p_winners, p_scores);
  update nx_rooms set status = 'lobby', updated_at = now() where id = m.room_id and match_id = m.id;
  update nx_room_players set ready = false where room_id = m.room_id and seat > 0;
  return jsonb_build_object('ok', true, 'winners', p_winners);
end $$;

-- Leaving a running match = forfeit. 2-player: the other seat wins. N-player: logged as a 'forfeit' move
-- so the game continues without that seat (games skip forfeited seats).
create or replace function public.nx_forfeit(p_match uuid, p_seat int default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); m nx_matches; s int; others int[];
begin
  select * into m from nx_matches where id = p_match for update;
  if m.id is null or m.status <> 'playing' then return jsonb_build_object('ok', false); end if;
  s := array_position(m.players, me) - 1;
  if s is null then raise exception 'not a player'; end if;
  if p_seat is not null and p_seat <> s then
    if s <> 0 then raise exception 'authority only'; end if;  -- host may forfeit an absent seat
    s := p_seat;
  end if;
  insert into nx_match_moves(match_id, seq, seat, by_user, kind, move)
  values (p_match, m.last_seq + 1, s, me, 'forfeit', jsonb_build_object('seat', s));
  update nx_matches set last_seq = m.last_seq + 1 where id = p_match;
  if array_length(m.players, 1) = 2 then
    select array_agg(g) into others from generate_series(0, 1) g where g <> s;
    return nx_finish_match_as(p_match, others, s);
  end if;
  return jsonb_build_object('ok', true, 'seat', s);
end $$;

create or replace function public.nx_finish_match_as(p_match uuid, p_winners int[], p_loser int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare m nx_matches;
begin
  update nx_matches set status = 'finished', winner_seats = p_winners, reason = 'forfeit:' || p_loser, ended_at = now()
   where id = p_match and status = 'playing' returning * into m;
  if m.id is null then return jsonb_build_object('ok', false); end if;
  perform _nx_apply_result(m, p_winners, null);
  update nx_rooms set status = 'lobby', updated_at = now() where id = m.room_id and match_id = m.id;
  return jsonb_build_object('ok', true, 'winners', p_winners, 'forfeit', p_loser);
end $$;

create or replace function public.nx_invite(p_room uuid, p_user uuid)
returns void language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); r nx_rooms;
begin
  select * into r from nx_rooms where id = p_room;
  if r.id is null or not nx_in_room(p_room) then raise exception 'not in room'; end if;
  if exists (select 1 from user_blocks where blocker = p_user and blocked = me) then raise exception 'blocked'; end if;
  insert into nx_invites(from_user, to_user, kind, room_id, payload)
  values (me, p_user, 'game', p_room, jsonb_build_object('code', r.code, 'game', r.game,
          'from_name', (select username from profiles where id = me)));
end $$;

-- Leaderboards
create or replace view public.nx_leaderboard with (security_invoker = true) as
  select s.game, s.user_id, p.username, p.avatar, s.rating, s.played, s.won, s.lost, s.draw, s.best
    from public.nx_game_stats s join public.profiles p on p.id = s.user_id;

create or replace view public.nx_leaderboard_global with (security_invoker = true) as
  select p.id as user_id, p.username, p.avatar, p.xp, p.level,
         coalesce(sum(s.won), 0)::int as won, coalesce(sum(s.played), 0)::int as played
    from public.profiles p join public.nx_profiles n on n.id = p.id
    left join public.nx_game_stats s on s.user_id = p.id
   group by p.id, p.username, p.avatar, p.xp, p.level;

grant select on public.nx_leaderboard, public.nx_leaderboard_global to anon, authenticated;
grant execute on function public.nx_award, public.nx_purchase, public.nx_import_local, public.nx_set_username,
  public.nx_create_room, public.nx_join_room, public.nx_leave_room, public.nx_set_ready, public.nx_update_room,
  public.nx_start_match, public.nx_quick, public.nx_push_move, public.nx_put_secret, public.nx_finish_match,
  public.nx_forfeit, public.nx_invite to authenticated;
revoke execute on function public._nx_apply_result, public.nx_finish_match_as, public.nx_start_match_quick, public._nx_leave_all
  from anon, authenticated, public;

-- Realtime for lobby + move log + invites
do $$ begin
  begin alter publication supabase_realtime add table public.nx_rooms; exception when others then null; end;
  begin alter publication supabase_realtime add table public.nx_room_players; exception when others then null; end;
  begin alter publication supabase_realtime add table public.nx_matches; exception when others then null; end;
  begin alter publication supabase_realtime add table public.nx_match_moves; exception when others then null; end;
  begin alter publication supabase_realtime add table public.nx_invites; exception when others then null; end;
end $$;

insert into public.nx_catalog(item_id, price, min_level) values ('gear_helmet',300,1),('gear_visor_panel',260,1),('gear_tiara',480,6),('gear_headphones',180,1),('gear_sunglasses',120,1),('gear_jacket',350,1),('gear_armor_vest',520,5),('gear_scarf',140,1),('gear_glove',200,1),('gear_bracelet',160,1),('gear_watch',220,1),('gear_belt',150,1),('gear_boots',280,1),('gear_backpack',600,8),('gear_planet_orb',900,12),('gear_crystal_shards',750,10),('decor_planet_globe',120,1),('decor_terrarium_globe',150,1),('decor_plant_bowl',80,1),('decor_purple_tree_pot',110,1),('decor_light_pillar',140,1),('decor_crystal_cluster',200,1),('decor_crystal_arch',320,4),('decor_curved_arch',260,1),('decor_diamond_spinner',380,5),('decor_dna_tube',240,1),('decor_orb_rings',300,1),('decor_ring_sculpture',280,1),('decor_satellite',220,1),('decor_spire_tower',420,7),('decor_tablet_stand',90,1),('decor_banner',60,1),('puck_nx_green',0,1),('puck_tech_nx',0,1),('puck_frost',150,1),('puck_frost_b',150,1),('puck_eagle_marble',220,1),('puck_eagle_gold',350,1),('puck_noble_lion',300,1),('puck_royal_lion',450,5),('puck_phoenix_purple',500,6),('puck_dragon_fire',650,8),('puck_cosmic_crown',800,10),('striker_soccer',0,1),('striker_compass',140,1),('striker_eagle',200,1),('striker_wolf',240,1),('striker_lion',260,1),('striker_fire',320,4),('striker_dragon',420,6),('striker_galaxy',600,9),('cue_classic',0,1),('cue_neon',250,1),('cue_gold',500,6),('theme_aurora',0,1),('theme_nebula',200,1),('theme_crystal',300,1),('theme_solar',400,5),('frame_holo_1',140,1),('frame_holo_2',180,1),('frame_holo_3',220,1),('frame_holo_4',260,1),('frame_holo_5',300,1),('frame_holo_6',340,1),('frame_holo_7',380,1),('frame_holo_8',420,1)
on conflict (item_id) do update set price = excluded.price, min_level = excluded.min_level;
