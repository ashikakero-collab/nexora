-- ONE-OFF MAINTENANCE (not run by CI): mark the owner account. Done once on 2026-11-16.
-- 1) Create the account in Supabase Auth (Dashboard → Authentication → Add user, or the Auth admin API) with
--    email nexora_owner@nexora.app, "auto confirm" on, user_metadata {"username":"nexora_owner"} and a strong random password
--    (never committed). The on_auth_user_created trigger creates its profiles row.
-- 2) Then run this (needs migration 20261116000400_nx_owner.sql):
do $$
declare oid uuid := (select id from auth.users where lower(email) = 'nexora_owner@nexora.app');
begin
  if oid is null then raise exception 'owner auth user not found'; end if;
  update public.profiles set role = 'owner', is_guest = false where id = oid;
  insert into public.nx_staff(user_id, role, granted_by, unlimited) values (oid, 'owner', null, true)
    on conflict (user_id) do update set role = 'owner', unlimited = true;
  -- the app forces a password change on first login; the auth.users trigger clears this flag when the password really changes
  insert into public.nx_account_flags(user_id, must_change_password) values (oid, true)
    on conflict (user_id) do update set must_change_password = true;
  insert into public.nx_owner_audit(actor, action, target, data) values (null, 'owner_created', oid, '{"via":"maintenance"}');
end $$;
