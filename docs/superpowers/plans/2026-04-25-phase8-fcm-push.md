# Phase 8 — FCM Push Instantané — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ramener à < 5 secondes la latence entre un événement admin (publish playlist / assign-detach / revoke device) et la réaction côté Player Android, en utilisant FCM HTTP v1 data messages dispatchés par 3 nouvelles Edge Functions Deno qui remplacent les écritures DB directes du backoffice.

**Architecture:** 3 Edge Functions (`publish-playlist`, `assign-playlist`, `revoke-device`) appellent un `FcmDispatcher` partagé qui parle à FCM HTTP v1 via OAuth2 service account. Player Android intègre Firebase Messaging via SDK natif + bridge MethodChannel `app.player/fcm` vers un `FcmHandler` Dart qui (1) persiste le token via la policy RLS `devices_self_update_heartbeat`, et (2) bump `forceSyncRequestProvider` (ajouté en Phase 9) ou `fcmRevokedSignalProvider` (nouveau) selon le type de message. Mode `LOG_ONLY` activé si `FIREBASE_SERVICE_ACCOUNT` absent → permet le dev local sans Firebase. Polling 15min reste comme safety net.

**Tech Stack:** Deno + djwt (existant), `jsr:@supabase/supabase-js@^2.46.0`, FCM HTTP v1 API, Firebase Android SDK BoM 34.12.0 + `firebase-messaging`, plugin Gradle `com.google.gms.google-services:4.4.4`, Dart 3.6 + Riverpod, mocktail.

**Spec source:** [`docs/superpowers/specs/2026-04-25-phase8-fcm-push-design.md`](../specs/2026-04-25-phase8-fcm-push-design.md)

---

## Task 1 : .gitignore + placeholder Firebase config

**Files:**
- Modify: `.gitignore`
- Create: `apps/player/android/app/google-services.json.example`
- Create: `docs/firebase-setup.md`

- [ ] **Step 1: Update root .gitignore**

Append to `D:/App de diffusion/.gitignore` :

```gitignore
# Firebase (Phase 8) — secrets & generated config
apps/player/android/app/google-services.json
*.serviceaccount.json
*-firebase-adminsdk-*.json
```

- [ ] **Step 2: Create example template for google-services.json**

Create `apps/player/android/app/google-services.json.example` :

```json
{
  "project_info": {
    "project_number": "REPLACE_WITH_YOUR_PROJECT_NUMBER",
    "project_id": "REPLACE_WITH_YOUR_PROJECT_ID",
    "storage_bucket": "REPLACE_WITH_YOUR_PROJECT_ID.appspot.com"
  },
  "client": [
    {
      "client_info": {
        "mobilesdk_app_id": "REPLACE_WITH_YOUR_APP_ID",
        "android_client_info": {
          "package_name": "com.appdiffusion.player"
        }
      },
      "api_key": [
        { "current_key": "REPLACE_WITH_YOUR_API_KEY" }
      ]
    }
  ],
  "configuration_version": "1"
}
```

- [ ] **Step 3: Create Firebase setup doc**

Create `docs/firebase-setup.md` :

````markdown
# Firebase setup pour Phase 8 (FCM)

À faire une fois, manuellement, avant la démo Phase 8.

## 1. Créer le project Firebase

1. Aller sur https://console.firebase.google.com
2. **Add project** → nom : `App-de-Diffusion-Prod` (ou ce que tu veux)
3. Désactiver Google Analytics (pas utile pour notre cas)

## 2. Ajouter l'app Android

1. Dans le project Firebase → icône Android → **Add app**
2. **Android package name** : `com.appdiffusion.player` (impératif — doit matcher
   `applicationId` dans `apps/player/android/app/build.gradle.kts`)
3. App nickname : `Player Android`
4. Skip SHA-1 (pas requis pour FCM)
5. **Download `google-services.json`** → poser dans `apps/player/android/app/`

⚠️ Ce fichier est dans `.gitignore`, ne le commit JAMAIS.

## 3. Récupérer le service account JSON pour les Edge Functions

1. Project Settings (⚙️) → **Service accounts**
2. **Generate new private key** → confirme → JSON téléchargé
3. Renomme en `firebase-serviceaccount.json` (mais ne le pose nulle part dans le repo)

## 4. Configurer le secret Supabase

```bash
cd "D:/App de diffusion"

# Pour Supabase local (dev) :
echo 'FIREBASE_SERVICE_ACCOUNT=<contenu_json_minifié_sur_une_ligne>' >> supabase/.env.local

# Pour Supabase Cloud (prod) :
supabase secrets set FIREBASE_SERVICE_ACCOUNT="$(cat ~/Downloads/firebase-serviceaccount.json)"
```

Pour minifier le JSON sur une ligne :
```bash
cat firebase-serviceaccount.json | jq -c .
```

## 5. Vérifier

Au prochain démarrage du Player après pairing, vérifier que `devices.fcm_token`
est non-NULL :

```sql
docker exec supabase_db_App_de_diffusion psql -U postgres -d postgres -c \
  "select id, name, fcm_token is not null as has_token from public.devices;"
```

Si `has_token = true` partout → FCM marche côté Player.

## Mode LOG_ONLY (sans Firebase)

Si `FIREBASE_SERVICE_ACCOUNT` n'est pas défini (cas dev local sans avoir fait
les étapes ci-dessus), les Edge Functions logguent les push qu'elles auraient
envoyés sans rien envoyer. Le polling 15min reste actif → tout marche, juste
sans le bonus de réactivité instantanée.
````

- [ ] **Step 4: Commit**

```bash
cd "D:/App de diffusion" && git add .gitignore apps/player/android/app/google-services.json.example docs/firebase-setup.md && git commit -m "chore(phase8): gitignore Firebase secrets + setup doc"
```

---

## Task 2 : Configuration Gradle Android (Firebase BoM + plugin google-services)

**Files:**
- Modify: `apps/player/android/build.gradle.kts`
- Modify: `apps/player/android/app/build.gradle.kts`

- [ ] **Step 1: Read current state of both gradle files**

Use Read tool on :
- `D:/App de diffusion/apps/player/android/build.gradle.kts`
- `D:/App de diffusion/apps/player/android/app/build.gradle.kts`

- [ ] **Step 2: Add google-services plugin declaration in project-level build.gradle.kts**

In `apps/player/android/build.gradle.kts`, locate the `plugins { ... }` block at the top (or create one if absent) and ADD :

```kotlin
plugins {
    id("com.google.gms.google-services") version "4.4.4" apply false
}
```

If the file currently has no `plugins` block at the top (only buildscript / allprojects / etc.), prepend the block at line 1.

- [ ] **Step 3: Apply the plugin + Firebase BoM in app-level build.gradle.kts**

In `apps/player/android/app/build.gradle.kts`, in the existing `plugins { ... }` block at the top of the file, ADD :

```kotlin
    id("com.google.gms.google-services")
```

In the `dependencies { ... }` block, ADD at the end :

```kotlin
    // Firebase (Phase 8 — FCM push)
    implementation(platform("com.google.firebase:firebase-bom:34.12.0"))
    implementation("com.google.firebase:firebase-messaging")
```

- [ ] **Step 4: Create a stub google-services.json for build to succeed**

Build will fail if the file is missing. Copy the example as a stub :

```bash
cp "D:/App de diffusion/apps/player/android/app/google-services.json.example" "D:/App de diffusion/apps/player/android/app/google-services.json"
```

⚠️ This stub has placeholder values. The real one (with valid project numbers) must be put in place before running on device. The stub allows `flutter analyze` and `pub get` to succeed during dev.

