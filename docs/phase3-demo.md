# Démo Phase 3

## Prérequis
- Phase 1 + Phase 2 setup complets
- Supabase local + `supabase functions serve --env-file supabase/.env.local` actifs
- Back office Flutter Web servi (en build release sur 0.0.0.0 si tablette physique)
- Avoir au moins 1 fichier vidéo MP4 (≤ 100 Mo) et 3 images (JPG/PNG/WebP, ≤ 10 Mo chacune)

## Scénario

1. **Login admin**
   - http://127.0.0.1:4552 → `admin@local.test` / `AdminPass123!`

2. **Naviguer vers Médias**
   - Menu de gauche → "Médias" (icône 📷)
   - Vue : grille vide "Aucun média."

3. **Upload d'une image**
   - Bouton "Uploader un média" (FAB en bas à droite)
   - Sélectionner "Lounge Plateau" comme établissement
   - "Choisir un fichier" → choisir une image JPG ≤ 10 Mo
   - Vérifier que la taille s'affiche correctement (ex: "2.34 Mo")
   - Cliquer "Uploader" → barre de progression
   - Dialog se ferme → vignette apparaît dans la grille

4. **Upload d'une vidéo**
   - Re-cliquer "Uploader un média"
   - Choisir un MP4 ≤ 100 Mo
   - Uploader → vignette avec icône play apparaît, badge "vidéo" visible

5. **Upload de 2 images supplémentaires** (PNG + WebP) pour avoir 4 médias au total

6. **Validation des erreurs**
   - Tenter d'uploader un fichier > 10 Mo (image) → message d'erreur "Fichier trop gros (max 10 Mo)"
   - Tenter un format non supporté (ex: .gif) → file_picker filtre les extensions, sinon message d'erreur

7. **Prévisualisation**
   - Cliquer sur la vignette d'une image → dialog plein écran avec InteractiveViewer (zoom)
   - Cliquer sur la vignette d'une vidéo → lecture automatique, contrôles play/pause + barre de progression
   - Fermer (icône X)

8. **Test isolation gérant (via Studio)**
   - Se déconnecter et se connecter avec un compte gérant qui n'est PAS rattaché à Lounge Plateau
   - Naviguer vers Médias → la liste est vide (RLS bloque)
   - Confirme que les policies RLS séparent bien par établissement

## Résultat attendu
- 4 médias uploadés visibles dans la grille (1 vidéo + 3 images)
- Vignettes d'images chargées via signed URLs (1h)
- Lecture vidéo fluide
- Validation client (taille/format) bloque les fichiers invalides
- Validation serveur (DB CHECK + bucket file_size_limit + Storage RLS) en deuxième ligne de défense
- Isolation par établissement effective
- Tests automatiques : `flutter test` (23 total : 17 shared + 4 backoffice + 2 player) et `supabase test db` (15 pgTAP) tous au vert

## Limites connues (Phase 3)
- **Métadonnées vidéo** (durée, dimensions) non extraites côté client — TODO Phase 3.5 si besoin (via `video_player` ou Edge Function `ffprobe`)
- **Pas de déduplication via SHA-256** — la colonne est stockée mais l'UI n'avertit pas si un média identique existe déjà
- **Pas de reprise d'upload** — un upload de 100 Mo échoue intégralement si la connexion coupe (acceptable en phase MVP)
- **CORS Supabase Storage** — si la lecture vidéo via signed URL échoue côté navigateur, la config CORS du bucket peut nécessiter un ajustement (non testé sous device physique en Phase 3)
