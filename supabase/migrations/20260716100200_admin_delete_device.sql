-- Deleting a device cascades to playback_logs.device_id + device_heartbeats
-- .device_id (both `on delete cascade`). A long-running kiosk accumulates
-- over a million playback_logs (1.3M observed), so the cascade delete blows
-- the 8s statement_timeout (57014) — same root cause as the media delete, and
-- the timeout can't be lifted from inside a single statement.
--
-- This admin-only RPC does the deletion in bounded batches, one HTTP call =
-- one statement, so each stays under the timeout. The caller loops until it
-- returns true (device fully removed). Children are cleared first, so the
-- final device delete has an empty cascade.
create or replace function public.admin_delete_device(
    p_id uuid,
    p_batch int default 50000
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
    n int;
begin
    if not public.is_admin() then
        raise exception 'Admin role required' using errcode = '42501';
    end if;

    delete from public.playback_logs
     where id in (
        select id from public.playback_logs
         where device_id = p_id
         limit p_batch
     );
    get diagnostics n = row_count;
    if n > 0 then
        return false; -- more playback_logs to clear
    end if;

    delete from public.device_heartbeats
     where id in (
        select id from public.device_heartbeats
         where device_id = p_id
         limit p_batch
     );
    get diagnostics n = row_count;
    if n > 0 then
        return false; -- more heartbeats to clear
    end if;

    -- Children cleared: the device delete now cascades over nothing heavy.
    delete from public.devices where id = p_id;
    return true;
end $$;

revoke all on function public.admin_delete_device(uuid, int) from public;
grant execute on function public.admin_delete_device(uuid, int) to authenticated;
