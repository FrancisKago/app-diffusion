-- playback_logs.media_id had `on delete set null`. A heavily-played media
-- accumulates hundreds of thousands of log rows, so deleting it forced a
-- synchronous update of every referencing log within the delete's top-level
-- statement — which blows the 8s statement_timeout (57014). The timeout is
-- armed when the outer statement starts, so it cannot be lifted from inside a
-- function.
--
-- Drop the FK: a media delete now touches only the single media row (instant,
-- independent of log volume). playback_logs keep their historical media_id
-- value — which is actually preferable for proof-of-diffusion reporting than
-- nulling it. The FK on playlist_items.media_id (on delete restrict) is
-- untouched, so a media still in a playlist remains protected from deletion.
alter table public.playback_logs
    drop constraint if exists playback_logs_media_id_fkey;
