# Phase 8 — Démo FCM push instantané

Pré-requis :
- APK Phase 8 installée sur tablette
- Firebase project configuré avec `google-services.json` en place et
  `FIREBASE_SERVICE_ACCOUNT` dans `supabase/.env.local` (cf. `docs/firebase-setup.md`)
- Player paired, playlist assignée

## 1. Vérifier l'enregistrement du token

Au démarrage du Player (max 30s après pairing) :

```bash
docker exec supabase_db_App_de_diffusion psql -U postgres -d postgres -c \
  "select id, name, fcm_token is not null as has_token, length(fcm_token) as token_len from public.devices;"
```

✅ `has_token = t` et `token_len > 100` pour le device de test.

## 2. Publier une playlist → reprise instantanée

- Backoffice : naviguer dans la playlist assignée.
- Modifier l'ordre des items ou ajouter un nouveau média.
- Cliquer **Publier**.
- ✅ Le snackbar affiche "Publié — push envoyé à 1 device(s)".
- ✅ La tablette synchronise et affiche le nouveau contenu en **< 5 secondes** (chronométrer).

Vérifier les logs Edge Functions :
```bash
supabase functions logs publish-playlist --tail
```
On doit voir le push envoyé (ou `[FCM LOG_ONLY]` si en mode dégradé).

## 3. Assigner une autre playlist → bascule instantanée

- Backoffice : depuis le détail device, choisir une autre playlist.
- ✅ Tablette bascule sur la nouvelle playlist en **< 5 secondes**.

## 4. Détacher la playlist → écran Standby

- Backoffice : "Détacher la playlist".
- ✅ Tablette affiche `StandbyScreen` "EN ATTENTE DE CONTENU" en **< 5 secondes**.

## 5. Révoquer le device → RevokedScreen

- Backoffice : depuis le détail device, "Révoquer".
- ✅ Tablette affiche `RevokedScreen` en **< 5 secondes** (sans attendre le prochain heartbeat).
- ✅ En SQL, `devices.fcm_token IS NULL` après révocation.

## 6. Mode dégradé (FCM down)

- Couper le Wifi de la tablette pendant 1 min.
- Publier une playlist depuis le backoffice.
- Réactiver le Wifi.
- ✅ Le polling 15 min finit par sync (au connectivity listener côté Player, sync immédiate au retour réseau).

## 7. Mode LOG_ONLY (sans Firebase)

Si tu veux tester en local sans Firebase :
- Ne mets pas `FIREBASE_SERVICE_ACCOUNT` dans `supabase/.env.local`.
- Tous les flows ci-dessus marchent, mais **les push réels ne partent pas** : seul le polling 15 min propage. Les actions admin réussissent quand même (pas de blocage).
- Vérifier les logs : `[FCM LOG_ONLY] Would send to ...`
