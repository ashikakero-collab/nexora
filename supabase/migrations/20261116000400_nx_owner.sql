-- NEXORA (Flutter, branch nxg) · Owner (company super-admin) + Owner Console backend.
-- Role ladder: owner > admin > organizer ("tournament admin") > player. The owner implicitly has every admin and organizer power.
-- Owner = nx_staff.role 'owner' (or the shared profiles.role = 'owner' / is_owner()). The owner role is never granted by an RPC:
-- it is set once in SQL. Every console action is a SECURITY DEFINER RPC that checks nx_is_owner() and writes nx_owner_audit
-- (append-only). Tournament admins (organizers with nx_staff.unlimited) host with unlimited coins/gems: fixed prizes and their
-- own entry fees are not deducted from a balance, but every fee/refund/payout is still written to nx_t_ledger.
-- No separate server. Idempotent: safe to re-run.

-- ---------------------------------------------------------------------------
-- schema
-- ---------------------------------------------------------------------------
alter table public.nx_staff drop constraint if exists nx_staff_role_check;
alter table public.nx_staff add constraint nx_staff_role_check check (role in ('owner', 'admin', 'organizer'));
alter table public.nx_staff add column if not exists unlimited boolean not null default false;
alter table public.nx_staff add column if not exists via_code uuid;

create table if not exists public.nx_settings (
  key text primary key,
  value jsonb not null,
  updated_by uuid,
  updated_at timestamptz not null default now()
);
insert into public.nx_settings(key, value) values ('tadmin_cap', '10'::jsonb) on conflict (key) do nothing;

create table if not exists public.nx_account_flags (
  user_id uuid primary key references auth.users(id) on delete cascade,
  must_change_password boolean not null default false,
  banned boolean not null default false,
  ban_reason text,
  banned_at timestamptz,
  banned_by uuid,
  updated_at timestamptz not null default now()
);

