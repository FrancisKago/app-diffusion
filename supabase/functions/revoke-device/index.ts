import { createClient } from 'jsr:@supabase/supabase-js@^2.46.0';
import { createFcmDispatcher } from '../_shared/fcm_dispatcher.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-supabase-api-version',
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

  const { data: device, error: devErr } = await admin
    .from('devices')
    .select('id, fcm_token, revoked_at')
    .eq('id', deviceId)
    .single();
  if (devErr || !device) return json({ error: 'Device not found' }, 404);
  const capturedToken = device.fcm_token as string | null;

  const { error: updErr } = await admin
    .from('devices')
    .update({
      revoked_at: new Date().toISOString(),
      fcm_token: null,
    })
    .eq('id', deviceId);
  if (updErr) return json({ error: updErr.message }, 500);

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
