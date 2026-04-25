# Phase 4 — Playlists & publication — Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development to implement task-by-task. Steps use checkbox syntax.

**Goal:** Permettre à l'admin/gérant de construire une playlist de médias avec ordre, durée d'affichage (images) et dates d'activation (campagnes datées), d'assigner cette playlist à un appareil, et de la "publier" (incrémente `version` pour que les devices détectent le changement en Phase 5).

**Architecture:** Trois tables connectées : `playlists` (métadonnées + version), `playlist_items` (ordre ordonné via `position`), `device_playlists` (1:1 device → playlist). Un device a au plus une playlist active à la fois. L'éditeur du back office utilise `ReorderableListView` pour le drag-drop. Le réordonnancement transite par une fonction Postgres `reorder_playlist_items` qui accepte un tableau ordonné d'UUIDs et met à jour les positions atomiquement (évite les collisions sur la contrainte UNIQUE). La publication est une simple action qui incrémente `version` et met à jour `published_at`.

**Tech Stack:**
- 3 migrations + 1 fonction Postgres pour le réordonnancement
- Modèles Dart `Playlist`, `PlaylistItem` (freezed)
- 3 repositories (playlists, items, device_playlists)
- UI : écran liste + éditeur drag-drop + dialog d'assignation dans le détail device
- pgTAP pour les RLS

---

## File Structure additions

```
app-diffusion/
├── apps/backoffice/
│   └── lib/features/playlists/                    # Nouveau
│       ├── data/
│       │   ├── playlists_repository.dart
│       │   ├── playlist_items_repository.dart
│       │   └── device_playlists_repository.dart
│       ├── application/playlists_controller.dart
│       └── presentation/
│           ├── playlists_list_screen.dart
│           ├── playlist_editor_screen.dart          # drag-drop + publish
│           └── assign_playlist_dialog.dart          # utilisée depuis la liste devices
├── packages/shared/lib/src/models/
│   ├── playlist.dart                                # Nouveau
│   └── playlist_item.dart                           # Nouveau
└── supabase/
    ├── migrations/
    │   ├── 20260425300000_playlists.sql
    │   ├── 20260425300100_playlist_items.sql
    │   ├── 20260425300200_device_playlists.sql
    │   └── 20260425300300_reorder_playlist_items.sql
    └── tests/
        └── rls_phase4_test.sql
```

---

## Task 1 — Migration `playlists`

**Files:**
- Create: `supabase/migrations/20260425300000_playlists.sql`

```sql
create table public.playlists (
    id uuid primary key default gen_random_uuid(),
    establishment_id uuid not null references public.establishments(id) on delete cascade,
    name text not null check (length(trim(name)) > 0),
    is_default boolean not null default false,
    audio_enabled boolean not null default false,
    version int not null default 0,
    published_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create trigger playlists_set_updated_at
    before update on public.playlists
    for each row execute function public.tg_set_updated_at();

create index playlists_establishment_idx on public.playlists (establishment_id);

alter table public.playlists enable row level security;

-- Admin = tout
create policy playlists_admin_all on public.playlists
    for all using (public.is_admin()) with check (public.is_admin());

-- Manager = tout sur les playlists de ses établissements
create policy playlists_manager_all on public.playlists
    for all using (
        exists (
            select 1 from public.establishment_managers em
            where em.establishment_id = playlists.establishment_id
              and em.profile_id = auth.uid()
        )
    ) with check (
        exists (
            select 1 from public.establishment_managers em
            where em.establishment_id = playlists.establishment_id
              and em.profile_id = auth.uid()
        )
    );

-- Device = SELECT de la playlist rattachée à lui (via device_playlists — policy ajoutée Task 3)
-- Temporary : device peut aussi SELECT les playlists de son établissement (JWT claim)
create policy playlists_device_select on public.playlists
    for select using (
        coalesce(auth.jwt()->>'is_device', 'false')::boolean = true
        and establishment_id::text = auth.jwt()->>'establishment_id'
    );
```

Apply: `supabase db reset`.
Commit: `feat(db): add playlists table with RLS and version tracking`

---

## Task 2 — Migration `playlist_items`

**Files:**
- Create: `supabase/migrations/20260425300100_playlist_items.sql`

