create table public.playlists (
    id uuid primary key default gen_random_uuid(),
    establishment_id uuid not null references public.establishments(id) on delete cascade,
    name text not null check (length(trim(name)) > 0),
    is_default boolean not null default false,
    audio_enabled boolean not null default false,
    version int not null default 0,
    published_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create trigger playlists_set_updated_at
    before update on public.playlists
    for each row execute function public.tg_set_updated_at();

create index playlists_establishment_idx on public.playlists (establishment_id);

alter table public.playlists enable row level security;

create policy playlists_admin_all on public.playlists
    for all using (public.is_admin()) with check (public.is_admin());

create policy playlists_manager_all on public.playlists
    for all using (
        exists (
            select 1 from public.establishment_managers em
            where em.establishment_id = playlists.establishment_id
              and em.profile_id = auth.uid()
        )
    ) with check (
        exists (
            select 1 from public.establishment_managers em
            where em.establishment_id = playlists.establishment_id
              and em.profile_id = auth.uid()
        )
    );

create policy playlists_device_select on public.playlists
    for select using (
        coalesce(auth.jwt()->>'is_device', 'false')::boolean = true
        and establishment_id::text = auth.jwt()->>'establishment_id'
    );
