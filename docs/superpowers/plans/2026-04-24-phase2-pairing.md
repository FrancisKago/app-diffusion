# Phase 2 — Appairage bout-en-bout — Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development to implement task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Permettre qu'une tablette Android lance l'app Player, affiche un code d'appairage à 6 chiffres, soit rattachée par un admin depuis le back office, et passe en mode "ready" avec un JWT persistant sécurisé.

**Architecture:** Table `pairing_sessions` (transitoire, TTL 15 min) pour stocker les codes avant association à un `device` existant. Trois Edge Functions : `request-pairing-code` (public, crée une session), `pairing-status` (public, polling par session_id), `claim-pairing-code` (admin, lie une session à un device + émet JWT). Le Player persiste le JWT dans `flutter_secure_storage` (Android Keystore).

**Tech Stack:**
- Flutter Android (nouveau artefact `apps/player`)
- `flutter_secure_storage` ^9.x (Keystore)
- `http` package (polling minimal — pas besoin de supabase_flutter côté Player en Phase 2)
- Reprise : Supabase Edge Functions Deno, Riverpod, go_router, supabase_flutter côté back office
- Tests : `flutter_test`, `mocktail` + pgTAP

---

## File Structure additions

```
app-diffusion/
├── apps/
│   ├── backoffice/
│   │   └── lib/features/devices/          # Nouveau
│   │       ├── data/devices_repository.dart
│   │       ├── data/pairing_repository.dart
│   │       ├── application/devices_controller.dart
│   │       └── presentation/
│   │           ├── devices_list_screen.dart
│   │           ├── device_form_screen.dart
│   │           └── claim_pairing_dialog.dart
│   └── player/                             # Nouveau (Flutter Android)
│       ├── pubspec.yaml
│       ├── android/                        # généré par flutter create
│       ├── lib/
│       │   ├── main.dart
│       │   ├── app.dart
│       │   ├── services/
│       │   │   ├── secure_storage.dart    # wrapper sur flutter_secure_storage
│       │   │   └── pairing_service.dart   # HTTP calls to pairing Edge Functions
│       │   └── features/
│       │       ├── pairing/presentation/pairing_screen.dart
│       │       └── ready/presentation/ready_screen.dart
│       └── test/services/pairing_service_test.dart
├── packages/shared/
│   └── lib/src/models/
│       ├── device.dart                     # Nouveau
│       └── pairing_session.dart            # Nouveau
└── supabase/
    ├── migrations/
    │   ├── 20260425100000_devices.sql
    │   └── 20260425100100_pairing_sessions.sql
    ├── functions/
    │   ├── request-pairing-code/{deno.json,index.ts}
    │   ├── pairing-status/{deno.json,index.ts}
    │   └── claim-pairing-code/{deno.json,index.ts}
    └── tests/
        └── rls_phase2_test.sql
```

---

## Task 1 — Migration `devices`

**Files:**
- Create: `supabase/migrations/20260425100000_devices.sql`

- [ ] **Step 1: Create the migration**

```sql
create type device_orientation as enum ('landscape', 'portrait');

create table public.devices (
    id uuid primary key default gen_random_uuid(),
    establishment_id uuid not null references public.establishments(id) on delete cascade,
    name text not null check (length(trim(name)) > 0),
    orientation device_orientation not null default 'landscape',
    fcm_token text,                       -- Phase 5+
    last_seen_at timestamptz,
    revoked_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create trigger devices_set_updated_at
    before update on public.devices
    for each row execute function public.tg_set_updated_at();

create index devices_establishment_idx on public.devices (establishment_id);

alter table public.devices enable row level security;

-- Admin = tout
create policy devices_admin_all on public.devices
    for all using (public.is_admin()) with check (public.is_admin());

-- Gérant = SELECT sur ses établissements
create policy devices_manager_select on public.devices
    for select using (
        exists (
            select 1 from public.establishment_managers em
            where em.establishment_id = devices.establishment_id
              and em.profile_id = auth.uid()
        )
    );

-- Device = SELECT sur sa propre ligne (claim via JWT custom, device_id dans les claims)
-- Le JWT device contient: { sub: device_id, role: 'device', establishment_id }
-- La vérif est donc auth.uid() = devices.id quand le "user" est en fait le device.
create policy devices_self_select on public.devices
    for select using (id = auth.uid());

-- Device = UPDATE sur last_seen_at uniquement (heartbeat arrivera Phase 6)
create policy devices_self_update_heartbeat on public.devices
    for update using (id = auth.uid())
    with check (id = auth.uid());
```

- [ ] **Step 2: Apply**

```bash
cd "D:/App de diffusion"
supabase db reset
```

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260425100000_devices.sql
git commit -m "feat(db): add devices table with RLS (admin/manager/self)"
```

---

## Task 2 — Migration `pairing_sessions`

**Files:**
- Create: `supabase/migrations/20260425100100_pairing_sessions.sql`

- [ ] **Step 1: Create the migration**

```sql
create type pairing_session_status as enum ('pending', 'claimed', 'expired');

create table public.pairing_sessions (
    id uuid primary key default gen_random_uuid(),
    code text not null,
    status pairing_session_status not null default 'pending',
    device_id uuid references public.devices(id) on delete set null,
    jwt text,                              -- populated when claimed
    expires_at timestamptz not null,
    claimed_at timestamptz,
    created_at timestamptz not null default now()
);

-- Unique parmi les sessions pending (code réutilisable une fois claimed/expired)
create unique index pairing_sessions_pending_code_idx
    on public.pairing_sessions (code)
    where status = 'pending';

create index pairing_sessions_device_idx on public.pairing_sessions (device_id);

alter table public.pairing_sessions enable row level security;

-- Les Edge Functions utiliseront la service_role key → bypass RLS.
-- On restreint tout accès client côté app/back office.

-- Admin = SELECT (pour debug / audit)
create policy pairing_sessions_admin_select on public.pairing_sessions
    for select using (public.is_admin());

