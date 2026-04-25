# Phase 8 — FCM push instantané

**Date** : 2026-04-25
**Statut** : design figé, prêt pour planification
**Scope** : zéro-latence sur publish playlist + assign/detach + revoke device. Polling 15min reste filet de sécurité.

---

## 1. Objectif

Aujourd'hui, le Player polle toutes les 15 minutes. Quand un gérant publie une
playlist à 19h pour le service du soir, l'écran peut mettre jusqu'à 15 minutes
à refléter le changement. Phase 8 ramène ce délai à **< 5 secondes** pour les
3 événements à fort impact métier :

1. **Publication d'une playlist** (nouvelle version) → push vers tous les
   devices qui ont cette playlist assignée.
2. **Assignation/désassignation playlist↔device** → push vers le device
   concerné.
3. **Révocation device** → push instant pour basculer en `RevokedScreen` sans
   attendre les 15 minutes ou un échec RLS au prochain heartbeat.

Le polling 15 min reste actif comme safety net.

## 2. Non-objectifs (YAGNI)

- ❌ FCM iOS / APNs (Player Android-only par design)
- ❌ Topic-based subscriptions (token-based suffit, plus flexible pour
  ciblage device-spécifique)
- ❌ Push depuis le Player vers le backend (heartbeats REST suffisent)
- ❌ Notifications système visibles (data-only, jamais de popup OS)
- ❌ Web push pour le backoffice (utilise déjà du polling, pas de besoin)
- ❌ Migration DB (`devices.fcm_token` existe déjà depuis Phase 2)
- ❌ Postgres triggers + `pg_net` (couplage opaque, dépendance extension non
  installée — voir Section 9 "Décisions tranchées")

## 3. Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│ Backoffice (Flutter Web)                                            │
│  ┌─────────────────────┐                                            │
│  │ Publish playlist    │ ──── REST ────┐                            │
│  │ Assign / Detach     │ ──── REST ────┤                            │
│  │ Revoke device       │ ──── REST ────┤                            │
│  └─────────────────────┘               │                            │
└────────────────────────────────────────┼────────────────────────────┘
                                         ↓
┌────────────────────────────────────────────────────────────────────┐
│ Supabase (Postgres + 3 nouvelles Edge Functions Deno)              │
│  ┌─────────────────────┐  ┌─────────────────────┐  ┌─────────────┐│
│  │ publish-playlist    │  │ assign-playlist     │  │revoke-device││
│  └────────┬────────────┘  └────────┬────────────┘  └──────┬──────┘│
│           └─────────┬───────────────┴──────────────────────┘       │
│                     ↓                                               │
│         ┌─────────────────────────┐                                │
│         │ FcmDispatcher (helper)  │                                │
│         │  - OAuth2 → Bearer      │                                │
│         │  - POST /v1/projects/.. │                                │
│         └────────────┬────────────┘                                │
└──────────────────────┼─────────────────────────────────────────────┘
                       ↓ HTTPS (FCM HTTP v1 API)
┌─────────────────────────────────────────────────────────────────────┐
│ Google FCM                                                          │
└──────────────────────┬──────────────────────────────────────────────┘
                       ↓ silent data message (priority HIGH)
