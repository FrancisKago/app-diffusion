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

  const { deviceId, playlistId } = (await req.json()) as {
    deviceId?: string;
    playlistId?: string | null;
  };
  if (!deviceId) return json({ error: 'deviceId required' }, 400);

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

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

  const { data: device } = await admin
    .from('devices')
    .select('fcm_token, revoked_at')
    .eq('id', deviceId)
    .single();

  let pushResult: { ok: boolean; reason?: string } = { ok: false, reason: 'no_token' };
  if (device?.fcm_token && !device.revoked_at) {
    const dispatcher = createFcmDispatcher();
    const data: Record<string, string> = {
      type: 'assignment_changed',
      playlist_id: playlistId ?? '',
    };
    const result = await dispatcher.send(device.fcm_token, data);
    pushResult = result.ok ? { ok: true } : { ok: false, reason: result.reason };
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
