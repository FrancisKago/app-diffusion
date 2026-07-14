# Security and Player Reliability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove broad device mutations, enforce tenant-consistent content assignments, restore FCM token registration, and make playlist unassignment deterministic without re-pairing deployed devices.

**Architecture:** PostgreSQL becomes the final authority through one narrowly scoped FCM RPC and two tenant-consistency triggers. The player calls the RPC through its existing JWT-authenticated HTTP client and replaces or clears its single active Drift playlist transactionally. The `assign-playlist` Edge Function performs an early tenant check for useful HTTP errors while the database trigger remains the race-safe guard.

**Tech Stack:** PostgreSQL 17, pgTAP, Supabase CLI 2.81.3 via `npx`, Deno 2, Flutter 3.38.9, Dart 3.10.8, Riverpod 2.6, Dio 5, Drift 2.28, mocktail.

## Global Constraints

- Do not execute `supabase db push`, deploy an Edge Function, or otherwise mutate Supabase Cloud until the local verification report has been shown to the user and the user explicitly approves deployment.
- Preserve every existing device ID, JWT, secure-storage entry, and pairing; no database reset may target the linked Cloud project.
- Existing players must retain offline playback, five-minute heartbeats, and fifteen-minute polling throughout rollout.
- A device with no assignment must show the standby screen after its next successful synchronization.
- Cross-establishment device–playlist and playlist–media links are forbidden even for admins.
- Device credentials, FCM tokens, service-role keys, JWT secrets, and private Firebase material must never enter Git or logs.
- User-facing copy remains French; code and database identifiers remain English.
- Use TDD for SQL, Dart, and Deno behavior, and end every implementation task with an atomic conventional commit.
- Run the CLI as `npx supabase@2.81.3`; npm global installation is unsupported. Node.js must be 20 or newer.
- Create migration files only with the exact `migration new` command in Tasks 1 and 2, then edit the path printed by the CLI; never invent a migration timestamp manually.
- The Cloud project is already linked to `mnoeteagkcqlrchyudju`; every command without `--local` must be treated as production-sensitive.

## File and Interface Map

- `supabase/migrations/*_secure_device_fcm_registration.sql`: removes broad device UPDATE policy and creates `register_device_fcm_token(text)`.
- `supabase/tests/device_fcm_security_test.sql`: pgTAP coverage for direct UPDATE denial and RPC authorization.
- `supabase/migrations/*_enforce_tenant_content_links.sql`: validates existing data and installs both consistency triggers.
- `supabase/tests/tenant_content_links_test.sql`: pgTAP coverage for same-tenant success and cross-tenant rejection.
- `supabase/functions/assign-playlist/validation.ts`: pure tenant validation used by the Edge Function.
- `supabase/functions/assign-playlist/validation.test.ts`: Deno unit tests for `404` and `409` decisions.
- `supabase/functions/assign-playlist/index.ts`: fetches resources before mutation and delegates validation.
- `apps/player/lib/data/remote/sync_api_client.dart`: adds `registerFcmToken(String token)` using the device JWT headers.
- `apps/player/lib/services/fcm_handler.dart`: delegates registration to `SyncApiClient`; no Supabase singleton.
- `apps/player/lib/features/player/presentation/player_screen.dart`: retries token registration when connectivity returns.
- `apps/player/test/data/remote/sync_api_client_test.dart`: verifies RPC URL, body, and authentication headers.
- `apps/player/test/services/fcm_handler_test.dart`: verifies delegation, missing credentials, and best-effort failure behavior.
- `apps/player/lib/data/local/app_database.dart`: exposes atomic replace/clear operations and one active-playlist query.
- `apps/player/lib/data/sync_service.dart`: returns explicit assigned/unassigned outcomes.
- `apps/player/lib/data/providers.dart`: reads the single active playlist without `all.first`.
- `apps/player/test/data/local/active_playlist_test.dart`: verifies replacement, clearing, and retained media metadata.
- `apps/player/test/data/sync_service_test.dart`: verifies remote unassignment clears logical state and releases LRU protection.

## Local Preflight

- [ ] Start Docker Desktop and verify the Linux engine is reachable:

```powershell
docker version
docker ps
```

Expected: both commands exit `0`; `docker ps` must not report a missing named pipe.

- [ ] Verify Node and the pinned Supabase CLI:

```powershell
node --version
npx supabase@2.81.3 --version
npx supabase@2.81.3 --help
```

Expected: Node is `v20` or newer and Supabase reports `2.81.3`.

- [ ] Start or inspect the local stack only:

```powershell
npx supabase@2.81.3 start
npx supabase@2.81.3 status
```

Expected: local API `54321`, database `54322`, and Studio `54323` are healthy. Do not run `db push`.

- [ ] Capture the baseline before editing:

```powershell
Push-Location packages/shared
flutter test --no-pub
Pop-Location
Push-Location apps/backoffice
flutter test --no-pub
Pop-Location
Push-Location apps/player
flutter test --no-pub
Pop-Location
deno test --allow-env supabase/functions
npx supabase@2.81.3 test db
```

Expected: 27 shared, 9 back-office, 28 player, and the existing Deno/pgTAP suites pass; the intentionally ignored live-FCM test remains ignored.

---

### Task 1: Secure Device FCM Registration RPC

**Files:**
- Create: `supabase/tests/device_fcm_security_test.sql`
- Create via CLI: `supabase/migrations/*_secure_device_fcm_registration.sql`

