-- NEXORA tournaments · scheduler + realtime.
-- pg_cron is enabled on this project (extension `pg_cron`, also used by the other app's jobs). nx_t_tick runs every minute:
-- open/close registration, draw, start, 10-minute reminders, ready checks, walkovers, result acceptance, finish + payouts.
create extension if not exists pg_cron;

do $$
begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'nx_t_tick';
exception when others then null;
end $$;
select cron.schedule('nx_t_tick', '* * * * *', 'select public.nx_t_tick()');

do $$ begin
  begin alter publication supabase_realtime add table public.nx_tournaments; exception when others then null; end;
  begin alter publication supabase_realtime add table public.nx_t_matches; exception when others then null; end;
  begin alter publication supabase_realtime add table public.nx_t_entries; exception when others then null; end;
  begin alter publication supabase_realtime add table public.nx_t_notifications; exception when others then null; end;
end $$;