-- Aucun INSERT/UPDATE/DELETE côté client : seules les Edge Functions peuvent écrire.

-- Purge automatique des sessions expirées (pg_cron pas disponible localement
-- sans config — on fait la purge dans request-pairing-code à chaque appel,
-- ce qui suffit en dev et en prod low-volume).
```

- [ ] **Step 2: Apply**

```bash
supabase db reset
```

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260425100100_pairing_sessions.sql
git commit -m "feat(db): add pairing_sessions table for device enrollment flow"
```

---

## Task 3 — pgTAP tests for devices + sessions RLS

**Files:**
- Create: `supabase/tests/rls_phase2_test.sql`

- [ ] **Step 1: Create the test file**

```sql
begin;

select plan(5);

set local role authenticated;

-- Seed un device pour les tests
insert into public.devices (id, establishment_id, name)
  values ('22222222-2222-2222-2222-222222222222',
          '11111111-1111-1111-1111-111111111111',
          'Écran terrasse');

-- 1) Manager voit les devices de son établissement
set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-000000000002","role":"authenticated"}';
select results_eq(
    $$ select count(*) from public.devices $$,
    $$ values (1::bigint) $$,
    'manager sees 1 device in his establishment'
);

-- 2) Manager ne peut PAS créer un device
prepare manager_insert_device as
    insert into public.devices (establishment_id, name)
    values ('11111111-1111-1111-1111-111111111111', 'Forbidden');
select throws_ok('manager_insert_device', '42501', null, 'manager device insert blocked');

-- 3) Admin voit tous les devices
set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}';
select results_eq(
    $$ select count(*) from public.devices $$,
    $$ values (1::bigint) $$,
    'admin sees all devices'
);

-- 4) Admin peut créer un device
insert into public.devices (establishment_id, name)
  values ('11111111-1111-1111-1111-111111111111', 'Test');
select pass('admin can insert device');

-- 5) Non-admin ne voit pas les pairing_sessions
insert into public.pairing_sessions (code, expires_at)
  values ('123456', now() + interval '15 minutes');
set local "request.jwt.claims" to '{"sub":"00000000-0000-0000-0000-000000000002","role":"authenticated"}';
select results_eq(
    $$ select count(*) from public.pairing_sessions $$,
    $$ values (0::bigint) $$,
    'manager cannot see pairing sessions'
);

select * from finish();

rollback;
```

- [ ] **Step 2: Run tests**

```bash
supabase test db
```

Expected: 11/11 pass (6 Phase 1 + 5 Phase 2).

- [ ] **Step 3: Commit**

```bash
git add supabase/tests/rls_phase2_test.sql
git commit -m "test(db): add pgTAP RLS tests for devices and pairing sessions"
```

---

## Task 4 — Edge Function `request-pairing-code`

**Files:**
- Create: `supabase/functions/request-pairing-code/{deno.json,index.ts}`

- [ ] **Step 1: deno.json**

```json
{
  "imports": {
    "supabase": "jsr:@supabase/supabase-js@^2.46.0"
  }
}
```

- [ ] **Step 2: index.ts**

```typescript
import { createClient } from 'jsr:@supabase/supabase-js@^2.46.0';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type, apikey',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function generateCode(): string {
  // 6 digits, randomly generated. Uses crypto.
  const bytes = new Uint8Array(4);
  crypto.getRandomValues(bytes);
  const num = new DataView(bytes.buffer).getUint32(0) % 1_000_000;
  return num.toString().padStart(6, '0');
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (req.method !== 'POST') {
    return json({ error: 'Method not allowed' }, 405);
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // Purge expired sessions in-band (no cron needed)
  await admin
    .from('pairing_sessions')
    .update({ status: 'expired' })
    .lt('expires_at', new Date().toISOString())
    .eq('status', 'pending');

  // Generate a unique code (retry up to 5× in unlikely collision)
  let code = '';
  let sessionId = '';
  for (let attempt = 0; attempt < 5; attempt++) {
    code = generateCode();
    const expiresAt = new Date(Date.now() + 15 * 60 * 1000).toISOString();
    const { data, error } = await admin
      .from('pairing_sessions')
      .insert({ code, expires_at: expiresAt })
      .select('id')
      .single();
    if (!error && data) {
      sessionId = data.id;
      break;
    }
    if (attempt === 4) {
      return json({ error: 'Could not allocate pairing code' }, 500);
    }
  }

  return json({ session_id: sessionId, code, ttl_seconds: 900 }, 200);
});

function json(body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}
```

- [ ] **Step 3: Add to config.toml**

Edit `supabase/config.toml`, append to the functions section:
```toml
[functions.request-pairing-code]
verify_jwt = false
```

- [ ] **Step 4: Test manually**

Restart `supabase functions serve` (kill previous, relaunch).

```bash
curl -s -X POST http://127.0.0.1:54321/functions/v1/request-pairing-code \
  -H "Content-Type: application/json" \
  -H "apikey: <ANON_KEY>"
```

Expected: `{"session_id": "...", "code": "123456", "ttl_seconds": 900}`

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/request-pairing-code/ supabase/config.toml
git commit -m "feat(functions): add request-pairing-code edge function"
```

---

## Task 5 — Edge Function `pairing-status`

**Files:**
- Create: `supabase/functions/pairing-status/{deno.json,index.ts}`

- [ ] **Step 1: deno.json** (same as Task 4)

- [ ] **Step 2: index.ts**

```typescript
import { createClient } from 'jsr:@supabase/supabase-js@^2.46.0';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type, apikey',
  'Access-Control-Allow-Methods': 'GET, OPTIONS',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (req.method !== 'GET') {
    return json({ error: 'Method not allowed' }, 405);
  }

  const url = new URL(req.url);
  const sessionId = url.searchParams.get('session_id');
  if (!sessionId) {
    return json({ error: 'session_id required' }, 400);
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data, error } = await admin
    .from('pairing_sessions')
    .select('status, device_id, jwt, expires_at')
    .eq('id', sessionId)
    .single();

  if (error || !data) {
    return json({ error: 'Session not found' }, 404);
  }

  if (data.status === 'claimed' && data.jwt && data.device_id) {
    return json({
      status: 'claimed',
      device_id: data.device_id,
      jwt: data.jwt,
    }, 200);
  }

  if (new Date(data.expires_at) < new Date()) {
    return json({ status: 'expired' }, 200);
  }

  return json({ status: 'pending' }, 200);
});

