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
