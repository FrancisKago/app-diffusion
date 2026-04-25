create table public.audit_events (
    id bigserial primary key,
    actor_id uuid,
    actor_type text not null check (actor_type in ('admin', 'manager', 'device', 'system')),
    event_type text not null,
    target_id uuid,
    metadata jsonb,
    created_at timestamptz not null default now()
);

create index audit_events_created_idx on public.audit_events (created_at desc);
create index audit_events_event_type_idx on public.audit_events (event_type);
create index audit_events_actor_idx on public.audit_events (actor_id);

alter table public.audit_events enable row level security;

create policy audit_admin_select on public.audit_events
    for select using (public.is_admin());

-- INSERT only via SECURITY DEFINER triggers/functions (no client-side INSERT policy)
