begin;

select plan(6);

set local role postgres;

-- Seed: 1 device + 1 media for the existing Lounge Plateau
insert into public.devices (id, establishment_id, name)
values ('99999999-9999-9999-9999-999999999999',
        '11111111-1111-1111-1111-111111111111',
        'Test device supervision');

insert into public.media (
    id, establishment_id, type, file_path, file_size,
    mime_type, checksum_sha256, original_filename
) values (
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    '11111111-1111-1111-1111-111111111111',
    'image',
    '11111111-1111-1111-1111-111111111111/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa.jpg',
    1024, 'image/jpeg', 'sup1', 'sup.jpg'
);

set local role authenticated;

-- 1) Device peut appeler record_heartbeat (auth.uid() = device_id via JWT claims)
set local "request.jwt.claims" to '{"sub":"99999999-9999-9999-9999-999999999999","role":"authenticated","is_device":true,"establishment_id":"11111111-1111-1111-1111-111111111111"}';
select public.record_heartbeat(85, 4096, 'player-0.1.0', 100, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
select pass('record_heartbeat callable by device');

-- 2) Heartbeat insère ligne + met à jour devices.last_seen_at
set local role postgres;
select results_eq(
    $$ select count(*) from public.device_heartbeats
        where device_id = '99999999-9999-9999-9999-999999999999' $$,
    $$ values (1::bigint) $$,
    'heartbeat row inserted'
);

select isnt(
    (select last_seen_at from public.devices where id = '99999999-9999-9999-9999-999999999999'),
    null,
    'devices.last_seen_at updated'
);

-- 3) record_playback insère ligne avec bon device_id
set local role authenticated;
set local "request.jwt.claims" to '{"sub":"99999999-9999-9999-9999-999999999999","role":"authenticated","is_device":true,"establishment_id":"11111111-1111-1111-1111-111111111111"}';
select public.record_playback('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid, 12);

set local role postgres;
select results_eq(
    $$ select count(*) from public.playback_logs
        where device_id = '99999999-9999-9999-9999-999999999999'
        and media_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
        and duration_played_sec = 12 $$,
    $$ values (1::bigint) $$,
    'playback log inserted with correct fields'
);

-- 3b) Second play in the same hour aggregates into the same row: cumulative
-- duration + incremented play_count, still exactly one row.
set local role authenticated;
set local "request.jwt.claims" to '{"sub":"99999999-9999-9999-9999-999999999999","role":"authenticated","is_device":true,"establishment_id":"11111111-1111-1111-1111-111111111111"}';
select public.record_playback('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid, 8);

set local role postgres;
select results_eq(
    $$ select count(*), max(duration_played_sec), max(play_count)
         from public.playback_logs
        where device_id = '99999999-9999-9999-9999-999999999999'
          and media_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' $$,
    $$ values (1::bigint, 20, 2) $$,
    'second play aggregates: one row, duration 12+8=20, play_count 2'
);

-- 4) Manager voit les heartbeats de son établissement
set local role authenticated;
set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-000000000002","role":"authenticated"}';
select results_eq(
    $$ select count(*) from public.device_heartbeats $$,
    $$ values (1::bigint) $$,
    'manager sees heartbeats of his establishment devices'
);

select * from finish();

rollback;