**Interfaces:**
- Consumes: custom JWT claims `sub`, `role=authenticated`, `is_device=true`.
- Produces: `public.register_device_fcm_token(p_token text) returns void` callable only by `authenticated` and internally restricted to device JWTs.

- [ ] **Step 1: Write the failing pgTAP test**

Create `supabase/tests/device_fcm_security_test.sql`:

```sql
begin;

select plan(6);

set local role postgres;
insert into public.devices (id, establishment_id, name)
values (
  'a1000000-0000-0000-0000-000000000001',
  '11111111-1111-1111-1111-111111111111',
  'Device FCM security test'
);

set local role authenticated;
set local "request.jwt.claims" to
  '{"sub":"a1000000-0000-0000-0000-000000000001","role":"authenticated","is_device":true,"establishment_id":"11111111-1111-1111-1111-111111111111"}';

prepare direct_device_update as
  update public.devices
     set fcm_token = 'forbidden-direct-token'
   where id = 'a1000000-0000-0000-0000-000000000001';
select throws_ok(
  'direct_device_update',
  '42501',
  null,
  'device cannot update its row directly'
);

select lives_ok(
  $$ select public.register_device_fcm_token('rpc-token') $$,
  'device can register its own FCM token through RPC'
);

set local role postgres;
select results_eq(
  $$ select fcm_token from public.devices
      where id = 'a1000000-0000-0000-0000-000000000001' $$,
  $$ values ('rpc-token'::text) $$,
  'RPC updates the authenticated device token'
);

set local role authenticated;
set local "request.jwt.claims" to
  '{"sub":"a1000000-0000-0000-0000-000000000001","role":"authenticated","is_device":true,"establishment_id":"11111111-1111-1111-1111-111111111111"}';
select throws_ok(
  $$ select public.register_device_fcm_token('') $$,
  '22023',
  'Invalid FCM token',
  'empty FCM token is rejected'
);

set local "request.jwt.claims" to
  '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}';
select throws_ok(
  $$ select public.register_device_fcm_token('human-token') $$,
  '42501',
  'Device authentication required',
  'human session cannot call device FCM RPC'
);

set local role postgres;
update public.devices
   set revoked_at = now()
 where id = 'a1000000-0000-0000-0000-000000000001';
set local role authenticated;
set local "request.jwt.claims" to
  '{"sub":"a1000000-0000-0000-0000-000000000001","role":"authenticated","is_device":true,"establishment_id":"11111111-1111-1111-1111-111111111111"}';
select throws_ok(
  $$ select public.register_device_fcm_token('revoked-token') $$,
  '42501',
  'Device not found or revoked',
  'revoked device cannot register a token'
);

select * from finish();
rollback;
```

- [ ] **Step 2: Run the SQL suite and verify the new test fails**

```powershell
npx supabase@2.81.3 test db
```

Expected: FAIL because `register_device_fcm_token(text)` does not exist and the current broad UPDATE policy lets `direct_device_update` live.

- [ ] **Step 3: Create the migration through the CLI**

```powershell
npx supabase@2.81.3 migration new secure_device_fcm_registration
```

Expected: the CLI prints one new path ending in `_secure_device_fcm_registration.sql`. Put this exact SQL in that generated file:

```sql
drop policy if exists devices_self_update_heartbeat on public.devices;

create or replace function public.register_device_fcm_token(p_token text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_device_id uuid := auth.uid();
begin
  if coalesce((auth.jwt() ->> 'is_device')::boolean, false) is not true then
    raise exception 'Device authentication required' using errcode = '42501';
  end if;

  if p_token is null
     or length(btrim(p_token)) = 0
     or length(p_token) > 4096 then
    raise exception 'Invalid FCM token' using errcode = '22023';
  end if;

  update public.devices
     set fcm_token = p_token
   where id = v_device_id
     and revoked_at is null;

  if not found then
    raise exception 'Device not found or revoked' using errcode = '42501';
  end if;
end;
$$;

revoke all on function public.register_device_fcm_token(text) from public;
revoke all on function public.register_device_fcm_token(text) from anon;
revoke all on function public.register_device_fcm_token(text) from authenticated;
grant execute on function public.register_device_fcm_token(text) to authenticated;
```

- [ ] **Step 4: Reset the local database and verify the pgTAP suite passes**

```powershell
npx supabase@2.81.3 db reset --local
npx supabase@2.81.3 test db
```

Expected: PASS, including all six assertions in `device_fcm_security_test.sql`.

- [ ] **Step 5: Run local database advisors**

```powershell
npx supabase@2.81.3 db advisors --local
```

Expected: no new security or performance advisory attributable to `register_device_fcm_token`.

- [ ] **Step 6: Commit the RPC and its test**

```powershell
git add supabase/tests/device_fcm_security_test.sql supabase/migrations/*_secure_device_fcm_registration.sql
git commit -m "fix(db): restrict device FCM token updates"
```

---

### Task 2: Enforce Tenant-Consistent Content Links

**Files:**
- Create: `supabase/tests/tenant_content_links_test.sql`
- Create via CLI: `supabase/migrations/*_enforce_tenant_content_links.sql`

**Interfaces:**
- Consumes: `devices.establishment_id`, `playlists.establishment_id`, and `media.establishment_id`.
- Produces: trigger functions `enforce_device_playlist_tenant()` and `enforce_playlist_item_tenant()` raising SQLSTATE `23514` for cross-tenant links.