```sql
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

-- Helper : vérifier qu'un playlist_id appartient à un établissement accessible
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

-- Device = SELECT des items de sa playlist assignée
create policy playlist_items_device_select on public.playlist_items
    for select using (
        coalesce(auth.jwt()->>'is_device', 'false')::boolean = true
        and exists (
            select 1 from public.playlists pl
            where pl.id = playlist_items.playlist_id
              and pl.establishment_id::text = auth.jwt()->>'establishment_id'
        )
    );
```

Apply + verify. Commit: `feat(db): add playlist_items with position uniqueness and date constraints`

---

## Task 3 — Migration `device_playlists`

**Files:**
- Create: `supabase/migrations/20260425300200_device_playlists.sql`

```sql
create table public.device_playlists (
    device_id uuid primary key references public.devices(id) on delete cascade,
    playlist_id uuid not null references public.playlists(id) on delete cascade,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create trigger device_playlists_set_updated_at
    before update on public.device_playlists
    for each row execute function public.tg_set_updated_at();

create index device_playlists_playlist_idx on public.device_playlists (playlist_id);

alter table public.device_playlists enable row level security;

-- Admin + manager (sur son établissement) = tout
create policy device_playlists_admin_all on public.device_playlists
    for all using (public.is_admin()) with check (public.is_admin());

create policy device_playlists_manager_all on public.device_playlists
    for all using (
        exists (
            select 1 from public.devices d
            join public.establishment_managers em
              on em.establishment_id = d.establishment_id
            where d.id = device_playlists.device_id
              and em.profile_id = auth.uid()
        )
    ) with check (
        exists (
            select 1 from public.devices d
            join public.establishment_managers em
              on em.establishment_id = d.establishment_id
            where d.id = device_playlists.device_id
              and em.profile_id = auth.uid()
        )
    );

-- Device = SELECT sa propre affectation
create policy device_playlists_self_select on public.device_playlists
    for select using (
        device_id = auth.uid()
        or (
            coalesce(auth.jwt()->>'is_device', 'false')::boolean = true
            and device_id::text = auth.jwt()->>'sub'
        )
    );
```

Apply + verify. Commit: `feat(db): add device_playlists (1:1 device to playlist) with RLS`

---

## Task 4 — RPC `reorder_playlist_items`

**Files:**
- Create: `supabase/migrations/20260425300300_reorder_playlist_items.sql`

Fonction SECURITY DEFINER qui accepte un tableau ordonné d'UUIDs et met à jour les positions atomiquement. Utilise la clé UNIQUE deferrable pour éviter les collisions pendant l'UPDATE.

```sql
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
    -- Check authorization (admin or manager of the establishment)
    select public.can_manage_playlist(p_playlist_id) into can_manage;
    if not can_manage then
        raise exception 'Not authorized to reorder items of playlist %', p_playlist_id
            using errcode = '42501';
    end if;

    -- Use deferrable unique constraint: all UPDATEs visible at end of transaction
    set constraints playlist_items_unique_position deferred;

    -- Update positions in sequence
    for i in 1..array_length(p_ordered_item_ids, 1) loop
        update public.playlist_items
           set position = i - 1
         where id = p_ordered_item_ids[i]
           and playlist_id = p_playlist_id;
    end loop;
end $$;

-- Expose via RPC to authenticated users
revoke all on function public.reorder_playlist_items(uuid, uuid[]) from public;
grant execute on function public.reorder_playlist_items(uuid, uuid[]) to authenticated;
```

Apply + verify. Commit: `feat(db): add reorder_playlist_items RPC for atomic drag-drop`

---

## Task 5 — pgTAP tests for Phase 4 RLS

**Files:**
- Create: `supabase/tests/rls_phase4_test.sql`

