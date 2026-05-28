import { createClient } from 'jsr:@supabase/supabase-js@^2.46.0';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-supabase-api-version',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function generateCode(): string {
  const bytes = new Uint8Array(4);
  crypto.getRandomValues(bytes);
  const num = new DataView(bytes.buffer).getUint32(0) % 1_000_000;
  return num.toString().padStart(6, '0');
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (req.method !== 'POST') {
    return json({ error: 'Method not allowed' }, 405);
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // Purge expired sessions in-band
  await admin
    .from('pairing_sessions')
    .update({ status: 'expired' })
    .lt('expires_at', new Date().toISOString())
    .eq('status', 'pending');

  // Generate a unique code (retry up to 5x in unlikely collision)
  let code = '';
  let sessionId = '';
  for (let attempt = 0; attempt < 5; attempt++) {
    code = generateCode();
    const expiresAt = new Date(Date.now() + 15 * 60 * 1000).toISOString();
    const { data, error } = await admin
      .from('pairing_sessions')
      .insert({ code, expires_at: expiresAt })
      .select('id')
      .single();
    if (!error && data) {
      sessionId = data.id;
      break;
    }
    if (attempt === 4) {
      return json({ error: 'Could not allocate pairing code' }, 500);
    }
  }

  return json({ session_id: sessionId, code, ttl_seconds: 900 }, 200);
});

function json(body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}
