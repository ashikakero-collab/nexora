-- NEXORA hub (branch nxg) — M3/M4 social worlds: Orbit Network chats + calls, Nova Gallery, Social Station.
-- Everything lives under the nx_ prefix; no existing table of the other app is changed.
-- RLS on every table; writes that need checks go through SECURITY DEFINER RPCs.

-- ───────────────────────────── ORBIT NETWORK ─────────────────────────────
create table if not exists public.nx_chats (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('direct','group','channel')),
  name text not null default '' check (char_length(name) <= 64),
  description text not null default '' check (char_length(description) <= 500),
  badge_id text not null default '',
  owner uuid not null references auth.users(id) on delete cascade,
  dm_key text unique,                       -- 'uidA:uidB' (sorted) for direct chats
  is_public boolean not null default false, -- public channels/groups can be joined by link
  created_at timestamptz not null default now(),
  last_msg_at timestamptz not null default now()
);

create table if not exists public.nx_chat_members (
  chat_id uuid not null references public.nx_chats(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'member' check (role in ('owner','admin','member')),
  joined_at timestamptz not null default now(),
  last_read_at timestamptz not null default now(),
  pinned boolean not null default false,
  muted boolean not null default false,
  primary key (chat_id, user_id)
);
create index if not exists nx_chat_members_user on public.nx_chat_members(user_id);

create table if not exists public.nx_messages (
  id uuid primary key default gen_random_uuid(),
  chat_id uuid not null references public.nx_chats(id) on delete cascade,
  author uuid references auth.users(id) on delete set null,
  author_name text not null default '',
  kind text not null default 'text' check (kind in ('text','art','shared','invite','system','call')),
  text text not null default '' check (char_length(text) <= 4000),
  payload jsonb not null default '{}'::jsonb,
  reply_to uuid,
  created_at timestamptz not null default now(),
  edited_at timestamptz,
  deleted boolean not null default false,
  pinned boolean not null default false
);
create index if not exists nx_messages_chat on public.nx_messages(chat_id, created_at);

create table if not exists public.nx_message_stars (
  user_id uuid not null references auth.users(id) on delete cascade,
  message_id uuid not null references public.nx_messages(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, message_id)
);

create table if not exists public.nx_calls (
  id uuid primary key default gen_random_uuid(),
  chat_id uuid not null references public.nx_chats(id) on delete cascade,
  caller uuid not null references auth.users(id) on delete cascade,
  video boolean not null default false,
  created_at timestamptz not null default now(),
  ended_at timestamptz
);
create index if not exists nx_calls_chat on public.nx_calls(chat_id, created_at desc);

create or replace function public.nx_is_chat_member(c uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from nx_chat_members where chat_id = c and user_id = auth.uid());
$$;

create or replace function public.nx_chat_role(c uuid) returns text
language sql stable security definer set search_path = public as $$
  select role from nx_chat_members where chat_id = c and user_id = auth.uid();
$$;

alter table public.nx_chats enable row level security;
alter table public.nx_chat_members enable row level security;
alter table public.nx_messages enable row level security;
alter table public.nx_message_stars enable row level security;
alter table public.nx_calls enable row level security;

drop policy if exists nx_chats_read on public.nx_chats;
create policy nx_chats_read on public.nx_chats for select using (is_public or public.nx_is_chat_member(id));
drop policy if exists nx_chats_update on public.nx_chats;
create policy nx_chats_update on public.nx_chats for update
  using (public.nx_chat_role(id) in ('owner','admin')) with check (public.nx_chat_role(id) in ('owner','admin'));
drop policy if exists nx_chats_delete on public.nx_chats;
create policy nx_chats_delete on public.nx_chats for delete using (owner = auth.uid() and kind <> 'direct');

drop policy if exists nx_cm_read on public.nx_chat_members;
create policy nx_cm_read on public.nx_chat_members for select using (public.nx_is_chat_member(chat_id));
drop policy if exists nx_cm_self_update on public.nx_chat_members;
create policy nx_cm_self_update on public.nx_chat_members for update using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists nx_msg_read on public.nx_messages;
create policy nx_msg_read on public.nx_messages for select using (public.nx_is_chat_member(chat_id));
-- inserts / edits go through nx_send_message / nx_edit_message (role checks for channels)

drop policy if exists nx_star_own on public.nx_message_stars;
create policy nx_star_own on public.nx_message_stars for all using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists nx_calls_read on public.nx_calls;
create policy nx_calls_read on public.nx_calls for select using (public.nx_is_chat_member(chat_id));

-- protect immutable columns of nx_chats on direct updates
create or replace function public.nx_chats_guard() returns trigger language plpgsql as $$
begin
  new.id := old.id; new.kind := old.kind; new.owner := old.owner; new.dm_key := old.dm_key; new.created_at := old.created_at;
  return new;
end $$;
drop trigger if exists nx_chats_guard on public.nx_chats;
create trigger nx_chats_guard before update on public.nx_chats for each row execute function public.nx_chats_guard();

create or replace function public.nx_cm_guard() returns trigger language plpgsql as $$
begin
  new.chat_id := old.chat_id; new.user_id := old.user_id; new.joined_at := old.joined_at;
  if current_setting('nx.role_change', true) is distinct from 'on' then new.role := old.role; end if;
  return new;
end $$;
drop trigger if exists nx_cm_guard on public.nx_chat_members;
create trigger nx_cm_guard before update on public.nx_chat_members for each row execute function public.nx_cm_guard();

create or replace function public._nx_name(u uuid) returns text
language sql stable security definer set search_path = public as $$
  select coalesce((select username from profiles where id = u), 'Pilot');
$$;

-- Direct chat with another real user (idempotent).
create or replace function public.nx_open_direct(p_user uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); k text; cid uuid;
begin
  if me is null then raise exception 'not_signed_in'; end if;
  if p_user is null or p_user = me then raise exception 'bad_user'; end if;
  if not exists(select 1 from auth.users where id = p_user) then raise exception 'no_such_user'; end if;
  k := least(me::text, p_user::text) || ':' || greatest(me::text, p_user::text);
  select id into cid from nx_chats where dm_key = k;
  if cid is null then
    insert into nx_chats(kind, owner, dm_key) values ('direct', me, k) returning id into cid;
  end if;
  -- (re)join both sides: a person who removed the chat gets it back on the next message
  insert into nx_chat_members(chat_id, user_id, role) values (cid, me, 'member'), (cid, p_user, 'member')
    on conflict do nothing;
  return cid;
end $$;

create or replace function public.nx_create_chat(p_kind text, p_name text, p_description text, p_badge text,
  p_members uuid[] default '{}', p_public boolean default false) returns uuid
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); cid uuid; u uuid;
begin
  if me is null then raise exception 'not_signed_in'; end if;
  if p_kind not in ('group','channel') then raise exception 'bad_kind'; end if;
  insert into nx_chats(kind, name, description, badge_id, owner, is_public)
    values (p_kind, left(coalesce(nullif(trim(p_name),''),'Orbit'),64), left(coalesce(p_description,''),500), coalesce(p_badge,''), me, coalesce(p_public,false))
    returning id into cid;
  insert into nx_chat_members(chat_id, user_id, role) values (cid, me, 'owner');
  foreach u in array coalesce(p_members,'{}') loop
    if u <> me and exists(select 1 from auth.users where id = u) then
      insert into nx_chat_members(chat_id, user_id) values (cid, u) on conflict do nothing;
    end if;
  end loop;
  insert into nx_messages(chat_id, author, author_name, kind, text, payload)
    values (cid, null, 'ORBIT', 'system', case when p_kind = 'channel' then 'channel_created' else 'group_created' end,
            jsonb_build_object('by', _nx_name(me)));
  return cid;
