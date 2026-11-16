-- ONE-OFF MAINTENANCE (not a migration, never run by CI): reset all user data of project eisstodgncimypdawisy to zero.
-- Keeps every schema object, function, RLS policy, cron job, bucket, and the static/config tables:
--   arena_tiers, challenge_defs, disc_packs, discs, gm_quiz_bank, leagues, nx_catalog, season_rewards, seasons,
--   admin_codes (the other app's unused owner invite codes; used_by is set null), cron.job, vault.secrets, storage.buckets.
-- Run as postgres (SQL editor / Management API) after:  select set_config('nx.confirm_wipe', 'YES', false);
-- Then empty the Storage buckets with wipe_storage.sh (storage.objects rows must go through the Storage API so the
-- files themselves are deleted too). Executed once on 2026-11-16 before the owner account was created.
begin;
do $$ begin
  if current_setting('nx.confirm_wipe', true) is distinct from 'YES' then
    raise exception 'refusing to wipe: run  select set_config(''nx.confirm_wipe'', ''YES'', false);  first';
  end if;
end $$;

-- user data of both apps (TRUNCATE skips the append-only row triggers of nx_t_ledger / nx_t_audit on purpose)
truncate table
  public.admin_applications, public.admin_audit, public.admin_bank_ledger, public.admin_banks, public.admin_code_attempts,
  public.admins, public.arena_stakes, public.client_errors,
  public.club_challenges, public.club_members, public.club_requests, public.clubs,
  public.conversation_members, public.conversations, public.messages, public.notifications, public.device_tokens,
  public.cup_games, public.cup_ledger, public.cup_lineups, public.cup_matches, public.cup_payouts, public.cup_players,
  public.cup_rankings, public.cups,
  public.follows, public.friend_requests, public.user_blocks,
  public.game_moves, public.game_private, public.game_ratings, public.game_secret, public.game_state,
  public.inventory, public.matches, public.mm_tickets, public.room_players, public.rooms,
  public.season_claims, public.user_challenges, public.xp_events, public.oracle_usage,
  public.tournament_codes, public.tournament_entries, public.tournament_matches, public.tournament_prizes, public.tournaments,
  public.nx_calls, public.nx_chat_members, public.nx_chats, public.nx_messages, public.nx_message_stars,
  public.nx_communities, public.nx_community_members,
  public.nx_posts, public.nx_post_comments, public.nx_post_likes, public.nx_post_saves, public.nx_story_views, public.nx_notifications,
  public.nx_rooms, public.nx_room_players, public.nx_invites, public.nx_matches, public.nx_match_moves, public.nx_match_results,
  public.nx_match_secrets, public.nx_game_stats, public.nx_xp_events, public.nx_profiles,
  public.nx_staff, public.nx_tournaments, public.nx_t_audit, public.nx_t_code_attempts, public.nx_t_codes, public.nx_t_entries,
  public.nx_t_games, public.nx_t_jobs, public.nx_t_ledger, public.nx_t_matches, public.nx_t_notifications, public.nx_t_reports,
  public.nx_t_staff
  restart identity;

-- owner console tables (exist from migration 20261116000400 on)
do $$ begin
  if to_regclass('public.nx_owner_audit') is not null then
    execute 'truncate public.nx_owner_audit, public.nx_admin_codes, public.nx_admin_code_attempts, public.nx_account_flags restart identity';
  end if;
end $$;

-- every account: cascades profiles + identities/sessions/refresh tokens/MFA; admin_codes.used_by -> null
delete from auth.users;
delete from auth.audit_log_entries;
delete from auth.flow_state;
delete from auth.one_time_tokens;
truncate realtime.messages;
commit;
