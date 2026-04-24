create type device_orientation as enum ('landscape', 'portrait');

create table public.devices (
    id uuid primary key default gen_random_uuid(),
    establishment_id uuid not null references public.establishments(id) on delete cascade,
    name text not null check (length(trim(name)) > 0),
    orientation device_orientation not null default 'landscape',
    fcm_token text,
    last_seen_at timestamptz,
    revoked_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create trigger devices_set_updated_at
    before update on public.devices
    for each row execute function public.tg_set_updated_at();

create index devices_establishment_idx on public.devices (establishment_id);

alter table public.devices enable row level security;

-- Admin = tout
create policy devices_admin_all on public.devices
    for all using (public.is_admin()) with check (public.is_admin());

-- Gérant = SELECT sur ses établissements
create policy devices_manager_select on public.devices
    for select using (
        exists (
            select 1 from public.establishment_managers em
            where em.establishment_id = devices.establishment_id
              and em.profile_id = auth.uid()
        )
    );

-- Device = SELECT sur sa propre ligne (JWT custom avec sub = device_id)
create policy devices_self_select on public.devices
    for select using (id = auth.uid());

-- Device = UPDATE limité à lui-même (heartbeats, Phase 6)
create policy devices_self_update_heartbeat on public.devices
    for update using (id = auth.uid())
    with check (id = auth.uid());
