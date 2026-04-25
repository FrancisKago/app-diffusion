# Démo Phase 7 — MVP complet

## Prérequis
- Phases 1-6 fonctionnelles
- Back office Flutter Web rebuilt avec Phase 7 (audit, rôle-gated, indicateur live)
- Player Android rebuilt avec Phase 7 (RevokedScreen)
- Supabase + functions serve actifs

## Scénario admin

1. **Login admin** (`admin@local.test` / `AdminPass123!`)
   - Menu de gauche : 6 entrées (Établissements, Appareils, Médias, Playlists, **Gérants**, **Audit**)
   - Petit label "admin" au-dessus du bouton logout

2. **Audit log**
   - Cliquer sur **Audit** (icône horloge)
   - Voir les événements récents : `Profil créé`, `Appareil appairé`, `Playlist publiée`, `Appareil révoqué` (selon ce qui s'est passé)
   - Filtres : type d'événement + période (24h/7j/30j)
   - Indicateur "● live" + auto-refresh 30s

3. **Révoquer un appareil**
   - Aller dans **Appareils** → menu ⋯ sur la tablette → **"Révoquer"** → confirmer
   - Un nouvel événement `Appareil révoqué` apparaît dans Audit (déclenché par le trigger DB)
   - Côté tablette, au prochain heartbeat (≤ 5 min) → bascule vers écran rouge **"APPAREIL RÉVOQUÉ"** avec bouton "Ré-appairer cet appareil"

4. **Ré-appairage propre**
   - Sur la tablette, cliquer "Ré-appairer cet appareil" → secure storage cleared → retour PairingScreen avec un nouveau code
   - Côté admin, dans **Appareils**, le device existe toujours mais la pastille est grise et `revoked_at` est non-null
   - Pour permettre le ré-appairage : `update devices set revoked_at = null where id = ?` (via Studio) OU créer un nouveau device row, puis utiliser le nouveau code de la tablette

5. **Logout admin**

## Scénario gérant

1. **Login gérant** (`manager@local.test` / `ManagerPass123!`)
   - Menu de gauche : seulement 4 entrées (Établissements, Appareils, Médias, Playlists)
   - Pas de **Gérants**, pas de **Audit**
   - Label "gérant" au-dessus de logout

2. **Visibilité limitée par RLS**
   - Le gérant ne voit QUE "Lounge Plateau" dans Établissements (RLS via `establishment_managers`)
   - Pas de FAB "Nouvel établissement" (gating UI)
   - Pas de FAB "Nouvel appareil"
   - Devices : pas de "Supprimer" dans le menu carte
   - Le manager voit uniquement les médias, playlists et devices de Lounge Plateau

3. **Action métier autorisée : éditer une playlist**
   - **Playlists** → cliquer sur la playlist existante → éditeur drag-drop
   - Modifier la durée d'un item, ajouter/retirer un média, changer l'ordre
   - **Publier** → événement `playlist_published` apparaît dans l'audit (côté admin)
   - Le device sync la nouvelle version au prochain polling

4. **Tentative non autorisée**
   - Saisir manuellement `/managers` dans l'URL → la page se charge mais la liste est vide (RLS bloque côté DB)
   - Saisir `/audit` → idem, RLS bloque (admin-only SELECT)
   - Edge Function `create-manager` rejette si l'utilisateur n'est pas admin (vérification interne)

## Résultat attendu — MVP fonctionnel

- ✅ Séparation admin/gérant nette (UI + RLS + Edge Functions)
- ✅ Audit trail traçable de toutes les actions sensibles
- ✅ Tablette sait gérer son cycle de vie : appairage → lecture → révocation → ré-appairage
- ✅ Documentation production complète (README)

**34 pgTAP RLS tests · 25 shared tests · 4 backoffice tests · 6 player tests · 6 phases démontrées**

Le MVP couvre le cas d'usage : un restaurant/lounge avec un parc de tablettes, gérées par un admin et un ou plusieurs gérants, lit en boucle des playlists publiées avec campagnes datées, en restant fonctionnel offline.

## Limites résiduelles (post-MVP)

- **Pas de FCM** (push instantané) — polling 15 min suffit pour signage
- **Pas de foreground service Android** — la tablette doit rester en mode kiosque (1 app au premier plan)
- **Pas de bouton supprimer pour managers/médias/établissements** dans l'UI (admin doit passer par SQL ou RLS direct)
- **Pas d'export CSV des playback_logs** — preuve de diffusion exportable serait un Phase 8
- **Pas de chart sparkline** des heartbeats — uniquement liste
- **Hardcoded thresholds** (10 min pastille verte, 15 min polling, 5 min heartbeat) — non configurables
- **Audit log paginé à 100** — pas de pagination ni recherche full-text
- **Pas de signing keys rotation** — JWT_SECRET fixe dans le déploiement
