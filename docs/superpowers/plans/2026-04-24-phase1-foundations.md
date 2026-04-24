# Phase 1 — Fondations — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Poser les fondations du projet : monorepo Flutter, package partagé, Supabase local avec les 3 tables de base (profiles / establishments / establishment_managers) et leurs RLS, back office Flutter Web avec login admin + CRUD établissements + création gérants, CI GitHub Actions.

**Architecture:** Monorepo Flutter workspaces (Dart 3.6+). Un package `shared` héberge les modèles typés (freezed) et le client Supabase. Le back office consomme `shared` et implémente login + 2 features (establishments, managers) via Riverpod + go_router. Backend Supabase local via Docker, migrations SQL versionnées avec RLS active dès la table 1.

**Tech Stack:**
- Flutter 3.27+ / Dart 3.6+ (workspaces)
- `supabase_flutter` (client), `flutter_riverpod` (state), `go_router` (routing), `freezed` + `json_serializable` (models)
- Tests : `flutter_test`, `mocktail`
- Supabase CLI (local dev), Postgres 15 dans Docker
- CI : GitHub Actions (`subosito/flutter-action`, `supabase/setup-cli`)
- Lint : `very_good_analysis`

---

## File Structure (Phase 1)

```
app-diffusion/
├── .github/workflows/ci.yml
├── .gitignore
├── README.md
├── analysis_options.yaml            # lint rules partagées (very_good_analysis)
├── pubspec.yaml                     # Flutter workspace root
│
├── packages/shared/
│   ├── pubspec.yaml
│   ├── analysis_options.yaml
│   ├── lib/
│   │   ├── shared.dart              # barrel file, exports publics
│   │   └── src/
│   │       ├── models/
│   │       │   ├── user_role.dart   # enum admin|manager
│   │       │   ├── profile.dart     # freezed
│   │       │   └── establishment.dart
│   │       ├── supabase/
│   │       │   └── supabase_bootstrap.dart  # Supabase.initialize wrapper
│   │       └── errors/
│   │           └── app_exception.dart
│   └── test/src/models/
│       ├── user_role_test.dart
│       ├── profile_test.dart
│       └── establishment_test.dart
│
├── apps/backoffice/
│   ├── pubspec.yaml
│   ├── analysis_options.yaml
│   ├── lib/
│   │   ├── main.dart
│   │   ├── app.dart
│   │   ├── routing/
│   │   │   └── app_router.dart      # go_router + redirect auth
│   │   ├── theme/
│   │   │   └── app_theme.dart
│   │   ├── features/
│   │   │   ├── auth/
│   │   │   │   ├── data/auth_repository.dart
│   │   │   │   ├── application/auth_controller.dart
│   │   │   │   └── presentation/login_screen.dart
│   │   │   ├── establishments/
│   │   │   │   ├── data/establishments_repository.dart
│   │   │   │   ├── application/establishments_controller.dart
│   │   │   │   └── presentation/
│   │   │   │       ├── establishments_list_screen.dart
│   │   │   │       └── establishment_form_screen.dart
│   │   │   └── managers/
│   │   │       ├── data/managers_repository.dart
│   │   │       ├── application/managers_controller.dart
│   │   │       └── presentation/
│   │   │           ├── managers_list_screen.dart
│   │   │           └── manager_form_screen.dart
│   │   └── shared_widgets/
│   │       └── app_shell.dart       # navigation latérale
│   ├── test/
│   │   ├── features/auth/auth_repository_test.dart
│   │   ├── features/establishments/establishments_repository_test.dart
│   │   └── features/managers/managers_repository_test.dart
│   └── web/index.html
│
└── supabase/
    ├── config.toml                  # généré par supabase init
    ├── migrations/
    │   ├── 20260424100000_profiles.sql
    │   ├── 20260424100100_establishments.sql
    │   ├── 20260424100200_establishment_managers.sql
    │   └── 20260424100300_rls_policies.sql
    ├── seed.sql                     # admin de dev + un établissement de test
    └── tests/
        └── rls_phase1_test.sql      # tests pgTAP des RLS
```

**Principe de découpage** : chaque feature back office a ses 3 couches (data / application / presentation) dans un dossier autonome. Le package `shared` expose **uniquement** ce qui est réutilisable entre player et back office (modèles, bootstrap Supabase). Pas de logique UI dans `shared`.

---

## Task 1 — Initialisation du dépôt git et structure racine

**Files:**
- Create: `.gitignore`
- Create: `README.md`
- Create: `analysis_options.yaml`

- [ ] **Step 1: Initialiser git et créer le .gitignore**

Run :
```bash
cd "D:/App de diffusion"
git init
git branch -M main
```

Créer `.gitignore` :
```gitignore
# Flutter / Dart
.dart_tool/
.packages
.pub-cache/
.pub/
build/
ios/
macos/
linux/
windows/

# IDE
.idea/
.vscode/
*.iml

# Env secrets
.env
.env.local
.env.*.local

# Supabase local
supabase/.branches/
supabase/.temp/

# Generated files
*.g.dart
*.freezed.dart

# OS
.DS_Store
Thumbs.db

# Logs
*.log
```

- [ ] **Step 2: Créer le README minimal**

Créer `README.md` :
```markdown
# App de Diffusion

Application de signage pour restaurants et lounge bars :
- Back office Flutter Web
- Player Flutter Android
- Backend Supabase + FCM

## Documentation
- Design : [docs/superpowers/specs/2026-04-24-app-diffusion-design.md](docs/superpowers/specs/2026-04-24-app-diffusion-design.md)
- Plans : [docs/superpowers/plans/](docs/superpowers/plans/)

## Setup local
Voir la section "Phase 1" dans ce README après complétion du plan Phase 1.
```

- [ ] **Step 3: Créer les lint rules partagées**

Créer `analysis_options.yaml` (racine) :
```yaml
include: package:very_good_analysis/analysis_options.yaml

analyzer:
  exclude:
    - "**/*.g.dart"
    - "**/*.freezed.dart"
    - "build/**"

linter:
  rules:
    public_member_api_docs: false   # trop strict pour un projet applicatif
    lines_longer_than_80_chars: false
```

- [ ] **Step 4: Commit initial**

```bash
git add .gitignore README.md analysis_options.yaml docs/
git commit -m "chore: initial repo, gitignore, shared lint rules"
```

---

## Task 2 — Workspace Flutter et package `shared`

**Files:**
- Create: `pubspec.yaml` (workspace root)
- Create: `packages/shared/pubspec.yaml`
- Create: `packages/shared/analysis_options.yaml`
- Create: `packages/shared/lib/shared.dart`

- [ ] **Step 1: Créer le pubspec workspace racine**

Créer `pubspec.yaml` :
```yaml
name: app_diffusion_workspace
publish_to: none

environment:
  sdk: ^3.6.0

workspace:
  - packages/shared
  - apps/backoffice
```

- [ ] **Step 2: Créer le pubspec du package shared**

Créer `packages/shared/pubspec.yaml` :
```yaml
name: shared
description: Modèles partagés et client Supabase pour app-diffusion.
publish_to: none
version: 0.1.0

environment:
  sdk: ^3.6.0
  flutter: ">=3.27.0"

resolution: workspace

dependencies:
  flutter:
    sdk: flutter
  freezed_annotation: ^2.4.4
  json_annotation: ^4.9.0
  supabase_flutter: ^2.8.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  build_runner: ^2.4.13
  freezed: ^2.5.7
  json_serializable: ^6.9.0
  very_good_analysis: ^6.0.0
  mocktail: ^1.0.4
```

- [ ] **Step 3: Analysis options pour shared**

Créer `packages/shared/analysis_options.yaml` :
```yaml
include: ../../analysis_options.yaml
```

- [ ] **Step 4: Créer le barrel file**

Créer `packages/shared/lib/shared.dart` :
```dart
// Public API du package shared.
// Les exports seront ajoutés au fur et à mesure des tâches suivantes.
library shared;
```

- [ ] **Step 5: Vérifier que le workspace se résout**