- [ ] **Step 5: Sanity check — analyze (Android-side gradle issues won't surface here, but Dart will be clean)**

```bash
cd "D:/App de diffusion/apps/player" && flutter pub get && flutter analyze
```

Expected : `No issues found!` (analyze) ; pub get OK.

A full Android gradle build will only be possible once the real `google-services.json` is in place (per Task 1's Firebase setup doc). Stub gradle build will fail with "invalid project number" — this is expected.

- [ ] **Step 6: Commit**

```bash
cd "D:/App de diffusion" && git add apps/player/android/build.gradle.kts apps/player/android/app/build.gradle.kts && git commit -m "feat(player): add Firebase BoM + google-services plugin for FCM"
```

---

## Task 3 : `FcmDispatcher` Deno helper (OAuth2 + FCM v1 + LOG_ONLY)

**Files:**
- Create: `supabase/functions/_shared/fcm_dispatcher.ts`
- Test: `supabase/functions/_shared/fcm_dispatcher.test.ts`

- [ ] **Step 1: Write failing tests**

Create `supabase/functions/_shared/fcm_dispatcher.test.ts` :

```typescript
import { assertEquals, assertExists } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { createFcmDispatcher } from './fcm_dispatcher.ts';

Deno.test('LOG_ONLY mode when FIREBASE_SERVICE_ACCOUNT is absent', async () => {
  Deno.env.delete('FIREBASE_SERVICE_ACCOUNT');
  const dispatcher = createFcmDispatcher();
  const result = await dispatcher.send('fake-token', { type: 'playlist_published' });
  assertEquals(result.ok, false);
  if (!result.ok) assertEquals(result.reason, 'log_only');
});

Deno.test('sendMany returns batch result with okCount and unregisteredOwnerIds', async () => {
  Deno.env.delete('FIREBASE_SERVICE_ACCOUNT');
  const dispatcher = createFcmDispatcher();
  const result = await dispatcher.sendMany(
    [
      { token: 't1', ownerId: 'o1' },
      { token: 't2', ownerId: 'o2' },
    ],
    { type: 'playlist_published' },
  );
  // En LOG_ONLY, aucun envoi réel : okCount = 0, mais on ne wipe pas non plus.
  assertEquals(result.okCount, 0);
  assertEquals(result.unregisteredOwnerIds.length, 0);
  assertEquals(result.errors.length, 2);
});

Deno.test('parses UNREGISTERED response as wipe-able', async () => {
  // Mock fetch globally to simulate FCM returning UNREGISTERED
  const fakeServiceAccount = JSON.stringify({
    project_id: 'test-project',
    client_email: 'svc@test.iam.gserviceaccount.com',
    private_key: '-----BEGIN PRIVATE KEY-----\nMIIE...\n-----END PRIVATE KEY-----\n',
    private_key_id: 'kid1',
  });
  Deno.env.set('FIREBASE_SERVICE_ACCOUNT', fakeServiceAccount);

  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (url: string | URL | Request, _init?: RequestInit) => {
    const u = url.toString();
    if (u.includes('oauth2.googleapis.com/token')) {
      return new Response(
        JSON.stringify({ access_token: 'fake-access', expires_in: 3600 }),
        { status: 200 },
      );
    }
    if (u.includes('fcm.googleapis.com')) {
      return new Response(
        JSON.stringify({
          error: {
            code: 404,
            status: 'NOT_FOUND',
            message: 'Requested entity was not found.',
            details: [
              {
                '@type': 'type.googleapis.com/google.firebase.fcm.v1.FcmError',
                errorCode: 'UNREGISTERED',
              },
            ],
          },
        }),
        { status: 404 },
      );
    }
    return new Response('not found', { status: 404 });
  };

  try {
    const dispatcher = createFcmDispatcher();
    const result = await dispatcher.sendMany(
      [{ token: 'stale-token', ownerId: 'owner-1' }],
      { type: 'playlist_published' },
    );
    assertEquals(result.okCount, 0);
    assertEquals(result.unregisteredOwnerIds, ['owner-1']);
  } finally {
    globalThis.fetch = originalFetch;
    Deno.env.delete('FIREBASE_SERVICE_ACCOUNT');
  }
});
```

- [ ] **Step 2: Run tests, verify they fail**

```bash
cd "D:/App de diffusion" && deno test --allow-env --allow-net --allow-read supabase/functions/_shared/fcm_dispatcher.test.ts 2>&1 | tail -10
```

Expected : FAIL with "Module not found ./fcm_dispatcher.ts" or similar.

- [ ] **Step 3: Implement `FcmDispatcher`**

Create `supabase/functions/_shared/fcm_dispatcher.ts` :

```typescript
import { create as createJwt, getNumericDate } from 'https://deno.land/x/djwt@v3.0.1/mod.ts';

export interface FcmDispatcher {
  send(token: string, data: Record<string, string>): Promise<FcmResult>;
  sendMany(
    pairs: Array<{ token: string; ownerId: string }>,
    data: Record<string, string>,
  ): Promise<FcmBatchResult>;
}

export type FcmResult =
  | { ok: true }
  | {
      ok: false;
      reason: 'unregistered' | 'invalid_token' | 'transient' | 'log_only';
      error?: string;
    };

export interface FcmBatchResult {
  okCount: number;
  unregisteredOwnerIds: string[];
  errors: Array<{ ownerId: string; reason: string }>;
}

interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
  private_key_id: string;
}

interface CachedAccessToken {
  token: string;
  expiresAt: number; // epoch ms
}

class _FcmDispatcher implements FcmDispatcher {
  private tokenCache: CachedAccessToken | null = null;

  constructor(private readonly serviceAccount: ServiceAccount | null) {}

  async send(token: string, data: Record<string, string>): Promise<FcmResult> {
    if (!this.serviceAccount) {
      console.log(`[FCM LOG_ONLY] Would send to ${token}:`, JSON.stringify(data));
      return { ok: false, reason: 'log_only' };
    }

    const accessToken = await this.getAccessToken();
    const url =
      `https://fcm.googleapis.com/v1/projects/${this.serviceAccount.project_id}/messages:send`;
    const body = {
      message: {
        token,
        data,
        android: { priority: 'high', ttl: '300s' },
      },
    };

    let response: Response;
    try {
      response = await fetch(url, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(body),
      });
    } catch (e) {
      return { ok: false, reason: 'transient', error: String(e) };
    }

    if (response.ok) return { ok: true };

    const errBody = await response.json().catch(() => ({}));
    const fcmError = errBody?.error?.details?.find?.(
      (d: { errorCode?: string }) => d?.errorCode,
    )?.errorCode as string | undefined;

    if (fcmError === 'UNREGISTERED' || response.status === 404) {
      return { ok: false, reason: 'unregistered', error: fcmError ?? 'NOT_FOUND' };
    }
    if (fcmError === 'INVALID_ARGUMENT') {
      return { ok: false, reason: 'invalid_token', error: fcmError };
    }
    return { ok: false, reason: 'transient', error: `${response.status}: ${JSON.stringify(errBody)}` };
  }

  async sendMany(
    pairs: Array<{ token: string; ownerId: string }>,
    data: Record<string, string>,
  ): Promise<FcmBatchResult> {
    const results = await Promise.all(
      pairs.map(async (p) => ({ ownerId: p.ownerId, result: await this.send(p.token, data) })),
    );
    let okCount = 0;
    const unregisteredOwnerIds: string[] = [];
    const errors: Array<{ ownerId: string; reason: string }> = [];
    for (const r of results) {
      if (r.result.ok) okCount++;
      else if (r.result.reason === 'unregistered') unregisteredOwnerIds.push(r.ownerId);
      else errors.push({ ownerId: r.ownerId, reason: r.result.reason });
    }
    // En LOG_ONLY, on remonte les "envois" comme errors pour rester traçable
    return { okCount, unregisteredOwnerIds, errors };
  }

  private async getAccessToken(): Promise<string> {
    if (!this.serviceAccount) throw new Error('No service account');
    if (this.tokenCache && this.tokenCache.expiresAt > Date.now() + 60_000) {
      return this.tokenCache.token;
    }

    const now = getNumericDate(0);
    const exp = getNumericDate(60 * 60); // 1h
    const jwt = await createJwt(
      { alg: 'RS256', typ: 'JWT', kid: this.serviceAccount.private_key_id },
      {
        iss: this.serviceAccount.client_email,
        scope: 'https://www.googleapis.com/auth/firebase.messaging',
        aud: 'https://oauth2.googleapis.com/token',
        iat: now,
        exp,
      },
      await importPrivateKey(this.serviceAccount.private_key),
    );

    const tokenResponse = await fetch('https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        assertion: jwt,
      }),
    });

    if (!tokenResponse.ok) {
      const err = await tokenResponse.text();
      throw new Error(`OAuth2 token exchange failed: ${err}`);
    }

    const json = (await tokenResponse.json()) as { access_token: string; expires_in: number };
    this.tokenCache = {
      token: json.access_token,
      expiresAt: Date.now() + json.expires_in * 1000,
    };
    return this.tokenCache.token;
  }
}