end $$;

create or replace function public.nx_add_chat_members(p_chat uuid, p_users uuid[]) returns int
language plpgsql security definer set search_path = public as $$
declare u uuid; n int := 0; k text;
begin
  select kind into k from nx_chats where id = p_chat;
  if k is null or k = 'direct' then raise exception 'bad_chat'; end if;
  if coalesce(nx_chat_role(p_chat),'') not in ('owner','admin') and not (k = 'group' and nx_is_chat_member(p_chat)) then
    raise exception 'forbidden';
  end if;
  foreach u in array coalesce(p_users,'{}') loop
    if exists(select 1 from auth.users where id = u) then
      insert into nx_chat_members(chat_id, user_id) values (p_chat, u) on conflict do nothing;
      if found then
        n := n + 1;
        insert into nx_messages(chat_id, author, author_name, kind, text, payload)
          values (p_chat, null, 'ORBIT', 'system', 'member_added', jsonb_build_object('by', _nx_name(auth.uid()), 'who', _nx_name(u)));
      end if;
    end if;
  end loop;
  return n;
end $$;

create or replace function public.nx_join_chat(p_chat uuid) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  if not exists(select 1 from nx_chats where id = p_chat and is_public) then raise exception 'not_public'; end if;
  insert into nx_chat_members(chat_id, user_id) values (p_chat, auth.uid()) on conflict do nothing;
  return true;