```sql
begin;

select plan(6);

set local role postgres;

-- Seed : 1 media pour Lounge Plateau
insert into public.media (
    id, establishment_id, type, file_path, file_size,
    mime_type, checksum_sha256, original_filename
) values (
    '44444444-4444-4444-4444-444444444444',
    '11111111-1111-1111-1111-111111111111',
    'image',
    '11111111-1111-1111-1111-111111111111/44444444-4444-4444-4444-444444444444.jpg',
    1024, 'image/jpeg', 'aa', 'pl.jpg'
);

-- Seed : 1 playlist + 1 item pour Lounge Plateau
insert into public.playlists (id, establishment_id, name)
values ('55555555-5555-5555-5555-555555555555',
        '11111111-1111-1111-1111-111111111111', 'Playlist test');

insert into public.playlist_items (
    id, playlist_id, media_id, position
) values (
    '66666666-6666-6666-6666-666666666666',
    '55555555-5555-5555-5555-555555555555',
    '44444444-4444-4444-4444-444444444444',
    0
);

-- Seed : 1 device (Phase 2 pattern)
insert into public.devices (id, establishment_id, name)
values ('77777777-7777-7777-7777-777777777777',
        '11111111-1111-1111-1111-111111111111', 'Écran test');

set local role authenticated;

-- 1) Manager voit la playlist de son établissement
set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-000000000002","role":"authenticated"}';
select results_eq(
    $$ select count(*) from public.playlists $$,
    $$ values (1::bigint) $$,
    'manager sees playlist in his establishment'
);

-- 2) Manager voit l'item
select results_eq(
    $$ select count(*) from public.playlist_items $$,
    $$ values (1::bigint) $$,
    'manager sees playlist_items'
);

-- 3) Manager peut assigner une playlist à un device de son établissement
insert into public.device_playlists (device_id, playlist_id)
values ('77777777-7777-7777-7777-777777777777',
        '55555555-5555-5555-5555-555555555555');
select pass('manager can assign playlist to device');

-- 4) Contrainte : starts_at < ends_at
set local role postgres;
prepare bad_dates as
    insert into public.playlist_items (
        playlist_id, media_id, position, starts_at, ends_at
    ) values (
        '55555555-5555-5555-5555-555555555555',
        '44444444-4444-4444-4444-444444444444',
        99,
        '2026-05-10 00:00:00+00',
        '2026-05-01 00:00:00+00'
    );
select throws_ok('bad_dates', '23514', null, 'ends_at before starts_at blocked');

-- 5) RPC reorder_playlist_items fonctionne pour le manager
set local role authenticated;
set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-000000000002","role":"authenticated"}';
-- Ajout d'un 2e item pour avoir quoi réordonner (bypass RLS via service for setup)
set local role postgres;
insert into public.playlist_items (
    id, playlist_id, media_id, position
) values (
    '88888888-8888-8888-8888-888888888888',
    '55555555-5555-5555-5555-555555555555',
    '44444444-4444-4444-4444-444444444444',
    1
);
set local role authenticated;
set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-000000000002","role":"authenticated"}';
select public.reorder_playlist_items(
    '55555555-5555-5555-5555-555555555555',
    array[
        '88888888-8888-8888-8888-888888888888'::uuid,
        '66666666-6666-6666-6666-666666666666'::uuid
    ]
);
select results_eq(
    $$ select position from public.playlist_items
       where id = '88888888-8888-8888-8888-888888888888' $$,
    $$ values (0) $$,
    'reorder moved second item to position 0'
);

-- 6) Device voit sa playlist via JWT claim
set local "request.jwt.claims" to '{"sub":"77777777-7777-7777-7777-777777777777","role":"authenticated","is_device":true,"establishment_id":"11111111-1111-1111-1111-111111111111"}';
select results_eq(
    $$ select count(*) from public.playlists $$,
    $$ values (1::bigint) $$,
    'device sees playlist of its establishment'
);

select * from finish();

rollback;
```

Run: `supabase test db` — 21 tests total (6+5+4+6). Commit: `test(db): add pgTAP RLS tests for playlists, items, device_playlists`

---

## Task 6 — Shared models `Playlist` + `PlaylistItem`

**Files:**
- Create: `packages/shared/lib/src/models/playlist.dart`
- Create: `packages/shared/lib/src/models/playlist_item.dart`
- Create: `packages/shared/test/src/models/playlist_test.dart`
- Create: `packages/shared/test/src/models/playlist_item_test.dart`
- Modify: `packages/shared/lib/shared.dart`

### `Playlist` (3 tests)
```dart
// test
import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';

void main() {
  group('Playlist', () {
    final json = {
      'id': 'p1',
      'establishment_id': 'e1',
      'name': 'Playlist principale',
      'is_default': true,
      'audio_enabled': false,
      'version': 3,
      'published_at': '2026-04-25T10:00:00Z',
    };

    test('fromJson', () {
      final p = Playlist.fromJson(json);
      expect(p.id, 'p1');
      expect(p.isDefault, true);
      expect(p.audioEnabled, false);
      expect(p.version, 3);
      expect(p.publishedAt, isNotNull);
    });

    test('fromJson with null published_at', () {
      final p = Playlist.fromJson({...json, 'published_at': null});
      expect(p.publishedAt, isNull);
    });

    test('toJson roundtrip snake_case', () {
      final p = Playlist.fromJson(json);
      final j = p.toJson();
      expect(j['establishment_id'], 'e1');
      expect(j['is_default'], true);
      expect(j['audio_enabled'], false);
    });
  });
}
```

