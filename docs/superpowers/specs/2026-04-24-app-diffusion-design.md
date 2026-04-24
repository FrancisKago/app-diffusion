# App de Diffusion — Design Document

**Date** : 2026-04-24
**Statut** : Validé (brainstorming)
**Auteur** : Francis KAGO

---

## 1. Contexte & objectif

Application de diffusion (digital signage) pour écrans dans restaurants et lounge bars.

**Livrables :**
- Une application Flutter Android qui joue en boucle du contenu (vidéos et images) plein écran sur des TV / tablettes.
- Un back office Flutter Web permettant de gérer les établissements, les appareils, les médias, les playlists, et de pousser du contenu aux appareils.

**Contraintes fonctionnelles clés :**
- Connexion internet **intermittente** sur les appareils Android : la lecture doit continuer hors-ligne.
- Chaque appareil a un **identifiant unique** et reçoit du contenu de manière ciblée.
- Programmation du contenu **par date** (campagnes datées) dans une playlist.
- Multi-rôles : **admin** (contrôle global) et **gérant** (limité à ses établissements).

---

## 2. Stack technique

| Couche | Technologie | Justification |
|---|---|---|
| Mobile | Flutter (Android APK) | Cross-platform, stack unifiée avec le web |
| Web | Flutter Web | Réutilisation des modèles et logique du package `shared` |
| Backend | Supabase (Postgres + Auth + Storage + Edge Functions) | Postgres natif pour planning, RLS pour multi-tenant, Storage pour vidéos |
| Push Android | Firebase Cloud Messaging (FCM) | Réveil de l'app même en background, seule Google-approved solution sur Android |
| Stockage local Android | SQLite via `drift` + `path_provider` pour médias | Lecture offline, requêtes typées |
| Stockage sécurisé (JWT) | `flutter_secure_storage` (Android Keystore) | Protection du token device |
| Background work | `workmanager` (Android) + foreground service | Survie aux redémarrages, sync après reboot |
| Téléchargement médias | `dio` avec resume | Reprise sur coupure réseau |
| Lecteur vidéo | `video_player` | Officiel Flutter, gestion des codecs natifs |
| Monorepo | Flutter workspaces (Dart 3.6+) | Structure officielle, pas de tooling externe |

---

## 3. Architecture globale

### 3.1 Structure monorepo

```
app-diffusion/
├── apps/
│   ├── player/                # Flutter Android (lecteur)
│   └── backoffice/            # Flutter Web (administration)
├── packages/
│   └── shared/                # Modèles Dart + client Supabase + logique partagée
├── supabase/
│   ├── migrations/            # Schéma SQL versionné
│   ├── functions/             # Edge Functions (TypeScript Deno)
│   │   ├── request-pairing-code/
│   │   ├── claim-pairing-code/
│   │   ├── push-playlist/
│   │   └── revoke-device/
│   └── seed.sql
├── docs/
│   └── superpowers/specs/     # Ce document
├── .github/workflows/         # CI (lint + test)
└── pubspec.yaml               # workspace racine
```

### 3.2 Composants et responsabilités

**`apps/player` — Lecteur Android**
- Mode **appairage** au premier lancement : affiche un code 6 chiffres, polle le statut.
- Mode **lecture** : boucle infinie sur la playlist locale, filtrée par dates d'activation.
- Mode **sync** : déclenché par data-message FCM ou par polling de secours (15 min) — télécharge nouveaux médias, purge anciens.
- Remonte heartbeat et télémétrie de lecture.
- Foreground service pour survivre au kill système.

**`apps/backoffice` — Back office Flutter Web**
- Auth Supabase (admin / gérant).
- CRUD établissements, appareils, médias, playlists.
- Upload médias avec validation formats/tailles.
- Éditeur de playlist drag-drop.
- Dashboard supervision (temps réel).
- Gestion des utilisateurs (admin uniquement).

**`packages/shared` — Domaine commun**
- Modèles typés (`Device`, `Media`, `Playlist`, `PlaylistItem`, `Establishment`, etc.) avec `freezed` + `json_serializable`.
- Wrapper du client Supabase.
- Logique pure : filtrage par dates, diff de playlists, validation de fichiers, génération de checksums.
- Testé exhaustivement en unit tests.

