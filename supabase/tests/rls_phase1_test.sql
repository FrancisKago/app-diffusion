begin;

select plan(6);

set local role authenticated;

-- 1) Un gérant ne peut PAS voir tous les profils (voit seulement le sien)
set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-000000000002","role":"authenticated"}';
select results_eq(
    $$ select count(*) from public.profiles $$,
    $$ values (1::bigint) $$,
    'manager sees only his own profile'
);

-- 2) Un gérant ne peut voir QUE son établissement
select results_eq(
    $$ select count(*) from public.establishments $$,
    $$ values (1::bigint) $$,
    'manager sees exactly one establishment'
);

-- 3) Un gérant ne peut PAS créer un établissement
prepare manager_insert as
    insert into public.establishments (name) values ('Forbidden');
select throws_ok('manager_insert', '42501', null, 'manager insert blocked');

-- 4) Admin voit tous les profils
set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}';
select results_eq(
    $$ select count(*) from public.profiles $$,
    $$ values (2::bigint) $$,
    'admin sees all profiles'
);

-- 5) Admin voit tous les établissements
select results_eq(
    $$ select count(*) from public.establishments $$,
    $$ values (1::bigint) $$,
    'admin sees all establishments'
);

-- 6) Admin peut créer un établissement
insert into public.establishments (name) values ('Test Admin Insert');
select pass('admin can create establishments');

select * from finish();

rollback;