async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const pemContents = pem
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replace(/\s/g, '');
  const binaryDer = Uint8Array.from(atob(pemContents), (c) => c.charCodeAt(0));
  return await crypto.subtle.importKey(
    'pkcs8',
    binaryDer.buffer,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
}

export function createFcmDispatcher(): FcmDispatcher {
  const raw = Deno.env.get('FIREBASE_SERVICE_ACCOUNT');
  if (!raw || raw.trim() === '') {
    return new _FcmDispatcher(null);
  }
  try {
    const parsed = JSON.parse(raw) as ServiceAccount;
    if (!parsed.project_id || !parsed.client_email || !parsed.private_key) {
      console.error('[FCM] FIREBASE_SERVICE_ACCOUNT is malformed, falling back to LOG_ONLY');
      return new _FcmDispatcher(null);
    }
    return new _FcmDispatcher(parsed);
  } catch (e) {
    console.error('[FCM] FIREBASE_SERVICE_ACCOUNT JSON parse failed, falling back to LOG_ONLY', e);
    return new _FcmDispatcher(null);
  }
}
```

- [ ] **Step 4: Run tests, verify they pass**

```bash
cd "D:/App de diffusion" && deno test --allow-env --allow-net --allow-read supabase/functions/_shared/fcm_dispatcher.test.ts 2>&1 | tail -10
```

Expected : 3 tests passed. If the third test fails because of djwt RS256 key parse issues with the fake key, document the deviation in your report and SKIP that specific test (mark it `Deno.test.ignore`) — the LOG_ONLY tests are the critical ones for confidence.

- [ ] **Step 5: Commit**

```bash
cd "D:/App de diffusion" && git add supabase/functions/_shared/fcm_dispatcher.ts supabase/functions/_shared/fcm_dispatcher.test.ts && git commit -m "feat(functions): add FcmDispatcher helper (OAuth2 + FCM v1 + LOG_ONLY)"
```

---

## Task 4 : Edge Function `revoke-device`

**Files:**
- Create: `supabase/functions/revoke-device/index.ts`

- [ ] **Step 1: Implement the function**

Create `supabase/functions/revoke-device/index.ts` :

```typescript
import { createClient } from 'jsr:@supabase/supabase-js@^2.46.0';
import { createFcmDispatcher } from '../_shared/fcm_dispatcher.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type, apikey',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);

  const authHeader = req.headers.get('Authorization');
  if (!authHeader) return json({ error: 'Missing auth' }, 401);

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
  if (!callerProfile || callerProfile.role !== 'admin') {
    return json({ error: 'Admin role required' }, 403);
  }

  const { deviceId } = (await req.json()) as { deviceId?: string };
  if (!deviceId) return json({ error: 'deviceId required' }, 400);

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // 1. Capture token BEFORE revoke
  const { data: device, error: devErr } = await admin
    .from('devices')
    .select('id, fcm_token, revoked_at')
    .eq('id', deviceId)
    .single();
  if (devErr || !device) return json({ error: 'Device not found' }, 404);
  const capturedToken = device.fcm_token as string | null;

  // 2. Revoke (also wipes token in same UPDATE)
  const { error: updErr } = await admin
    .from('devices')
    .update({
      revoked_at: new Date().toISOString(),
      fcm_token: null,
    })
    .eq('id', deviceId);
  if (updErr) return json({ error: updErr.message }, 500);

  // 3. Push (best-effort, never block on push failure)
  let pushResult: { ok: boolean; reason?: string } = { ok: false, reason: 'no_token' };
  if (capturedToken) {
    const dispatcher = createFcmDispatcher();
    const result = await dispatcher.send(capturedToken, { type: 'revoked' });
    pushResult = result.ok ? { ok: true } : { ok: false, reason: result.reason };
  }

  return json({ ok: true, push: pushResult }, 200);
});

function json(body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}
```

- [ ] **Step 2: Smoke test via local stack**

Start the stack and serve functions :

```bash
cd "D:/App de diffusion" && supabase functions serve --env-file supabase/.env.local
```

In another terminal, with an admin JWT (récupérable via login dans le backoffice puis copier le JWT depuis Network tab) :

```bash
curl -X POST http://127.0.0.1:54321/functions/v1/revoke-device \
  -H "apikey: $ANON_KEY" \
  -H "Authorization: Bearer <admin_jwt>" \
  -H "Content-Type: application/json" \
  -d '{"deviceId":"7ba88f33-6dc0-4d43-957a-12e7ab9ee4b3"}'
```

Expected : `{"ok":true,"push":{"ok":false,"reason":"log_only"}}` (en LOG_ONLY mode car FIREBASE_SERVICE_ACCOUNT pas configuré). Vérifier les logs : `[FCM LOG_ONLY] Would send to ...: {"type":"revoked"}`.

Si le device n'existait pas → `{"error":"Device not found"}` 404. C'est OK aussi pour valider que la function tourne.

- [ ] **Step 3: Commit**

```bash
cd "D:/App de diffusion" && git add supabase/functions/revoke-device/index.ts && git commit -m "feat(functions): add revoke-device Edge Function with FCM push"
```

---

## Task 5 : Edge Function `assign-playlist`

**Files:**
- Create: `supabase/functions/assign-playlist/index.ts`

- [ ] **Step 1: Implement the function**

Create `supabase/functions/assign-playlist/index.ts` :

```typescript
import { createClient } from 'jsr:@supabase/supabase-js@^2.46.0';
import { createFcmDispatcher } from '../_shared/fcm_dispatcher.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type, apikey',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);

  const authHeader = req.headers.get('Authorization');
  if (!authHeader) return json({ error: 'Missing auth' }, 401);

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
  if (!callerProfile || callerProfile.role !== 'admin') {
    return json({ error: 'Admin role required' }, 403);
  }

  const { deviceId, playlistId } = (await req.json()) as {
    deviceId?: string;
    playlistId?: string | null;
  };
  if (!deviceId) return json({ error: 'deviceId required' }, 400);

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // 1. Apply assignment change
  if (playlistId) {
    const { error: upErr } = await admin
      .from('device_playlists')
      .upsert(
        { device_id: deviceId, playlist_id: playlistId },
        { onConflict: 'device_id' },
      );
    if (upErr) return json({ error: upErr.message }, 500);
  } else {
    const { error: delErr } = await admin
      .from('device_playlists')
      .delete()
      .eq('device_id', deviceId);
    if (delErr) return json({ error: delErr.message }, 500);
  }

  // 2. Resolve token
  const { data: device } = await admin
    .from('devices')
    .select('fcm_token, revoked_at')
    .eq('id', deviceId)
    .single();

  // 3. Push
  let pushResult: { ok: boolean; reason?: string } = { ok: false, reason: 'no_token' };
  if (device?.fcm_token && !device.revoked_at) {
    const dispatcher = createFcmDispatcher();
    const data: Record<string, string> = {
      type: 'assignment_changed',
      playlist_id: playlistId ?? '',
    };
    const result = await dispatcher.send(device.fcm_token, data);
    pushResult = result.ok ? { ok: true } : { ok: false, reason: result.reason };
    // Wipe stale token
    if (!result.ok && result.reason === 'unregistered') {
      await admin.from('devices').update({ fcm_token: null }).eq('id', deviceId);
    }
  }

  return json({ ok: true, push: pushResult }, 200);
});

