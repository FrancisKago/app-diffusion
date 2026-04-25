begin;

select plan(8);

set local role postgres;

-- Seed: 2nd establishment with its own manager
insert into auth.users (
    id, instance_id, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, aud, role,
    created_at, updated_at,
    confirmation_token, recovery_token, email_change_token_new,
    email_change, email_change_token_current, phone_change,
    phone_change_token, reauthentication_token
) values (
    '00000000-0000-0000-0000-000000000003',
    '00000000-0000-0000-0000-000000000000',
    'manager2@local.test',
    crypt('Test1234!', gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}',
    '{"full_name":"Manager 2"}',
    'authenticated', 'authenticated',
    now(), now(),
    '', '', '', '', '', '', '', ''
);

update public.profiles set full_name = 'Manager 2'
 where id = '00000000-0000-0000-0000-000000000003';

insert into public.establishments (id, name, timezone) values
    ('22222222-2222-2222-2222-222222222222', 'Resto Centre', 'UTC');

insert into public.establishment_managers (establishment_id, profile_id) values
    ('22222222-2222-2222-2222-222222222222',
     '00000000-0000-0000-0000-000000000003');

-- Seed: 1 device + 1 playlist for Lounge Plateau (used by isolation tests)
insert into public.devices (id, establishment_id, name)
values ('aaaaaaaa-1111-1111-1111-aaaaaaaaaaaa',
        '11111111-1111-1111-1111-111111111111',
        'Lounge device A');

insert into public.playlists (id, establishment_id, name)
values ('bbbbbbbb-1111-1111-1111-bbbbbbbbbbbb',
        '11111111-1111-1111-1111-111111111111', 'Lounge playlist');

-- 1) Manager non-rattaché à Lounge ne voit aucun device de Lounge
set local role authenticated;
set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-000000000003","role":"authenticated"}';
select results_eq(
    $$ select count(*) from public.devices where establishment_id = '11111111-1111-1111-1111-111111111111' $$,
    $$ values (0::bigint) $$,
    'manager 2 cannot see Lounge devices'
);

-- 2) Manager non-rattaché ne voit aucune playlist de Lounge
select results_eq(
    $$ select count(*) from public.playlists where establishment_id = '11111111-1111-1111-1111-111111111111' $$,
    $$ values (0::bigint) $$,
    'manager 2 cannot see Lounge playlists'
);

-- 3) Audit_events admin-only : un manager ne voit RIEN
set local role postgres;
insert into public.audit_events (actor_type, event_type, target_id, metadata)
values ('system', 'test_event', null, '{}'::jsonb);

set local role authenticated;
set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-000000000002","role":"authenticated"}';
select results_eq(
    $$ select count(*) from public.audit_events $$,
    $$ values (0::bigint) $$,
    'manager cannot see audit events'
);

-- 4) Admin voit les audit_events
set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}';
select cmp_ok(
    (select count(*) from public.audit_events),
    '>=',
    1::bigint,
    'admin can see audit events'
);

-- 5) Trigger device_revoked émet un audit event
set local role postgres;
update public.devices set revoked_at = now()
 where id = 'aaaaaaaa-1111-1111-1111-aaaaaaaaaaaa';
select cmp_ok(
    (select count(*) from public.audit_events
       where event_type = 'device_revoked'
         and target_id = 'aaaaaaaa-1111-1111-1111-aaaaaaaaaaaa'),
    '>=',
    1::bigint,
    'device_revoked audit event emitted'
);

-- 6) Trigger playlist_published émet un audit event
update public.playlists
   set version = version + 1, published_at = now()
 where id = 'bbbbbbbb-1111-1111-1111-bbbbbbbbbbbb';
select cmp_ok(
    (select count(*) from public.audit_events
       where event_type = 'playlist_published'
         and target_id = 'bbbbbbbb-1111-1111-1111-bbbbbbbbbbbb'),
    '>=',
    1::bigint,
    'playlist_published audit event emitted'
);

-- 7) Cascade FK: delete device cascades to device_playlists
insert into public.device_playlists (device_id, playlist_id)
values ('aaaaaaaa-1111-1111-1111-aaaaaaaaaaaa',
        'bbbbbbbb-1111-1111-1111-bbbbbbbbbbbb');

delete from public.devices where id = 'aaaaaaaa-1111-1111-1111-aaaaaaaaaaaa';

select results_eq(
    $$ select count(*) from public.device_playlists
        where device_id = 'aaaaaaaa-1111-1111-1111-aaaaaaaaaaaa' $$,
    $$ values (0::bigint) $$,
    'delete device cascades device_playlists'
);

-- 8) Profile RLS: manager voit seulement son propre profile
set local role authenticated;
set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-000000000002","role":"authenticated"}';
select results_eq(
    $$ select count(*) from public.profiles $$,
    $$ values (1::bigint) $$,
    'manager sees only his own profile'
);

select * from finish();

rollback;
