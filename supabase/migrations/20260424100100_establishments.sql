create table public.establishments (
    id uuid primary key default gen_random_uuid(),
    name text not null,
    timezone text not null default 'UTC',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint establishments_name_not_empty check (length(trim(name)) > 0)
);

create trigger establishments_set_updated_at
    before update on public.establishments
    for each row execute function public.tg_set_updated_at();

alter table public.establishments enable row level security;

-- Admin = tout (is_admin() est défini dans la migration profiles)
create policy establishments_admin_all on public.establishments
    for all using (public.is_admin()) with check (public.is_admin());

-- La policy SELECT pour les gérants est ajoutée dans la migration suivante
-- (dépend de establishment_managers).
