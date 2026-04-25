# Phase 6 — Supervision — Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development to implement task-by-task.

**Goal:** Donner à l'admin une vue temps-réel du parc d'appareils : qui est en ligne, qui joue quoi, % synchro, historique des heartbeats et des lectures. Bouton révoquer/supprimer un device. Auto-refresh côté UI pour ne pas avoir à cliquer "🔄".

**Architecture:**
- 2 nouvelles tables : `device_heartbeats` (rolling 7j, point dans le temps de chaque heartbeat) et `playback_logs` (rolling 30j, une ligne par lecture média)
- 2 RPC SECURITY DEFINER : `record_heartbeat(...)` (insert + update devices + purge en bande) et `record_playback(...)` (insert log)
- Player : appelle les RPC au lieu du PATCH direct + queue locale playback_logs (flush à chaque heartbeat)
- Backoffice : auto-refresh `devicesListProvider` toutes les 30s + écran détail device avec sparkline heartbeats + table playback logs
- Boutons "Révoquer" et "Supprimer" exposés dans l'UI (extend `DevicesRepository`)

---

## Task 1 — Migrations device_heartbeats + playback_logs

**Files:**
- Create: `supabase/migrations/20260427100000_supervision_tables.sql`

```sql
create table public.device_heartbeats (
    id bigserial primary key,
    device_id uuid not null references public.devices(id) on delete cascade,
    received_at timestamptz not null default now(),
    battery int,
    storage_free_mb int,
    app_version text
);

create index device_heartbeats_device_idx
    on public.device_heartbeats (device_id, received_at desc);

alter table public.device_heartbeats enable row level security;

create policy heartbeats_admin_select on public.device_heartbeats
    for select using (public.is_admin());

create policy heartbeats_manager_select on public.device_heartbeats
    for select using (
        exists (
            select 1 from public.devices d
            join public.establishment_managers em
              on em.establishment_id = d.establishment_id
            where d.id = device_heartbeats.device_id
              and em.profile_id = auth.uid()
        )
    );

-- Aucun INSERT côté client : passe par RPC record_heartbeat (Task 2)


create table public.playback_logs (
    id bigserial primary key,
    device_id uuid not null references public.devices(id) on delete cascade,
    media_id uuid references public.media(id) on delete set null,
    played_at timestamptz not null default now(),
    duration_played_sec int not null check (duration_played_sec >= 0)
);

create index playback_logs_device_idx
    on public.playback_logs (device_id, played_at desc);

create index playback_logs_media_idx
    on public.playback_logs (media_id);

alter table public.playback_logs enable row level security;

create policy playback_logs_admin_select on public.playback_logs
    for select using (public.is_admin());

create policy playback_logs_manager_select on public.playback_logs
    for select using (
        exists (
            select 1 from public.devices d
            join public.establishment_managers em
              on em.establishment_id = d.establishment_id
            where d.id = playback_logs.device_id
              and em.profile_id = auth.uid()
        )
    );

-- Aucun INSERT côté client : passe par RPC record_playback (Task 2)
```

Apply, commit: `feat(db): add device_heartbeats and playback_logs tables with RLS`

---

## Task 2 — RPC record_heartbeat + record_playback (security definer + in-band purge)

**Files:**
- Create: `supabase/migrations/20260427100100_supervision_rpcs.sql`

```sql
-- Purge windows
create or replace function public.purge_old_supervision_data()
returns void language sql security definer set search_path = public as $$
    delete from public.device_heartbeats where received_at < now() - interval '7 days';
    delete from public.playback_logs where played_at < now() - interval '30 days';
$$;

revoke all on function public.purge_old_supervision_data() from public;

-- record_heartbeat : appelé par le device (JWT.sub = device_id)
create or replace function public.record_heartbeat(
    p_battery int default null,
    p_storage_free_mb int default null,
    p_app_version text default null,
    p_sync_progress int default null,
    p_current_media_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_device_id uuid;
begin
    v_device_id := auth.uid();
    if v_device_id is null then
        raise exception 'No auth context' using errcode = '42501';
    end if;

    -- Sanity: must reference an existing, non-revoked device
    if not exists (
        select 1 from public.devices d
        where d.id = v_device_id and d.revoked_at is null
    ) then
        raise exception 'Device not found or revoked' using errcode = '42501';
    end if;

    insert into public.device_heartbeats (
        device_id, battery, storage_free_mb, app_version
    ) values (
        v_device_id, p_battery, p_storage_free_mb, p_app_version
    );

    update public.devices
       set last_seen_at = now(),
           sync_progress = coalesce(p_sync_progress, sync_progress),
           current_media_id = coalesce(p_current_media_id, current_media_id)
     where id = v_device_id;

    -- Best-effort in-band purge (occasional)
    if random() < 0.01 then  -- ~1% of calls trigger cleanup
        perform public.purge_old_supervision_data();
    end if;
end $$;

revoke all on function public.record_heartbeat(int, int, text, int, uuid) from public;
grant execute on function public.record_heartbeat(int, int, text, int, uuid) to authenticated;

-- record_playback : un log par item joué
create or replace function public.record_playback(
    p_media_id uuid,
    p_duration_played_sec int
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_device_id uuid;
begin
    v_device_id := auth.uid();
    if v_device_id is null then
        raise exception 'No auth context' using errcode = '42501';
    end if;

    if not exists (
        select 1 from public.devices d
        where d.id = v_device_id and d.revoked_at is null
    ) then
        raise exception 'Device not found or revoked' using errcode = '42501';
    end if;

    insert into public.playback_logs (
        device_id, media_id, duration_played_sec
    ) values (
        v_device_id, p_media_id, greatest(p_duration_played_sec, 0)
    );
end $$;

revoke all on function public.record_playback(uuid, int) from public;
grant execute on function public.record_playback(uuid, int) to authenticated;
```