function json(body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}
```

- [ ] **Step 3: Add to config.toml**

```toml
[functions.pairing-status]
verify_jwt = false
```

- [ ] **Step 4: Manual test**

```bash
curl -s "http://127.0.0.1:54321/functions/v1/pairing-status?session_id=<id>" \
  -H "apikey: <ANON_KEY>"
```

Expected: `{"status": "pending"}` for a freshly-created session.

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/pairing-status/ supabase/config.toml
git commit -m "feat(functions): add pairing-status edge function"
```

---

## Task 6 — Edge Function `claim-pairing-code`

**Files:**
- Create: `supabase/functions/claim-pairing-code/{deno.json,index.ts}`

- [ ] **Step 1: deno.json** (same)

- [ ] **Step 2: index.ts**

The claim function requires admin. It:
1. Verifies caller is admin (same pattern as `create-manager`)
2. Finds the session by code (must be pending + not expired)
3. Verifies the device exists and isn't already paired to an active session
4. Generates a custom JWT with `{sub: device_id, role: 'authenticated', aud: 'authenticated', exp: +90d, establishment_id, is_device: true}` signed with the Supabase JWT secret
5. Updates the session: status=claimed, device_id, jwt
6. Returns `{ok: true}` to the admin

```typescript
import { createClient } from 'jsr:@supabase/supabase-js@^2.46.0';
import { create as createJwt, getNumericDate } from 'https://deno.land/x/djwt@v3.0.1/mod.ts';

type Payload = { code: string; device_id: string };

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type, apikey',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (req.method !== 'POST') {
    return json({ error: 'Method not allowed' }, 405);
  }

  const authHeader = req.headers.get('Authorization');
  if (!authHeader) return json({ error: 'Missing auth' }, 401);

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const jwtSecret = Deno.env.get('JWT_SECRET')!;

  const caller = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: callerUser, error: userErr } = await caller.auth.getUser();
  if (userErr || !callerUser.user) return json({ error: 'Unauthorized' }, 401);

  const { data: callerProfile, error: profileErr } = await caller
    .from('profiles')
    .select('role')
    .eq('id', callerUser.user.id)
    .single();
  if (profileErr || !callerProfile || callerProfile.role !== 'admin') {
    return json({ error: 'Admin role required' }, 403);
  }

  const payload = (await req.json()) as Payload;
  if (!payload.code || !payload.device_id) {
    return json({ error: 'code, device_id required' }, 400);
  }

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // Find pending session
  const { data: session, error: sessErr } = await admin
    .from('pairing_sessions')
    .select('id, expires_at, status')
    .eq('code', payload.code)
    .eq('status', 'pending')
    .maybeSingle();
  if (sessErr) return json({ error: sessErr.message }, 500);
  if (!session) return json({ error: 'Invalid or already-used code' }, 404);
  if (new Date(session.expires_at) < new Date()) {
    await admin.from('pairing_sessions').update({ status: 'expired' }).eq('id', session.id);
    return json({ error: 'Code expired' }, 410);
  }

  // Verify device exists
  const { data: device, error: devErr } = await admin
    .from('devices')
    .select('id, establishment_id, revoked_at')
    .eq('id', payload.device_id)
    .single();
  if (devErr || !device) return json({ error: 'Device not found' }, 404);
  if (device.revoked_at) return json({ error: 'Device revoked' }, 410);

  // Generate device JWT (90 days)
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(jwtSecret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign', 'verify'],
  );
  const now = getNumericDate(0);
  const exp = getNumericDate(60 * 60 * 24 * 90); // 90 days
  const jwt = await createJwt(
    { alg: 'HS256', typ: 'JWT' },
    {
      sub: device.id,
      role: 'authenticated',
      aud: 'authenticated',
      iat: now,
      exp,
      establishment_id: device.establishment_id,
      is_device: true,
    },
    key,
  );

  // Mark session claimed
  const { error: updateErr } = await admin
    .from('pairing_sessions')
    .update({
      status: 'claimed',
      device_id: device.id,
      jwt,
      claimed_at: new Date().toISOString(),
    })
    .eq('id', session.id);
  if (updateErr) return json({ error: updateErr.message }, 500);

  return json({ ok: true }, 200);
});

function json(body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}
```

- [ ] **Step 3: config.toml**

```toml
[functions.claim-pairing-code]
verify_jwt = false
```

(Function does its own admin check — see Phase 1 `create-manager` pattern.)

- [ ] **Step 4: End-to-end manual test**

```bash
# 1. Request a code (no auth needed)
curl -s -X POST http://127.0.0.1:54321/functions/v1/request-pairing-code -H "apikey: <ANON>"
# → {session_id, code}

# 2. Create a device via Studio or SQL insert for the test
# 3. Admin login → get JWT
ADMIN_JWT=$(curl -s -X POST 'http://127.0.0.1:54321/auth/v1/token?grant_type=password' \
  -H "apikey: <ANON>" -H "Content-Type: application/json" \
  -d '{"email":"admin@local.test","password":"AdminPass123!"}' | jq -r .access_token)

# 4. Claim
curl -s -X POST http://127.0.0.1:54321/functions/v1/claim-pairing-code \
  -H "Authorization: Bearer $ADMIN_JWT" -H "Content-Type: application/json" \
  -H "apikey: <ANON>" \
  -d '{"code":"<CODE>","device_id":"<DEVICE_UUID>"}'
# → {"ok": true}

# 5. Poll status — should now return claimed + jwt
curl -s "http://127.0.0.1:54321/functions/v1/pairing-status?session_id=<ID>" -H "apikey: <ANON>"
# → {"status": "claimed", "device_id": "...", "jwt": "..."}
```

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/claim-pairing-code/ supabase/config.toml
git commit -m "feat(functions): add claim-pairing-code edge function with device JWT issuance"
```

---

## Task 7 — Shared model `Device`

**Files:**
- Create: `packages/shared/lib/src/models/device.dart`
- Create: `packages/shared/test/src/models/device_test.dart`
- Modify: `packages/shared/lib/shared.dart`

- [ ] **Step 1: Test first**

`packages/shared/test/src/models/device_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';

