-- Deleting a media row fans out to `on delete set null` on
-- public.playback_logs.media_id. A heavily-played media can have hundreds of
-- thousands of log rows (265k+ observed), so the synchronous cascade update
-- exceeds the 8s statement_timeout and the delete fails with 57014
-- ("canceling statement due to statement timeout").
--
-- This admin-only RPC runs the delete with the statement timeout disabled so
-- the cascade can finish, regardless of how much playback history exists. The
-- FK (and thus PostgREST's media embed on playback_logs) is preserved.
create or replace function public.admin_delete_media(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    if not public.is_admin() then
        raise exception 'Admin role required' using errcode = '42501';
    end if;

    -- Let the on-delete-set-null cascade over playback_logs run to completion.
    set local statement_timeout = 0;

    delete from public.media where id = p_id;
end $$;

revoke all on function public.admin_delete_media(uuid) from public;
grant execute on function public.admin_delete_media(uuid) to authenticated;