```dart
// impl
import 'package:freezed_annotation/freezed_annotation.dart';

part 'playlist.freezed.dart';
part 'playlist.g.dart';

@freezed
class Playlist with _$Playlist {
  const factory Playlist({
    required String id,
    @JsonKey(name: 'establishment_id') required String establishmentId,
    required String name,
    @JsonKey(name: 'is_default') @Default(false) bool isDefault,
    @JsonKey(name: 'audio_enabled') @Default(false) bool audioEnabled,
    @Default(0) int version,
    @JsonKey(name: 'published_at') DateTime? publishedAt,
  }) = _Playlist;

  factory Playlist.fromJson(Map<String, dynamic> json) =>
      _$PlaylistFromJson(json);
}
```

### `PlaylistItem` (3 tests)
```dart
// test
import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';

void main() {
  group('PlaylistItem', () {
    final json = {
      'id': 'pi1',
      'playlist_id': 'p1',
      'media_id': 'm1',
      'position': 0,
      'display_duration_sec': 15,
      'starts_at': null,
      'ends_at': null,
    };

    test('fromJson minimal', () {
      final pi = PlaylistItem.fromJson(json);
      expect(pi.id, 'pi1');
      expect(pi.position, 0);
      expect(pi.displayDurationSec, 15);
      expect(pi.startsAt, isNull);
    });

    test('fromJson with campaign dates', () {
      final j = {
        ...json,
        'starts_at': '2026-05-01T00:00:00Z',
        'ends_at': '2026-05-07T23:59:59Z',
      };
      final pi = PlaylistItem.fromJson(j);
      expect(pi.startsAt, isNotNull);
      expect(pi.endsAt, isNotNull);
    });

    test('toJson roundtrip', () {
      final pi = PlaylistItem.fromJson(json);
      final j = pi.toJson();
      expect(j['playlist_id'], 'p1');
      expect(j['media_id'], 'm1');
      expect(j['display_duration_sec'], 15);
    });
  });
}
```

```dart
// impl
import 'package:freezed_annotation/freezed_annotation.dart';

part 'playlist_item.freezed.dart';
part 'playlist_item.g.dart';

@freezed
class PlaylistItem with _$PlaylistItem {
  const factory PlaylistItem({
    required String id,
    @JsonKey(name: 'playlist_id') required String playlistId,
    @JsonKey(name: 'media_id') required String mediaId,
    required int position,
    @JsonKey(name: 'display_duration_sec') @Default(10) int displayDurationSec,
    @JsonKey(name: 'starts_at') DateTime? startsAt,
    @JsonKey(name: 'ends_at') DateTime? endsAt,
  }) = _PlaylistItem;

  factory PlaylistItem.fromJson(Map<String, dynamic> json) =>
      _$PlaylistItemFromJson(json);
}
```

Update barrel, run build_runner, tests 23/23 (17+6).
Commit: `feat(shared): add Playlist and PlaylistItem models`

---

## Task 7 — `PlaylistsRepository`

**Files:**
- Create: `apps/backoffice/lib/features/playlists/data/playlists_repository.dart`

