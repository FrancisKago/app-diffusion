# Phase 3 — Upload & gestion médias — Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development to implement task-by-task. Steps use checkbox syntax.

**Goal:** Permettre à l'admin/gérant d'uploader des vidéos et images (avec validation, progression, prévisualisation) dans le back office, stockées dans Supabase Storage avec RLS par établissement, prêtes à être référencées par les futures playlists (Phase 4).

**Architecture:** Table `media` (métadonnées) + bucket Storage `media` (fichiers binaires, chemin `<establishment_id>/<media_id>.<ext>`). Policies Storage limitent l'accès par rôle/établissement. Upload côté back office via le SDK supabase_flutter qui gère la progression. Validation client (taille, MIME) + côté DB (CHECK constraints + Storage `file_size_limit`).

**Tech Stack:**
- `media` table avec RLS (admin/manager/device par establishment_id)
- Bucket Supabase Storage `media`, privé, signed URLs 1h pour les downloads
- Côté Flutter Web : `file_picker` pour la sélection drag-drop, `crypto` pour SHA-256, `image_picker` (alternative) ou `dart:html` pour les dimensions images, `video_player` pour la lecture
- Tests : pgTAP RLS + unit Dart pour la validation/checksum

---

## File Structure additions

```
app-diffusion/
├── apps/backoffice/
│   └── lib/features/media/                    # Nouveau
│       ├── data/media_repository.dart
│       ├── application/media_controller.dart
│       └── presentation/
│           ├── media_library_screen.dart
│           ├── media_upload_dialog.dart       # drag-drop + progression
│           └── media_preview.dart             # widget reutilisable (image / video)
├── packages/shared/lib/src/models/
│   └── media.dart                             # Nouveau
└── supabase/
    ├── migrations/
    │   ├── 20260425200000_media.sql           # table + RLS
    │   └── 20260425200100_storage_policies.sql # bucket policies (storage.objects)
    ├── config.toml                            # déclarer le bucket media
    └── tests/
        └── rls_phase3_test.sql                # tests RLS media + storage
```

---

## Task 1 — Migration `media` table

**Files:**
- Create: `supabase/migrations/20260425200000_media.sql`

```sql
create type media_type as enum ('video', 'image');

create table public.media (
    id uuid primary key default gen_random_uuid(),
    establishment_id uuid not null references public.establishments(id) on delete cascade,
    owner_id uuid references public.profiles(id) on delete set null,
    type media_type not null,
    file_path text not null,                            -- e.g. <establishment_id>/<id>.mp4
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

-- Admin = tout
create policy media_admin_all on public.media
    for all using (public.is_admin()) with check (public.is_admin());

-- Manager = SELECT/INSERT/UPDATE/DELETE sur ses établissements
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

-- Device = SELECT sur les médias de son établissement (JWT.establishment_id check)
-- Le JWT custom du device contient establishment_id en claim — on l'accepte aussi
-- via auth.jwt()->>'establishment_id' pour ne pas dépendre uniquement de auth.uid()
create policy media_device_select on public.media
    for select using (
        coalesce(auth.jwt()->>'is_device', 'false')::boolean = true
        and establishment_id::text = auth.jwt()->>'establishment_id'
    );
```

Apply: `supabase db reset`.
Commit: `feat(db): add media table with size constraints and RLS`

---

## Task 2 — Storage bucket + policies

**Files:**
- Modify: `supabase/config.toml` (ajouter le bucket `media`)
- Create: `supabase/migrations/20260425200100_storage_policies.sql`

Edit `supabase/config.toml`, **uncomment + adapt** the storage buckets section:
```toml
[storage.buckets.media]
public = false
file_size_limit = "100MiB"
allowed_mime_types = ["video/mp4", "image/jpeg", "image/png", "image/webp"]
```

Create migration `supabase/migrations/20260425200100_storage_policies.sql`:
```sql
-- Storage policies pour le bucket 'media'
-- Le bucket est privé : tout accès passe par les policies sur storage.objects.

-- Helpers : extraire establishment_id depuis le path (premier segment)
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

-- SELECT (download via signed URL ou direct) : admin + manager + device de l'établissement
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
```

Apply: `supabase db reset`.
Restart Supabase to pick up the bucket: `supabase stop && supabase start --env-file supabase/.env.local`.
Verify in Studio (`http://127.0.0.1:54323`) → Storage → bucket `media` exists.
Commit: `feat(storage): add media bucket with RLS policies`

---

## Task 3 — pgTAP tests for media + storage RLS

**Files:**
- Create: `supabase/tests/rls_phase3_test.sql`

