# Démo Phase 6

## Prérequis
- Phases 1-5 fonctionnelles ; tablette physique appairée et synchronisée
- Supabase local + `supabase functions serve --env-file supabase/.env.local` actifs
- Back office Flutter Web rebuild après Phase 6 (port 4552)
- Player Android rebuild côté PowerShell admin (drift schema v2 → migration auto au lancement)

## Scénario

1. **Lancer le Player Phase 6 sur la tablette**
   - Au lancement, la migration drift v1→v2 ajoute la table `pending_playback_logs` localement
   - Sync standard puis lecture en boucle
   - À chaque item terminé : log enqueué localement
   - Toutes les 5 min (heartbeat) : flush de la queue via `record_playback` RPC + `record_heartbeat`

2. **Dashboard cards (back office)**
   - Aller dans **Appareils** → vue **cards** (ne plus une simple liste)
   - Chaque carte affiche : pastille statut large, nom, établissement, "il y a X min", sync%, ▶ média en cours
   - Petit indicateur "● live" dans l'AppBar = auto-refresh 30s actif
   - Au bout de 30s sans toucher la page, la pastille `last_seen_at` se met à jour automatiquement

3. **Détail device**
   - Cliquer sur une carte (ou menu ⋯ → "Voir détails") → écran `/devices/:id`
   - Section **Statut actuel** : pastille, last_seen, sync%, média joué, version playlist
   - Section **Heartbeats récents** (50 derniers) : timestamp + battery + storage_free_mb + app_version
   - Section **Lectures récentes** (50 derniers playback_logs) : timestamp + nom du média + durée mm:ss
   - Auto-refresh 30s aussi

4. **Test offline + queue de logs**
   - Couper le wifi tablette → la lecture continue
   - Les playback_logs s'accumulent dans `pending_playback_logs` (drift local)
   - Réactiver wifi → au prochain heartbeat (≤5 min), les logs sont flushés en RPC
   - Détail device → la liste "Lectures récentes" affiche maintenant les logs accumulés (avec timestamps de capture, pas de flush)

5. **Révoquer un device**
   - Carte device → menu ⋯ → **"Révoquer"** → confirm → `revoked_at` posé
   - Au prochain heartbeat de la tablette, le RPC `record_heartbeat` lève "Device not found or revoked" (errcode 42501)
   - Le Player ne fait rien de spécial sur erreur — la queue de logs reste en local jusqu'à ré-appairage
   - Pour ré-appairer : clear app data tablette + nouveau pairing-code + claim

6. **Supprimer un device**
   - Carte device → menu ⋯ → **"Supprimer"** → confirm rouge "irréversible" → `delete from devices`
   - Cascades : `device_playlists`, `device_heartbeats`, `playback_logs` supprimés via FK ON DELETE CASCADE
   - La carte disparaît de la liste

## Résultat attendu
- Vue cards live avec auto-refresh visible
- Détail device avec historique heartbeats et lectures
- Queue offline des playback_logs robuste : aucun log perdu après reconnexion
- Révocation fonctionnelle (RPC bloque les heartbeats)
- Suppression définitive avec cascade FK propre
- Tests : 24 shared + 4 backoffice + 6 player = 34 Dart, 26 pgTAP (5 phase 6 + 21 prior)

## Limites connues (Phase 6)
- **Auto-refresh polling 30s** au lieu de Supabase Realtime — simpler à déployer, latence acceptable pour supervision (alertes non critiques). Migration vers Realtime possible Phase 7.
- **Purge probabiliste 1%** des heartbeats déclenchent le DELETE des vieilles données (>7j heartbeats, >30j logs). Pour parc important, pg_cron serait plus propre.
- **Pas de chart sparkline** des heartbeats — uniquement liste. Visualisation possible en Phase 7+.
- **Pas d'export CSV** des playback_logs (preuve de diffusion exportable). À envisager en Phase 7 si besoin business.
- **Bouton "Détacher playlist"** existait déjà dans `AssignPlaylistDialog` mais n'a pas été déplacé dans le menu carte — le dialog reste le point d'entrée.
- **Pas de notification visible côté Player** quand le device est révoqué — l'app ne montre pas d'erreur, le sync échoue silencieusement. À traiter Phase 7 (UI "device révoqué" avec bouton ré-appairer).