Run :
```bash
flutter pub get
```
Expected : message "Resolving dependencies in workspace..." sans erreur. Un fichier `pubspec.lock` est créé à la racine.

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml packages/
git commit -m "chore: scaffold workspace + empty shared package"
```

---

## Task 3 — Modèle `UserRole` (enum) avec test

**Files:**
- Create: `packages/shared/lib/src/models/user_role.dart`
- Create: `packages/shared/test/src/models/user_role_test.dart`
- Modify: `packages/shared/lib/shared.dart`

- [ ] **Step 1: Écrire le test d'abord**

Créer `packages/shared/test/src/models/user_role_test.dart` :
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';

void main() {
  group('UserRole', () {
    test('fromString parses admin', () {
      expect(UserRole.fromString('admin'), UserRole.admin);
    });

    test('fromString parses manager', () {
      expect(UserRole.fromString('manager'), UserRole.manager);
    });

    test('fromString throws on unknown', () {
      expect(
        () => UserRole.fromString('pirate'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('dbValue returns lowercase snake', () {
      expect(UserRole.admin.dbValue, 'admin');
      expect(UserRole.manager.dbValue, 'manager');
    });
  });
}
```

- [ ] **Step 2: Run — le test doit échouer (fichier user_role.dart n'existe pas)**

Run :
```bash
cd packages/shared
flutter test test/src/models/user_role_test.dart
```
Expected : FAIL avec `Error: Type 'UserRole' not found.` (ou équivalent).

- [ ] **Step 3: Implémentation minimale**

Créer `packages/shared/lib/src/models/user_role.dart` :
```dart
enum UserRole {
  admin,
  manager;

  String get dbValue => name;

  static UserRole fromString(String value) {
    return switch (value) {
      'admin' => UserRole.admin,
      'manager' => UserRole.manager,
      _ => throw ArgumentError.value(value, 'value', 'unknown role'),
    };
  }
}
```

- [ ] **Step 4: Exposer via le barrel**

Modifier `packages/shared/lib/shared.dart` :
```dart
library shared;

export 'src/models/user_role.dart';
```

- [ ] **Step 5: Run — tous les tests doivent passer**

Run :
```bash
flutter test
```
Expected : `+4 -0: All tests passed!`

- [ ] **Step 6: Commit**

```bash
git add packages/shared/
git commit -m "feat(shared): add UserRole enum"
```

---

## Task 4 — Modèles `Profile` et `Establishment` (freezed) avec tests

**Files:**
- Create: `packages/shared/lib/src/models/profile.dart`
- Create: `packages/shared/lib/src/models/establishment.dart`
- Create: `packages/shared/test/src/models/profile_test.dart`
- Create: `packages/shared/test/src/models/establishment_test.dart`
- Modify: `packages/shared/lib/shared.dart`

- [ ] **Step 1: Écrire les tests de Profile d'abord**

Créer `packages/shared/test/src/models/profile_test.dart` :
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';

void main() {
  group('Profile', () {
    const json = {
      'id': '11111111-1111-1111-1111-111111111111',
      'role': 'admin',
      'full_name': 'Alice',
    };

    test('fromJson parses admin profile', () {
      final p = Profile.fromJson(json);
      expect(p.id, '11111111-1111-1111-1111-111111111111');
      expect(p.role, UserRole.admin);
      expect(p.fullName, 'Alice');
    });

    test('toJson produces snake_case', () {
      const p = Profile(
        id: 'x',
        role: UserRole.manager,
        fullName: 'Bob',
      );
      expect(p.toJson(), {
        'id': 'x',
        'role': 'manager',
        'full_name': 'Bob',
      });
    });

    test('equality by value', () {
      const a = Profile(id: 'x', role: UserRole.admin, fullName: 'A');
      const b = Profile(id: 'x', role: UserRole.admin, fullName: 'A');
      expect(a, b);
    });
  });
}
```

- [ ] **Step 2: Écrire les tests d'Establishment**

Créer `packages/shared/test/src/models/establishment_test.dart` :
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';

void main() {
  group('Establishment', () {
    test('fromJson parses required fields and timezone', () {
      final e = Establishment.fromJson({
        'id': 'e1',
        'name': 'Lounge Plateau',
        'timezone': 'Africa/Yaounde',
      });
      expect(e.id, 'e1');
      expect(e.name, 'Lounge Plateau');
      expect(e.timezone, 'Africa/Yaounde');
    });

    test('defaults timezone to UTC when missing', () {
      final e = Establishment.fromJson({'id': 'e1', 'name': 'Resto'});
      expect(e.timezone, 'UTC');
    });
  });
}
```

- [ ] **Step 3: Run — doit échouer (Profile/Establishment inconnus)**

Run :
```bash
flutter test
```
Expected : FAIL avec "Profile not found" / "Establishment not found".

- [ ] **Step 4: Implémenter Profile avec freezed**

Créer `packages/shared/lib/src/models/profile.dart` :
```dart
import 'package:freezed_annotation/freezed_annotation.dart';
import 'user_role.dart';

part 'profile.freezed.dart';
part 'profile.g.dart';

@freezed
class Profile with _$Profile {
  const factory Profile({
    required String id,
    required UserRole role,
    required String fullName,
  }) = _Profile;

  factory Profile.fromJson(Map<String, dynamic> json) =>
      _$ProfileFromJson(json);
}
```

- [ ] **Step 5: Implémenter Establishment avec freezed**

Créer `packages/shared/lib/src/models/establishment.dart` :
```dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'establishment.freezed.dart';
part 'establishment.g.dart';

@freezed
class Establishment with _$Establishment {
  const factory Establishment({
    required String id,
    required String name,
    @Default('UTC') String timezone,
  }) = _Establishment;

  factory Establishment.fromJson(Map<String, dynamic> json) =>
      _$EstablishmentFromJson(json);
}
```

- [ ] **Step 6: Exporter**

Modifier `packages/shared/lib/shared.dart` :
```dart
library shared;

export 'src/models/establishment.dart';
export 'src/models/profile.dart';
export 'src/models/user_role.dart';
```

- [ ] **Step 7: Générer les fichiers freezed/json**

Run (depuis `packages/shared/`) :
```bash
dart run build_runner build --delete-conflicting-outputs
```
Expected : `[INFO] Succeeded after ...`. Les fichiers `profile.freezed.dart`, `profile.g.dart`, `establishment.freezed.dart`, `establishment.g.dart` sont créés. **Ajouter un convertisseur JSON pour `UserRole`** car l'enum stocke `admin`/`manager` directement — si `json_serializable` refuse l'enum, ajouter dans `profile.dart` juste avant la classe :

```dart
class _UserRoleConverter implements JsonConverter<UserRole, String> {
  const _UserRoleConverter();
  @override
  UserRole fromJson(String json) => UserRole.fromString(json);
  @override
  String toJson(UserRole object) => object.dbValue;
}
```

Puis annoter le champ `role` :
```dart
@_UserRoleConverter() required UserRole role,
```

Régénérer :
```bash
dart run build_runner build --delete-conflicting-outputs
```

- [ ] **Step 8: Run — les tests doivent passer**

Run :
```bash
flutter test
```
Expected : `+9 -0: All tests passed!` (les 4 UserRole + 3 Profile + 2 Establishment).

- [ ] **Step 9: Commit**

```bash
git add packages/shared/
git commit -m "feat(shared): add Profile and Establishment models with freezed"
```

---

## Task 5 — Bootstrap Supabase partagé + AppException

**Files:**
- Create: `packages/shared/lib/src/supabase/supabase_bootstrap.dart`
- Create: `packages/shared/lib/src/errors/app_exception.dart`
- Create: `packages/shared/test/src/errors/app_exception_test.dart`
- Modify: `packages/shared/lib/shared.dart`

- [ ] **Step 1: Test AppException**

Créer `packages/shared/test/src/errors/app_exception_test.dart` :
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';

void main() {
  group('AppException', () {
    test('stores message and optional cause', () {
      final e = AppException('boom', cause: 'detail');
      expect(e.message, 'boom');
      expect(e.cause, 'detail');
      expect(e.toString(), contains('boom'));
    });

    test('toString without cause', () {
      final e = AppException('boom');
      expect(e.toString(), 'AppException: boom');
    });
  });
}
```

- [ ] **Step 2: Run — doit échouer**

```bash
flutter test
```
Expected : FAIL.

- [ ] **Step 3: Implémenter AppException**

Créer `packages/shared/lib/src/errors/app_exception.dart` :
```dart
class AppException implements Exception {
  AppException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => cause == null
      ? 'AppException: $message'
      : 'AppException: $message (cause: $cause)';
}
```

- [ ] **Step 4: Bootstrap Supabase**

Créer `packages/shared/lib/src/supabase/supabase_bootstrap.dart` :
```dart
import 'package:supabase_flutter/supabase_flutter.dart';

/// Configuration minimale Supabase pour les apps.
/// Les clés viennent du `--dart-define` pour éviter de les commiter.
class SupabaseConfig {
  const SupabaseConfig({required this.url, required this.anonKey});

  factory SupabaseConfig.fromDefines() {
    const url = String.fromEnvironment('SUPABASE_URL');
    const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
    if (url.isEmpty || anonKey.isEmpty) {
      throw StateError(
        'SUPABASE_URL and SUPABASE_ANON_KEY must be passed via --dart-define.',
      );
    }
    return const SupabaseConfig(url: url, anonKey: anonKey);
  }

  final String url;
  final String anonKey;
}

Future<SupabaseClient> initSupabase(SupabaseConfig config) async {
  await Supabase.initialize(
    url: config.url,
    anonKey: config.anonKey,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );
  return Supabase.instance.client;
}
```

- [ ] **Step 5: Mettre à jour le barrel**

Modifier `packages/shared/lib/shared.dart` :
```dart
library shared;

export 'package:supabase_flutter/supabase_flutter.dart'
    show SupabaseClient, AuthException, PostgrestException, User, Session;

export 'src/errors/app_exception.dart';
export 'src/models/establishment.dart';
export 'src/models/profile.dart';
export 'src/models/user_role.dart';
export 'src/supabase/supabase_bootstrap.dart';
```

- [ ] **Step 6: Tests passent**

```bash
flutter test
```
Expected : `+11 -0: All tests passed!`

- [ ] **Step 7: Commit**

```bash
git add packages/shared/
git commit -m "feat(shared): add Supabase bootstrap and AppException"
```

---

## Task 6 — Initialiser Supabase local + premiere migration (profiles)

**Files:**
- Create: `supabase/config.toml` (généré par CLI)
- Create: `supabase/migrations/20260424100000_profiles.sql`

**Prérequis** : Docker Desktop installé et démarré. Supabase CLI installé (`npm i -g supabase` ou `scoop install supabase`).

- [ ] **Step 1: Initialiser Supabase**

Run (depuis la racine du repo) :
```bash
supabase init
```
Expected : création du dossier `supabase/` avec `config.toml`, `seed.sql`.

- [ ] **Step 2: Démarrer Supabase local**

Run :
```bash
supabase start
```
Expected : après 1-2 min, sortie avec URLs (API `http://127.0.0.1:54321`, DB, Studio `http://127.0.0.1:54323`, anon/service_role keys). **Noter les clés `anon key` et `service_role key`** pour les tâches suivantes.

- [ ] **Step 3: Créer la migration profiles**

Créer `supabase/migrations/20260424100000_profiles.sql` :
```sql
-- Profil applicatif lié à auth.users Supabase.
-- Créé automatiquement à l'inscription via trigger on_auth_user_created.

create type user_role as enum ('admin', 'manager');

create table public.profiles (
    id uuid primary key references auth.users(id) on delete cascade,
    role user_role not null default 'manager',
    full_name text not null default '',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

-- Trigger updated_at
create or replace function public.tg_set_updated_at()
returns trigger language plpgsql as $$
begin
    new.updated_at = now();
    return new;
end $$;

create trigger profiles_set_updated_at
    before update on public.profiles
    for each row execute function public.tg_set_updated_at();

-- Auto-create profile on signup (rôle par défaut: manager).
-- L'admin peut promouvoir ensuite via UPDATE direct (admin-only RLS).
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
    insert into public.profiles (id, full_name)
    values (new.id, coalesce(new.raw_user_meta_data->>'full_name', ''));
    return new;
end $$;

create trigger on_auth_user_created
    after insert on auth.users
    for each row execute function public.handle_new_user();

-- RLS
alter table public.profiles enable row level security;

-- Un utilisateur peut lire son propre profil
create policy profiles_self_select on public.profiles
    for select using (id = auth.uid());

-- Un admin peut tout lire
create policy profiles_admin_select on public.profiles
    for select using (
        exists (
            select 1 from public.profiles p
            where p.id = auth.uid() and p.role = 'admin'
        )
    );

-- Seul un admin peut INSERT/UPDATE/DELETE des profils
create policy profiles_admin_write on public.profiles
    for all using (
        exists (
            select 1 from public.profiles p
            where p.id = auth.uid() and p.role = 'admin'
        )
    ) with check (
        exists (
            select 1 from public.profiles p
            where p.id = auth.uid() and p.role = 'admin'
        )
    );
```

- [ ] **Step 4: Appliquer la migration**

Run :
```bash
supabase db reset
```
Expected : réinitialise la DB, applique les migrations, puis le seed. Doit se terminer par "Finished supabase db reset on branch main".

- [ ] **Step 5: Vérifier dans le Studio**

Ouvrir `http://127.0.0.1:54323` dans un navigateur → Table Editor → voir `public.profiles` avec les colonnes attendues. RLS activé (cadenas).

- [ ] **Step 6: Commit**

```bash
git add supabase/
git commit -m "feat(db): add profiles table with RLS and auto-create trigger"
```

---

## Task 7 — Migration establishments + establishment_managers

**Files:**
- Create: `supabase/migrations/20260424100100_establishments.sql`
- Create: `supabase/migrations/20260424100200_establishment_managers.sql`

- [ ] **Step 1: Migration establishments**

Créer `supabase/migrations/20260424100100_establishments.sql` :
```sql
create table public.establishments (
    id uuid primary key default gen_random_uuid(),
    name text not null,
    timezone text not null default 'UTC',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint establishments_name_not_empty check (length(trim(name)) > 0)
);

create trigger establishments_set_updated_at
    before update on public.establishments
    for each row execute function public.tg_set_updated_at();

alter table public.establishments enable row level security;

-- Helper function : l'utilisateur courant est-il admin ?
create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
    select exists (
        select 1 from public.profiles p
        where p.id = auth.uid() and p.role = 'admin'
    );
$$;

-- Admin = tout
create policy establishments_admin_all on public.establishments
    for all using (public.is_admin()) with check (public.is_admin());

-- Les gérants liés voient leurs établissements (policy ajoutée après la table
-- establishment_managers dans la migration suivante).
```

- [ ] **Step 2: Migration establishment_managers**

Créer `supabase/migrations/20260424100200_establishment_managers.sql` :
```sql
create table public.establishment_managers (
    establishment_id uuid not null references public.establishments(id) on delete cascade,
    profile_id uuid not null references public.profiles(id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key (establishment_id, profile_id)
);

alter table public.establishment_managers enable row level security;

-- Admin = tout
create policy em_admin_all on public.establishment_managers
    for all using (public.is_admin()) with check (public.is_admin());

-- Un gérant peut lire ses propres affectations
create policy em_self_select on public.establishment_managers
    for select using (profile_id = auth.uid());

-- Policy SELECT pour establishments : gérant voit ses établissements
create policy establishments_manager_select on public.establishments
    for select using (
        exists (
            select 1 from public.establishment_managers em
            where em.establishment_id = public.establishments.id
              and em.profile_id = auth.uid()
        )
    );
```

- [ ] **Step 3: Appliquer et vérifier**

Run :
```bash
supabase db reset
```
Expected : 3 migrations appliquées sans erreur.

Ouvrir Studio → voir `establishments` et `establishment_managers`.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/
git commit -m "feat(db): add establishments and establishment_managers with RLS"
```

---

## Task 8 — Seed de développement (admin + établissement + gérant)

**Files:**
- Modify: `supabase/seed.sql`

- [ ] **Step 1: Remplir le seed**

Remplacer le contenu de `supabase/seed.sql` par :
```sql
-- Seed de développement local. NE PAS utiliser en prod.

-- Admin de dev : email admin@local.test / password AdminPass123!
-- L'insertion directe dans auth.users suit le pattern Supabase local.
insert into auth.users (
    id, instance_id, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, aud, role,
    created_at, updated_at
) values (
    '00000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000000',
    'admin@local.test',
    crypt('AdminPass123!', gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}',
    '{"full_name":"Dev Admin"}',
    'authenticated', 'authenticated',
    now(), now()
) on conflict (id) do nothing;

-- Forcer le rôle admin (le trigger a créé un manager par défaut)
update public.profiles
   set role = 'admin', full_name = 'Dev Admin'
 where id = '00000000-0000-0000-0000-000000000001';

-- Gérant de dev : manager@local.test / ManagerPass123!
insert into auth.users (
    id, instance_id, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, aud, role,
    created_at, updated_at
) values (
    '00000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000000',
    'manager@local.test',
    crypt('ManagerPass123!', gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}',
    '{"full_name":"Dev Manager"}',
    'authenticated', 'authenticated',
    now(), now()
) on conflict (id) do nothing;

update public.profiles
   set full_name = 'Dev Manager'
 where id = '00000000-0000-0000-0000-000000000002';

-- Établissement de démo
insert into public.establishments (id, name, timezone) values
    ('11111111-1111-1111-1111-111111111111', 'Lounge Plateau', 'Africa/Yaounde')
on conflict (id) do nothing;

-- Rattacher le gérant
insert into public.establishment_managers (establishment_id, profile_id) values
    ('11111111-1111-1111-1111-111111111111',
     '00000000-0000-0000-0000-000000000002')
on conflict do nothing;
```

- [ ] **Step 2: Appliquer**

```bash
supabase db reset
```
Expected : DB réinit + seed exécuté sans erreur.

- [ ] **Step 3: Vérifier dans Studio**

- `auth.users` contient 2 lignes.
- `public.profiles` contient 2 lignes, une en `admin`, l'autre en `manager`.
- `public.establishments` contient 1 ligne.
- `public.establishment_managers` contient 1 ligne.

- [ ] **Step 4: Commit**

```bash
git add supabase/seed.sql
git commit -m "feat(db): seed dev admin, manager and demo establishment"
```

---

## Task 9 — Tests RLS SQL (pgTAP)

**Files:**
- Create: `supabase/tests/rls_phase1_test.sql`

- [ ] **Step 1: Écrire les tests pgTAP**

Créer `supabase/tests/rls_phase1_test.sql` :
```sql
begin;

create extension if not exists pgtap;

select plan(6);

-- Utiliser les UUIDs du seed
set local role authenticated;

-- 1) Un gérant ne peut PAS voir tous les profils
set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-000000000002","role":"authenticated"}';
select results_eq(
    $$ select count(*) from public.profiles $$,
    $$ values (1::bigint) $$,
    'manager sees only his own profile'
);