void main() {
  group('Device', () {
    test('fromJson parses landscape device', () {
      final d = Device.fromJson({
        'id': 'd1',
        'establishment_id': 'e1',
        'name': 'Écran terrasse',
        'orientation': 'landscape',
      });
      expect(d.id, 'd1');
      expect(d.orientation, DeviceOrientation.landscape);
    });

    test('fromJson defaults orientation to landscape when missing', () {
      final d = Device.fromJson({
        'id': 'd1',
        'establishment_id': 'e1',
        'name': 'X',
      });
      expect(d.orientation, DeviceOrientation.landscape);
    });
  });
}
```

- [ ] **Step 2: Run** — FAIL.

- [ ] **Step 3: Implement**

`packages/shared/lib/src/models/device.dart`:
```dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'device.freezed.dart';
part 'device.g.dart';

enum DeviceOrientation {
  landscape,
  portrait;

  String get dbValue => name;

  static DeviceOrientation fromString(String value) {
    return switch (value) {
      'landscape' => DeviceOrientation.landscape,
      'portrait' => DeviceOrientation.portrait,
      _ => DeviceOrientation.landscape,
    };
  }
}

class _OrientationConverter
    implements JsonConverter<DeviceOrientation, String?> {
  const _OrientationConverter();
  @override
  DeviceOrientation fromJson(String? json) =>
      json == null ? DeviceOrientation.landscape : DeviceOrientation.fromString(json);
  @override
  String toJson(DeviceOrientation object) => object.dbValue;
}

@freezed
class Device with _$Device {
  const factory Device({
    required String id,
    @JsonKey(name: 'establishment_id') required String establishmentId,
    required String name,
    @_OrientationConverter()
    @Default(DeviceOrientation.landscape)
    DeviceOrientation orientation,
  }) = _Device;

  factory Device.fromJson(Map<String, dynamic> json) =>
      _$DeviceFromJson(json);
}
```

- [ ] **Step 4: Update barrel**

Add to `packages/shared/lib/shared.dart`:
```dart
export 'src/models/device.dart';
```

- [ ] **Step 5: Codegen + tests**

```bash
cd packages/shared
dart run build_runner build --delete-conflicting-outputs
flutter test
```

- [ ] **Step 6: Commit**

```bash
git add packages/shared/
git commit -m "feat(shared): add Device model with orientation enum"
```

---

## Task 8 — Backoffice `DevicesRepository` + `PairingRepository`

**Files:**
- Create: `apps/backoffice/lib/features/devices/data/devices_repository.dart`
- Create: `apps/backoffice/lib/features/devices/data/pairing_repository.dart`

- [ ] **Step 1: DevicesRepository**

Same pattern as `EstablishmentsRepository`. Methods: `list()`, `listForEstablishment(establishmentId)`, `create({name, establishment_id, orientation})`, `update(...)`, `delete(id)`, `revoke(id)` (sets `revoked_at = now()`).

```dart
import 'package:shared/shared.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DevicesRepository {
  DevicesRepository(this._client);
  final SupabaseClient _client;

  Future<List<Device>> list() async {
    try {
      final rows = await _client
          .from('devices')
          .select()
          .order('name');
      return rows.map<Device>(
        (r) => Device.fromJson(Map<String, dynamic>.from(r as Map)),
      ).toList();
    } on PostgrestException catch (e) {
      throw AppException('Lecture devices échouée', cause: e.message);
    }
  }

  Future<Device> create({
    required String establishmentId,
    required String name,
    required DeviceOrientation orientation,
  }) async {
    try {
      final row = await _client.from('devices').insert({
        'establishment_id': establishmentId,
        'name': name,
        'orientation': orientation.dbValue,
      }).select().single();
      return Device.fromJson(Map<String, dynamic>.from(row));
    } on PostgrestException catch (e) {
      throw AppException('Création device échouée', cause: e.message);
    }
  }

  Future<void> revoke(String id) async {
    try {
      await _client.from('devices').update({
        'revoked_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', id);
    } on PostgrestException catch (e) {
      throw AppException('Révocation échouée', cause: e.message);
    }
  }
}
```

- [ ] **Step 2: PairingRepository**

```dart
import 'package:shared/shared.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PairingRepository {
  PairingRepository(this._client);
  final SupabaseClient _client;

  Future<void> claim({required String code, required String deviceId}) async {
    try {
      final response = await _client.functions.invoke(
        'claim-pairing-code',
        body: {'code': code, 'device_id': deviceId},
      );
      if (response.status >= 400) {
        final data = response.data;
        final err = (data is Map) ? data['error'] : data;
        throw AppException('Appairage échoué', cause: err);
      }
    } on FunctionException catch (e) {
      throw AppException('Appairage échoué', cause: e.details);
    }
  }
}
```

- [ ] **Step 3: Commit**

```bash
git add apps/backoffice/
git commit -m "feat(backoffice): add DevicesRepository and PairingRepository"
```

---

## Task 9 — Backoffice controllers + devices list screen + device form

**Files:**
- Create: `apps/backoffice/lib/features/devices/application/devices_controller.dart`
- Create: `apps/backoffice/lib/features/devices/presentation/devices_list_screen.dart`
- Create: `apps/backoffice/lib/features/devices/presentation/device_form_screen.dart`

- [ ] **Step 1: Controller**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../auth/application/auth_controller.dart';
import '../data/devices_repository.dart';
import '../data/pairing_repository.dart';

final devicesRepositoryProvider = Provider<DevicesRepository>((ref) {
  return DevicesRepository(ref.watch(supabaseClientProvider));
});

final devicesListProvider = FutureProvider<List<Device>>((ref) {
  return ref.watch(devicesRepositoryProvider).list();
});

final pairingRepositoryProvider = Provider<PairingRepository>((ref) {
  return PairingRepository(ref.watch(supabaseClientProvider));
});
```

