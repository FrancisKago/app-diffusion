begin;

select plan(4);

set local role postgres;
insert into public.media (
    id, establishment_id, type, file_path, file_size,
    mime_type, checksum_sha256, original_filename
) values (
    '33333333-3333-3333-3333-333333333333',
    '11111111-1111-1111-1111-111111111111',
    'image',
    '11111111-1111-1111-1111-111111111111/33333333-3333-3333-3333-333333333333.jpg',
    1024,
    'image/jpeg',
    'abc123',
    'test.jpg'
);
set local role authenticated;

-- 1) Manager voit le media de son établissement
set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-000000000002","role":"authenticated"}';
select results_eq(
    $$ select count(*) from public.media $$,
    $$ values (1::bigint) $$,
    'manager sees media in his establishment'
);

-- 2) Admin voit aussi
set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}';
select results_eq(
    $$ select count(*) from public.media $$,
    $$ values (1::bigint) $$,
    'admin sees media'
);

-- 3) Contrainte taille : video > 100MB rejetée
set local role postgres;
prepare oversized_video as
    insert into public.media (establishment_id, type, file_path, file_size,
                              mime_type, checksum_sha256, original_filename)
    values ('11111111-1111-1111-1111-111111111111', 'video',
            '11111111-1111-1111-1111-111111111111/x.mp4',
            200 * 1024 * 1024, 'video/mp4', 'def', 'big.mp4');
select throws_ok('oversized_video', '23514', null, 'video > 100MB blocked');

-- 4) Helper media_path_establishment_id extrait correctement
select is(
    public.media_path_establishment_id('11111111-1111-1111-1111-111111111111/abc.mp4'),
    '11111111-1111-1111-1111-111111111111'::uuid,
    'media_path_establishment_id extracts UUID prefix'
);

select * from finish();

rollback;