-- 2) Un gérant ne peut voir QUE son établissement
select results_eq(
    $$ select count(*) from public.establishments $$,
    $$ values (1::bigint) $$,
    'manager sees exactly one establishment'
);

-- 3) Un gérant ne peut PAS créer un établissement
prepare manager_insert as
    insert into public.establishments (name) values ('Forbidden');
select throws_ok('manager_insert', '42501', null, 'manager insert blocked');

-- 4) Admin voit tous les profils
set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}';
select results_eq(
    $$ select count(*) from public.profiles $$,
    $$ values (2::bigint) $$,
    'admin sees all profiles'
);

-- 5) Admin voit tous les établissements
select results_eq(
    $$ select count(*) from public.establishments $$,
    $$ values (1::bigint) $$,
    'admin sees all establishments'
);

-- 6) Admin peut créer un établissement
insert into public.establishments (name) values ('Test Admin Insert');
select pass('admin can create establishments');

select * from finish();

rollback;
```

- [ ] **Step 2: Installer pgTAP dans Supabase local**

Run :
```bash
supabase db reset
```

Puis ajouter l'extension via migration. Créer une nouvelle migration :
`supabase/migrations/20260424100300_enable_pgtap.sql` :
```sql
create extension if not exists pgtap with schema extensions;
```

Re-run :
```bash
supabase db reset
```

- [ ] **Step 3: Exécuter les tests**

Run :
```bash
supabase db test
```
Expected : `All tests passed (6/6)`. Si échec, ajuster les policies et relancer.

- [ ] **Step 4: Commit**

```bash
git add supabase/tests/ supabase/migrations/20260424100300_enable_pgtap.sql
git commit -m "test(db): add pgTAP RLS tests for phase 1"
```

---

## Task 10 — Scaffold du back office Flutter Web

**Files:**
- Create: `apps/backoffice/pubspec.yaml`
- Create: `apps/backoffice/analysis_options.yaml`
- Create: `apps/backoffice/lib/main.dart`
- Create: `apps/backoffice/lib/app.dart`
- Create: `apps/backoffice/lib/theme/app_theme.dart`
- Create: `apps/backoffice/web/index.html` (généré)

- [ ] **Step 1: Créer l'app Flutter web**

Run (depuis la racine) :
```bash
flutter create --platforms=web --project-name backoffice apps/backoffice
```
Expected : génère `apps/backoffice/` avec `lib/main.dart`, `web/`, etc.

- [ ] **Step 2: Remplacer le pubspec par la version workspace**

Remplacer `apps/backoffice/pubspec.yaml` par :
```yaml
name: backoffice
description: Back office Flutter Web pour app-diffusion.
publish_to: none
version: 0.1.0