function json(body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}
```

- [ ] **Step 2: Smoke test**

```bash
curl -X POST http://127.0.0.1:54321/functions/v1/assign-playlist \
  -H "apikey: $ANON_KEY" \
  -H "Authorization: Bearer <admin_jwt>" \
  -H "Content-Type: application/json" \
  -d '{"deviceId":"7ba88f33-6dc0-4d43-957a-12e7ab9ee4b3","playlistId":"c0a53b32-2fa1-43c7-9e13-52b65310e4f1"}'
```

Expected : `{"ok":true,"push":{"ok":false,"reason":"log_only"}}` ou `no_token`.

Tester aussi avec `"playlistId":null` pour le détachement :

```bash
curl -X POST http://127.0.0.1:54321/functions/v1/assign-playlist \
  -H "apikey: $ANON_KEY" \
  -H "Authorization: Bearer <admin_jwt>" \
  -H "Content-Type: application/json" \
  -d '{"deviceId":"7ba88f33-6dc0-4d43-957a-12e7ab9ee4b3","playlistId":null}'
```

Vérifier en SQL que la ligne `device_playlists` est bien deleted :
```bash
docker exec supabase_db_App_de_diffusion psql -U postgres -d postgres -c \
  "select * from device_playlists where device_id = '7ba88f33-6dc0-4d43-957a-12e7ab9ee4b3';"
```

- [ ] **Step 3: Commit**

```bash
cd "D:/App de diffusion" && git add supabase/functions/assign-playlist/index.ts && git commit -m "feat(functions): add assign-playlist Edge Function with FCM push"
```

---

## Task 6 : Edge Function `publish-playlist` (fan-out)

**Files:**
- Create: `supabase/functions/publish-playlist/index.ts`

- [ ] **Step 1: Implement the function**

Create `supabase/functions/publish-playlist/index.ts` :

```typescript
import { createClient } from 'jsr:@supabase/supabase-js@^2.46.0';
import { createFcmDispatcher } from '../_shared/fcm_dispatcher.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type, apikey',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);

  const authHeader = req.headers.get('Authorization');
  if (!authHeader) return json({ error: 'Missing auth' }, 401);

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
  if (!callerProfile || !['admin', 'manager'].includes(callerProfile.role as string)) {
    return json({ error: 'Admin or manager role required' }, 403);
  }

  const { id } = (await req.json()) as { id?: string };
  if (!id) return json({ error: 'id required' }, 400);

  // 1. Update via the CALLER client so RLS is enforced (manager scope)
  const { data: current, error: fetchErr } = await caller
    .from('playlists')
    .select('version')
    .eq('id', id)
    .single();
  if (fetchErr || !current) return json({ error: 'Playlist not found or not authorized' }, 404);

  const newVersion = (current.version as number) + 1;
  const { data: published, error: updErr } = await caller
    .from('playlists')
    .update({
      version: newVersion,
      published_at: new Date().toISOString(),
    })
    .eq('id', id)
    .select()
    .single();
  if (updErr) return json({ error: updErr.message }, 500);

  // 2. Resolve devices (service role bypass — we need to read across tenants safely)
  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: rows, error: rowsErr } = await admin
    .from('device_playlists')
    .select('device_id, devices!inner(id, fcm_token, revoked_at)')
    .eq('playlist_id', id);
  if (rowsErr) return json({ error: rowsErr.message }, 500);

  type DeviceRow = {
    device_id: string;
    devices: { id: string; fcm_token: string | null; revoked_at: string | null };
  };

  const targets = (rows as DeviceRow[])
    .filter((r) => r.devices.fcm_token && !r.devices.revoked_at)
    .map((r) => ({ token: r.devices.fcm_token!, ownerId: r.devices.id }));

  // 3. Fan-out push
  const dispatcher = createFcmDispatcher();
  const result = await dispatcher.sendMany(targets, {
    type: 'playlist_published',
    playlist_id: id,
    version: String(newVersion),
  });

  // 4. Wipe stale tokens
  if (result.unregisteredOwnerIds.length > 0) {
    await admin
      .from('devices')
      .update({ fcm_token: null })
      .in('id', result.unregisteredOwnerIds);
  }

  return json(
    {
      ok: true,
      playlist: published,
      push: {
        sentCount: result.okCount,
        targetCount: targets.length,
        wipedCount: result.unregisteredOwnerIds.length,
      },
    },
    200,
  );
});

function json(body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}
```

- [ ] **Step 2: Smoke test**

```bash
curl -X POST http://127.0.0.1:54321/functions/v1/publish-playlist \
  -H "apikey: $ANON_KEY" \
  -H "Authorization: Bearer <admin_jwt>" \
  -H "Content-Type: application/json" \
  -d '{"id":"c0a53b32-2fa1-43c7-9e13-52b65310e4f1"}'
```

Expected : `{"ok":true,"playlist":{...},"push":{"sentCount":0,"targetCount":N,"wipedCount":0}}` (sentCount = 0 en LOG_ONLY).

Vérifier en SQL que la version a bien été bumpée :
```bash
docker exec supabase_db_App_de_diffusion psql -U postgres -d postgres -c \
  "select id, version, published_at from playlists where id = 'c0a53b32-2fa1-43c7-9e13-52b65310e4f1';"
```

- [ ] **Step 3: Commit**

```bash
cd "D:/App de diffusion" && git add supabase/functions/publish-playlist/index.ts && git commit -m "feat(functions): add publish-playlist Edge Function with FCM fan-out"
```

---

## Task 7 : `FcmService.kt` + `PendingFcmTokenStorage.kt` (Android natif)

**Files:**
- Create: `apps/player/android/app/src/main/kotlin/com/appdiffusion/player/FcmService.kt`
- Create: `apps/player/android/app/src/main/kotlin/com/appdiffusion/player/FcmEngineHolder.kt`
- Create: `apps/player/android/app/src/main/kotlin/com/appdiffusion/player/PendingFcmTokenStorage.kt`
- Modify: `apps/player/android/app/src/main/kotlin/com/appdiffusion/player/MainActivity.kt`
- Modify: `apps/player/android/app/src/main/AndroidManifest.xml`

- [ ] **Step 1: Create FcmEngineHolder (singleton holder for Flutter engine reference)**

Create `apps/player/android/app/src/main/kotlin/com/appdiffusion/player/FcmEngineHolder.kt` :

```kotlin
package com.appdiffusion.player

import io.flutter.embedding.engine.FlutterEngine

/**
 * Singleton holder that lets background services (FcmService) reach the live
 * Flutter engine when one is attached. Set on MainActivity attach, cleared on detach.
 */
