# Sécurisation multi-tenant et fiabilité du player

**Date :** 14 juillet 2026
**Statut :** design validé
**Lot :** A — prérequis aux lots reporting/supervision et médias avancés

## Contexte

App de Diffusion est actuellement déployée sur Supabase Cloud. Les appareils
Android utilisent un JWT device custom, signé en HS256 et contenant notamment
`sub`, `is_device` et `establishment_id`. Le player accède principalement à
PostgREST et aux RPC avec ce JWT, tandis que le back-office utilise une session
Supabase humaine.

L'audit du 14 juillet 2026 a identifié quatre défauts prioritaires :

1. la policy `devices_self_update_heartbeat` autorise un device à mettre à jour
   toutes les colonnes de sa propre ligne ;
2. l'enregistrement FCM utilise `Supabase.instance.client` sans initialisation ni
   session SDK dans le player ;
3. une désaffectation ou un changement de playlist peut laisser une playlist
   locale obsolète active ;
4. la base ne garantit pas que les relations device–playlist et
   playlist–média restent dans le même établissement.

Le correctif doit préserver les JWT et appairages existants, ne pas interrompre
la lecture des appareils déployés et être validé localement avant toute écriture
sur Supabase Cloud.

## Objectifs

- Retirer toute mutation directe et trop large de `public.devices` par un JWT
  device.
- Enregistrer le token FCM par une RPC dédiée et limitée à cette seule donnée.
- Interdire sans exception les relations métier entre établissements différents,
  y compris lorsqu'elles sont demandées par un administrateur global.
- Faire passer un player désaffecté sur l'écran d'attente dès la synchronisation.
- Garantir qu'une seule playlist locale est active après un changement
  d'affectation.
- Conserver le polling et la lecture offline pendant le déploiement.
- Couvrir les nouveaux invariants par des tests pgTAP, Dart et Deno.

## Non-objectifs

- Modifier le format ou la durée de validité des JWT device.
- Réappairer, réinstaller ou effacer les données des appareils existants.
- Remplacer le polling de quinze minutes par une dépendance exclusive à FCM.
- Purger immédiatement les fichiers médias lors d'une désaffectation.
- Ajouter les fonctionnalités de reporting ou de traitement média des lots B et
  C dans cette livraison.

## Architecture retenue

### Frontière de mutation des devices

La policy `devices_self_update_heartbeat` sera supprimée. Le player ne disposera
plus d'un chemin PostgREST permettant un `UPDATE` arbitraire de sa ligne dans
`devices`.

Les heartbeats continueront à passer par `record_heartbeat`. Une nouvelle RPC
`register_device_fcm_token(p_token text)` sera l'unique chemin utilisé par un
device pour enregistrer ou renouveler son token FCM.

La RPC :

- dérive le device depuis `auth.uid()` et n'accepte aucun `device_id` fourni par
  le client ;
- exige le claim `is_device=true` ;
- vérifie que le device existe et que `revoked_at` est nul ;
- refuse un token vide ou supérieur à 4 096 caractères ;
- ne modifie que `fcm_token` et `updated_at` ;
- est déclarée `SECURITY DEFINER`, avec un propriétaire contrôlé et un
  `search_path` explicite, car la policy UPDATE device sera supprimée ;
- retire l'EXECUTE à `PUBLIC` et ne l'accorde qu'au rôle `authenticated`.

Une erreur d'enregistrement FCM reste non bloquante : la lecture et le polling
continuent à fonctionner.

### Cohérence multi-tenant

La base devient l'autorité finale pour les deux invariants suivants :

- `device_playlists.device_id` et `device_playlists.playlist_id` doivent pointer
  vers le même `establishment_id` ;
- `playlist_items.playlist_id` et `playlist_items.media_id` doivent pointer vers
  le même `establishment_id`.

Des fonctions de validation et triggers `BEFORE INSERT OR UPDATE` rejetteront une
relation incohérente avec un message stable et un SQLSTATE exploitable. Les
fonctions utiliseront un `search_path` explicite. Leur droit d'exécution sera
retiré à `PUBLIC`, `anon` et `authenticated` afin qu'elles ne deviennent pas des
API publiques supplémentaires.

L'Edge Function `assign-playlist` effectuera aussi une prévalidation. Elle lira
les établissements du device et de la playlist avec le client service role,
renverra `404` lorsqu'une ressource n'existe pas et `409` lorsque les
établissements diffèrent. Le trigger restera la protection finale contre les
écritures concurrentes, directes ou futures.

### Client FCM du player

Le player n'initialisera pas une session `supabase_flutter` pour son JWT custom.
Le handler FCM dépendra d'une petite interface injectable utilisant le client HTTP
device existant et l'endpoint :

```text
POST /rest/v1/rpc/register_device_fcm_token
apikey: <clé publique>
Authorization: Bearer <JWT device>
Content-Type: application/json

{"p_token":"<token FCM>"}
```

L'enregistrement sera tenté :

- au démarrage lorsque des credentials device existent ;
- immédiatement après un appairage réussi ;
- lors d'un renouvellement de token transmis par Android ;
- au retour de la connectivité.

Les erreurs seront journalisées sans inclure le JWT, la clé Supabase ou le token
FCM complet. Aucun de ces échecs ne mettra la lecture en pause.

### État local de la playlist

Le résultat de synchronisation distinguera explicitement :

- `assigned`, avec la version et les compteurs actuels ;
- `unassigned`, sans playlist active.