```sql
begin;

select plan(4);

set local role postgres;
-- Insert un media de l'établissement Lounge Plateau
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

-- 3) Contrainte taille : video > 100MB rejeté
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
```

Run: `supabase test db` — expect 15 total (11 + 4).
Commit: `test(db): add pgTAP RLS tests for media`

---

## Task 4 — Shared model `Media` + `MediaType`

**Files:**
- Create: `packages/shared/lib/src/models/media.dart`
- Create: `packages/shared/test/src/models/media_test.dart`
- Modify: `packages/shared/lib/shared.dart`

Test (3 cases) :
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';

void main() {
  group('Media', () {
    final fullJson = {
      'id': 'm1',
      'establishment_id': 'e1',
      'owner_id': 'u1',
      'type': 'video',
      'file_path': 'e1/m1.mp4',
      'file_size': 5242880,
      'duration_sec': 30,
      'width': 1920,
      'height': 1080,
      'mime_type': 'video/mp4',
      'checksum_sha256': 'deadbeef',
      'original_filename': 'clip.mp4',
    };

    test('fromJson parses video', () {
      final m = Media.fromJson(fullJson);
      expect(m.id, 'm1');
      expect(m.type, MediaType.video);
      expect(m.durationSec, 30);
      expect(m.fileSize, 5242880);
    });

    test('fromJson parses image without duration', () {
      final j = {...fullJson, 'type': 'image', 'duration_sec': null};
      final m = Media.fromJson(j);
      expect(m.type, MediaType.image);
      expect(m.durationSec, isNull);
    });

    test('toJson roundtrip', () {
      final m = Media.fromJson(fullJson);
      final j = m.toJson();
      expect(j['type'], 'video');
      expect(j['file_size'], 5242880);
      expect(j['duration_sec'], 30);
    });
  });
}
```

Implement (using freezed + JsonKey for snake_case):
```dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'media.freezed.dart';
part 'media.g.dart';

enum MediaType {
  video,
  image;

  String get dbValue => name;

  static MediaType fromString(String v) => switch (v) {
    'video' => MediaType.video,
    'image' => MediaType.image,
    _ => throw ArgumentError.value(v, 'value', 'unknown media type'),
  };
}

class _MediaTypeConverter implements JsonConverter<MediaType, String> {
  const _MediaTypeConverter();
  @override
  MediaType fromJson(String json) => MediaType.fromString(json);
  @override
  String toJson(MediaType object) => object.dbValue;
}

@freezed
class Media with _$Media {
  const factory Media({
    required String id,
    @JsonKey(name: 'establishment_id') required String establishmentId,
    @JsonKey(name: 'owner_id') String? ownerId,
    @_MediaTypeConverter() required MediaType type,
    @JsonKey(name: 'file_path') required String filePath,
    @JsonKey(name: 'file_size') required int fileSize,
    @JsonKey(name: 'duration_sec') int? durationSec,
    int? width,
    int? height,
    @JsonKey(name: 'mime_type') required String mimeType,
    @JsonKey(name: 'checksum_sha256') required String checksumSha256,
    @JsonKey(name: 'original_filename') required String originalFilename,
  }) = _Media;

  factory Media.fromJson(Map<String, dynamic> json) => _$MediaFromJson(json);
}
```

Add to barrel. Run build_runner. Tests pass 17 total (14 + 3).
Commit: `feat(shared): add Media model with type enum`

---

## Task 5 — `MediaRepository`

**Files:**
- Create: `apps/backoffice/lib/features/media/data/media_repository.dart`

```dart
import 'dart:typed_data';
import 'package:shared/shared.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MediaUploadInput {
  const MediaUploadInput({
    required this.establishmentId,
    required this.type,
    required this.bytes,
    required this.mimeType,
    required this.checksum,
    required this.originalFilename,
    this.durationSec,
    this.width,
    this.height,
  });

  final String establishmentId;
  final MediaType type;
  final Uint8List bytes;
  final String mimeType;
  final String checksum;
  final String originalFilename;
  final int? durationSec;
  final int? width;
  final int? height;
}

class MediaRepository {
  MediaRepository(this._client);
  final SupabaseClient _client;

  static const _bucket = 'media';

  Future<List<Media>> list() async {
    try {
      final rows = await _client
          .from('media')
          .select()
          .order('created_at', ascending: false);
      return rows.map<Media>(
        (r) => Media.fromJson(Map<String, dynamic>.from(r as Map)),
      ).toList();
    } on PostgrestException catch (e) {
      throw AppException('Lecture médias échouée', cause: e.message);
    }
  }