object FcmEngineHolder {
    @Volatile
    var engine: FlutterEngine? = null
}
```

- [ ] **Step 2: Create PendingFcmTokenStorage (SharedPreferences holder for offline-bootstrap tokens)**

Create `apps/player/android/app/src/main/kotlin/com/appdiffusion/player/PendingFcmTokenStorage.kt` :

```kotlin
package com.appdiffusion.player

import android.content.Context

/**
 * Stocke un token FCM reçu par le service natif quand l'engine Flutter n'est
 * pas vivant. Le Dart side le lira au prochain démarrage et le pushera en DB.
 */
object PendingFcmTokenStorage {
    private const val PREFS_NAME = "fcm_pending"
    private const val KEY_TOKEN = "pending_token"

    fun save(context: Context, token: String) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_TOKEN, token)
            .apply()
    }

    fun read(context: Context): String? {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_TOKEN, null)
    }

    fun clear(context: Context) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .remove(KEY_TOKEN)
            .apply()
    }
}
```

- [ ] **Step 3: Create FcmService**

Create `apps/player/android/app/src/main/kotlin/com/appdiffusion/player/FcmService.kt` :

```kotlin
package com.appdiffusion.player

import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import io.flutter.plugin.common.MethodChannel

class FcmService : FirebaseMessagingService() {
    override fun onNewToken(token: String) {
        super.onNewToken(token)
        val engine = FcmEngineHolder.engine
        if (engine != null) {
            MethodChannel(engine.dartExecutor.binaryMessenger, "app.player/fcm")
                .invokeMethod("onTokenRefresh", token)
        } else {
            // Engine not attached → persist for next cold start.
            PendingFcmTokenStorage.save(applicationContext, token)
        }
    }

    override fun onMessageReceived(message: RemoteMessage) {
        super.onMessageReceived(message)
        val engine = FcmEngineHolder.engine ?: return // app not running, sync at next start will catch up
        val data = HashMap<String, String>(message.data)
        MethodChannel(engine.dartExecutor.binaryMessenger, "app.player/fcm")
            .invokeMethod("onMessage", data)
    }
}
```

- [ ] **Step 4: Register FcmService in AndroidManifest.xml**

In `apps/player/android/app/src/main/AndroidManifest.xml`, in the `<application>` block (anywhere — alongside other `<service>` declarations), ADD :

```xml
        <!-- FCM messaging service (Phase 8) -->
        <service
            android:name=".FcmService"
            android:exported="false">
            <intent-filter>
                <action android:name="com.google.firebase.MESSAGING_EVENT" />
            </intent-filter>
        </service>
```

- [ ] **Step 5: Wire FcmEngineHolder set/clear in MainActivity**

Replace `apps/player/android/app/src/main/kotlin/com/appdiffusion/player/MainActivity.kt` with :

```kotlin
package com.appdiffusion.player

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(BatteryOptimPlugin())
        FcmEngineHolder.engine = flutterEngine
    }

    override fun onDestroy() {
        if (FcmEngineHolder.engine === flutterEngine) {
            FcmEngineHolder.engine = null
        }
        super.onDestroy()
    }
}
```

- [ ] **Step 6: Sanity check Dart-side compile (Kotlin won't compile without google-services.json setup, that's expected)**

```bash
cd "D:/App de diffusion/apps/player" && flutter analyze
```

Expected : `No issues found!` (Kotlin code is not analyzed by `flutter analyze`).

- [ ] **Step 7: Commit**

```bash
cd "D:/App de diffusion" && git add apps/player/android/app/src/main/kotlin/com/appdiffusion/player/FcmService.kt apps/player/android/app/src/main/kotlin/com/appdiffusion/player/FcmEngineHolder.kt apps/player/android/app/src/main/kotlin/com/appdiffusion/player/PendingFcmTokenStorage.kt apps/player/android/app/src/main/kotlin/com/appdiffusion/player/MainActivity.kt apps/player/android/app/src/main/AndroidManifest.xml && git commit -m "feat(player): add native FcmService + engine holder + pending token storage"
```

---

## Task 8 : `FcmHandler` Dart + lifecycle providers extension

**Files:**
- Create: `apps/player/lib/services/fcm_handler.dart`
- Modify: `apps/player/lib/features/lifecycle/application/lifecycle_providers.dart`
- Test: `apps/player/test/services/fcm_handler_test.dart`

- [ ] **Step 1: Write failing tests**

Create `apps/player/test/services/fcm_handler_test.dart` :

```dart
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/features/lifecycle/application/lifecycle_providers.dart';
import 'package:player/services/fcm_handler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('onMessage with type=playlist_published bumps forceSyncRequestProvider',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final handler = FcmHandlerImpl(ref: container);
    final before = container.read(forceSyncRequestProvider);
    handler.onMessage({'type': 'playlist_published'});
    final after = container.read(forceSyncRequestProvider);
    expect(after, before + 1);
  });

  test('onMessage with type=assignment_changed bumps forceSyncRequestProvider',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final handler = FcmHandlerImpl(ref: container);
    final before = container.read(forceSyncRequestProvider);
    handler.onMessage({'type': 'assignment_changed', 'playlist_id': ''});
    expect(container.read(forceSyncRequestProvider), before + 1);
  });

  test('onMessage with type=revoked bumps fcmRevokedSignalProvider', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final handler = FcmHandlerImpl(ref: container);
    final before = container.read(fcmRevokedSignalProvider);
    handler.onMessage({'type': 'revoked'});
    expect(container.read(fcmRevokedSignalProvider), before + 1);
  });

  test('onMessage with unknown type is a no-op', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final handler = FcmHandlerImpl(ref: container);
    final beforeSync = container.read(forceSyncRequestProvider);
    final beforeRevoke = container.read(fcmRevokedSignalProvider);
    handler.onMessage({'type': 'unknown_type'});
    expect(container.read(forceSyncRequestProvider), beforeSync);
    expect(container.read(fcmRevokedSignalProvider), beforeRevoke);
  });
}
```

- [ ] **Step 2: Add `fcmRevokedSignalProvider` to lifecycle_providers.dart**

In `apps/player/lib/features/lifecycle/application/lifecycle_providers.dart`, ADD at the end of the file :

```dart
/// Bumped (incrementing counter) by FcmHandler when the device receives a
/// `revoked` push from the backend. PlayerScreen listens and switches to
/// RevokedScreen immediately.
final fcmRevokedSignalProvider = StateProvider<int>((ref) => 0);
```

- [ ] **Step 3: Run tests, verify they fail**

```bash
cd "D:/App de diffusion/apps/player" && flutter test test/services/fcm_handler_test.dart
```

Expected : FAIL with "Target of URI doesn't exist".

- [ ] **Step 4: Implement `FcmHandler`**

Create `apps/player/lib/services/fcm_handler.dart` :

```dart
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:player/data/providers.dart';
import 'package:player/features/lifecycle/application/lifecycle_providers.dart';
import 'package:player/providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract class FcmHandler {
  Future<void> registerToken(String token);
  void onMessage(Map<String, String> data);
}

class FcmHandlerImpl implements FcmHandler {
  FcmHandlerImpl({required this.ref, SupabaseClient? client}) : _client = client;

  final ProviderContainer ref;
  final SupabaseClient? _client;

  static const _channel = MethodChannel('app.player/fcm');