**Edge Functions Supabase (TypeScript Deno)**
- `request-pairing-code` : génère un code 6 chiffres pour un device donné (TTL 15 min).
- `claim-pairing-code` : valide un code, émet un JWT custom long-lived (90 jours), attache l'appareil.
- `push-playlist` : récupère les FCM tokens des devices d'un établissement/playlist, envoie un data-message.
- `revoke-device` : invalide le JWT d'un device, force la ré-authentification.

---

## 4. Modèle de données (Postgres)

Toutes les tables ont `id uuid PRIMARY KEY DEFAULT gen_random_uuid()`, `created_at timestamptz DEFAULT now()`, et `updated_at timestamptz` via trigger.

### 4.1 Tables

**`profiles`** — extension de `auth.users` Supabase
- `id uuid` (FK `auth.users`)
- `role text CHECK (role IN ('admin', 'manager'))`
- `full_name text`

**`establishments`**
- `name text NOT NULL`
- `timezone text NOT NULL DEFAULT 'UTC'`

**`establishment_managers`** — quels gérants accèdent à quel établissement
- `establishment_id uuid FK establishments`
- `profile_id uuid FK profiles`
- PK composite `(establishment_id, profile_id)`

**`devices`** — une ligne par écran physique
- `establishment_id uuid FK establishments NOT NULL`
- `name text NOT NULL` (ex: "Écran terrasse")
- `orientation text CHECK (orientation IN ('landscape', 'portrait')) DEFAULT 'landscape'`
- `pairing_code text` (nullable, effacé après claim)
- `pairing_code_expires_at timestamptz` (nullable)
- `fcm_token text` (nullable)
- `last_seen_at timestamptz`
- `current_media_id uuid FK media` (nullable)
- `sync_progress int DEFAULT 0` (0-100)
- `playlist_version int DEFAULT 0`
- `revoked_at timestamptz` (nullable, soft revoke)

**`media`** — tous les fichiers uploadés
- `establishment_id uuid FK establishments NOT NULL`
- `owner_id uuid FK profiles`
- `type text CHECK (type IN ('video', 'image'))`
- `file_path text NOT NULL` (path dans Supabase Storage)
- `file_size bigint NOT NULL`
- `duration_sec int` (nullable pour images)
- `width int`, `height int`
- `mime_type text`
- `checksum_sha256 text NOT NULL`
- `original_filename text`

**`playlists`**
- `establishment_id uuid FK establishments NOT NULL`
- `name text NOT NULL`
- `is_default bool DEFAULT false`
- `audio_enabled bool DEFAULT false`
- `version int DEFAULT 0` (incrémenté à chaque publication)
- `published_at timestamptz` (dernière publication)

**`playlist_items`** — contenu ordonné
- `playlist_id uuid FK playlists NOT NULL`
- `media_id uuid FK media NOT NULL`
- `position int NOT NULL`
- `display_duration_sec int DEFAULT 10` (utilisé pour images)
- `starts_at timestamptz` (nullable — campagne datée)
- `ends_at timestamptz` (nullable — campagne datée)
- UNIQUE `(playlist_id, position)`

**`device_playlists`** — assignation playlist → device (1:1 à un instant T)
- `device_id uuid FK devices NOT NULL`
- `playlist_id uuid FK playlists NOT NULL`
- PK `(device_id)` — un seul playlist par device

**`device_heartbeats`** — rolling, purge auto > 7 jours via pg_cron
- `device_id uuid FK devices NOT NULL`
- `received_at timestamptz NOT NULL DEFAULT now()`
- `battery int` (nullable)
- `storage_free_mb int`
- `app_version text`

**`playback_logs`** — rolling, purge auto > 30 jours
- `device_id uuid FK devices NOT NULL`
- `media_id uuid FK media NOT NULL`
- `played_at timestamptz NOT NULL DEFAULT now()`
- `duration_played_sec int NOT NULL`

**`audit_events`** — traçabilité actions sensibles, purge > 30 jours
- `actor_id uuid` (profile ou device)
- `actor_type text` ('admin' | 'manager' | 'device' | 'system')
- `event_type text` ('device_paired' | 'device_revoked' | 'playlist_published' | 'user_created')
- `target_id uuid`
- `metadata jsonb`