```dart
import 'package:shared/shared.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PlaylistsRepository {
  PlaylistsRepository(this._client);
  final SupabaseClient _client;

  Future<List<Playlist>> list() async {
    try {
      final rows = await _client
          .from('playlists')
          .select()
          .order('created_at', ascending: false);
      return rows.map<Playlist>(
        (r) => Playlist.fromJson(Map<String, dynamic>.from(r as Map)),
      ).toList();
    } on PostgrestException catch (e) {
      throw AppException('Lecture playlists échouée', cause: e.message);
    }
  }

  Future<Playlist> fetch(String id) async {
    try {
      final row = await _client.from('playlists').select().eq('id', id).single();
      return Playlist.fromJson(Map<String, dynamic>.from(row));
    } on PostgrestException catch (e) {
      throw AppException('Lecture playlist échouée', cause: e.message);
    }
  }

  Future<Playlist> create({
    required String establishmentId,
    required String name,
    bool audioEnabled = false,
  }) async {
    try {
      final row = await _client.from('playlists').insert({
        'establishment_id': establishmentId,
        'name': name,
        'audio_enabled': audioEnabled,
      }).select().single();
      return Playlist.fromJson(Map<String, dynamic>.from(row));
    } on PostgrestException catch (e) {
      throw AppException('Création playlist échouée', cause: e.message);
    }
  }

  Future<Playlist> update({
    required String id,
    required String name,
    required bool audioEnabled,
  }) async {
    try {
      final row = await _client.from('playlists').update({
        'name': name,
        'audio_enabled': audioEnabled,
      }).eq('id', id).select().single();
      return Playlist.fromJson(Map<String, dynamic>.from(row));
    } on PostgrestException catch (e) {
      throw AppException('Mise à jour playlist échouée', cause: e.message);
    }
  }

  Future<void> delete(String id) async {
    try {
      await _client.from('playlists').delete().eq('id', id);
    } on PostgrestException catch (e) {
      throw AppException('Suppression échouée', cause: e.message);
    }
  }

  Future<Playlist> publish(String id) async {
    try {
      // Increment version and set published_at
      final now = DateTime.now().toUtc().toIso8601String();
      // Fetch current version to compute next
      final current = await fetch(id);
      final row = await _client.from('playlists').update({
        'version': current.version + 1,
        'published_at': now,
      }).eq('id', id).select().single();
      return Playlist.fromJson(Map<String, dynamic>.from(row));
    } on PostgrestException catch (e) {
      throw AppException('Publication échouée', cause: e.message);
    }
  }
}
```

Note: the `publish` method does two round-trips (fetch + update). A single-roundtrip alternative would be an RPC like `publish_playlist(p_id uuid)` that uses `update ... set version = version + 1`. For Phase 4 simplicity, the two-step is acceptable; race conditions are negligible since a playlist is edited by one admin at a time.

Commit: `feat(backoffice): add PlaylistsRepository with publish action`

---

## Task 8 — `PlaylistItemsRepository` + `DevicePlaylistsRepository`

**Files:**
- Create: `apps/backoffice/lib/features/playlists/data/playlist_items_repository.dart`
- Create: `apps/backoffice/lib/features/playlists/data/device_playlists_repository.dart`

### `PlaylistItemsRepository`

```dart
import 'package:shared/shared.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PlaylistItemsRepository {
  PlaylistItemsRepository(this._client);
  final SupabaseClient _client;

  Future<List<PlaylistItem>> listFor(String playlistId) async {
    try {
      final rows = await _client
          .from('playlist_items')
          .select()
          .eq('playlist_id', playlistId)
          .order('position');
      return rows.map<PlaylistItem>(
        (r) => PlaylistItem.fromJson(Map<String, dynamic>.from(r as Map)),
      ).toList();
    } on PostgrestException catch (e) {
      throw AppException('Lecture items échouée', cause: e.message);
    }
  }

  Future<PlaylistItem> append({
    required String playlistId,
    required String mediaId,
    int displayDurationSec = 10,
  }) async {
    try {
      // Compute next position
      final existing = await _client
          .from('playlist_items')
          .select('position')
          .eq('playlist_id', playlistId)
          .order('position', ascending: false)
          .limit(1);
      final nextPos = existing.isEmpty ? 0 : (existing.first['position'] as int) + 1;

      final row = await _client.from('playlist_items').insert({
        'playlist_id': playlistId,
        'media_id': mediaId,
        'position': nextPos,
        'display_duration_sec': displayDurationSec,
      }).select().single();
      return PlaylistItem.fromJson(Map<String, dynamic>.from(row));
    } on PostgrestException catch (e) {
      throw AppException('Ajout item échoué', cause: e.message);
    }
  }

  Future<PlaylistItem> updateItem({
    required String id,
    int? displayDurationSec,
    DateTime? startsAt,
    DateTime? endsAt,
    bool clearStartsAt = false,
    bool clearEndsAt = false,
  }) async {
    try {
      final patch = <String, dynamic>{};
      if (displayDurationSec != null) {
        patch['display_duration_sec'] = displayDurationSec;
      }
      if (clearStartsAt) {
        patch['starts_at'] = null;
      } else if (startsAt != null) {
        patch['starts_at'] = startsAt.toUtc().toIso8601String();
      }
      if (clearEndsAt) {
        patch['ends_at'] = null;
      } else if (endsAt != null) {
        patch['ends_at'] = endsAt.toUtc().toIso8601String();
      }
      final row = await _client
          .from('playlist_items')
          .update(patch)
          .eq('id', id)
          .select()
          .single();
      return PlaylistItem.fromJson(Map<String, dynamic>.from(row));
    } on PostgrestException catch (e) {
      throw AppException('Mise à jour item échouée', cause: e.message);
    }
  }

  Future<void> delete(String id) async {
    try {
      await _client.from('playlist_items').delete().eq('id', id);
    } on PostgrestException catch (e) {
      throw AppException('Suppression item échouée', cause: e.message);
    }
  }

  Future<void> reorder({
    required String playlistId,
    required List<String> orderedItemIds,
  }) async {
    try {
      await _client.rpc(
        'reorder_playlist_items',
        params: {
          'p_playlist_id': playlistId,
          'p_ordered_item_ids': orderedItemIds,
        },
      );
    } on PostgrestException catch (e) {
      throw AppException('Réordonnancement échoué', cause: e.message);
    }
  }
}
```