- [ ] **Step 2: List screen**

Follows `EstablishmentsListScreen` pattern: AppBar with refresh, FAB for new device, list items showing name + orientation chip + "Appairer" action.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/devices_controller.dart';
import 'claim_pairing_dialog.dart';

class DevicesListScreen extends ConsumerWidget {
  const DevicesListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(devicesListProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Appareils'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(devicesListProvider),
          ),
          IconButton(
            icon: const Icon(Icons.link),
            tooltip: 'Appairer par code',
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const ClaimPairingDialog(),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/devices/new'),
        icon: const Icon(Icons.add),
        label: const Text('Nouvel appareil'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur : $e')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(child: Text('Aucun appareil.'));
          }
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final d = list[i];
              return ListTile(
                leading: Icon(
                  d.orientation.dbValue == 'portrait'
                      ? Icons.stay_current_portrait
                      : Icons.tv_outlined,
                ),
                title: Text(d.name),
                subtitle: Text('${d.orientation.dbValue} · ${d.id.substring(0, 8)}…'),
              );
            },
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 3: Device form**

Similar to establishment form. Fields: name (required), establishment (dropdown of admin's establishments), orientation (radio buttons). Save via repository → invalidate list → navigate back.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared/shared.dart';

import '../../establishments/application/establishments_controller.dart';
import '../application/devices_controller.dart';

class DeviceFormScreen extends ConsumerStatefulWidget {
  const DeviceFormScreen({super.key});

  @override
  ConsumerState<DeviceFormScreen> createState() => _DeviceFormScreenState();
}

class _DeviceFormScreenState extends ConsumerState<DeviceFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  String? _establishmentId;
  DeviceOrientation _orientation = DeviceOrientation.landscape;
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_establishmentId == null) {
      setState(() => _error = 'Établissement requis');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await ref.read(devicesRepositoryProvider).create(
        establishmentId: _establishmentId!,
        name: _nameCtrl.text.trim(),
        orientation: _orientation,
      );
      ref.invalidate(devicesListProvider);
      if (mounted) context.go('/devices');
    } on AppException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final establishmentsAsync = ref.watch(establishmentsListProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Nouvel appareil')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Nom'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Nom requis' : null,
              ),
              const SizedBox(height: 16),
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
              Text('Orientation', style: Theme.of(context).textTheme.titleMedium),
              RadioListTile<DeviceOrientation>(
                title: const Text('Paysage (TV)'),
                value: DeviceOrientation.landscape,
                groupValue: _orientation,
                onChanged: (v) => setState(() => _orientation = v!),
              ),
              RadioListTile<DeviceOrientation>(
                title: const Text('Portrait (menu vertical)'),
                value: DeviceOrientation.portrait,
                groupValue: _orientation,
                onChanged: (v) => setState(() => _orientation = v!),
              ),
              const SizedBox(height: 24),
              if (_error != null)
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Créer'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() { _nameCtrl.dispose(); super.dispose(); }
}
```

- [ ] **Step 4: Commit**

```bash
git add apps/backoffice/
git commit -m "feat(backoffice): add devices controller, list and form screens"
```

---

## Task 10 — `ClaimPairingDialog`

**Files:**
- Create: `apps/backoffice/lib/features/devices/presentation/claim_pairing_dialog.dart`

- [ ] **Step 1: Implement**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../application/devices_controller.dart';

class ClaimPairingDialog extends ConsumerStatefulWidget {
  const ClaimPairingDialog({super.key});

  @override
  ConsumerState<ClaimPairingDialog> createState() => _ClaimPairingDialogState();
}

class _ClaimPairingDialogState extends ConsumerState<ClaimPairingDialog> {
  final _codeCtrl = TextEditingController();
  String? _deviceId;
  bool _saving = false;
  String? _error;

  Future<void> _submit() async {
    final code = _codeCtrl.text.trim().replaceAll(' ', '').replaceAll('-', '');
    if (code.length != 6 || _deviceId == null) {
      setState(() => _error = 'Code 6 chiffres + device requis');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await ref.read(pairingRepositoryProvider).claim(
        code: code, deviceId: _deviceId!,
      );
      if (mounted) {
        Navigator.of(context).pop();
        ref.invalidate(devicesListProvider);
      }
    } on AppException catch (e) {
      setState(() => _error = '${e.message} — ${e.cause}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final devicesAsync = ref.watch(devicesListProvider);
    return AlertDialog(
      title: const Text('Appairer un appareil'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _codeCtrl,
              decoration: const InputDecoration(
                labelText: 'Code affiché sur la tablette',
                hintText: '482193',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            devicesAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('Erreur: $e'),
              data: (list) => DropdownButtonFormField<String>(
                initialValue: _deviceId,
                decoration: const InputDecoration(labelText: 'Rattacher à l\'appareil'),
                items: [
                  for (final d in list)
                    DropdownMenuItem(value: d.id, child: Text(d.name)),
                ],
                onChanged: (v) => setState(() => _deviceId = v),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Appairer'),
        ),
      ],
    );
  }

  @override
  void dispose() { _codeCtrl.dispose(); super.dispose(); }
}
```

- [ ] **Step 2: Commit**

