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
  if (!callerProfile || !['admin', 'manager'].includes(callerProfile.role as string)) {
    return json({ error: 'Admin or manager role required' }, 403);
  }

  const { id } = (await req.json()) as { id?: string };
  if (!id) return json({ error: 'id required' }, 400);

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

  const dispatcher = createFcmDispatcher();
  const result = await dispatcher.sendMany(targets, {
    type: 'playlist_published',
    playlist_id: id,
    version: String(newVersion),
  });

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