  /// Wires the MethodChannel handler. Call once at app startup.
  void wireChannel() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onTokenRefresh':
          final token = call.arguments as String?;
          if (token != null) await registerToken(token);
          break;
        case 'onMessage':
          final raw = call.arguments;
          if (raw is Map) {
            onMessage(raw.map((k, v) => MapEntry(k.toString(), v.toString())));
          }
          break;
      }
      return null;
    });
  }

  @override
  Future<void> registerToken(String token) async {
    final creds = await ref.read(credentialsProvider.future);
    if (creds == null) {
      // Will be retried on next pairing complete (PairingScreen calls registerToken too).
      return;
    }
    final client = _client ?? Supabase.instance.client;
    try {
      await client.from('devices').update({'fcm_token': token}).eq('id', creds.deviceId);
    } catch (_) {
      // Best-effort. Next refresh will retry. Polling 15min keeps things working anyway.
    }
  }

  @override
  void onMessage(Map<String, String> data) {
    switch (data['type']) {
      case 'playlist_published':
      case 'assignment_changed':
        ref.read(forceSyncRequestProvider.notifier).state++;
        break;
      case 'revoked':
        ref.read(fcmRevokedSignalProvider.notifier).state++;
        break;
      default:
        // Unknown type — no-op
        break;
    }
  }
}

final fcmHandlerProvider = Provider<FcmHandler>((ref) {
  // Note: we pass a ProviderContainer-like ref by capturing the WidgetRef container.
  // This is wired at app bootstrap.
  throw UnimplementedError(
    'fcmHandlerProvider must be overridden at app startup with a real container',
  );
});
```

- [ ] **Step 5: Run tests, verify they pass**

```bash
cd "D:/App de diffusion/apps/player" && flutter test test/services/fcm_handler_test.dart
```

Expected : 4 tests passed.

- [ ] **Step 6: Commit**

```bash
cd "D:/App de diffusion" && git add apps/player/lib/services/fcm_handler.dart apps/player/lib/features/lifecycle/application/lifecycle_providers.dart apps/player/test/services/fcm_handler_test.dart && git commit -m "feat(player): add FcmHandler dispatching push to sync/revoke providers"
```

---

## Task 9 : Wire-up FCM init dans `main.dart` + `app.dart` + listen revoked dans PlayerScreen

**Files:**
- Modify: `apps/player/lib/main.dart`
- Modify: `apps/player/lib/app.dart`
- Modify: `apps/player/lib/features/player/presentation/player_screen.dart`

- [ ] **Step 1: Read current state of all three files**

Use the Read tool on :
- `D:/App de diffusion/apps/player/lib/main.dart`
- `D:/App de diffusion/apps/player/lib/app.dart`
- `D:/App de diffusion/apps/player/lib/features/player/presentation/player_screen.dart`

- [ ] **Step 2: Add FCM bootstrap in main.dart**

In `apps/player/lib/main.dart`, replace the body of `main()` with the version below (preserves existing FlutterForegroundTask init from Phase 9, adds FcmHandler bootstrap) :

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:player/app.dart';
import 'package:player/services/fcm_handler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);

  FlutterForegroundTask.initCommunicationPort();
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'app_diffusion_playback',
      channelName: 'Lecture diffusion',
      channelDescription: "Indique que l'app de diffusion fonctionne en continu.",
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.LOW,
    ),
    iosNotificationOptions: const IOSNotificationOptions(),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.nothing(),
      autoRunOnBoot: true,
      autoRunOnMyPackageReplaced: true,
      allowWakeLock: true,
    ),
  );

  final container = ProviderContainer();
  final fcmHandler = FcmHandlerImpl(ref: container);
  fcmHandler.wireChannel();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: ProviderScope(
        overrides: [
          fcmHandlerProvider.overrideWithValue(fcmHandler),
        ],
        child: const PlayerApp(),
      ),
    ),
  );
}
```

⚠️ Cette structure peut paraître compliquée mais elle évite l'`UnimplementedError` du provider. Si Riverpod 2.x se plaint de la double-scope, simplifier en passant juste `ProviderScope(overrides: [...])` avec `parent: container`. Adapter au besoin selon l'API exacte de la version installée.

- [ ] **Step 3: Sanity check that everything compiles**

```bash
cd "D:/App de diffusion/apps/player" && flutter analyze
```

Si erreur sur `UncontrolledProviderScope` (peut différer d'une version Riverpod à l'autre), bascule sur la forme simple :
```dart
runApp(
  ProviderScope(
    overrides: [
      fcmHandlerProvider.overrideWith((ref) => fcmHandler),
    ],
    child: const PlayerApp(),
  ),
);
```
(et accepte que le `container` interne du `ProviderScope` ne soit pas le même que celui passé au handler — pas grave pour la phase 8, le handler bump le bon `forceSyncRequestProvider` car il est créé dans le même container).

- [ ] **Step 4: Listen `fcmRevokedSignalProvider` dans PlayerScreen**

In `apps/player/lib/features/player/presentation/player_screen.dart`, locate the `build()` method. After the existing `ref.listen<int>(forceSyncRequestProvider, ...)` (added in Phase 9), ADD a sibling listen :

```dart
    ref.listen<int>(fcmRevokedSignalProvider, (prev, next) {
      if (prev != null && next != prev && mounted && !_revoked) {
        setState(() => _revoked = true);
      }
    });
```

Si l'import de `fcmRevokedSignalProvider` n'est pas déjà là (il vient du même `lifecycle_providers.dart`), pas besoin de toucher aux imports.

- [ ] **Step 5: Run tests + analyze**

```bash
cd "D:/App de diffusion/apps/player" && flutter analyze && flutter test 2>&1 | tail -10
```

Expected : analyze clean, all tests still pass (≥ 24 — 20 baseline + 4 new from Task 8).

- [ ] **Step 6: Commit**

```bash
cd "D:/App de diffusion" && git add apps/player/lib/main.dart apps/player/lib/features/player/presentation/player_screen.dart && git commit -m "feat(player): wire FCM bootstrap + listen revoked signal in PlayerScreen"
```

---

## Task 10 : Refacto `PlaylistsRepository.publish()` → invoke Edge Function

**Files:**
- Modify: `apps/backoffice/lib/features/playlists/data/playlists_repository.dart`
- Test: `apps/backoffice/test/features/playlists/playlists_repository_publish_test.dart`

- [ ] **Step 1: Write failing test**

Create `apps/backoffice/test/features/playlists/playlists_repository_publish_test.dart` :

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:backoffice/features/playlists/data/playlists_repository.dart';

class _MockClient extends Mock implements SupabaseClient {}
class _MockFunctions extends Mock implements FunctionsClient {}
class _FakeFunctionResponse extends Fake implements FunctionResponse {
  _FakeFunctionResponse(this._data, this._status);
  final dynamic _data;
  final int _status;
  @override int get status => _status;
  @override dynamic get data => _data;
}

