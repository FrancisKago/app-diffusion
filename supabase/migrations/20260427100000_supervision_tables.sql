create table public.device_heartbeats (
    id bigserial primary key,
    device_id uuid not null references public.devices(id) on delete cascade,
    received_at timestamptz not null default now(),
    battery int,
    storage_free_mb int,
    app_version text
);

create index device_heartbeats_device_idx
    on public.device_heartbeats (device_id, received_at desc);

alter table public.device_heartbeats enable row level security;

create policy heartbeats_admin_select on public.device_heartbeats
    for select using (public.is_admin());

create policy heartbeats_manager_select on public.device_heartbeats
    for select using (
        exists (
            select 1 from public.devices d
            join public.establishment_managers em
              on em.establishment_id = d.establishment_id
            where d.id = device_heartbeats.device_id
              and em.profile_id = auth.uid()
        )
    );

create table public.playback_logs (
    id bigserial primary key,
    device_id uuid not null references public.devices(id) on delete cascade,
    media_id uuid references public.media(id) on delete set null,
    played_at timestamptz not null default now(),
    duration_played_sec int not null check (duration_played_sec >= 0)
);

create index playback_logs_device_idx
    on public.playback_logs (device_id, played_at desc);

create index playback_logs_media_idx
    on public.playback_logs (media_id);

alter table public.playback_logs enable row level security;

create policy playback_logs_admin_select on public.playback_logs
    for select using (public.is_admin());

create policy playback_logs_manager_select on public.playback_logs
    for select using (
        exists (
            select 1 from public.devices d
            join public.establishment_managers em
              on em.establishment_id = d.establishment_id
            where d.id = playback_logs.device_id
              and em.profile_id = auth.uid()
        )
    );
