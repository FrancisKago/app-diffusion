create or replace function public.purge_old_supervision_data()
returns void
language sql
security definer
set search_path = public
as $$
    delete from public.device_heartbeats where received_at < now() - interval '7 days';
    delete from public.playback_logs where played_at < now() - interval '30 days';
$$;

revoke all on function public.purge_old_supervision_data() from public;

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

    if random() < 0.01 then
        perform public.purge_old_supervision_data();
    end if;
end $$;

revoke all on function public.record_heartbeat(int, int, text, int, uuid) from public;
grant execute on function public.record_heartbeat(int, int, text, int, uuid) to authenticated;

create or replace function public.record_playback(
    p_media_id uuid,
    p_duration_played_sec int
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

    insert into public.playback_logs (
        device_id, media_id, duration_played_sec
    ) values (
        v_device_id, p_media_id, greatest(p_duration_played_sec, 0)
    );
end $$;

revoke all on function public.record_playback(uuid, int) from public;
grant execute on function public.record_playback(uuid, int) to authenticated;
