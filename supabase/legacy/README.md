# Legacy (not applied)
Planning-stage SQL/Edge Function from the offline build. They collide with tables that already exist on the
shared Supabase project (profiles, conversations, messages …) and were **never applied**. The live schema is
`supabase/migrations/20261115*_nx_*.sql` (nx_ prefix). Online physics is host-authoritative on the phones
(shot input relayed + snapshot correction), so `submit_shot` is not used.
