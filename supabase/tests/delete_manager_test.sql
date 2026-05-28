-- Verifies the DB cascade the `delete-manager` Edge Function relies on:
-- deleting an auth.users row removes the public.profiles row and, in turn,
-- every public.establishment_managers link for that manager.
begin;

select plan(3);

set local role postgres;

-- Seed a throwaway manager attached to two establishments.
insert into auth.users (
    id, instance_id, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, aud, role,
    created_at, updated_at,
    confirmation_token, recovery_token, email_change_token_new,
    email_change, email_change_token_current, phone_change,
    phone_change_token, reauthentication_token
) values (
    '00000000-0000-0000-0000-0000000000de',
    '00000000-0000-0000-0000-000000000000',
    'delete-me@local.test',
    crypt('Test1234!', gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}',
    '{"full_name":"Delete Me"}',
    'authenticated', 'authenticated',
    now(), now(),
    '', '', '', '', '', '', '', ''
);

update public.profiles set full_name = 'Delete Me', role = 'manager'
 where id = '00000000-0000-0000-0000-0000000000de';

insert into public.establishments (id, name, timezone) values
    ('33333333-3333-3333-3333-333333333333', 'Resto Sud', 'UTC')
on conflict (id) do nothing;

insert into public.establishment_managers (establishment_id, profile_id) values
    ('11111111-1111-1111-1111-111111111111',
     '00000000-0000-0000-0000-0000000000de'),
    ('33333333-3333-3333-3333-333333333333',
     '00000000-0000-0000-0000-0000000000de');

-- Sanity: links exist before deletion.
select results_eq(
    $$ select count(*) from public.establishment_managers
        where profile_id = '00000000-0000-0000-0000-0000000000de' $$,
    $$ values (2::bigint) $$,
    'manager has 2 establishment links before deletion'
);

-- Act: delete the auth user (what the Edge Function does via service role).
delete from auth.users where id = '00000000-0000-0000-0000-0000000000de';

-- 1) Profile cascade-deleted.
select results_eq(
    $$ select count(*) from public.profiles
        where id = '00000000-0000-0000-0000-0000000000de' $$,
    $$ values (0::bigint) $$,
    'delete auth user cascades profile'
);

-- 2) Establishment links cascade-deleted.
select results_eq(
    $$ select count(*) from public.establishment_managers
        where profile_id = '00000000-0000-0000-0000-0000000000de' $$,
    $$ values (0::bigint) $$,
    'delete profile cascades establishment_managers links'
);

select * from finish();

rollback;