┌─────────────────────────────────────────────────────────────────────┐
│ Player Android                                                      │
│  ┌─────────────────────────────────┐                               │
│  │ FcmService (Kotlin)             │                               │
│  │  - extends FirebaseMessagingSvc │                               │
│  │  - onNewToken / onMessage       │                               │
│  └────────────┬────────────────────┘                               │
│               ↓ MethodChannel "app.player/fcm"                     │
│  ┌─────────────────────────────────┐                               │
│  │ FcmHandler (Dart)               │                               │
│  │  - persiste token en DB         │                               │
│  │  - bump providers de sync/revoke│                               │
│  └─────────────────────────────────┘                               │
└─────────────────────────────────────────────────────────────────────┘
```

### Composants nouveaux

1. **`FcmService` Kotlin** (`apps/player/android/app/src/main/kotlin/com/appdiffusion/player/FcmService.kt`)
   - `extends FirebaseMessagingService`
   - `onNewToken(token)` → MethodChannel "app.player/fcm" `onTokenRefresh` (ou
     persiste dans `PendingFcmTokenStorage` si l'engine n'est pas encore vivant)
   - `onMessageReceived(remoteMessage)` → MethodChannel `onMessage`

2. **`FcmHandler` Dart** (`apps/player/lib/services/fcm_handler.dart`)
   - `registerToken(token)` : `supabase.from('devices').update({'fcm_token': token}).eq('id', deviceId)`
     (la policy `devices_self_update_heartbeat` autorise déjà ça). Si offline,
     enqueue dans `LocalSettings` (table Phase 9) pour retry au prochain pairing
     ou retour réseau.
   - `onMessage(data)` : switch sur `data['type']` :
     - `playlist_published` ou `assignment_changed` → bump
       `forceSyncRequestProvider` (mécanisme Phase 9) → PlayerScreen re-sync
     - `revoked` → bump `fcmRevokedSignalProvider` → PlayerScreen bascule sur
       `RevokedScreen`

3. **3 Edge Functions Deno** (`supabase/functions/`)
   - `publish-playlist/index.ts` : update DB + dispatch push à tous devices
     ayant la playlist assignée
   - `assign-playlist/index.ts` : upsert ou delete dans `device_playlists` +
     push au device concerné
   - `revoke-device/index.ts` : `revoked_at = now()` + push au device

4. **`FcmDispatcher` helper** (`supabase/functions/_shared/fcm_dispatcher.ts`)
   - Lit `Deno.env.get('FIREBASE_SERVICE_ACCOUNT')` (JSON string complète du
     service account)
   - Génère un access token OAuth2 via JWT signé (`djwt`) → POST
     `https://oauth2.googleapis.com/token`
   - Cache l'access token (1h validity)
   - POST `https://fcm.googleapis.com/v1/projects/<project_id>/messages:send`
   - Mode **LOG_ONLY** activé si `FIREBASE_SERVICE_ACCOUNT` absent : log à la
     console au lieu d'envoyer. Permet le dev local sans Firebase.
   - Détecte `UNREGISTERED` → caller doit wipe le token en DB

5. **Refacto backoffice repositories** (3 fichiers)
   - `PlaylistsRepository.publish(id)` : remplace l'UPDATE direct par
     `supabase.functions.invoke('publish-playlist', {body: {id}})`
   - `DevicesRepository.assignPlaylist(deviceId, playlistId)` :
     `invoke('assign-playlist', ...)`
   - `DevicesRepository.revoke(deviceId)` : `invoke('revoke-device', ...)`

## 4. Format des messages FCM

Tous les push sont des **data messages** (jamais de bloc `notification`,
silencieux pour le client final). Format uniforme :

```json
{
  "message": {
    "token": "<device_fcm_token>",
    "data": {
      "type": "playlist_published" | "assignment_changed" | "revoked",
      "playlist_id": "<uuid>" | null,
      "version": "<int as string>"
    },
    "android": {
      "priority": "high",
      "ttl": "300s"
    }
  }
}
```

Toutes les valeurs `data` sont des strings (contrainte FCM).

### Type 1 — `playlist_published`
```json
{ "type": "playlist_published", "playlist_id": "c0a5...", "version": "12" }
```

### Type 2 — `assignment_changed`
```json
{ "type": "assignment_changed", "playlist_id": "c0a5..." }
// ou pour détacher :
{ "type": "assignment_changed", "playlist_id": "" }   // string vide = détaché
```

### Type 3 — `revoked`
```json
{ "type": "revoked" }
```

### Options Android communes
- `priority: "high"` : réveille le device même en Doze (combiné avec battery
  exclusion de Phase 9, le service foreground tient le process en vie).
- `ttl: "300s"` : si le device est offline plus de 5 minutes, drop le push.
  Le polling 15 min rattrape de toute façon.

## 5. Flows complets