### 4.2 Invariants clés

- **`playlist_version` sur `devices`** sert d'ETag : l'Android compare sa version locale → déclenche une sync si différent.
- **`pairing_code` expirant** (15 min) + à usage unique (effacé à la première `claim` réussie).
- **`checksum_sha256` sur `media`** permet déduplication côté Android (deux playlists référant le même média = 1 seul download).
- **Un appareil = une playlist à la fois** (par `device_playlists` PK simple). Plusieurs écrans dans un même lieu = plusieurs playlists.

---

## 5. Flux clés

### 5.1 Flux A — Appairage d'un nouvel appareil

```
1. Admin crée "Écran terrasse" dans le back office.
   → INSERT devices (establishment_id, name)   (pas encore de pairing_code)

2. Installateur lance l'APK sur la tablette/TV.
   → App détecte absence de JWT en secure storage → mode "appairage".
   → App POST /request-pairing-code  { device_name_hint? }
      Edge Function :
        - insère une ligne `devices` fantôme OU met à jour la ligne créée en (1) ?
          → décision : en V1 l'admin DOIT créer la ligne avant ; le code est lié
            à un device_id existant.
        - génère un code 6 chiffres, enregistre dans devices.pairing_code + expires_at
   → App affiche le code plein écran ("482-193").

3. Admin saisit "482-193" dans le back office, associé à "Écran terrasse".
   → Back office POST /claim-pairing-code  { code, device_id }
      Edge Function :
        - vérifie code + non-expiré + device_id cohérent
        - génère JWT custom (claims: role=device, device_id, establishment_id, exp=90j)
        - efface pairing_code, enregistre audit_event 'device_paired'

4. App polle /pairing-status  (toutes les 3 sec, timeout 15 min).
   → Reçoit { jwt, device_id, establishment_id }
   → Stocke en flutter_secure_storage
   → Enregistre son FCM token : UPDATE devices SET fcm_token = ?
   → Bascule en mode "lecture" (télécharge playlist si assignée).
```

### 5.2 Flux B — Push de nouveau contenu

```
1. Gérant modifie une playlist (ajoute un média, réordonne, change dates).
   → Modifications en DB (playlist_items), mais playlist.version inchangé.
   → Bandeau UI : "Modifications non publiées".

2. Clic "Publier".
   → UPDATE playlists SET version = version + 1, published_at = now() WHERE id = ?
   → POST /push-playlist { playlist_id }
      Edge Function :
        - SELECT devices.fcm_token WHERE id IN (
            SELECT device_id FROM device_playlists WHERE playlist_id = ?
          ) AND fcm_token IS NOT NULL AND revoked_at IS NULL
        - Envoie FCM data-message (pas notification visible) :
            { type: "SYNC", playlist_id, version }
        - audit_event 'playlist_published'

3. Côté Android :
   - FirebaseMessaging.onBackgroundMessage reçoit le data-message.
   - Workmanager enqueue un SyncWorker unique (policy REPLACE).
   - Worker :
     a. Fetch playlist + playlist_items via Supabase (JWT device).
     b. Diff contre la copie locale SQLite : nouveaux items, items supprimés.
     c. Télécharge les médias manquants via Dio (resume sur échec).
     d. À chaque fichier OK : met à jour progress local + push
        UPDATE devices SET sync_progress = X
     e. Purge LRU des médias orphelins si cache > 2 Go.
     f. UPDATE devices SET playlist_version = version locale.
     g. Notifie le player UI (via stream) pour rafraîchir la boucle.

4. Fallback si FCM perdu :
   - Au retour du réseau (Connectivity.onChange), l'app déclenche un sync check.
   - Polling de secours toutes les 15 min :
     SELECT version FROM playlists WHERE id = (my device_playlist)
     Si version > local → même SyncWorker.
```

### 5.3 Flux C — Lecture offline + campagnes datées

