create table public.playlist_items (
    id uuid primary key default gen_random_uuid(),
    playlist_id uuid not null references public.playlists(id) on delete cascade,
    media_id uuid not null references public.media(id) on delete restrict,
    position int not null check (position >= 0),
    display_duration_sec int not null default 10 check (display_duration_sec > 0),
    starts_at timestamptz,
    ends_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint playlist_items_unique_position unique (playlist_id, position) deferrable initially deferred,
    constraint playlist_items_dates_order
      check (starts_at is null or ends_at is null or starts_at < ends_at)
);

create trigger playlist_items_set_updated_at
    before update on public.playlist_items
    for each row execute function public.tg_set_updated_at();

create index playlist_items_playlist_idx on public.playlist_items (playlist_id, position);
create index playlist_items_media_idx on public.playlist_items (media_id);

alter table public.playlist_items enable row level security;

create or replace function public.can_manage_playlist(p_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
    select public.is_admin() or exists (
        select 1 from public.playlists pl
        join public.establishment_managers em
          on em.establishment_id = pl.establishment_id
        where pl.id = p_id and em.profile_id = auth.uid()
    )
$$;

create policy playlist_items_rw on public.playlist_items
    for all using (public.can_manage_playlist(playlist_id))
    with check (public.can_manage_playlist(playlist_id));

create policy playlist_items_device_select on public.playlist_items
    for select using (
        coalesce(auth.jwt()->>'is_device', 'false')::boolean = true
        and exists (
            select 1 from public.playlists pl
            where pl.id = playlist_items.playlist_id
              and pl.establishment_id::text = auth.jwt()->>'establishment_id'
        )
    );
