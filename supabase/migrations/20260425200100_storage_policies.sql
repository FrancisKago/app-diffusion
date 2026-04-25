-- Storage policies pour le bucket 'media'.
-- Le bucket est privé : tout accès passe par les policies sur storage.objects.

-- Helper : extraire establishment_id depuis le path (premier segment)
create or replace function public.media_path_establishment_id(path text)
returns uuid language sql immutable as $$
    select nullif(split_part(path, '/', 1), '')::uuid
$$;

-- Upload : admin partout, manager dans ses établissements
create policy media_storage_admin_insert on storage.objects
    for insert to authenticated
    with check (
        bucket_id = 'media' and public.is_admin()
    );

create policy media_storage_manager_insert on storage.objects
    for insert to authenticated
    with check (
        bucket_id = 'media'
        and exists (
            select 1 from public.establishment_managers em
            where em.establishment_id = public.media_path_establishment_id(name)
              and em.profile_id = auth.uid()
        )
    );

-- SELECT : admin + manager + device de l'établissement
create policy media_storage_admin_select on storage.objects
    for select to authenticated
    using (bucket_id = 'media' and public.is_admin());

create policy media_storage_manager_select on storage.objects
    for select to authenticated
    using (
        bucket_id = 'media'
        and exists (
            select 1 from public.establishment_managers em
            where em.establishment_id = public.media_path_establishment_id(name)
              and em.profile_id = auth.uid()
        )
    );

create policy media_storage_device_select on storage.objects
    for select to authenticated
    using (
        bucket_id = 'media'
        and coalesce(auth.jwt()->>'is_device', 'false')::boolean = true
        and public.media_path_establishment_id(name)::text = auth.jwt()->>'establishment_id'
    );

-- DELETE : admin + manager
create policy media_storage_admin_delete on storage.objects
    for delete to authenticated
    using (bucket_id = 'media' and public.is_admin());

create policy media_storage_manager_delete on storage.objects
    for delete to authenticated
    using (
        bucket_id = 'media'
        and exists (
            select 1 from public.establishment_managers em
            where em.establishment_id = public.media_path_establishment_id(name)
              and em.profile_id = auth.uid()
        )
    );
