create table public.establishment_managers (
    establishment_id uuid not null references public.establishments(id) on delete cascade,
    profile_id uuid not null references public.profiles(id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key (establishment_id, profile_id)
);

alter table public.establishment_managers enable row level security;

-- Admin = tout
create policy em_admin_all on public.establishment_managers
    for all using (public.is_admin()) with check (public.is_admin());

-- Un gérant peut lire ses propres affectations
create policy em_self_select on public.establishment_managers
    for select using (profile_id = auth.uid());

-- Policy SELECT pour establishments : gérant voit ses établissements
create policy establishments_manager_select on public.establishments
    for select using (
        exists (
            select 1 from public.establishment_managers em
            where em.establishment_id = public.establishments.id
              and em.profile_id = auth.uid()
        )
    );
