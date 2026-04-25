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
  assertEquals(result.okCount, 0);
  assertEquals(result.unregisteredOwnerIds.length, 0);
  assertEquals(result.errors.length, 2);
});

// TODO: integration test with valid PEM in CI
Deno.test.ignore('parses UNREGISTERED response as wipe-able', async () => {
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