environment:
  sdk: ^3.6.0
  flutter: ">=3.27.0"

resolution: workspace

dependencies:
  flutter:
    sdk: flutter
  shared:
    path: ../../packages/shared
  flutter_riverpod: ^2.6.1
  go_router: ^14.6.2
  supabase_flutter: ^2.8.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  very_good_analysis: ^6.0.0
  mocktail: ^1.0.4
```

- [ ] **Step 3: analysis_options.yaml**

Créer `apps/backoffice/analysis_options.yaml` :
```yaml
include: ../../analysis_options.yaml
```

- [ ] **Step 4: Theme minimal**

Créer `apps/backoffice/lib/theme/app_theme.dart` :
```dart
import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
    );
  }
}
```

- [ ] **Step 5: main.dart avec Supabase init**

Remplacer `apps/backoffice/lib/main.dart` par :
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = SupabaseConfig.fromDefines();
  await initSupabase(config);
  runApp(const ProviderScope(child: BackofficeApp()));
}
```

- [ ] **Step 6: app.dart minimal (sans routing encore)**

Créer `apps/backoffice/lib/app.dart` :
```dart
import 'package:flutter/material.dart';

import 'theme/app_theme.dart';

class BackofficeApp extends StatelessWidget {
  const BackofficeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'App Diffusion — Back Office',
      theme: AppTheme.light(),
      home: const Scaffold(
        body: Center(child: Text('App Diffusion — Back Office (Phase 1)')),
      ),
    );
  }
}
```

- [ ] **Step 7: Lancer le web pour vérifier**

Run :
```bash
flutter run -d chrome \
  --dart-define=SUPABASE_URL=http://127.0.0.1:54321 \
  --dart-define=SUPABASE_ANON_KEY=<anon_key_depuis_supabase_start>
```
Expected : Chrome ouvre sur l'app qui affiche "App Diffusion — Back Office (Phase 1)".

**Noter la anon key dans un fichier `.env.local` (déjà gitignored)** pour réutilisation :
```
SUPABASE_URL=http://127.0.0.1:54321
SUPABASE_ANON_KEY=<copier depuis supabase start>
```

- [ ] **Step 8: Commit**

```bash
git add apps/backoffice/
git commit -m "feat(backoffice): scaffold Flutter Web app with Supabase bootstrap"
```

---

## Task 11 — Feature Auth : repository avec test

**Files:**
- Create: `apps/backoffice/lib/features/auth/data/auth_repository.dart`
- Create: `apps/backoffice/test/features/auth/auth_repository_test.dart`

- [ ] **Step 1: Écrire les tests (mocktail)**