Apply, commit: `feat(db): add record_heartbeat and record_playback RPCs with in-band purge`

---

## Task 3 — pgTAP tests

**Files:**
- Create: `supabase/tests/rls_phase6_test.sql`

5 tests :
1. Device peut appeler `record_heartbeat` (en simulant device JWT)
2. Heartbeat insère ligne + met à jour `devices.last_seen_at`
3. Manager voit les heartbeats de ses établissements
4. Manager NE voit PAS les heartbeats d'un autre établissement
5. `record_playback` insère ligne avec bon `device_id`

Run: `supabase test db` — 26 tests total (21 + 5).
Commit: `test(db): add pgTAP tests for supervision RPCs and RLS`

---

## Task 4 — Étendre Player heartbeat → record_heartbeat RPC + queue playback_logs

**Files:**
- Modify: `apps/player/lib/data/remote/sync_api_client.dart` — remplacer la méthode `heartbeat` par appel RPC + ajouter `recordPlayback(mediaId, duration)`
- Create: `apps/player/lib/data/local/playback_log_queue.dart` — petite table drift `pending_playback_logs` pour buffer offline + flush
- Modify: `apps/player/lib/data/local/app_database.dart` — ajouter table `pending_playback_logs(id pk, media_id, duration_sec, captured_at)`
- Modify: `apps/player/lib/features/player/presentation/player_screen.dart` — quand un item finit, enqueue un log local ; à chaque heartbeat, flush la queue via RPC + appel record_heartbeat

Code snippets clés :

```dart
// SyncApiClient, replace heartbeat()
Future<void> heartbeat({
  int? syncProgress,
  String? currentMediaId,
  int? battery,
  int? storageFreeMb,
  String? appVersion,
}) async {
  await _dio.post(
    '$baseUrl/rest/v1/rpc/record_heartbeat',
    data: jsonEncode({
      if (battery != null) 'p_battery': battery,
      if (storageFreeMb != null) 'p_storage_free_mb': storageFreeMb,
      if (appVersion != null) 'p_app_version': appVersion,
      if (syncProgress != null) 'p_sync_progress': syncProgress,
      if (currentMediaId != null) 'p_current_media_id': currentMediaId,
    }),
    options: Options(headers: {..._headers, 'Content-Type': 'application/json'}),
  );
}

Future<void> recordPlayback({required String mediaId, required int durationPlayedSec}) async {
  await _dio.post(
    '$baseUrl/rest/v1/rpc/record_playback',
    data: jsonEncode({'p_media_id': mediaId, 'p_duration_played_sec': durationPlayedSec}),
    options: Options(headers: {..._headers, 'Content-Type': 'application/json'}),
  );
}
```

Drift table :
```dart
class PendingPlaybackLogs extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get mediaId => text().named('media_id')();
  IntColumn get durationSec => integer().named('duration_sec')();
  IntColumn get capturedAt => integer().named('captured_at')();  // unix ms
}
```

Schema version bump : `2`. Drift gère la migration auto pour ajouts de tables (avec `MigrationStrategy`). À implémenter proprement :
```dart
@override
MigrationStrategy get migration => MigrationStrategy(
  onUpgrade: (m, from, to) async {
    if (from < 2) await m.createTable(pendingPlaybackLogs);
  },
);
```

Player flow:
- À la fin d'un item (vidéo terminée OU image timer écoulé), insérer dans `pending_playback_logs` avec `media_id, duration_sec, captured_at`
- À chaque heartbeat (Timer.periodic 5 min), avant l'appel record_heartbeat :
  - Lire toutes les lignes `pending_playback_logs`
  - Pour chacune, appeler `recordPlayback`
  - Si succès, supprimer la ligne locale
  - Sur échec → on garde, on retry au prochain heartbeat

Commit: `feat(player): use record_heartbeat RPC and queue playback logs`

---

## Task 5 — Backoffice : auto-refresh devices list + sparkline heartbeat (carte)

**Files:**
- Modify: `apps/backoffice/lib/features/devices/presentation/devices_list_screen.dart`