### Flow 1 — Gérant publie une playlist
```
1. Gérant clique "Publier" dans backoffice
2. PlaylistsRepository.publish(id) → supabase.functions.invoke('publish-playlist', {id})
3. Edge Function publish-playlist :
   a. UPDATE playlists SET version = version + 1, published_at = now() WHERE id = $1
   b. (le trigger DB tg_audit_playlist_published existant se déclenche → audit_event créé)
   c. SELECT d.id, d.fcm_token FROM device_playlists dp
      JOIN devices d ON d.id = dp.device_id
      WHERE dp.playlist_id = $1
        AND d.fcm_token IS NOT NULL
        AND d.revoked_at IS NULL
   d. Pour chaque token : FcmDispatcher.send(token, {type: 'playlist_published', ...})
   e. Wipe les tokens UNREGISTERED via UPDATE devices SET fcm_token = NULL WHERE id IN (...)
   f. Return JSON { sent: N, skipped: M } pour feedback UI
4. Backoffice affiche "Publié — push envoyé à N device(s)"
5. Player reçoit le data message :
   a. FcmService.onMessageReceived → MethodChannel → FcmHandler
   b. FcmHandler bump forceSyncRequestProvider
   c. PlayerScreen.ref.listen détecte → _runSync() → nouvelle playlist en lecture en < 5s
```

### Flow 2 — Admin assigne (ou détache) une playlist
```
1. Admin choisit dans backoffice
2. DevicesRepository.assignPlaylist(deviceId, playlistId | null) → invoke('assign-playlist', {...})
3. Edge Function :
   a. Si playlistId non null : INSERT INTO device_playlists ... ON CONFLICT (device_id) DO UPDATE
      Si null : DELETE FROM device_playlists WHERE device_id = $1
   b. SELECT fcm_token FROM devices WHERE id = $deviceId AND fcm_token IS NOT NULL
   c. FcmDispatcher.send(token, {type: 'assignment_changed', playlist_id: $playlistId ?? ''})
4. Player → forceSyncRequestProvider++ → re-sync → nouvelle playlist (ou écran Standby si détaché)
```

### Flow 3 — Admin révoque un device
```
1. Admin clique "Révoquer" dans le détail device
2. DevicesRepository.revoke(deviceId) → invoke('revoke-device', {deviceId})
3. Edge Function :
   a. SELECT fcm_token FROM devices WHERE id = $deviceId  (capture AVANT revoke)
   b. UPDATE devices SET revoked_at = now() WHERE id = $deviceId
   c. (trigger audit existant tg_audit_device_revoked s'enclenche)
   d. FcmDispatcher.send(captured_token, {type: 'revoked'})
   e. UPDATE devices SET fcm_token = NULL WHERE id = $deviceId
4. Player reçoit :
   a. FcmHandler détecte type === 'revoked'
   b. fcmRevokedSignalProvider bumpé
   c. PlayerScreen bascule immédiatement sur RevokedScreen
```

### Flow 4 — Player s'enregistre (bootstrap FCM)
```
1. Au lancement, FcmService.onCreate (Android) :
   a. FirebaseMessaging.getInstance().token (asynchrone)
   b. onNewToken callback → MethodChannel "app.player/fcm" "onTokenRefresh" {token}
2. Côté Dart, FcmHandler.onTokenRefresh(token) :
   a. supabase.from('devices').update({'fcm_token': token}).eq('id', deviceId)
   b. RLS policy devices_self_update_heartbeat autorise (déjà en place)
3. Si pas encore de credentials Supabase (avant pairing) → token mis en
   attente, persisté dans LocalSettings (table de Phase 9), envoyé au pairing
   complete dans le PairingScreen.
```

### Flow 5 — Token devient stale
```
1. Edge Function tente d'envoyer push → réponse FCM 404 / error "UNREGISTERED"
2. FcmDispatcher catch et caller wipe : UPDATE devices SET fcm_token = NULL
3. Au prochain lancement Player, FCM SDK émet un nouveau token via onNewToken
   → FcmHandler.registerToken → DB à jour
```

### Flow 6 — Mode LOG_ONLY (dev local sans Firebase)
```
- Si Deno.env.get('FIREBASE_SERVICE_ACCOUNT') est null/empty :
  - FcmDispatcher.send() loggue console.log("[FCM LOG_ONLY] Would send to {token}: {payload}")
  - Retourne { ok: false, reason: 'log_only' } pour permettre au caller de
    distinguer du vrai succès dans les tests
  - Permet de tester les Edge Functions et le wire-up backoffice sans Firebase
  - Polling 15min reste le mécanisme de propagation effectif
```

## 6. Composants Dart/Kotlin/Deno — contrats

### Arborescence (nouveaux fichiers)