- [ ] **Step 1: Write the failing tenant-invariant tests**

Create `supabase/tests/tenant_content_links_test.sql`:

```sql
begin;

select plan(4);

set local role postgres;

insert into public.establishments (id, name, timezone)
values (
  'a2000000-0000-0000-0000-000000000100',
  'Tenant B test establishment',
  'UTC'
);

insert into public.devices (id, establishment_id, name) values
  (
    'a2000000-0000-0000-0000-000000000001',
    '11111111-1111-1111-1111-111111111111',
    'Tenant A device'
  ),
  (
    'a2000000-0000-0000-0000-000000000002',
    'a2000000-0000-0000-0000-000000000100',
    'Tenant B device'
  );

insert into public.playlists (id, establishment_id, name) values
  (
    'a2000000-0000-0000-0000-000000000011',
    '11111111-1111-1111-1111-111111111111',
    'Tenant A playlist'
  ),
  (
    'a2000000-0000-0000-0000-000000000012',
    'a2000000-0000-0000-0000-000000000100',
    'Tenant B playlist'
  );

insert into public.media (
  id,
  establishment_id,
  type,
  file_path,
  file_size,
  mime_type,
  checksum_sha256,
  original_filename
) values
  (
    'a2000000-0000-0000-0000-000000000021',
    '11111111-1111-1111-1111-111111111111',
    'image',
    '11111111-1111-1111-1111-111111111111/a-media.jpg',
    100,
    'image/jpeg',
    'tenant-a-checksum',
    'a-media.jpg'
  ),
  (
    'a2000000-0000-0000-0000-000000000022',
    'a2000000-0000-0000-0000-000000000100',
    'image',
    'a2000000-0000-0000-0000-000000000100/b-media.jpg',
    100,
    'image/jpeg',
    'tenant-b-checksum',
    'b-media.jpg'
  );

select lives_ok(
  $$ insert into public.device_playlists (device_id, playlist_id)
     values ('a2000000-0000-0000-0000-000000000001',
             'a2000000-0000-0000-0000-000000000011') $$,
  'same-tenant device playlist link is accepted'
);

select throws_ok(
  $$ insert into public.device_playlists (device_id, playlist_id)
     values ('a2000000-0000-0000-0000-000000000002',
             'a2000000-0000-0000-0000-000000000011') $$,
  '23514',
  'Device and playlist must belong to the same establishment',
  'cross-tenant device playlist link is rejected'
);

select lives_ok(
  $$ insert into public.playlist_items (playlist_id, media_id, position)
     values ('a2000000-0000-0000-0000-000000000011',
             'a2000000-0000-0000-0000-000000000021', 0) $$,
  'same-tenant playlist media link is accepted'
);

select throws_ok(
  $$ insert into public.playlist_items (playlist_id, media_id, position)
     values ('a2000000-0000-0000-0000-000000000011',
             'a2000000-0000-0000-0000-000000000022', 1) $$,
  '23514',
  'Playlist and media must belong to the same establishment',
  'cross-tenant playlist media link is rejected'
);

select * from finish();
rollback;
```

- [ ] **Step 2: Run the SQL suite and verify cross-tenant assertions fail**

```powershell
npx supabase@2.81.3 test db
```

Expected: the two `lives_ok` assertions pass and both `throws_ok` assertions fail because no trigger exists yet.

- [ ] **Step 3: Create the migration through the CLI**

```powershell
npx supabase@2.81.3 migration new enforce_tenant_content_links
```

Put this SQL in the generated `_enforce_tenant_content_links.sql` file:

```sql
do $$
begin
  if exists (
    select 1
      from public.device_playlists dp
      join public.devices d on d.id = dp.device_id
      join public.playlists p on p.id = dp.playlist_id
     where d.establishment_id <> p.establishment_id
  ) then
    raise exception 'Existing cross-tenant device playlist link found'
      using errcode = '23514';
  end if;

  if exists (
    select 1
      from public.playlist_items pi
      join public.playlists p on p.id = pi.playlist_id
      join public.media m on m.id = pi.media_id
     where p.establishment_id <> m.establishment_id
  ) then
    raise exception 'Existing cross-tenant playlist media link found'
      using errcode = '23514';
  end if;
end;
$$;

create or replace function public.enforce_device_playlist_tenant()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_device_establishment uuid;
  v_playlist_establishment uuid;
begin
  select establishment_id into v_device_establishment
    from public.devices where id = new.device_id;
  select establishment_id into v_playlist_establishment
    from public.playlists where id = new.playlist_id;

  if v_device_establishment is null or v_playlist_establishment is null then
    return new;
  end if;

  if v_device_establishment <> v_playlist_establishment then
    raise exception 'Device and playlist must belong to the same establishment'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

create or replace function public.enforce_playlist_item_tenant()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_playlist_establishment uuid;
  v_media_establishment uuid;
begin
  select establishment_id into v_playlist_establishment
    from public.playlists where id = new.playlist_id;
  select establishment_id into v_media_establishment
    from public.media where id = new.media_id;

  if v_playlist_establishment is null or v_media_establishment is null then
    return new;
  end if;

  if v_playlist_establishment <> v_media_establishment then
    raise exception 'Playlist and media must belong to the same establishment'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

revoke all on function public.enforce_device_playlist_tenant() from public, anon, authenticated;
revoke all on function public.enforce_playlist_item_tenant() from public, anon, authenticated;

create trigger device_playlists_same_tenant
before insert or update of device_id, playlist_id on public.device_playlists
for each row execute function public.enforce_device_playlist_tenant();

create trigger playlist_items_same_tenant
before insert or update of playlist_id, media_id on public.playlist_items
for each row execute function public.enforce_playlist_item_tenant();
```

