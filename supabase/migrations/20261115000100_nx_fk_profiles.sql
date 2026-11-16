-- Let PostgREST embed public profiles (username/avatar) in lobby + results queries.
do $$ begin
  begin alter table public.nx_room_players add constraint nx_room_players_profile_fk foreign key (user_id) references public.profiles(id) on delete cascade; exception when duplicate_object then null; end;
  begin alter table public.nx_match_results add constraint nx_match_results_profile_fk foreign key (user_id) references public.profiles(id) on delete cascade; exception when duplicate_object then null; end;
  begin alter table public.nx_game_stats add constraint nx_game_stats_profile_fk foreign key (user_id) references public.profiles(id) on delete cascade; exception when duplicate_object then null; end;
end $$;
notify pgrst, 'reload schema';
