# Phase 9 — Foreground service Android & robustesse Player

**Date** : 2026-04-25
**Statut** : design figé, prêt pour planification
**Scope** : niveau A "Robustesse production" (cf. brainstorming session 2026-04-25)

---

## 1. Objectif

Rendre le Player Android **survivable 24/7** sur des tablettes en exploitation
(restaurants, lounge bars). Aujourd'hui c'est une `FlutterActivity` standard,
sans foreground service ni protection contre :

- Doze mode / battery optimization (kill après quelques heures sans interaction)
- OOM-killer Android sous pression mémoire
- Power cuts → tablette redémarre, écran reste sur le launcher

Cible : **0 intervention humaine** entre l'installation initiale et un éventuel
reboot tablette ou coupure réseau.

## 2. Non-objectifs (YAGNI)

- ❌ Lock-task / Screen Pinning programmatique (Phase 9.5 future si demande)
- ❌ Device Owner / Android Enterprise / DPC (autre catégorie produit)
- ❌ iOS (Player Android-only par design)
- ❌ Android < 8 (toutes les tablettes cibles sont API 28+)
- ❌ Notification persistante avec actions interactives custom
- ❌ Téléchargement médias en background isolate (la lecture est visible et
  continue dans l'isolate principal — pas de cas d'usage off-screen)

## 3. Architecture

```
┌───────────────────────────────────────────────────────────┐
│ Android OS                                                │
│  ┌────────────────────┐    BOOT_COMPLETED                 │
│  │ BootReceiver (Kt)  │ ─────────────┐                    │
│  └────────────────────┘              ↓                    │
│                              ┌─────────────────────┐      │
│                              │ PlaybackForeground  │      │
│                              │ Service (plugin)    │      │
│                              │  + notif persistante│      │
│                              │  + WAKE_LOCK        │      │
│                              └──────────┬──────────┘      │
│                                         │                  │
│                                         ↓ launches         │
│                              ┌─────────────────────┐      │
│                              │ MainActivity        │      │
│                              │ (FlutterActivity)   │      │
│                              │  └─ player_screen   │      │
│                              │     ▸ AdminOverlay  │      │
│                              └─────────────────────┘      │
└───────────────────────────────────────────────────────────┘
```

### Composants

1. **`flutter_foreground_task` v8.x** — gère le service Android, la notif
   persistante (type `mediaPlayback`), l'auto-restart au boot et l'isolate de
   fond. Utilisé en mode "service-as-keepalive" : pas de logique métier dans
   l'isolate background, la lecture reste dans l'Activity. Le plugin sert
   uniquement à marquer le process comme "important" pour le système.