- [ ] **Step 4: Reset locally and verify every pgTAP test passes**

```powershell
npx supabase@2.81.3 db reset --local
npx supabase@2.81.3 test db
npx supabase@2.81.3 db advisors --local
```

Expected: all pgTAP suites pass and advisors report no new issue caused by the triggers.

- [ ] **Step 5: Commit the invariant migration and test**

```powershell
git add supabase/tests/tenant_content_links_test.sql supabase/migrations/*_enforce_tenant_content_links.sql
git commit -m "fix(db): enforce tenant-consistent content links"
```

---

### Task 3: Return Explicit Assignment Errors from the Edge Function

**Files:**
- Create: `supabase/functions/assign-playlist/validation.ts`
- Create: `supabase/functions/assign-playlist/validation.test.ts`
- Modify: `supabase/functions/assign-playlist/index.ts`

**Interfaces:**
- Consumes: device row `{establishment_id, fcm_token, revoked_at}` and optional playlist row `{establishment_id}`.
- Produces: `validateAssignment(device, playlistId, playlist): AssignmentValidationError | null`.

- [ ] **Step 1: Write failing Deno validation tests**

Create `validation.test.ts`:

```ts
import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { validateAssignment } from './validation.ts';

const device = {
  establishment_id: 'est-a',
  fcm_token: 'token',
  revoked_at: null,
};

Deno.test('missing device returns 404', () => {
  assertEquals(validateAssignment(null, 'playlist-a', { establishment_id: 'est-a' }), {
    status: 404,
    error: 'Device not found',
  });
});

Deno.test('missing playlist returns 404', () => {
  assertEquals(validateAssignment(device, 'playlist-a', null), {
    status: 404,
    error: 'Playlist not found',
  });
});

Deno.test('cross-tenant assignment returns 409', () => {
  assertEquals(validateAssignment(device, 'playlist-b', { establishment_id: 'est-b' }), {
    status: 409,
    error: 'Device and playlist must belong to the same establishment',
  });
});

Deno.test('same-tenant assignment and unassignment are valid', () => {
  assertEquals(validateAssignment(device, 'playlist-a', { establishment_id: 'est-a' }), null);
  assertEquals(validateAssignment(device, null, null), null);
});
```

- [ ] **Step 2: Run the new test and verify it fails**

```powershell
deno test supabase/functions/assign-playlist/validation.test.ts
```

Expected: FAIL because `validation.ts` does not exist.

- [ ] **Step 3: Implement the pure validator**

Create `validation.ts`:

```ts
export type DeviceAssignmentRow = {
  establishment_id: string;
  fcm_token: string | null;
  revoked_at: string | null;
};

export type PlaylistAssignmentRow = { establishment_id: string };

export type AssignmentValidationError = {
  status: 404 | 409;
  error: string;
};

export function validateAssignment(
  device: DeviceAssignmentRow | null,
  playlistId: string | null,
  playlist: PlaylistAssignmentRow | null,
): AssignmentValidationError | null {
  if (device === null) return { status: 404, error: 'Device not found' };
  if (playlistId === null) return null;
  if (playlist === null) return { status: 404, error: 'Playlist not found' };
  if (device.establishment_id !== playlist.establishment_id) {
    return {
      status: 409,
      error: 'Device and playlist must belong to the same establishment',
    };
  }
  return null;
}
```

- [ ] **Step 4: Refactor `index.ts` to validate before mutating**

Import the validator, fetch the device immediately after creating the service-role client, and fetch the playlist only when `playlistId` is non-null:

```ts
import { validateAssignment } from './validation.ts';

const { data: device, error: deviceError } = await admin
  .from('devices')
  .select('establishment_id, fcm_token, revoked_at')
  .eq('id', deviceId)
  .maybeSingle();
if (deviceError) return json({ error: 'Device lookup failed' }, 500);

let playlist: { establishment_id: string } | null = null;
if (playlistId) {
  const { data, error: playlistError } = await admin
    .from('playlists')
    .select('establishment_id')
    .eq('id', playlistId)
    .maybeSingle();
  if (playlistError) return json({ error: 'Playlist lookup failed' }, 500);
  playlist = data;
}

const validation = validateAssignment(device, playlistId ?? null, playlist);
if (validation) return json({ error: validation.error }, validation.status);
```

Keep the existing upsert/delete and FCM dispatch after this block. If the upsert
returns Postgres code `23514`, map it to the same `409` response because the
database trigger may win a race after prevalidation. Map other write errors to
`500`. Remove the later duplicate device query and use the already loaded
`device` for push dispatch.

- [ ] **Step 5: Format and run all Deno tests**

```powershell
deno fmt supabase/functions/assign-playlist
deno test --allow-env supabase/functions
```

Expected: four new validation tests and all existing Deno tests pass; the live-FCM integration test remains ignored.

- [ ] **Step 6: Commit the Edge Function validation**

```powershell
git add supabase/functions/assign-playlist
git commit -m "fix(functions): reject cross-tenant playlist assignments"
```

---

