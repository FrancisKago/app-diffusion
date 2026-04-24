begin;

select plan(5);

set local role authenticated;

-- Seed un device pour les tests (en utilisant le service-level bypass via
-- l'absence de claims auth, on passe par le rôle postgres)
-- Note: ce INSERT va passer car on est pas encore "authenticated" avec un uid
set local role postgres;
insert into public.devices (id, establishment_id, name)
  values ('22222222-2222-2222-2222-222222222222',
          '11111111-1111-1111-1111-111111111111',
          'Écran terrasse');
set local role authenticated;

-- 1) Manager (du seed, rattaché à Lounge Plateau) voit le device
set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-000000000002","role":"authenticated"}';
select results_eq(
    $$ select count(*) from public.devices $$,
    $$ values (1::bigint) $$,
    'manager sees 1 device in his establishment'
);

-- 2) Manager ne peut PAS créer un device
prepare manager_insert_device as
    insert into public.devices (establishment_id, name)
    values ('11111111-1111-1111-1111-111111111111', 'Forbidden');
select throws_ok('manager_insert_device', '42501', null, 'manager device insert blocked');

-- 3) Admin voit tous les devices
set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}';
select results_eq(
    $$ select count(*) from public.devices $$,
    $$ values (1::bigint) $$,
    'admin sees all devices'
);

-- 4) Admin peut créer un device
insert into public.devices (establishment_id, name)
  values ('11111111-1111-1111-1111-111111111111', 'Test Admin Create');
select pass('admin can insert device');

-- 5) Manager NE voit PAS les pairing_sessions (seul admin a SELECT)
set local role postgres;
insert into public.pairing_sessions (code, expires_at)
  values ('123456', now() + interval '15 minutes');
set local role authenticated;
set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-000000000002","role":"authenticated"}';
select results_eq(
    $$ select count(*) from public.pairing_sessions $$,
    $$ values (0::bigint) $$,
    'manager cannot see pairing sessions'
);

select * from finish();

rollback;
