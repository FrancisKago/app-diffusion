create type media_type as enum ('video', 'image');

create table public.media (
    id uuid primary key default gen_random_uuid(),
    establishment_id uuid not null references public.establishments(id) on delete cascade,
    owner_id uuid references public.profiles(id) on delete set null,
    type media_type not null,
    file_path text not null,
    file_size bigint not null check (file_size > 0),
    duration_sec int check (duration_sec is null or duration_sec > 0),
    width int,
    height int,
    mime_type text not null,
    checksum_sha256 text not null,
    original_filename text not null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint media_video_size_check
      check (type <> 'video' or file_size <= 100 * 1024 * 1024),
    constraint media_image_size_check
      check (type <> 'image' or file_size <= 10 * 1024 * 1024)
);

create trigger media_set_updated_at
    before update on public.media
    for each row execute function public.tg_set_updated_at();

create index media_establishment_idx on public.media (establishment_id);
create index media_checksum_idx on public.media (checksum_sha256);

alter table public.media enable row level security;

create policy media_admin_all on public.media
    for all using (public.is_admin()) with check (public.is_admin());

create policy media_manager_select on public.media
    for select using (
        exists (
            select 1 from public.establishment_managers em
            where em.establishment_id = media.establishment_id
              and em.profile_id = auth.uid()
        )
    );

create policy media_manager_insert on public.media
    for insert with check (
        exists (
            select 1 from public.establishment_managers em
            where em.establishment_id = media.establishment_id
              and em.profile_id = auth.uid()
        )
    );

create policy media_manager_delete on public.media
    for delete using (
        exists (
            select 1 from public.establishment_managers em
            where em.establishment_id = media.establishment_id
              and em.profile_id = auth.uid()
        )
    );

create policy media_device_select on public.media
    for select using (
        coalesce(auth.jwt()->>'is_device', 'false')::boolean = true
        and establishment_id::text = auth.jwt()->>'establishment_id'
    );
