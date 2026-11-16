-- NEXORA tournaments · engine (internal functions; not callable by clients).
-- Bracket generation (single/double elimination, two legs, round robin, groups→KO, swiss), byes, advancement,
-- series (Bo1/2/3/5, aggregate, golden-goal deciders), ready checks, walkovers, placements, escrow + payouts.
-- The pure-Dart mirror lives in lib/features/tournaments/domain (unit-tested); keep both in sync.

-- ---------------------------------------------------------------------------
-- small helpers
-- ---------------------------------------------------------------------------
create or replace function public._nx_t_cfg_int(c jsonb, k text, d int) returns int
language sql immutable as $$
  select case when jsonb_typeof(c -> k) = 'number' then (c ->> k)::numeric::int
              when jsonb_typeof(c -> k) = 'string' and (c ->> k) ~ '^-?[0-9]+$' then (c ->> k)::int
              else d end
$$;

create or replace function public._nx_t_cfg_bool(c jsonb, k text, d boolean) returns boolean
language sql immutable as $$
  select case when jsonb_typeof(c -> k) = 'boolean' then (c ->> k)::boolean else d end
$$;

create or replace function public._nx_t_audit(p_t uuid, p_actor uuid, p_action text, p_data jsonb default '{}'::jsonb)
returns void language sql security definer set search_path = public as $$
  insert into nx_t_audit(tournament_id, actor, action, data) values (p_t, p_actor, p_action, coalesce(p_data, '{}'::jsonb));
$$;

create or replace function public._nx_t_notify(p_user uuid, p_t uuid, p_tm uuid, p_kind text, p_data jsonb default '{}'::jsonb,
                                               p_dedup text default null)
returns void language plpgsql security definer set search_path = public as $$
declare ttl text;
begin
  if p_user is null then return; end if;
  select title into ttl from nx_tournaments where id = p_t;
  insert into nx_t_notifications(user_id, tournament_id, tmatch, kind, data, dedup)
  values (p_user, p_t, p_tm, p_kind, coalesce(p_data, '{}'::jsonb) || jsonb_build_object('title', ttl), p_dedup)
  on conflict (user_id, dedup) do nothing;
end $$;

-- Notify every entry of a tournament with one of the given statuses.
create or replace function public._nx_t_notify_all(p_t uuid, p_kind text, p_data jsonb, p_dedup text,
                                                   p_statuses text[] default array['approved'])
returns void language plpgsql security definer set search_path = public as $$
declare r record;
begin
  for r in select user_id from nx_t_entries where tournament_id = p_t and status = any(p_statuses) loop
    perform _nx_t_notify(r.user_id, p_t, null, p_kind, p_data, case when p_dedup is null then null else p_dedup end);
  end loop;
end $$;

-- Managers (creator, runners, nx admins) of a tournament.
create or replace function public._nx_t_notify_managers(p_t uuid, p_tm uuid, p_kind text, p_data jsonb, p_dedup text)
returns void language plpgsql security definer set search_path = public as $$
declare u uuid;
begin
  for u in
    select created_by from nx_tournaments where id = p_t
    union select user_id from nx_t_staff where tournament_id = p_t
    union select user_id from nx_staff where role = 'admin'
  loop
    perform _nx_t_notify(u, p_t, p_tm, p_kind, p_data, p_dedup);
  end loop;
end $$;

create or replace function public._nx_t_job(p_kind text, p_t uuid, p_ref uuid, p_run timestamptz, p_key text)
returns void language sql security definer set search_path = public as $$
  insert into nx_t_jobs(kind, tournament_id, ref, run_at, idem_key) values (p_kind, p_t, p_ref, p_run, p_key)
  on conflict (idem_key) do update set run_at = excluded.run_at, last_error = null
   where nx_t_jobs.done_at is null;
$$;

-- (Re)create the time-based jobs of a published tournament.
create or replace function public._nx_t_sync_jobs(p_t uuid) returns void
language plpgsql security definer set search_path = public as $$
declare t nx_tournaments;
begin
  select * into t from nx_tournaments where id = p_t;
  if t.id is null or t.status in ('draft', 'finished', 'cancelled') then return; end if;
  perform _nx_t_job('open_reg', t.id, null, t.reg_open_at, 'open_reg:' || t.id);
  perform _nx_t_job('close_reg', t.id, null, t.reg_close_at, 'close_reg:' || t.id);
  perform _nx_t_job('draw', t.id, null, t.draw_at, 'draw:' || t.id);
  perform _nx_t_job('start', t.id, null, t.start_at, 'start:' || t.id);
  if t.start_at - interval '10 minutes' > now() then
    perform _nx_t_job('remind_start', t.id, null, t.start_at - interval '10 minutes', 'remind_start:' || t.id);
  end if;
end $$;

-- Best-of for a round kind ('early' | 'semi' | 'final').
create or replace function public._nx_t_bo(t nx_tournaments, p_kind text) returns int
language plpgsql immutable as $$
declare v int;
begin
  if t.format = 'two_legs' then
    if p_kind = 'final' and _nx_t_cfg_bool(t.config, 'final_one_leg', false) then return 1; end if;
    return 2;
  end if;
  v := _nx_t_cfg_int(t.config, 'bo_' || p_kind, _nx_t_cfg_int(t.config, 'bo_early', 1));
  if v not in (1, 2, 3, 5) then v := 1; end if;
  return v;
end $$;

-- Planned start time of a time slot (1-based): explicit round_starts[] or start_at + (slot-1) * round_minutes.
create or replace function public._nx_t_planned(t nx_tournaments, p_slot int) returns timestamptz
language plpgsql stable as $$
declare a jsonb := t.config -> 'round_starts'; v text;
begin
  if jsonb_typeof(a) = 'array' and jsonb_array_length(a) >= p_slot and p_slot >= 1 then
    v := a ->> (p_slot - 1);
    if v is not null and v <> '' then
      begin return v::timestamptz; exception when others then null; end;
    end if;
  end if;
  return t.start_at + make_interval(mins => greatest(0, p_slot - 1) * greatest(1, _nx_t_cfg_int(t.config, 'round_minutes', 20)));
end $$;

-- Standard bracket order for P (power of two): 1,P,P/2+1,... so seeds 1 and 2 meet only in the final.
create or replace function public._nx_t_seed_order(p int) returns int[]
language plpgsql immutable as $$
declare a int[] := array[1]; b int[]; n int := 1; x int;
begin
  while n < p loop
    n := n * 2; b := '{}';
    foreach x in array a loop b := b || x || (n + 1 - x); end loop;
    a := b;
  end loop;
  return a;
end $$;

create or replace function public._nx_t_mid(p_t uuid, p_stage text, p_bracket text, p_round int, p_idx int) returns uuid
language sql stable security definer set search_path = public as $$
  select id from nx_t_matches where tournament_id = p_t and stage = p_stage and bracket = p_bracket
     and round = p_round and idx = p_idx limit 1
$$;