create table if not exists public.nx_owner_audit (
  id bigserial primary key,
  actor uuid,
  action text not null,
  target uuid,
  data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists nx_owner_audit_time on public.nx_owner_audit(created_at desc);
drop trigger if exists nx_owner_audit_immutable on public.nx_owner_audit;
create trigger nx_owner_audit_immutable before update or delete on public.nx_owner_audit
  for each row execute function public._nx_t_ledger_immutable();

alter table public.nx_t_ledger drop constraint if exists nx_t_ledger_kind_check;
alter table public.nx_t_ledger add constraint nx_t_ledger_kind_check
  check (kind in ('entry_fee', 'refund', 'payout', 'house_fee', 'entry_fee_unlimited', 'refund_unlimited'));

alter table public.nx_settings enable row level security;
alter table public.nx_account_flags enable row level security;
alter table public.nx_owner_audit enable row level security;
drop policy if exists nx_account_flags_self on public.nx_account_flags;
create policy nx_account_flags_self on public.nx_account_flags for select to authenticated using (user_id = auth.uid());
-- nx_settings / nx_owner_audit: no policies → only the RPCs below read them.

-- ---------------------------------------------------------------------------
-- role helpers
-- ---------------------------------------------------------------------------
create or replace function public.nx_is_owner(u uuid default auth.uid()) returns boolean
language plpgsql stable security definer set search_path = public as $$
begin
  if u is null then return false; end if;
  if exists (select 1 from nx_staff where user_id = u and role = 'owner') then return true; end if;
  begin
    return coalesce(is_owner(u), false);
  exception when others then
    return false;
  end;
end $$;

create or replace function public.nx_t_is_admin(u uuid default auth.uid()) returns boolean
language plpgsql stable security definer set search_path = public as $$
begin
  if u is null then return false; end if;
  if exists (select 1 from nx_staff where user_id = u and role in ('admin', 'owner')) then return true; end if;
  begin
    return coalesce(is_admin(u), false);
  exception when others then
    return false;
  end;
end $$;

-- Unlimited coins/gems for hosting: the owner and tournament admins (organizer + unlimited). Checked live, so a revoke ends it now.
create or replace function public.nx_unlimited(u uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = public as $$
  select u is not null and (nx_is_owner(u)
    or exists (select 1 from nx_staff where user_id = u and role = 'organizer' and unlimited))
$$;

create or replace function public.nx_is_banned(u uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from nx_account_flags where user_id = u and banned)
$$;

create or replace function public.nx_t_my_role() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('admin', nx_t_is_admin(auth.uid()), 'organizer', nx_t_is_organizer(auth.uid()), 'uid', auth.uid(),
                            'owner', nx_is_owner(auth.uid()), 'unlimited', nx_unlimited(auth.uid()))
$$;

-- What the app needs to show the hidden owner entry / tournament-admin badge / forced password change.
create or replace function public.nx_my_access() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'uid', auth.uid(),
    'owner', nx_is_owner(auth.uid()),
    'admin', nx_t_is_admin(auth.uid()),
    'organizer', nx_t_is_organizer(auth.uid()),
    'tournament_admin', exists (select 1 from nx_staff where user_id = auth.uid() and role = 'organizer' and unlimited),
    'unlimited', nx_unlimited(auth.uid()),
    'banned', nx_is_banned(auth.uid()),
    'must_change_password', coalesce((select must_change_password from nx_account_flags where user_id = auth.uid()), false))
$$;

-- A real password change (auth.users.encrypted_password changes) clears the must-change flag; the app cannot fake it.
create or replace function public._nx_password_changed() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.encrypted_password is distinct from old.encrypted_password then
    update nx_account_flags set must_change_password = false, updated_at = now()
     where user_id = new.id and must_change_password;
    if found then
      insert into nx_owner_audit(actor, action, target) values (new.id, 'password_changed', new.id);
    end if;
  end if;
  return new;
end $$;
drop trigger if exists zz_nx_password_changed on auth.users;
create trigger zz_nx_password_changed after update of encrypted_password on auth.users
  for each row execute function public._nx_password_changed();

-- Guard for every console RPC: returns null when allowed, else the error text.
create or replace function public._nx_owner_guard() returns text
language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null then return 'not_signed_in'; end if;
  if not nx_is_owner(auth.uid()) then return 'forbidden'; end if;
  if coalesce((select must_change_password from nx_account_flags where user_id = auth.uid()), false) then
    return 'password_change_required'; end if;
  return null;
end $$;

create or replace function public._nx_owner_log(p_action text, p_target uuid, p_data jsonb default '{}'::jsonb) returns void
language sql security definer set search_path = public as $$
  insert into nx_owner_audit(actor, action, target, data) values (auth.uid(), p_action, p_target, coalesce(p_data, '{}'::jsonb));
$$;

create or replace function public._nx_tadmin_cap() returns int
language sql stable security definer set search_path = public as $$
  select coalesce((select (value #>> '{}')::int from nx_settings where key = 'tadmin_cap'), 10)
$$;

create or replace function public._nx_tadmin_count() returns int
language sql stable security definer set search_path = public as $$
  select count(*)::int from nx_staff where role = 'organizer' and unlimited
$$;

-- ---------------------------------------------------------------------------
-- money: tournament admins / owner pay entry fees from an unlimited balance (ledger still written)
-- ---------------------------------------------------------------------------
create or replace function public._nx_t_charge(p_t uuid, p_user uuid, p_coins int, p_gems int) returns bigint
language plpgsql security definer set search_path = public as $$
declare lid bigint; ok uuid; unl boolean := nx_unlimited(p_user);
        k text := case when unl then 'ufee:' else 'fee:' end || p_t || ':' || p_user || ':'
                  || floor(extract(epoch from clock_timestamp()) * 1000)::bigint;
        kd text := case when unl then 'entry_fee_unlimited' else 'entry_fee' end;
begin
  if coalesce(p_coins, 0) = 0 and coalesce(p_gems, 0) = 0 then return 0; end if;
  if not unl then
    update profiles set coins = coins - p_coins, gems = coalesce(gems, 0) - p_gems
     where id = p_user and coins >= p_coins and coalesce(gems, 0) >= p_gems returning id into ok;
    if ok is null then return null; end if;
  end if;
  if p_coins > 0 then
    insert into nx_t_ledger(tournament_id, user_id, kind, currency, amount, idem_key)
    values (p_t, p_user, kd, 'coins', -p_coins, k || ':c') returning id into lid;
  end if;
  if p_gems > 0 then
    insert into nx_t_ledger(tournament_id, user_id, kind, currency, amount, idem_key)
    values (p_t, p_user, kd, 'gems', -p_gems, k || ':g') returning id into lid;
  end if;
  update nx_tournaments set escrow_coins = escrow_coins + p_coins, escrow_gems = escrow_gems + p_gems where id = p_t;
  return lid;
end $$;

-- A fee paid from the unlimited balance is refunded to it (ledger row, no balance credit), so withdraw/cancel can't mint coins.
create or replace function public._nx_t_refund(p_t uuid, p_user uuid, p_reason text) returns boolean
language plpgsql security definer set search_path = public as $$
declare e nx_t_entries; got boolean := false; unl boolean; kd text;
begin
  select * into e from nx_t_entries where tournament_id = p_t and user_id = p_user for update;
  if e.user_id is null or (e.paid_coins = 0 and e.paid_gems = 0) then return false; end if;
  unl := coalesce((select kind = 'entry_fee_unlimited' from nx_t_ledger where id = e.fee_ref), false);
  kd := case when unl then 'refund_unlimited' else 'refund' end;
  if e.paid_coins > 0 then
    insert into nx_t_ledger(tournament_id, user_id, kind, currency, amount, idem_key)
    values (p_t, p_user, kd, 'coins', e.paid_coins, 'refund:coins:' || coalesce(e.fee_ref::text, p_t || ':' || p_user))
    on conflict (idem_key) do nothing;
    if found then
      if not unl then update profiles set coins = coins + e.paid_coins where id = p_user; end if;
      update nx_tournaments set escrow_coins = greatest(0, escrow_coins - e.paid_coins) where id = p_t;
      got := true;
    end if;
  end if;
  if e.paid_gems > 0 then
    insert into nx_t_ledger(tournament_id, user_id, kind, currency, amount, idem_key)
    values (p_t, p_user, kd, 'gems', e.paid_gems, 'refund:gems:' || coalesce(e.fee_ref::text, p_t || ':' || p_user))
    on conflict (idem_key) do nothing;
    if found then
      if not unl then update profiles set gems = gems + e.paid_gems where id = p_user; end if;
      update nx_tournaments set escrow_gems = greatest(0, escrow_gems - e.paid_gems) where id = p_t;
      got := true;
    end if;
  end if;
  update nx_t_entries set paid_coins = 0, paid_gems = 0, updated_at = now() where tournament_id = p_t and user_id = p_user;
  if got then
    perform _nx_t_notify(p_user, p_t, null, 'refund', jsonb_build_object('coins', e.paid_coins, 'gems', e.paid_gems,
                         'reason', p_reason, 'unlimited', unl), 'refund:' || coalesce(e.fee_ref::text, p_user::text));
  end if;
  return got;
end $$;

-- nx_t_save: fixed (minted) prizes allowed for admins/owner AND tournament admins with the unlimited perk (audited).
create or replace function public.nx_t_save(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); t nx_tournaments; old nx_tournaments; isnew boolean; adm boolean; paid boolean;
        n_appr int; times_changed boolean := false; prize jsonb; dsum int := 0; v jsonb;
begin
  if me is null then return jsonb_build_object('ok', false, 'error', 'not_signed_in'); end if;
  adm := nx_t_is_admin(me);
  isnew := (p ->> 'id') is null;
  if isnew then
    if not nx_t_is_organizer(me) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
    t.id := gen_random_uuid(); t.status := 'draft'; t.created_by := me; t.config := '{}'; t.prize := '{}';
    t.game := 'finger_soccer'; t.format := 'single_elim'; t.capacity := 16; t.min_players := 2; t.reg_mode := 'open';
    t.min_level := 0; t.min_xp := 0; t.min_rating := 0; t.fee_coins := 0; t.fee_gems := 0; t.seeding := 'random';
    t.description := ''; t.rules := ''; t.paused := false; t.stage := 'main'; t.escrow_coins := 0; t.escrow_gems := 0;
    t.paid_out := false; t.created_at := now();
  else
    select * into t from nx_tournaments where id = (p ->> 'id')::uuid for update;
    if t.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
    if not nx_t_can_manage(t.id, me) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
    if t.status in ('finished', 'cancelled') then return jsonb_build_object('ok', false, 'error', 'locked'); end if;
  end if;
  old := t;
  -- always editable
  if p ? 'title' then t.title := left(trim(p ->> 'title'), 80); end if;
  if p ? 'description' then t.description := left(coalesce(p ->> 'description', ''), 4000); end if;
  if p ? 'rules' then t.rules := left(coalesce(p ->> 'rules', ''), 4000); end if;
  if p ? 'reg_open_at' and t.status in ('draft', 'scheduled') then t.reg_open_at := (p ->> 'reg_open_at')::timestamptz; end if;
  if p ? 'reg_close_at' and t.status in ('draft', 'scheduled', 'registering') then t.reg_close_at := (p ->> 'reg_close_at')::timestamptz; end if;
  if p ? 'draw_at' and t.status in ('draft', 'scheduled', 'registering', 'closed') then t.draw_at := (p ->> 'draw_at')::timestamptz; end if;
  if p ? 'start_at' and t.status in ('draft', 'scheduled', 'registering', 'closed', 'drawn') then t.start_at := (p ->> 'start_at')::timestamptz; end if;
  if p ? 'config' then
    if t.status in ('draft', 'scheduled', 'registering', 'closed') then
      t.config := _nx_t_validate_cfg(p -> 'config');
    else
      -- after the draw only timing settings may change
      v := p -> 'config';
      t.config := _nx_t_validate_cfg(t.config || jsonb_strip_nulls(jsonb_build_object(
        'round_starts', v -> 'round_starts', 'round_minutes', v -> 'round_minutes', 'ready_seconds', v -> 'ready_seconds',
        'max_game_minutes', v -> 'max_game_minutes')));
    end if;
  end if;
  if t.status in ('draft', 'scheduled', 'registering', 'closed') then
    select count(*) into n_appr from nx_t_entries where tournament_id = t.id and status = 'approved';
    select exists (select 1 from nx_t_entries where tournament_id = t.id and (paid_coins > 0 or paid_gems > 0)) into paid;
    if p ? 'game' then t.game := p ->> 'game'; end if;
    if p ? 'format' then t.format := p ->> 'format'; end if;
    if p ? 'capacity' then t.capacity := greatest(n_appr, (p ->> 'capacity')::int); end if;
    if p ? 'min_players' then t.min_players := greatest(2, least((p ->> 'min_players')::int, t.capacity)); end if;
    if p ? 'reg_mode' then t.reg_mode := p ->> 'reg_mode'; end if;
    if p ? 'min_level' then t.min_level := greatest(0, (p ->> 'min_level')::int); end if;
    if p ? 'min_xp' then t.min_xp := greatest(0, (p ->> 'min_xp')::int); end if;
    if p ? 'min_rating' then t.min_rating := greatest(0, (p ->> 'min_rating')::int); end if;
    if p ? 'seeding' then t.seeding := p ->> 'seeding'; end if;
    if not paid then
      if p ? 'fee_coins' then t.fee_coins := greatest(0, (p ->> 'fee_coins')::int); end if;
      if p ? 'fee_gems' then t.fee_gems := greatest(0, (p ->> 'fee_gems')::int); end if;
    elsif (p ? 'fee_coins' and (p ->> 'fee_coins')::int <> t.fee_coins) or (p ? 'fee_gems' and (p ->> 'fee_gems')::int <> t.fee_gems) then
      return jsonb_build_object('ok', false, 'error', 'fee_locked');
    end if;
    if p ? 'prize' then
      prize := coalesce(p -> 'prize', '{}'::jsonb);
      prize := jsonb_build_object(
        'fixed_coins', greatest(0, _nx_t_cfg_int(prize, 'fixed_coins', 0)),
        'fixed_gems', greatest(0, _nx_t_cfg_int(prize, 'fixed_gems', 0)),
        'pool_pct', greatest(0, least(_nx_t_cfg_int(prize, 'pool_pct', 0), 100)),
        'fee_pct', greatest(0, least(_nx_t_cfg_int(prize, 'fee_pct', 0), 50)),
        'dist', case when jsonb_typeof(prize -> 'dist') = 'array' then prize -> 'dist' else '[60,30,10]'::jsonb end);
      select coalesce(sum(greatest(0, x::numeric::int)), 0) into dsum from jsonb_array_elements_text(prize -> 'dist') x;
      if dsum > 100 or jsonb_array_length(prize -> 'dist') > 64 then
        return jsonb_build_object('ok', false, 'error', 'bad_distribution'); end if;
      -- minting coins/gems out of nothing is an admin decision
      -- (admins, the owner and tournament admins with the 'unlimited' perk; nothing is deducted from their balance,
      --  every payout is still written to nx_t_ledger)
      if (_nx_t_cfg_int(prize, 'fixed_coins', 0) > _nx_t_cfg_int(old.prize, 'fixed_coins', 0)
          or _nx_t_cfg_int(prize, 'fixed_gems', 0) > _nx_t_cfg_int(old.prize, 'fixed_gems', 0)) then
        if not (adm or nx_unlimited(me)) then
          return jsonb_build_object('ok', false, 'error', 'fixed_prize_admin_only'); end if;
        perform _nx_t_audit(t.id, me, 'fixed_prize_minted', jsonb_build_object(
          'fixed_coins', _nx_t_cfg_int(prize, 'fixed_coins', 0), 'fixed_gems', _nx_t_cfg_int(prize, 'fixed_gems', 0),
          'by', case when adm then 'admin' else 'tournament_admin_unlimited' end));
      end if;
      t.prize := prize;
    end if;
  end if;
  if t.title is null or char_length(t.title) < 3 then return jsonb_build_object('ok', false, 'error', 'bad_title'); end if;
  if t.format not in ('single_elim', 'double_elim', 'two_legs', 'round_robin', 'groups_ko', 'swiss', 'custom') then
    return jsonb_build_object('ok', false, 'error', 'bad_format'); end if;
  if t.capacity is null or t.capacity < 2 or t.capacity > 64 then return jsonb_build_object('ok', false, 'error', 'bad_capacity'); end if;
  if t.game not in ('finger_soccer', 'carrom', 'billiards', 'backgammon', 'quiz') then
    return jsonb_build_object('ok', false, 'error', 'bad_game'); end if;
  if t.reg_open_at is null or t.reg_close_at is null or t.draw_at is null or t.start_at is null
     or not (t.reg_open_at < t.reg_close_at and t.reg_close_at <= t.draw_at and t.draw_at <= t.start_at) then
    return jsonb_build_object('ok', false, 'error', 'bad_times'); end if;
  if t.format = 'groups_ko' and t.capacity < 4 then return jsonb_build_object('ok', false, 'error', 'groups_need_4'); end if;
  times_changed := not isnew and old.status <> 'draft' and (old.reg_open_at, old.reg_close_at, old.draw_at, old.start_at, old.config -> 'round_starts', old.config -> 'round_minutes')
                   is distinct from (t.reg_open_at, t.reg_close_at, t.draw_at, t.start_at, t.config -> 'round_starts', t.config -> 'round_minutes');
  t.updated_at := now();
  if isnew then
    insert into nx_tournaments select t.*;
    perform _nx_t_audit(t.id, me, 'created', jsonb_build_object('title', t.title, 'format', t.format));
  else
    update nx_tournaments set title = t.title, description = t.description, rules = t.rules, game = t.game, format = t.format,
           capacity = t.capacity, min_players = t.min_players, config = t.config, reg_mode = t.reg_mode, min_level = t.min_level,
           min_xp = t.min_xp, min_rating = t.min_rating, fee_coins = t.fee_coins, fee_gems = t.fee_gems, prize = t.prize,
           reg_open_at = t.reg_open_at, reg_close_at = t.reg_close_at, draw_at = t.draw_at, start_at = t.start_at,
           seeding = t.seeding, updated_at = now()
     where id = t.id;
    perform _nx_t_audit(t.id, me, 'edited', jsonb_build_object('times_changed', times_changed));
  end if;
  if times_changed then
    perform _nx_t_sync_jobs(t.id);
    perform _nx_t_reschedule(t.id);
    perform _nx_t_notify_all(t.id, 'time_changed', jsonb_build_object('start_at', t.start_at, 'reg_close_at', t.reg_close_at,
              'draw_at', t.draw_at), 'time:' || t.id || ':' || floor(extract(epoch from clock_timestamp()))::bigint,
              array['approved', 'pending', 'waitlist']);
  end if;
  return jsonb_build_object('ok', true, 'id', t.id);
end $$;


-- ---------------------------------------------------------------------------
-- Owner Console RPCs
-- ---------------------------------------------------------------------------
create or replace function public.nx_owner_stats() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare g text := _nx_owner_guard();
begin
  if g is not null then return jsonb_build_object('ok', false, 'error', g); end if;
  return jsonb_build_object('ok', true,
    'users', (select count(*) from auth.users),
    'guests', (select count(*) from auth.users where coalesce(is_anonymous, false)),
    'banned', (select count(*) from nx_account_flags where banned),
    'admins', (select count(*) from nx_staff where role = 'admin'),
    'organizers', (select count(*) from nx_staff where role = 'organizer'),
    'tournament_admins', _nx_tadmin_count(),
    'tadmin_cap', _nx_tadmin_cap(),
    'tournaments_live', (select count(*) from nx_tournaments where status in ('registering', 'closed', 'drawn', 'live')),
    'tournaments_total', (select count(*) from nx_tournaments));
end $$;

-- Search users by username, email or id prefix. Newest first.
create or replace function public.nx_owner_users(p_q text default '', p_limit int default 50, p_offset int default 0) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare g text := _nx_owner_guard(); q text := lower(trim(coalesce(p_q, ''))); res jsonb;
begin
  if g is not null then return jsonb_build_object('ok', false, 'error', g); end if;
  select coalesce(jsonb_agg(x order by x.created_at desc), '[]'::jsonb) into res from (
    select u.id, p.username, u.email, coalesce(u.is_anonymous, false) as guest, u.created_at, u.last_sign_in_at,
           coalesce(p.coins, 0) as coins, coalesce(p.gems, 0) as gems, coalesce(p.xp, 0) as xp, coalesce(p.level, 1) as level,
           case when nx_is_owner(u.id) then 'owner' else coalesce(s.role, 'player') end as role,
           coalesce(s.unlimited, false) as unlimited,
           coalesce(f.banned, false) as banned, f.ban_reason
      from auth.users u
      left join profiles p on p.id = u.id
      left join nx_staff s on s.user_id = u.id
      left join nx_account_flags f on f.user_id = u.id
     where q = '' or lower(coalesce(p.username, '')) like '%' || q || '%' or lower(coalesce(u.email, '')) like '%' || q || '%'
           or u.id::text like q || '%'
     order by u.created_at desc
     limit greatest(1, least(coalesce(p_limit, 50), 200)) offset greatest(0, coalesce(p_offset, 0))) x;
  return jsonb_build_object('ok', true, 'users', res);
end $$;

-- Ban: Supabase Auth refuses sign-in / token refresh (banned_until), open sessions are revoked, the flag is visible to RPCs.
create or replace function public.nx_owner_ban(p_user uuid, p_ban boolean, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public, auth as $$
declare g text := _nx_owner_guard();
begin
  if g is not null then return jsonb_build_object('ok', false, 'error', g); end if;
  if p_user is null or not exists (select 1 from auth.users where id = p_user) then
    return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if p_user = auth.uid() or nx_is_owner(p_user) then return jsonb_build_object('ok', false, 'error', 'cannot_ban_owner'); end if;
  if p_ban then
    insert into nx_account_flags(user_id, banned, ban_reason, banned_at, banned_by) values (p_user, true, left(p_reason, 300), now(), auth.uid())
    on conflict (user_id) do update set banned = true, ban_reason = excluded.ban_reason, banned_at = now(), banned_by = auth.uid(),
       updated_at = now();
    update auth.users set banned_until = 'infinity'::timestamptz where id = p_user;
    delete from auth.sessions where user_id = p_user;
    delete from auth.refresh_tokens where user_id = p_user::text;
  else
    update nx_account_flags set banned = false, ban_reason = null, banned_at = null, banned_by = null, updated_at = now() where user_id = p_user;
    update auth.users set banned_until = null where id = p_user;
  end if;
  perform _nx_owner_log(case when p_ban then 'ban' else 'unban' end, p_user, jsonb_build_object('reason', p_reason));
  return jsonb_build_object('ok', true, 'banned', p_ban);
end $$;

-- Grant (positive) or take back (negative) coins/gems. Balances never go below zero.
create or replace function public.nx_owner_grant(p_user uuid, p_coins int, p_gems int, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare g text := _nx_owner_guard(); c int := coalesce(p_coins, 0); gm int := coalesce(p_gems, 0); r record;
begin
  if g is not null then return jsonb_build_object('ok', false, 'error', g); end if;
  if abs(c) > 10000000 or abs(gm) > 10000000 then return jsonb_build_object('ok', false, 'error', 'amount_too_large'); end if;
  if c = 0 and gm = 0 then return jsonb_build_object('ok', false, 'error', 'zero_amount'); end if;
  update profiles set coins = coins + c, gems = coalesce(gems, 0) + gm
   where id = p_user and coins + c >= 0 and coalesce(gems, 0) + gm >= 0 returning coins, gems into r;
  if not found then
    if not exists (select 1 from profiles where id = p_user) then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
    return jsonb_build_object('ok', false, 'error', 'insufficient_balance');
  end if;
  perform _nx_owner_log('grant', p_user, jsonb_build_object('coins', c, 'gems', gm, 'reason', p_reason,
                                                             'balance_coins', r.coins, 'balance_gems', r.gems));
  return jsonb_build_object('ok', true, 'coins', r.coins, 'gems', r.gems);
end $$;

-- Assign/revoke staff roles: 'admin', 'organizer' (= tournament admin with unlimited hosting, counts toward the cap), 'player'.
create or replace function public.nx_owner_set_role(p_user uuid, p_role text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare g text := _nx_owner_guard(); cur nx_staff;
begin
  if g is not null then return jsonb_build_object('ok', false, 'error', g); end if;
  if p_user is null or not exists (select 1 from auth.users where id = p_user) then
    return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if nx_is_owner(p_user) then return jsonb_build_object('ok', false, 'error', 'cannot_change_owner'); end if;
  select * into cur from nx_staff where user_id = p_user for update;
  if p_role is null or p_role in ('', 'player') then
    delete from nx_staff where user_id = p_user;
  elsif p_role = 'admin' then
    insert into nx_staff(user_id, role, granted_by, unlimited) values (p_user, 'admin', auth.uid(), false)
    on conflict (user_id) do update set role = 'admin', unlimited = false, via_code = null, granted_by = auth.uid(), granted_at = now();
  elsif p_role = 'organizer' then
    if not coalesce(cur.role = 'organizer' and cur.unlimited, false) and _nx_tadmin_count() >= _nx_tadmin_cap() then
      return jsonb_build_object('ok', false, 'error', 'cap_reached', 'cap', _nx_tadmin_cap()); end if;
    insert into nx_staff(user_id, role, granted_by, unlimited) values (p_user, 'organizer', auth.uid(), true)
    on conflict (user_id) do update set role = 'organizer', unlimited = true, granted_by = auth.uid(), granted_at = now();
  else
    return jsonb_build_object('ok', false, 'error', 'bad_role');
  end if;
  perform _nx_owner_log('set_role', p_user, jsonb_build_object('role', coalesce(nullif(p_role, ''), 'player'), 'previous', cur.role));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.nx_owner_set_cap(p_cap int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare g text := _nx_owner_guard();
begin
  if g is not null then return jsonb_build_object('ok', false, 'error', g); end if;
  if p_cap is null or p_cap < 1 or p_cap > 1000 then return jsonb_build_object('ok', false, 'error', 'bad_cap'); end if;
  insert into nx_settings(key, value, updated_by, updated_at) values ('tadmin_cap', to_jsonb(p_cap), auth.uid(), now())
  on conflict (key) do update set value = excluded.value, updated_by = auth.uid(), updated_at = now();
  perform _nx_owner_log('set_tadmin_cap', null, jsonb_build_object('cap', p_cap));
  return jsonb_build_object('ok', true, 'cap', p_cap, 'active', _nx_tadmin_count());
end $$;

-- All tournaments (drafts too) with creator and entry counts. Actions go through nx_t_admin / nx_t_admin_match (owner = admin).
create or replace function public.nx_owner_tournaments(p_limit int default 100) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare g text := _nx_owner_guard(); res jsonb;
begin
  if g is not null then return jsonb_build_object('ok', false, 'error', g); end if;
  select coalesce(jsonb_agg(x order by x.created_at desc), '[]'::jsonb) into res from (
    select t.id, t.title, t.game, t.format, t.status, t.capacity, t.start_at, t.created_at, t.created_by, p.username as creator,
           (select count(*) from nx_t_entries e where e.tournament_id = t.id and e.status = 'approved') as players,
           (select count(*) from nx_t_matches m where m.tournament_id = t.id and m.status = 'disputed') as disputes,
           t.fee_coins, t.fee_gems, t.prize
      from nx_tournaments t left join profiles p on p.id = t.created_by
     order by t.created_at desc limit greatest(1, least(coalesce(p_limit, 100), 500))) x;
  return jsonb_build_object('ok', true, 'tournaments', res);
end $$;

-- Merged audit trail: console actions (nx_owner_audit) + tournament actions (nx_t_audit). Newest first.
create or replace function public.nx_owner_audit_list(p_limit int default 100, p_before timestamptz default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare g text := _nx_owner_guard(); res jsonb;
begin
  if g is not null then return jsonb_build_object('ok', false, 'error', g); end if;
  select coalesce(jsonb_agg(x order by x.created_at desc), '[]'::jsonb) into res from (
    select * from (
      select 'owner' as source, a.created_at, a.action, a.actor, pa.username as actor_name, a.target, pt.username as target_name,
             null::uuid as tournament_id, a.data
        from nx_owner_audit a left join profiles pa on pa.id = a.actor left join profiles pt on pt.id = a.target
       where p_before is null or a.created_at < p_before
      union all
      select 'tournament', a.created_at, a.action, a.actor, pa.username, null, null, a.tournament_id, a.data
        from nx_t_audit a left join profiles pa on pa.id = a.actor
       where p_before is null or a.created_at < p_before) u
    order by created_at desc limit greatest(1, least(coalesce(p_limit, 100), 500))) x;
  return jsonb_build_object('ok', true, 'entries', res);
end $$;

-- ---------------------------------------------------------------------------
-- grants
-- ---------------------------------------------------------------------------
revoke execute on function public._nx_owner_guard(), public._nx_owner_log(text, uuid, jsonb), public._nx_tadmin_cap(),
  public._nx_tadmin_count(), public._nx_password_changed(), public._nx_t_charge(uuid, uuid, int, int),
  public._nx_t_refund(uuid, uuid, text) from public, anon, authenticated;
revoke execute on function public.nx_is_owner(uuid), public.nx_unlimited(uuid), public.nx_is_banned(uuid), public.nx_my_access(),
  public.nx_t_my_role(), public.nx_t_save(jsonb), public.nx_owner_stats(), public.nx_owner_users(text, int, int),
  public.nx_owner_ban(uuid, boolean, text), public.nx_owner_grant(uuid, int, int, text), public.nx_owner_set_role(uuid, text),
  public.nx_owner_set_cap(int), public.nx_owner_tournaments(int), public.nx_owner_audit_list(int, timestamptz) from public, anon;
grant execute on function public.nx_is_owner(uuid), public.nx_unlimited(uuid), public.nx_is_banned(uuid), public.nx_my_access(),
  public.nx_t_my_role(), public.nx_t_save(jsonb), public.nx_owner_stats(), public.nx_owner_users(text, int, int),
  public.nx_owner_ban(uuid, boolean, text), public.nx_owner_grant(uuid, int, int, text), public.nx_owner_set_role(uuid, text),
  public.nx_owner_set_cap(int), public.nx_owner_tournaments(int), public.nx_owner_audit_list(int, timestamptz) to authenticated;

-- Admin tool nx_t_set_staff may never touch the owner, nor hand out 'owner'.
create or replace function public.nx_t_set_staff(p_user uuid, p_role text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if not nx_t_is_admin(me) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  if nx_is_owner(p_user) then return jsonb_build_object('ok', false, 'error', 'cannot_change_owner'); end if;
  if p_role is null or p_role = '' or p_role = 'player' then
    delete from nx_staff where user_id = p_user;
  elsif p_role in ('admin', 'organizer') then
    insert into nx_staff(user_id, role, granted_by) values (p_user, p_role, me)
    on conflict (user_id) do update set role = excluded.role, granted_by = me, granted_at = now();
  else
    return jsonb_build_object('ok', false, 'error', 'bad_role');
  end if;
  perform _nx_t_audit(null, me, 'set_staff', jsonb_build_object('user', p_user, 'role', p_role));
  return jsonb_build_object('ok', true);
end $$;
