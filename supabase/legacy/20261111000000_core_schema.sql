-- NEXORA core schema (STEP_06/07/13). Apply with: supabase db push
-- RLS on every table (P19). Clients read; sensitive writes go through RPC/Edge Functions.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  explorer_id text unique not null,
  username text unique not null check (char_length(username) between 2 and 20),
  bio text default '',
  avatar_core text default 'hero_front',
  xp integer not null default 0,
  coins integer not null default 0,
  equipped jsonb not null default '{}'::jsonb,
  orbit_layout jsonb not null default '{}'::jsonb,
  orbit_theme text not null default 'aurora',
  created_at timestamptz not null default now()
);
alter table public.profiles enable row level security;
create policy "profiles readable by signed in" on public.profiles for select using (auth.role() = 'authenticated');
create policy "own profile cosmetic update" on public.profiles for update using (auth.uid() = id)
  with check (auth.uid() = id);
-- xp/coins are only changed by security definer functions below:
revoke update (xp, coins) on public.profiles from authenticated;

create table if not exists public.xp_events (
  id bigserial primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  event text not null,
  xp integer not null,
  coins integer not null default 0,
  idempotency_key text not null,
  created_at timestamptz not null default now(),
  unique (user_id, idempotency_key)
);
alter table public.xp_events enable row level security;
create policy "own xp events" on public.xp_events for select using (auth.uid() = user_id);

create table if not exists public.inventory (
  user_id uuid not null references public.profiles(id) on delete cascade,
  item_id text not null,
  acquired_at timestamptz not null default now(),
  primary key (user_id, item_id)
);
alter table public.inventory enable row level security;
create policy "own inventory" on public.inventory for select using (auth.uid() = user_id);

create table if not exists public.user_achievements (
  user_id uuid not null references public.profiles(id) on delete cascade,
  achievement_id text not null,
  unlocked_at timestamptz not null default now(),
  primary key (user_id, achievement_id)
);
alter table public.user_achievements enable row level security;
create policy "achievements readable" on public.user_achievements for select using (auth.role() = 'authenticated');

create table if not exists public.game_stats (
  user_id uuid not null references public.profiles(id) on delete cascade,
  game_id text not null,
  played integer not null default 0,
  won integer not null default 0,
  lost integer not null default 0,
  draw integer not null default 0,
  best integer not null default 0,
  primary key (user_id, game_id)
);
alter table public.game_stats enable row level security;
create policy "stats readable" on public.game_stats for select using (auth.role() = 'authenticated');

-- Social graph, messaging, posts, communities (STEP_15/23/25/26)
create table if not exists public.friendships (
  user_id uuid references public.profiles(id) on delete cascade,
  friend_id uuid references public.profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','accepted','blocked')),
  created_at timestamptz default now(),
  primary key (user_id, friend_id)
);
alter table public.friendships enable row level security;
create policy "own friendships" on public.friendships for all using (auth.uid() in (user_id, friend_id));

create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('direct','group','channel')),
  title text, icon text, description text,
  created_by uuid references public.profiles(id),
  created_at timestamptz default now()
);
create table if not exists public.conversation_members (
  conversation_id uuid references public.conversations(id) on delete cascade,
  user_id uuid references public.profiles(id) on delete cascade,
  role text not null default 'member',
  primary key (conversation_id, user_id)
);
create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid references public.conversations(id) on delete cascade,
  sender_id uuid references public.profiles(id),
  body text, kind text not null default 'text', payload jsonb default '{}'::jsonb,
  reply_to uuid, edited_at timestamptz, deleted boolean default false,
  created_at timestamptz default now()
);
alter table public.conversations enable row level security;
alter table public.conversation_members enable row level security;
alter table public.messages enable row level security;
create policy "members see conversation" on public.conversations for select using (
  exists (select 1 from public.conversation_members m where m.conversation_id = id and m.user_id = auth.uid()));
create policy "members see members" on public.conversation_members for select using (
  exists (select 1 from public.conversation_members m where m.conversation_id = conversation_id and m.user_id = auth.uid()));
create policy "members read messages" on public.messages for select using (
  exists (select 1 from public.conversation_members m where m.conversation_id = messages.conversation_id and m.user_id = auth.uid()));
