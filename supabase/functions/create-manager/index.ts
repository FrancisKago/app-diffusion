import { createClient } from 'jsr:@supabase/supabase-js@^2.46.0';

type Payload = {
  email: string;
  password: string;
  full_name: string;
  establishment_ids: string[];
};

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  const authHeader = req.headers.get('Authorization');
  if (!authHeader) {
    return json({ error: 'Missing auth' }, 401);
  }
  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

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
  if (!payload.email || !payload.password || !payload.full_name) {
    return json({ error: 'email, password, full_name required' }, 400);
  }
  if (payload.password.length < 8) {
    return json({ error: 'Password must be at least 8 characters' }, 400);
  }

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: created, error: createErr } = await admin.auth.admin.createUser(
    {
      email: payload.email,
      password: payload.password,
      email_confirm: true,
      user_metadata: { full_name: payload.full_name },
    },
  );
  if (createErr) return json({ error: createErr.message }, 400);

  const userId = created.user.id;

  const rollback = async (reason: string, status: number) => {
    await admin.auth.admin.deleteUser(userId);
    return json({ error: reason }, status);
  };

  const { error: updateErr } = await admin
    .from('profiles')
    .update({ full_name: payload.full_name, role: 'manager' })
    .eq('id', userId);
  if (updateErr) return rollback(updateErr.message, 500);

  if (payload.establishment_ids.length > 0) {
    const rows = payload.establishment_ids.map((eid) => ({
      establishment_id: eid,
      profile_id: userId,
    }));
    const { error: linkErr } = await admin
      .from('establishment_managers')
      .insert(rows);
    if (linkErr) return rollback(linkErr.message, 500);
  }

  return json({ id: userId }, 200);
});

function json(body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}
