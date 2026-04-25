create table public.device_playlists (
    device_id uuid primary key references public.devices(id) on delete cascade,
    playlist_id uuid not null references public.playlists(id) on delete cascade,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create trigger device_playlists_set_updated_at
    before update on public.device_playlists
    for each row execute function public.tg_set_updated_at();

create index device_playlists_playlist_idx on public.device_playlists (playlist_id);

alter table public.device_playlists enable row level security;

create policy device_playlists_admin_all on public.device_playlists
    for all using (public.is_admin()) with check (public.is_admin());

create policy device_playlists_manager_all on public.device_playlists
    for all using (
        exists (
            select 1 from public.devices d
            join public.establishment_managers em
              on em.establishment_id = d.establishment_id
            where d.id = device_playlists.device_id
              and em.profile_id = auth.uid()
        )
    ) with check (
        exists (
            select 1 from public.devices d
            join public.establishment_managers em
              on em.establishment_id = d.establishment_id
            where d.id = device_playlists.device_id
              and em.profile_id = auth.uid()
        )
    );

create policy device_playlists_self_select on public.device_playlists
    for select using (
        device_id = auth.uid()
        or (
            coalesce(auth.jwt()->>'is_device', 'false')::boolean = true
            and device_id::text = auth.jwt()->>'sub'
        )
    );