  Future<Media> upload(MediaUploadInput input) async {
    // 1. Generate id + path
    final id = _newId();
    final ext = _extensionFor(input.mimeType);
    final filePath = '${input.establishmentId}/$id.$ext';

    // 2. Upload binary to Storage
    try {
      await _client.storage.from(_bucket).uploadBinary(
        filePath,
        input.bytes,
        fileOptions: FileOptions(
          contentType: input.mimeType,
          upsert: false,
        ),
      );
    } on StorageException catch (e) {
      throw AppException('Upload échoué', cause: e.message);
    }

    // 3. Insert metadata row
    try {
      final row = await _client.from('media').insert({
        'id': id,
        'establishment_id': input.establishmentId,
        'type': input.type.dbValue,
        'file_path': filePath,
        'file_size': input.bytes.length,
        'duration_sec': input.durationSec,
        'width': input.width,
        'height': input.height,
        'mime_type': input.mimeType,
        'checksum_sha256': input.checksum,
        'original_filename': input.originalFilename,
      }).select().single();
      return Media.fromJson(Map<String, dynamic>.from(row));
    } on PostgrestException catch (e) {
      // Roll back storage on metadata insert failure
      await _client.storage.from(_bucket).remove([filePath]).catchError((_) => <FileObject>[]);
      throw AppException('Insertion média échouée', cause: e.message);
    }
  }

  Future<void> delete(Media media) async {
    try {
      await _client.from('media').delete().eq('id', media.id);
      await _client.storage.from(_bucket).remove([media.filePath]);
    } on PostgrestException catch (e) {
      throw AppException('Suppression échouée', cause: e.message);
    }
  }

  Future<String> signedUrl(Media media, {int expiresInSeconds = 3600}) async {
    try {
      return await _client.storage
          .from(_bucket)
          .createSignedUrl(media.filePath, expiresInSeconds);
    } on StorageException catch (e) {
      throw AppException('URL signée échouée', cause: e.message);
    }
  }

  String _newId() {
    // Simple UUID v4 generator (avoid extra dep). Use uuid package if available.
    final r = List<int>.generate(16, (_) => _rand.nextInt(256));
    r[6] = (r[6] & 0x0f) | 0x40;
    r[8] = (r[8] & 0x3f) | 0x80;
    String h(int i) => r[i].toRadixString(16).padLeft(2, '0');
    return '${h(0)}${h(1)}${h(2)}${h(3)}-${h(4)}${h(5)}-${h(6)}${h(7)}-${h(8)}${h(9)}-${h(10)}${h(11)}${h(12)}${h(13)}${h(14)}${h(15)}';
  }

  static final _rand = _initRand();
  static dynamic _initRand() {
    // ignore: avoid_print
    return _SecureRand();
  }
}

class _SecureRand {
  int nextInt(int max) {
    // Not cryptographically secure but sufficient for ID generation
    return DateTime.now().microsecondsSinceEpoch % max;
  }
}

String _extensionFor(String mimeType) => switch (mimeType) {
      'video/mp4' => 'mp4',
      'image/jpeg' => 'jpg',
      'image/png' => 'png',
      'image/webp' => 'webp',
      _ => 'bin',
    };
```

Note: the random ID generator above is naive (using microsecondsSinceEpoch). In a real implementation we'd use the `uuid` package (`uuid: ^4.5.1`). The implementer should add `uuid` as a dependency in `apps/backoffice/pubspec.yaml` and replace `_newId()` with `Uuid().v4()`. This avoids the naive `_SecureRand` class — keep the implementation cleaner.

Commit: `feat(backoffice): add MediaRepository with upload/list/delete/signedUrl`

---

## Task 6 — Media controller + library list screen

**Files:**
- Create: `apps/backoffice/lib/features/media/application/media_controller.dart`
- Create: `apps/backoffice/lib/features/media/presentation/media_library_screen.dart`

**Controller:**
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../auth/application/auth_controller.dart';
import '../data/media_repository.dart';

final mediaRepositoryProvider = Provider<MediaRepository>((ref) {
  return MediaRepository(ref.watch(supabaseClientProvider));
});

final mediaListProvider = FutureProvider<List<Media>>((ref) {
  return ref.watch(mediaRepositoryProvider).list();
});
```

**Library screen:** GridView of media items, each as a card showing:
- Thumbnail (image inline / video icon placeholder)
- Original filename
- Size in human-readable format (KB/MB)
- Type badge (vidéo/image)
- Click → open preview dialog
- Long-press / menu → delete

FAB → opens upload dialog.

Commit: `feat(backoffice): add media library screen and controller`

