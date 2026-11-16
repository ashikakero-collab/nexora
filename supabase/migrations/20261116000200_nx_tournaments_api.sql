-- NEXORA tournaments · client RPCs (SECURITY DEFINER, role-checked in Postgres; the UI only hides buttons).
-- User-facing failures return {ok:false, error:'...'} instead of raising, so rate-limit rows and similar survive.

create or replace function public.nx_t_my_role() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('admin', nx_t_is_admin(auth.uid()), 'organizer', nx_t_is_organizer(auth.uid()), 'uid', auth.uid())
$$;

-- Admin only: grant/revoke the global organizer/admin role.
create or replace function public.nx_t_set_staff(p_user uuid, p_role text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if not nx_t_is_admin(me) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
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

-- Creator/admin: add or remove a runner of one tournament.
create or replace function public.nx_t_set_runner(p_t uuid, p_user uuid, p_add boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if not (nx_t_is_admin(me) or exists (select 1 from nx_tournaments where id = p_t and created_by = me)) then
    return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  if p_add then
    insert into nx_t_staff(tournament_id, user_id, added_by) values (p_t, p_user, me) on conflict do nothing;
  else
    delete from nx_t_staff where tournament_id = p_t and user_id = p_user;
  end if;
  perform _nx_t_audit(p_t, me, 'set_runner', jsonb_build_object('user', p_user, 'add', p_add));
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------------
-- create / edit
-- ---------------------------------------------------------------------------
create or replace function public._nx_t_validate_cfg(c jsonb) returns jsonb
language plpgsql immutable as $$
declare o jsonb := coalesce(c, '{}'::jsonb); k text;
begin
  foreach k in array array['bo_early', 'bo_semi', 'bo_final'] loop
    if _nx_t_cfg_int(o, k, 1) not in (1, 2, 3, 5) then o := o || jsonb_build_object(k, 1); end if;
  end loop;
  o := o || jsonb_build_object(
    'groups', greatest(1, least(_nx_t_cfg_int(o, 'groups', 2), 16)),
    'advance', greatest(1, least(_nx_t_cfg_int(o, 'advance', 2), 8)),
    'swiss_rounds', greatest(0, least(_nx_t_cfg_int(o, 'swiss_rounds', 0), 12)),
    'points_win', greatest(0, least(_nx_t_cfg_int(o, 'points_win', 3), 10)),
    'points_draw', greatest(0, least(_nx_t_cfg_int(o, 'points_draw', 1), 10)),
    'ready_seconds', greatest(30, least(_nx_t_cfg_int(o, 'ready_seconds', 300), 3600)),
    'round_minutes', greatest(1, least(_nx_t_cfg_int(o, 'round_minutes', 20), 10080)),
    'max_game_minutes', greatest(5, least(_nx_t_cfg_int(o, 'max_game_minutes', 30), 240)));
  return o;
end $$;

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
      if not adm and (_nx_t_cfg_int(prize, 'fixed_coins', 0) > _nx_t_cfg_int(old.prize, 'fixed_coins', 0)
                      or _nx_t_cfg_int(prize, 'fixed_gems', 0) > _nx_t_cfg_int(old.prize, 'fixed_gems', 0)) then
        return jsonb_build_object('ok', false, 'error', 'fixed_prize_admin_only'); end if;
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

create or replace function public._nx_t_reschedule(p_t uuid) returns void
language plpgsql security definer set search_path = public as $$
declare t nx_tournaments; r record; at timestamptz;
begin
  select * into t from nx_tournaments where id = p_t;
  for r in select id, tslot from nx_t_matches where tournament_id = p_t and status = 'scheduled' loop
    at := greatest(_nx_t_planned(t, r.tslot), now());
    update nx_t_matches set scheduled_at = at, updated_at = now() where id = r.id;
    if at - interval '10 minutes' > now() + interval '1 minute' then
      perform _nx_t_job('remind_match', p_t, r.id, at - interval '10 minutes', 'remind_match:' || r.id);
    end if;
  end loop;
end $$;
revoke execute on function public._nx_t_reschedule(uuid) from public, anon, authenticated;
revoke execute on function public._nx_t_validate_cfg(jsonb) from public, anon, authenticated;

-- publish / registration / draw / start / pause / cancel / finish / delete
create or replace function public.nx_t_admin(p_t uuid, p_action text, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); t nx_tournaments; r record;
begin
  select * into t from nx_tournaments where id = p_t for update;
  if t.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if not nx_t_can_manage(p_t, me) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  case p_action
    when 'publish' then
      if t.status <> 'draft' then return jsonb_build_object('ok', false, 'error', 'not_draft'); end if;
      update nx_tournaments set status = case when reg_open_at <= now() then 'registering' else 'scheduled' end,
             published_at = now(), updated_at = now() where id = p_t;
      perform _nx_t_sync_jobs(p_t);
    when 'open_reg' then
      if t.status <> 'scheduled' then return jsonb_build_object('ok', false, 'error', 'bad_status'); end if;
      update nx_tournaments set status = 'registering', reg_open_at = least(reg_open_at, now()), updated_at = now() where id = p_t;
      perform _nx_t_sync_jobs(p_t);
    when 'close_reg' then
      if t.status <> 'registering' then return jsonb_build_object('ok', false, 'error', 'bad_status'); end if;
      update nx_tournaments set status = 'closed', reg_close_at = greatest(reg_open_at + interval '1 second', least(reg_close_at, now())),
             updated_at = now() where id = p_t;
      update nx_t_jobs set done_at = now() where idem_key = 'close_reg:' || p_t and done_at is null;
    when 'draw', 'redraw' then
      if p_action = 'redraw' then
        if t.status <> 'drawn' then return jsonb_build_object('ok', false, 'error', 'bad_status'); end if;
        delete from nx_t_matches where tournament_id = p_t;
        update nx_tournaments set status = 'closed', seed = null, stage = 'main' where id = p_t;
      elsif t.status not in ('registering', 'closed') then
        return jsonb_build_object('ok', false, 'error', 'bad_status');
      end if;
      update nx_tournaments set reg_close_at = greatest(reg_open_at + interval '1 second', least(reg_close_at, now())),
             draw_at = greatest(reg_open_at + interval '1 second', least(draw_at, now())) where id = p_t;
      perform _nx_t_draw(p_t, me);
      update nx_t_jobs set done_at = now() where idem_key in ('close_reg:' || p_t, 'draw:' || p_t) and done_at is null;
    when 'start' then
      if t.status not in ('registering', 'closed', 'drawn') then return jsonb_build_object('ok', false, 'error', 'bad_status'); end if;
      update nx_tournaments set
             reg_close_at = greatest(reg_open_at + interval '1 second', least(reg_close_at, now())),
             draw_at = greatest(reg_open_at + interval '1 second', least(draw_at, now())),
             start_at = greatest(reg_open_at + interval '1 second', least(start_at, now())) where id = p_t;
      perform _nx_t_start(p_t, me);
      update nx_t_jobs set done_at = now() where idem_key in ('close_reg:' || p_t, 'draw:' || p_t, 'start:' || p_t, 'remind_start:' || p_t)
         and done_at is null;
      perform _nx_t_reschedule(p_t);
    when 'pause' then
      update nx_tournaments set paused = true, updated_at = now() where id = p_t;
    when 'resume' then
      update nx_tournaments set paused = false, updated_at = now() where id = p_t;
      for r in select id from nx_t_matches where tournament_id = p_t and status = 'ready_check' loop
        update nx_t_matches set ready_deadline = now() + make_interval(secs => _nx_t_cfg_int(t.config, 'ready_seconds', 300))
         where id = r.id;
      end loop;
    when 'cancel' then
      perform _nx_t_cancel(p_t, coalesce(nullif(p_reason, ''), 'cancelled_by_organizer'), me);
    when 'finish' then
      if t.status <> 'live' then return jsonb_build_object('ok', false, 'error', 'bad_status'); end if;
      update nx_t_matches set status = 'void', result_note = 'closed_by_organizer', updated_at = now()
       where tournament_id = p_t and status not in ('done', 'walkover', 'bye', 'void', 'skipped');
      perform _nx_t_finish(p_t);
    when 'delete' then
      if t.status <> 'draft' or exists (select 1 from nx_t_ledger where tournament_id = p_t) then
        return jsonb_build_object('ok', false, 'error', 'not_deletable'); end if;
      delete from nx_tournaments where id = p_t;
      return jsonb_build_object('ok', true, 'deleted', true);
    else
      return jsonb_build_object('ok', false, 'error', 'bad_action');
  end case;
  perform _nx_t_audit(p_t, me, 'admin_' || p_action, jsonb_build_object('reason', p_reason));
  return jsonb_build_object('ok', true, 'status', (select status from nx_tournaments where id = p_t));
end $$;

-- ---------------------------------------------------------------------------
-- invite codes
-- ---------------------------------------------------------------------------
create or replace function public._nx_t_new_code() returns text language plpgsql as $$
declare c text; alphabet text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; i int;
begin
  loop
    c := '';
    for i in 1..8 loop c := c || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1); end loop;
    exit when not exists (select 1 from nx_t_codes where code = c);
  end loop;
  return c;
end $$;
revoke execute on function public._nx_t_new_code() from public, anon, authenticated;

create or replace function public.nx_t_code_create(p_t uuid, p_max_uses int default 1, p_expires_at timestamptz default null,
                                                   p_requires_approval boolean default false, p_count int default 1)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); out_codes jsonb := '[]'::jsonb; c text; i int;