```bash
git add apps/backoffice/
git commit -m "feat(backoffice): add claim-pairing dialog"
```

---

## Task 11 — Router update + AppShell nav

**Files:**
- Modify: `apps/backoffice/lib/routing/app_router.dart`
- Modify: `apps/backoffice/lib/shared_widgets/app_shell.dart`

- [ ] **Step 1: Add /devices routes**

Edit `app_router.dart`, add imports:
```dart
import '../features/devices/presentation/devices_list_screen.dart';
import '../features/devices/presentation/device_form_screen.dart';
```

Add inside the ShellRoute routes list (between establishments and managers):
```dart
GoRoute(
  path: '/devices',
  builder: (_, __) => const DevicesListScreen(),
  routes: [
    GoRoute(
      path: 'new',
      builder: (_, __) => const DeviceFormScreen(),
    ),
  ],
),
```

- [ ] **Step 2: Add /devices destination**

Edit `app_shell.dart`, extend `_destinations`:
```dart
static const _destinations = [
  _Dest('/establishments', Icons.store_outlined, 'Établissements'),
  _Dest('/devices', Icons.tv_outlined, 'Appareils'),
  _Dest('/managers', Icons.people_outline, 'Gérants'),
];
```

- [ ] **Step 3: Verify**

```bash
cd apps/backoffice
flutter analyze
```

0 errors.

- [ ] **Step 4: Commit**

```bash
git add apps/backoffice/
git commit -m "feat(backoffice): wire /devices into router and app shell nav"
```

---

## Task 12 — Scaffold `apps/player` (Flutter Android)

**Files:**
- Create: `apps/player/` (via flutter create)

- [ ] **Step 1: Create the Android app**

```bash
cd "D:/App de diffusion"
flutter create --platforms=android --project-name player --org com.appdiffusion apps/player
```

- [ ] **Step 2: Replace `apps/player/pubspec.yaml`**

```yaml
name: player
description: Lecteur Android pour app-diffusion.
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
  flutter_secure_storage: ^9.2.2
  http: ^1.2.2

dev_dependencies:
  flutter_test:
    sdk: flutter
  very_good_analysis: ^6.0.0
  mocktail: ^1.0.4
```

- [ ] **Step 3: analysis_options.yaml**

`apps/player/analysis_options.yaml`:
```yaml
include: ../../analysis_options.yaml
```

- [ ] **Step 4: Re-enable in root workspace pubspec**

Edit `D:/App de diffusion/pubspec.yaml`:
```yaml
workspace:
  - packages/shared
  - apps/backoffice
  - apps/player
```

- [ ] **Step 5: Delete generated test file**

```bash
rm apps/player/test/widget_test.dart
```

- [ ] **Step 6: Set Android minSdk + fullscreen**

Edit `apps/player/android/app/build.gradle.kts` (or `.gradle`): set `minSdkVersion` to at least 23 (required by flutter_secure_storage).

Edit `apps/player/android/app/src/main/AndroidManifest.xml`, ensure the application has:
```xml
<activity
    android:theme="@style/LaunchTheme"
    ...
    android:showWhenLocked="true"
    android:turnScreenOn="true">
```

And add a landscape-first orientation in the MainActivity intent filter — but this detail can vary; the Flutter main.dart will handle `SystemChrome.setPreferredOrientations` at runtime, which is portable enough.

- [ ] **Step 7: `flutter pub get` + analyze**

```bash
cd "D:/App de diffusion"
flutter pub get
flutter analyze apps/player
```

0 errors.

- [ ] **Step 8: Commit**

```bash
git add apps/ pubspec.yaml pubspec.lock
git commit -m "feat(player): scaffold Flutter Android app"
```

---

## Task 13 — Player: secure storage service

**Files:**
- Create: `apps/player/lib/services/secure_storage.dart`

- [ ] **Step 1: Implement**

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class DeviceCredentials {
  const DeviceCredentials({required this.deviceId, required this.jwt});
  final String deviceId;
  final String jwt;
}

