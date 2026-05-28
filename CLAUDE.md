# App de Diffusion — Project Memory

Persistent context for any Claude Code session working on this project.

## Project

Application de signage (digital signage) pour restaurants/lounge bars :
- **Player** Flutter Android (`apps/player/`) qui joue en boucle des vidéos/images sur des TV/tablettes
- **Back office** Flutter Web (`apps/backoffice/`) pour admin + gérants
- **Backend** Supabase local (Docker) en dev, déployable sur Supabase Cloud en prod
- **Package partagé** Dart (`packages/shared/`) pour modèles freezed + bootstrap

**Statut au 25 avr. 2026** : MVP complet. 7 phases livrées (Fondations → Appairage → Médias → Playlists → Sync+Lecteur → Supervision → Rôle gérant + polish).

## Stack & versions

- Flutter 3.38.9, Dart 3.6+, Flutter workspaces (monorepo)
- Supabase CLI 2.75, Postgres 17, Edge Functions Deno
- Drift ^2.21 (SQLite local Player), supabase_flutter ^2.8, flutter_riverpod ^2.6, go_router ^14.6, freezed ^2.5
- Docker Desktop 29 sur Windows
- pgTAP pour tests RLS

## Architecture invariants

1. **Multi-tenant par établissement** : tout est cloisonné par `establishment_id` via RLS Postgres. Un gérant ne voit jamais les données d'un autre établissement.
2. **Device JWT custom** (HS256, signé avec `JWT_SECRET`) émis par Edge Function `claim-pairing-code`. Claims : `sub=device_id`, `role=authenticated`, `aud=authenticated`, `is_device=true`, `establishment_id=...`, `exp=+90j`.
3. **Sync polling-first** : pas de FCM (différé Phase 5.5+). Player polle toutes les 15 min via REST + connectivity listener pour sync au retour réseau.
4. **Lecture offline** : drift SQLite mirror tables + cache fichiers `getApplicationSupportDirectory()/media/` avec LRU 2 Go.
5. **Audit centralisé** : triggers DB `security definer` sur revoke/publish/profile_created → table `audit_events` (admin-only SELECT).
6. **Rôle-gated UI** : `currentProfileProvider` charge le profile au login → `isAdminProvider` gate les FAB/menu/boutons admin-only.

## Conventions

