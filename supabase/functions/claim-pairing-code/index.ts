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

  const { data: device, error: devErr } = await admin
    .from('devices')
    .select('id, establishment_id, revoked_at')
    .eq('id', payload.device_id)
    .single();
  if (devErr || !device) return json({ error: 'Device not found' }, 404);
  if (device.revoked_at) return json({ error: 'Device revoked' }, 410);

  // Generate device JWT (90 days, HS256 with Supabase JWT secret)
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

  // Audit: device paired (best-effort; never block pairing on audit failure)
  try {
    const { data: deviceMeta } = await admin
      .from('devices')
      .select('name')
      .eq('id', device.id)
      .single();
    await admin.from('audit_events').insert({
      actor_id: callerUser.user.id,
      actor_type: 'admin',
      event_type: 'device_paired',
      target_id: device.id,
      metadata: {
        device_name: deviceMeta?.name ?? null,
        establishment_id: device.establishment_id,
      },
    });
  } catch (e) {
    console.error('audit insert failed', e);
  }

  return json({ ok: true }, 200);
});

function json(body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}