Créer `apps/backoffice/test/features/auth/auth_repository_test.dart` :
```dart
import 'package:backoffice/features/auth/data/auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared/shared.dart';

class _MockSupabaseClient extends Mock implements SupabaseClient {}
class _MockGoTrueClient extends Mock implements GoTrueClient {}

void main() {
  late _MockSupabaseClient client;
  late _MockGoTrueClient auth;
  late AuthRepository repo;

  setUp(() {
    client = _MockSupabaseClient();
    auth = _MockGoTrueClient();
    when(() => client.auth).thenReturn(auth);
    repo = AuthRepository(client);
  });

  group('signIn', () {
    test('returns session on success', () async {
      final fakeSession = Session(
        accessToken: 'a',
        tokenType: 'bearer',
        user: User(
          id: 'u1',
          appMetadata: const {},
          userMetadata: const {},
          aud: 'authenticated',
          createdAt: DateTime.now().toIso8601String(),
        ),
      );
      when(() => auth.signInWithPassword(
        email: any(named: 'email'),
        password: any(named: 'password'),
      )).thenAnswer(
        (_) async => AuthResponse(session: fakeSession, user: fakeSession.user),
      );

      final result = await repo.signIn(
        email: 'admin@local.test',
        password: 'x',
      );
      expect(result.user.id, 'u1');
    });

    test('wraps AuthException into AppException', () async {
      when(() => auth.signInWithPassword(
        email: any(named: 'email'),
        password: any(named: 'password'),
      )).thenThrow(const AuthException('invalid login'));

      expect(
        () => repo.signIn(email: 'x', password: 'y'),
        throwsA(isA<AppException>()),
      );
    });
  });

  test('signOut calls auth.signOut', () async {
    when(() => auth.signOut()).thenAnswer((_) async {});
    await repo.signOut();
    verify(() => auth.signOut()).called(1);
  });
}
```

- [ ] **Step 2: Run — doit échouer (fichier inexistant)**

```bash
cd apps/backoffice
flutter test test/features/auth/auth_repository_test.dart
```
Expected : FAIL.

- [ ] **Step 3: Implémenter**

Créer `apps/backoffice/lib/features/auth/data/auth_repository.dart` :
```dart
import 'package:shared/shared.dart';

class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    try {
      return await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );
    } on AuthException catch (e) {
      throw AppException('Échec de la connexion', cause: e.message);
    }
  }

  Future<void> signOut() => _client.auth.signOut();

  Stream<AuthState> onAuthStateChange() => _client.auth.onAuthStateChange;

  Session? get currentSession => _client.auth.currentSession;
}
```

- [ ] **Step 4: Tests passent**

```bash
flutter test
```
Expected : `+3 -0: All tests passed!` (en plus des tests shared si relancés).

- [ ] **Step 5: Commit**

```bash
git add apps/backoffice/
git commit -m "feat(backoffice): add AuthRepository with tests"
```

---

## Task 12 — Auth : controller Riverpod + écran login

**Files:**
- Create: `apps/backoffice/lib/features/auth/application/auth_controller.dart`
- Create: `apps/backoffice/lib/features/auth/presentation/login_screen.dart`

- [ ] **Step 1: AuthController (provider Riverpod)**

Créer `apps/backoffice/lib/features/auth/application/auth_controller.dart` :
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../data/auth_repository.dart';

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(supabaseClientProvider));
});

final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(authRepositoryProvider).onAuthStateChange();
});

final currentSessionProvider = Provider<Session?>((ref) {
  final asyncState = ref.watch(authStateProvider);
  return asyncState.maybeWhen(
    data: (s) => s.session,
    orElse: () => ref.watch(authRepositoryProvider).currentSession,
  );
});
```

- [ ] **Step 2: LoginScreen**

Créer `apps/backoffice/lib/features/auth/presentation/login_screen.dart` :
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../application/auth_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).signIn(
            email: _emailCtrl.text.trim(),
            password: _passwordCtrl.text,
          );
    } on AppException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'App Diffusion — Back Office',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _emailCtrl,
                    decoration: const InputDecoration(labelText: 'Email'),
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordCtrl,
                    decoration: const InputDecoration(labelText: 'Mot de passe'),
                    obscureText: true,
                    onSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 16),
                  if (_error != null)
                    Text(
                      _error!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(
                            height: 18, width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Se connecter'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }
}
```

- [ ] **Step 3: Commit**

```bash
git add apps/backoffice/lib/features/auth/
git commit -m "feat(backoffice): add auth controller and login screen"
```

---

## Task 13 — Routing (go_router) avec redirect auth

**Files:**
- Create: `apps/backoffice/lib/routing/app_router.dart`
- Create: `apps/backoffice/lib/shared_widgets/app_shell.dart`
- Modify: `apps/backoffice/lib/app.dart`

- [ ] **Step 1: Shell de navigation**

Créer `apps/backoffice/lib/shared_widgets/app_shell.dart` :
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/application/auth_controller.dart';

class AppShell extends ConsumerWidget {
  const AppShell({required this.child, required this.location, super.key});

  final Widget child;
  final String location;