```
Foreground service Android héberge le player. Boucle :

   loop:
     items = SELECT * FROM playlist_items_local
             WHERE media_file_downloaded = true
               AND (starts_at IS NULL OR starts_at <= now())
               AND (ends_at   IS NULL OR ends_at   >= now())
             ORDER BY position

     if items.isEmpty:
        render_standby(establishment_logo)  # fallback "rien à jouer"
        wait 30s ; continue

     for item in items:
        play(item)
          if item.media.type == video:
             VideoController.play(file) ; await until done or skip_signal
          else:  # image
             render(file) ; await display_duration_sec

        enqueue_playback_log(item.media_id, duration_actually_played)
        if skip_signal or new_version_available:
           break  # re-lire la liste au prochain tour

Le skip_signal est levé quand SyncWorker signale "playlist mise à jour".
Les playback_logs sont poussés en batch à chaque heartbeat.
```

### 5.4 Heartbeat

```
Toutes les 5 min (WorkManager periodic) :
  UPSERT device_heartbeats (device_id, battery, storage_free_mb, app_version)
  UPDATE devices SET last_seen_at = now(), current_media_id = ?
  Flush playback_logs queue locale.
```

---

## 6. Sécurité

### 6.1 Identités

| Identité | Auth | Stockage |
|---|---|---|
| Admin | Supabase Auth (email + password) | cookie navigateur |
| Gérant | Supabase Auth (email + password, créé par admin) | cookie navigateur |
| Device | JWT custom émis par Edge Function, lifetime 90j | flutter_secure_storage (Android Keystore) |

Le device n'est pas un `auth.users` classique — son JWT contient les claims `role=device`, `device_id`, `establishment_id`, et est signé avec le JWT secret Supabase pour passer les RLS.

### 6.2 RLS (Row Level Security)

Activé sur **toutes les tables**. Règles simplifiées :

- **`establishments`** : admin = tout ; gérant = SELECT uniquement sur ses établissements (via `establishment_managers`).
- **`devices`, `media`, `playlists`, `playlist_items`, `device_playlists`** : admin = tout ; gérant = tout sur les lignes de ses établissements ; device = SELECT uniquement sur sa propre ligne et les ressources liées à son établissement et à sa playlist.
- **`device_heartbeats`, `playback_logs`** : device INSERT uniquement (son propre `device_id`) ; admin/gérant SELECT.
- **`profiles`** : admin = tout ; autres = SELECT leur propre ligne uniquement.
- **`audit_events`** : admin SELECT ; INSERT par Edge Functions uniquement (service role).

### 6.3 Storage Supabase

- Bucket unique `media`. Chemins forcés : `<establishment_id>/<media_id>.<ext>`.
- Policies :
  - Upload : admin + gérant (dans leur établissement).
  - Download : admin + gérant + device de l'établissement.
- URLs signées 1h pour les downloads Android. Re-demandées à expiration.

### 6.4 Défenses additionnelles

- **Rate limit** sur `/request-pairing-code` et `/claim-pairing-code` (Edge Function + table `rate_limits` avec `(ip, endpoint, window_start)`). Max 10 requêtes / min / IP.
- **Code d'appairage** : usage unique, effacé à la première `claim` réussie. Aléatoire cryptographique (pas `Math.random`).
- **Révocation device** : bouton admin → `UPDATE devices SET revoked_at = now()`. L'Edge Function `push-playlist` ignore les devices révoqués. Le device au prochain heartbeat reçoit une réponse 401 → efface JWT → repasse en mode appairage.
- **Création des gérants** : réservée à l'admin (pas de self-service). Admin crée le profil puis associe aux établissements.

---

## 7. Contenu et lecture

### 7.1 Contraintes médias

| Type | Formats | Taille max | Autres |
|---|---|---|---|
| Vidéo | MP4 (H.264 + AAC) uniquement | 100 Mo | Validation codec via `ffprobe` côté Edge Function ou côté client |
| Image | JPG, PNG, WebP | 10 Mo | — |

- **Durée image** : paramétrable par `playlist_item.display_duration_sec`, défaut 10s.
- **Son vidéo** : muet par défaut (`playlists.audio_enabled = false`). Activable par playlist.
- **Orientation écran** : paysage ou portrait, réglable par device. Le player applique `SystemChrome.setPreferredOrientations`.

### 7.2 Cache local & téléchargement