### Task 4: Register FCM Through the Device HTTP Client

**Files:**
- Modify: `apps/player/lib/data/remote/sync_api_client.dart`
- Modify: `apps/player/lib/services/fcm_handler.dart`
- Modify: `apps/player/lib/features/player/presentation/player_screen.dart`
- Create: `apps/player/test/data/remote/sync_api_client_test.dart`
- Modify: `apps/player/test/services/fcm_handler_test.dart`

**Interfaces:**
- Consumes: `DeviceCredentials` and `syncApiClientProvider(credentials)`.
- Produces: `SyncApiClient.registerFcmToken(String token)` and best-effort `FcmHandler.registerToken(String token)` delegation.

- [ ] **Step 1: Write the failing HTTP client test**

Create `sync_api_client_test.dart`:

```dart
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:player/data/remote/sync_api_client.dart';

class _MockDio extends Mock implements Dio {}

void main() {
  setUpAll(() => registerFallbackValue(Options()));

  test('registerFcmToken posts token with device authentication', () async {
    final dio = _MockDio();
    when(
      () => dio.post<dynamic>(
        any(),
        data: any(named: 'data'),
        options: any(named: 'options'),
      ),
    ).thenAnswer(
      (_) async => Response<dynamic>(
        requestOptions: RequestOptions(path: ''),
        statusCode: 204,
      ),
    );
    final client = SyncApiClient(
      baseUrl: 'https://project.supabase.co',
      anonKey: 'publishable-key',
      deviceJwt: 'device-jwt',
      dio: dio,
    );

    await client.registerFcmToken('fcm-123');

    final captured = verify(
      () => dio.post<dynamic>(
        captureAny(),
        data: captureAny(named: 'data'),
        options: captureAny(named: 'options'),
      ),
    ).captured;
    final capturedUrl = captured[0] as String;
    final capturedData = captured[1];
    final capturedOptions = captured[2] as Options;
    expect(
      capturedUrl,
      'https://project.supabase.co/rest/v1/rpc/register_device_fcm_token',
    );
    expect(jsonDecode(capturedData as String), {'p_token': 'fcm-123'});
    expect(capturedOptions.headers?['apikey'], 'publishable-key');
    expect(capturedOptions.headers?['Authorization'], 'Bearer device-jwt');
    expect(capturedOptions.headers?['Content-Type'], 'application/json');
  });
}
```

- [ ] **Step 2: Write failing handler delegation tests**

Add these imports and mock to `fcm_handler_test.dart`:

```dart
import 'package:mocktail/mocktail.dart';
import 'package:player/data/providers.dart';
import 'package:player/data/remote/sync_api_client.dart';
import 'package:player/providers.dart';
import 'package:player/services/secure_storage.dart';

class _MockSyncApiClient extends Mock implements SyncApiClient {}
```

Add these three complete tests inside `main()`:

```dart
test('registerToken delegates to device API client', () async {
  final api = _MockSyncApiClient();
  when(() => api.registerFcmToken(any())).thenAnswer((_) async {});
  final container = ProviderContainer(
    overrides: [
      credentialsProvider.overrideWith(
        (ref) async =>
            const DeviceCredentials(deviceId: 'device-1', jwt: 'jwt-1'),
      ),
      syncApiClientProvider.overrideWith((ref, creds) => api),
    ],
  );
  addTearDown(container.dispose);

  await FcmHandlerImpl(ref: container).registerToken('fcm-123');

  verify(() => api.registerFcmToken('fcm-123')).called(1);
});

test('registerToken does nothing before pairing', () async {
  final api = _MockSyncApiClient();
  final container = ProviderContainer(
    overrides: [
      credentialsProvider.overrideWith((ref) async => null),
      syncApiClientProvider.overrideWith((ref, creds) => api),
    ],
  );
  addTearDown(container.dispose);

  await FcmHandlerImpl(ref: container).registerToken('fcm-123');

  verifyNever(() => api.registerFcmToken(any()));
});

test('registerToken swallows network errors to preserve playback', () async {
  final api = _MockSyncApiClient();
  when(() => api.registerFcmToken(any())).thenThrow(Exception('offline'));
  final container = ProviderContainer(
    overrides: [
      credentialsProvider.overrideWith(
        (ref) async =>
            const DeviceCredentials(deviceId: 'device-1', jwt: 'jwt-1'),
      ),
      syncApiClientProvider.overrideWith((ref, creds) => api),
    ],
  );
  addTearDown(container.dispose);

  await expectLater(
    FcmHandlerImpl(ref: container).registerToken('fcm-123'),
    completes,
  );
});
```

- [ ] **Step 3: Run the focused tests and verify they fail**

```powershell
Push-Location apps/player
flutter test test/data/remote/sync_api_client_test.dart test/services/fcm_handler_test.dart
Pop-Location
```

Expected: FAIL because `registerFcmToken` does not exist and the handler still uses `Supabase.instance.client`.

- [ ] **Step 4: Add the RPC call to `SyncApiClient`**

Add this method:

```dart
Future<void> registerFcmToken(String token) async {
  await _dio.post<dynamic>(
    '$baseUrl/rest/v1/rpc/register_device_fcm_token',
    data: jsonEncode({'p_token': token}),
    options: Options(
      headers: {..._headers, 'Content-Type': 'application/json'},
    ),
  );
}
```

- [ ] **Step 5: Replace the Supabase singleton in `FcmHandlerImpl`**