```
apps/player/android/app/src/main/kotlin/com/appdiffusion/player/
  ├─ FcmService.kt
  └─ PendingFcmTokenStorage.kt              ← simple SharedPreferences pour token offline-bootstrap

apps/player/android/app/
  ├─ build.gradle.kts                       ← Modifié : plugin google-services + dep firebase-messaging
  └─ google-services.json                   ← À FOURNIR (gitignored, voir Section 7)

apps/player/android/
  └─ build.gradle.kts                       ← Modifié : declare le plugin gms version 4.4.4 apply false

apps/player/lib/services/
  └─ fcm_handler.dart                       ← Bridge Dart, persistance token, dispatch messages

apps/player/lib/features/lifecycle/application/
  └─ lifecycle_providers.dart               ← Modifié : ajout fcmRevokedSignalProvider + fcmHandlerProvider

supabase/functions/
  ├─ _shared/
  │   └─ fcm_dispatcher.ts                  ← Helper OAuth2 + POST FCM v1
  ├─ publish-playlist/index.ts
  ├─ assign-playlist/index.ts
  └─ revoke-device/index.ts

apps/backoffice/lib/features/playlists/data/
  └─ playlists_repository.dart              ← Modifié : publish() → invoke
apps/backoffice/lib/features/devices/data/
  └─ devices_repository.dart                ← Modifié : assignPlaylist + revoke → invoke
```

### Contrats clés

```dart
// apps/player/lib/services/fcm_handler.dart
abstract class FcmHandler {
  Future<void> registerToken(String token);
  void onMessage(Map<String, String> data);
}

// Riverpod additions dans lifecycle_providers.dart
final fcmRevokedSignalProvider = StateProvider<int>((ref) => 0);
final fcmHandlerProvider = Provider<FcmHandler>((ref) { ... });
```

```typescript
// supabase/functions/_shared/fcm_dispatcher.ts
export interface FcmDispatcher {
  send(token: string, data: Record<string, string>): Promise<FcmResult>;
  sendMany(
    pairs: Array<{ token: string; ownerId: string }>,
    data: Record<string, string>,
  ): Promise<FcmBatchResult>;
}

export type FcmResult =
  | { ok: true }
  | { ok: false; reason: 'unregistered' | 'invalid_token' | 'transient' | 'log_only'; error?: string };

export interface FcmBatchResult {
  okCount: number;
  unregisteredOwnerIds: string[];   // pour wipe DB
  errors: Array<{ ownerId: string; reason: string }>;
}
```

## 7. Configuration Firebase (à fournir manuellement)

### Étapes utilisateur (déjà documentées par Firebase) :
1. Créer un project Firebase (ex: "App-de-Diffusion-Prod") sur console.firebase.google.com.
2. Add Android app avec `applicationId = com.appdiffusion.player`.
3. Télécharger `google-services.json` → poser dans `apps/player/android/app/`
   (ce fichier sera dans `.gitignore`).
4. Project Settings → Service accounts → Generate new private key → JSON.
5. `cd "D:/App de diffusion" && supabase secrets set FIREBASE_SERVICE_ACCOUNT="<contenu_json_minifié>"`
   (ne JAMAIS commit ce fichier).

### Plugin Gradle (Android-side)

`apps/player/android/build.gradle.kts` (au niveau projet) :
```kotlin
plugins {
  id("com.google.gms.google-services") version "4.4.4" apply false
}
```

`apps/player/android/app/build.gradle.kts` :
```kotlin
plugins {
  id("com.android.application")
  id("com.google.gms.google-services")
}

dependencies {
  implementation(platform("com.google.firebase:firebase-bom:34.12.0"))
  implementation("com.google.firebase:firebase-messaging")
}
```

### `.gitignore` ajouts
```
# Firebase
apps/player/android/app/google-services.json
*.serviceaccount.json
```

## 8. Tests

### Backend
- **pgTAP** : aucun (pas de nouvelle table).
- **Edge Functions Deno** : tests avec `deno test` mockant `fetch` global.
  Couvre :
  - `publish-playlist` : send vers N devices, gère devices sans fcm_token, gère
    les tokens UNREGISTERED (wipe en DB).
  - `assign-playlist` : send vers 1 device, gère cas `playlist_id: null`.
  - `revoke-device` : send + wipe token + audit triggered.
  - `FcmDispatcher` : OAuth2 caching, mode LOG_ONLY, parsing UNREGISTERED.

