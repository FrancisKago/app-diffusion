-- Crée le bucket 'media' si absent. Idempotent.
-- Le bucket est aussi déclaré dans supabase/config.toml ([storage.buckets.media])
-- mais la CLI ne le synchronise pas systématiquement en DB après `supabase db reset` ;
-- cette migration garantit sa présence en dev comme en prod (`supabase db push`).
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
    'media',
    'media',
    false,
    104857600, -- 100 MiB, aligné avec config.toml
    array['video/mp4', 'image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do nothing;
