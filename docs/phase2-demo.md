# Démo Phase 2

## Prérequis
- Phase 1 setup complet
- Un émulateur Android démarré (ou une vraie tablette connectée en adb)
- Supabase local + `supabase functions serve` actifs
- Back office Flutter Web servi

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
