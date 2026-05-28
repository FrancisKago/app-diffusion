import { createClient } from 'jsr:@supabase/supabase-js@^2.46.0';

type Payload = {
  managerId: string;
};

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type, apikey',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
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
  const { data: callerProfile, error: profileErr } = await caller
    .from('profiles')
    .select('role')
    .eq('id', callerUser.user.id)
    .single();
  if (profileErr || !callerProfile || callerProfile.role !== 'admin') {
    return json({ error: 'Admin role required' }, 403);
  }

  const payload = (await req.json()) as Payload;
  if (!payload.managerId) {
    return json({ error: 'managerId required' }, 400);
  }

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // Load target profile to (a) ensure it is a manager — never an admin — and
  // (b) capture metadata for the audit trail before the row cascades away.
  const { data: target, error: targetErr } = await admin
    .from('profiles')
    .select('id, role, full_name, establishment_managers(establishment_id)')
    .eq('id', payload.managerId)
    .single();
  if (targetErr || !target) return json({ error: 'Manager not found' }, 404);
  if (target.role !== 'manager') {
    return json({ error: 'Only managers can be deleted' }, 403);
  }
  const establishmentCount =
    (target.establishment_managers as unknown[] | null)?.length ?? 0;

  // Record the audit event up front with the *caller* admin as actor. The
  // cascade delete below runs under the service role (auth.uid() = null), so a
  // DB trigger could not attribute the action correctly — we do it explicitly.
  const { error: auditErr } = await admin.from('audit_events').insert({
    actor_id: callerUser.user.id,
    actor_type: 'admin',
    event_type: 'user_deleted',
    target_id: target.id,
    metadata: {
      role: target.role,
      full_name: target.full_name,
      establishment_count: establishmentCount,
    },
  });
  if (auditErr) return json({ error: auditErr.message }, 500);

  // Deleting the auth user cascades to public.profiles (FK on delete cascade)
  // and onward to public.establishment_managers.
  const { error: delErr } = await admin.auth.admin.deleteUser(target.id);
  if (delErr) return json({ error: delErr.message }, 500);

  return json({ ok: true }, 200);
});

function json(body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}
