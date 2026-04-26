# Rotation du JWT_SECRET

## Quand rotater ?

- **Avant la première mise en production** (le secret de dev est public dans
  ce repo, à remplacer obligatoirement avant prod).
- **Après tout incident de sécurité** suspectant qu'un secret a fuité (push
  accidentel sur GitHub, ordi compromis, etc.).
- **Routine** : tous les 12 mois en prod.

## Impact sur les devices

Le projet utilise HS256 avec un secret partagé entre l'Edge Function
`claim-pairing-code` (qui signe les JWT des devices) et Postgres (qui les
valide via `auth.jwt_secret`). PostgREST ne supporte pas la validation
multi-secrets nativement.

⇒ **Toute rotation invalide TOUS les JWT existants**. Les devices appairés
   doivent être ré-appairés manuellement après une rotation.

C'est un compromis assumé pour le scope MVP : la rotation est un événement
rare et planifié, pas une opération continue. Si le besoin de rotation
sans-downtime apparaît, il faudra :
- Soit migrer vers RS256 (clé publique partagée, clé privée tournante)
- Soit ajouter un proxy de validation dual-secret entre Kong et PostgREST

## Procédure

Lancer le script qui génère un nouveau secret et imprime les étapes :

```bash
./scripts/rotate-jwt-secret.sh
```

Suivre les étapes imprimées (dev OU prod selon le contexte). Le script ne
modifie RIEN automatiquement — chaque action est explicite et auditée.

## Audit

Chaque rotation insère un événement `jwt_secret_rotated` dans
`public.audit_events` avec metadata `{rotated_at, environment?}`. Cet
événement est filtrable depuis le journal d'audit du back office.

## Recovery

Si l'ancien secret a été sauvegardé (script copie `supabase/.env.local`
vers `.env.local.bak.<timestamp>`), il est possible de revenir en arrière
avant que les devices soient ré-appairés :

1. Restaurer le fichier .env.local depuis le backup
2. Restart la stack
3. Re-marquer les devices comme non-revoked manuellement en SQL si besoin

Une fois qu'un device a été ré-appairé avec le NOUVEAU secret, le rollback
n'est plus possible pour ce device sans re-pairing.
