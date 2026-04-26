import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  create as createJwt,
  verify as verifyJwt,
  getNumericDate,
} from 'https://deno.land/x/djwt@v3.0.1/mod.ts';

async function importSecret(secret: string): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign', 'verify'],
  );
}

Deno.test('JWT signed with secret A is rejected when verified with secret B', async () => {
  const secretA = 'old-secret-with-at-least-32-characters-AAAAA';
  const secretB = 'new-secret-with-at-least-32-characters-BBBBB';
  const keyA = await importSecret(secretA);
  const keyB = await importSecret(secretB);

  const token = await createJwt(
    { alg: 'HS256', typ: 'JWT' },
    {
      sub: 'device-id-1',
      role: 'authenticated',
      aud: 'authenticated',
      iat: getNumericDate(0),
      exp: getNumericDate(60 * 60),
      establishment_id: 'est-1',
      is_device: true,
    },
    keyA,
  );

  // Verifying with the SAME key works
  const payloadSame = await verifyJwt(token, keyA);
  assertEquals(payloadSame.sub, 'device-id-1');

  // Verifying with a DIFFERENT key throws
  let threw = false;
  try {
    await verifyJwt(token, keyB);
  } catch (_) {
    threw = true;
  }
  assertEquals(threw, true, 'Expected verifyJwt to throw with different secret');
});
