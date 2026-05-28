-- Verifies the deterministic supervision purge: the pg_cron job is registered
-- and purge_old_supervision_data() drops rows past their retention window
-- (heartbeats > 7 days, playback_logs > 30 days) while keeping recent ones.
begin;

select plan(3);

set local role postgres;

-- 1) The daily purge job is scheduled by the migration.
select results_eq(
    $$ select count(*) from cron.job where jobname = 'purge-supervision-data' $$,
    $$ values (1::bigint) $$,
    'pg_cron purge job is scheduled'
);

-- Seed a device with old + recent supervision rows.
insert into public.devices (id, establishment_id, name)
values ('cccccccc-1111-1111-1111-cccccccccccc',
        '11111111-1111-1111-1111-111111111111', 'Purge device');

insert into public.device_heartbeats (device_id, received_at)
values ('cccccccc-1111-1111-1111-cccccccccccc', now() - interval '10 days'),
       ('cccccccc-1111-1111-1111-cccccccccccc', now() - interval '1 day');

insert into public.playback_logs (device_id, played_at, duration_played_sec)
values ('cccccccc-1111-1111-1111-cccccccccccc', now() - interval '40 days', 5),
       ('cccccccc-1111-1111-1111-cccccccccccc', now() - interval '5 days', 5);

select public.purge_old_supervision_data();

-- 2) Heartbeats older than 7 days gone, recent kept.
select results_eq(
    $$ select count(*) from public.device_heartbeats
        where device_id = 'cccccccc-1111-1111-1111-cccccccccccc' $$,
    $$ values (1::bigint) $$,
    'purge drops heartbeats older than 7 days, keeps recent'
);

-- 3) Playback logs older than 30 days gone, recent kept.
select results_eq(
    $$ select count(*) from public.playback_logs
        where device_id = 'cccccccc-1111-1111-1111-cccccccccccc' $$,
    $$ values (1::bigint) $$,
    'purge drops playback_logs older than 30 days, keeps recent'
);

select * from finish();

rollback;