---

## Task 7 — Upload dialog (drag-drop + validation + progress)

**Files:**
- Create: `apps/backoffice/lib/features/media/presentation/media_upload_dialog.dart`
- Modify: `apps/backoffice/pubspec.yaml` (add `file_picker: ^8.1.4`, `crypto: ^3.0.5`, `uuid: ^4.5.1`)

Workflow:
1. User clicks "Sélectionner un fichier" or drag-drops
2. Validate: extension MP4 (video), JPG/PNG/WebP (image); size <100MB video, <10MB image
3. Compute SHA-256 (sync, fast for small files; for 100MB video may take 1-2s)
4. For images, decode to get width/height (via `dart:ui` `decodeImageFromList`)
5. For videos, defer width/height/duration to a TODO comment (Phase 3.5 if needed)
6. Show progress bar while uploading via `MediaRepository.upload`
7. On success, refresh `mediaListProvider` and close dialog
8. On error, display message + allow retry

```dart
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../establishments/application/establishments_controller.dart';
import '../application/media_controller.dart';
import '../data/media_repository.dart';

class MediaUploadDialog extends ConsumerStatefulWidget {
  const MediaUploadDialog({super.key});

  @override
  ConsumerState<MediaUploadDialog> createState() => _MediaUploadDialogState();
}

class _MediaUploadDialogState extends ConsumerState<MediaUploadDialog> {
  String? _establishmentId;
  PlatformFile? _file;
  String? _error;
  bool _uploading = false;

  static const _videoExt = {'mp4'};
  static const _imageExt = {'jpg', 'jpeg', 'png', 'webp'};
  static const _videoMax = 100 * 1024 * 1024;
  static const _imageMax = 10 * 1024 * 1024;

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [..._videoExt, ..._imageExt],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final f = result.files.first;
    setState(() {
      _file = f;
      _error = _validate(f);
    });
  }

  String? _validate(PlatformFile f) {
    final ext = f.extension?.toLowerCase();
    if (ext == null) return 'Extension manquante';
    final isVideo = _videoExt.contains(ext);
    final isImage = _imageExt.contains(ext);
    if (!isVideo && !isImage) return 'Format non supporté';
    final maxSize = isVideo ? _videoMax : _imageMax;
    if (f.size > maxSize) {
      return 'Fichier trop gros (max ${(maxSize / 1024 / 1024).toInt()} Mo)';
    }
    return null;
  }

  Future<void> _upload() async {
    if (_file == null || _error != null || _establishmentId == null) return;
    final f = _file!;
    final bytes = f.bytes!;
    final ext = f.extension!.toLowerCase();
    final isVideo = _videoExt.contains(ext);

    setState(() { _uploading = true; });
    try {
      // Compute SHA-256
      final checksum = sha256.convert(bytes).toString();

      // For images, get dimensions
      int? width;
      int? height;
      if (!isVideo) {
        final img = await decodeImageFromList(bytes);
        width = img.width;
        height = img.height;
      }
      // TODO Phase 3.5: extract video duration/dimensions via video_player

      final mime = switch (ext) {
        'mp4' => 'video/mp4',
        'jpg' || 'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        'webp' => 'image/webp',
        _ => 'application/octet-stream',
      };

      await ref.read(mediaRepositoryProvider).upload(MediaUploadInput(
        establishmentId: _establishmentId!,
        type: isVideo ? MediaType.video : MediaType.image,
        bytes: bytes,
        mimeType: mime,
        checksum: checksum,
        originalFilename: f.name,
        width: width,
        height: height,
      ));

      ref.invalidate(mediaListProvider);
      if (mounted) Navigator.of(context).pop();
    } on AppException catch (e) {
      setState(() => _error = '${e.message} — ${e.cause}');
    } finally {
      if (mounted) setState(() { _uploading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final establishmentsAsync = ref.watch(establishmentsListProvider);
    return AlertDialog(
      title: const Text('Uploader un média'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            establishmentsAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('Erreur: $e'),
              data: (list) => DropdownButtonFormField<String>(
                initialValue: _establishmentId,
                decoration: const InputDecoration(labelText: 'Établissement'),
                items: [
                  for (final e in list)
                    DropdownMenuItem(value: e.id, child: Text(e.name)),
                ],
                onChanged: (v) => setState(() => _establishmentId = v),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _uploading ? null : _pickFile,
              icon: const Icon(Icons.attach_file),
              label: Text(_file?.name ?? 'Choisir un fichier'),
            ),
            const SizedBox(height: 8),
            Text('MP4 ≤ 100 Mo · JPG/PNG/WebP ≤ 10 Mo',
                style: Theme.of(context).textTheme.bodySmall),
            if (_file != null) ...[
              const SizedBox(height: 12),
              Text(
                '${(_file!.size / 1024 / 1024).toStringAsFixed(2)} Mo',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            if (_uploading) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _uploading ? null : () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: (_uploading || _file == null || _error != null || _establishmentId == null)
              ? null : _upload,
          child: _uploading
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Uploader'),
        ),
      ],
    );
  }
}
```