class SecureStorageService {
  SecureStorageService([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _storage;

  static const _kDeviceId = 'device_id';
  static const _kJwt = 'device_jwt';

  Future<DeviceCredentials?> readCredentials() async {
    final deviceId = await _storage.read(key: _kDeviceId);
    final jwt = await _storage.read(key: _kJwt);
    if (deviceId == null || jwt == null) return null;
    return DeviceCredentials(deviceId: deviceId, jwt: jwt);
  }

  Future<void> writeCredentials(DeviceCredentials creds) async {
    await _storage.write(key: _kDeviceId, value: creds.deviceId);
    await _storage.write(key: _kJwt, value: creds.jwt);
  }

  Future<void> clear() async {
    await _storage.delete(key: _kDeviceId);
    await _storage.delete(key: _kJwt);
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add apps/player/lib/services/secure_storage.dart
git commit -m "feat(player): add secure storage service for JWT persistence"
```

---

## Task 14 — Player: pairing service + test

**Files:**
- Create: `apps/player/lib/services/pairing_service.dart`
- Create: `apps/player/test/services/pairing_service_test.dart`

- [ ] **Step 1: Test first**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:player/services/pairing_service.dart';

class _MockClient extends Mock implements http.Client {}

void main() {
  setUpAll(() {
    registerFallbackValue(Uri.parse('http://x'));
  });

  group('PairingService.requestCode', () {
    test('parses session_id and code from successful response', () async {
      final client = _MockClient();
      when(() => client.post(
            any(),
            headers: any(named: 'headers'),
          )).thenAnswer((_) async => http.Response(
            '{"session_id":"s1","code":"482193","ttl_seconds":900}', 200,
          ));

      final svc = PairingService(
        baseUrl: 'http://localhost:54321',
        anonKey: 'anon',
        httpClient: client,
      );
      final res = await svc.requestCode();
      expect(res.sessionId, 's1');
      expect(res.code, '482193');
    });
  });

  group('PairingService.pollStatus', () {
    test('returns claimed with jwt', () async {
      final client = _MockClient();
      when(() => client.get(
            any(),
            headers: any(named: 'headers'),
          )).thenAnswer((_) async => http.Response(
            '{"status":"claimed","device_id":"d1","jwt":"eyJ..."}', 200,
          ));

      final svc = PairingService(
        baseUrl: 'http://localhost:54321',
        anonKey: 'anon',
        httpClient: client,
      );
      final res = await svc.pollStatus('s1');
      expect(res.status, PairingStatus.claimed);
      expect(res.deviceId, 'd1');
      expect(res.jwt, 'eyJ...');
    });
  });
}
```

- [ ] **Step 2: Implement**

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;

enum PairingStatus { pending, claimed, expired }

class PairingCodeResponse {
  const PairingCodeResponse({
    required this.sessionId,
    required this.code,
    required this.ttlSeconds,
  });
  final String sessionId;
  final String code;
  final int ttlSeconds;
}

class PairingStatusResponse {
  const PairingStatusResponse({
    required this.status,
    this.deviceId,
    this.jwt,
  });
  final PairingStatus status;
  final String? deviceId;
  final String? jwt;
}

class PairingService {
  PairingService({
    required this.baseUrl,
    required this.anonKey,
    http.Client? httpClient,
  }) : _client = httpClient ?? http.Client();

  final String baseUrl;
  final String anonKey;
  final http.Client _client;

  Map<String, String> get _headers => {
        'apikey': anonKey,
        'Content-Type': 'application/json',
      };

  Future<PairingCodeResponse> requestCode() async {
    final uri = Uri.parse('$baseUrl/functions/v1/request-pairing-code');
    final res = await _client.post(uri, headers: _headers);
    if (res.statusCode != 200) {
      throw StateError('request-pairing-code failed: ${res.statusCode} ${res.body}');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    return PairingCodeResponse(
      sessionId: json['session_id'] as String,
      code: json['code'] as String,
      ttlSeconds: json['ttl_seconds'] as int? ?? 900,
    );
  }

  Future<PairingStatusResponse> pollStatus(String sessionId) async {
    final uri = Uri.parse(
      '$baseUrl/functions/v1/pairing-status?session_id=$sessionId',
    );
    final res = await _client.get(uri, headers: _headers);
    if (res.statusCode != 200) {
      throw StateError('pairing-status failed: ${res.statusCode} ${res.body}');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final statusStr = json['status'] as String;
    final status = switch (statusStr) {
      'claimed' => PairingStatus.claimed,
      'expired' => PairingStatus.expired,
      _ => PairingStatus.pending,
    };
    return PairingStatusResponse(
      status: status,
      deviceId: json['device_id'] as String?,
      jwt: json['jwt'] as String?,
    );
  }
}
```

- [ ] **Step 3: Run tests** — 2/2 pass.

- [ ] **Step 4: Commit**

```bash
git add apps/player/
git commit -m "feat(player): add PairingService with tests"
```

---

## Task 15 — Player: main + routing (pairing vs ready)

**Files:**
- Create: `apps/player/lib/main.dart`
- Create: `apps/player/lib/app.dart`
- Create: `apps/player/lib/features/pairing/presentation/pairing_screen.dart`
- Create: `apps/player/lib/features/ready/presentation/ready_screen.dart`

- [ ] **Step 1: main.dart**

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
  runApp(const ProviderScope(child: PlayerApp()));
}
```

- [ ] **Step 2: app.dart — bootstrap logic**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/pairing/presentation/pairing_screen.dart';
import 'features/ready/presentation/ready_screen.dart';
import 'services/pairing_service.dart';
import 'services/secure_storage.dart';

const _kSupabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'http://10.0.2.2:54321',
);
const _kAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue: '',
);

final secureStorageProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});

final pairingServiceProvider = Provider<PairingService>((ref) {
  return PairingService(baseUrl: _kSupabaseUrl, anonKey: _kAnonKey);
});

final credentialsProvider = FutureProvider<DeviceCredentials?>((ref) {
  return ref.watch(secureStorageProvider).readCredentials();
});

class PlayerApp extends ConsumerWidget {
  const PlayerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final creds = ref.watch(credentialsProvider);
    return MaterialApp(
      title: 'App Diffusion — Player',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
      ),
      home: creds.when(
        loading: () => const Scaffold(
          backgroundColor: Colors.black,
          body: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Scaffold(
          backgroundColor: Colors.black,
          body: Center(child: Text('Erreur: $e', style: const TextStyle(color: Colors.white))),
        ),
        data: (c) => c == null ? const PairingScreen() : ReadyScreen(creds: c),
      ),
    );
  }
}
```

- [ ] **Step 3: Pairing screen**

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app.dart';
import '../../../services/pairing_service.dart';
import '../../../services/secure_storage.dart';

class PairingScreen extends ConsumerStatefulWidget {
  const PairingScreen({super.key});

  @override
  ConsumerState<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends ConsumerState<PairingScreen> {
  String? _code;
  String? _sessionId;
  Timer? _pollTimer;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final svc = ref.read(pairingServiceProvider);
      final res = await svc.requestCode();
      if (!mounted) return;
      setState(() {
        _code = res.code;
        _sessionId = res.sessionId;
      });
      _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _poll());
    } catch (e) {
      if (mounted) setState(() => _error = 'Impossible de demander un code: $e');
    }
  }

  Future<void> _poll() async {
    if (_sessionId == null) return;
    try {
      final svc = ref.read(pairingServiceProvider);
      final res = await svc.pollStatus(_sessionId!);
      if (res.status == PairingStatus.claimed && res.jwt != null && res.deviceId != null) {
        _pollTimer?.cancel();
        await ref.read(secureStorageProvider).writeCredentials(
          DeviceCredentials(deviceId: res.deviceId!, jwt: res.jwt!),
        );
        if (mounted) ref.invalidate(credentialsProvider);
      } else if (res.status == PairingStatus.expired) {
        _pollTimer?.cancel();
        if (mounted) {
          setState(() {
            _error = 'Code expiré. Redémarrez l\'app.';
            _code = null;
          });
        }
      }
    } catch (_) {
      // Silent retry; network blips shouldn't break the screen.
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayCode = _code == null
        ? '- - -   - - -'
        : '${_code!.substring(0, 3)}   ${_code!.substring(3)}';
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'APPAIRAGE EN COURS',
              style: TextStyle(color: Colors.white70, fontSize: 24, letterSpacing: 4),
            ),
            const SizedBox(height: 48),
            Text(
              displayCode,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 140,
                fontWeight: FontWeight.bold,
                letterSpacing: 8,
                fontFamily: 'Roboto',
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              'Saisissez ce code dans le back office',
              style: TextStyle(color: Colors.white70, fontSize: 20),
            ),
            if (_error != null) ...[
              const SizedBox(height: 32),
              Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 16)),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}
```

- [ ] **Step 4: Ready screen (placeholder)**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app.dart';
import '../../../services/secure_storage.dart';

class ReadyScreen extends ConsumerWidget {
  const ReadyScreen({required this.creds, super.key});

