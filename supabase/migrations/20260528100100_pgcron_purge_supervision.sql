-- Replace the probabilistic (1% per heartbeat) supervision purge with a
-- deterministic daily pg_cron job. pg_cron is preloaded by the Supabase
-- Postgres image and runs jobs in the `postgres` database.
create extension if not exists pg_cron;

-- Recreate record_heartbeat WITHOUT the inline `random() < 0.01` purge call.
-- Grants from the original migration persist across create-or-replace.
create or replace function public.record_heartbeat(
    p_battery int default null,
    p_storage_free_mb int default null,
    p_app_version text default null,
    p_sync_progress int default null,
    p_current_media_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_device_id uuid;
begin
    v_device_id := auth.uid();
    if v_device_id is null then
        raise exception 'No auth context' using errcode = '42501';
    end if;

    if not exists (
        select 1 from public.devices d
        where d.id = v_device_id and d.revoked_at is null
    ) then
        raise exception 'Device not found or revoked' using errcode = '42501';
    end if;

    insert into public.device_heartbeats (
        device_id, battery, storage_free_mb, app_version
    ) values (
        v_device_id, p_battery, p_storage_free_mb, p_app_version
    );

    update public.devices
       set last_seen_at = now(),
           sync_progress = coalesce(p_sync_progress, sync_progress),
           current_media_id = coalesce(p_current_media_id, current_media_id)
     where id = v_device_id;
end $$;

-- Schedule the purge daily at 03:17 UTC. cron.schedule upserts by job name,
-- so re-running this migration is idempotent.
select cron.schedule(
    'purge-supervision-data',
    '17 3 * * *',
    $$ select public.purge_old_supervision_data(); $$
);