begin
  if not nx_t_can_manage(p_t, me) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  for i in 1..greatest(1, least(coalesce(p_count, 1), 50)) loop
    c := _nx_t_new_code();
    insert into nx_t_codes(tournament_id, code, max_uses, expires_at, requires_approval, created_by)
    values (p_t, c, greatest(1, least(coalesce(p_max_uses, 1), 1000)), p_expires_at, coalesce(p_requires_approval, false), me);
    out_codes := out_codes || to_jsonb(c);
  end loop;
  perform _nx_t_audit(p_t, me, 'codes_created', jsonb_build_object('count', jsonb_array_length(out_codes)));
  return jsonb_build_object('ok', true, 'codes', out_codes);
end $$;

create or replace function public.nx_t_code_revoke(p_code uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); t uuid;
begin
  select tournament_id into t from nx_t_codes where id = p_code;
  if t is null or not nx_t_can_manage(t, me) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  update nx_t_codes set revoked = true where id = p_code;
  perform _nx_t_audit(t, me, 'code_revoked', jsonb_build_object('code', p_code));
  return jsonb_build_object('ok', true);
end $$;

-- Validates a code (5 wrong tries per 15 min). Returns {ok, code_id, tournament_id, requires_approval} or {ok:false,error}.
create or replace function public._nx_t_check_code(p_user uuid, p_t uuid, p_code text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c nx_t_codes; norm text := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g')); bad int; err text;
begin
  select count(*) into bad from nx_t_code_attempts where user_id = p_user and not ok and created_at > now() - interval '15 minutes';
  if bad >= 5 then return jsonb_build_object('ok', false, 'error', 'too_many_attempts'); end if;
  select * into c from nx_t_codes where code = norm and (p_t is null or tournament_id = p_t);
  if c.id is null then err := 'bad_code';
  elsif c.revoked then err := 'code_revoked';
  elsif c.expires_at is not null and c.expires_at < now() then err := 'code_expired';
  elsif c.uses >= c.max_uses then err := 'code_used_up';
  end if;
  insert into nx_t_code_attempts(user_id, code, ok) values (p_user, left(norm, 16), err is null);
  if err is not null then return jsonb_build_object('ok', false, 'error', err); end if;
  return jsonb_build_object('ok', true, 'code_id', c.id, 'tournament_id', c.tournament_id, 'requires_approval', c.requires_approval);
end $$;
revoke execute on function public._nx_t_check_code(uuid, uuid, text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- registration
-- ---------------------------------------------------------------------------
create or replace function public.nx_t_register(p_t uuid, p_code text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); t nx_tournaments; e nx_t_entries; pr record; rating int; chk jsonb := null; approval boolean;
        lid bigint; st text; n_appr int; code_id uuid;
begin
  if me is null then return jsonb_build_object('ok', false, 'error', 'not_signed_in'); end if;
  select * into t from nx_tournaments where id = p_t for update;
  if t.id is null or t.status = 'draft' then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if t.status <> 'registering' then return jsonb_build_object('ok', false, 'error', 'registration_closed'); end if;
  select * into e from nx_t_entries where tournament_id = p_t and user_id = me for update;
  if e.user_id is not null and e.status in ('pending', 'approved', 'waitlist') then
    return jsonb_build_object('ok', true, 'status', e.status, 'already', true);
  end if;
  if e.user_id is not null and e.status in ('removed', 'rejected') then
    return jsonb_build_object('ok', false, 'error', 'not_allowed');
  end if;
  select level, xp, coins, coalesce(gems, 0) as gems into pr from profiles where id = me;
  if pr is null then return jsonb_build_object('ok', false, 'error', 'no_profile'); end if;
  select coalesce((select s.rating from nx_game_stats s where s.user_id = me and s.game = t.game), 1000) into rating;
  if coalesce(pr.level, 1) < t.min_level then return jsonb_build_object('ok', false, 'error', 'min_level', 'need', t.min_level); end if;
  if coalesce(pr.xp, 0) < t.min_xp then return jsonb_build_object('ok', false, 'error', 'min_xp', 'need', t.min_xp); end if;
  if rating < t.min_rating then return jsonb_build_object('ok', false, 'error', 'min_rating', 'need', t.min_rating); end if;
  if coalesce(p_code, '') <> '' then
    chk := _nx_t_check_code(me, p_t, p_code);
    if not (chk ->> 'ok')::boolean then return chk; end if;
    code_id := (chk ->> 'code_id')::uuid;
  elsif t.reg_mode in ('code', 'code_approval') then
    return jsonb_build_object('ok', false, 'error', 'code_required');
  end if;
  approval := t.reg_mode in ('approval', 'code_approval') or coalesce((chk ->> 'requires_approval')::boolean, false);
  lid := _nx_t_charge(p_t, me, t.fee_coins, t.fee_gems);
  if lid is null then return jsonb_build_object('ok', false, 'error', 'insufficient_funds',
                                                'fee_coins', t.fee_coins, 'fee_gems', t.fee_gems); end if;
  select count(*) into n_appr from nx_t_entries where tournament_id = p_t and status = 'approved';
  st := case when approval then 'pending' when n_appr >= t.capacity then 'waitlist' else 'approved' end;
  insert into nx_t_entries(tournament_id, user_id, status, rating, paid_coins, paid_gems, fee_ref, code_id)
  values (p_t, me, st, rating, t.fee_coins, t.fee_gems, nullif(lid, 0), code_id)
  on conflict (tournament_id, user_id) do update set status = excluded.status, rating = excluded.rating,
     paid_coins = excluded.paid_coins, paid_gems = excluded.paid_gems, fee_ref = excluded.fee_ref, code_id = excluded.code_id,
     note = null, place = null, seed = null, group_no = null, decided_by = null, created_at = now(), updated_at = now();
  if code_id is not null then update nx_t_codes set uses = uses + 1 where id = code_id; end if;
  perform _nx_t_notify(me, p_t, null, case st when 'approved' then 'approved' when 'waitlist' then 'waitlisted' else 'registered' end,
                       '{}'::jsonb, 'reg:' || p_t || ':' || coalesce(lid, 0));
  if st = 'pending' then
    perform _nx_t_notify_managers(p_t, null, 'approval_needed', jsonb_build_object('user', me), 'appr:' || p_t || ':' || me || ':' || coalesce(lid, 0));
  end if;
  perform _nx_t_audit(p_t, me, 'registered', jsonb_build_object('status', st, 'code', code_id, 'fee_coins', t.fee_coins, 'fee_gems', t.fee_gems));
  return jsonb_build_object('ok', true, 'status', st);
end $$;

-- Deep link nexora://t/<code> → find the tournament by code and register with it.
create or replace function public.nx_t_join_code(p_code text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); chk jsonb; res jsonb; t uuid;
begin
  if me is null then return jsonb_build_object('ok', false, 'error', 'not_signed_in'); end if;
  chk := _nx_t_check_code(me, null, p_code);
  if not (chk ->> 'ok')::boolean then return chk; end if;
  t := (chk ->> 'tournament_id')::uuid;
  -- the check above logged a successful attempt; nx_t_register validates (and logs) once more on purpose
  res := nx_t_register(t, p_code);
  return res || jsonb_build_object('tournament_id', t);
end $$;

-- Promote waitlisted entries into free places (oldest first).
create or replace function public._nx_t_fill_from_waitlist(p_t uuid) returns void
language plpgsql security definer set search_path = public as $$
declare t nx_tournaments; n int; r record;
begin
  select * into t from nx_tournaments where id = p_t;
  select count(*) into n from nx_t_entries where tournament_id = p_t and status = 'approved';
  for r in select user_id from nx_t_entries where tournament_id = p_t and status = 'waitlist' order by created_at loop
    exit when n >= t.capacity;
    update nx_t_entries set status = 'approved', updated_at = now() where tournament_id = p_t and user_id = r.user_id;
    perform _nx_t_notify(r.user_id, p_t, null, 'promoted', '{}'::jsonb, 'promo:' || p_t || ':' || r.user_id);
    n := n + 1;
  end loop;
end $$;
revoke execute on function public._nx_t_fill_from_waitlist(uuid) from public, anon, authenticated;

create or replace function public.nx_t_withdraw(p_t uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); t nx_tournaments; e nx_t_entries; refunded boolean := false;
begin
  select * into t from nx_tournaments where id = p_t for update;
  select * into e from nx_t_entries where tournament_id = p_t and user_id = me for update;
  if e.user_id is null or e.status not in ('pending', 'approved', 'waitlist') then
    return jsonb_build_object('ok', false, 'error', 'not_registered'); end if;
  if t.status not in ('registering', 'closed') then return jsonb_build_object('ok', false, 'error', 'too_late'); end if;
  if t.status = 'registering' then refunded := _nx_t_refund(p_t, me, 'withdrawn'); end if;
  update nx_t_entries set status = 'withdrawn', updated_at = now() where tournament_id = p_t and user_id = me;
  if e.status = 'approved' then perform _nx_t_fill_from_waitlist(p_t); end if;
  perform _nx_t_audit(p_t, me, 'withdrawn', jsonb_build_object('refunded', refunded));
  return jsonb_build_object('ok', true, 'refunded', refunded);
end $$;

create or replace function public.nx_t_decide(p_t uuid, p_user uuid, p_approve boolean, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); t nx_tournaments; e nx_t_entries; n int; st text;
begin
  select * into t from nx_tournaments where id = p_t for update;
  if t.id is null or not nx_t_can_manage(p_t, me) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  if t.status not in ('scheduled', 'registering', 'closed') then return jsonb_build_object('ok', false, 'error', 'too_late'); end if;
  select * into e from nx_t_entries where tournament_id = p_t and user_id = p_user for update;
  if e.user_id is null or e.status not in ('pending', 'waitlist') then return jsonb_build_object('ok', false, 'error', 'not_pending'); end if;
  if p_approve then
    select count(*) into n from nx_t_entries where tournament_id = p_t and status = 'approved';
    st := case when n >= t.capacity then 'waitlist' else 'approved' end;
    update nx_t_entries set status = st, decided_by = me, note = p_note, updated_at = now() where tournament_id = p_t and user_id = p_user;
    perform _nx_t_notify(p_user, p_t, null, case st when 'approved' then 'approved' else 'waitlisted' end,
                         jsonb_build_object('note', p_note), 'dec:' || p_t || ':' || p_user || ':' || st);
  else
    st := 'rejected';
    perform _nx_t_refund(p_t, p_user, 'rejected');
    update nx_t_entries set status = st, decided_by = me, note = p_note, updated_at = now() where tournament_id = p_t and user_id = p_user;
    perform _nx_t_notify(p_user, p_t, null, 'rejected', jsonb_build_object('note', p_note), 'dec:' || p_t || ':' || p_user || ':rejected');
  end if;
  perform _nx_t_audit(p_t, me, 'decided', jsonb_build_object('user', p_user, 'status', st, 'note', p_note));
  return jsonb_build_object('ok', true, 'status', st);
end $$;

create or replace function public.nx_t_remove_entry(p_t uuid, p_user uuid, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); t nx_tournaments; e nx_t_entries;
begin
  select * into t from nx_tournaments where id = p_t for update;
  if t.id is null or not nx_t_can_manage(p_t, me) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  if t.status not in ('scheduled', 'registering', 'closed') then return jsonb_build_object('ok', false, 'error', 'too_late'); end if;
  select * into e from nx_t_entries where tournament_id = p_t and user_id = p_user for update;
  if e.user_id is null or e.status not in ('pending', 'approved', 'waitlist') then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  perform _nx_t_refund(p_t, p_user, 'removed');
  update nx_t_entries set status = 'removed', note = p_note, decided_by = me, updated_at = now() where tournament_id = p_t and user_id = p_user;
  perform _nx_t_notify(p_user, p_t, null, 'rejected', jsonb_build_object('note', p_note, 'removed', true), 'rm:' || p_t || ':' || p_user);
  if e.status = 'approved' then perform _nx_t_fill_from_waitlist(p_t); end if;
  perform _nx_t_audit(p_t, me, 'removed', jsonb_build_object('user', p_user, 'note', p_note));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.nx_t_set_seed(p_t uuid, p_user uuid, p_seed int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); t nx_tournaments;
begin
  select * into t from nx_tournaments where id = p_t;
  if t.id is null or not nx_t_can_manage(p_t, me) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  if t.status not in ('draft', 'scheduled', 'registering', 'closed') then return jsonb_build_object('ok', false, 'error', 'too_late'); end if;
  update nx_t_entries set seed = greatest(1, least(p_seed, 64)), updated_at = now() where tournament_id = p_t and user_id = p_user;
  perform _nx_t_audit(p_t, me, 'seed', jsonb_build_object('user', p_user, 'seed', p_seed));
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------------
-- match flow (players)
-- ---------------------------------------------------------------------------
create or replace function public.nx_t_ready(p_m uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); m nx_t_matches; t nx_tournaments; gm uuid;
begin
  select * into m from nx_t_matches where id = p_m for update;
  if m.id is null or me is null or not (me = m.p1 or me = m.p2) then return jsonb_build_object('ok', false, 'error', 'not_a_player'); end if;
  if m.status = 'playing' then return jsonb_build_object('ok', true, 'status', 'playing', 'game_match', m.game_match); end if;
  if m.status <> 'ready_check' then return jsonb_build_object('ok', false, 'error', 'not_ready_time', 'status', m.status); end if;
  select * into t from nx_tournaments where id = m.tournament_id;
  if t.paused or t.status <> 'live' then return jsonb_build_object('ok', false, 'error', 'paused'); end if;
  if me = m.p1 then update nx_t_matches set p1_ready = true, updated_at = now() where id = p_m returning * into m;
  else update nx_t_matches set p2_ready = true, updated_at = now() where id = p_m returning * into m; end if;
  if m.p1_ready and m.p2_ready then
    gm := _nx_t_launch(p_m);
    return jsonb_build_object('ok', true, 'status', 'playing', 'game_match', gm);
  end if;
  return jsonb_build_object('ok', true, 'status', 'ready_check', 'p1_ready', m.p1_ready, 'p2_ready', m.p2_ready);
end $$;

-- A player's report of a finished game (seat 0 = home). winner_seat -1 = draw.
create or replace function public.nx_t_report(p_game uuid, p_winner_seat int, p_s0 int, p_s1 int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); g nx_t_games; w uuid;
begin
  select * into g from nx_t_games where game_match = p_game;
  if g.game_match is null or me is null or not (me = g.home or me = g.away) then
    return jsonb_build_object('ok', false, 'error', 'not_a_player'); end if;
  if p_winner_seat not in (-1, 0, 1) or p_s0 is null or p_s1 is null or p_s0 not between 0 and 99 or p_s1 not between 0 and 99 then
    return jsonb_build_object('ok', false, 'error', 'bad_report'); end if;
  if (p_winner_seat = 0 and p_s0 < p_s1) or (p_winner_seat = 1 and p_s1 < p_s0) or (p_winner_seat = -1 and p_s0 <> p_s1) then
    return jsonb_build_object('ok', false, 'error', 'inconsistent_report'); end if;
  w := case p_winner_seat when 0 then g.home when 1 then g.away end;
  insert into nx_t_reports(game_match, user_id, winner, s_home, s_away) values (p_game, me, w, p_s0, p_s1)
  on conflict (game_match, user_id) do nothing;
  perform _nx_t_try_accept(p_game, false);
  return jsonb_build_object('ok', true, 'accepted', (select accepted from nx_t_games where game_match = p_game),
                            'disputed', (select disputed from nx_t_games where game_match = p_game));
end $$;

create or replace function public.nx_t_dispute(p_m uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); m nx_t_matches;
begin
  select * into m from nx_t_matches where id = p_m;
  if m.id is null or not (me = m.p1 or me = m.p2) then return jsonb_build_object('ok', false, 'error', 'not_a_player'); end if;
  if m.status in ('done', 'walkover', 'bye', 'void', 'skipped') then return jsonb_build_object('ok', false, 'error', 'too_late'); end if;
  perform _nx_t_dispute(p_m, me, coalesce(nullif(left(p_reason, 120), ''), 'player_dispute'));
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------------
-- organizer match tools: result / correction, replay, edit, add (custom), delete (custom)
-- ---------------------------------------------------------------------------
create or replace function public._nx_t_downstream_free(p_m uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select not exists (
    select 1 from nx_t_matches d, nx_t_matches m
     where m.id = p_m and (d.id = m.win_to or d.id = m.lose_to
                           or (m.bracket = 'GF' and d.tournament_id = m.tournament_id and d.bracket = 'GF2'))
       and (d.games > 0 or d.status in ('playing', 'done', 'walkover', 'disputed')))
$$;
revoke execute on function public._nx_t_downstream_free(uuid) from public, anon, authenticated;

create or replace function public.nx_t_admin_match(p_m uuid, p_action text, p jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); m nx_t_matches; t nx_tournaments; w uuid; l uuid; dr boolean; d record; mid uuid;
        np1 uuid; np2 uuid;
begin
  if p_action = 'add' then
    select * into t from nx_tournaments where id = (p ->> 'tournament_id')::uuid for update;
  else
    select * into m from nx_t_matches where id = p_m for update;
    select * into t from nx_tournaments where id = m.tournament_id for update;
  end if;
  if t.id is null or not nx_t_can_manage(t.id, me) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  if t.status in ('finished', 'cancelled') then return jsonb_build_object('ok', false, 'error', 'locked'); end if;
  case p_action
    when 'result' then
      w := nullif(p ->> 'winner', '')::uuid;
      dr := coalesce((p ->> 'draw')::boolean, false);
      if not dr and (w is null or not (w = m.p1 or w = m.p2)) then return jsonb_build_object('ok', false, 'error', 'bad_winner'); end if;
      if dr and m.bracket in ('W', 'L', 'GF', 'GF2', 'P3') then return jsonb_build_object('ok', false, 'error', 'knockout_needs_winner'); end if;
      l := case when w = m.p1 then m.p2 when w = m.p2 then m.p1 end;
      if m.status in ('done', 'walkover') then
        if not _nx_t_downstream_free(m.id) then return jsonb_build_object('ok', false, 'error', 'downstream_started'); end if;
        update nx_t_matches set winner = w, loser = l, is_draw = dr, status = 'done',
               w1 = coalesce((p ->> 'w1')::int, w1), w2 = coalesce((p ->> 'w2')::int, w2),
               g1 = coalesce((p ->> 'g1')::int, g1), g2 = coalesce((p ->> 'g2')::int, g2),
               result_note = 'admin:' || coalesce(p ->> 'note', ''), updated_at = now() where id = m.id;
        if w is distinct from m.winner then
          -- re-seat the corrected players downstream
          for d in select id, status from nx_t_matches where id in (m.win_to, m.lose_to) loop
            update nx_t_matches set status = 'pending', ready_deadline = null, p1_ready = false, p2_ready = false where id = d.id;
          end loop;
          if m.win_to is not null then perform _nx_t_put(m.win_to, m.win_slot, w); end if;
          if m.lose_to is not null then perform _nx_t_put(m.lose_to, m.lose_slot, l); end if;
          if m.bracket = 'GF' then
            update nx_t_matches set status = 'pending', p1 = null, p2 = null, p1_set = false, p2_set = false
             where tournament_id = t.id and bracket = 'GF2';
            perform _nx_t_propagate(m.id);
          end if;
        end if;
        perform _nx_t_notify(m.p1, t.id, m.id, 'result_corrected', jsonb_build_object('winner', w), 'fix:' || m.id || ':' || clock_timestamp());
        perform _nx_t_notify(m.p2, t.id, m.id, 'result_corrected', jsonb_build_object('winner', w), 'fix:' || m.id || ':' || clock_timestamp());
      else
        if m.p1 is null or m.p2 is null then return jsonb_build_object('ok', false, 'error', 'players_unknown'); end if;
        update nx_t_matches set w1 = coalesce((p ->> 'w1')::int, w1), w2 = coalesce((p ->> 'w2')::int, w2),
               g1 = coalesce((p ->> 'g1')::int, g1), g2 = coalesce((p ->> 'g2')::int, g2) where id = m.id;
        if m.game_match is not null then
          update nx_t_games set accepted = true, winner = w, source = 'admin' where game_match = m.game_match;
          update nx_matches set status = 'abandoned', reason = 'admin', ended_at = now() where id = m.game_match and status = 'playing';
        end if;
        perform _nx_t_complete(m.id, w, l, dr, 'done', 'admin:' || coalesce(p ->> 'note', ''));
      end if;
    when 'replay' then
      if m.status not in ('disputed', 'playing', 'ready_check', 'scheduled') or m.p1 is null or m.p2 is null then
        return jsonb_build_object('ok', false, 'error', 'bad_status'); end if;
      if m.game_match is not null then
        update nx_t_games set accepted = true, source = 'void_replay' where game_match = m.game_match;
        update nx_matches set status = 'abandoned', reason = 'replay', ended_at = now() where id = m.game_match and status = 'playing';
      end if;
      update nx_t_matches set status = 'scheduled', game_match = null, updated_at = now() where id = m.id;
      if t.status = 'live' then perform _nx_t_open_ready(m.id); end if;
    when 'edit' then
      if m.status not in ('pending', 'scheduled', 'ready_check') or m.games > 0 then
        return jsonb_build_object('ok', false, 'error', 'already_started'); end if;
      np1 := case when p ? 'p1' then nullif(p ->> 'p1', '')::uuid else m.p1 end;
      np2 := case when p ? 'p2' then nullif(p ->> 'p2', '')::uuid else m.p2 end;
      if (np1 is not null and not exists (select 1 from nx_t_entries where tournament_id = t.id and user_id = np1 and status = 'approved'))
         or (np2 is not null and not exists (select 1 from nx_t_entries where tournament_id = t.id and user_id = np2 and status = 'approved'))
         or (np1 = np2) then
        return jsonb_build_object('ok', false, 'error', 'bad_players'); end if;
      update nx_t_matches set p1 = np1, p2 = np2,
             p1_set = p1_set or p ? 'p1', p2_set = p2_set or p ? 'p2',
             best_of = case when (p ->> 'best_of')::int in (1, 2, 3, 5) then (p ->> 'best_of')::int else best_of end,
             status = 'pending', ready_deadline = null, p1_ready = false, p2_ready = false, updated_at = now()
       where id = m.id;
      perform _nx_t_check(m.id);
      if p ? 'scheduled_at' then
        update nx_t_matches set scheduled_at = greatest((p ->> 'scheduled_at')::timestamptz, now()) where id = m.id and status = 'scheduled';
      end if;
    when 'add' then
      if t.format <> 'custom' then return jsonb_build_object('ok', false, 'error', 'custom_only'); end if;
      if t.status not in ('drawn', 'live') then return jsonb_build_object('ok', false, 'error', 'draw_first'); end if;
      np1 := nullif(p ->> 'p1', '')::uuid; np2 := nullif(p ->> 'p2', '')::uuid;
      if np1 is null or np2 is null or np1 = np2
         or not exists (select 1 from nx_t_entries where tournament_id = t.id and user_id = np1 and status = 'approved')
         or not exists (select 1 from nx_t_entries where tournament_id = t.id and user_id = np2 and status = 'approved') then
        return jsonb_build_object('ok', false, 'error', 'bad_players'); end if;
      mid := _nx_t_new_match(t, 'main', 'C', greatest(1, coalesce((p ->> 'round')::int, 1)),
                             coalesce((select count(*) from nx_t_matches where tournament_id = t.id and bracket = 'C'
                                        and round = greatest(1, coalesce((p ->> 'round')::int, 1))), 0)::int,
                             greatest(1, coalesce((p ->> 'round')::int, 1)), null,
                             case when (p ->> 'best_of')::int in (1, 2, 3, 5) then (p ->> 'best_of')::int else 1 end,
                             left(p ->> 'label', 40));
      update nx_t_matches set p1 = np1, p2 = np2, p1_set = true, p2_set = true where id = mid;
      perform _nx_t_check(mid);
      if p ? 'scheduled_at' then
        update nx_t_matches set scheduled_at = greatest((p ->> 'scheduled_at')::timestamptz, now()) where id = mid and status = 'scheduled';
      end if;
      perform _nx_t_audit(t.id, me, 'match_add', jsonb_build_object('match', mid, 'p', p));
      return jsonb_build_object('ok', true, 'id', mid);
    when 'delete' then
      if t.format <> 'custom' or m.games > 0 or m.status not in ('pending', 'scheduled', 'ready_check') then
        return jsonb_build_object('ok', false, 'error', 'not_deletable'); end if;
      delete from nx_t_matches where id = m.id;
    else
      return jsonb_build_object('ok', false, 'error', 'bad_action');
  end case;
  perform _nx_t_audit(t.id, me, 'match_' || p_action, jsonb_build_object('match', p_m, 'p', p));
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------------
-- reads
-- ---------------------------------------------------------------------------
create or replace function public.nx_t_standings(p_t uuid)
returns table(group_no int, user_id uuid, username text, seed int, played int, won int, drawn int, lost int, gf int, ga int,
              pts int, rank int)
language plpgsql stable security definer set search_path = public as $$
declare t nx_tournaments; g int;
begin
  select * into t from nx_tournaments where id = p_t;
  if t.id is null or not nx_t_visible(p_t) then return; end if;
  if t.format = 'groups_ko' then
    for g in select distinct e.group_no from nx_t_entries e where e.tournament_id = p_t and e.group_no is not null order by 1 loop
      return query
        select g, x.user_id, p.username, x.seed, x.played, x.won, x.drawn, x.lost, x.gf, x.ga, x.pts,
               (row_number() over (order by x.pts desc, (x.gf - x.ga) desc, x.gf desc, x.won desc, x.seed))::int
          from _nx_t_table(p_t, 'groups', g) x left join profiles p on p.id = x.user_id;
    end loop;
  else
    return query
      select null::int, x.user_id, p.username, x.seed, x.played, x.won, x.drawn, x.lost, x.gf, x.ga, x.pts,
             (row_number() over (order by x.pts desc, (x.gf - x.ga) desc, x.gf desc, x.won desc, x.seed))::int
        from _nx_t_table(p_t, 'main', null) x left join profiles p on p.id = x.user_id;
  end if;
end $$;

create or replace function public.nx_t_logs(p_t uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not nx_t_can_manage(p_t) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  return jsonb_build_object('ok', true,
    'audit', coalesce((select jsonb_agg(to_jsonb(a) || jsonb_build_object('actor_name', p.username) order by a.created_at desc)
                         from (select * from nx_t_audit where tournament_id = p_t order by created_at desc limit 300) a
                         left join profiles p on p.id = a.actor), '[]'::jsonb),
    'jobs', coalesce((select jsonb_agg(to_jsonb(j) order by j.run_at) from nx_t_jobs j where j.tournament_id = p_t), '[]'::jsonb),
    'ledger', coalesce((select jsonb_agg(to_jsonb(l) order by l.id) from nx_t_ledger l where l.tournament_id = p_t), '[]'::jsonb));
end $$;

create or replace function public.nx_t_mark_read() returns void
language sql security definer set search_path = public as $$
  update nx_t_notifications set read = true where user_id = auth.uid() and not read;
$$;

grant execute on function public.nx_t_my_role(), public.nx_t_set_staff(uuid, text), public.nx_t_set_runner(uuid, uuid, boolean),
  public.nx_t_save(jsonb), public.nx_t_admin(uuid, text, text), public.nx_t_code_create(uuid, int, timestamptz, boolean, int),
  public.nx_t_code_revoke(uuid), public.nx_t_register(uuid, text), public.nx_t_join_code(text), public.nx_t_withdraw(uuid),
  public.nx_t_decide(uuid, uuid, boolean, text), public.nx_t_remove_entry(uuid, uuid, text), public.nx_t_set_seed(uuid, uuid, int),
  public.nx_t_ready(uuid), public.nx_t_report(uuid, int, int, int), public.nx_t_dispute(uuid, text),
  public.nx_t_admin_match(uuid, text, jsonb), public.nx_t_standings(uuid), public.nx_t_logs(uuid), public.nx_t_mark_read(),
  public.nx_t_is_admin(uuid), public.nx_t_is_organizer(uuid), public.nx_t_can_manage(uuid, uuid), public.nx_t_visible(uuid)
  to authenticated;
revoke execute on function public.nx_t_my_role(), public.nx_t_set_staff(uuid, text), public.nx_t_set_runner(uuid, uuid, boolean),
  public.nx_t_save(jsonb), public.nx_t_admin(uuid, text, text), public.nx_t_code_create(uuid, int, timestamptz, boolean, int),
  public.nx_t_code_revoke(uuid), public.nx_t_register(uuid, text), public.nx_t_join_code(text), public.nx_t_withdraw(uuid),
  public.nx_t_decide(uuid, uuid, boolean, text), public.nx_t_remove_entry(uuid, uuid, text), public.nx_t_set_seed(uuid, uuid, int),
  public.nx_t_ready(uuid), public.nx_t_report(uuid, int, int, int), public.nx_t_dispute(uuid, text),
  public.nx_t_admin_match(uuid, text, jsonb), public.nx_t_standings(uuid), public.nx_t_logs(uuid), public.nx_t_mark_read()
  from anon, public;