Remove the `supabase_flutter` import, the optional `SupabaseClient`, and `_client`. Import `player/data/providers.dart` and implement registration as:

```dart
@override
Future<void> registerToken(String token) async {
  try {
    final creds = await ref.read(credentialsProvider.future);
    if (creds == null) return;
    await ref.read(syncApiClientProvider(creds)).registerFcmToken(token);
  } catch (_) {
    // Best effort. Polling remains the safety net.
  }
}
```

- [ ] **Step 6: Retry token registration on connectivity recovery**

Update the existing connectivity listener in `player_screen.dart`:

```dart
if (hasNetwork) {
  unawaited(_runSync());
  unawaited(ref.read(fcmHandlerProvider).registerCurrentToken());
}
```

Startup and post-pairing registration remain covered by `_bootstrap()`, which runs after `credentialsProvider` is invalidated with the newly stored credentials.

- [ ] **Step 7: Format and run the player suite**

```powershell
dart format apps/player/lib/data/remote/sync_api_client.dart apps/player/lib/services/fcm_handler.dart apps/player/lib/features/player/presentation/player_screen.dart apps/player/test/data/remote/sync_api_client_test.dart apps/player/test/services/fcm_handler_test.dart
Push-Location apps/player
flutter test
Pop-Location
```

Expected: all player tests pass, including the new RPC and handler tests.

- [ ] **Step 8: Commit the player FCM transport**

```powershell
git add apps/player/lib/data/remote/sync_api_client.dart apps/player/lib/services/fcm_handler.dart apps/player/lib/features/player/presentation/player_screen.dart apps/player/test/data/remote/sync_api_client_test.dart apps/player/test/services/fcm_handler_test.dart
git commit -m "fix(player): register FCM token with device JWT"
```

---

### Task 5: Make Active Playlist State Atomic

**Files:**
- Modify: `apps/player/lib/data/local/app_database.dart`
- Modify: `apps/player/lib/data/sync_service.dart`
- Modify: `apps/player/lib/data/providers.dart`
- Create: `apps/player/test/data/local/active_playlist_test.dart`
- Create: `apps/player/test/data/sync_service_test.dart`

**Interfaces:**
- Produces: `AppDatabase.getActivePlaylist()`, `replaceActivePlaylist(playlist, items)`, and `clearActivePlaylist()`.
- Produces: `SyncAssignmentState { assigned, unassigned }` and non-null `Future<SyncResult> sync()`.

- [ ] **Step 1: Write failing Drift replacement and clearing tests**

Create `active_playlist_test.dart`:

```dart
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/data/local/app_database.dart';

CachedPlaylistCompanion _playlist(String id) => CachedPlaylistCompanion(
      id: Value(id),
      establishmentId: const Value('establishment-1'),
      name: Value(id),
      version: const Value(1),
      audioEnabled: const Value(false),
    );

CachedPlaylistItemsCompanion _item(String id, String playlistId) =>
    CachedPlaylistItemsCompanion(
      id: Value(id),
      playlistId: Value(playlistId),
      mediaId: const Value('media-a'),
      position: const Value(0),
    );

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('replaceActivePlaylist leaves exactly one playlist and its items',
      () async {
    await db.replaceActivePlaylist(
      _playlist('playlist-a'),
      [_item('item-a', 'playlist-a')],
    );
    await db.replaceActivePlaylist(
      _playlist('playlist-b'),
      [_item('item-b', 'playlist-b')],
    );

    final playlists = await db.select(db.cachedPlaylist).get();
    expect(playlists.map((playlist) => playlist.id).toList(), ['playlist-b']);
    expect(await db.itemsFor('playlist-a'), isEmpty);
    expect((await db.itemsFor('playlist-b')).single.id, 'item-b');
  });

  test('clearActivePlaylist removes logical state but retains media metadata',
      () async {
    await db.replaceActivePlaylist(
      _playlist('playlist-a'),
      [_item('item-a', 'playlist-a')],
    );
    await db.upsertMedia(
      const CachedMediaCompanion(
        id: Value('media-a'),
        establishmentId: Value('establishment-1'),
        type: Value('image'),
        filePath: Value('establishment-1/media-a.jpg'),
        fileSize: Value(100),
        mimeType: Value('image/jpeg'),
        checksumSha256: Value('checksum-a'),
        originalFilename: Value('media-a.jpg'),
      ),
    );

    await db.clearActivePlaylist();

    expect(await db.getActivePlaylist(), isNull);
    expect(await db.itemsFor('playlist-a'), isEmpty);
    expect(await db.getMedia('media-a'), isNotNull);
  });
}
```

- [ ] **Step 2: Write the failing unassignment sync test**

Create `sync_service_test.dart`:

```dart
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:player/data/local/app_database.dart';
import 'package:player/data/local/cache_storage.dart';
import 'package:player/data/remote/sync_api_client.dart';
import 'package:player/data/sync_service.dart';

class _MockSyncApiClient extends Mock implements SyncApiClient {}
class _MockCacheStorage extends Mock implements CacheStorage {}

void main() {
  late AppDatabase db;
  late _MockSyncApiClient api;
  late _MockCacheStorage storage;

  setUpAll(() => registerFallbackValue(<String>{}));

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    api = _MockSyncApiClient();
    storage = _MockCacheStorage();
    await db.replaceActivePlaylist(
      const CachedPlaylistCompanion(
        id: Value('playlist-a'),
        establishmentId: Value('establishment-1'),
        name: Value('Playlist A'),
        version: Value(1),
        audioEnabled: Value(false),
      ),
      const [],
    );
  });

  tearDown(() => db.close());

  test('remote unassignment clears active state and releases LRU protection',
      () async {
    when(() => api.getMyDevicePlaylistAssignment('device-1'))
        .thenAnswer((_) async => null);
    when(() => storage.purgeLruIfNeeded(any())).thenAnswer((_) async => 0);

    final result = await SyncService(
      api: api,
      db: db,
      storage: storage,
      deviceId: 'device-1',
    ).sync();

    expect(result.state, SyncAssignmentState.unassigned);
    expect(await db.getActivePlaylist(), isNull);
    final captured = verify(
      () => storage.purgeLruIfNeeded(captureAny()),
    ).captured.single as Set<String>;
    expect(captured, isEmpty);
  });
}
```

- [ ] **Step 3: Run focused tests and verify they fail**

```powershell
Push-Location apps/player
flutter test test/data/local/active_playlist_test.dart test/data/sync_service_test.dart
Pop-Location
```

Expected: FAIL because the atomic database methods and explicit assignment state do not exist.

- [ ] **Step 4: Add atomic active-playlist operations**

Replace `upsertPlaylist` and `replaceItems` with:

```dart
Future<CachedPlaylistData?> getActivePlaylist() =>
    select(cachedPlaylist).getSingleOrNull();

Future<void> replaceActivePlaylist(
  CachedPlaylistCompanion playlist,
  List<CachedPlaylistItemsCompanion> items,
) async {
  await transaction(() async {
    await delete(cachedPlaylistItems).go();
    await delete(cachedPlaylist).go();
    await into(cachedPlaylist).insert(playlist);
    if (items.isNotEmpty) {
      await batch((batch) => batch.insertAll(cachedPlaylistItems, items));
    }
  });
}

Future<void> clearActivePlaylist() async {
  await transaction(() async {
    await delete(cachedPlaylistItems).go();
    await delete(cachedPlaylist).go();
  });
}
```

No Drift schema migration or generated-code change is required because table definitions are unchanged.

- [ ] **Step 5: Make the sync outcome explicit**

Add:

```dart
enum SyncAssignmentState { assigned, unassigned }

class SyncResult {
  const SyncResult.assigned({
    required this.playlistVersion,
    required this.itemCount,
    required this.downloadedCount,
    required this.purgedCount,
  }) : state = SyncAssignmentState.assigned;

  const SyncResult.unassigned({required this.purgedCount})
      : state = SyncAssignmentState.unassigned,
        playlistVersion = 0,
        itemCount = 0,
        downloadedCount = 0;

  final SyncAssignmentState state;
  final int playlistVersion;
  final int itemCount;
  final int downloadedCount;
  final int purgedCount;
}
```

Change `sync()` to return `Future<SyncResult>`. Handle no assignment first:

```dart
if (playlistId == null) {
  await db.clearActivePlaylist();
  final purged = await storage.purgeLruIfNeeded(<String>{});
  return SyncResult.unassigned(purgedCount: purged);
}
```

For an assignment, build the playlist and item companions, then call
`db.replaceActivePlaylist(playlistCompanion, itemCompanions)`. Return
`SyncResult.assigned(...)` after downloads and LRU processing.

- [ ] **Step 6: Stop selecting an arbitrary playlist**

Replace `cachedPlaylistProvider`'s `all.first` logic with:

```dart
final cachedPlaylistProvider = FutureProvider<CachedPlaylistData?>((ref) {
  return ref.watch(appDatabaseProvider).getActivePlaylist();
});
```

- [ ] **Step 7: Format and run the full player suite**

```powershell
dart format apps/player/lib/data/local/app_database.dart apps/player/lib/data/sync_service.dart apps/player/lib/data/providers.dart apps/player/test/data/local/active_playlist_test.dart apps/player/test/data/sync_service_test.dart
Push-Location apps/player
flutter test
Pop-Location
```

Expected: all existing and new player tests pass. The unassignment test proves logical cache removal while the Drift test proves media metadata remains available for LRU handling.

- [ ] **Step 8: Commit atomic playlist state**

```powershell
git add apps/player/lib/data/local/app_database.dart apps/player/lib/data/sync_service.dart apps/player/lib/data/providers.dart apps/player/test/data/local/active_playlist_test.dart apps/player/test/data/sync_service_test.dart
git commit -m "fix(player): clear stale playlist assignments"
```

---

### Task 6: Full Local Verification and Cloud Deployment Gate

**Files:**
- Create: `docs/phase10a-demo.md`

**Interfaces:**
- Consumes: all commits from Tasks 1–5.
- Produces: an evidence report with exact command results and a hard stop before Cloud mutation.

- [ ] **Step 1: Verify formatting and static analysis**

```powershell
dart format --output=none --set-exit-if-changed apps/player/lib apps/player/test
deno fmt --check supabase/functions
Push-Location packages/shared
flutter analyze --no-pub
Pop-Location
Push-Location apps/backoffice
flutter analyze --no-pub
Pop-Location
Push-Location apps/player
flutter analyze --no-pub
Pop-Location
```

Expected: formatting checks exit `0`; analysis introduces no error-level diagnostic. Record pre-existing warnings/info separately rather than claiming the repository is lint-clean.

- [ ] **Step 2: Run every automated suite**

