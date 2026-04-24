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
