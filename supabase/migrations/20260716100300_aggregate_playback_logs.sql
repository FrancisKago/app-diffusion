-- playback_logs grew ~46k rows/day because record_playback inserted one row on
-- every clip loop. That volume caused media- and device-deletion timeouts and
-- slow exports. Aggregate instead: one row per (device, media, hour) holding
-- the cumulative duration and a play count.
--
-- The RPC signature is unchanged, so already-deployed players get this fix
-- with no APK update — their per-loop calls now fold into the hourly row.

-- Number of individual plays folded into a row (duration is cumulative).
alter table public.playback_logs
    add column if not exists play_count int not null default 1;

-- Upsert target for the aggregation. The table is empty at migration time, so
-- the unique index is safe to add. media_id is effectively always set by the
-- RPC (nullable only for legacy reasons), so NULL-distinct semantics are moot.
create unique index if not exists playback_logs_device_media_hour_uniq
    on public.playback_logs (device_id, media_id, played_at);

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

    -- Fold this play into the current hour's row for (device, media).
    insert into public.playback_logs (
        device_id, media_id, played_at, duration_played_sec, play_count
    ) values (
        v_device_id,
        p_media_id,
        date_trunc('hour', now()),
        greatest(p_duration_played_sec, 0),
        1
    )
    on conflict (device_id, media_id, played_at)
    do update set
        duration_played_sec =
            public.playback_logs.duration_played_sec + excluded.duration_played_sec,
        play_count = public.playback_logs.play_count + 1;
end $$;

revoke all on function public.record_playback(uuid, int) from public;
grant execute on function public.record_playback(uuid, int) to authenticated;