void main() {
  setUpAll(() {
    registerFallbackValue(const FunctionInvokeOptions());
  });

  test('publish() invokes publish-playlist Edge Function with id in body',
      () async {
    final client = _MockClient();
    final fns = _MockFunctions();
    when(() => client.functions).thenReturn(fns);
    when(() => fns.invoke(
          any(),
          body: any(named: 'body'),
          method: any(named: 'method'),
          headers: any(named: 'headers'),
          queryParameters: any(named: 'queryParameters'),
        )).thenAnswer((_) async => _FakeFunctionResponse(
          {
            'ok': true,
            'playlist': {
              'id': 'p1',
              'establishment_id': 'e1',
              'name': 'Demo',
              'audio_enabled': false,
              'version': 5,
              'published_at': '2026-04-25T18:00:00.000Z',
              'created_at': '2026-04-25T17:00:00.000Z',
            },
            'push': {'sentCount': 1, 'targetCount': 1, 'wipedCount': 0},
          },
          200,
        ));

    final repo = PlaylistsRepository(client);
    final result = await repo.publish('p1');

    expect(result.id, 'p1');
    expect(result.version, 5);
    final captured = verify(() => fns.invoke(
          captureAny(),
          body: captureAny(named: 'body'),
          method: any(named: 'method'),
          headers: any(named: 'headers'),
          queryParameters: any(named: 'queryParameters'),
        )).captured;
    expect(captured[0], 'publish-playlist');
    expect(captured[1], {'id': 'p1'});
  });
}
```

- [ ] **Step 2: Run test, verify it fails**

```bash
cd "D:/App de diffusion/apps/backoffice" && flutter test test/features/playlists/playlists_repository_publish_test.dart
```

Expected : FAIL — current `publish()` does direct UPDATE, not invoke.

- [ ] **Step 3: Refacto `publish()` to invoke**

In `apps/backoffice/lib/features/playlists/data/playlists_repository.dart`, replace the `publish()` method (lines ~75-87) with :

```dart
  Future<Playlist> publish(String id) async {
    try {
      final response = await _client.functions.invoke(
        'publish-playlist',
        body: {'id': id},
      );
      if (response.status != 200) {
        throw AppException(
          'Publication échouée',
          cause: 'Edge function returned status ${response.status}',
        );
      }
      final data = response.data as Map<String, dynamic>;
      if (data['ok'] != true) {
        throw AppException(
          'Publication échouée',
          cause: data['error']?.toString() ?? 'unknown',
        );
      }
      return Playlist.fromJson(
        Map<String, dynamic>.from(data['playlist'] as Map),
      );
    } on AppException {
      rethrow;
    } catch (e) {
      throw AppException('Publication échouée', cause: e.toString());
    }
  }
```

- [ ] **Step 4: Run test, verify it passes**

```bash
cd "D:/App de diffusion/apps/backoffice" && flutter test test/features/playlists/playlists_repository_publish_test.dart
```

Expected : 1 test passed.

- [ ] **Step 5: Commit**

```bash
cd "D:/App de diffusion" && git add apps/backoffice/lib/features/playlists/data/playlists_repository.dart apps/backoffice/test/features/playlists/playlists_repository_publish_test.dart && git commit -m "refactor(backoffice): publish() now invokes publish-playlist Edge Function"
```

---

## Task 11 : Refacto `DevicePlaylistsRepository.assign/unassign` + `DevicesRepository.revoke` → invoke

**Files:**
- Modify: `apps/backoffice/lib/features/playlists/data/device_playlists_repository.dart`
- Modify: `apps/backoffice/lib/features/devices/data/devices_repository.dart`
- Test: `apps/backoffice/test/features/playlists/device_playlists_repository_test.dart`
- Test: `apps/backoffice/test/features/devices/devices_repository_revoke_test.dart`

- [ ] **Step 1: Write failing tests for assign/unassign**

Create `apps/backoffice/test/features/playlists/device_playlists_repository_test.dart` :

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:backoffice/features/playlists/data/device_playlists_repository.dart';

class _MockClient extends Mock implements SupabaseClient {}
class _MockFunctions extends Mock implements FunctionsClient {}
class _FakeFunctionResponse extends Fake implements FunctionResponse {
  _FakeFunctionResponse(this._data, this._status);
  final dynamic _data;
  final int _status;
  @override int get status => _status;
  @override dynamic get data => _data;
}

void main() {
  setUpAll(() {
    registerFallbackValue(const FunctionInvokeOptions());
  });

  test('assign() invokes assign-playlist with deviceId + playlistId', () async {
    final client = _MockClient();
    final fns = _MockFunctions();
    when(() => client.functions).thenReturn(fns);
    when(() => fns.invoke(any(),
            body: any(named: 'body'),
            method: any(named: 'method'),
            headers: any(named: 'headers'),
            queryParameters: any(named: 'queryParameters')))
        .thenAnswer((_) async => _FakeFunctionResponse({'ok': true}, 200));

    await DevicePlaylistsRepository(client).assign(deviceId: 'd1', playlistId: 'p1');

    final captured = verify(() => fns.invoke(captureAny(),
            body: captureAny(named: 'body'),
            method: any(named: 'method'),
            headers: any(named: 'headers'),
            queryParameters: any(named: 'queryParameters')))
        .captured;
    expect(captured[0], 'assign-playlist');
    expect(captured[1], {'deviceId': 'd1', 'playlistId': 'p1'});
  });

  test('unassign() invokes assign-playlist with playlistId: null', () async {
    final client = _MockClient();
    final fns = _MockFunctions();
    when(() => client.functions).thenReturn(fns);
    when(() => fns.invoke(any(),
            body: any(named: 'body'),
            method: any(named: 'method'),
            headers: any(named: 'headers'),
            queryParameters: any(named: 'queryParameters')))
        .thenAnswer((_) async => _FakeFunctionResponse({'ok': true}, 200));

    await DevicePlaylistsRepository(client).unassign('d1');

    final captured = verify(() => fns.invoke(captureAny(),
            body: captureAny(named: 'body'),
            method: any(named: 'method'),
            headers: any(named: 'headers'),
            queryParameters: any(named: 'queryParameters')))
        .captured;
    expect(captured[0], 'assign-playlist');
    expect(captured[1], {'deviceId': 'd1', 'playlistId': null});
  });
}
```

- [ ] **Step 2: Refacto assign/unassign**

In `apps/backoffice/lib/features/playlists/data/device_playlists_repository.dart`, replace the `assign()` and `unassign()` methods with :

```dart
  Future<void> assign({
    required String deviceId,
    required String playlistId,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'assign-playlist',
        body: {'deviceId': deviceId, 'playlistId': playlistId},
      );
      if (response.status != 200) {
        throw AppException(
          'Assignation échouée',
          cause: 'Edge function returned status ${response.status}',
        );
      }
    } on AppException {
      rethrow;
    } catch (e) {
      throw AppException('Assignation échouée', cause: e.toString());
    }
  }

  Future<void> unassign(String deviceId) async {
    try {
      final response = await _client.functions.invoke(
        'assign-playlist',
        body: {'deviceId': deviceId, 'playlistId': null},
      );
      if (response.status != 200) {
        throw AppException(
          'Détachement échoué',
          cause: 'Edge function returned status ${response.status}',
        );
      }
    } on AppException {
      rethrow;
    } catch (e) {
      throw AppException('Détachement échoué', cause: e.toString());
    }
  }
```

Tu peux retirer l'import `package:supabase_flutter/supabase_flutter.dart` si plus utilisé après le refacto, ou le garder s'il sert encore pour `playlistForDevice()`.

- [ ] **Step 3: Run assign/unassign test**

```bash
cd "D:/App de diffusion/apps/backoffice" && flutter test test/features/playlists/device_playlists_repository_test.dart
```

Expected : 2 tests passed.

- [ ] **Step 4: Write failing test for revoke**

Create `apps/backoffice/test/features/devices/devices_repository_revoke_test.dart` :

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:backoffice/features/devices/data/devices_repository.dart';

class _MockClient extends Mock implements SupabaseClient {}
class _MockFunctions extends Mock implements FunctionsClient {}
class _FakeFunctionResponse extends Fake implements FunctionResponse {
  _FakeFunctionResponse(this._data, this._status);
  final dynamic _data;
  final int _status;
  @override int get status => _status;
  @override dynamic get data => _data;
}