- Répertoire : `getApplicationSupportDirectory()/media/`.
- Cap : 2 Go (constante, ajustable). Purge LRU si dépassement.
- Vérification `checksum_sha256` après download. Re-download si mismatch.
- **Lecture pendant téléchargement partiel** : l'app joue les médias déjà disponibles, et intègre les nouveaux au fur et à mesure. Jamais d'écran noir pour attendre 100%.
- **Wifi-only** par défaut (togglable par device) pour éviter de consommer la 4G.

---

## 8. Supervision (monitoring)

Dashboard back office (admin + gérant sur ses établissements) :

- **Liste des devices** avec statut live :
  - En ligne (heartbeat < 10 min) / Hors ligne
  - Média actuellement joué
  - Version playlist locale vs serveur (à jour / en cours de sync / retard)
  - Progression sync (%)
  - Storage libre, app version
  - Dernière vue
- **Alerte** : device offline > 1h → badge rouge.
- **Actions** : renommer, changer établissement, révoquer, forcer un resync (re-envoie FCM).

Pas de preuve de diffusion en V1 (overkill pour restaurant perso).

---

## 9. Stratégie de tests

| Niveau | Outil | Portée |
|---|---|---|
| Unit | `flutter_test` | Logique pure `packages/shared` : filtrage dates, diff playlists, validation fichiers, checksum |
| Widget | `flutter_test` + `golden_toolkit` | Écrans clés : appairage, lecteur (paysage/portrait), liste médias |
| Intégration backend | Supabase local (Docker) + Postgres | Migrations idempotentes, **tests RLS exhaustifs** (un test par règle) |
| E2E | Flutter `integration_test` + émulateur Android | Parcours complet : appairage → assignation playlist → push → lecture |

**Priorité tests RLS.** C'est la ligne de défense multi-tenant. Un bug RLS = fuite transverse entre établissements.

---

## 10. Phases de livraison

Estimation : **8 à 10 semaines** pour un MVP production-ready. Chaque phase finit par une démo jouable.

### Phase 1 — Fondations (1-2 sem.)
- Monorepo Flutter workspace, pubspec racine.
- CI GitHub Actions : lint (`flutter analyze`), tests unit, format check.
- Supabase local (Docker) + migrations : `profiles`, `establishments`, `establishment_managers`.
- Back office : login admin, CRUD établissements, création gérants.
- **Démo** : admin se connecte, crée un établissement, crée un gérant.

### Phase 2 — Appairage bout-en-bout (1-2 sem.)
- Tables `devices`.
- Edge Functions `/request-pairing-code`, `/claim-pairing-code`, `/pairing-status`.
- App Android minimaliste : écran "affichage code" + polling + stockage JWT.
- Back office : liste des devices, bouton "Appairer" avec input de code.
- **Démo** : une tablette affiche un code, l'admin la rattache, l'app passe en mode "prête".

### Phase 3 — Upload & gestion médias (1 sem.)
- Table `media`, Supabase Storage avec policies.
- Back office : drag-drop upload, prévisualisation, validation formats/tailles, barre de progression.
- **Démo** : upload d'une vidéo et 3 images, vignettes dans la bibliothèque.

### Phase 4 — Playlists & publication (1-2 sem.)
- Tables `playlists`, `playlist_items`, `device_playlists`.
- Back office : éditeur drag-drop, champs durée / dates début-fin / son activé.
- Bouton "Publier" → incrémente la version (pas encore de push).
- **Démo** : création d'une playlist de 5 médias, assignation à un device, publication.

### Phase 5 — Sync Android + lecteur (2 sem.) — cœur technique
- Intégration Firebase projet + FCM côté app.
- Edge Function `/push-playlist` qui envoie le data-message.
- App : `Workmanager`, `Dio` avec resume, cache SQLite local (`drift`), player plein écran.
- Foreground service, filtrage dates, boucle de lecture, mode standby.
- **Démo** : push depuis back office → tablette télécharge → joue en boucle. Coupure wifi → continue. Retour wifi → rattrape.

### Phase 6 — Supervision (1 sem.)
- Tables `device_heartbeats`, `playback_logs` + colonnes live sur `devices`.
- Back office : dashboard devices avec statut live, média joué, % synchro.
- Révocation device.
- **Démo** : dashboard en temps réel sur 2-3 tablettes.

