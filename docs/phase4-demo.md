# Démo Phase 4

## Prérequis
- Phases 1-3 fonctionnelles
- Supabase local + `supabase functions serve --env-file supabase/.env.local` actifs
- Back office Flutter Web en build release servi (port 4552)
- Au moins 5 médias dans la bibliothèque (voir démo Phase 3)
- Au moins 1 appareil créé dans "Appareils" (voir démo Phase 2)

## Scénario

1. **Login admin**
   - http://127.0.0.1:4552 → `admin@local.test` / `AdminPass123!`

2. **Créer une playlist**
   - Menu "Playlists" (nouvelle entrée dans la barre de gauche, icône 🎵)
   - Bouton "Nouvelle playlist" → nom `Ambiance Lounge`, établissement `Lounge Plateau` → Créer
   - La playlist apparaît dans la liste, badge "v0 · jamais publiée"

3. **Ajouter des médias**
   - Cliquer sur la playlist pour ouvrir l'éditeur
   - Bouton "Ajouter un média" → sélectionner une image → apparaît en haut de la liste (position 0)
   - Répéter 4 fois (pour avoir 5 items : mix images + vidéo)
   - Chaque item affiche : handle drag, nom du fichier, position, durée (pour images)

4. **Réordonner par drag-drop**
   - Glisser un item avec l'icône ≡ pour changer son ordre
   - L'ordre est persisté instantanément (RPC `reorder_playlist_items` atomique via contrainte deferrable)
   - Recharger la page → l'ordre est conservé

5. **Configurer une campagne datée**
   - Cliquer "✏️" sur un item → dialog d'édition
   - Définir "Début" et "Fin" (ex: promo du 1er mai au 7 mai)
   - Enregistrer → le sous-titre de l'item affiche maintenant `2026-05-01 → 2026-05-07`

6. **Modifier la durée d'une image**
   - Pour un item image, changer "Durée d'affichage" de 10s à 15s → Enregistrer
   - Sous-titre mis à jour

7. **Publier la playlist**
   - Bouton "Publier" en haut à droite
   - `version` passe de 0 à 1, badge "publiée à l'instant" apparaît
   - (Cette action incrémente `playlists.version` ; Phase 5 utilisera ça pour déclencher la sync FCM)

8. **Assigner la playlist à un appareil**
   - Menu "Appareils" → cliquer l'icône 🎵 sur la ligne de "Tablette Samsung"
   - Dialog "Playlist pour Tablette Samsung" → sélectionner "Ambiance Lounge" → Assigner
   - La table `device_playlists` reflète l'assignation (vérifiable dans Studio)

9. **Test isolation manager (Studio SQL)**
   - En tant qu'un gérant NON rattaché à Lounge Plateau : `select count(*) from public.playlists` → 0 (RLS bloque)
   - En tant qu'un gérant rattaché : `select count(*) from public.playlists` → 1 (la playlist créée)

## Résultat attendu
- Playlist de 5 items avec ordre personnalisé et au moins 1 campagne datée
- Publication incrémente `version` et met à jour `published_at`
- Assignation 1:1 device→playlist (upsert, PK simple sur device_id)
- Isolation RLS par établissement pour playlists, items, device_playlists
- Tests automatiques : `flutter test` (23 shared + 4 backoffice + 2 player = 29 total) et `supabase test db` (21 pgTAP : 6+5+4+6) tous au vert

## Limites connues (Phase 4)
- **Pas de badge "modifications non publiées"** — l'UI ne montre pas visuellement que des items ont été ajoutés/modifiés depuis la dernière `published_at`. Deferred Phase 4.5 si besoin.
- **Publication en 2 round-trips** (fetch + update) plutôt qu'une RPC atomique — acceptable car un seul admin édite une playlist à la fois.
- **Pas de prévisualisation de playlist** — on ne peut pas "jouer" une playlist dans le back office comme le ferait le player. Viendra Phase 5 avec la sync vers Android.
- **Drag-drop optimiste** — si le RPC de réordonnancement échoue, l'UI montre l'ordre local désynchronisé du serveur jusqu'à un refresh manuel. Erreur affichée néanmoins.
- **Pas de duplication empêchée** — un même média peut apparaître 2 fois dans une playlist (pas de UNIQUE sur `media_id` intentionnellement).