  static const _destinations = [
    _Dest('/establishments', Icons.store_outlined, 'Établissements'),
    _Dest('/managers', Icons.people_outline, 'Gérants'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = _destinations.indexWhere(
      (d) => location.startsWith(d.path),
    );
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: selected < 0 ? 0 : selected,
            onDestinationSelected: (i) => context.go(_destinations[i].path),
            labelType: NavigationRailLabelType.all,
            destinations: [
              for (final d in _destinations)
                NavigationRailDestination(
                  icon: Icon(d.icon),
                  label: Text(d.label),
                ),
            ],
            trailing: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: IconButton(
                icon: const Icon(Icons.logout),
                tooltip: 'Se déconnecter',
                onPressed: () async {
                  await ref.read(authRepositoryProvider).signOut();
                },
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _Dest {
  const _Dest(this.path, this.icon, this.label);
  final String path;
  final IconData icon;
  final String label;
}
```

- [ ] **Step 2: Router avec redirect**

Créer `apps/backoffice/lib/routing/app_router.dart` :
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/application/auth_controller.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/establishments/presentation/establishments_list_screen.dart';
import '../features/establishments/presentation/establishment_form_screen.dart';
import '../features/managers/presentation/managers_list_screen.dart';
import '../features/managers/presentation/manager_form_screen.dart';
import '../shared_widgets/app_shell.dart';

final goRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/establishments',
    redirect: (context, state) {
      final session = ref.read(currentSessionProvider);
      final loggedIn = session != null;
      final onLogin = state.matchedLocation == '/login';
      if (!loggedIn && !onLogin) return '/login';
      if (loggedIn && onLogin) return '/establishments';
      return null;
    },
    refreshListenable: _AuthRefreshNotifier(ref),
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(
            path: '/establishments',
            builder: (_, __) => const EstablishmentsListScreen(),
            routes: [
              GoRoute(
                path: 'new',
                builder: (_, __) => const EstablishmentFormScreen(),
              ),
              GoRoute(
                path: ':id',
                builder: (_, s) => EstablishmentFormScreen(
                  establishmentId: s.pathParameters['id'],
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/managers',
            builder: (_, __) => const ManagersListScreen(),
            routes: [
              GoRoute(
                path: 'new',
                builder: (_, __) => const ManagerFormScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

class _AuthRefreshNotifier extends ChangeNotifier {
  _AuthRefreshNotifier(Ref ref) {
    _sub = ref.listen<AsyncValue>(
      authStateProvider,
      (_, __) => notifyListeners(),
    );
  }
  late final ProviderSubscription _sub;

  @override
  void dispose() {
    _sub.close();
    super.dispose();
  }
}
```

Import manquant au début :
```dart
import 'package:flutter/foundation.dart';
```

- [ ] **Step 3: Brancher le router dans app.dart**

Remplacer `apps/backoffice/lib/app.dart` par :
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'routing/app_router.dart';
import 'theme/app_theme.dart';

class BackofficeApp extends ConsumerWidget {
  const BackofficeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(goRouterProvider);
    return MaterialApp.router(
      title: 'App Diffusion — Back Office',
      theme: AppTheme.light(),
      routerConfig: router,
    );
  }
}
```

- [ ] **Step 4: Commit (écrans placeholder viennent après)**

```bash
git add apps/backoffice/lib/
git commit -m "feat(backoffice): add go_router with auth redirect and app shell"
```

---

## Task 14 — Feature Establishments : repository avec tests

**Files:**
- Create: `apps/backoffice/lib/features/establishments/data/establishments_repository.dart`
- Create: `apps/backoffice/test/features/establishments/establishments_repository_test.dart`

- [ ] **Step 1: Tests**

Créer `apps/backoffice/test/features/establishments/establishments_repository_test.dart` :
```dart
import 'package:backoffice/features/establishments/data/establishments_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared/shared.dart';

class _MockClient extends Mock implements SupabaseClient {}
class _MockBuilder extends Mock implements SupabaseQueryBuilder {}
class _MockSelectBuilder extends Mock implements PostgrestFilterBuilder<List<Map<String, dynamic>>> {}

void main() {
  late _MockClient client;
  late EstablishmentsRepository repo;

  setUp(() {
    client = _MockClient();
    repo = EstablishmentsRepository(client);
  });

  test('list returns list of establishments ordered by name', () async {
    final builder = _MockBuilder();
    final select = _MockSelectBuilder();
    when(() => client.from('establishments')).thenReturn(builder);
    when(() => builder.select()).thenReturn(select);
    when(() => select.order('name')).thenAnswer((_) async => [
      {'id': 'e1', 'name': 'Alpha', 'timezone': 'UTC'},
      {'id': 'e2', 'name': 'Bravo', 'timezone': 'UTC'},
    ]);

    final result = await repo.list();
    expect(result, hasLength(2));
    expect(result.first.name, 'Alpha');
  });
}
```

**Note** : l'API Supabase utilise des builders chaînés parfois difficiles à mocker. Si mocker devient trop compliqué, tester directement contre Supabase local dans un test d'intégration séparé. Pour ce plan, on garde le test unitaire simple.

- [ ] **Step 2: Run — doit échouer**

```bash
flutter test test/features/establishments/
```
Expected : FAIL.

- [ ] **Step 3: Implémenter**

Créer `apps/backoffice/lib/features/establishments/data/establishments_repository.dart` :
```dart
import 'package:shared/shared.dart';

class EstablishmentsRepository {
  EstablishmentsRepository(this._client);
  final SupabaseClient _client;

  Future<List<Establishment>> list() async {
    try {
      final rows = await _client.from('establishments').select().order('name');
      return rows.map<Establishment>(Establishment.fromJson).toList();
    } on PostgrestException catch (e) {
      throw AppException('Lecture des établissements échouée', cause: e.message);
    }
  }

  Future<Establishment> create({
    required String name,
    required String timezone,
  }) async {
    try {
      final row = await _client
          .from('establishments')
          .insert({'name': name, 'timezone': timezone})
          .select()
          .single();
      return Establishment.fromJson(row);
    } on PostgrestException catch (e) {
      throw AppException('Création échouée', cause: e.message);
    }
  }

  Future<Establishment> update({
    required String id,
    required String name,
    required String timezone,
  }) async {
    try {
      final row = await _client
          .from('establishments')
          .update({'name': name, 'timezone': timezone})
          .eq('id', id)
          .select()
          .single();
      return Establishment.fromJson(row);
    } on PostgrestException catch (e) {
      throw AppException('Mise à jour échouée', cause: e.message);
    }
  }

  Future<void> delete(String id) async {
    try {
      await _client.from('establishments').delete().eq('id', id);
    } on PostgrestException catch (e) {
      throw AppException('Suppression échouée', cause: e.message);
    }
  }
}
```

- [ ] **Step 4: Tests passent**

```bash
flutter test
```
Expected : le test `list` passe. (Les tests unitaires de create/update/delete sont omis car le mocking devient fastidieux ; ils seront couverts en E2E en Phase 7.)

- [ ] **Step 5: Commit**

```bash
git add apps/backoffice/
git commit -m "feat(backoffice): add EstablishmentsRepository with list test"
```

---

## Task 15 — Establishments : controller + liste + formulaire

**Files:**
- Create: `apps/backoffice/lib/features/establishments/application/establishments_controller.dart`
- Create: `apps/backoffice/lib/features/establishments/presentation/establishments_list_screen.dart`
- Create: `apps/backoffice/lib/features/establishments/presentation/establishment_form_screen.dart`

- [ ] **Step 1: Controller**

Créer `apps/backoffice/lib/features/establishments/application/establishments_controller.dart` :
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../auth/application/auth_controller.dart';
import '../data/establishments_repository.dart';

final establishmentsRepositoryProvider = Provider<EstablishmentsRepository>((ref) {
  return EstablishmentsRepository(ref.watch(supabaseClientProvider));
});

final establishmentsListProvider = FutureProvider<List<Establishment>>((ref) {
  return ref.watch(establishmentsRepositoryProvider).list();
});
```

- [ ] **Step 2: Liste des établissements**

Créer `apps/backoffice/lib/features/establishments/presentation/establishments_list_screen.dart` :
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/establishments_controller.dart';

class EstablishmentsListScreen extends ConsumerWidget {
  const EstablishmentsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(establishmentsListProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Établissements'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(establishmentsListProvider),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/establishments/new'),
        icon: const Icon(Icons.add),
        label: const Text('Nouvel établissement'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur : $e')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(child: Text('Aucun établissement.'));
          }
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final e = list[i];
              return ListTile(
                title: Text(e.name),
                subtitle: Text('Fuseau : ${e.timezone}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go('/establishments/${e.id}'),
              );
            },
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 3: Formulaire création/édition**

Créer `apps/backoffice/lib/features/establishments/presentation/establishment_form_screen.dart` :
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared/shared.dart';

import '../application/establishments_controller.dart';

class EstablishmentFormScreen extends ConsumerStatefulWidget {
  const EstablishmentFormScreen({this.establishmentId, super.key});

  final String? establishmentId;
  bool get isEditing => establishmentId != null;

  @override
  ConsumerState<EstablishmentFormScreen> createState() =>
      _EstablishmentFormScreenState();
}

class _EstablishmentFormScreenState
    extends ConsumerState<EstablishmentFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _tzCtrl = TextEditingController(text: 'Africa/Yaounde');
  bool _saving = false;
  String? _error;
  Establishment? _loaded;

  @override
  void initState() {
    super.initState();
    if (widget.isEditing) _load();
  }

  Future<void> _load() async {
    final list = await ref.read(establishmentsListProvider.future);
    final e = list.firstWhere(
      (x) => x.id == widget.establishmentId,
      orElse: () => throw const FormatException('Not found'),
    );
    setState(() {
      _loaded = e;
      _nameCtrl.text = e.name;
      _tzCtrl.text = e.timezone;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repo = ref.read(establishmentsRepositoryProvider);
      if (widget.isEditing) {
        await repo.update(
          id: widget.establishmentId!,
          name: _nameCtrl.text.trim(),
          timezone: _tzCtrl.text.trim(),
        );
      } else {
        await repo.create(
          name: _nameCtrl.text.trim(),
          timezone: _tzCtrl.text.trim(),
        );
      }
      ref.invalidate(establishmentsListProvider);
      if (mounted) context.go('/establishments');
    } on AppException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer ?'),
        content: Text('Supprimer "${_loaded?.name}" ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ref.read(establishmentsRepositoryProvider).delete(widget.establishmentId!);
      ref.invalidate(establishmentsListProvider);
      if (mounted) context.go('/establishments');
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Modifier' : 'Nouvel établissement'),
        actions: [
          if (widget.isEditing)
            IconButton(icon: const Icon(Icons.delete), onPressed: _delete),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Nom'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Nom requis' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _tzCtrl,
                decoration: const InputDecoration(
                  labelText: 'Fuseau horaire',
                  helperText: 'Ex: Africa/Yaounde, Europe/Paris, UTC',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Fuseau requis' : null,
              ),
              const SizedBox(height: 24),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 18, width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Enregistrer'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _tzCtrl.dispose();
    super.dispose();
  }
}
```

- [ ] **Step 4: Lancer l'app et tester manuellement**

Run :
```bash
flutter run -d chrome \
  --dart-define=SUPABASE_URL=http://127.0.0.1:54321 \
  --dart-define=SUPABASE_ANON_KEY=<anon_key>
```

Tester :
1. Se connecter avec `admin@local.test` / `AdminPass123!` → redirige vers /establishments
2. "Lounge Plateau" doit apparaître (seed)
3. Créer "Resto Centre-ville" (fuseau `Africa/Yaounde`) → apparaît dans la liste
4. Cliquer sur un établissement → formulaire d'édition → modifier → enregistre
5. Supprimer → retour à la liste

- [ ] **Step 5: Commit**

```bash
git add apps/backoffice/
git commit -m "feat(backoffice): add establishments list and form"
```

---

## Task 16 — Feature Managers : repository + liste + création

**Files:**
- Create: `apps/backoffice/lib/features/managers/data/managers_repository.dart`
- Create: `apps/backoffice/lib/features/managers/application/managers_controller.dart`
- Create: `apps/backoffice/lib/features/managers/presentation/managers_list_screen.dart`
- Create: `apps/backoffice/lib/features/managers/presentation/manager_form_screen.dart`
- Create: `supabase/functions/create-manager/index.ts`
- Create: `supabase/functions/create-manager/deno.json`

**Contexte** : créer un compte manager requiert d'appeler `supabase.auth.admin.createUser()`, ce qui nécessite la `service_role key` (dangereuse côté client). On délègue à une Edge Function.

- [ ] **Step 1: Edge Function create-manager**

Créer `supabase/functions/create-manager/deno.json` :
```json
{
  "imports": {
    "supabase": "jsr:@supabase/supabase-js@^2.46.0"
  }
}
```

Créer `supabase/functions/create-manager/index.ts` :
```typescript
import { createClient } from 'jsr:@supabase/supabase-js@^2.46.0';

type Payload = {
  email: string;
  password: string;
  full_name: string;
  establishment_ids: string[];
};

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  // 1) Vérifier que le caller est admin.
  const authHeader = req.headers.get('Authorization');
  if (!authHeader) {
    return json({ error: 'Missing auth' }, 401);
  }
  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

  const caller = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: callerUser, error: userErr } = await caller.auth.getUser();
  if (userErr || !callerUser.user) return json({ error: 'Unauthorized' }, 401);
  const { data: callerProfile } = await caller
    .from('profiles')
    .select('role')
    .eq('id', callerUser.user.id)
    .single();
  if (callerProfile?.role !== 'admin') {
    return json({ error: 'Admin role required' }, 403);
  }

  // 2) Créer le user via service_role.
  const payload = (await req.json()) as Payload;
  if (!payload.email || !payload.password || !payload.full_name) {
    return json({ error: 'email, password, full_name required' }, 400);
  }

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: created, error: createErr } = await admin.auth.admin.createUser(
    {
      email: payload.email,
      password: payload.password,
      email_confirm: true,
      user_metadata: { full_name: payload.full_name },
    },
  );
  if (createErr) return json({ error: createErr.message }, 400);

  const userId = created.user.id;

  // 3) Mettre à jour full_name (déjà rempli par trigger mais au cas où).
  await admin
    .from('profiles')
    .update({ full_name: payload.full_name, role: 'manager' })
    .eq('id', userId);

  // 4) Rattacher aux établissements.
  if (payload.establishment_ids.length > 0) {
    const rows = payload.establishment_ids.map((eid) => ({
      establishment_id: eid,
      profile_id: userId,
    }));
    const { error: linkErr } = await admin
      .from('establishment_managers')
      .insert(rows);
    if (linkErr) return json({ error: linkErr.message }, 500);
  }

  return json({ id: userId }, 200);
});

function json(body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}
```

- [ ] **Step 2: Servir la function en local**

Run :
```bash
supabase functions serve --env-file supabase/.env.local
```

(Créer `supabase/.env.local` si besoin — les variables `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` sont déjà fournies par `supabase start`, donc le fichier peut être vide.)

Expected : message "Serving functions on http://127.0.0.1:54321/functions/v1/".

- [ ] **Step 3: ManagersRepository**

Créer `apps/backoffice/lib/features/managers/data/managers_repository.dart` :
```dart
import 'package:shared/shared.dart';

class ManagerWithEstablishments {
  ManagerWithEstablishments({
    required this.profile,
    required this.establishmentIds,
  });
  final Profile profile;
  final List<String> establishmentIds;
}

class ManagersRepository {
  ManagersRepository(this._client);
  final SupabaseClient _client;

  Future<List<ManagerWithEstablishments>> list() async {
    try {
      final rows = await _client
          .from('profiles')
          .select('id, role, full_name, establishment_managers(establishment_id)')
          .eq('role', 'manager')
          .order('full_name');
      return rows.map<ManagerWithEstablishments>((row) {
        final links = (row['establishment_managers'] as List)
            .map((l) => l['establishment_id'] as String)
            .toList();
        return ManagerWithEstablishments(
          profile: Profile.fromJson({
            'id': row['id'],
            'role': row['role'],
            'full_name': row['full_name'],
          }),
          establishmentIds: links,
        );
      }).toList();
    } on PostgrestException catch (e) {
      throw AppException('Lecture gérants échouée', cause: e.message);
    }
  }

  Future<void> create({
    required String email,
    required String password,
    required String fullName,
    required List<String> establishmentIds,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'create-manager',
        body: {
          'email': email,
          'password': password,
          'full_name': fullName,
          'establishment_ids': establishmentIds,
        },
      );
      if (response.status >= 400) {
        final err = (response.data is Map)
            ? (response.data as Map)['error']
            : response.data;
        throw AppException('Création gérant échouée', cause: err);
      }
    } on FunctionException catch (e) {
      throw AppException('Création gérant échouée', cause: e.details);
    }
  }
}
```

- [ ] **Step 4: Controller managers**

Créer `apps/backoffice/lib/features/managers/application/managers_controller.dart` :
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../data/managers_repository.dart';

final managersRepositoryProvider = Provider<ManagersRepository>((ref) {
  return ManagersRepository(ref.watch(supabaseClientProvider));
});

final managersListProvider =
    FutureProvider<List<ManagerWithEstablishments>>((ref) {
  return ref.watch(managersRepositoryProvider).list();
});
```

- [ ] **Step 5: Écran liste**

Créer `apps/backoffice/lib/features/managers/presentation/managers_list_screen.dart` :
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/managers_controller.dart';

class ManagersListScreen extends ConsumerWidget {
  const ManagersListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(managersListProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gérants'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(managersListProvider),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/managers/new'),
        icon: const Icon(Icons.add),
        label: const Text('Nouveau gérant'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur : $e')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(child: Text('Aucun gérant.'));
          }
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final m = list[i];
              return ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text(m.profile.fullName),
                subtitle: Text(
                  '${m.establishmentIds.length} établissement(s)',
                ),
              );
            },
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 6: Écran création**

