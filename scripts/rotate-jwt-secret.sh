#!/usr/bin/env bash
# Generates a new JWT_SECRET and prints the steps to rotate it.
# This is INFORMATIONAL — it does NOT modify any file or DB by itself.
# Apply the printed steps manually to keep rotation auditable and intentional.
#
# Usage : ./scripts/rotate-jwt-secret.sh

set -euo pipefail

# Generate a 48-byte secret, base64-encoded → ~64 chars (well above Supabase's 32 minimum)
NEW_SECRET="$(openssl rand -base64 48 | tr -d '\n')"

cat <<EOF
═══════════════════════════════════════════════════════════════════
  ROTATION JWT_SECRET — App de Diffusion
═══════════════════════════════════════════════════════════════════

Nouveau secret généré :
  ${NEW_SECRET}

⚠️  ATTENTION : après rotation, TOUS les devices appairés deviennent
   invalides (leurs JWT ne se valident plus côté Postgres). Ils
   afficheront un écran d'erreur ou tomberont en revoked au prochain
   heartbeat. Tous les devices doivent être ré-appairés.

Procédure de rotation (à exécuter dans l'ordre) :

────── DEV LOCAL ──────────────────────────────────────────────────

1. Sauvegarder l'ancien secret au cas où :
     cp supabase/.env.local supabase/.env.local.bak.\$(date +%s)

2. Mettre à jour supabase/.env.local :
     JWT_SECRET=${NEW_SECRET}

3. Mettre à jour supabase/config.toml si JWT_SECRET y apparaît
   en dur (sinon Supabase le lit depuis l'env directement).

4. Restart la stack pour que Postgres recharge auth.jwt_secret :
     supabase stop && supabase start

5. Wipe les devices.fcm_token et marquer revoked pour forcer re-pair :
     docker exec supabase_db_App_de_diffusion psql -U postgres -d postgres -c "
       update public.devices
          set revoked_at = now(),
              fcm_token = null
        where revoked_at is null;
       insert into public.audit_events (
         actor_id, actor_type, event_type, metadata
       ) values (
         null, 'system', 'jwt_secret_rotated',
         jsonb_build_object('rotated_at', now())
       );
     "

6. Re-lancer supabase functions serve avec le nouveau .env.local :
     supabase functions serve --env-file supabase/.env.local

7. Re-pairer chaque device physiquement.

────── PROD (Supabase Cloud) ──────────────────────────────────────

1. Dashboard Supabase → Project Settings → JWT Settings → Regenerate
   ⚠️  copier la nouvelle valeur immédiatement, elle ne sera plus affichée

2. Edge Functions secrets : mettre à jour
     supabase secrets set JWT_SECRET="<nouvelle_valeur>"

3. Redéployer les Edge Functions :
     supabase functions deploy --no-verify-jwt

4. Sur la DB de prod, exécuter :
     update public.devices
        set revoked_at = now(),
            fcm_token = null
      where revoked_at is null;
     insert into public.audit_events (
       actor_id, actor_type, event_type, metadata
     ) values (
       null, 'system', 'jwt_secret_rotated',
       jsonb_build_object('rotated_at', now(), 'environment', 'prod')
     );

5. Notifier l'équipe de re-pairer tous les devices terrain.

═══════════════════════════════════════════════════════════════════
EOF