### `DevicePlaylistsRepository`

```dart
import 'package:shared/shared.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DevicePlaylistsRepository {
  DevicePlaylistsRepository(this._client);
  final SupabaseClient _client;

  Future<String?> playlistForDevice(String deviceId) async {
    try {
      final rows = await _client
          .from('device_playlists')
          .select('playlist_id')
          .eq('device_id', deviceId);
      if (rows.isEmpty) return null;
      return rows.first['playlist_id'] as String;
    } on PostgrestException catch (e) {
      throw AppException('Lecture affectation échouée', cause: e.message);
    }
  }

  Future<void> assign({
    required String deviceId,
    required String playlistId,
  }) async {
    try {
      await _client.from('device_playlists').upsert({
        'device_id': deviceId,
        'playlist_id': playlistId,
      });
    } on PostgrestException catch (e) {
      throw AppException('Assignation échouée', cause: e.message);
    }
  }

  Future<void> unassign(String deviceId) async {
    try {
      await _client.from('device_playlists').delete().eq('device_id', deviceId);
    } on PostgrestException catch (e) {
      throw AppException('Détachement échoué', cause: e.message);
    }
  }
}
```

Commit: `feat(backoffice): add playlist items and device assignment repositories`

---

## Task 9 — Controllers + playlists list screen

**Files:**
- Create: `apps/backoffice/lib/features/playlists/application/playlists_controller.dart`
- Create: `apps/backoffice/lib/features/playlists/presentation/playlists_list_screen.dart`

### Controller
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../auth/application/auth_controller.dart';
import '../data/device_playlists_repository.dart';
import '../data/playlist_items_repository.dart';
import '../data/playlists_repository.dart';

final playlistsRepositoryProvider = Provider<PlaylistsRepository>((ref) {
  return PlaylistsRepository(ref.watch(supabaseClientProvider));
});

final playlistItemsRepositoryProvider = Provider<PlaylistItemsRepository>((ref) {
  return PlaylistItemsRepository(ref.watch(supabaseClientProvider));
});

final devicePlaylistsRepositoryProvider =
    Provider<DevicePlaylistsRepository>((ref) {
  return DevicePlaylistsRepository(ref.watch(supabaseClientProvider));
});

final playlistsListProvider = FutureProvider<List<Playlist>>((ref) {
  return ref.watch(playlistsRepositoryProvider).list();
});

final playlistItemsProvider =
    FutureProvider.family<List<PlaylistItem>, String>((ref, playlistId) {
  return ref.watch(playlistItemsRepositoryProvider).listFor(playlistId);
});