Créer `apps/backoffice/lib/features/managers/presentation/manager_form_screen.dart` :
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared/shared.dart';

import '../../establishments/application/establishments_controller.dart';
import '../application/managers_controller.dart';

class ManagerFormScreen extends ConsumerStatefulWidget {
  const ManagerFormScreen({super.key});

  @override
  ConsumerState<ManagerFormScreen> createState() => _ManagerFormScreenState();
}

class _ManagerFormScreenState extends ConsumerState<ManagerFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _selected = <String>{};
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selected.isEmpty) {
      setState(() => _error = 'Sélectionnez au moins un établissement');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(managersRepositoryProvider).create(
            email: _emailCtrl.text.trim(),
            password: _passCtrl.text,
            fullName: _nameCtrl.text.trim(),
            establishmentIds: _selected.toList(),
          );
      ref.invalidate(managersListProvider);
      if (mounted) context.go('/managers');
    } on AppException catch (e) {
      setState(() => _error = '${e.message} — ${e.cause}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final establishmentsAsync = ref.watch(establishmentsListProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Nouveau gérant')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Nom complet'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Requis' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailCtrl,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
                validator: (v) => (v == null || !v.contains('@'))
                    ? 'Email invalide'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passCtrl,
                decoration: const InputDecoration(labelText: 'Mot de passe'),
                obscureText: true,
                validator: (v) => (v == null || v.length < 8)
                    ? 'Minimum 8 caractères'
                    : null,
              ),
              const SizedBox(height: 24),
              Text(
                'Établissements',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              establishmentsAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(16),
                  child: LinearProgressIndicator(),
                ),
                error: (e, _) => Text('Erreur chargement : $e'),
                data: (list) => Column(
                  children: [
                    for (final e in list)
                      CheckboxListTile(
                        title: Text(e.name),
                        value: _selected.contains(e.id),
                        onChanged: (v) {
                          setState(() {
                            if (v == true) {
                              _selected.add(e.id);
                            } else {
                              _selected.remove(e.id);
                            }
                          });
                        },
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 18, width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Créer'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }
}
```

- [ ] **Step 7: Tester bout-en-bout**

1. `supabase functions serve` dans un terminal.
2. `flutter run -d chrome ...` dans un autre.
3. Login admin → aller dans "Gérants" → voir `Dev Manager` (seed) → cliquer "Nouveau gérant" → remplir → sélectionner "Lounge Plateau" → créer → retour à la liste avec le nouveau gérant.
4. Se déconnecter → se reconnecter avec le nouveau compte → vérifier que le gérant voit uniquement son établissement (via Studio directement pour l'instant ; UI gérant polish en Phase 7).

- [ ] **Step 8: Commit**

```bash
git add apps/backoffice/ supabase/functions/
git commit -m "feat(backoffice): add managers list and creation via Edge Function"
```

---

## Task 17 — CI GitHub Actions

**Files:**
- Create: `.github/workflows/ci.yml`

- [ ] **Step 1: Workflow CI**

Créer `.github/workflows/ci.yml` :
```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  flutter:
    name: Flutter analyze & test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          channel: stable
          cache: true

      - name: Install deps (workspace)
        run: flutter pub get

      - name: Generate freezed/json
        run: |
          cd packages/shared
          dart run build_runner build --delete-conflicting-outputs

      - name: Analyze
        run: flutter analyze

      - name: Test shared
        run: |
          cd packages/shared
          flutter test

      - name: Test backoffice
        run: |
          cd apps/backoffice
          flutter test

  supabase:
    name: Supabase migrations & RLS tests
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Supabase CLI
        uses: supabase/setup-cli@v1
        with:
          version: latest

      - name: Start Supabase
        run: supabase start

      - name: Run RLS tests
        run: supabase db test

      - name: Stop Supabase
        if: always()
        run: supabase stop
```

- [ ] **Step 2: Vérifier la CI en local**

Run :
```bash
flutter pub get
flutter analyze
cd packages/shared && flutter test && cd ../..
cd apps/backoffice && flutter test && cd ../..
supabase db test
```
Expected : tout vert.

- [ ] **Step 3: Commit et push**

```bash
git add .github/
git commit -m "ci: add GitHub Actions workflow for Flutter + Supabase"
```

Si un dépôt GitHub existe déjà, faire `git push -u origin main` et vérifier que la CI passe.

---

## Task 18 — README Phase 1 + script de démo

**Files:**
- Modify: `README.md`
- Create: `docs/phase1-demo.md`

- [ ] **Step 1: README enrichi**

Remplacer `README.md` par :
```markdown
# App de Diffusion

Application de signage pour restaurants et lounge bars :
- Back office Flutter Web
- Player Flutter Android (Phase 5+)
- Backend Supabase + FCM (Phase 5+)

## Documentation
- Design : [docs/superpowers/specs/2026-04-24-app-diffusion-design.md](docs/superpowers/specs/2026-04-24-app-diffusion-design.md)
- Plans : [docs/superpowers/plans/](docs/superpowers/plans/)
- Démo Phase 1 : [docs/phase1-demo.md](docs/phase1-demo.md)

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
#    anon key: eyJhbGc...
#    service_role key: eyJhbGc...

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
# Tests unitaires
flutter test

# Tests RLS Postgres
supabase db test
```
```

- [ ] **Step 2: Script de démo Phase 1**

Créer `docs/phase1-demo.md` :
```markdown
# Démo Phase 1

## Prérequis
- Supabase local tourne (`supabase start`)
- Edge Functions servent (`supabase functions serve`)
- Back office tourne (`flutter run -d chrome ...`)

## Scénario de démo

1. **Login admin**
   - Saisir `admin@local.test` / `AdminPass123!`
   - Cliquer "Se connecter" → redirection `/establishments`

2. **CRUD Établissements**
   - Voir "Lounge Plateau" (seed)
   - Cliquer "Nouvel établissement" → saisir "Resto Centre-ville" + fuseau "Africa/Yaounde" → Enregistrer
   - La liste affiche 2 lignes
   - Cliquer sur "Resto Centre-ville" → modifier le fuseau → Enregistrer → vérifier dans la liste
   - Supprimer "Resto Centre-ville" → confirmer → disparition

3. **Création Gérant**
   - Aller dans "Gérants" → voir "Dev Manager" (seed)
   - Cliquer "Nouveau gérant" → saisir "Jean Dupont" / jean@local.test / Test1234! → cocher "Lounge Plateau" → Créer
   - Retour à la liste : "Jean Dupont" apparaît avec "1 établissement(s)"

4. **Test isolation gérant (via Studio)**
   - Se déconnecter
   - Se connecter avec `jean@local.test` / `Test1234!`
   - Dans Studio (`http://127.0.0.1:54323`), exécuter en SQL `select * from establishments` en tant que `jean@local.test` → doit retourner uniquement "Lounge Plateau" (preuve que RLS fonctionne)

## Résultat attendu

Tous les points ci-dessus marchent, l'UI est navigable, les données persistent après refresh.
Les tests `flutter test` et `supabase db test` passent tous.
```

- [ ] **Step 3: Commit final Phase 1**

```bash
git add README.md docs/
git commit -m "docs: add phase 1 README and demo script"
```

---

## Self-Review

Relecture du plan avec le spec en parallèle.

**1. Spec coverage (Phase 1 items du spec section 10) :**
- ✅ Monorepo Flutter workspace → Tasks 2, 5, 10
- ✅ CI GitHub Actions (lint + test) → Task 17
- ✅ Supabase local + migrations `profiles`, `establishments`, `establishment_managers` → Tasks 6-7
- ✅ Back office login admin → Tasks 11-13
- ✅ CRUD établissements → Tasks 14-15
- ✅ Création gérants → Task 16
- ✅ Démo : admin se connecte, crée un établissement, crée un gérant → Task 18 (script)

**2. Placeholder scan :**
- Pas de "TBD", "TODO", "implement later" dans les steps.
- Code complet donné à chaque step impliquant du code.
- Les chemins de fichiers sont absolus et exacts.
- Références `<anon_key>` dans les commandes — explicitement signalé comme valeur à copier depuis `supabase start`, pas un placeholder abstrait.

**3. Type consistency :**
- `UserRole` : défini Task 3, utilisé Task 4 (Profile), consistant.
- `Profile` / `Establishment` : définis Task 4, utilisés Tasks 11, 14, 16.
- `AppException` : défini Task 5, utilisé Tasks 11, 14, 15, 16.
- `SupabaseConfig` / `initSupabase` : définis Task 5, utilisés Task 10 (main.dart).
- `supabaseClientProvider` : défini Task 12 (auth_controller), réutilisé Tasks 15, 16.
- `authRepositoryProvider` / `currentSessionProvider` / `authStateProvider` : définis Task 12, utilisés Task 13.
- `establishmentsRepositoryProvider` / `establishmentsListProvider` : définis Task 15, utilisés Task 16 (form manager pour la liste des établissements à cocher).
- Noms des tables Postgres cohérents avec les repositories (`establishments`, `profiles`, `establishment_managers`).
- Nom Edge Function `create-manager` cohérent entre Task 16 step 1, step 2 et step 3.

**4. Points d'attention notés pendant la review :**
- Le test mocktail du Task 14 est limité (un seul cas `list`) — noté dans le step comme choix délibéré, avec couverture E2E prévue Phase 7.
- Le bouton "déconnexion" est dans `AppShell` (Task 13) mais ne force pas le routeur à rediriger — le redirect Go Router le fait via le `refreshListenable`. OK.
- La Edge Function `create-manager` nécessite `supabase functions serve` à tourner en parallèle du back. Documenté dans README + phase1-demo.

Plan cohérent, pas de modifications nécessaires.
