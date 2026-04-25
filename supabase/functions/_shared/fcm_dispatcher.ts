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
  expiresAt: number;
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
    return { okCount, unregisteredOwnerIds, errors };
  }

  private async getAccessToken(): Promise<string> {
    if (!this.serviceAccount) throw new Error('No service account');
    if (this.tokenCache && this.tokenCache.expiresAt > Date.now() + 60_000) {
      return this.tokenCache.token;
    }

    const now = getNumericDate(0);
    const exp = getNumericDate(60 * 60);
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