end $$;

create or replace function public.nx_leave_chat(p_chat uuid) returns boolean
language plpgsql security definer set search_path = public as $$
declare r text; nxt uuid;
begin
  r := nx_chat_role(p_chat);
  if r is null then return false; end if;
  delete from nx_chat_members where chat_id = p_chat and user_id = auth.uid();
  if r = 'owner' then
    select user_id into nxt from nx_chat_members where chat_id = p_chat order by (role = 'admin') desc, joined_at limit 1;
    if nxt is null then delete from nx_chats where id = p_chat;
    else
      perform set_config('nx.role_change', 'on', true);
      update nx_chat_members set role = 'owner' where chat_id = p_chat and user_id = nxt;
    end if;
  end if;
  return true;
end $$;

create or replace function public.nx_set_chat_role(p_chat uuid, p_user uuid, p_role text) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if nx_chat_role(p_chat) <> 'owner' or p_role not in ('admin','member') or p_user = auth.uid() then raise exception 'forbidden'; end if;
  perform set_config('nx.role_change', 'on', true);
  update nx_chat_members set role = p_role where chat_id = p_chat and user_id = p_user and role <> 'owner';
  return found;
end $$;

create or replace function public.nx_send_message(p_chat uuid, p_kind text, p_text text, p_payload jsonb default '{}', p_reply_to uuid default null)
returns public.nx_messages
language plpgsql security definer set search_path = public as $$
declare k text; r text; m nx_messages;
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  select kind into k from nx_chats where id = p_chat;
  r := nx_chat_role(p_chat);
  if k is null or r is null then raise exception 'not_member'; end if;
  if k = 'channel' and r not in ('owner','admin') then raise exception 'channel_admins_only'; end if;
  if p_kind not in ('text','art','shared','invite','call') then raise exception 'bad_kind'; end if;
  if p_kind = 'text' and coalesce(trim(p_text),'') = '' then raise exception 'empty'; end if;
  insert into nx_messages(chat_id, author, author_name, kind, text, payload, reply_to)
    values (p_chat, auth.uid(), _nx_name(auth.uid()), p_kind, left(trim(coalesce(p_text,'')),4000), coalesce(p_payload,'{}'), p_reply_to)
    returning * into m;
  update nx_chats set last_msg_at = m.created_at where id = p_chat;
  update nx_chat_members set last_read_at = m.created_at where chat_id = p_chat and user_id = auth.uid();
  return m;
end $$;

create or replace function public.nx_edit_message(p_id uuid, p_text text) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(trim(p_text),'') = '' then return false; end if;
  update nx_messages set text = left(trim(p_text),4000), edited_at = now()
    where id = p_id and author = auth.uid() and kind = 'text' and not deleted;
  return found;
