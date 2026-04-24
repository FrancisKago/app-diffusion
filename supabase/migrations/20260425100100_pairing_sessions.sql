create type pairing_session_status as enum ('pending', 'claimed', 'expired');

create table public.pairing_sessions (
    id uuid primary key default gen_random_uuid(),
    code text not null,
    status pairing_session_status not null default 'pending',
    device_id uuid references public.devices(id) on delete set null,
    jwt text,
    expires_at timestamptz not null,
    claimed_at timestamptz,
    created_at timestamptz not null default now()
);

-- Unique code parmi les sessions pending uniquement
create unique index pairing_sessions_pending_code_idx
    on public.pairing_sessions (code)
    where status = 'pending';

create index pairing_sessions_device_idx on public.pairing_sessions (device_id);

alter table public.pairing_sessions enable row level security;

-- Les Edge Functions utilisent service_role -> bypass RLS
-- Cote client on restreint tout sauf SELECT pour admin (debug/audit)

create policy pairing_sessions_admin_select on public.pairing_sessions
    for select using (public.is_admin());

-- Aucune autre policy : INSERT/UPDATE/DELETE reserves au service_role