Changements :
1. `Timer.periodic(Duration(seconds: 30), ...)` qui invalide `devicesListProvider`
2. Vue **cards** au lieu de **liste** (GridView ou Wrap), chaque card montre :
   - Pastille statut (vert/gris) gros format en haut à droite
   - Nom du device
   - Établissement (lookup local depuis `establishmentsListProvider`)
   - Sous-titre : `il y a X min` (relatif)
   - Sync progress (si != 100, barre LinearProgressIndicator)
   - **Média actuel** : nom du fichier (lookup `mediaListProvider` par `current_media_id`) — nécessite que `Device` model expose `currentMediaId` (étendre Phase 5 model)
   - Boutons : 🎵 assigner playlist · 🚫 révoquer · 🗑 supprimer (avec confirm)

Ajouter `currentMediaId` à `Device` model (`packages/shared/lib/src/models/device.dart`) — extension non-breaking.

Refresh manuel toujours dispo dans l'AppBar. Auto-refresh visible via un petit indicateur "live" dans l'AppBar.

Commit: `feat(backoffice): auto-refresh devices list with rich status cards`

---

## Task 6 — Backoffice : Device detail screen (heartbeat history + playback logs)

**Files:**
- Create: `apps/backoffice/lib/features/devices/data/device_detail_repository.dart` — methods : `recentHeartbeats(deviceId, limit)`, `recentPlaybackLogs(deviceId, limit)`
- Create: `apps/backoffice/lib/features/devices/presentation/device_detail_screen.dart`
- Modify: `apps/backoffice/lib/routing/app_router.dart` — add route `/devices/:id`
- Modify: list screen onTap card → navigate to detail

Detail screen layout :
- Header : nom + statut + révoquer/supprimer
- Section "Statut actuel" : pastille, dernière vue, sync progress, média joué, version playlist
- Section "Heartbeats (24h)" : liste des 50 derniers heartbeats avec timestamp + battery + storage_free_mb + app_version (option : chart simple)
- Section "Lectures récentes (24h)" : 50 dernières playback_logs avec timestamp + média (nom) + durée

Commit: `feat(backoffice): add device detail screen with heartbeats and playback logs`

---

## Task 7 — Boutons révoquer + supprimer + DevicesRepository extend

**Files:**
- Modify: `apps/backoffice/lib/features/devices/data/devices_repository.dart` — déjà a `revoke(id)`. Ajouter `delete(id)`.
- Modify: `apps/backoffice/lib/features/devices/presentation/devices_list_screen.dart` ET `device_detail_screen.dart` — ajouter PopupMenuButton avec :
  - "Révoquer (force re-pair)" → confirm dialog → `repo.revoke(id)` → invalidate
  - "Supprimer définitivement" → confirm dialog rouge "irreversible" → `repo.delete(id)` → invalidate

```dart
Future<void> delete(String id) async {
  try {
    await _client.from('devices').delete().eq('id', id);
  } on PostgrestException catch (e) {
    throw AppException('Suppression échouée', cause: e.message);
  }
}
```

Commit: `feat(backoffice): expose revoke and delete actions in devices UI`

---

## Task 8 — Phase 6 demo doc + README

**Files:**
- Create: `docs/phase6-demo.md`
- Modify: `README.md`

Démo :
1. Lancer le Player (rebuild après player changes Task 4) sur la tablette → sync + lecture
2. Ouvrir back office Appareils → vue cards, pastille verte qui se rafraîchit toute seule (~30s)
3. Cliquer sur la carte → device detail screen
4. Voir les heartbeats arriver en temps quasi-réel (5 min) + les playback_logs (1 par item joué)
5. Couper le wifi → continue à jouer + queue les logs en local
6. Reconnecter → les logs queue sont flushés au prochain heartbeat
7. Bouton "Révoquer" : déconnecte le device → l'app au prochain heartbeat reçoit 401 (RPC échoue car `revoked_at` non null) → revient en mode appairage

Commit: `docs(phase6): add phase 6 supervision demo script`

---

## Self-Review

1. **Spec coverage** (section 10 Phase 6):
   - ✅ Tables `device_heartbeats`, `playback_logs` → Task 1
   - ✅ Colonnes live sur devices → déjà ajoutées Phase 5
   - ✅ Dashboard avec statut live, média joué, % synchro, dernière vue → Tasks 5-6
   - ✅ Révocation device → Task 7
   - ✅ Démo dashboard temps réel → Task 8

2. **Type consistency** :
   - `record_heartbeat`/`record_playback` RPCs (Task 2) appelés Task 4
   - Drift schema v2 + migration onUpgrade (Task 4)
   - `Device.currentMediaId` étendu (Task 5)
   - `DevicesRepository.delete` ajouté (Task 7)

3. **Dette acceptée** :
   - Pas de pg_cron : purge en bande sur 1% des heartbeats (probabiliste, suffisant en dev)
   - Pas de WebSocket Realtime : auto-refresh polling 30s (acceptable, transition vers Realtime en Phase 7+ si besoin)
   - Pas de chart historique sparkline (juste liste de heartbeats — peut être ajouté plus tard)
   - Pas de bouton "preuve de diffusion exportable" (CSV des playback_logs) — Phase 7+