create or replace function public._nx_t_new_match(t nx_tournaments, p_stage text, p_bracket text, p_round int, p_idx int,
                                                  p_slot int, p_group int, p_bo int, p_label text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare mid uuid;
begin
  insert into nx_t_matches(tournament_id, stage, bracket, round, idx, tslot, group_no, best_of, aggregate, label)
  values (t.id, p_stage, p_bracket, p_round, p_idx, p_slot, p_group, p_bo,
          t.format = 'two_legs' and p_bo = 2, p_label)
  returning id into mid;
  return mid;
end $$;

create or replace function public._nx_t_gen_on() returns boolean language sql stable as $$
  select coalesce(current_setting('nx.tgen', true), '') = 'on'
$$;

-- ---------------------------------------------------------------------------
-- advancement core
-- ---------------------------------------------------------------------------
create or replace function public._nx_t_put(p_m uuid, p_slot int, p_player uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_m is null then return; end if;
  if p_slot = 1 then
    update nx_t_matches set p1 = p_player, p1_set = true, updated_at = now() where id = p_m;
  else
    update nx_t_matches set p2 = p_player, p2_set = true, updated_at = now() where id = p_m;
  end if;
  perform _nx_t_check(p_m);
end $$;

create or replace function public._nx_t_check(p_m uuid) returns void
language plpgsql security definer set search_path = public as $$
declare m nx_t_matches; t nx_tournaments; at timestamptz;
begin
  select * into m from nx_t_matches where id = p_m for update;
  if m.id is null or m.status <> 'pending' or not (m.p1_set and m.p2_set) then return; end if;
  if m.p1 is null or m.p2 is null then
    perform _nx_t_complete(m.id, coalesce(m.p1, m.p2), null, false, 'bye', 'bye');
    return;
  end if;
  select * into t from nx_tournaments where id = m.tournament_id;
  at := greatest(_nx_t_planned(t, m.tslot), now());
  update nx_t_matches set status = 'scheduled', scheduled_at = at, updated_at = now() where id = m.id;
  if at - interval '10 minutes' > now() + interval '1 minute' then
    perform _nx_t_job('remind_match', t.id, m.id, at - interval '10 minutes', 'remind_match:' || m.id);
  end if;
end $$;

create or replace function public._nx_t_propagate(p_m uuid) returns void
language plpgsql security definer set search_path = public as $$
declare m nx_t_matches; gf2 uuid;
begin
  select * into m from nx_t_matches where id = p_m;
  if m.bracket = 'GF' then
    select id into gf2 from nx_t_matches where tournament_id = m.tournament_id and bracket = 'GF2' and status = 'pending';
    if gf2 is null then return; end if;
    if m.winner is not distinct from m.p1 or m.p2 is null or m.p1 is null then
      update nx_t_matches set status = 'skipped', result_note = 'winners_bracket_champion', updated_at = now() where id = gf2;
    else
      perform _nx_t_put(gf2, 1, m.p1);
      perform _nx_t_put(gf2, 2, m.p2);
    end if;
    return;
  end if;
  if m.win_to is not null then perform _nx_t_put(m.win_to, m.win_slot, m.winner); end if;
  if m.lose_to is not null then perform _nx_t_put(m.lose_to, m.lose_slot, m.loser); end if;
end $$;

-- Final result of a tournament match → notify, propagate, maybe advance the tournament.
create or replace function public._nx_t_complete(p_m uuid, p_winner uuid, p_loser uuid, p_draw boolean, p_status text,
                                                 p_note text default null)
returns void language plpgsql security definer set search_path = public as $$
declare m nx_t_matches; elim boolean;
begin
  update nx_t_matches set winner = p_winner, loser = p_loser, is_draw = coalesce(p_draw, false), status = p_status,
         result_note = coalesce(p_note, result_note), finished_at = now(), game_match = null, ready_deadline = null,
         updated_at = now()
   where id = p_m and status not in ('done', 'walkover', 'bye', 'void', 'skipped')
  returning * into m;
  if m.id is null then return; end if;
  if not _nx_t_gen_on() and p_status <> 'bye' then
    elim := m.bracket in ('W', 'L', 'GF', 'GF2', 'P3');
    perform _nx_t_notify(m.p1, m.tournament_id, m.id, 'result',
      jsonb_build_object('won', p_winner = m.p1, 'draw', coalesce(p_draw, false), 'w1', m.w1, 'w2', m.w2, 'g1', m.g1, 'g2', m.g2,
                         'note', p_note), 'result:' || m.id);
    perform _nx_t_notify(m.p2, m.tournament_id, m.id, 'result',
      jsonb_build_object('won', p_winner = m.p2, 'draw', coalesce(p_draw, false), 'w1', m.w1, 'w2', m.w2, 'g1', m.g1, 'g2', m.g2,
                         'note', p_note), 'result:' || m.id);
    if elim then
      if p_winner is not null and (m.win_to is not null or m.bracket = 'GF' and p_winner <> m.p1) then
        perform _nx_t_notify(p_winner, m.tournament_id, m.id, 'advanced', '{}'::jsonb, 'adv:' || m.id);
      end if;
      if p_loser is not null and m.lose_to is null and not (m.bracket = 'GF' and p_loser = m.p1) then
        perform _nx_t_notify(p_loser, m.tournament_id, m.id, 'eliminated', '{}'::jsonb, 'elim:' || m.id);
      end if;
    end if;
  elsif p_status = 'bye' and not _nx_t_gen_on() and p_winner is not null then
    perform _nx_t_notify(p_winner, m.tournament_id, m.id, 'bye', '{}'::jsonb, 'bye:' || m.id);
  end if;
  perform _nx_t_audit(m.tournament_id, null, 'match_' || p_status,
                      jsonb_build_object('match', m.id, 'winner', p_winner, 'loser', p_loser, 'draw', p_draw, 'note', p_note));
  perform _nx_t_propagate(m.id);
  perform _nx_t_progress(m.tournament_id);
end $$;

-- ---------------------------------------------------------------------------
-- generators
-- ---------------------------------------------------------------------------
-- Single elimination over players[] (already in seed order). Returns the final's id.
create or replace function public._nx_t_gen_se(p_t uuid, players uuid[], p_stage text, r_off int, s_off int)
returns uuid language plpgsql security definer set search_path = public as $$
declare t nx_tournaments; n int := coalesce(array_length(players, 1), 0); k int := 0; p int; ord int[];
        r int; i int; cnt int; mid uuid; final_id uuid; p3 uuid; kind text; a int; b int; nxt uuid;
begin
  select * into t from nx_tournaments where id = p_t;
  if n < 2 then return null; end if;
  while (1 << k) < n loop k := k + 1; end loop;
  p := 1 << k;
  ord := _nx_t_seed_order(p);
  perform set_config('nx.tgen', 'on', true);
  for r in 1..k loop
    cnt := p >> r;
    kind := case when r = k then 'final' when r = k - 1 then 'semi' else 'early' end;
    for i in 0..cnt - 1 loop
      mid := _nx_t_new_match(t, p_stage, 'W', r_off + r, i, s_off + r, null, _nx_t_bo(t, kind));
      if r = k then final_id := mid; end if;
    end loop;
  end loop;
  for r in 1..k - 1 loop
    for i in 0..(p >> r) - 1 loop
      nxt := _nx_t_mid(p_t, p_stage, 'W', r_off + r + 1, i / 2);
      update nx_t_matches set win_to = nxt, win_slot = (i % 2) + 1
       where id = _nx_t_mid(p_t, p_stage, 'W', r_off + r, i);
    end loop;
  end loop;
  if k >= 2 and _nx_t_cfg_bool(t.config, 'third_place', false) then
    p3 := _nx_t_new_match(t, p_stage, 'P3', r_off + k, 0, s_off + k, null, _nx_t_bo(t, 'final'));
    update nx_t_matches set lose_to = p3, lose_slot = 1 where id = _nx_t_mid(p_t, p_stage, 'W', r_off + k - 1, 0);
    update nx_t_matches set lose_to = p3, lose_slot = 2 where id = _nx_t_mid(p_t, p_stage, 'W', r_off + k - 1, 1);
  end if;
  for i in 0..(p / 2) - 1 loop
    a := ord[2 * i + 1]; b := ord[2 * i + 2];
    mid := _nx_t_mid(p_t, p_stage, 'W', r_off + 1, i);
    update nx_t_matches set p1 = case when a <= n then players[a] end, p1_set = true,
                            p2 = case when b <= n then players[b] end, p2_set = true where id = mid;
    perform _nx_t_check(mid);
  end loop;
  perform set_config('nx.tgen', 'off', true);
  return final_id;
end $$;

-- Double elimination: winners bracket W (k rounds), losers bracket L (2(k-1) rounds), grand final GF + reset GF2.
create or replace function public._nx_t_lb_count(p int, m int) returns int language sql immutable as $$
  select case when m = 1 then p >> 2 when m % 2 = 0 then p >> (m / 2 + 1) else p >> ((m - 1) / 2 + 2) end
$$;

create or replace function public._nx_t_gen_de(p_t uuid, players uuid[]) returns void
language plpgsql security definer set search_path = public as $$
declare t nx_tournaments; n int := coalesce(array_length(players, 1), 0); k int := 0; p int; ord int[];
        r int; i int; m int; cnt int; mid uuid; gf uuid; gf2 uuid; lrounds int; kind text; a int; b int; j int;
begin
  select * into t from nx_tournaments where id = p_t;
  if n < 2 then return; end if;
  while (1 << k) < n loop k := k + 1; end loop;
  p := 1 << k;
  ord := _nx_t_seed_order(p);
  lrounds := 2 * (k - 1);
  perform set_config('nx.tgen', 'on', true);
  for r in 1..k loop
    kind := case when r = k then 'final' when r = k - 1 then 'semi' else 'early' end;
    for i in 0..(p >> r) - 1 loop
      perform _nx_t_new_match(t, 'main', 'W', r, i, r, null, _nx_t_bo(t, kind));
    end loop;
  end loop;
  for m in 1..lrounds loop
    cnt := _nx_t_lb_count(p, m);
    kind := case when m = lrounds then 'semi' else 'early' end;
    for i in 0..cnt - 1 loop
      perform _nx_t_new_match(t, 'main', 'L', m, i, m + 1, null, _nx_t_bo(t, kind));
    end loop;
  end loop;
  gf := _nx_t_new_match(t, 'main', 'GF', 1, 0, greatest(2 * k, lrounds + 2), null, _nx_t_bo(t, 'final'));
  gf2 := _nx_t_new_match(t, 'main', 'GF2', 1, 0, greatest(2 * k, lrounds + 2) + 1, null, _nx_t_bo(t, 'final'));
  -- winners bracket links
  for r in 1..k loop
    for i in 0..(p >> r) - 1 loop
      mid := _nx_t_mid(p_t, 'main', 'W', r, i);
      if r < k then
        update nx_t_matches set win_to = _nx_t_mid(p_t, 'main', 'W', r + 1, i / 2), win_slot = (i % 2) + 1 where id = mid;
      else
        update nx_t_matches set win_to = gf, win_slot = 1 where id = mid;
      end if;
      if k = 1 then
        update nx_t_matches set lose_to = gf, lose_slot = 2 where id = mid;
      elsif r = 1 then
        update nx_t_matches set lose_to = _nx_t_mid(p_t, 'main', 'L', 1, i / 2), lose_slot = (i % 2) + 1 where id = mid;
      else
        cnt := p >> r;
        j := case when r % 2 = 0 then cnt - 1 - i else i end;
        update nx_t_matches set lose_to = _nx_t_mid(p_t, 'main', 'L', 2 * (r - 1), j), lose_slot = 2 where id = mid;
      end if;
    end loop;
  end loop;
  -- losers bracket links
  for m in 1..lrounds loop
    cnt := _nx_t_lb_count(p, m);
    for i in 0..cnt - 1 loop
      mid := _nx_t_mid(p_t, 'main', 'L', m, i);
      if m = lrounds then
        update nx_t_matches set win_to = gf, win_slot = 2 where id = mid;
      elsif m % 2 = 1 then
        update nx_t_matches set win_to = _nx_t_mid(p_t, 'main', 'L', m + 1, i), win_slot = 1 where id = mid;
      else
        update nx_t_matches set win_to = _nx_t_mid(p_t, 'main', 'L', m + 1, i / 2), win_slot = (i % 2) + 1 where id = mid;
      end if;
    end loop;
  end loop;
  for i in 0..(p / 2) - 1 loop
    a := ord[2 * i + 1]; b := ord[2 * i + 2];
    mid := _nx_t_mid(p_t, 'main', 'W', 1, i);
    update nx_t_matches set p1 = case when a <= n then players[a] end, p1_set = true,
                            p2 = case when b <= n then players[b] end, p2_set = true where id = mid;
    perform _nx_t_check(mid);
  end loop;
  perform set_config('nx.tgen', 'off', true);
end $$;

-- Round robin (circle method). Returns the number of rounds created.
create or replace function public._nx_t_gen_rr(p_t uuid, players uuid[], p_group int, p_double boolean, r_off int,
                                               s_off int, p_bracket text, p_stage text)
returns int language plpgsql security definer set search_path = public as $$
declare t nx_tournaments; arr uuid[] := players; m int; rounds int; cyc int; r int; i int; a uuid; b uuid; tmp uuid;
        rr int; mid uuid; idx int;
begin
  select * into t from nx_tournaments where id = p_t;
  if coalesce(array_length(arr, 1), 0) < 2 then return 0; end if;
  if array_length(arr, 1) % 2 = 1 then arr := arr || null::uuid; end if;
  m := array_length(arr, 1);
  rounds := m - 1;
  perform set_config('nx.tgen', 'on', true);
  for cyc in 0..(case when p_double then 1 else 0 end) loop
    arr := players;
    if array_length(arr, 1) % 2 = 1 then arr := arr || null::uuid; end if;
    for r in 0..rounds - 1 loop
      rr := cyc * rounds + r + 1;
      idx := 0;
      for i in 0..(m / 2) - 1 loop
        a := arr[i + 1]; b := arr[m - i];
        if a is not null and b is not null then
          if (r % 2 = 1 and i = 0) <> (cyc = 1) then tmp := a; a := b; b := tmp; end if;
          mid := _nx_t_new_match(t, p_stage, p_bracket, r_off + rr, idx, s_off + rr, p_group, _nx_t_bo(t, 'early'));
          update nx_t_matches set p1 = a, p1_set = true, p2 = b, p2_set = true where id = mid;
          perform _nx_t_check(mid);
          idx := idx + 1;
        end if;
      end loop;
      -- rotate all but the first
      arr := array[arr[1], arr[m]] || arr[2:m - 1];
    end loop;
  end loop;
  perform set_config('nx.tgen', 'off', true);
  return rounds * (case when p_double then 2 else 1 end);
end $$;

-- League table of a stage (optionally one group). Byes and walkovers count as wins.
create or replace function public._nx_t_table(p_t uuid, p_stage text, p_group int)
returns table(user_id uuid, seed int, played int, won int, drawn int, lost int, gf int, ga int, pts int)
language sql stable security definer set search_path = public as $$
  with t as (select * from nx_tournaments where id = p_t),
  rows as (
    select m.p1 as u, m.p2 as o, m.winner, m.is_draw, m.g1 as f, m.g2 as a, m.status from nx_t_matches m
     where m.tournament_id = p_t and m.stage = p_stage and m.bracket in ('RR', 'G', 'SW', 'C') and m.p1 is not null
       and (p_group is null or m.group_no = p_group) and m.status in ('done', 'walkover', 'bye')
    union all
    select m.p2, m.p1, m.winner, m.is_draw, m.g2, m.g1, m.status from nx_t_matches m
     where m.tournament_id = p_t and m.stage = p_stage and m.bracket in ('RR', 'G', 'SW', 'C') and m.p2 is not null
       and (p_group is null or m.group_no = p_group) and m.status in ('done', 'walkover', 'bye')
  )
  select e.user_id, e.seed,
         count(r.u)::int,
         count(r.u) filter (where r.winner = e.user_id)::int,
         count(r.u) filter (where r.is_draw)::int,
         count(r.u) filter (where r.winner is distinct from e.user_id and not r.is_draw)::int,
         coalesce(sum(r.f), 0)::int, coalesce(sum(r.a), 0)::int,
         (count(r.u) filter (where r.winner = e.user_id) * _nx_t_cfg_int((select config from t), 'points_win', 3)
          + count(r.u) filter (where r.is_draw) * _nx_t_cfg_int((select config from t), 'points_draw', 1))::int
    from nx_t_entries e left join rows r on r.u = e.user_id
   where e.tournament_id = p_t and e.status = 'approved' and (p_group is null or e.group_no = p_group)
   group by e.user_id, e.seed
$$;

-- Swiss: pair round r (1 = by seed halves, then by points avoiding rematches; odd → bye to lowest without one).
create or replace function public._nx_t_swiss_round(p_t uuid, p_r int) returns void
language plpgsql security definer set search_path = public as $$
declare t nx_tournaments; ord uuid[]; n int; h int; i int; j int; used boolean[]; bye uuid; mid uuid; idx int := 0;
        partner int;
begin
  select * into t from nx_tournaments where id = p_t;
  if p_r = 1 then
    select array_agg(user_id order by seed) into ord from nx_t_entries where tournament_id = p_t and status = 'approved';
  else
    select array_agg(x.user_id order by x.pts desc, (x.gf - x.ga) desc, x.gf desc, x.seed) into ord
      from _nx_t_table(p_t, 'main', null) x;
  end if;
  n := coalesce(array_length(ord, 1), 0);
  if n < 2 then return; end if;
  perform set_config('nx.tgen', 'on', true);
  if n % 2 = 1 then
    for i in reverse n..1 loop
      if not exists (select 1 from nx_t_matches where tournament_id = p_t and bracket = 'SW' and status = 'bye'
                      and p1 = ord[i]) then
        bye := ord[i]; exit;
      end if;
    end loop;
    if bye is null then bye := ord[n]; end if;
    ord := array_remove(ord, bye);
    n := n - 1;
  end if;
  if p_r = 1 then
    h := n / 2;
    for i in 1..h loop
      mid := _nx_t_new_match(t, 'main', 'SW', p_r, idx, p_r, null, _nx_t_bo(t, 'early'));
      update nx_t_matches set p1 = ord[i], p1_set = true, p2 = ord[i + h], p2_set = true where id = mid;
      perform _nx_t_check(mid); idx := idx + 1;
    end loop;
  else
    used := array_fill(false, array[n]);
    for i in 1..n loop
      continue when used[i];
      partner := null;
      for j in i + 1..n loop
        continue when used[j];
        if not exists (select 1 from nx_t_matches where tournament_id = p_t and bracket = 'SW'
                        and ((p1 = ord[i] and p2 = ord[j]) or (p1 = ord[j] and p2 = ord[i]))) then
          partner := j; exit;
        end if;
      end loop;
      if partner is null then
        for j in i + 1..n loop
          if not used[j] then partner := j; exit; end if;
        end loop;
      end if;
      exit when partner is null;
      used[i] := true; used[partner] := true;
      mid := _nx_t_new_match(t, 'main', 'SW', p_r, idx, p_r, null, _nx_t_bo(t, 'early'));
      update nx_t_matches set p1 = ord[i], p1_set = true, p2 = ord[partner], p2_set = true where id = mid;
      perform _nx_t_check(mid); idx := idx + 1;
    end loop;
  end if;
  if bye is not null then
    mid := _nx_t_new_match(t, 'main', 'SW', p_r, idx, p_r, null, 1);
    update nx_t_matches set p1 = bye, p1_set = true, p2 = null, p2_set = true where id = mid;
    perform _nx_t_check(mid);
  end if;
  perform set_config('nx.tgen', 'off', true);
  update nx_tournaments set updated_at = now() where id = p_t;
end $$;

-- ---------------------------------------------------------------------------
-- money: escrow, refunds, payouts (immutable ledger, idempotency keys)
-- ---------------------------------------------------------------------------
create or replace function public._nx_t_refund(p_t uuid, p_user uuid, p_reason text) returns boolean
language plpgsql security definer set search_path = public as $$
declare e nx_t_entries; got boolean := false;
begin
  select * into e from nx_t_entries where tournament_id = p_t and user_id = p_user for update;
  if e.user_id is null or (e.paid_coins = 0 and e.paid_gems = 0) then return false; end if;
  if e.paid_coins > 0 then
    insert into nx_t_ledger(tournament_id, user_id, kind, currency, amount, idem_key)
    values (p_t, p_user, 'refund', 'coins', e.paid_coins, 'refund:coins:' || coalesce(e.fee_ref::text, p_t || ':' || p_user))
    on conflict (idem_key) do nothing;
    if found then
      update profiles set coins = coins + e.paid_coins where id = p_user;
      update nx_tournaments set escrow_coins = greatest(0, escrow_coins - e.paid_coins) where id = p_t;
      got := true;
    end if;
  end if;
  if e.paid_gems > 0 then
    insert into nx_t_ledger(tournament_id, user_id, kind, currency, amount, idem_key)
    values (p_t, p_user, 'refund', 'gems', e.paid_gems, 'refund:gems:' || coalesce(e.fee_ref::text, p_t || ':' || p_user))
    on conflict (idem_key) do nothing;
    if found then
      update profiles set gems = gems + e.paid_gems where id = p_user;
      update nx_tournaments set escrow_gems = greatest(0, escrow_gems - e.paid_gems) where id = p_t;
      got := true;
    end if;
  end if;
  update nx_t_entries set paid_coins = 0, paid_gems = 0, updated_at = now() where tournament_id = p_t and user_id = p_user;
  if got then
    perform _nx_t_notify(p_user, p_t, null, 'refund', jsonb_build_object('coins', e.paid_coins, 'gems', e.paid_gems,
                         'reason', p_reason), 'refund:' || coalesce(e.fee_ref::text, p_user::text));
  end if;
  return got;
end $$;

-- Charge the entry fee into escrow. Returns the ledger id (0 when free) or null when the balance is too low.
create or replace function public._nx_t_charge(p_t uuid, p_user uuid, p_coins int, p_gems int) returns bigint
language plpgsql security definer set search_path = public as $$
declare lid bigint; ok uuid; k text := 'fee:' || p_t || ':' || p_user || ':' || floor(extract(epoch from clock_timestamp()) * 1000)::bigint;
begin
  if coalesce(p_coins, 0) = 0 and coalesce(p_gems, 0) = 0 then return 0; end if;
  update profiles set coins = coins - p_coins, gems = coalesce(gems, 0) - p_gems
   where id = p_user and coins >= p_coins and coalesce(gems, 0) >= p_gems returning id into ok;
  if ok is null then return null; end if;
  if p_coins > 0 then
    insert into nx_t_ledger(tournament_id, user_id, kind, currency, amount, idem_key)
    values (p_t, p_user, 'entry_fee', 'coins', -p_coins, k || ':c') returning id into lid;
  end if;
  if p_gems > 0 then
    insert into nx_t_ledger(tournament_id, user_id, kind, currency, amount, idem_key)
    values (p_t, p_user, 'entry_fee', 'gems', -p_gems, k || ':g') returning id into lid;
  end if;
  update nx_tournaments set escrow_coins = escrow_coins + p_coins, escrow_gems = escrow_gems + p_gems where id = p_t;
  return lid;
end $$;

-- Prize total for one currency: fixed + pool% of escrow − house fee% of that pool part.
create or replace function public._nx_t_prize_total(p_fixed int, p_escrow int, p_pool_pct int, p_fee_pct int)
returns int language sql immutable as $$
  select greatest(0, coalesce(p_fixed, 0))
       + (greatest(0, coalesce(p_escrow, 0)) * least(100, greatest(0, coalesce(p_pool_pct, 0))) / 100)
       - ((greatest(0, coalesce(p_escrow, 0)) * least(100, greatest(0, coalesce(p_pool_pct, 0))) / 100)
          * least(100, greatest(0, coalesce(p_fee_pct, 0))) / 100)
$$;

-- Amount per user for a currency (same algorithm as PrizeSplit in Dart): users sharing a place split the
-- percentages of the places they cover; the rounding remainder goes to the (first) champion.
create or replace function public._nx_t_split(p_t uuid, p_total int, p_dist int[])
returns table(user_id uuid, place int, amount int)
language plpgsql stable security definer set search_path = public as $$
declare r record; k int; share int; i int; paid int := 0; top uuid; dsum int := 0; first_place int;
begin
  if p_total <= 0 or p_dist is null then return; end if;
  for i in 1..coalesce(array_length(p_dist, 1), 0) loop dsum := dsum + greatest(0, p_dist[i]); end loop;
  select min(e.place) into first_place from nx_t_entries e where e.tournament_id = p_t and e.status = 'approved' and e.place is not null;
  for r in select e.place as pl, array_agg(e.user_id order by e.seed nulls last, e.user_id) as us
             from nx_t_entries e where e.tournament_id = p_t and e.status = 'approved' and e.place is not null
            group by e.place order by e.place loop
    k := array_length(r.us, 1);
    share := 0;
    for i in r.pl..r.pl + k - 1 loop
      if i <= coalesce(array_length(p_dist, 1), 0) then share := share + greatest(0, p_dist[i]); end if;
    end loop;
    if share > 0 then
      for i in 1..k loop
        user_id := r.us[i]; place := r.pl; amount := (p_total::bigint * share / 100 / k)::int;
        paid := paid + amount;
        if top is null and r.pl = first_place then top := r.us[i]; end if;
        return next;
      end loop;
    end if;
  end loop;
  if top is not null and (p_total::bigint * least(100, dsum) / 100)::int - paid > 0 then
    user_id := top; place := first_place; amount := (p_total::bigint * least(100, dsum) / 100)::int - paid;
    return next;
  end if;
end $$;

create or replace function public._nx_t_payout(p_t uuid) returns void
language plpgsql security definer set search_path = public as $$
declare t nx_tournaments; dist int[]; tc int; tg int; r record; pool int;
begin
  select * into t from nx_tournaments where id = p_t for update;
  if t.id is null or t.paid_out then return; end if;
  select coalesce(array_agg(v::numeric::int order by o), array[60, 30, 10]) into dist
    from jsonb_array_elements_text(case when jsonb_typeof(t.prize -> 'dist') = 'array' then t.prize -> 'dist' else '[60,30,10]'::jsonb end)
         with ordinality as x(v, o);
  tc := _nx_t_prize_total(_nx_t_cfg_int(t.prize, 'fixed_coins', 0), t.escrow_coins, _nx_t_cfg_int(t.prize, 'pool_pct', 0),
                          _nx_t_cfg_int(t.prize, 'fee_pct', 0));
  tg := _nx_t_prize_total(_nx_t_cfg_int(t.prize, 'fixed_gems', 0), t.escrow_gems, _nx_t_cfg_int(t.prize, 'pool_pct', 0),
                          _nx_t_cfg_int(t.prize, 'fee_pct', 0));
  for r in select s.user_id, min(s.place) as place, sum(s.amount)::int as amount from _nx_t_split(p_t, tc, dist) s group by s.user_id loop
    continue when r.amount <= 0;
    insert into nx_t_ledger(tournament_id, user_id, kind, currency, amount, place, idem_key)
    values (p_t, r.user_id, 'payout', 'coins', r.amount, r.place, 'payout:' || p_t || ':' || r.user_id || ':coins')
    on conflict (idem_key) do nothing;
    if found then
      update profiles set coins = coins + r.amount where id = r.user_id;
      perform _nx_t_notify(r.user_id, p_t, null, 'prize', jsonb_build_object('coins', r.amount, 'place', r.place),
                           'prize:coins:' || p_t);
    end if;
  end loop;
  for r in select s.user_id, min(s.place) as place, sum(s.amount)::int as amount from _nx_t_split(p_t, tg, dist) s group by s.user_id loop
    continue when r.amount <= 0;
    insert into nx_t_ledger(tournament_id, user_id, kind, currency, amount, place, idem_key)
    values (p_t, r.user_id, 'payout', 'gems', r.amount, r.place, 'payout:' || p_t || ':' || r.user_id || ':gems')
    on conflict (idem_key) do nothing;
    if found then
      update profiles set gems = coalesce(gems, 0) + r.amount where id = r.user_id;
      perform _nx_t_notify(r.user_id, p_t, null, 'prize', jsonb_build_object('gems', r.amount, 'place', r.place),
                           'prize:gems:' || p_t);
    end if;
  end loop;
  -- the rest of the escrow (house fee + the part not in the pool) is released to the house in the ledger
  pool := t.escrow_coins;
  if pool > 0 then
    insert into nx_t_ledger(tournament_id, user_id, kind, currency, amount, idem_key)
    values (p_t, null, 'house_fee', 'coins', pool - least(pool, greatest(0, tc - _nx_t_cfg_int(t.prize, 'fixed_coins', 0))),
            'house:' || p_t || ':coins') on conflict (idem_key) do nothing;
  end if;
  if t.escrow_gems > 0 then
    insert into nx_t_ledger(tournament_id, user_id, kind, currency, amount, idem_key)
    values (p_t, null, 'house_fee', 'gems',
            t.escrow_gems - least(t.escrow_gems, greatest(0, tg - _nx_t_cfg_int(t.prize, 'fixed_gems', 0))),
            'house:' || p_t || ':gems') on conflict (idem_key) do nothing;
  end if;
  update nx_tournaments set paid_out = true, escrow_coins = 0, escrow_gems = 0, updated_at = now() where id = p_t;
  perform _nx_t_audit(p_t, null, 'payout', jsonb_build_object('coins', tc, 'gems', tg, 'dist', to_jsonb(dist)));
end $$;

-- ---------------------------------------------------------------------------
-- placements + finish + cancel
-- ---------------------------------------------------------------------------
create or replace function public._nx_t_place_elim(p_t uuid, p_stage text) returns int
language plpgsql security definer set search_path = public as $$
declare t nx_tournaments; minr int; maxr int; k int; m record; champ uuid; second uuid; lmax int; placed int := 0;
        r record; cnt int;
begin
  select * into t from nx_tournaments where id = p_t;
  if t.format = 'double_elim' then
    select * into m from nx_t_matches where tournament_id = p_t and bracket = 'GF2' and status in ('done', 'walkover');
    if m.id is null then
      select * into m from nx_t_matches where tournament_id = p_t and bracket = 'GF';
    end if;
    champ := m.winner; second := case when m.winner = m.p1 then m.p2 else m.p1 end;
    update nx_t_entries set place = 1 where tournament_id = p_t and user_id = champ;
    update nx_t_entries set place = 2 where tournament_id = p_t and user_id = second;
    placed := 2;
    select max(round) into lmax from nx_t_matches where tournament_id = p_t and bracket = 'L';
    for r in select round as rd, array_agg(loser) as us from nx_t_matches
              where tournament_id = p_t and bracket = 'L' and loser is not null group by round order by round desc loop
      update nx_t_entries set place = placed + 1 where tournament_id = p_t and user_id = any(r.us) and place is null;
      placed := placed + array_length(r.us, 1);
    end loop;
    return placed;
  end if;
  select min(round), max(round) into minr, maxr from nx_t_matches where tournament_id = p_t and stage = p_stage and bracket = 'W';
  if minr is null then return 0; end if;
  k := maxr - minr + 1;
  select * into m from nx_t_matches where tournament_id = p_t and stage = p_stage and bracket = 'W' and round = maxr;
  update nx_t_entries set place = 1 where tournament_id = p_t and user_id = m.winner;
  for r in select round as rd, loser from nx_t_matches
            where tournament_id = p_t and stage = p_stage and bracket = 'W' and loser is not null loop
    update nx_t_entries set place = (1 << (k - (r.rd - minr + 1))) + 1 where tournament_id = p_t and user_id = r.loser;
  end loop;
  select * into m from nx_t_matches where tournament_id = p_t and stage = p_stage and bracket = 'P3' and status in ('done', 'walkover', 'bye');
  if m.id is not null and m.winner is not null then
    update nx_t_entries set place = 3 where tournament_id = p_t and user_id = m.winner;
    if m.loser is not null then update nx_t_entries set place = 4 where tournament_id = p_t and user_id = m.loser; end if;
  end if;
  select count(*) into cnt from nx_t_entries where tournament_id = p_t and status = 'approved' and place is not null;
  return cnt;
end $$;

create or replace function public._nx_t_finish(p_t uuid) returns void
language plpgsql security definer set search_path = public as $$
declare t nx_tournaments; placed int; r record; i int := 0; champ uuid;
begin
  select * into t from nx_tournaments where id = p_t for update;
  if t.id is null or t.status in ('finished', 'cancelled') then return; end if;
  update nx_t_entries set place = null where tournament_id = p_t;
  if t.format in ('single_elim', 'two_legs', 'double_elim') then
    placed := _nx_t_place_elim(p_t, 'main');
  elsif t.format = 'groups_ko' then
    placed := _nx_t_place_elim(p_t, 'ko');
    update nx_t_entries set place = placed + 1 where tournament_id = p_t and status = 'approved' and place is null;
  else
    for r in select x.user_id from _nx_t_table(p_t, 'main', null) x
              order by x.pts desc, (x.gf - x.ga) desc, x.gf desc, x.won desc, x.seed loop
      i := i + 1;
      update nx_t_entries set place = i where tournament_id = p_t and user_id = r.user_id;
    end loop;
  end if;
  select user_id into champ from nx_t_entries where tournament_id = p_t and place = 1 order by seed limit 1;
  update nx_tournaments set status = 'finished', finished_at = now(), winner = champ, updated_at = now() where id = p_t;
  perform _nx_t_payout(p_t);
  perform _nx_t_notify_all(p_t, 'finished', jsonb_build_object('winner', champ,
            'winner_name', (select username from profiles where id = champ)), 'finished:' || p_t);
  perform _nx_t_audit(p_t, null, 'finished', jsonb_build_object('winner', champ));
end $$;

create or replace function public._nx_t_cancel(p_t uuid, p_reason text, p_actor uuid default null) returns void
language plpgsql security definer set search_path = public as $$
declare t nx_tournaments; r record;
begin
  select * into t from nx_tournaments where id = p_t for update;
  if t.id is null or t.status in ('finished', 'cancelled') then return; end if;
  for r in select user_id from nx_t_entries where tournament_id = p_t and (paid_coins > 0 or paid_gems > 0) loop
    perform _nx_t_refund(p_t, r.user_id, 'cancelled');
  end loop;
  update nx_t_matches set status = 'void', result_note = 'cancelled', updated_at = now()
   where tournament_id = p_t and status not in ('done', 'walkover', 'bye', 'void', 'skipped');
  update nx_tournaments set status = 'cancelled', cancel_reason = left(p_reason, 200), finished_at = now(), updated_at = now()
   where id = p_t;
  update nx_t_jobs set done_at = now(), last_error = 'cancelled' where tournament_id = p_t and done_at is null;
  perform _nx_t_notify_all(p_t, 'cancelled', jsonb_build_object('reason', p_reason), 'cancelled:' || p_t,
                           array['approved', 'pending', 'waitlist']);
  perform _nx_t_audit(p_t, p_actor, 'cancelled', jsonb_build_object('reason', p_reason));
end $$;

-- ---------------------------------------------------------------------------
-- draw + stage progress
-- ---------------------------------------------------------------------------
create or replace function public._nx_t_draw(p_t uuid, p_actor uuid default null) returns void
language plpgsql security definer set search_path = public as $$
declare t nx_tournaments; n int; players uuid[]; g int; a int; i int; grp int; r record; maxr int := 0; rr int;
begin
  select * into t from nx_tournaments where id = p_t for update;
  if t.id is null or t.status not in ('registering', 'closed') then return; end if;
  select count(*) into n from nx_t_entries where tournament_id = p_t and status = 'approved';
  if n < greatest(2, t.min_players) then
    perform _nx_t_cancel(p_t, 'not_enough_players', p_actor);
    return;
  end if;
  -- whoever did not make it (pending approval / waitlist) gets the fee back
  for r in select user_id from nx_t_entries where tournament_id = p_t and status in ('pending', 'waitlist') loop
    perform _nx_t_refund(p_t, r.user_id, 'not_drawn');
    update nx_t_entries set status = 'rejected', note = 'not_drawn', updated_at = now()
     where tournament_id = p_t and user_id = r.user_id;
    perform _nx_t_notify(r.user_id, p_t, null, 'rejected', jsonb_build_object('reason', 'not_drawn'), 'notdrawn:' || p_t);
  end loop;
  if t.seed is null then
    t.seed := floor(random() * 2147483646)::bigint + 1;
    update nx_tournaments set seed = t.seed where id = p_t;
  end if;
  select array_agg(user_id order by
           case when t.seeding = 'manual' then coalesce(seed, 100000) else 0 end,
           case when t.seeding = 'rating' then -rating else 0 end,
           md5(t.seed::text || user_id::text))
    into players from nx_t_entries where tournament_id = p_t and status = 'approved';
  for i in 1..n loop
    update nx_t_entries set seed = i, group_no = null where tournament_id = p_t and user_id = players[i];
  end loop;
  delete from nx_t_matches where tournament_id = p_t;
  if t.format in ('single_elim', 'two_legs') then
    perform _nx_t_gen_se(p_t, players, 'main', 0, 0);
  elsif t.format = 'double_elim' then
    perform _nx_t_gen_de(p_t, players);
  elsif t.format = 'round_robin' then
    perform _nx_t_gen_rr(p_t, players, null, _nx_t_cfg_bool(t.config, 'rr_double', false), 0, 0, 'RR', 'main');
  elsif t.format = 'groups_ko' then
    g := greatest(1, least(_nx_t_cfg_int(t.config, 'groups', 2), n / 2));
    for i in 1..n loop
      -- snake: 1..g, g..1, ...
      grp := case when ((i - 1) / g) % 2 = 0 then ((i - 1) % g) + 1 else g - ((i - 1) % g) end;
      update nx_t_entries set group_no = grp where tournament_id = p_t and user_id = players[i];
    end loop;
    for grp in 1..g loop
      rr := _nx_t_gen_rr(p_t, (select array_agg(user_id order by seed) from nx_t_entries
                                where tournament_id = p_t and status = 'approved' and group_no = grp),
                         grp, _nx_t_cfg_bool(t.config, 'rr_double', false), 0, 0, 'G', 'groups');
    end loop;
    update nx_tournaments set stage = 'groups' where id = p_t;
  elsif t.format = 'swiss' then
    perform _nx_t_swiss_round(p_t, 1);
  end if;
  update nx_tournaments set status = 'drawn', drawn_at = now(), updated_at = now() where id = p_t;
  perform _nx_t_notify_all(p_t, 'drawn', '{}'::jsonb, 'drawn:' || p_t);
  perform _nx_t_audit(p_t, p_actor, 'drawn', jsonb_build_object('seed', t.seed, 'players', n, 'seeding', t.seeding));
end $$;

create or replace function public._nx_t_start(p_t uuid, p_actor uuid default null) returns void
language plpgsql security definer set search_path = public as $$
declare t nx_tournaments;
begin
  select * into t from nx_tournaments where id = p_t for update;
  if t.id is null then return; end if;
  if t.status in ('registering', 'closed') then
    perform _nx_t_draw(p_t, p_actor);
    select * into t from nx_tournaments where id = p_t;
  end if;
  if t.status <> 'drawn' then return; end if;
  update nx_tournaments set status = 'live', started_at = now(), updated_at = now() where id = p_t;
  perform _nx_t_notify_all(p_t, 'started', '{}'::jsonb, 'started:' || p_t);
  perform _nx_t_audit(p_t, p_actor, 'started', '{}'::jsonb);
  perform _nx_t_progress(p_t);
end $$;

create or replace function public._nx_t_progress(p_t uuid) returns void
language plpgsql security definer set search_path = public as $$
declare t nx_tournaments; open_n int; g int; a int; rk int; grp int; adv uuid[] := '{}'; r record; maxr int; maxs int;
        rounds int; pick uuid; k int;
begin
  if _nx_t_gen_on() then return; end if;
  select * into t from nx_tournaments where id = p_t;
  if t.id is null or t.status <> 'live' then return; end if;
  select count(*) into open_n from nx_t_matches
   where tournament_id = p_t and status not in ('done', 'walkover', 'bye', 'void', 'skipped');
  if open_n > 0 then return; end if;
  if t.format = 'groups_ko' and t.stage = 'groups' then
    g := coalesce((select max(group_no) from nx_t_entries where tournament_id = p_t and status = 'approved'), 1);
    a := greatest(1, least(_nx_t_cfg_int(t.config, 'advance', 2), 8));
    for rk in 1..a loop
      for grp in 1..g loop
        -- A1, B1, C1 ..., A2, B2 ...: the standard bracket order then pairs A1–(last group)2, B1–…, never two of one group
        pick := null;
        select y.user_id into pick from (
          select x.user_id, row_number() over (order by x.pts desc, (x.gf - x.ga) desc, x.gf desc, x.won desc, x.seed) as pos
            from _nx_t_table(p_t, 'groups', grp) x) y where y.pos = rk;
        if pick is not null then adv := adv || pick; end if;
      end loop;
    end loop;
    select max(round), max(tslot) into maxr, maxs from nx_t_matches where tournament_id = p_t;
    update nx_tournaments set stage = 'ko', updated_at = now() where id = p_t;
    for r in select user_id from nx_t_entries where tournament_id = p_t and status = 'approved' and not (user_id = any(adv)) loop
      perform _nx_t_notify(r.user_id, p_t, null, 'eliminated', jsonb_build_object('stage', 'groups'), 'elimg:' || p_t);
    end loop;
    if coalesce(array_length(adv, 1), 0) >= 2 then
      for r in select unnest(adv) as u loop
        perform _nx_t_notify(r.u, p_t, null, 'advanced', jsonb_build_object('stage', 'groups'), 'advg:' || p_t);
      end loop;
      perform _nx_t_gen_se(p_t, adv, 'ko', coalesce(maxr, 0), coalesce(maxs, 0));
      perform _nx_t_progress(p_t);
      return;
    end if;
  elsif t.format = 'swiss' then
    select max(round) into maxr from nx_t_matches where tournament_id = p_t and bracket = 'SW';
    select count(*) into rounds from nx_t_entries where tournament_id = p_t and status = 'approved';
    k := 0;
    while (1 << k) < rounds loop k := k + 1; end loop;
    rounds := least(greatest(1, _nx_t_cfg_int(t.config, 'swiss_rounds', greatest(k, 1))), greatest(1, rounds - 1));
    if coalesce(maxr, 0) < rounds then
      perform _nx_t_swiss_round(p_t, coalesce(maxr, 0) + 1);
      perform _nx_t_progress(p_t);
      return;
    end if;
  elsif t.format = 'custom' then
    return; -- custom brackets are finished by the organizer
  end if;
  perform _nx_t_finish(p_t);
end $$;

-- ---------------------------------------------------------------------------
-- match flow: ready check → online game (existing nx_rooms / nx_matches) → result
-- ---------------------------------------------------------------------------
create or replace function public._nx_t_open_ready(p_m uuid) returns void
language plpgsql security definer set search_path = public as $$
declare m nx_t_matches; t nx_tournaments; secs int;
begin
  select * into m from nx_t_matches where id = p_m for update;
  if m.id is null or m.status not in ('scheduled', 'playing') then return; end if;
  select * into t from nx_tournaments where id = m.tournament_id;
  secs := greatest(30, least(_nx_t_cfg_int(t.config, 'ready_seconds', 300), 3600));
  update nx_t_matches set status = 'ready_check', ready_deadline = now() + make_interval(secs => secs),
         p1_ready = false, p2_ready = false, game_match = null, updated_at = now() where id = p_m;
  perform _nx_t_notify(m.p1, m.tournament_id, m.id, 'match_ready', jsonb_build_object('game', m.games + 1, 'seconds', secs),
                       'ready:' || m.id || ':' || m.games);
  perform _nx_t_notify(m.p2, m.tournament_id, m.id, 'match_ready', jsonb_build_object('game', m.games + 1, 'seconds', secs),
                       'ready:' || m.id || ':' || m.games);
end $$;

create or replace function public._nx_t_better_seed(p_t uuid, a uuid, b uuid) returns uuid
language sql stable security definer set search_path = public as $$
  select user_id from nx_t_entries where tournament_id = p_t and user_id in (a, b) order by seed nulls last, user_id limit 1
$$;

create or replace function public._nx_t_no_show(p_m uuid) returns void
language plpgsql security definer set search_path = public as $$
declare m nx_t_matches; elim boolean; w uuid;
begin
  select * into m from nx_t_matches where id = p_m for update;
  if m.id is null or m.status <> 'ready_check' or m.ready_deadline > now() then return; end if;
  elim := m.bracket in ('W', 'L', 'GF', 'GF2', 'P3');
  if m.p1_ready and not m.p2_ready then
    perform _nx_t_complete(m.id, m.p1, m.p2, false, 'walkover', 'no_show');
    perform _nx_t_notify(m.p2, m.tournament_id, m.id, 'walkover', jsonb_build_object('lost', true), 'wo:' || m.id);
  elsif m.p2_ready and not m.p1_ready then
    perform _nx_t_complete(m.id, m.p2, m.p1, false, 'walkover', 'no_show');
    perform _nx_t_notify(m.p1, m.tournament_id, m.id, 'walkover', jsonb_build_object('lost', true), 'wo:' || m.id);
  elsif elim then
    -- nobody showed up: the better seed advances (a knockout needs a winner)
    w := _nx_t_better_seed(m.tournament_id, m.p1, m.p2);
    perform _nx_t_complete(m.id, w, case when w = m.p1 then m.p2 else m.p1 end, false, 'walkover', 'double_no_show');
  else
    perform _nx_t_complete(m.id, null, null, false, 'void', 'double_no_show');
  end if;
end $$;

-- Both ready → create the private room + online match exactly like the lobby does (nx_rooms/nx_room_players/nx_matches),
-- tagged with settings.tmatch so the result flows back here.
create or replace function public._nx_t_launch(p_m uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare m nx_t_matches; t nx_tournaments; home uuid; away uuid; rid uuid; mid uuid; sd bigint; c text; golden boolean;
        st jsonb;
begin
  select * into m from nx_t_matches where id = p_m for update;
  if m.id is null or m.status <> 'ready_check' then return null; end if;
  select * into t from nx_tournaments where id = m.tournament_id;
  if m.games % 2 = 0 then home := m.p1; away := m.p2; else home := m.p2; away := m.p1; end if;
  golden := m.games >= m.best_of;
  st := jsonb_build_object('tmatch', m.id, 'tournament', t.id, 'game_no', m.games + 1, 'golden_goal', golden,
                           'grace_sec', 60, 'best_of', m.best_of, 'aggregate', m.aggregate);
  c := nx_gen_code();
  insert into nx_rooms(code, game, host, seats, status, is_private, quick, settings)
  values (c, t.game, home, 2, 'playing', true, false, st) returning id into rid;
  insert into nx_room_players(room_id, user_id, seat, ready) values (rid, home, 0, true), (rid, away, 1, true);
  sd := floor(random() * 2147483646)::bigint + 1;
  insert into nx_matches(room_id, game, players, names, seed, settings)
  values (rid, t.game, array[home, away],
          array[coalesce((select username from profiles where id = home), 'Pilot'),
                coalesce((select username from profiles where id = away), 'Pilot')], sd, st)
  returning id into mid;
  update nx_rooms set match_id = mid where id = rid;
  insert into nx_t_games(game_match, tmatch, n, home, away, golden) values (mid, m.id, m.games + 1, home, away, golden);
  update nx_t_matches set status = 'playing', game_match = mid, ready_deadline = null, updated_at = now() where id = m.id;
  perform _nx_t_audit(t.id, null, 'game_started', jsonb_build_object('match', m.id, 'game_match', mid, 'n', m.games + 1));
  return mid;
end $$;

-- Apply one accepted game to its series and decide the match or open the next game.
create or replace function public._nx_t_game_result(p_gm uuid, p_winner uuid, p_s_home int, p_s_away int, p_source text)
returns void language plpgsql security definer set search_path = public as $$
declare g nx_t_games; m nx_t_matches; s1 int; s2 int; need int; elim boolean; w uuid; l uuid; draw boolean := false;
        decided boolean := false;
begin
  select * into g from nx_t_games where game_match = p_gm for update;
  if g.game_match is null or g.accepted then return; end if;
  update nx_t_games set accepted = true, disputed = false, winner = p_winner, s_home = p_s_home, s_away = p_s_away,
         source = p_source where game_match = p_gm;
  select * into m from nx_t_matches where id = g.tmatch for update;
  if m.status in ('done', 'walkover', 'bye', 'void', 'skipped') then return; end if;
  if g.home = m.p1 then s1 := coalesce(p_s_home, 0); s2 := coalesce(p_s_away, 0);
  else s1 := coalesce(p_s_away, 0); s2 := coalesce(p_s_home, 0); end if;
  update nx_t_matches set games = games + 1, g1 = g1 + s1, g2 = g2 + s2,
         w1 = w1 + coalesce(p_winner = p1, false)::int, w2 = w2 + coalesce(p_winner = p2, false)::int, game_match = null, updated_at = now()
   where id = m.id returning * into m;
  elim := m.bracket in ('W', 'L', 'GF', 'GF2', 'P3');
  need := m.best_of / 2 + 1;
  if m.aggregate then
    if m.games >= 2 then
      if m.games > 2 and p_winner is not null then w := p_winner; decided := true;
      elsif m.g1 > m.g2 then w := m.p1; decided := true;
      elsif m.g2 > m.g1 then w := m.p2; decided := true;
      elsif not elim then draw := true; decided := true;
      end if;
    end if;
  else
    if m.best_of <> 2 and m.w1 >= need then w := m.p1; decided := true;
    elsif m.best_of <> 2 and m.w2 >= need then w := m.p2; decided := true;
    elsif m.games >= m.best_of then
      if m.w1 > m.w2 then w := m.p1; decided := true;
      elsif m.w2 > m.w1 then w := m.p2; decided := true;
      elsif not elim then draw := true; decided := true;
      end if; -- knockout tie → golden-goal decider game
    end if;
  end if;
  if not decided and m.games >= m.best_of + 4 then
    w := _nx_t_better_seed(m.tournament_id, m.p1, m.p2); decided := true;
  end if;
  perform _nx_t_audit(m.tournament_id, null, 'game_accepted',
    jsonb_build_object('match', m.id, 'game_match', p_gm, 'winner', p_winner, 's_home', p_s_home, 's_away', p_s_away, 'source', p_source));
  if decided then
    l := case when w = m.p1 then m.p2 when w = m.p2 then m.p1 end;
    perform _nx_t_complete(m.id, w, l, draw, 'done', p_source);
  else
    update nx_t_matches set status = 'scheduled', updated_at = now() where id = m.id;
    perform _nx_t_open_ready(m.id);
  end if;
end $$;

create or replace function public._nx_t_dispute(p_m uuid, p_actor uuid, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare m nx_t_matches;
begin
  select * into m from nx_t_matches where id = p_m for update;
  if m.id is null or m.status in ('done', 'walkover', 'bye', 'void', 'skipped', 'disputed') then return; end if;
  update nx_t_matches set status = 'disputed', result_note = left(p_reason, 120), updated_at = now() where id = p_m;
  if m.game_match is not null then update nx_t_games set disputed = true where game_match = m.game_match; end if;
  perform _nx_t_notify_managers(m.tournament_id, m.id, 'dispute', jsonb_build_object('reason', p_reason), 'dispute:' || m.id);
  perform _nx_t_notify(m.p1, m.tournament_id, m.id, 'dispute', jsonb_build_object('reason', p_reason), 'disputep:' || m.id);
  perform _nx_t_notify(m.p2, m.tournament_id, m.id, 'dispute', jsonb_build_object('reason', p_reason), 'disputep:' || m.id);
  perform _nx_t_audit(m.tournament_id, p_actor, 'dispute', jsonb_build_object('match', m.id, 'reason', p_reason));
end $$;

-- Consensus: both reports agree → accept. One report matching the server row and the other silent 90 s → accept.
-- No report but a finished server row for 3 min → accept. Any disagreement → dispute.
create or replace function public._nx_t_try_accept(p_gm uuid, p_from_tick boolean default false) returns void
language plpgsql security definer set search_path = public as $$
declare g nx_t_games; rh nx_t_reports; ra nx_t_reports; one nx_t_reports; n int;
begin
  select * into g from nx_t_games where game_match = p_gm;
  if g.game_match is null or g.accepted or g.disputed then return; end if;
  select * into rh from nx_t_reports where game_match = p_gm and user_id = g.home;
  select * into ra from nx_t_reports where game_match = p_gm and user_id = g.away;
  if rh.user_id is not null and ra.user_id is not null then
    if rh.winner is not distinct from ra.winner and rh.s_home = ra.s_home and rh.s_away = ra.s_away then
      perform _nx_t_game_result(p_gm, rh.winner, rh.s_home, rh.s_away, 'both_reports');
    else
      perform _nx_t_dispute(g.tmatch, null, 'reports_disagree');
    end if;
    return;
  end if;
  one := coalesce(rh, ra);
  if one.user_id is not null then
    if g.ended_at is not null and (one.winner is distinct from g.srv_winner) then
      perform _nx_t_dispute(g.tmatch, null, 'report_vs_server');
      return;
    end if;
    if p_from_tick and g.ended_at is not null and greatest(g.ended_at, one.created_at) < now() - interval '90 seconds' then
      perform _nx_t_game_result(p_gm, one.winner, one.s_home, one.s_away, 'single_report');
    end if;
    return;
  end if;
  if p_from_tick and g.ended_at is not null and g.ended_at < now() - interval '3 minutes' then
    perform _nx_t_game_result(p_gm, g.srv_winner, coalesce(g.srv_s_home, 0), coalesce(g.srv_s_away, 0), 'server_only');
  end if;
end $$;

-- nx_matches → tournament: forfeits are server facts (accepted at once); normal ends wait for both reports.
create or replace function public._nx_t_on_match_end() returns trigger
language plpgsql security definer set search_path = public as $$
declare w uuid;
begin
  if not (new.settings ? 'tmatch') or old.status <> 'playing' or new.status = 'playing' then return new; end if;
  begin
    update nx_rooms set status = 'closed', updated_at = now() where id = new.room_id;
    if array_length(new.winner_seats, 1) = 1 then w := new.players[new.winner_seats[1] + 1]; end if;
    update nx_t_games set ended_at = now(), srv_winner = w, srv_s_home = coalesce(new.scores[1], 0),
           srv_s_away = coalesce(new.scores[2], 0) where game_match = new.id;
    if coalesce(new.reason, '') like 'forfeit%' or new.status = 'abandoned' then
      perform _nx_t_game_result(new.id, w, coalesce(new.scores[1], 0), coalesce(new.scores[2], 0), 'forfeit');
    else
      perform _nx_t_try_accept(new.id, false);
    end if;
  exception when others then
    insert into nx_t_audit(tournament_id, action, data)
    values ((new.settings ->> 'tournament')::uuid, 'error_match_end', jsonb_build_object('match', new.id, 'error', sqlerrm));
  end;
  return new;
end $$;
drop trigger if exists nx_t_on_match_end on public.nx_matches;
create trigger nx_t_on_match_end after update of status on public.nx_matches
  for each row execute function public._nx_t_on_match_end();

-- ---------------------------------------------------------------------------
-- jobs + tick (pg_cron every minute)
-- ---------------------------------------------------------------------------
create or replace function public._nx_t_run_job(j nx_t_jobs) returns void
language plpgsql security definer set search_path = public as $$
declare t nx_tournaments; m nx_t_matches;
begin
  select * into t from nx_tournaments where id = j.tournament_id;
  if t.id is null or t.status in ('finished', 'cancelled', 'draft') then return; end if;
  case j.kind
    when 'open_reg' then
      update nx_tournaments set status = 'registering', updated_at = now() where id = t.id and status = 'scheduled';
    when 'close_reg' then
      update nx_tournaments set status = 'closed', updated_at = now() where id = t.id and status = 'registering';
    when 'draw' then
      if t.status = 'scheduled' then update nx_tournaments set status = 'closed' where id = t.id; end if;
      perform _nx_t_draw(t.id);
    when 'start' then
      if t.status = 'scheduled' then update nx_tournaments set status = 'closed' where id = t.id; end if;
      perform _nx_t_start(t.id);
    when 'remind_start' then
      if t.status in ('registering', 'closed', 'drawn') then
        perform _nx_t_notify_all(t.id, 'starting_soon', jsonb_build_object('start_at', t.start_at), 'soon:' || t.id);
      end if;
    when 'remind_match' then
      select * into m from nx_t_matches where id = j.ref;
      if m.id is not null and m.status = 'scheduled' and m.p1 is not null and m.p2 is not null then
        perform _nx_t_notify(m.p1, t.id, m.id, 'match_soon', jsonb_build_object('at', m.scheduled_at), 'msoon:' || m.id);
        perform _nx_t_notify(m.p2, t.id, m.id, 'match_soon', jsonb_build_object('at', m.scheduled_at), 'msoon:' || m.id);
      end if;
    else
      null;
  end case;
end $$;

create or replace function public.nx_t_tick() returns jsonb
language plpgsql security definer set search_path = public as $$
declare j nx_t_jobs; r record; nj int := 0; nr int := 0; nn int := 0; na int := 0;
begin
  if not pg_try_advisory_xact_lock(74230011) then return jsonb_build_object('skipped', true); end if;
  for j in select jb.* from nx_t_jobs jb left join nx_tournaments t on t.id = jb.tournament_id
            where jb.done_at is null and jb.run_at <= now()
              and not (coalesce(t.paused, false) and jb.kind in ('draw', 'start'))
            order by jb.run_at limit 200 loop
    begin
      perform _nx_t_run_job(j);
      update nx_t_jobs set done_at = now(), attempts = attempts + 1, last_error = null where id = j.id;
      nj := nj + 1;
    exception when others then
      update nx_t_jobs set attempts = attempts + 1, last_error = left(sqlerrm, 300),
             run_at = now() + make_interval(mins => least(attempts + 1, 15)),
             done_at = case when attempts + 1 >= 60 then now() end
       where id = j.id;
    end;
  end loop;
  -- due matches → ready check
  for r in select m.id from nx_t_matches m join nx_tournaments t on t.id = m.tournament_id
            where m.status = 'scheduled' and m.scheduled_at <= now() and t.status = 'live' and not t.paused
            order by m.scheduled_at limit 500 loop
    begin perform _nx_t_open_ready(r.id); nr := nr + 1;
    exception when others then perform _nx_t_audit(null, null, 'error_ready', jsonb_build_object('match', r.id, 'error', sqlerrm)); end;
  end loop;
  -- ready deadlines → walkovers
  for r in select m.id from nx_t_matches m join nx_tournaments t on t.id = m.tournament_id
            where m.status = 'ready_check' and m.ready_deadline < now() and not t.paused limit 500 loop
    begin perform _nx_t_no_show(r.id); nn := nn + 1;
    exception when others then perform _nx_t_audit(null, null, 'error_no_show', jsonb_build_object('match', r.id, 'error', sqlerrm)); end;
  end loop;
  -- results waiting for the second report
  for r in select g.game_match from nx_t_games g where not g.accepted and not g.disputed and g.ended_at is not null limit 500 loop
    begin perform _nx_t_try_accept(r.game_match, true); na := na + 1;
    exception when others then perform _nx_t_audit(null, null, 'error_accept', jsonb_build_object('game', r.game_match, 'error', sqlerrm)); end;
  end loop;
  -- games that never ended (both phones gone) → dispute for an organizer
  for r in select g.tmatch from nx_t_games g join nx_t_matches m on m.id = g.tmatch join nx_tournaments t on t.id = m.tournament_id
            where not g.accepted and not g.disputed and g.ended_at is null and m.status = 'playing'
              and g.created_at < now() - make_interval(mins => greatest(5, _nx_t_cfg_int(t.config, 'max_game_minutes', 30)))
            limit 100 loop
    begin perform _nx_t_dispute(r.tmatch, null, 'game_timeout');
    exception when others then null; end;
  end loop;
  return jsonb_build_object('jobs', nj, 'ready', nr, 'no_show', nn, 'accept', na);
end $$;

-- Only the server (cron/owner) runs the engine.
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and (p.proname like '\_nx\_t\_%' or p.proname = 'nx_t_tick') loop
    execute format('revoke execute on function %s from public, anon, authenticated', f.sig);
  end loop;
end $$;
