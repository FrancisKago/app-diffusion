begin;

select plan(6);

set local role postgres;

insert into public.media (
    id, establishment_id, type, file_path, file_size,
    mime_type, checksum_sha256, original_filename
) values (
    '44444444-4444-4444-4444-444444444444',
    '11111111-1111-1111-1111-111111111111',
    'image',
    '11111111-1111-1111-1111-111111111111/44444444-4444-4444-4444-444444444444.jpg',
    1024, 'image/jpeg', 'aa', 'pl.jpg'
);

insert into public.playlists (id, establishment_id, name)
values ('55555555-5555-5555-5555-555555555555',
        '11111111-1111-1111-1111-111111111111', 'Playlist test');

insert into public.playlist_items (
    id, playlist_id, media_id, position
) values (
    '66666666-6666-6666-6666-666666666666',
    '55555555-5555-5555-5555-555555555555',
    '44444444-4444-4444-4444-444444444444',
    0
);

insert into public.devices (id, establishment_id, name)
values ('77777777-7777-7777-7777-777777777777',
        '11111111-1111-1111-1111-111111111111', 'Écran test');

set local role authenticated;

-- 1) Manager voit la playlist
set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-000000000002","role":"authenticated"}';
select results_eq(
    $$ select count(*) from public.playlists $$,
    $$ values (1::bigint) $$,
    'manager sees playlist in his establishment'
);

-- 2) Manager voit l'item
select results_eq(
    $$ select count(*) from public.playlist_items $$,
    $$ values (1::bigint) $$,
    'manager sees playlist_items'
);

-- 3) Manager peut assigner une playlist au device
insert into public.device_playlists (device_id, playlist_id)
values ('77777777-7777-7777-7777-777777777777',
        '55555555-5555-5555-5555-555555555555');
select pass('manager can assign playlist to device');

-- 4) Contrainte : starts_at < ends_at
set local role postgres;
prepare bad_dates as
    insert into public.playlist_items (
        playlist_id, media_id, position, starts_at, ends_at
    ) values (
        '55555555-5555-5555-5555-555555555555',
        '44444444-4444-4444-4444-444444444444',
        99,
        '2026-05-10 00:00:00+00',
        '2026-05-01 00:00:00+00'
    );
select throws_ok('bad_dates', '23514', null, 'ends_at before starts_at blocked');

-- 5) RPC reorder_playlist_items fonctionne pour le manager
set local role postgres;
insert into public.playlist_items (
    id, playlist_id, media_id, position
) values (
    '88888888-8888-8888-8888-888888888888',
    '55555555-5555-5555-5555-555555555555',
    '44444444-4444-4444-4444-444444444444',
    1
);
set local role authenticated;
set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-000000000002","role":"authenticated"}';
select public.reorder_playlist_items(
    '55555555-5555-5555-5555-555555555555',
    array[
        '88888888-8888-8888-8888-888888888888'::uuid,
        '66666666-6666-6666-6666-666666666666'::uuid
    ]
);
select results_eq(
    $$ select position from public.playlist_items
       where id = '88888888-8888-8888-8888-888888888888' $$,
    $$ values (0) $$,
    'reorder moved second item to position 0'
);

-- 6) Device voit sa playlist via JWT claim
set local "request.jwt.claims" to '{"sub":"77777777-7777-7777-7777-777777777777","role":"authenticated","is_device":true,"establishment_id":"11111111-1111-1111-1111-111111111111"}';
select results_eq(
    $$ select count(*) from public.playlists $$,
    $$ values (1::bigint) $$,
    'device sees playlist of its establishment'
);

select * from finish();

rollback;
