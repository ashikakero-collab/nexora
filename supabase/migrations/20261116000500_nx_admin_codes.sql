-- NEXORA (Flutter, branch nxg) · Tournament-admin invite codes (owner-issued).
-- The owner creates single-use codes (optional expiry, revocable). A signed-in, registered (non-guest) player redeems one in
-- Settings → "Redeem admin code" and becomes a tournament admin: nx_staff role 'organizer' with unlimited = true (organizer
-- wizard + manage panel, unlimited coins/gems for hosting). At most nx_settings.tadmin_cap (default 10) tournament admins are
-- active at once. Only a SHA-256 hash of each code is stored; the plain code is shown to the owner once, at creation.
-- Wrong codes: 5 per 15 minutes per account (same rule as tournament codes). Idempotent.

create table if not exists public.nx_admin_codes (
  id uuid primary key default gen_random_uuid(),
  code_hash text not null unique,
  hint text not null,                       -- last 4 characters, to recognise a code in the list
  label text not null default '',
  created_by uuid,
  created_at timestamptz not null default now(),
  expires_at timestamptz,
  revoked_at timestamptz,
  revoked_by uuid,
  used_by uuid references auth.users(id) on delete set null,
  used_at timestamptz
);
create index if not exists nx_admin_codes_time on public.nx_admin_codes(created_at desc);

create table if not exists public.nx_admin_code_attempts (
  id bigserial primary key,
  user_id uuid not null,
  ok boolean not null,
  created_at timestamptz not null default now()
);
create index if not exists nx_admin_code_attempts_user on public.nx_admin_code_attempts(user_id, created_at desc);

alter table public.nx_admin_codes enable row level security;
alter table public.nx_admin_code_attempts enable row level security;
-- no policies: only the RPCs below touch these tables.

create or replace function public._nx_admin_code_norm(p text) returns text
language sql immutable as $$ select upper(regexp_replace(coalesce(p, ''), '[^A-Za-z0-9]', '', 'g')) $$;

create or replace function public._nx_admin_code_hash(p text) returns text
language sql immutable set search_path = public, extensions as $$
  select encode(extensions.digest('nx-admin-code:' || _nx_admin_code_norm(p), 'sha256'), 'hex')
$$;

-- Owner: create 1..20 codes. Returns the plain codes once (format XXXX-XXXX-XXXX, no 0/O/1/I).
create or replace function public.nx_owner_code_create(p_label text default '', p_expires_at timestamptz default null,
                                                       p_count int default 1) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare g text := _nx_owner_guard(); alphabet text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; raw text; i int; k int;
        b bytea; out jsonb := '[]'::jsonb; cid uuid;
begin
  if g is not null then return jsonb_build_object('ok', false, 'error', g); end if;
  if p_expires_at is not null and p_expires_at <= now() then return jsonb_build_object('ok', false, 'error', 'bad_expiry'); end if;
  for k in 1..greatest(1, least(coalesce(p_count, 1), 20)) loop
    loop
      b := extensions.gen_random_bytes(12); raw := '';
      for i in 0..11 loop raw := raw || substr(alphabet, (get_byte(b, i) % 32) + 1, 1); end loop;
      exit when not exists (select 1 from nx_admin_codes where code_hash = _nx_admin_code_hash(raw));
    end loop;
    insert into nx_admin_codes(code_hash, hint, label, created_by, expires_at)
    values (_nx_admin_code_hash(raw), right(raw, 4), left(coalesce(p_label, ''), 60), auth.uid(), p_expires_at) returning id into cid;
    out := out || jsonb_build_object('id', cid, 'code', substr(raw, 1, 4) || '-' || substr(raw, 5, 4) || '-' || substr(raw, 9, 4));
  end loop;
  perform _nx_owner_log('admin_code_create', null, jsonb_build_object('count', jsonb_array_length(out), 'label', p_label,
                        'expires_at', p_expires_at, 'ids', (select jsonb_agg(x -> 'id') from jsonb_array_elements(out) x)));
  return jsonb_build_object('ok', true, 'codes', out);
end $$;