2. **`BootReceiver` (Kotlin)** — `BroadcastReceiver` réveillé sur
   `BOOT_COMPLETED`. Démarre le foreground service ET la `MainActivity`
   (sinon l'écran reste sur le launcher au reboot, défaite du kiosque).
   Sur Android 10+, `startActivity` depuis un receiver est restreint :
   workaround via `pendingIntent.send()` depuis le service (le plugin
   `flutter_foreground_task` expose ce hook).

3. **`AdminOverlay` (Dart)** — widget posé sur `player_screen.dart`.
   Affiche une icône warning orange en coin haut-droit lorsque
   `isBatteryOptimExcluded == false`. Tap → ouvre `AdminScreen`.
   Discret (le client lambda ne le remarque pas) mais signalant.

4. **`AdminScreen` (Dart)** — modal full-screen exposant le diagnostic
   et les actions admin :
   - Version app, device id, nom établissement, dernière sync OK
   - État service foreground (running/stopped)
   - État battery optimization (excluded/not)
   - Bouton "Demander exclusion batterie" → ouvre Settings system
   - Bouton "Re-appairer" → clear Keystore + retour `PairingScreen`
   - Bouton "Forcer une sync maintenant" (utile aussi pour la dette
     technique et pour Phase 8)

5. **`BatteryOptimChecker` (Dart + MethodChannel léger)** — vérifie
   `PowerManager.isIgnoringBatteryOptimizations(packageName)` et offre
   `openExclusionSettings()` qui pose
   `Intent.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`.

6. **`FirstRunBatteryDialog` (Dart)** — popup affichée **une seule fois**
   après le premier pairing (flag persisté localement — nouveau
   `LocalSettings` table Drift, à ajouter dans la même migration
   `app_database.dart`) pour inviter l'utilisateur à autoriser
   l'exclusion. S'il refuse, le banner d'`AdminOverlay` reste comme
   rattrapage permanent.

### Permissions ajoutées au manifest

```xml
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
<uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" />
```

Type de service : `mediaPlayback` (justifiable car app de signage = lecture
vidéo en boucle ; conforme aux exigences Play Store si publication un jour).

## 4. Flows de cycle de vie

### Flow 1 — Premier lancement (post-pairing)

```
1. PairingScreen → JWT obtenu → save Keystore
2. main.dart bascule sur PlayerScreen
3. PlayerScreen.initState():
   a. FlutterForegroundTask.startService(...)  ← notif persistante apparaît
   b. BatteryOptimChecker.isExcluded() → false
   c. AdminOverlay icône orange visible
   d. FirstRunBatteryDialog.showOnce(): "Pour garantir la diffusion 24/7,
      merci d'autoriser l'app dans les réglages batterie." [OK / Plus tard]
   e. OK → BatteryOptimChecker.openExclusionSettings()
4. Retour Settings → onResume → invalidate(isBatteryOptimExcludedProvider)
   → si true, AdminOverlay icône disparaît
```

### Flow 2 — Reboot tablette (power cut, 3 h du matin)

```
1. Android boot → BootReceiver.onReceive(BOOT_COMPLETED)
2. BootReceiver:
   a. context.startForegroundService(serviceIntent)  ← service notif up
   b. via pendingIntent → MainActivity lancée plein écran
3. Flutter cold start → AppRoot lit Keystore
   a. JWT présent → goto PlayerScreen → reprend la lecture
   b. JWT absent (jamais appairé) → PairingScreen
```

### Flow 3 — Veille écran

```
- WakelockPlus.enable() en initState de PlayerScreen
- Foreground service tient le process en vie (même si écran éteint, scénario rare)
- Combinaison = écran toujours allumé pendant la diffusion
```

### Flow 4 — Battery optim refusée puis ré-autorisée

```
1. Admin a refusé au flow 1 → AdminOverlay icône orange persistante
2. Gérant tap icône → AdminScreen ouvre
3. Tap "Demander exclusion batterie" → openExclusionSettings()
4. Retour → onResume → check → icône disparaît automatiquement
```

### Flow 5 — Service tué par OS (RAM critique)

```
- ServiceInfo.flag = START_STICKY (défaut du plugin)
- OS relance le service → notif réapparaît
- Service relance l'activity (même mécanisme que flow 2)
- Reprise lecture depuis l'item courant cached localement
```

### Matrice d'états

| Cas | Service | Activity | UI affichée |
|---|---|---|---|
| Normal | Running | Running | PlayerScreen + lecture |
| Battery non excluded | Running | Running | PlayerScreen + AdminOverlay orange |
| Tablette éteinte | Killed | Killed | — |
| Tablette redémarrée | Running (boot) | Running (boot) | PlayerScreen reprise auto |
| `am force-stop` admin | Killed | Killed | Récupéré au prochain boot uniquement |

## 5. Composants Dart — contrats

### Arborescence (nouveaux fichiers)

```
apps/player/lib/features/lifecycle/
  ├─ data/
  │   └─ battery_optim_checker.dart
  ├─ application/
  │   ├─ foreground_service_controller.dart
  │   └─ lifecycle_providers.dart
  └─ presentation/
      ├─ admin_overlay.dart
      ├─ admin_screen.dart
      └─ first_run_battery_dialog.dart

apps/player/android/app/src/main/kotlin/com/appdiffusion/player/
  ├─ MainActivity.kt           ← inchangé
  ├─ BootReceiver.kt           ← BOOT_COMPLETED handler
  └─ BatteryOptimPlugin.kt     ← MethodChannel app.player/battery_optim

packages/shared/lib/src/models/
  └─ admin_diagnostic.dart     ← freezed
```

### Contrats clés

```dart
// data/battery_optim_checker.dart
abstract class BatteryOptimChecker {
  Future<bool> isExcluded();
  Future<void> openExclusionSettings();
}

class _NativeBatteryOptimChecker implements BatteryOptimChecker {
  static const _channel = MethodChannel('app.player/battery_optim');
  @override Future<bool> isExcluded() async =>
    (await _channel.invokeMethod<bool>('isExcluded')) ?? false;
  @override Future<void> openExclusionSettings() =>
    _channel.invokeMethod('openExclusionSettings');
}

// application/foreground_service_controller.dart
class ForegroundServiceController {
  Future<void> start();
  Future<void> stop();
  Stream<bool> get isRunning;
}

// application/lifecycle_providers.dart
final batteryOptimCheckerProvider = Provider<BatteryOptimChecker>(...);
final foregroundServiceProvider = Provider<ForegroundServiceController>(...);
final isBatteryOptimExcludedProvider =
    FutureProvider<bool>((ref) => ref.read(batteryOptimCheckerProvider).isExcluded());
final adminDiagnosticProvider = FutureProvider<AdminDiagnostic>(...);
```

### Modèle partagé

```dart
// packages/shared/lib/src/models/admin_diagnostic.dart
@freezed
class AdminDiagnostic with _$AdminDiagnostic {
  const factory AdminDiagnostic({
    required String appVersion,
    required String deviceId,
    String? establishmentName,
    DateTime? lastSyncOk,
    required bool foregroundServiceRunning,
    required bool batteryOptimExcluded,
  }) = _AdminDiagnostic;
}
```

### Intégration au code existant

**`apps/player/lib/main.dart`** — initialiser le plugin avant `runApp` :
```dart
await FlutterForegroundTask.initCommunicationPort();
FlutterForegroundTask.init(
  androidNotificationOptions: AndroidNotificationOptions(
    channelId: 'app_diffusion_playback',
    channelName: 'Lecture diffusion',
    channelImportance: NotificationChannelImportance.LOW,
    priority: NotificationPriority.LOW,
  ),
  iosNotificationOptions: const IOSNotificationOptions(),
  foregroundTaskOptions:
      ForegroundTaskOptions(eventAction: ForegroundTaskEventAction.nothing()),
);
```

**`PlayerScreen`** — wrap par `WithForegroundTask` + ajouter `AdminOverlay` :
```dart
return WithForegroundTask(
  child: Stack(children: [
    existingPlayerContent,
    const AdminOverlay(), // top-right, conditionnel
  ]),
);
```

Démarrage du service : `PlayerScreen.initState` (lazy — pas dans `main.dart`
car on n'en veut pas avant pairing).

## 6. Tests

### Unit (Dart)
- `BatteryOptimChecker` : mock `MethodChannel`, vérifier que `isExcluded()`
  parse `true` / `false` / `null`.
- `ForegroundServiceController` : mock `FlutterForegroundTask`, vérifier
  que `start()` n'est appelé qu'une fois si déjà running.
- `AdminDiagnostic` : couverture freezed équivalente au reste du projet
  (json round-trip).

### Widget
- `AdminOverlay` : `pumpWidget` avec `isBatteryOptimExcludedProvider`
  overridé → icône visible / masquée.
- `AdminScreen` : pumpWidget → boutons appellent bien le checker / le
  controller.
- `FirstRunBatteryDialog` : flag `shared_preferences` empêche le re-affichage.

### Intégration manuelle / E2E (démo)
1. Build APK release, installer sur tablette.
2. Pair → notif "App de diffusion en cours" visible dans la barre.
3. Refuser popup batterie → AdminOverlay icône orange.
4. Settings → autoriser → revenir → icône disparaît.
5. `adb shell am force-stop` → service redémarre (logcat).
6. `adb reboot` → Player se relance tout seul plein écran.
7. Soak 24 h en notif LOW → pas de kill, lecture ininterrompue.

Pas de test pgTAP (pas de DB touchée).

## 7. Risques & mitigations

| Risque | Mitigation |
|---|---|
| Constructeurs custom (MIUI, Knox) tuent quand même le service | Doc déploiement + check démo. Pas couvert par code. |
| Refus systématique popup batterie par staff non technique | AdminOverlay persistant → jamais perdu, rattrapable. |
| `BOOT_COMPLETED` plus restrictif Android 14+ | Tester explicitement ; fallback `LOCKED_BOOT_COMPLETED`. |
| Plugin `flutter_foreground_task` abandonné dans 2 ans | Code wrappé derrière `ForegroundServiceController` → swap possible vers Kotlin natif sans toucher au reste. |

## 8. Critères d'acceptation

- [ ] Notification persistante visible dans la status bar dès qu'un device est appairé.
- [ ] Au reboot Android, le Player se relance et reprend la diffusion sans intervention.
- [ ] Si battery optim n'est pas exclue, icône warning visible dans le coin haut-droit.
- [ ] Tap sur l'icône → AdminScreen avec diagnostic + bouton fonctionnel.
- [ ] Tests Dart unit + widget passent (≥ 5 nouveaux tests).
- [ ] Démo manuelle complète : pair → notif → refuse battery → icône → autorise → icône disparaît → reboot adb → reprise auto.
- [ ] Documentation déploiement mise à jour (CLAUDE.md gotcha si nouveau).