```powershell
Push-Location packages/shared
flutter test --no-pub
Pop-Location
Push-Location apps/backoffice
flutter test --no-pub
Pop-Location
Push-Location apps/player
flutter test --no-pub
Pop-Location
deno test --allow-env supabase/functions
npx supabase@2.81.3 db reset --local
npx supabase@2.81.3 test db
npx supabase@2.81.3 db advisors --local
```

Expected: every non-ignored test passes, database reset succeeds, and advisors show no new issue introduced by this lot.

- [ ] **Step 3: Verify the Android build precondition and build locally**

```powershell
Test-Path apps/player/android/app/google-services.json
```

Expected: `True`. If it is `False`, stop and follow `docs/firebase-setup.md`; do not fabricate or commit the file.

From an elevated PowerShell session:

```powershell
Push-Location apps/player
flutter build apk --debug `
  --dart-define=SUPABASE_URL=$env:SUPABASE_URL `
  --dart-define=SUPABASE_ANON_KEY=$env:SUPABASE_ANON_KEY
Pop-Location
```

Expected: build exits `0` and produces `apps/player/build/app/outputs/flutter-apk/app-debug.apk`. The environment variables must contain the intended validation endpoint and public key; never paste secrets into the plan or commit them.

- [ ] **Step 4: Write the verification and UAT guide**

Create `docs/phase10a-demo.md` with:

- exact test counts and command exit codes;
- analyzer warning counts, explicitly separated from errors;
- local RPC test procedure for valid, human, and revoked JWT contexts;
- same-tenant assignment and cross-tenant rejection checks;
- device flow: assignment A, switch to B, unassignment to standby, reassignment;
- FCM token verification in the device detail/admin diagnostic;
- statement that no Cloud command has run yet.

- [ ] **Step 5: Inspect the production-sensitive commands without running them**

```powershell
npx supabase@2.81.3 db push --help
npx supabase@2.81.3 functions deploy --help
npx supabase@2.81.3 migration list
```

Expected: help text is available and the linked migration list can be compared with local history. Do not execute `db push` or `functions deploy` in this step.

- [ ] **Step 6: Commit the verification guide**

```powershell
git add docs/phase10a-demo.md
git commit -m "docs(security): add reliability verification guide"
```

- [ ] **Step 7: Present the evidence and stop**

Present the local test results, migration names, advisor output, APK build result, Git status, and the exact two production commands that would run next. Wait for a new explicit user approval before Task 7.

---

### Task 7: Deploy to Supabase Cloud and Perform UAT

**Gate:** This task is forbidden until the user explicitly approves deployment after reviewing Task 6 evidence.

**Files:**
- Modify only if observations require documentation updates: `docs/phase10a-demo.md`

**Interfaces:**
- Consumes: linked project `mnoeteagkcqlrchyudju` and the verified local migration history.
- Produces: Cloud schema with the two migrations, updated `assign-playlist`, and observed device UAT.

- [ ] **Step 1: Reconfirm the linked target**

```powershell
npx supabase@2.81.3 projects list
npx supabase@2.81.3 migration list
```

Expected: the selected project reference is exactly `mnoeteagkcqlrchyudju`. Stop if it differs.

- [ ] **Step 2: Push the reviewed migrations**

```powershell
npx supabase@2.81.3 db push
```

Expected: only `_secure_device_fcm_registration.sql` and `_enforce_tenant_content_links.sql` are applied. Stop on any additional pending migration.

- [ ] **Step 3: Deploy the validated Edge Function**

```powershell
npx supabase@2.81.3 functions deploy assign-playlist --project-ref mnoeteagkcqlrchyudju
```

Expected: deployment succeeds and the function remains configured consistently with `supabase/config.toml`.

- [ ] **Step 4: Run Cloud smoke checks with a dedicated validation device**

Using the back-office and the signed validation APK:

1. pair the dedicated validation device without touching existing device rows;
2. confirm its FCM token becomes non-null after startup;
3. assign a same-establishment playlist and verify playback;
4. change to another same-establishment playlist and verify only the new playlist plays;
5. unassign and verify the standby screen appears after FCM or manual reconnect;
6. reassign and verify cached media can be reused;
7. confirm an existing production device remains paired and continues playback/polling.

- [ ] **Step 5: Record UAT evidence and commit only documentation**

Append the exact Cloud migration status, function deployment time, validation device result, and existing-device regression result to `docs/phase10a-demo.md`. Do not include IDs, JWTs, FCM tokens, keys, or account credentials.

```powershell
git add docs/phase10a-demo.md
git commit -m "docs(security): record cloud reliability UAT"
```

---

## Completion Checklist

- [ ] Direct device UPDATE is denied and the FCM RPC is the only device-authenticated path that can change a device token.
- [ ] Human and revoked JWTs cannot use the FCM RPC.
- [ ] Both cross-tenant relationship types are impossible at database level.
- [ ] `assign-playlist` returns deterministic `404` and `409` responses.
- [ ] Player FCM registration uses the device JWT HTTP client and retries after reconnect.
- [ ] Unassignment clears active Drift state and displays standby.
- [ ] Switching assignments leaves exactly one active local playlist.
- [ ] Media files and metadata survive logical unassignment until LRU needs space.
- [ ] Flutter, Deno, pgTAP, advisors, and Android build evidence are recorded.
- [ ] Cloud deployment occurs only after the explicit post-verification approval gate.