### Player (Dart)
- **`FcmHandler`** unit : mock du SupabaseClient, vérifier `registerToken`
  retry/enqueue ; mock du Riverpod ref, vérifier que
  `onMessage('playlist_published')` bump `forceSyncRequestProvider` et
  `onMessage('revoked')` bump `fcmRevokedSignalProvider`.
- **PlayerScreen widget** : pump `fcmRevokedSignalProvider` → vérifier
  basculement sur RevokedScreen.

### Backoffice (Dart)
- **`PlaylistsRepository.publish()`** : mock `supabase.functions.invoke` →
  vérifier args `{body: {id}}`.
- **`DevicesRepository.assignPlaylist`/`revoke`** : idem.

### Intégration manuelle (démo)
1. Player démarré → vérifier dans `devices.fcm_token` que la valeur est
   non-NULL après ~10s.
2. Backoffice : publier une playlist → Player reprend avec nouveau contenu
   en < 5s.
3. Backoffice : assigner une autre playlist → Player bascule en < 5s.
4. Backoffice : révoquer device → Player affiche RevokedScreen en < 5s.
5. Mode dégradé : couper Internet sur la tablette pendant 1min → restaurer →
   polling 15min reprend de toute façon.

## 9. Décisions tranchées (alternatives écartées)

| Décision | Alternatives écartées | Raison |
|---|---|---|
| Edge Functions au lieu de Postgres triggers + pg_net | (B) `pg_net` + triggers DB, (C) Supabase Cloud webhooks | (B) requiert extension non installée + couplage DB↔HTTP fragilisant les pgTAP. (C) cloud-only, casse parité dev/local. |
| Token-based (envoi à un fcm_token) plutôt que topic-based | Topics FCM | Topics OK pour fan-out massif, mais notre cible inclut des push device-spécifiques (assign/revoke) où les topics ne marchent pas. Un seul mécanisme = plus simple. |
| Data messages only (pas de notification block) | Notification block ou both | On ne veut JAMAIS de popup OS visible (kiosque dans bar/restaurant). Data-only force aussi le code app à toujours traiter le message. |
| OAuth2 access token via service account | Legacy server key | Server keys sunset par Google en juin 2024. v1 API obligatoire. |
| Polling 15min conservé | Désactiver polling après FCM | Filet de sécurité contre OEM agressifs, FCM down, token stale temporairement. Coût quasi nul. |

## 10. Risques & mitigations

| Risque | Mitigation |
|---|---|
| OEM bloque le réveil de l'app par FCM (Xiaomi MIUI agressif) | Battery optim exclusion (Phase 9) + foreground service tient le process ; FCM data message à priorité HIGH passe |
| Service account JSON leaké | Stocké comme secret Supabase (`supabase secrets set FIREBASE_SERVICE_ACCOUNT=...`), jamais commit ; `.gitignore` couvre |
| Quota FCM | Pas de limite à notre échelle (quelques devices, quelques publish/jour) |
| Modif SQL directe → pas de push | Documenté ; polling 15 min sert de safety net ; à long terme refacto vers RPC SECURITY DEFINER si besoin |
| `google-services.json` absent en CI/dev | Build Android conditionné : si absent → désactiver la dependency Firebase via flag de build, le code Dart skip l'init FCM gracefully |
| Ancien token jamais wipé | FCM retourne UNREGISTERED → wipe automatique. Auto-healing. |
| Push reçu pendant l'initial sync | Bump du provider devient un no-op (déjà en sync) — pas de double-sync |

## 11. Critères d'acceptation

- [ ] Player envoie son `fcm_token` à `devices` table dans les 30s du premier lancement post-pairing.
- [ ] Publication d'une playlist : Player(s) impactés sync en < 5s.
- [ ] Assignation playlist : Player concerné bascule en < 5s.
- [ ] Révocation : Player concerné affiche `RevokedScreen` en < 5s.
- [ ] Mode LOG_ONLY fonctionne sans `FIREBASE_SERVICE_ACCOUNT` (dev local).
- [ ] Token stale (UNREGISTERED) → wipe automatique en DB.
- [ ] ≥ 8 nouveaux tests (Dart + Deno).
- [ ] Démo manuelle complète OK sur tablette physique.
- [ ] Polling 15min toujours actif comme safety net.
- [ ] Documentation déploiement à jour (Firebase setup, secret config, gitignore).
