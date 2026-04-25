alter table public.devices
    add column if not exists current_media_id uuid references public.media(id) on delete set null,
    add column if not exists sync_progress int not null default 0,
    add column if not exists playlist_version int not null default 0;