Drift exposera deux opérations transactionnelles :

1. remplacer l'unique playlist active et ses items par la nouvelle affectation ;
2. supprimer toutes les playlists et tous les items actifs lors d'une
   désaffectation.

Le provider de lecture ne choisira plus arbitrairement `all.first`. Après
`unassigned`, il observera un cache logique vide et affichera l'écran d'attente.

Les métadonnées et fichiers médias ne seront pas supprimés immédiatement. Ils ne
feront plus partie de l'ensemble protégé de la playlist courante et deviendront
éligibles à la purge LRU. Cette stratégie permet une réaffectation rapide sans
téléchargement inutile, tout en récupérant progressivement l'espace disque.

## Flux et codes d'erreur

### Enregistrement FCM

1. Android transmet le token à Dart par MethodChannel.
2. Dart charge les credentials device depuis le stockage sécurisé.
3. Le client HTTP appelle la RPC avec le JWT device.
4. PostgreSQL authentifie le JWT, vérifie le device et met à jour le token.
5. Un échec déclenche un log assaini et sera retenté à un prochain événement.

### Affectation de playlist

1. Le back-office appelle `assign-playlist` avec sa session humaine.
2. La fonction vérifie l'utilisateur et son rôle admin.
3. Elle charge le device et la playlist demandés.
4. Elle refuse une ressource absente ou une relation inter-établissements.
5. Elle effectue l'upsert ; le trigger DB revérifie l'invariant.
6. Elle envoie le push FCM en best effort.

### Codes HTTP

- `400` : corps ou token FCM invalide ;
- `401` : JWT absent ou invalide ;
- `403` : appelant non-device, device révoqué ou rôle humain insuffisant ;
- `404` : device, playlist ou média inexistant ;
- `409` : tentative de liaison entre établissements différents ;
- `500` : erreur interne non classifiée, sans détail sensible renvoyé au client.

## Compatibilité et ordre de déploiement

La migration ne change ni le format des JWT ni les identifiants des devices. Les
anciennes versions du player gardent leur cache, leur lecture offline, leurs
heartbeats RPC et leur polling. Elles peuvent seulement ne plus réussir à
renouveler directement `fcm_token` jusqu'à la mise à jour de l'APK ; ce cas est
déjà couvert fonctionnellement par le polling.

L'ordre prévu est :

1. installer ou rendre disponible le CLI Supabase et démarrer Docker ;
2. créer la migration via le CLI du projet ;
3. appliquer les migrations sur la base locale et exécuter pgTAP ;
4. exécuter les tests Deno et Flutter ;
5. construire et tester l'APK signé avec la nouvelle RPC ;
6. présenter le diff SQL, les résultats et les commandes Cloud ;
7. attendre une autorisation explicite avant toute écriture distante ;
8. pousser la migration et déployer `assign-playlist` ;
9. effectuer un smoke test Cloud avec un device de validation dédié ;
10. distribuer l'APK aux appareils existants.

Une défaillance de l'Edge Function ou de l'APK peut être corrigée par un nouveau
déploiement sans retirer les contraintes de sécurité. Aucun rollback ne doit
restaurer la permission UPDATE large sur `devices` sauf décision d'urgence
explicite et temporaire.

## Stratégie de tests

### pgTAP

- Un JWT device peut lire sa propre ligne mais ne peut modifier directement ni
  `name`, ni `establishment_id`, ni `revoked_at`, ni `fcm_token`.
- `register_device_fcm_token` met à jour uniquement le device dérivé de
  `auth.uid()`.
- La RPC refuse un appel humain, un token invalide et un device révoqué.
- Une affectation device–playlist du même établissement réussit.
- Une affectation device–playlist inter-établissements échoue.
- Un item playlist–média du même établissement réussit.
- Un item playlist–média inter-établissements échoue, y compris pour un admin.

### Dart et Flutter

- Le handler FCM appelle l'interface HTTP injectable avec le token attendu.
- Le handler n'accède plus à `Supabase.instance`.
- Un échec réseau FCM ne bloque pas le player.
- Une désaffectation vide le cache logique et produit `unassigned`.
- Un changement A vers B supprime A et ne laisse que B active.
- Les fichiers médias d'une ancienne playlist restent présents mais deviennent
  éligibles à la purge LRU.
- Les tests existants de lecture, appairage, foreground service et cache restent
  passants.

### Deno

- `assign-playlist` renvoie `404` pour une ressource absente.
- `assign-playlist` renvoie `409` pour une relation inter-établissements.
- Une affectation valide conserve l'envoi FCM best effort.

### Vérification Cloud

Après autorisation de déploiement, un device de validation dédié devra prouver :

- l'enregistrement du token FCM par RPC ;
- une affectation valide et une synchronisation réussie ;
- une désaffectation suivie de l'écran d'attente ;
- le maintien des appairages et de la lecture sur les appareils existants.

## Critères d'acceptation

- Aucun JWT device ne peut modifier directement une colonne de `devices`.
- La RPC FCM est le seul chemin device pour mettre à jour `fcm_token`.
- Les relations inter-établissements sont impossibles au niveau DB.
- Une désaffectation observée en ligne conduit le player à l'écran d'attente.
- Une seule playlist locale peut être active.
- Les appareils existants ne sont ni réappairés ni réinstallés.
- Toutes les suites pgTAP, Deno et Flutter passent localement.
- Aucune commande de déploiement Cloud n'est exécutée sans validation explicite
  après présentation des résultats locaux.
