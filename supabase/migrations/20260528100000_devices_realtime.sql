-- Stream device state changes (heartbeats, sync progress, revocation,
-- assignments) to the back office in realtime, replacing the 30s polling loop.
-- RLS still governs what each subscriber receives: admins get every device,
-- managers only devices of their establishments.
do $$
begin
    if not exists (
        select 1 from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename = 'devices'
    ) then
        alter publication supabase_realtime add table public.devices;
    end if;
end $$;