create policy "members send messages" on public.messages for insert with check (
  sender_id = auth.uid() and exists (select 1 from public.conversation_members m
    where m.conversation_id = messages.conversation_id and m.user_id = auth.uid()));

create table if not exists public.posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid references public.profiles(id) on delete cascade,
  body text, visual jsonb default '{}'::jsonb, kind text default 'post',
  visibility text not null default 'public' check (visibility in ('public','friends','private')),
  expires_at timestamptz,
  created_at timestamptz default now()
);
create table if not exists public.post_likes (post_id uuid references public.posts(id) on delete cascade,
  user_id uuid references public.profiles(id) on delete cascade, primary key (post_id, user_id));
create table if not exists public.post_comments (id uuid primary key default gen_random_uuid(),
  post_id uuid references public.posts(id) on delete cascade, author_id uuid references public.profiles(id),
  body text not null, created_at timestamptz default now());
alter table public.posts enable row level security;
alter table public.post_likes enable row level security;
alter table public.post_comments enable row level security;
create policy "public posts readable" on public.posts for select using (visibility = 'public' or author_id = auth.uid());
create policy "own posts write" on public.posts for all using (author_id = auth.uid()) with check (author_id = auth.uid());
create policy "likes" on public.post_likes for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "comments read" on public.post_comments for select using (true);
create policy "comments write" on public.post_comments for insert with check (author_id = auth.uid());

create table if not exists public.communities (
  id uuid primary key default gen_random_uuid(),
  name text not null, kind text not null, badge text, description text, is_private boolean default false,
  owner_id uuid references public.profiles(id), created_at timestamptz default now()
);
create table if not exists public.community_members (
  community_id uuid references public.communities(id) on delete cascade,
  user_id uuid references public.profiles(id) on delete cascade,
  role text not null default 'member' check (role in ('owner','admin','moderator','member')),
  primary key (community_id, user_id)
);
alter table public.communities enable row level security;
alter table public.community_members enable row level security;
create policy "public communities" on public.communities for select using (not is_private or owner_id = auth.uid()
  or exists (select 1 from public.community_members m where m.community_id = id and m.user_id = auth.uid()));
create policy "member list" on public.community_members for select using (true);

create table if not exists public.reports (
  id bigserial primary key, reporter_id uuid references public.profiles(id),
  target_kind text not null, target_id text not null, reason text, created_at timestamptz default now()
);
alter table public.reports enable row level security;
create policy "file report" on public.reports for insert with check (reporter_id = auth.uid());

-- Server-authoritative XP (P21). Called by Edge Functions with service role after validating the event.
create or replace function public.award_xp(p_user uuid, p_event text, p_xp int, p_coins int, p_key text)
returns void language plpgsql security definer set search_path = public as $$
declare today_total int;
begin
  select coalesce(sum(xp),0) into today_total from xp_events
    where user_id = p_user and created_at >= date_trunc('day', now());
  if today_total + p_xp > 3000 then p_xp := greatest(0, 3000 - today_total); end if;
  insert into xp_events(user_id, event, xp, coins, idempotency_key) values (p_user, p_event, p_xp, p_coins, p_key)
    on conflict (user_id, idempotency_key) do nothing;
  if found then
    update profiles set xp = xp + p_xp, coins = coins + p_coins where id = p_user;
  end if;
end $$;
revoke all on function public.award_xp(uuid, text, int, int, text) from public, authenticated;

-- Purchases: deterministic price check server-side (no gambling, P26)
create table if not exists public.catalog (item_id text primary key, price int not null, min_level int not null default 1);
alter table public.catalog enable row level security;
create policy "catalog readable" on public.catalog for select using (true);

create or replace function public.purchase_item(p_item text)
returns boolean language plpgsql security definer set search_path = public as $$
declare v_price int; v_coins int;
begin
  select price into v_price from catalog where item_id = p_item;
  if v_price is null then return false; end if;
  if exists (select 1 from inventory where user_id = auth.uid() and item_id = p_item) then return false; end if;
  select coins into v_coins from profiles where id = auth.uid() for update;
  if v_coins < v_price then return false; end if;
  update profiles set coins = coins - v_price where id = auth.uid();
  insert into inventory(user_id, item_id) values (auth.uid(), p_item);
  return true;
end $$;
grant execute on function public.purchase_item(text) to authenticated;