### Phase 7 — Rôle gérant + polish (1 sem.)
- RLS complètes, tests RLS exhaustifs.
- UI gérant (vue réduite à ses établissements).
- Audit log (`audit_events`).
- Documentation : README déploiement Supabase, build APK, on-boarding admin.
- **Démo** : un gérant se connecte, ne voit que son établissement, gère sa playlist. **MVP complet.**

---

## 11. Risques techniques identifiés

1. **Survie du foreground service Android** — les constructeurs chinois (Xiaomi, Oppo, Huawei) tuent agressivement les apps en background.
   - **Atténuation** : en Phase 5, test sur au moins 2 fabricants. Documenter la mise en whitelist "Battery optimization" dans l'onboarding.

2. **Taille vidéos vs données mobiles** — 100 Mo × 10 vidéos = 1 Go. Un device en 4G limitée pourrait consommer son forfait.
   - **Atténuation** : `wifi_only` par défaut, togglable par device. Télémétrie de storage et connectivité exposée en dashboard.

3. **Fuite mémoire lecteur vidéo 24/7** — problème connu de `video_player` en boucle longue durée.
   - **Atténuation** : recycler le `VideoPlayerController` à chaque média, surveiller la RAM via heartbeat. Si besoin, introduire un restart programmé de l'activité toutes les 24h.

4. **Perte de FCM** — le token FCM peut être invalidé par Google (réinstallation, clear data). Le device ne reçoit plus les pushs.
   - **Atténuation** : polling de secours toutes les 15 min. À chaque heartbeat, l'Edge Function vérifie le token côté FCM et marque invalide si nécessaire (l'UI affiche un warning).

5. **Expiration JWT device (90j)** — si un device reste 90j sans jamais se connecter, son JWT expire.
   - **Atténuation** : refresh automatique à chaque heartbeat réussi. Si expiration complète → retour mode appairage, admin doit refaire un claim.

---

## 12. Hors-scope V1 (backlog)

Listé pour mémoire, **pas** à implémenter dans le MVP :

- Plage horaire précise (ex: playlist A de 8h à 12h, B de 12h à 14h). Les campagnes datées couvrent 90% des besoins.
- Groupes de devices cross-établissement / tags.
- Preuve de diffusion (logs détaillés avec horodatage exportables).
- Support iOS / TV OS / Linux kiosque.
- Player HTML5 pour fallback navigateur.
- Gestion multi-région / CDN pour les médias.
- API publique pour intégrations tierces.
- Notifications email (alerte device offline > X h).
- Self-service gérant (inscription libre).
- Rotation de playlist (plusieurs playlists actives en alternance sur un même device).

---

## 13. Décisions clés consolidées

| # | Décision | Choix |
|---|---|---|
| 1 | Backend | Supabase + FCM |
| 2 | Modèle contenu | Playlist + campagnes datées (A+C combinés) |
| 3 | Enrollment | Code d'appairage 6 chiffres + JWT persistant 90j |
| 4 | Hiérarchie | Établissements (pas de tags) |
| 5 | Sync offline | FCM wake + pull + cache local + polling secours 15 min |
| 6 | Supervision | Standard (heartbeat + télémétrie de lecture) |
| 7 | Formats médias | MP4 H.264/AAC ≤ 100 Mo ; JPG/PNG/WebP ≤ 10 Mo |
| 8 | Durée image | Paramétrable par item, défaut 10s |
| 9 | Orientation | Paysage ET portrait (par device) |
| 10 | Son vidéo | Muet par défaut, activable par playlist |
| 11 | Rôles | Admin + gérant (gérant limité à ses établissements, création par admin uniquement) |
| 12 | Publication playlist | Manuelle (bouton "Publier") |
| 13 | Lecture pendant download | Joue le contenu déjà disponible, complète au fur et à mesure |
| 14 | Foreground service | Accepté (notification persistante visible sur tablette, invisible sur TV) |
| 15 | Cap cache local | 2 Go, purge LRU |
| 16 | Réseau par défaut | Wifi-only, togglable par device |
