# Phase 9 — Démo robustesse Player

Pré-requis : APK Phase 9 installée, device appairé, playlist assignée.

## 1. Service foreground visible
- Pull-down de la status bar Android.
- ✅ Notification "App de diffusion · Lecture en cours" présente, niveau LOW (pas de son).

## 2. Premier démarrage : popup batterie
- Au tout premier lancement après pairing, dialog "Autoriser l'exécution permanente".
- Tap "Autoriser" → ouvre Settings Android sur la page d'exclusion batterie.
- Cocher l'app, revenir avec back → ✅ icône warning orange disparaît.

## 3. Refus puis rattrapage admin
- Re-installer l'APK (clear data) ou modifier `LocalSettings` pour reset le flag.
- Au démarrage, tap "Plus tard" sur la dialog.
- ✅ Icône warning orange visible en haut-droit du PlayerScreen.
- Tap sur l'icône → AdminScreen ouvre, montre "Battery optimization exclue : non".
- Tap "Demander l'exclusion batterie" → Settings Android.
- Autoriser, revenir → icône disparaît automatiquement.

## 4. Reboot tablette → reprise auto
- `adb reboot` (depuis PowerShell admin avec adb).
- Attendre que la tablette boot (≈45 s).
- ✅ Le Player se lance automatiquement plein écran sans intervention.
- ✅ La lecture reprend depuis le cache local sans nouvelle sync nécessaire.

## 5. Force-stop service → relance OS
- `adb shell am force-stop com.appdiffusion.player`
- ✅ La notification disparaît brièvement puis ré-apparaît (service relancé via START_STICKY).
- ⚠️ L'activity ne revient pas — seule l'icône Player tap depuis le launcher la ramène.
  C'est attendu : on protège contre le kill OS de fond, pas contre le force-stop user volontaire.

## 6. Soak 24 h
- Laisser tourner toute la nuit.
- ✅ Au matin : lecture toujours active, pas d'écran noir, pas d'écran de veille système.
- ✅ Notification toujours présente.
