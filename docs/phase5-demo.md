# Démo Phase 5

## Prérequis
- Phases 1-4 fonctionnelles
- Supabase local + `supabase functions serve --env-file supabase/.env.local` actifs
- Back office Flutter Web rebuild après Phase 5 (statique sur `:4552`)
- Player Android rebuilt (PowerShell admin) avec les nouvelles deps :
  ```
  cd "D:\App de diffusion\apps\player"
  flutter run -d <DEVICE_ID> --release `
    --dart-define=SUPABASE_URL=http://192.168.1.X:54321 `
    --dart-define=SUPABASE_ANON_KEY=<ANON>
  ```
  (X = IP LAN du PC)
- Au moins 1 playlist publiée + assignée à 1 device (Phase 4) avec ≥3 médias variés (image + vidéo)

## Scénario

1. **Lancer le Player**
   - L'app démarre, voit qu'elle a un JWT en Keystore
   - Affiche brièvement « Synchronisation initiale… » (loader noir)
   - Le sync télécharge les médias dans le cache local SQLite + fichiers
   - Heartbeat envoyé en boucle (5 min) avec progression

2. **Vérifier dans le back office**
   - Aller dans "Appareils"
   - La pastille verte apparaît à gauche du device (last_seen_at < 10 min)
   - Sous-titre montre `sync 50%` puis `sync 100%` puis disparaît (à 100% le `syncProgress` reste à 100 mais on l'affiche seulement si < 100 — ajuster si besoin)
   - Quand 100% atteint, la lecture en boucle commence sur le Player

3. **Lecture en boucle**
   - Tablette joue les médias dans l'ordre `position` de la playlist
   - Images : durée `display_duration_sec` (ex: 10s)
   - Vidéos : jouent jusqu'à la fin
   - Au dernier item, retour au premier (boucle infinie)

4. **Filtrage par dates**
   - Dans le back office, ajouter `starts_at` ou `ends_at` à un item de la playlist (ex: `ends_at` dans le passé)
   - Publier la playlist (version++)
   - Attendre <15 min OU redémarrer l'app Player → sync détecte la nouvelle version
   - L'item filtré n'apparaît plus dans la boucle

5. **Coupure réseau**
   - Couper le wifi sur la tablette
   - La lecture continue depuis le cache local
   - Le heartbeat échoue silencieusement (best effort) ; aucune erreur visible côté tablette
   - Côté back office, après ~10 min, la pastille du device passe au gris

6. **Retour réseau**
   - Réactiver le wifi
   - `connectivity_plus` détecte l'événement → un sync se déclenche immédiatement
   - Si la playlist a été modifiée pendant la coupure, les nouveautés sont téléchargées
   - Pastille redevient verte au premier heartbeat (≤5 min)

7. **Cache LRU**
   - Si le cache total dépasse 2 Go, les médias non utilisés depuis le plus longtemps sont purgés (et leurs lignes dans `cached_media` supprimées)
   - À la prochaine sync, ils seront re-téléchargés s'ils sont toujours dans la playlist

## Résultat attendu
- Synchronisation initiale terminée en 1-3 min selon la taille des médias
- Lecture en boucle fluide, transitions image→vidéo→image
- Filtrage par dates appliqué dynamiquement après chaque sync
- Persistance offline complète (24h+ sans réseau possibles)
- Tests : 6 player + 4 backoffice + 24 shared = 34 Dart, 21 pgTAP

## Limites connues (Phase 5)
- **Latence sync max 15 min** — pas de FCM (différé Phase 5.5). Pour tests rapides, redémarrer l'app force un sync immédiat.
- **Pas de foreground service** — si l'utilisateur sort de l'app via le bouton home, Android peut tuer le process. Tablette kiosque doit rester au premier plan. Ajout du foreground service prévu Phase 5.5.
- **Pas de resume de download** — un téléchargement interrompu par perte réseau redémarre du début à la sync suivante. Acceptable pour des médias <100 Mo sur wifi décent.
- **Heartbeat fréquence fixe à 5 min** — non configurable, pas de jitter. Si nécessaire, tunable via une constante en Phase 6.
- **`syncProgress` reste à 100** après une sync complète — l'UI le masque quand il vaut 100, mais la base ne le réinitialise pas à 0 entre cycles. Comportement OK pour la démo, à clarifier en Phase 6 (preuves de diffusion).
