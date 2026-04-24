-- Seed de développement local. NE PAS utiliser en prod.
--
-- Note: on force les champs token (confirmation_token, recovery_token, etc.)
-- à '' car GoTrue scanne ces colonnes en string non-nullable et échoue sur NULL.

-- Admin de dev : email admin@local.test / password AdminPass123!
insert into auth.users (
    id, instance_id, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, aud, role,
    created_at, updated_at,
    confirmation_token, recovery_token, email_change_token_new,
    email_change, email_change_token_current, phone_change,
    phone_change_token, reauthentication_token
) values (
    '00000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000000',
    'admin@local.test',
    crypt('AdminPass123!', gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}',
    '{"full_name":"Dev Admin"}',
    'authenticated', 'authenticated',
    now(), now(),
    '', '', '', '', '', '', '', ''
) on conflict (id) do nothing;

-- Forcer le rôle admin (trigger a créé un manager par défaut)
update public.profiles
   set role = 'admin', full_name = 'Dev Admin'
 where id = '00000000-0000-0000-0000-000000000001';

-- Gérant de dev
insert into auth.users (
    id, instance_id, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, aud, role,
    created_at, updated_at,
    confirmation_token, recovery_token, email_change_token_new,
    email_change, email_change_token_current, phone_change,
    phone_change_token, reauthentication_token
) values (
    '00000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000000',
    'manager@local.test',
    crypt('ManagerPass123!', gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}',
    '{"full_name":"Dev Manager"}',
    'authenticated', 'authenticated',
    now(), now(),
    '', '', '', '', '', '', '', ''
) on conflict (id) do nothing;

update public.profiles
   set full_name = 'Dev Manager'
 where id = '00000000-0000-0000-0000-000000000002';

-- Établissement de démo
insert into public.establishments (id, name, timezone) values
    ('11111111-1111-1111-1111-111111111111', 'Lounge Plateau', 'Africa/Yaounde')
on conflict (id) do nothing;

-- Rattacher le gérant
insert into public.establishment_managers (establishment_id, profile_id) values
    ('11111111-1111-1111-1111-111111111111',
     '00000000-0000-0000-0000-000000000002')
on conflict do nothing;