end $$;

create or replace function public.nx_delete_message(p_id uuid) returns boolean
language plpgsql security definer set search_path = public as $$
declare c uuid; a uuid;
begin
  select chat_id, author into c, a from nx_messages where id = p_id;
  if c is null then return false; end if;
  if a is distinct from auth.uid() and coalesce(nx_chat_role(c),'') not in ('owner','admin') then raise exception 'forbidden'; end if;
  update nx_messages set deleted = true, text = '', payload = '{}', pinned = false where id = p_id;
  return true;
end $$;

create or replace function public.nx_toggle_pin_message(p_id uuid) returns boolean
language plpgsql security definer set search_path = public as $$
declare c uuid; k text; v boolean;
begin
  select m.chat_id, ch.kind into c, k from nx_messages m join nx_chats ch on ch.id = m.chat_id where m.id = p_id and not m.deleted;
  if c is null or not nx_is_chat_member(c) then return false; end if;
  if k <> 'direct' and coalesce(nx_chat_role(c),'') not in ('owner','admin') then raise exception 'forbidden'; end if;
  update nx_messages set pinned = not pinned where id = p_id returning pinned into v;
  return v;
end $$;

create or replace function public.nx_mark_read(p_chat uuid) returns void
language sql security definer set search_path = public as $$
  update nx_chat_members set last_read_at = now() where chat_id = p_chat and user_id = auth.uid();
$$;

-- Chat list with last message + unread count in one round trip.
create or replace function public.nx_my_chats() returns table (
  id uuid, kind text, name text, description text, badge_id text, owner uuid, is_public boolean, created_at timestamptz,
  last_msg_at timestamptz, role text, pinned boolean, muted boolean, last_read_at timestamptz, unread int,
  peer uuid, peer_name text, peer_avatar text, peer_online timestamptz, members int, last jsonb)
language sql stable security definer set search_path = public as $$
  select c.id, c.kind, c.name, c.description, c.badge_id, c.owner, c.is_public, c.created_at, c.last_msg_at,
         m.role, m.pinned, m.muted, m.last_read_at,
         (select count(*)::int from nx_messages x where x.chat_id = c.id and x.created_at > m.last_read_at
            and x.author is distinct from auth.uid() and not x.deleted),
         p.id, p.username, p.avatar, p.online_at,
         (select count(*)::int from nx_chat_members y where y.chat_id = c.id),
         (select to_jsonb(l) from (select * from nx_messages z where z.chat_id = c.id order by z.created_at desc limit 1) l)
  from nx_chat_members m
  join nx_chats c on c.id = m.chat_id
  left join lateral (select pr.id, pr.username, pr.avatar, pr.online_at from nx_chat_members o join profiles pr on pr.id = o.user_id
                     where c.kind = 'direct' and o.chat_id = c.id and o.user_id <> auth.uid() limit 1) p on true
  where m.user_id = auth.uid()
  order by m.pinned desc, c.last_msg_at desc;
$$;

-- Calls: a row per started call; members get it in real time and ring.
create or replace function public.nx_start_call(p_chat uuid, p_video boolean) returns uuid
language plpgsql security definer set search_path = public as $$
declare cid uuid;
begin
  if not nx_is_chat_member(p_chat) then raise exception 'not_member'; end if;
  insert into nx_calls(chat_id, caller, video) values (p_chat, auth.uid(), coalesce(p_video,false)) returning id into cid;
  insert into nx_messages(chat_id, author, author_name, kind, text, payload)
    values (p_chat, auth.uid(), _nx_name(auth.uid()), 'call', '', jsonb_build_object('call', cid, 'video', coalesce(p_video,false)));
  update nx_chats set last_msg_at = now() where id = p_chat;
  return cid;
end $$;

create or replace function public.nx_end_call(p_call uuid) returns void
language sql security definer set search_path = public as $$
  update nx_calls set ended_at = coalesce(ended_at, now()) where id = p_call and nx_is_chat_member(chat_id);
