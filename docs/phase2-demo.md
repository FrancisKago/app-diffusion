# Démo Phase 2

## Prérequis
- Phase 1 setup complet
- Un émulateur Android démarré (ou une vraie tablette connectée en adb)
- Supabase local + `supabase functions serve --env-file supabase/.env.local` actifs
  (le fichier doit contenir `JWT_SECRET=super-secret-jwt-token-with-at-least-32-characters-long`)
- Back office Flutter Web servi (en build release sur 0.0.0.0 si la tablette est physique)
- **Windows** : `127.0.0.1 localhost` doit être présent (non-commenté) dans `C:\Windows\System32\drivers\etc\hosts` — sans ça, Gradle échoue avec `Unable to establish loopback connection`
- **Tablette physique** : utiliser l'IP LAN du PC (ex: `http://192.168.1.x:54321`) au lieu de `10.0.2.2`. Vérifier la même WiFi et que le firewall Windows autorise les ports 54321 et 4552

## Scénario

1. **Lancer le Player sur émulateur Android**
   ```bash
   cd apps/player
   flutter run --release \
     --dart-define=SUPABASE_URL=http://10.0.2.2:54321 \
     --dart-define=SUPABASE_ANON_KEY=<ANON>
   ```
   (`10.0.2.2` = localhost de la machine hôte vu depuis l'émulateur Android)

2. **Le Player affiche un code 6 chiffres** plein écran, fond noir.

3. **Pré-créer un appareil dans le back office**
   - Aller dans "Appareils" → "Nouvel appareil"
   - Nom : "Écran terrasse", Établissement : "Lounge Plateau", Orientation : paysage
   - Enregistrer

4. **Appairer**
   - Dans "Appareils", bouton 🔗 (lien) en haut à droite → dialog "Appairer un appareil"
   - Saisir le code affiché sur l'émulateur
   - Sélectionner "Écran terrasse"
   - Cliquer "Appairer"

5. **Le Player bascule en mode "APPAREIL ACTIF"** (polling détecte le claim dans les 3s)

6. **Redémarrer l'app Player** → revient directement en mode actif (JWT en Keystore).

## Résultat attendu
- Code affiché sur la tablette
- Rattachement réussi depuis le back office
- Bascule automatique vers l'écran "APPAREIL ACTIF"
- Persistance du JWT → pas besoin de re-appairer après redémarrage