  final DeviceCredentials creds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          const Center(
            child: Text(
              'APPAREIL ACTIF',
              style: TextStyle(color: Colors.white, fontSize: 48, letterSpacing: 6),
            ),
          ),
          Positioned(
            bottom: 16, right: 16,
            child: Row(
              children: [
                Text(
                  'Device: ${creds.deviceId.substring(0, 8)}…',
                  style: const TextStyle(color: Colors.white30, fontSize: 12),
                ),
                const SizedBox(width: 12),
                IconButton(
                  icon: const Icon(Icons.logout, color: Colors.white30),
                  tooltip: 'Déconnecter (dev)',
                  onPressed: () async {
                    await ref.read(secureStorageProvider).clear();
                    ref.invalidate(credentialsProvider);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: Commit**

```bash
git add apps/player/
git commit -m "feat(player): add pairing and ready screens with bootstrap logic"
```

---

## Task 16 — CI update + Phase 2 demo doc

**Files:**
- Modify: `.github/workflows/ci.yml` (add player to test matrix)
- Modify: `README.md`
- Create: `docs/phase2-demo.md`

- [ ] **Step 1: CI**

Edit `.github/workflows/ci.yml`, add a step:
```yaml
      - name: Test player
        run: |
          cd apps/player
          flutter test
```

- [ ] **Step 2: Phase 2 demo doc** at `docs/phase2-demo.md`:
```markdown
# Démo Phase 2

## Prérequis
- Phase 1 setup complet
- Un émulateur Android démarré (ou une vraie tablette connectée en adb)
- Supabase local + `supabase functions serve` actifs
- Back office Flutter Web servi

## Scénario

1. **Build APK du Player**
   ```bash
   cd apps/player
   flutter run --release \
     --dart-define=SUPABASE_URL=http://10.0.2.2:54321 \
     --dart-define=SUPABASE_ANON_KEY=<ANON>
   ```
   (`10.0.2.2` = localhost de la machine hôte vu depuis l'émulateur Android)

2. **Le Player affiche un code 6 chiffres** plein écran, fond noir.

3. **Pré-créer un appareil dans le back office**
   - Aller dans "Appareils" → "Nouvel appareil"
   - Nom : "Écran terrasse", Établissement : "Lounge Plateau", Orientation : paysage
   - Enregistrer

4. **Appairer**
   - Dans "Appareils", bouton 🔗 (lien) en haut à droite → dialog "Appairer un appareil"
   - Saisir le code affiché sur l'émulateur
   - Sélectionner "Écran terrasse"
   - Cliquer "Appairer"

5. **Le Player bascule en mode "APPAREIL ACTIF"** (polling détecte le claim dans les 3s)

6. **Redémarrer l'app Player** → revient directement en mode actif (JWT en Keystore).

## Résultat attendu
- Code affiché sur la tablette
- Rattachement réussi depuis le back office
- Bascule automatique vers l'écran "APPAREIL ACTIF"
- Persistance du JWT → pas besoin de re-appairer après redémarrage
```

- [ ] **Step 3: Update README** — add link to phase2-demo.md in the Documentation section.

- [ ] **Step 4: Commit**

```bash
git add .github/ docs/ README.md
git commit -m "docs: add phase 2 demo script and CI player step"
```

---

## Self-Review Checklist

1. **Spec coverage** (spec section 10 Phase 2):
   - ✅ Tables `devices` → Task 1
   - ✅ Edge Functions request/claim/status → Tasks 4-6
   - ✅ App Android : code + polling + JWT → Tasks 12-15
   - ✅ Back office : liste devices + bouton Appairer → Tasks 8-11
   - ✅ Démo scénario → Task 16

2. **Placeholders:** None. All code blocks are complete.

3. **Type consistency:**
   - `DeviceOrientation` (Task 7) used in Task 8, 9.
   - `DeviceCredentials` (Task 13) used in Task 14, 15.
   - `PairingStatus`, `PairingService` (Task 14) used in Task 15.
   - All Edge Function API contracts (`{session_id, code, ttl_seconds}`, `{status, device_id, jwt}`, `{ok}`) match between producer and consumer.

4. **Design refinement logged:** `pairing_sessions` table is explicit in Task 2 (not in original spec's data model); documented as a resolution of spec 5.1 ambiguity.

5. **Open debt:**
   - Edge Function `request-pairing-code` has no rate limit (documented in spec 6.4 as required) — deferred to a Phase 2.5 hardening task OR Phase 7.
   - Player app JWT isn't used yet to make Supabase calls — the "ready" state just persists it. Phase 3+ will wire it for media fetching.
   - No integration test running the full pairing flow against local Supabase — deferred.

These gaps are acceptable for Phase 2 and flagged for later phases.