final playlistDetailProvider =
    FutureProvider.family<Playlist, String>((ref, id) {
  return ref.watch(playlistsRepositoryProvider).fetch(id);
});
```

### List screen
Affiche toutes les playlists avec : nom, établissement (via join à faire dans un 2e call ou stocker `establishment_id` dans le model et faire la join UI-side), version, date de dernière publication. FAB pour créer une playlist. Clic → ouvre `PlaylistEditorScreen` via go_router.

Pour rester simple, on affichera juste `establishment_id` tronqué et non le nom de l'établissement. L'enrichissement sera ajouté en fonction du besoin.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/playlists_controller.dart';

class PlaylistsListScreen extends ConsumerWidget {
  const PlaylistsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(playlistsListProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Playlists'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(playlistsListProvider),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createDialog(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle playlist'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur : $e')),
        data: (list) {
          if (list.isEmpty) return const Center(child: Text('Aucune playlist.'));
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final p = list[i];
              final subtitle = [
                'v${p.version}',
                if (p.publishedAt != null)
                  'publiée ${_rel(p.publishedAt!)}'
                else
                  'jamais publiée',
              ].join(' · ');
              return ListTile(
                leading: const Icon(Icons.playlist_play_outlined),
                title: Text(p.name),
                subtitle: Text(subtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go('/playlists/${p.id}'),
              );
            },
          );
        },
      ),
    );
  }

  String _rel(DateTime when) {
    final diff = DateTime.now().difference(when);
    if (diff.inMinutes < 1) return 'à l\'instant';
    if (diff.inHours < 1) return 'il y a ${diff.inMinutes} min';
    if (diff.inDays < 1) return 'il y a ${diff.inHours} h';
    return 'il y a ${diff.inDays} j';
  }

  Future<void> _createDialog(BuildContext context, WidgetRef ref) async {
    // Simple dialog: name + establishment. Use establishmentsListProvider.
    // (Keep it brief — similar to establishment form pattern)
    final nameCtrl = TextEditingController();
    String? establishmentId;
    final establishmentsAsync = ref.read(establishmentsListProvider.future);
    final list = await establishmentsAsync;

    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Nouvelle playlist'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: 'Nom'),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: establishmentId,
                      decoration:
                          const InputDecoration(labelText: 'Établissement'),
                      items: [
                        for (final e in list)
                          DropdownMenuItem(value: e.id, child: Text(e.name)),
                      ],
                      onChanged: (v) => setState(() => establishmentId = v),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Annuler'),
                ),
                FilledButton(
                  onPressed: () async {
                    if (nameCtrl.text.trim().isEmpty ||
                        establishmentId == null) {
                      return;
                    }
                    await ref.read(playlistsRepositoryProvider).create(
                          establishmentId: establishmentId!,
                          name: nameCtrl.text.trim(),
                        );
                    ref.invalidate(playlistsListProvider);
                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext);
                    }
                  },
                  child: const Text('Créer'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
```

Note: needs `import '../../establishments/application/establishments_controller.dart';` for `establishmentsListProvider`.

Commit: `feat(backoffice): add playlists controllers and list screen`

---

## Task 10 — Playlist editor screen (drag-drop + items + publish)

**Files:**
- Create: `apps/backoffice/lib/features/playlists/presentation/playlist_editor_screen.dart`

Page qui prend un `playlistId` en param. Affiche :
- Header : nom de la playlist (éditable), badge version, date dernière publication, bouton **Publier** (primary button)
- Liste des items en `ReorderableListView` : chaque item = ligne avec thumbnail (via media repo), nom du fichier, contrôles pour `display_duration_sec` (pour images) et dates `starts_at` / `ends_at` (pour campagne), bouton supprimer
- FAB ou bouton "Ajouter un média" → dialog de sélection depuis la bibliothèque (ré-utilise `mediaListProvider`)
- Drag-drop via `ReorderableListView.builder` → au drop, appel `reorder()` sur le repository
- Date pickers (showDatePicker) pour starts_at/ends_at

