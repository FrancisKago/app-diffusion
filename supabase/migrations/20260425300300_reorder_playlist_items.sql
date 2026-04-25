create or replace function public.reorder_playlist_items(
    p_playlist_id uuid,
    p_ordered_item_ids uuid[]
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    can_manage boolean;
begin
    select public.can_manage_playlist(p_playlist_id) into can_manage;
    if not can_manage then
        raise exception 'Not authorized to reorder items of playlist %', p_playlist_id
            using errcode = '42501';
    end if;

    set constraints playlist_items_unique_position deferred;

    for i in 1..array_length(p_ordered_item_ids, 1) loop
        update public.playlist_items
           set position = i - 1
         where id = p_ordered_item_ids[i]
           and playlist_id = p_playlist_id;
    end loop;
end $$;

revoke all on function public.reorder_playlist_items(uuid, uuid[]) from public;
grant execute on function public.reorder_playlist_items(uuid, uuid[]) to authenticated;