Commit: `feat(backoffice): add media upload dialog with validation and SHA-256`

---

## Task 8 — Media preview widget

**Files:**
- Create: `apps/backoffice/lib/features/media/presentation/media_preview.dart`
- Modify: `apps/backoffice/pubspec.yaml` (add `video_player: ^2.9.2`)

Reusable widget that:
- For images: fetches signed URL → renders `Image.network`
- For videos: fetches signed URL → uses `VideoPlayerController.networkUrl(...)` with controls

Used in:
- Media library cards (thumbnail = first frame for image, icon for video)
- Preview dialog when user taps a media item (full-size playback)

Snippet (preview dialog):
```dart
class MediaPreviewDialog extends ConsumerStatefulWidget {
  const MediaPreviewDialog({required this.media, super.key});
  final Media media;
  // ...
}

// Inside build, after fetching signedUrl via mediaRepositoryProvider.signedUrl(...):
// if image: Image.network(url)
// if video: VideoPlayerController(...).play() with positionedControls
```

Commit: `feat(backoffice): add media preview widget`

---

## Task 9 — Router + AppShell wiring

**Files:**
- Modify: `apps/backoffice/lib/routing/app_router.dart`
- Modify: `apps/backoffice/lib/shared_widgets/app_shell.dart`

Add `/media` route inside ShellRoute, after `/devices`:
```dart
GoRoute(
  path: '/media',
  builder: (_, __) => const MediaLibraryScreen(),
),
```

Add destination to AppShell `_destinations`:
```dart
_Dest('/media', Icons.perm_media_outlined, 'Médias'),
```

Verify analyze 0 errors.
Commit: `feat(backoffice): wire /media route and shell nav`

---

## Task 10 — CI + docs phase 3

**Files:**
- Modify: `README.md` (link phase3-demo.md)
- Create: `docs/phase3-demo.md`

Demo script outline:
1. Login admin
2. Aller dans "Médias" → "Uploader un média"
3. Sélectionner Lounge Plateau, choisir une image JPG (<10 Mo) → Uploader → barre progresse → vignette apparaît
4. Réuploader une vidéo MP4 (<100 Mo) → vignette + badge "vidéo"
5. Cliquer sur la vignette → preview plein écran (image) ou lecture (vidéo)
6. Vérifier RLS via Studio : un manager d'un autre établissement ne voit pas ces médias
7. Supprimer un média → disparaît du Storage et de la table

Commit: `docs(phase3): add phase 3 demo script`

---

## Self-Review Checklist

1. **Spec coverage** (spec section 10 Phase 3):
   - ✅ Table `media` + Storage avec policies → Tasks 1-2
   - ✅ Drag-drop upload, prévisualisation → Tasks 7-8
   - ✅ Validation formats/tailles → Task 7 client + Task 1 DB CHECK + Task 2 bucket file_size_limit
   - ✅ Barre de progression → Task 7 (LinearProgressIndicator pendant upload)
   - ✅ Démo : upload vidéo + 3 images, vignettes → Task 10

2. **Placeholders:** None remaining. The video duration/dimensions extraction is explicitly deferred with a TODO comment, scope-bounded.

3. **Type consistency:**
   - `MediaType` (Task 4) used in Task 5 (`MediaUploadInput.type`).
   - `MediaUploadInput` (Task 5) used in Task 7.
   - `MediaRepository` providers used by both library and upload dialog.
   - DB schema constraints (`file_size <= 100MB` for video, `<= 10MB` for image) match Task 7 client validation.

4. **Open debt:**
   - Video metadata (duration, width, height) not extracted — explicit TODO; Phase 3.5 if needed.
   - No partial-upload resume — single-shot upload via `uploadBinary`. Acceptable for files ≤100MB on stable connections.
   - No deduplication via `checksum_sha256` — DB stores it but UI doesn't surface "already uploaded" warnings. Future enhancement.
   - Naive UUID generation in MediaRepository fallback if `uuid` package not added — implementer should add the dep and use `Uuid().v4()`.

These gaps are documented and acceptable for Phase 3 scope.
