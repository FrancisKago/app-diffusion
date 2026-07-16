import { createClient } from 'jsr:@supabase/supabase-js@^2.46.0';

// Deletes storage objects in the `media` bucket that have no corresponding
// row in public.media (e.g. files left behind when an establishment was
// deleted and cascaded away its media rows, or an upload that failed after
// the binary landed but before the metadata insert). Admin-only.
//
// `dryRun: true` (default) only reports what would be deleted.

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type, x-supabase-api-version',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const BUCKET = 'media';

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

  const body = (await req.json().catch(() => ({}))) as { dryRun?: boolean };
  const dryRun = body.dryRun ?? true;

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // Known file paths (source of truth).
  const { data: mediaRows, error: mediaErr } = await admin
    .from('media')
    .select('file_path');
  if (mediaErr) return json({ error: mediaErr.message }, 500);
  const known = new Set<string>(
    (mediaRows ?? []).map((r) => r.file_path as string),
  );

  // Walk the bucket: top level is one folder per establishment, files inside.
  const orphans: string[] = [];
  const { data: folders, error: listErr } = await admin.storage
    .from(BUCKET)
    .list('', { limit: 10000 });
  if (listErr) return json({ error: listErr.message }, 500);

  for (const folder of folders ?? []) {
    // Entries without an id are folders (prefixes); files have an id.
    if (folder.id !== null && folder.id !== undefined) {
      if (!known.has(folder.name)) orphans.push(folder.name);
      continue;
    }
    const prefix = folder.name;
    const { data: files, error: subErr } = await admin.storage
      .from(BUCKET)
      .list(prefix, { limit: 10000 });
    if (subErr) return json({ error: subErr.message }, 500);
    for (const f of files ?? []) {
      if (f.id === null || f.id === undefined) continue; // nested folder, skip
      const path = `${prefix}/${f.name}`;
      if (!known.has(path)) orphans.push(path);
    }
  }

  let deleted = 0;
  if (!dryRun && orphans.length > 0) {
    // remove() caps at ~1000 paths per call; chunk to be safe.
    for (let i = 0; i < orphans.length; i += 500) {
      const chunk = orphans.slice(i, i + 500);
      const { error: rmErr } = await admin.storage.from(BUCKET).remove(chunk);
      if (rmErr) return json({ error: rmErr.message, deleted }, 500);
      deleted += chunk.length;
    }
  }

  return json({
    ok: true,
    dryRun,
    orphanCount: orphans.length,
    deleted,
    orphans: orphans.slice(0, 100),
  }, 200);
});

function json(body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}
