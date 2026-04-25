-- Helper: derive actor_type from JWT claims and admin role
create or replace function public.audit_actor_type()
returns text
language sql
stable
security definer
set search_path = public
as $$
    select case
        when coalesce(auth.jwt()->>'is_device', 'false')::boolean then 'device'
        when public.is_admin() then 'admin'
        when auth.uid() is not null then 'manager'
        else 'system'
    end;
$$;

-- Trigger 1: device_revoked
create or replace function public.tg_audit_device_revoked()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if new.revoked_at is not null
       and (old.revoked_at is null or old.revoked_at != new.revoked_at) then
        insert into public.audit_events (
            actor_id, actor_type, event_type, target_id, metadata
        ) values (
            auth.uid(),
            public.audit_actor_type(),
            'device_revoked',
            new.id,
            jsonb_build_object(
                'device_name', new.name,
                'establishment_id', new.establishment_id
            )
        );
    end if;
    return new;
end $$;

create trigger devices_audit_revoked
    after update of revoked_at on public.devices
    for each row execute function public.tg_audit_device_revoked();

-- Trigger 2: playlist_published (version incremented + published_at set)
create or replace function public.tg_audit_playlist_published()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if new.version > old.version and new.published_at is not null then
        insert into public.audit_events (
            actor_id, actor_type, event_type, target_id, metadata
        ) values (
            auth.uid(),
            public.audit_actor_type(),
            'playlist_published',
            new.id,
            jsonb_build_object(
                'playlist_name', new.name,
                'version', new.version,
                'establishment_id', new.establishment_id
            )
        );
    end if;
    return new;
end $$;

create trigger playlists_audit_published
    after update of version on public.playlists
    for each row execute function public.tg_audit_playlist_published();

-- Trigger 3: user_created (any new profile row insert)
create or replace function public.tg_audit_user_created()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    insert into public.audit_events (
        actor_id, actor_type, event_type, target_id, metadata
    ) values (
        auth.uid(),
        public.audit_actor_type(),
        'user_created',
        new.id,
        jsonb_build_object('role', new.role, 'full_name', new.full_name)
    );
    return new;
end $$;

create trigger profiles_audit_created
    after insert on public.profiles
    for each row execute function public.tg_audit_user_created();
