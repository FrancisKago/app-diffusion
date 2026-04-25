# Firebase setup pour Phase 8 (FCM)

À faire une fois, manuellement, avant la démo Phase 8.

## 1. Créer le project Firebase

1. Aller sur https://console.firebase.google.com
2. **Add project** → nom : `App-de-Diffusion-Prod` (ou ce que tu veux)
3. Désactiver Google Analytics (pas utile pour notre cas)

## 2. Ajouter l'app Android

1. Dans le project Firebase → icône Android → **Add app**
2. **Android package name** : `com.appdiffusion.player` (impératif — doit matcher
   `applicationId` dans `apps/player/android/app/build.gradle.kts`)
3. App nickname : `Player Android`
4. Skip SHA-1 (pas requis pour FCM)
5. **Download `google-services.json`** → poser dans `apps/player/android/app/`

⚠️ Ce fichier est dans `.gitignore`, ne le commit JAMAIS.

## 3. Récupérer le service account JSON pour les Edge Functions

1. Project Settings (⚙️) → **Service accounts**
2. **Generate new private key** → confirme → JSON téléchargé
3. Renomme en `firebase-serviceaccount.json` (mais ne le pose nulle part dans le repo)

## 4. Configurer le secret Supabase

```bash
cd "D:/App de diffusion"

# Pour Supabase local (dev) :
echo 'FIREBASE_SERVICE_ACCOUNT=<contenu_json_minifié_sur_une_ligne>' >> supabase/.env.local

# Pour Supabase Cloud (prod) :
supabase secrets set FIREBASE_SERVICE_ACCOUNT="$(cat ~/Downloads/firebase-serviceaccount.json)"
```

Pour minifier le JSON sur une ligne :
```bash
cat firebase-serviceaccount.json | jq -c .
```

## 5. Vérifier

Au prochain démarrage du Player après pairing, vérifier que `devices.fcm_token`
est non-NULL :

```sql
docker exec supabase_db_App_de_diffusion psql -U postgres -d postgres -c \
  "select id, name, fcm_token is not null as has_token from public.devices;"
```

Si `has_token = true` partout → FCM marche côté Player.

## Mode LOG_ONLY (sans Firebase)

Si `FIREBASE_SERVICE_ACCOUNT` n'est pas défini (cas dev local sans avoir fait
les étapes ci-dessus), les Edge Functions logguent les push qu'elles auraient
envoyés sans rien envoyer. Le polling 15min reste actif → tout marche, juste
sans le bonus de réactivité instantanée.
