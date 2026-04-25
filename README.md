# App de Diffusion

Application de signage pour restaurants et lounge bars :
- Back office Flutter Web
- Player Flutter Android (Phase 5+)
- Backend Supabase + FCM (Phase 5+)

## Documentation
- Design : [docs/superpowers/specs/2026-04-24-app-diffusion-design.md](docs/superpowers/specs/2026-04-24-app-diffusion-design.md)
- Plans : [docs/superpowers/plans/](docs/superpowers/plans/)
- Démo Phase 1 : [docs/phase1-demo.md](docs/phase1-demo.md)
- Démo Phase 2 : [docs/phase2-demo.md](docs/phase2-demo.md)
- Démo Phase 3 : [docs/phase3-demo.md](docs/phase3-demo.md)
- Démo Phase 4 : [docs/phase4-demo.md](docs/phase4-demo.md)
- Démo Phase 5 : [docs/phase5-demo.md](docs/phase5-demo.md)
- Démo Phase 6 : [docs/phase6-demo.md](docs/phase6-demo.md)
- Démo Phase 7 : [docs/phase7-demo.md](docs/phase7-demo.md)

## Structure

```
app-diffusion/
├── apps/
│   └── backoffice/      # Flutter Web (admin + gérant)
├── packages/
│   └── shared/          # Modèles + client Supabase
└── supabase/
    ├── migrations/      # Schéma Postgres versionné
    ├── functions/       # Edge Functions
    └── tests/           # Tests pgTAP des RLS
```

## Prérequis

- Flutter 3.27+ / Dart 3.6+
- Docker Desktop
- Supabase CLI : `npm i -g supabase` ou `scoop install supabase`

## Setup développement

```bash
# 1. Lancer Supabase local
supabase start

# 2. Noter les URLs et clés (affichées par supabase start)
#    API: http://127.0.0.1:54321
#    Studio: http://127.0.0.1:54323
#    anon key / service_role key

# 3. Appliquer les migrations + seed
supabase db reset

# 4. Servir les Edge Functions (dans un autre terminal)
supabase functions serve

# 5. Installer les dépendances Flutter
flutter pub get

# 6. Générer les modèles freezed
cd packages/shared
dart run build_runner build --delete-conflicting-outputs
cd ../..

# 7. Lancer le back office (Chrome)
cd apps/backoffice
flutter run -d chrome \
  --dart-define=SUPABASE_URL=http://127.0.0.1:54321 \
  --dart-define=SUPABASE_ANON_KEY=<anon_key>
```

## Comptes de seed

- **Admin** : admin@local.test / AdminPass123!
- **Gérant** : manager@local.test / ManagerPass123! (lié à "Lounge Plateau")

## Tests

```bash
# Tests unitaires Flutter
flutter test

# Tests RLS Postgres
supabase test db
```

## Production setup (Supabase Cloud)

1. Créer un projet sur https://supabase.com
2. Récupérer `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `JWT_SECRET` depuis **Settings → API**
3. Linker le repo localement :
   ```bash
   supabase link --project-ref <project-ref>
   ```
4. Pousser le schéma :
   ```bash
   supabase db push
   ```
   Cela applique les 18 migrations dans l'ordre (Phases 1 à 7).
5. Pousser les Edge Functions :
   ```bash
   supabase functions deploy create-manager
   supabase functions deploy request-pairing-code
   supabase functions deploy pairing-status
   supabase functions deploy claim-pairing-code
   ```
6. Vérifier dans le dashboard Supabase (**Edge Functions → settings**) que les 4 fonctions ont `verify_jwt = false` (héritage de `config.toml` ; sinon configurer manuellement)
7. Définir le secret `JWT_SECRET` côté Functions :
   ```bash
   supabase secrets set JWT_SECRET=<jwt-secret-from-dashboard>
   ```
8. Créer un compte admin initial via Studio SQL :
   ```sql
   -- Après avoir créé un compte standard via Auth UI
   update public.profiles
      set role = 'admin', full_name = 'Votre Nom'
    where id = (select id from auth.users where email = 'admin@your-domain.com');
   ```

## Build du Player Android (APK)

```bash
cd apps/player
flutter build apk --release \
  --dart-define=SUPABASE_URL=https://<project-ref>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon-key>
```

L'APK est généré dans `build/app/outputs/flutter-apk/app-release.apk`.
- Distribuer via MDM (Mobile Device Management) sur le parc de tablettes
- Ou installer manuellement : `adb install -r app-release.apk`
- Sur Windows, si erreur Gradle "loopback connection" : ajouter `127.0.0.1 localhost` dans `C:\Windows\System32\drivers\etc\hosts`

## Build du Back Office (Flutter Web)

```bash
cd apps/backoffice
flutter build web --release \
  --dart-define=SUPABASE_URL=https://<project-ref>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon-key>
```

Le résultat est dans `build/web/`. Servir via :
- **Vercel** : `vercel --prod build/web`
- **Netlify** : drag-drop du dossier `build/web` ou `netlify deploy --prod --dir=build/web`
- **nginx** : copier `build/web/*` dans le webroot, configurer `try_files $uri $uri/ /index.html;` pour le fallback go_router

## On-boarding admin (premier déploiement)

Après le déploiement complet (DB + Functions + Web + 1 admin créé) :

1. **Login admin** sur le back office déployé
2. **Établissements** → "Nouvel établissement" pour chaque lieu (ex: "Restaurant Centre", "Lounge Plateau")
3. **Gérants** → "Nouveau gérant" pour chaque employé, en cochant les établissements qu'il gère
4. **Appareils** → "Nouvel appareil" (nom + établissement + orientation paysage/portrait) pour chaque écran physique
5. **Installer l'APK** sur la tablette/TV → l'app affiche un code 6 chiffres
6. **Appairer** : dans Appareils, bouton 🔗 (lien) → saisir le code + sélectionner le device préalablement créé
7. **Médias** → "Uploader un média" (vidéos MP4 ≤ 100 Mo, images JPG/PNG/WebP ≤ 10 Mo)
8. **Playlists** → "Nouvelle playlist" → ajouter les médias dans l'ordre, durée image, dates campagne (optionnel)
9. **Publier** la playlist (incrémente `version`)
10. **Appareils** → icône 🎵 sur le device → assigner la playlist
11. La tablette détecte la nouvelle version au prochain polling (≤ 15 min) ou au redémarrage de l'app et se met à jouer

Le **Journal d'audit** (admin only) trace tous les événements : appairage, révocation, publication, création de profil. À consulter régulièrement pour vérifier l'activité du parc.

## Architecture (résumé)

- **Tablette Android** ↔ **Supabase REST/Storage/RPC** : sync polling 15 min via JWT device (HS256, signé avec JWT_SECRET, claim `is_device=true`)
- **Cache local SQLite** (drift) + fichiers dans `getApplicationSupportDirectory()/media/`, purge LRU 2 Go
- **Heartbeat** : `record_heartbeat` RPC toutes les 5 min, met à jour `devices.last_seen_at` + insère dans `device_heartbeats`
- **Logs de lecture** : `record_playback` RPC à la fin de chaque item, queue locale `pending_playback_logs` flushed à chaque heartbeat (résilience offline)
- **Back office** : auto-refresh 30s sur les écrans critiques (Appareils, Audit). Le manager n'a PAS accès aux menus Gérants ni Audit.
- **Sécurité** : RLS Postgres sur toutes les tables. JWT device contient `establishment_id` pour scoper les SELECT. Edge Functions vérifient le rôle admin avant les actions sensibles.