$$;

-- ───────────────────────────── NOVA GALLERY ─────────────────────────────
create table if not exists public.nx_posts (
  id uuid primary key default gen_random_uuid(),
  author uuid not null references auth.users(id) on delete cascade,
  kind text not null default 'post' check (kind in ('post','story')),
  text text not null default '' check (char_length(text) <= 2200),
  visual jsonb not null default '{}'::jsonb,   -- {k:'gradient'|'asset'|'photo', g, a, url, path}
  motion boolean not null default false,
  hashtags text[] not null default '{}',
  like_count int not null default 0,
  comment_count int not null default 0,
  created_at timestamptz not null default now(),
  edited_at timestamptz,
  expires_at timestamptz
);
create index if not exists nx_posts_feed on public.nx_posts(kind, created_at desc);
create index if not exists nx_posts_tags on public.nx_posts using gin(hashtags);

create table if not exists public.nx_post_likes (
  post_id uuid not null references public.nx_posts(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);
create table if not exists public.nx_post_saves (
  post_id uuid not null references public.nx_posts(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);
create table if not exists public.nx_post_comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.nx_posts(id) on delete cascade,
  author uuid not null references auth.users(id) on delete cascade,
  text text not null check (char_length(text) between 1 and 1000),
  created_at timestamptz not null default now()
);
create index if not exists nx_post_comments_post on public.nx_post_comments(post_id, created_at);
create table if not exists public.nx_story_views (
  post_id uuid not null references public.nx_posts(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  primary key (post_id, user_id)
);
create table if not exists public.nx_notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  actor uuid references auth.users(id) on delete cascade,
  kind text not null,
  post_id uuid references public.nx_posts(id) on delete cascade,
  text text not null default '',
  read boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists nx_notifications_user on public.nx_notifications(user_id, created_at desc);

alter table public.nx_posts enable row level security;
alter table public.nx_post_likes enable row level security;
alter table public.nx_post_saves enable row level security;
alter table public.nx_post_comments enable row level security;
alter table public.nx_story_views enable row level security;
alter table public.nx_notifications enable row level security;

drop policy if exists nx_posts_read on public.nx_posts;
create policy nx_posts_read on public.nx_posts for select using (expires_at is null or expires_at > now() or author = auth.uid());
drop policy if exists nx_posts_insert on public.nx_posts;
create policy nx_posts_insert on public.nx_posts for insert with check (author = auth.uid() and like_count = 0 and comment_count = 0);
drop policy if exists nx_posts_update on public.nx_posts;
create policy nx_posts_update on public.nx_posts for update using (author = auth.uid()) with check (author = auth.uid());
drop policy if exists nx_posts_delete on public.nx_posts;
create policy nx_posts_delete on public.nx_posts for delete using (author = auth.uid());

drop policy if exists nx_likes_read on public.nx_post_likes;
create policy nx_likes_read on public.nx_post_likes for select using (true);
drop policy if exists nx_likes_write on public.nx_post_likes;
create policy nx_likes_write on public.nx_post_likes for insert with check (user_id = auth.uid());
drop policy if exists nx_likes_del on public.nx_post_likes;
create policy nx_likes_del on public.nx_post_likes for delete using (user_id = auth.uid());

drop policy if exists nx_saves_own on public.nx_post_saves;
create policy nx_saves_own on public.nx_post_saves for all using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists nx_comments_read on public.nx_post_comments;
create policy nx_comments_read on public.nx_post_comments for select using (true);
drop policy if exists nx_comments_write on public.nx_post_comments;
create policy nx_comments_write on public.nx_post_comments for insert with check (author = auth.uid());
drop policy if exists nx_comments_del on public.nx_post_comments;
create policy nx_comments_del on public.nx_post_comments for delete
  using (author = auth.uid() or exists(select 1 from public.nx_posts p where p.id = post_id and p.author = auth.uid()));

drop policy if exists nx_views_own on public.nx_story_views;
create policy nx_views_own on public.nx_story_views for all using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists nx_notif_own on public.nx_notifications;
create policy nx_notif_own on public.nx_notifications for select using (user_id = auth.uid());
drop policy if exists nx_notif_upd on public.nx_notifications;
create policy nx_notif_upd on public.nx_notifications for update using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists nx_notif_del on public.nx_notifications;
create policy nx_notif_del on public.nx_notifications for delete using (user_id = auth.uid());

-- server-owned columns + hashtags derived from text
create or replace function public.nx_posts_guard() returns trigger language plpgsql as $$
begin
  new.hashtags := coalesce((select array_agg(distinct lower(m[1])) from regexp_matches(new.text, '#([[:alnum:]_\u0600-\u06FF]{1,40})', 'g') m), '{}');
  if tg_op = 'UPDATE' then
    new.author := old.author; new.kind := old.kind; new.created_at := old.created_at; new.expires_at := old.expires_at;
    if current_setting('nx.counter', true) is distinct from 'on' then
      new.like_count := old.like_count; new.comment_count := old.comment_count; new.edited_at := now();
    end if;
  else
    new.created_at := now(); new.like_count := 0; new.comment_count := 0;
    new.expires_at := case when new.kind = 'story' then now() + interval '24 hours' else null end;
  end if;
  return new;
end $$;
drop trigger if exists nx_posts_guard on public.nx_posts;
create trigger nx_posts_guard before insert or update on public.nx_posts for each row execute function public.nx_posts_guard();

create or replace function public.nx_post_counters() returns trigger
language plpgsql security definer set search_path = public as $$
declare pid uuid := coalesce(new.post_id, old.post_id); a uuid;
begin
  perform set_config('nx.counter', 'on', true);
  if tg_table_name = 'nx_post_likes' then
    update nx_posts set like_count = (select count(*) from nx_post_likes where post_id = pid) where id = pid returning author into a;
    if tg_op = 'INSERT' and a is not null and a <> new.user_id then
      insert into nx_notifications(user_id, actor, kind, post_id, text) values (a, new.user_id, 'like', pid, _nx_name(new.user_id));
    end if;
  else
    update nx_posts set comment_count = (select count(*) from nx_post_comments where post_id = pid) where id = pid returning author into a;
    if tg_op = 'INSERT' and a is not null and a <> new.author then
      insert into nx_notifications(user_id, actor, kind, post_id, text) values (a, new.author, 'comment', pid, _nx_name(new.author) || ': ' || left(new.text, 80));
    end if;
  end if;
  perform set_config('nx.counter', 'off', true);
  return null;
end $$;
drop trigger if exists nx_likes_count on public.nx_post_likes;
create trigger nx_likes_count after insert or delete on public.nx_post_likes for each row execute function public.nx_post_counters();
drop trigger if exists nx_comments_count on public.nx_post_comments;
create trigger nx_comments_count after insert or delete on public.nx_post_comments for each row execute function public.nx_post_counters();

-- Media bucket: public read (posts are public), each user writes only inside their own folder <uid>/...
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('nx-media', 'nx-media', true, 8388608, array['image/jpeg','image/png','image/webp','image/gif'])
on conflict (id) do nothing;
drop policy if exists nx_media_read on storage.objects;
create policy nx_media_read on storage.objects for select using (bucket_id = 'nx-media');
drop policy if exists nx_media_insert on storage.objects;
create policy nx_media_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'nx-media' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists nx_media_update on storage.objects;
create policy nx_media_update on storage.objects for update to authenticated
  using (bucket_id = 'nx-media' and owner = auth.uid());
drop policy if exists nx_media_delete on storage.objects;
create policy nx_media_delete on storage.objects for delete to authenticated
  using (bucket_id = 'nx-media' and (storage.foldername(name))[1] = auth.uid()::text);

-- ───────────────────────────── SOCIAL STATION ─────────────────────────────
-- A community document (posts / events / announcements / tournaments with brackets / local players) plus
-- real membership rows. Writes are versioned (optimistic concurrency) and filtered by the caller's role.
create table if not exists public.nx_communities (
  id uuid primary key default gen_random_uuid(),
  owner uuid not null references auth.users(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 48),
  kind text not null default 'public' check (kind in ('public','private','topic','game','tournament')),
  badge_id text not null default '',
  invite_code text not null unique,
  data jsonb not null default '{}'::jsonb,
  version int not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.nx_community_members (
  community_id uuid not null references public.nx_communities(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'member' check (role in ('owner','admin','moderator','member')),
  joined_at timestamptz not null default now(),
  primary key (community_id, user_id)
);
create index if not exists nx_community_members_user on public.nx_community_members(user_id);

create or replace function public.nx_community_role(c uuid) returns text
language sql stable security definer set search_path = public as $$
  select role from nx_community_members where community_id = c and user_id = auth.uid();
$$;
create or replace function public._nx_rank(r text) returns int language sql immutable as $$
  select case r when 'owner' then 3 when 'admin' then 2 when 'moderator' then 1 when 'member' then 0 else -1 end;
$$;

alter table public.nx_communities enable row level security;
alter table public.nx_community_members enable row level security;
drop policy if exists nx_comm_read on public.nx_communities;
create policy nx_comm_read on public.nx_communities for select using (kind <> 'private' or public.nx_community_role(id) is not null);
drop policy if exists nx_commm_read on public.nx_community_members;
create policy nx_commm_read on public.nx_community_members for select
  using (exists(select 1 from public.nx_communities c where c.id = community_id and (c.kind <> 'private' or public.nx_community_role(c.id) is not null)));

create or replace function public.nx_community_create(p_name text, p_kind text, p_badge text, p_data jsonb) returns public.nx_communities
language plpgsql security definer set search_path = public as $$
declare r nx_communities; code text; i int := 0;
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  loop
    code := 'NX-' || (select string_agg(substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', 1 + floor(random() * 32)::int, 1), '') from generate_series(1, 6));
    exit when not exists(select 1 from nx_communities where invite_code = code);
    i := i + 1; if i > 20 then raise exception 'code_gen'; end if;
  end loop;
  insert into nx_communities(owner, name, kind, badge_id, invite_code, data)
    values (auth.uid(), left(coalesce(nullif(trim(p_name),''),'Community'),48), coalesce(p_kind,'public'), coalesce(p_badge,''), code,
            coalesce(p_data,'{}') - 'members' - 'id' - 'ownerId' - 'inviteCode')
    returning * into r;
  insert into nx_community_members(community_id, user_id, role) values (r.id, auth.uid(), 'owner');
  return r;
end $$;

-- Save a new version of the document. Each role may only change its own parts:
-- member: posts + events (RSVP); moderator: + tournaments, local players; admin/owner: everything.
create or replace function public.nx_community_save(p_id uuid, p_data jsonb, p_version int) returns int
language plpgsql security definer set search_path = public as $$
declare c nx_communities; r text; d jsonb; nv int;
begin
  r := nx_community_role(p_id);
  if r is null then raise exception 'not_member'; end if;
  select * into c from nx_communities where id = p_id for update;
  if c.version <> p_version then raise exception 'conflict'; end if;
  d := c.data;
  d := jsonb_set(d, '{posts}', coalesce(p_data->'posts', '[]'));
  d := jsonb_set(d, '{events}', coalesce(p_data->'events', '[]'));
  if _nx_rank(r) >= 1 then
    d := jsonb_set(d, '{tournaments}', coalesce(p_data->'tournaments', '[]'));
    d := jsonb_set(d, '{localMembers}', coalesce(p_data->'localMembers', '[]'));
  end if;
  if _nx_rank(r) >= 2 then
    d := (p_data - 'members' - 'id' - 'ownerId' - 'inviteCode');
  end if;
  nv := c.version + 1;
  update nx_communities set data = d, version = nv, updated_at = now(),
    name = case when _nx_rank(r) >= 2 then left(coalesce(nullif(trim(p_data->>'name'),''), name),48) else name end,
    kind = case when _nx_rank(r) >= 2 and (p_data->>'kind') in ('public','private','topic','game','tournament') then p_data->>'kind' else kind end,
    badge_id = case when _nx_rank(r) >= 2 then coalesce(p_data->>'badgeId', badge_id) else badge_id end
  where id = p_id;
  return nv;
end $$;

create or replace function public.nx_community_join(p_code text) returns uuid
language plpgsql security definer set search_path = public as $$
declare cid uuid;
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  select id into cid from nx_communities where invite_code = upper(trim(p_code));
  if cid is null then raise exception 'no_such_code'; end if;
  insert into nx_community_members(community_id, user_id) values (cid, auth.uid()) on conflict do nothing;
  return cid;
end $$;

create or replace function public.nx_community_join_open(p_id uuid) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if not exists(select 1 from nx_communities where id = p_id and kind <> 'private') then raise exception 'private'; end if;
  insert into nx_community_members(community_id, user_id) values (p_id, auth.uid()) on conflict do nothing;
  return true;
end $$;

create or replace function public.nx_community_leave(p_id uuid) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if nx_community_role(p_id) = 'owner' then raise exception 'owner_cannot_leave'; end if;
  delete from nx_community_members where community_id = p_id and user_id = auth.uid();
  return found;
end $$;

create or replace function public.nx_community_set_role(p_id uuid, p_user uuid, p_role text) returns boolean
language plpgsql security definer set search_path = public as $$
declare a text := nx_community_role(p_id); t text;
begin
  select role into t from nx_community_members where community_id = p_id and user_id = p_user;
  if a is null or t is null or p_user = auth.uid() or t = 'owner' or p_role not in ('admin','moderator','member')
     or _nx_rank(a) < 2 or _nx_rank(t) >= _nx_rank(a) or _nx_rank(p_role) >= _nx_rank(a) then
    raise exception 'forbidden';
  end if;
  update nx_community_members set role = p_role where community_id = p_id and user_id = p_user;
  return true;
end $$;

create or replace function public.nx_community_kick(p_id uuid, p_user uuid) returns boolean
language plpgsql security definer set search_path = public as $$
declare a text := nx_community_role(p_id); t text;
begin
  select role into t from nx_community_members where community_id = p_id and user_id = p_user;
  if a is null or t is null or p_user = auth.uid() or t = 'owner' or _nx_rank(a) < 1 or _nx_rank(a) <= _nx_rank(t) then
    raise exception 'forbidden';
  end if;
  delete from nx_community_members where community_id = p_id and user_id = p_user;
  return true;
end $$;

create or replace function public.nx_community_delete(p_id uuid) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if nx_community_role(p_id) <> 'owner' then raise exception 'forbidden'; end if;
  delete from nx_communities where id = p_id;
  return true;
end $$;

-- ───────────────────────────── grants + realtime ─────────────────────────────
revoke all on function public.nx_chats_guard(), public.nx_cm_guard(), public.nx_posts_guard(), public.nx_post_counters() from public, anon;
grant select, update, delete on public.nx_chats to authenticated;
grant select, update on public.nx_chat_members to authenticated;
grant select on public.nx_messages, public.nx_calls to authenticated;
grant select, insert, delete on public.nx_message_stars, public.nx_post_likes, public.nx_post_saves, public.nx_story_views to authenticated;
grant select, insert, update, delete on public.nx_posts to authenticated;
grant select, insert, delete on public.nx_post_comments to authenticated;
grant select, update, delete on public.nx_notifications to authenticated;
grant select on public.nx_communities, public.nx_community_members to authenticated;

do $$
declare t text;
begin
  foreach t in array array['nx_messages','nx_chat_members','nx_calls','nx_posts','nx_post_comments','nx_notifications','nx_communities','nx_community_members'] loop
    if not exists(select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;