void main() {
  setUpAll(() {
    registerFallbackValue(const FunctionInvokeOptions());
  });

  test('revoke() invokes revoke-device Edge Function with deviceId in body',
      () async {
    final client = _MockClient();
    final fns = _MockFunctions();
    when(() => client.functions).thenReturn(fns);
    when(() => fns.invoke(any(),
            body: any(named: 'body'),
            method: any(named: 'method'),
            headers: any(named: 'headers'),
            queryParameters: any(named: 'queryParameters')))
        .thenAnswer((_) async => _FakeFunctionResponse({'ok': true}, 200));

    await DevicesRepository(client).revoke('d1');

    final captured = verify(() => fns.invoke(captureAny(),
            body: captureAny(named: 'body'),
            method: any(named: 'method'),
            headers: any(named: 'headers'),
            queryParameters: any(named: 'queryParameters')))
        .captured;
    expect(captured[0], 'revoke-device');
    expect(captured[1], {'deviceId': 'd1'});
  });
}
```

- [ ] **Step 5: Refacto revoke**

In `apps/backoffice/lib/features/devices/data/devices_repository.dart`, replace the `revoke()` method with :

```dart
  Future<void> revoke(String id) async {
    try {
      final response = await _client.functions.invoke(
        'revoke-device',
        body: {'deviceId': id},
      );
      if (response.status != 200) {
        throw AppException(
          'Révocation échouée',
          cause: 'Edge function returned status ${response.status}',
        );
      }
    } on AppException {
      rethrow;
    } catch (e) {
      throw AppException('Révocation échouée', cause: e.toString());
    }
  }
```

- [ ] **Step 6: Run revoke test + full backoffice suite**

```bash
cd "D:/App de diffusion/apps/backoffice" && flutter test 2>&1 | tail -10
```

Expected : tous les tests passent, ≥ 7 (4 baseline + 1 publish + 2 assign/unassign + 1 revoke = 8 attendus). Si un ancien test casse à cause du refacto (anciens tests mockaient les calls table), il faut probablement les supprimer ou les adapter — signaler dans le rapport.

- [ ] **Step 7: Commit**

```bash
cd "D:/App de diffusion" && git add apps/backoffice/lib/features/playlists/data/device_playlists_repository.dart apps/backoffice/lib/features/devices/data/devices_repository.dart apps/backoffice/test/features/playlists/device_playlists_repository_test.dart apps/backoffice/test/features/devices/devices_repository_revoke_test.dart && git commit -m "refactor(backoffice): assign/unassign/revoke now invoke Edge Functions"
```

---

## Task 12 : Documentation déploiement + démo manuelle

**Files:**
- Modify: `CLAUDE.md`
- Create: `docs/phase8-demo.md`

- [ ] **Step 1: Update CLAUDE.md**

Read `CLAUDE.md`. In the section `## Gotchas Windows (résolus mais à savoir)`, add a new numbered point at the end (likely #10) :

```markdown
10. **Firebase setup obligatoire pour FCM (Phase 8)** : poser `apps/player/android/app/google-services.json` (téléchargé depuis console.firebase.google.com) avant tout build Android post-Phase 8. Sans ça, le build Gradle échoue avec "File google-services.json is missing". Voir `docs/firebase-setup.md` pour la procédure complète. Sans `FIREBASE_SERVICE_ACCOUNT` dans `supabase/.env.local`, les Edge Functions tournent en mode `LOG_ONLY` (loggue les push qu'elles auraient envoyés mais n'envoie rien) — le polling 15min reste effectif comme safety net.
```

In the section `## Dette explicitement reportée (post-MVP / Phase 8+)`, REMOVE the line :
```
- FCM push instantané (actuellement polling 15 min)
```

- [ ] **Step 2: Create demo doc**

Create `docs/phase8-demo.md` :

```markdown
# Phase 8 — Démo FCM push instantané

Pré-requis :
- APK Phase 8 installée sur tablette
- Firebase project configuré avec `google-services.json` en place et
  `FIREBASE_SERVICE_ACCOUNT` dans `supabase/.env.local` (cf. `docs/firebase-setup.md`)
- Player paired, playlist assignée

## 1. Vérifier l'enregistrement du token

Au démarrage du Player (max 30s après pairing) :

```bash
docker exec supabase_db_App_de_diffusion psql -U postgres -d postgres -c \
  "select id, name, fcm_token is not null as has_token, length(fcm_token) as token_len from public.devices;"
```

✅ `has_token = t` et `token_len > 100` pour le device de test.

## 2. Publier une playlist → reprise instantanée

- Backoffice : naviguer dans la playlist assignée.
- Modifier l'ordre des items ou ajouter un nouveau média.
- Cliquer **Publier**.
- ✅ Le snackbar affiche "Publié — push envoyé à 1 device(s)".
- ✅ La tablette synchronise et affiche le nouveau contenu en **< 5 secondes** (chronométrer).

Vérifier les logs Edge Functions :
```bash
supabase functions logs publish-playlist --tail
```
On doit voir le push envoyé (ou `[FCM LOG_ONLY]` si en mode dégradé).

## 3. Assigner une autre playlist → bascule instantanée

- Backoffice : depuis le détail device, choisir une autre playlist.
- ✅ Tablette bascule sur la nouvelle playlist en **< 5 secondes**.

## 4. Détacher la playlist → écran Standby

- Backoffice : "Détacher la playlist".
- ✅ Tablette affiche `StandbyScreen` "EN ATTENTE DE CONTENU" en **< 5 secondes**.

## 5. Révoquer le device → RevokedScreen

- Backoffice : depuis le détail device, "Révoquer".
- ✅ Tablette affiche `RevokedScreen` en **< 5 secondes** (sans attendre le prochain heartbeat).
- ✅ En SQL, `devices.fcm_token IS NULL` après révocation.

## 6. Mode dégradé (FCM down)

- Couper le Wifi de la tablette pendant 1 min.
- Publier une playlist depuis le backoffice.
- Réactiver le Wifi.
- ✅ Le polling 15 min finit par sync (au connectivity listener côté Player, sync immédiate au retour réseau).

## 7. Mode LOG_ONLY (sans Firebase)

Si tu veux tester en local sans Firebase :
- Ne mets pas `FIREBASE_SERVICE_ACCOUNT` dans `supabase/.env.local`.
- Tous les flows ci-dessus marchent, mais **les push réels ne partent pas** : seul le polling 15 min propage. Les actions admin réussissent quand même (pas de blocage).
- Vérifier les logs : `[FCM LOG_ONLY] Would send to ...`
```

- [ ] **Step 3: Commit**

```bash
cd "D:/App de diffusion" && git add CLAUDE.md docs/phase8-demo.md && git commit -m "docs(phase8): add Firebase gotcha + manual demo script"
```

---

## Validation finale Phase 8

- [ ] **Step 1: Run all test suites**

```bash
cd "D:/App de diffusion/apps/player" && flutter test 2>&1 | tail -5
cd "D:/App de diffusion/apps/backoffice" && flutter test 2>&1 | tail -5
cd "D:/App de diffusion/packages/shared" && flutter test 2>&1 | tail -5
cd "D:/App de diffusion" && deno test --allow-env --allow-net --allow-read supabase/functions/_shared/fcm_dispatcher.test.ts 2>&1 | tail -5
```

Expected : 100% passing across all suites. ≥ 8 nouveaux tests Phase 8 (4 fcm_handler + 1 publish + 2 assign/unassign + 1 revoke + ≥ 2 fcm_dispatcher = 10).

- [ ] **Step 2: Vérifier le log**

```bash
cd "D:/App de diffusion" && git log --oneline -15
```

Expected : ≥ 12 commits Phase 8 dans l'ordre des tasks.

- [ ] **Step 3: Build APK et test sur tablette physique**

À faire après que le user ait posé `google-services.json` réel :
```powershell
cd "D:\App de diffusion\apps\player"
flutter run -d R8YW80ANCYL --release `
  --dart-define=SUPABASE_URL=http://192.168.1.72:54321 `
  --dart-define=SUPABASE_ANON_KEY=eyJhbGc...
```

Suivre `docs/phase8-demo.md` étapes 1 à 7.

---

## Critères d'acceptation Phase 8 (rappel du spec)

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