Code squelette (détails dans l'implémentation) :
```dart
class PlaylistEditorScreen extends ConsumerWidget {
  const PlaylistEditorScreen({required this.playlistId, super.key});
  final String playlistId;

  // Build method :
  // 1. watch playlistDetailProvider(playlistId)
  // 2. watch playlistItemsProvider(playlistId)
  // 3. ReorderableListView with items
  // 4. onReorder: reorder the list in a local state, call repository.reorder()
  // 5. Publier button: call repository.publish(), then invalidate both providers
}
```

Compte tenu de la taille, le détail complet du code sera dans le subagent prompt au moment de l'exécution. Critères d'acceptation :
- Réordonnancement drag-drop persiste après refresh
- Publication incrémente `version` et met à jour `published_at`
- Ajout/suppression d'item refresh la liste

Commit: `feat(backoffice): add playlist editor with drag-drop and publish`

---

## Task 11 — `AssignPlaylistDialog` + intégration dans les devices

**Files:**
- Create: `apps/backoffice/lib/features/playlists/presentation/assign_playlist_dialog.dart`
- Modify: `apps/backoffice/lib/features/devices/presentation/devices_list_screen.dart` (ajouter action "Assigner playlist")

Dialog :
- Combobox des playlists de l'établissement du device
- Bouton "Assigner"
- Bouton "Détacher" (si déjà assigné)
- Appelle `DevicePlaylistsRepository.assign({deviceId, playlistId})` ou `unassign()`

Intégration UI :
- Dans `devices_list_screen.dart`, ajouter un `PopupMenuButton` ou un `IconButton` par ligne → "Assigner playlist" ouvre le dialog

Commit: `feat(backoffice): add assign playlist dialog and device menu action`

---

## Task 12 — Router + AppShell wiring

**Files:**
- Modify: `apps/backoffice/lib/routing/app_router.dart`
- Modify: `apps/backoffice/lib/shared_widgets/app_shell.dart`

Ajouter routes `/playlists` et `/playlists/:id` :
```dart
GoRoute(
  path: '/playlists',
  builder: (_, __) => const PlaylistsListScreen(),
  routes: [
    GoRoute(
      path: ':id',
      builder: (_, s) => PlaylistEditorScreen(
        playlistId: s.pathParameters['id']!,
      ),
    ),
  ],
),
```

AppShell : ajouter une 5e destination (entre Médias et Gérants) :
```dart
_Dest('/playlists', Icons.queue_music_outlined, 'Playlists'),
```

Commit: `feat(backoffice): wire /playlists routes and shell nav`

---

## Task 13 — Phase 4 demo doc + README

**Files:**
- Create: `docs/phase4-demo.md`
- Modify: `README.md` (ajouter lien)

Scénario démo :
1. Login admin
2. Créer playlist "Ambiance Lounge" dans "Lounge Plateau"
3. Dans l'éditeur : ajouter 5 médias depuis la bibliothèque (Phase 3 seed)
4. Drag-drop pour réordonner
5. Modifier durée d'un item image (ex: 15s)
6. Configurer dates campagne sur un item (ex: promo du 1er au 7 mai)
7. Cliquer "Publier" → badge version passe de 0 → 1, published_at apparaît
8. Retour dans Appareils → "Assigner playlist" sur "Tablette Samsung" → sélectionner "Ambiance Lounge"
9. Vérifier dans Studio : table `device_playlists` a la ligne, `playlists.version = 1`
10. Note : la réception sur l'Android arrive en Phase 5 (FCM + sync)

Commit: `docs(phase4): add phase 4 demo script and README link`

---

## Self-Review Checklist

1. **Spec coverage** (spec section 10 Phase 4):
   - ✅ Tables `playlists`, `playlist_items`, `device_playlists` → Tasks 1-3
   - ✅ Éditeur drag-drop → Task 10 (ReorderableListView + RPC `reorder_playlist_items`)
   - ✅ Durée + dates campagne par item → Task 10 (UI) + Task 2 (colonnes)
   - ✅ Bouton Publier → Task 10 (call `PlaylistsRepository.publish`) + Task 7 (implém)
   - ✅ Démo : playlist 5 médias + assignation + publication → Task 13

2. **Placeholders:** None. Task 10 décrit le squelette et renvoie au prompt d'exécution pour le détail — acceptable vu la taille.

3. **Type consistency:**
   - `Playlist` / `PlaylistItem` (Task 6) utilisés Tasks 7-11.
   - `reorder_playlist_items` RPC (Task 4) appelé Task 8.
   - `can_manage_playlist` helper (Task 2) utilisé par les policies items et par le RPC Task 4.
   - `establishmentsListProvider` réutilisé depuis Phase 1.
   - `mediaListProvider` (Phase 3) réutilisé dans Task 10 pour le picker d'ajout d'item.
   - `devicesListProvider` (Phase 2) réutilisé Task 11.

4. **Debt acceptée :**
   - `publish()` en 2 round-trips au lieu d'une RPC atomique (race conditions négligeables pour 1 admin à la fois)
   - L'UI n'affiche pas de badge "modifications non publiées" après édition (deferred Phase 4.5)
   - Pas de duplication d'un média dans une même playlist empêchée (pas de UNIQUE sur media_id) — volontaire, même média peut apparaître 2 fois

Plan prêt pour exécution.