- **Commits atomiques** par tâche, format conventional (`feat(scope):`, `fix(scope):`, `docs(scope):`, `test(scope):`).
- **TDD** pour code logique (modèles, services purs). UI testée en E2E via démo.
- **Subagent-driven development** : tasks groupées par batch (~3-5 par dispatch), implémenter+test+commit, puis review.
- **Plans stockés** dans `docs/superpowers/plans/YYYY-MM-DD-phaseN-name.md`, démos dans `docs/phaseN-demo.md`.
- **UI en français** (labels, messages d'erreur, doc démo). Code/comments mixés mais préférence anglais sauf justification métier.

## Build commands

### Local dev (Supabase + Flutter)
```bash
# Démarrage stack Supabase local
supabase start
supabase functions serve --env-file supabase/.env.local

# Tests
supabase test db                 # 34 pgTAP RLS tests
flutter test                     # depuis racine = workspace test
```

### Backoffice Web release (servi statiquement)
```bash
cd apps/backoffice
flutter build web --release \
  --dart-define=SUPABASE_URL=http://192.168.1.72:54321 \
  --dart-define=SUPABASE_ANON_KEY=<anon>
cd build/web && python -m http.server 4552 --bind 0.0.0.0
```

### Player APK (NÉCESSITE PowerShell admin sur Windows)
```powershell
cd "D:\App de diffusion\apps\player"
flutter run -d <DEVICE_ID> --release `
  --dart-define=SUPABASE_URL=http://192.168.1.72:54321 `
  --dart-define=SUPABASE_ANON_KEY=<anon>
```

## Gotchas Windows (résolus mais à savoir)

1. **`127.0.0.1 localhost` doit être présent** dans `C:\Windows\System32\drivers\etc\hosts` (non-commenté). Sans ça, Gradle daemon échoue avec "Unable to establish loopback connection".
2. **`kotlin.incremental=false`** dans `apps/player/android/gradle.properties` : nécessaire car projet sur `D:` et pub cache sur `C:` cassent le compilateur Kotlin incrémental ("different roots"). Build ralenti mais fonctionne.
3. **`supabase functions serve --env-file supabase/.env.local`** obligatoire (le file contient `JWT_SECRET=super-secret-jwt-token-with-at-least-32-characters-long`) sinon `claim-pairing-code` plante avec "Key length is zero".
4. **AndroidManifest cleartext + INTERNET permission** : `android:usesCleartextTraffic="true"` + `<uses-permission INTERNET/>` (déjà commités). Sinon HTTP local rejeté par Android 9+.
5. **IP LAN tablette physique** : `http://192.168.1.X:54321` au lieu de `10.0.2.2` (qui ne marche que sur émulateur). Vérifier `ipconfig` pour l'IP courante. Windows Firewall peut bloquer 54321/4552 → ajouter règle inbound si besoin.
6. **`flutter: uses-material-design: true`** doit être dans les pubspec player + backoffice (déjà commité). Sans ça, Material Icons ne sont pas embarqués → toutes les icônes affichent un rectangle vide.
7. **`flutter clean`** OBLIGATOIRE après ajout de package avec plugin web natif (ex: file_picker_web), sinon le plugin n'est pas enregistré dans le bundle release.
8. **Tablette physique = re-pairing nécessaire après `supabase db reset`** : si la table `devices` est wipée mais le JWT est dans le Keystore Android, l'app continue à envoyer des heartbeats sur un device_id qui n'existe plus → tout retourne empty. Solution : `Settings → Apps → Player → Storage → Clear` + nouvel appairage.
9. **Foreground service `mediaPlayback`** : depuis Phase 9, le manifest déclare le service du plugin `flutter_foreground_task`. Sur Android 14+, `FOREGROUND_SERVICE_MEDIA_PLAYBACK` est requise — déjà ajoutée. Si publication Play Store : justifier l'usage `mediaPlayback` (lecture vidéo en boucle pour signage) dans la fiche.
10. **Firebase setup obligatoire pour FCM (Phase 8)** : poser `apps/player/android/app/google-services.json` (téléchargé depuis console.firebase.google.com) avant tout build Android post-Phase 8. Sans ça, le build Gradle échoue avec "File google-services.json is missing". Voir `docs/firebase-setup.md` pour la procédure complète. Sans `FIREBASE_SERVICE_ACCOUNT` dans `supabase/.env.local`, les Edge Functions tournent en mode `LOG_ONLY` (loggue les push qu'elles auraient envoyés mais n'envoie rien) — le polling 15min reste effectif comme safety net.

## Comptes seed (dev local)

- Admin : `admin@local.test` / `AdminPass123!`
- Gérant : `manager@local.test` / `ManagerPass123!` (rattaché à "Lounge Plateau")
- Établissement seed : `Lounge Plateau` (id `11111111-1111-1111-1111-111111111111`)

## Déploiement Supabase Cloud

Projet Cloud **app-diffusion** (ref `mnoeteagkcqlrchyudju`, org `kzjfvodekvxzpccxxtpl`, région eu-west-1, créé le 28 mai 2026).
- Dashboard : https://supabase.com/dashboard/project/mnoeteagkcqlrchyudju
- URL API : `https://mnoeteagkcqlrchyudju.supabase.co`
- Clé client (publique) à passer en `--dart-define=SUPABASE_ANON_KEY` aux builds — utiliser la **clé publishable** (format moderne ; les clés JWT `anon`/`service_role` sont marquées legacy/dépréciées côté Supabase) :
  `sb_publishable_yHMBAWZGBiGetvahUw0IHA_VECuTL3N`
  Gateway REST/Auth/Functions/Storage OK avec supabase_flutter 2.12.4 ; vérifier le realtime devices (`.stream()`) au 1ᵉʳ test. Fallback historique (anon JWT legacy) : `eyJ…sBjESBNkG5AY3qGHTAHlAj54d7K0SDIjrJE2U13pZaQ`.
- Schéma : 20 migrations poussées (sans seed). Admin réel : `camerooninnovation58@gmail.com` (mdp hors repo). Service role key + mot de passe DB : **jamais commités** — voir gestionnaire de secrets.
- Le projet local est **lié** (`supabase link`). ⚠️ Un `supabase db push` **sans `--local` pousse en PROD**. Dev local : `supabase start` + dart-defines `192.168.1.X`.
- **Appairage device** : ✅ configuré. Le secret de fonction `JWT_SECRET` est posé sur le cloud et égale le JWT secret du projet (vérifié : signe des JWT device HS256 acceptés par la gateway). `claim-pairing-code` utilise le secret en **chaîne brute** (`TextEncoder().encode`), comme la vérification Supabase. ⚠️ Le JWT secret a transité en clair lors du setup — le faire tourner depuis le Dashboard (Settings > API) si besoin (régénère aussi anon/service keys). Pour le reposer : `supabase secrets set JWT_SECRET="<valeur>" --project-ref mnoeteagkcqlrchyudju`.

## Dépôt Git & hébergement web

- **GitHub** (public) : https://github.com/FrancisKago/app-diffusion — remote `origin`, branche `main`. Secrets gitignorés (`.env*`, `google-services.json`) ; clés publiques (anon/publishable) OK dans le repo.
- **Back office sur Vercel** : `vercel.json` + `scripts/vercel-build.sh` (Vercel ne build pas Flutter nativement → le script récupère le SDK et build le web). Réglages projet Vercel : **Root Directory = racine du repo** (pas `apps/backoffice`), **Framework = Other**, env vars **`SUPABASE_URL`** + **`SUPABASE_ANON_KEY`** (publishable). Output `apps/backoffice/build/web`. Hash routing → pas de rewrite SPA.
- **APK player via GitHub Actions** : `.github/workflows/build-apk.yml` (Windows ne build pas l'APK → `Unable to establish loopback connection` hors shell admin ; le runner Linux contourne). Build `--split-per-abi`, code généré (freezed/drift) régénéré, dart-defines cloud. `gh workflow run build-apk.yml` puis `gh run download <id> -n player-release-apks -D dist`. Secrets CI : `GOOGLE_SERVICES_JSON`, `ANDROID_KEYSTORE_BASE64` + `ANDROID_KEYSTORE_PASSWORD` + `ANDROID_KEY_ALIAS` + `ANDROID_KEY_PASSWORD`.
- **Signature release stable** : `apps/player/android/app/build.gradle.kts` lit `key.properties` (présent en CI, absent en local → fallback debug). Cert `CN=App Diffusion, O=ALH Groupe, C=FR`. ⚠️ Keystore local `dist/release.keystore` (gitignoré) + mot de passe = **identité de signature permanente, à sauvegarder hors repo** (perte = plus de MAJ par-dessus possible). Les builds CI étant tous signés avec cette clé, les MAJ s'installent over-the-top sans ré-appairage.

## Stats

- **99 commits** sur `main` au handoff
- **Tests** : 25 shared + 4 backoffice + 6 player Dart + 34 pgTAP RLS = **69 total, 100% passing**
- **18 migrations Postgres** + 4 Edge Functions Deno + 5 RPC SECURITY DEFINER

## Dette explicitement reportée (post-MVP)

Les trois items historiques sont **livrés** (mai 2026) — aucune dette reportée à ce jour :
- Suppression gérant → Edge Function `delete-manager` (admin-only, refuse les non-managers, audit `user_deleted`, cascade `auth.users` → `profiles` → `establishment_managers`) + bouton UI gated admin.
- Realtime devices → `public.devices` dans la publication `supabase_realtime` + `StreamProvider` via `.stream()`. Le polling 30s du back office est retiré.
- Purge supervision → job pg_cron `purge-supervision-data` quotidien (03:17 UTC). Le `random() < 0.01` est retiré de `record_heartbeat`.
