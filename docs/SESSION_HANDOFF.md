# Session handoff — 25 avr. 2026

État de fin de session, à lire en premier au prochain démarrage.

## Où on en est

**MVP complet — 7 phases sur 7 livrées et code commité.**

| Phase | Status | Démo physique faite |
|---|---|---|
| 1 — Fondations (auth + CRUD) | ✅ | Chrome ✓ |
| 2 — Appairage device | ✅ | Samsung SM X115 ✓ |
| 3 — Médias (upload + bibliothèque) | ✅ | Chrome ✓ |
| 4 — Playlists + publication | ✅ | Chrome ✓ |
| 5 — Sync Android + lecteur | ✅ | Samsung SM X115 ✓ |
| 6 — Supervision live | ✅ | **À faire (combinée avec Phase 7)** |
| 7 — Rôle gérant + audit + MVP | ✅ | **À faire (combinée avec Phase 6)** |

## Dernière action de la session

À la fin de la session précédente, je venais de :
1. Rebuilder le back office Phase 6+7 → servi statiquement sur `http://127.0.0.1:4552`
2. Relancer `supabase functions serve --env-file supabase/.env.local`
3. Donner à l'utilisateur la commande PowerShell admin pour rebuild + lancer le Player Android sur la tablette Samsung SM X115

L'utilisateur n'avait pas encore lancé le Player ni testé les démos Phase 6+7 quand on a fait le handoff.

## Services qui tournaient (à relancer après reboot Claude)

Les processus suivants **étaient lancés dans la session précédente** et seront tués au redémarrage de Claude Code (background tasks détachées du shell). À relancer manuellement dans la nouvelle session :

| Service | Commande | Comment |
|---|---|---|
| Supabase Postgres + Kong | `supabase start` | Persistant (Docker) — devrait toujours tourner |
| Edge Functions | `supabase functions serve --env-file supabase/.env.local` | À relancer |
| Backoffice statique | `cd apps/backoffice/build/web && python -m http.server 4552 --bind 0.0.0.0` | À relancer (build/web déjà à jour) |
| Player Android (tablette) | `flutter run -d R83Y60PXH0P --release ...` (PowerShell admin) | À relancer côté utilisateur |

Vérifier d'abord que Docker tourne : `docker ps`. Si Supabase lui-même est down, `supabase start` d'abord.

## État de la base au handoff

- 18 migrations appliquées (Phases 1-7 complètes)
- 4 Edge Functions servies : `create-manager`, `request-pairing-code`, `pairing-status`, `claim-pairing-code` (avec audit_event Phase 7)
- 34 pgTAP tests passants (phase1-7)
- Seed admin + manager + Lounge Plateau

**Tablette physique au handoff** :
- Device id : `7ba88f33-6dc0-4d43-957a-12e7ab9ee4b3` (nom DB : "Tablette physique")
- Établissement : Lounge Plateau (`11111111-1111-1111-1111-111111111111`)
- Playlist assignée : `c0a53b32-2fa1-43c7-9e13-52b65310e4f1`
- JWT en Keystore Android **valide** (dernier appairage post-fix .env.local)

**ATTENTION** : si `supabase db reset` est exécuté dans la nouvelle session, le device row est wipé → la tablette aura un JWT pour un device_id qui n'existe plus. Pour récupérer SANS clear-data sur la tablette :
```sql
docker exec supabase_db_App_de_diffusion psql -U postgres -d postgres -c "
insert into public.devices (id, establishment_id, name)
values ('7ba88f33-6dc0-4d43-957a-12e7ab9ee4b3',
        '11111111-1111-1111-1111-111111111111',
        'Tablette physique')
on conflict (id) do nothing;"
```
Puis assigner manuellement une playlist + insert dans `device_playlists`.

## À faire immédiatement après reboot

1. Vérifier `docker ps` → Supabase containers up
2. Relancer functions serve (background)
3. Relancer python http.server 4552 (background)
4. Vérifier `curl http://127.0.0.1:4552/` → 200 et `curl -X POST http://127.0.0.1:54321/functions/v1/request-pairing-code -H "apikey: <ANON>"` → 200
5. Demander à l'utilisateur de hard-refresh Chrome
6. Donner les instructions pour relancer le Player sur tablette dans PowerShell admin
7. Procéder à la démo combinée Phase 6 + Phase 7 selon `docs/phase6-demo.md` puis `docs/phase7-demo.md`

## Si l'utilisateur veut continuer vers Phase 8+

**Pas de Phase 8 spécifiée dans le spec original** — le MVP couvre le scope. Si le user veut étendre, candidats naturels :

1. **Phase 8 — FCM push** : ajouter Firebase + push notifications pour zéro-latence sync. Plan déjà esquissé en Phase 5 (différé Phase 5.5).
2. **Phase 9 — Foreground service Android** : robustesse kiosque (survie au kill système).
3. **Phase 10 — Export et reporting** : CSV/PDF des playback_logs (preuve de diffusion exportable).
4. **Phase 11 — Multi-tenant SaaS** : si revente du produit, gestion d'un super-admin transverse + facturation par établissement.
5. **Quick wins UX** : boutons Supprimer manquants, pagination audit, charts heartbeats.

## Plans déjà rédigés (référence)

Tous dans `docs/superpowers/plans/` :
- `2026-04-24-phase1-foundations.md`
- `2026-04-24-phase2-pairing.md`
- `2026-04-25-phase3-media.md`
- `2026-04-25-phase4-playlists.md`
- `2026-04-25-phase5-sync-playback.md`
- `2026-04-25-phase6-supervision.md`
- `2026-04-25-phase7-polish-mvp.md`

Spec design figée : `docs/superpowers/specs/2026-04-24-app-diffusion-design.md`.

## Comment reprendre proprement

À ouverture d'une nouvelle session Claude Code dans ce projet, lis :
1. `CLAUDE.md` (à la racine) — contexte permanent, gotchas, conventions
2. `docs/SESSION_HANDOFF.md` (ce fichier) — état au moment du handoff
3. `git log --oneline -15` — pour voir les derniers commits
4. Demande à l'utilisateur ce qu'il souhaite faire (continuer démo Phase 6+7 ? Phase 8+ ? Maintenance ?)