create or replace function public.nx_owner_codes(p_limit int default 200) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare g text := _nx_owner_guard(); res jsonb;
begin
  if g is not null then return jsonb_build_object('ok', false, 'error', g); end if;
  select coalesce(jsonb_agg(x order by x.created_at desc), '[]'::jsonb) into res from (
    select c.id, c.hint, c.label, c.created_at, c.expires_at, c.revoked_at, c.used_at, c.used_by, p.username as used_by_name,
           case when c.revoked_at is not null then 'revoked' when c.used_at is not null then 'used'
                when c.expires_at is not null and c.expires_at < now() then 'expired' else 'active' end as status,
           (c.used_by is not null and exists (select 1 from nx_staff s where s.user_id = c.used_by and s.role = 'organizer'
                                              and s.unlimited and s.via_code = c.id)) as holder_active
      from nx_admin_codes c left join profiles p on p.id = c.used_by
     order by c.created_at desc limit greatest(1, least(coalesce(p_limit, 200), 1000))) x;
  return jsonb_build_object('ok', true, 'codes', res, 'cap', _nx_tadmin_cap(), 'active', _nx_tadmin_count());
end $$;

-- Revoke an unused code. (To take the role from someone who already redeemed one: nx_owner_set_role(user, 'player').)
create or replace function public.nx_owner_code_revoke(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare g text := _nx_owner_guard();
begin
  if g is not null then return jsonb_build_object('ok', false, 'error', g); end if;
  update nx_admin_codes set revoked_at = now(), revoked_by = auth.uid() where id = p_id and revoked_at is null;
  if not found then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  perform _nx_owner_log('admin_code_revoke', null, jsonb_build_object('code', p_id));
  return jsonb_build_object('ok', true);
end $$;

-- Player: redeem a code.
create or replace function public.nx_redeem_admin_code(p_code text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); bad int; c nx_admin_codes; err text; cur nx_staff; guest boolean;
begin
  if me is null then return jsonb_build_object('ok', false, 'error', 'not_signed_in'); end if;
  if nx_is_banned(me) then return jsonb_build_object('ok', false, 'error', 'banned'); end if;
  select coalesce(is_anonymous, false) into guest from auth.users where id = me;
  if guest then return jsonb_build_object('ok', false, 'error', 'account_required'); end if;
  select count(*) into bad from nx_admin_code_attempts where user_id = me and not ok and created_at > now() - interval '15 minutes';
  if bad >= 5 then return jsonb_build_object('ok', false, 'error', 'too_many_attempts'); end if;
  select * into cur from nx_staff where user_id = me;
  if cur.role in ('owner', 'admin') or nx_is_owner(me) then return jsonb_build_object('ok', false, 'error', 'already_staff'); end if;
  if cur.role = 'organizer' and cur.unlimited then
    return jsonb_build_object('ok', false, 'error', 'already_tournament_admin'); end if;
  select * into c from nx_admin_codes where code_hash = _nx_admin_code_hash(p_code) for update;
  if c.id is null then err := 'bad_code';
  elsif c.revoked_at is not null then err := 'code_revoked';
  elsif c.used_at is not null then err := 'code_used';
  elsif c.expires_at is not null and c.expires_at < now() then err := 'code_expired';
  end if;
  if err is not null then
    insert into nx_admin_code_attempts(user_id, ok) values (me, false);
    return jsonb_build_object('ok', false, 'error', err);
  end if;
  -- serialize redemptions so two players can't both take the last seat
  perform pg_advisory_xact_lock(hashtext('nx_tadmin_cap'));
  if _nx_tadmin_count() >= _nx_tadmin_cap() then
    return jsonb_build_object('ok', false, 'error', 'cap_reached', 'cap', _nx_tadmin_cap()); end if;
  update nx_admin_codes set used_by = me, used_at = now() where id = c.id;
  insert into nx_staff(user_id, role, granted_by, unlimited, via_code) values (me, 'organizer', c.created_by, true, c.id)
  on conflict (user_id) do update set role = 'organizer', unlimited = true, via_code = c.id, granted_by = c.created_by, granted_at = now();
  insert into nx_admin_code_attempts(user_id, ok) values (me, true);
  insert into nx_owner_audit(actor, action, target, data) values (me, 'admin_code_redeemed', me, jsonb_build_object('code', c.id));
  return jsonb_build_object('ok', true, 'role', 'tournament_admin');
end $$;

revoke execute on function public._nx_admin_code_norm(text), public._nx_admin_code_hash(text) from public, anon, authenticated;
revoke execute on function public.nx_owner_code_create(text, timestamptz, int), public.nx_owner_codes(int),
  public.nx_owner_code_revoke(uuid), public.nx_redeem_admin_code(text) from public, anon;
grant execute on function public.nx_owner_code_create(text, timestamptz, int), public.nx_owner_codes(int),
  public.nx_owner_code_revoke(uuid), public.nx_redeem_admin_code(text) to authenticated;
