-- Profil applicatif lié à auth.users Supabase.
-- Créé automatiquement à l'inscription via trigger on_auth_user_created.

create type user_role as enum ('admin', 'manager');

create table public.profiles (
    id uuid primary key references auth.users(id) on delete cascade,
    role user_role not null default 'manager',
    full_name text not null default '',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

-- Trigger updated_at
create or replace function public.tg_set_updated_at()
returns trigger language plpgsql as $$
begin
    new.updated_at = now();
    return new;
end $$;

create trigger profiles_set_updated_at
    before update on public.profiles
    for each row execute function public.tg_set_updated_at();

-- Auto-create profile on signup (rôle par défaut: manager).
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
    insert into public.profiles (id, full_name)
    values (new.id, coalesce(new.raw_user_meta_data->>'full_name', ''));
    return new;
end $$;

create trigger on_auth_user_created
    after insert on auth.users
    for each row execute function public.handle_new_user();

-- Helper : l'utilisateur courant est-il admin ?
-- SECURITY DEFINER pour éviter la récursion infinie sur les policies de profiles.
create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
    select exists (
        select 1 from public.profiles p
        where p.id = auth.uid() and p.role = 'admin'
    );
$$;

-- RLS
alter table public.profiles enable row level security;

create policy profiles_self_select on public.profiles
    for select using (id = auth.uid());

create policy profiles_admin_select on public.profiles
    for select using (public.is_admin());

create policy profiles_admin_write on public.profiles
    for all using (public.is_admin()) with check (public.is_admin());
