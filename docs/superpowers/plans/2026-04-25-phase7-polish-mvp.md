# Phase 7 — Rôle gérant + polish + MVP — Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development to implement task-by-task.

**Goal:** Verrouiller la séparation admin/gérant côté UI (le gérant ne voit que ses établissements et n'a pas accès aux fonctions admin), ajouter un journal d'audit (`audit_events`) avec écran de consultation, finaliser la documentation de déploiement et boucler le MVP.

**Architecture:**
- `currentProfileProvider` charge le profil de l'utilisateur connecté (lookup `profiles` par `auth.uid()`) → expose `role` à toute l'UI
- UI conditionnelle : `if (role == admin)` autour des actions admin-only (créer établissement, créer gérant, créer playlist sur établissement non-géré, supprimer device, etc.)
- Table `audit_events` (admin-only SELECT) avec inserts depuis :
  - DB triggers sur `devices` (revoke), `playlists` (publish), `profiles` (création gérant via Edge Function)
  - Edge Functions existantes ajoutent un audit explicite (claim-pairing-code, create-manager)
- Player gère gracieusement le cas device révoqué (l'app détecte 401/RPC error → écran "Appareil révoqué" avec bouton ré-appairer qui clear la secure storage)
- Documentation déploiement : README enrichi avec section "Production setup" + script APK build

---

## File Structure additions

```
app-diffusion/
├── apps/backoffice/lib/
│   ├── features/
│   │   ├── auth/application/
│   │   │   └── current_profile_provider.dart      # Nouveau (extrait du existing)
│   │   └── audit/                                 # Nouveau
│   │       ├── data/audit_repository.dart
│   │       ├── application/audit_controller.dart
│   │       └── presentation/audit_log_screen.dart
│   └── shared_widgets/
│       └── role_gated.dart                        # Nouveau
├── apps/player/lib/features/
│   └── revoked/presentation/
│       └── revoked_screen.dart                    # Nouveau
└── supabase/
    ├── migrations/
    │   ├── 20260428100000_audit_events.sql
    │   └── 20260428100100_audit_triggers.sql
    └── tests/
        └── rls_phase7_test.sql
```

---

## Task 1 — `audit_events` table + RLS

**Files:**
- Create: `supabase/migrations/20260428100000_audit_events.sql`

```sql
create table public.audit_events (
    id bigserial primary key,
    actor_id uuid,                                  -- profile.id, device.id, or null (system)
    actor_type text not null check (actor_type in ('admin', 'manager', 'device', 'system')),
    event_type text not null,                       -- 'device_paired', 'device_revoked', 'playlist_published', 'user_created', etc.
    target_id uuid,                                 -- id of the affected row
    metadata jsonb,                                 -- free-form context
    created_at timestamptz not null default now()
);

create index audit_events_created_idx on public.audit_events (created_at desc);
create index audit_events_event_type_idx on public.audit_events (event_type);
create index audit_events_actor_idx on public.audit_events (actor_id);

alter table public.audit_events enable row level security;

-- Admin only
create policy audit_admin_select on public.audit_events
    for select using (public.is_admin());

-- INSERT only via SECURITY DEFINER triggers/functions; no client-side INSERT policy
```

Apply, commit: `feat(db): add audit_events table with admin-only RLS`

---

## Task 2 — Audit triggers

**Files:**
- Create: `supabase/migrations/20260428100100_audit_triggers.sql`

Trigger pattern : capture l'événement, déduit l'`actor_type` depuis `auth.jwt()`, insère dans `audit_events`.

```sql
-- Helper to extract actor type from JWT or fallback
create or replace function public.audit_actor_type()
returns text
language sql
stable
security definer
set search_path = public
as $$
    select case
        when coalesce(auth.jwt()->>'is_device', 'false')::boolean then 'device'
        when public.is_admin() then 'admin'
        when auth.uid() is not null then 'manager'
        else 'system'
    end;
$$;

-- Device revoked
create or replace function public.tg_audit_device_revoked()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if new.revoked_at is not null and (old.revoked_at is null or old.revoked_at != new.revoked_at) then
        insert into public.audit_events (actor_id, actor_type, event_type, target_id, metadata)
        values (
            auth.uid(),
            public.audit_actor_type(),
            'device_revoked',
            new.id,
            jsonb_build_object('device_name', new.name, 'establishment_id', new.establishment_id)
        );
    end if;
    return new;
end $$;

create trigger devices_audit_revoked
    after update of revoked_at on public.devices
    for each row execute function public.tg_audit_device_revoked();

-- Playlist published (version incremented + published_at set)
create or replace function public.tg_audit_playlist_published()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if new.version > old.version and new.published_at is not null then
        insert into public.audit_events (actor_id, actor_type, event_type, target_id, metadata)
        values (
            auth.uid(),
            public.audit_actor_type(),
            'playlist_published',
            new.id,
            jsonb_build_object(
                'playlist_name', new.name,
                'version', new.version,
                'establishment_id', new.establishment_id
            )
        );
    end if;
    return new;
end $$;

create trigger playlists_audit_published
    after update of version on public.playlists
    for each row execute function public.tg_audit_playlist_published();

-- Manager created (when a profile transitions to 'manager' role with a non-empty full_name
-- and an associated establishment_managers row exists). The Edge Function `create-manager`
-- could also do this explicitly; the trigger acts as a safety net.
create or replace function public.tg_audit_user_created()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    insert into public.audit_events (actor_id, actor_type, event_type, target_id, metadata)
    values (
        auth.uid(),
        public.audit_actor_type(),
        'user_created',
        new.id,
        jsonb_build_object('role', new.role, 'full_name', new.full_name)
    );
    return new;
end $$;

create trigger profiles_audit_created
    after insert on public.profiles
    for each row execute function public.tg_audit_user_created();

-- Device paired : when devices.last_seen_at goes from null → non-null
-- (proxy for "first heartbeat after pairing"). Better: log it in the Edge Function.
-- For now, we add the audit explicitly in claim-pairing-code (Task 3).
```

Apply, commit: `feat(db): add audit triggers for device revoke, playlist publish, profile creation`

---

## Task 3 — Edge Function `claim-pairing-code` adds audit event

**Files:**
- Modify: `supabase/functions/claim-pairing-code/index.ts`

Après l'UPDATE du `pairing_sessions` (`status = claimed`), insérer dans audit_events :

```typescript
// After the successful update of pairing_sessions:
const { error: auditErr } = await admin.from('audit_events').insert({
  actor_id: callerUser.user.id,
  actor_type: 'admin',
  event_type: 'device_paired',
  target_id: device.id,
  metadata: {
    device_name: (await admin.from('devices').select('name').eq('id', device.id).single()).data?.name,
    establishment_id: device.establishment_id,
  },
});
// Best effort: don't fail pairing on audit insert error
if (auditErr) console.error('audit insert failed', auditErr);
```

Restart functions serve.
Commit: `feat(functions): emit device_paired audit event from claim-pairing-code`

---

## Task 4 — pgTAP tests for audit + comprehensive cross-establishment isolation

**Files:**
- Create: `supabase/tests/rls_phase7_test.sql`

8 tests :
1. `audit_events` est admin-only en SELECT
2. Un trigger émet `device_revoked` quand `revoked_at` est posé
3. Un trigger émet `playlist_published` quand `version` est incrémenté + `published_at` posé
4. Cross-isolation: créer un 2e établissement + manager non-rattaché → vérifier qu'il ne voit RIEN dans Lounge Plateau (devices, playlists, media, audit_events)
5. RLS profiles : un manager voit seulement son propre profile
6. RLS establishment_managers : un manager voit seulement ses propres affectations
7. RLS device_playlists : un manager voit l'assignment de son établissement
8. Cascade FK : delete devices → delete device_heartbeats + playback_logs + device_playlists

Run: `supabase test db` — 34 tests total (26 + 8).
Commit: `test(db): add pgTAP tests for audit log and cross-establishment isolation`

---

## Task 5 — `currentProfileProvider` côté backoffice

**Files:**
- Create: `apps/backoffice/lib/features/auth/application/current_profile_provider.dart`
- Modify: `apps/backoffice/lib/features/auth/data/auth_repository.dart` — ajouter `Future<Profile> fetchCurrentProfile()` qui SELECT `profiles where id = auth.uid()`

```dart
// auth_repository.dart additions
Future<Profile> fetchCurrentProfile() async {
  try {
    final row = await _client.from('profiles')
        .select('id, role, full_name')
        .eq('id', _client.auth.currentUser!.id)
        .single();
    return Profile.fromJson(Map<String, dynamic>.from(row));
  } on PostgrestException catch (e) {
    throw AppException('Lecture profil échouée', cause: e.message);
  }
}

// current_profile_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import 'auth_controller.dart';

final currentProfileProvider = FutureProvider<Profile?>((ref) async {
  final session = ref.watch(currentSessionProvider);
  if (session == null) return null;
  return ref.read(authRepositoryProvider).fetchCurrentProfile();
});

final isAdminProvider = Provider<bool>((ref) {
  return ref.watch(currentProfileProvider).maybeWhen(
    data: (p) => p?.role == UserRole.admin,
    orElse: () => false,
  );
});
```

Commit: `feat(backoffice): add currentProfileProvider and isAdminProvider`

---

## Task 6 — UI rôle-gated : masquer/désactiver les actions admin-only

**Files:**
- Modify: `apps/backoffice/lib/shared_widgets/app_shell.dart` — masquer le menu "Gérants" si non-admin
- Modify: `apps/backoffice/lib/features/establishments/presentation/establishments_list_screen.dart` — masquer FAB "Nouvel établissement" si non-admin
- Modify: `apps/backoffice/lib/features/establishments/presentation/establishment_form_screen.dart` — masquer le bouton Supprimer si non-admin
- Modify: `apps/backoffice/lib/features/devices/presentation/devices_list_screen.dart` — dans le menu carte, masquer "Supprimer" si non-admin
- Modify: `apps/backoffice/lib/features/playlists/presentation/playlists_list_screen.dart` — masquer FAB "Nouvelle playlist" si non-admin (le manager peut éditer mais pas créer ; à confirmer ou ajuster)

Pattern :
```dart
final isAdmin = ref.watch(isAdminProvider);
floatingActionButton: isAdmin
    ? FloatingActionButton.extended(...)
    : null,
```

Pour le AppShell `_destinations`, filtrer dynamiquement :
```dart
final destinations = [
  const _Dest('/establishments', Icons.store_outlined, 'Établissements'),
  const _Dest('/devices', Icons.tv_outlined, 'Appareils'),
  const _Dest('/media', Icons.perm_media_outlined, 'Médias'),
  const _Dest('/playlists', Icons.queue_music_outlined, 'Playlists'),
  if (isAdmin) const _Dest('/managers', Icons.people_outline, 'Gérants'),
  if (isAdmin) const _Dest('/audit', Icons.history, 'Audit'),
];
```

Décision : le **manager peut créer/éditer/publier des playlists** dans ses établissements (c'est son cœur de métier), mais ne peut PAS :
- Créer/supprimer un établissement
- Créer/supprimer un device
- Créer un autre gérant
- Voir l'audit log

Commit: `feat(backoffice): role-gate admin-only UI (managers, audit, delete buttons)`

---

## Task 7 — Audit log viewer screen (admin only)

**Files:**
- Create: `apps/backoffice/lib/features/audit/data/audit_repository.dart`
- Create: `apps/backoffice/lib/features/audit/application/audit_controller.dart`
- Create: `apps/backoffice/lib/features/audit/presentation/audit_log_screen.dart`
- Modify: `apps/backoffice/lib/routing/app_router.dart` — add `/audit` route (only registered when admin? Or accessible but RLS filters)

Repository : list des derniers `audit_events` avec filtre par event_type.

UI : timeline des événements, chaque ligne :
- Icône selon event_type (🔗 paired, 🚫 revoked, 📢 published, 👤 user_created)
- Acteur (lookup profiles par actor_id)
- Description : `Admin {name} a publié la playlist {playlist_name} v{version}`
- Timestamp relatif

Filtres : combobox event_type + date range (24h, 7j, 30j).

Auto-refresh 30s identique aux devices.

Commit: `feat(backoffice): add audit log viewer screen for admins`

---

## Task 8 — Player : écran "Appareil révoqué" + détection

**Files:**
- Create: `apps/player/lib/features/revoked/presentation/revoked_screen.dart`
- Modify: `apps/player/lib/features/player/presentation/player_screen.dart` — détecter erreur RPC "Device not found or revoked" et set un flag → afficher RevokedScreen au lieu de standby

Pattern dans `_sendHeartbeat` ou `_runSync` :
```dart
catch (e) {
  if (e.toString().contains('Device not found or revoked')) {
    if (mounted) setState(() => _revoked = true);
  } else {
    // ... existing handling
  }
}
```

`RevokedScreen` :
```dart
class RevokedScreen extends ConsumerWidget {
  // Bouton "Re-appairer cet appareil" → clear secureStorage + invalidate credentialsProvider → retour PairingScreen
  Widget build(...) {
    return Scaffold(
      backgroundColor: Colors.red.shade900,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.block, size: 96, color: Colors.white),
            SizedBox(height: 24),
            Text('APPAREIL RÉVOQUÉ', style: TextStyle(color: Colors.white, fontSize: 32, letterSpacing: 4)),
            SizedBox(height: 16),
            Text('Cet appareil a été désactivé par l\'administrateur.', style: TextStyle(color: Colors.white70)),
            SizedBox(height: 48),
            FilledButton.icon(
              onPressed: () async {
                await ref.read(secureStorageProvider).clear();
                ref.invalidate(credentialsProvider);
              },
              icon: Icon(Icons.refresh),
              label: Text('Ré-appairer'),
            ),
          ],
        ),
      ),
    );
  }
}
```

Dans `app.dart`, le routage devient :
```dart
data: (c) => c == null
    ? const PairingScreen()
    : PlayerScreen(creds: c),
```

Et `PlayerScreen` lui-même affiche `RevokedScreen` si flag activé.

Commit: `feat(player): detect device revocation and show RevokedScreen with re-pair option`

---

## Task 9 — README de déploiement + script de build APK

**Files:**
- Modify: `README.md` — ajouter sections "Production setup", "Build APK", "On-boarding admin"

```markdown
## Production setup (Supabase Cloud)

1. Créer un projet Supabase Cloud (https://supabase.com)
2. Récupérer `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` depuis Settings → API
3. Linker le repo : `supabase link --project-ref <ref>`
4. Pousser les migrations : `supabase db push`
5. Pousser les Edge Functions :
   ```bash
   supabase functions deploy create-manager
   supabase functions deploy request-pairing-code
   supabase functions deploy pairing-status
   supabase functions deploy claim-pairing-code
   ```
6. Configurer `verify_jwt = false` pour `request-pairing-code`, `pairing-status`, `claim-pairing-code`, `create-manager` dans le dashboard Supabase
7. Définir le secret `JWT_SECRET` côté Supabase Functions : `supabase secrets set JWT_SECRET=<jwt-secret-from-dashboard>`
8. Créer un compte admin manuel via l'API ou Studio (insertion dans auth.users + UPDATE profiles SET role='admin')

## Build APK Player

```bash
cd apps/player
flutter build apk --release \
  --dart-define=SUPABASE_URL=https://<project-ref>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon-key>
```

L'APK est généré dans `build/app/outputs/flutter-apk/app-release.apk`. Distribuer via MDM ou installer manuellement (`adb install`).

## Build Web back office

```bash
cd apps/backoffice
flutter build web --release \
  --dart-define=SUPABASE_URL=https://<project-ref>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon-key>
```

Servir `build/web/` via Vercel, Netlify, ou nginx.

## On-boarding admin

1. Login admin via le back office (compte créé en étape 8 ci-dessus)
2. Créer les établissements (Établissements → Nouvel établissement)
3. Créer les gérants (Gérants → Nouveau gérant) en les rattachant aux établissements
4. Créer les devices (Appareils → Nouvel appareil) avec orientation paysage/portrait
5. Installer l'APK sur la tablette → afficher le code → Appairer dans le back office
6. Uploader les médias (Médias → Uploader)
7. Créer une playlist + ajouter les médias + Publier
8. Assigner la playlist au device (Appareils → 🎵)
9. La tablette sync et joue automatiquement
```

Commit: `docs: add production deployment, APK build, and admin onboarding guides`

---

## Task 10 — Phase 7 demo doc + finalize README

**Files:**
- Create: `docs/phase7-demo.md`
- Modify: `README.md` — add 7th demo bullet

Démo Phase 7 :
1. Login admin → voit toutes les entrées (Établissements, Appareils, Médias, Playlists, Gérants, Audit)
2. Naviguer dans **Audit** → voir l'historique des événements (revoke, publish, paired, user_created)
3. Logout → login `manager@local.test` / `ManagerPass123!`
4. Le menu de gauche n'affiche QUE Établissements, Appareils, Médias, Playlists (pas Gérants ni Audit)
5. Dans Établissements : pas de FAB "Nouveau" ; édition possible mais pas suppression
6. Manager voit uniquement "Lounge Plateau" et ses devices/médias/playlists
7. Tester : modifier la playlist, publier → ça marche
8. Tenter de naviguer manuellement vers `/managers` → URL invalide ou redirect vers /establishments
9. Côté admin : aller dans Appareils → menu carte → Révoquer la tablette
10. Sur la tablette : au prochain heartbeat (≤5 min), l'écran rouge "APPAREIL RÉVOQUÉ" s'affiche avec bouton "Ré-appairer"
11. Cliquer "Ré-appairer" sur la tablette → retour PairingScreen avec nouveau code
12. Admin re-appairer le device → reprend la lecture

Commit: `docs(phase7): add phase 7 demo script and final README`

---

## Self-Review

1. **Spec coverage** (section 10 Phase 7):
   - ✅ RLS complètes / tests RLS exhaustifs → Tasks 1-4
   - ✅ UI gérant (vue réduite) → Tasks 5-6
   - ✅ Audit log (`audit_events`) → Tasks 1-3, 7
   - ✅ Documentation déploiement / build APK / onboarding → Task 9
   - ✅ Démo : gérant connecté avec accès limité, gère sa playlist → Task 10

2. **Type consistency** :
   - `currentProfileProvider` (Task 5) consommé par UI Tasks 6, 7
   - `isAdminProvider` (Task 5) bool simple, utilisé partout pour les conditions
   - Triggers Phase 7 (Task 2) compatibles avec les `playlists.publish()` (Phase 4) et `devices.revoke()` (Phase 5+6)
   - Edge Function `claim-pairing-code` (Task 3) ajoute audit sans casser le flux Phase 2

3. **Dette acceptée** :
   - Pas de pagination de l'audit log (50 derniers seulement)
   - Pas de UI "Détacher playlist" déplacée vers le menu carte (reste dans le dialog `AssignPlaylistDialog`)
   - Pas de chart sparkline ni d'export CSV
   - "Audit" route accessible si admin tente l'URL même si menu masqué — protection RLS (admin-only SELECT) suffit
   - Bouton "Supprimer" non ajouté pour `managers`, `establishments`, `media` — déjà retravaillable mais hors scope MVP
   - Documentation production reste minimaliste — pas de docker-compose, pas de Terraform

Plan prêt.
