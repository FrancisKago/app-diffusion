# Phase 9 — Foreground Service & Robustesse Player — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rendre le Player Android survivable 24/7 (foreground service, auto-restart au reboot, demande d'exclusion battery optimization, écran admin diagnostic).

**Architecture:** Plugin `flutter_foreground_task` pour le service Android natif + notif persistante. `BootReceiver` Kotlin pour relancer service+activity au `BOOT_COMPLETED`. `BatteryOptimChecker` via MethodChannel léger. UI : `AdminOverlay` discret en coin haut-droit du `PlayerScreen` + `AdminScreen` modal pour diagnostic et actions admin (re-pair, force-sync, demander exclusion batterie). État "first-run dialog déjà affichée" persisté dans une nouvelle table Drift `LocalSettings` (schemaVersion 2 → 3).

**Tech Stack:** Flutter 3.38, Dart 3.6, Riverpod, `flutter_foreground_task` v8.x, `package_info_plus` v8.x, Drift 2.21, Kotlin (Android natif), MethodChannel, mocktail.

**Spec source:** [`docs/superpowers/specs/2026-04-25-phase9-foreground-service-design.md`](../specs/2026-04-25-phase9-foreground-service-design.md)

---

## Task 1 : Dépendances pubspec + permissions Android

**Files:**
- Modify: `apps/player/pubspec.yaml`
- Modify: `apps/player/android/app/src/main/AndroidManifest.xml`

- [ ] **Step 1: Ajouter les deux dépendances**

Edit `apps/player/pubspec.yaml`, dans la section `dependencies:`, ajouter les deux lignes alphabétiquement entre les deps existantes :

```yaml
  flutter_foreground_task: ^8.17.0
  package_info_plus: ^8.1.2
```

- [ ] **Step 2: Récupérer les packages**

```bash
cd "D:/App de diffusion/apps/player" && flutter pub get
```

Expected: `Got dependencies in D:\App de diffusion!` sans erreur.

- [ ] **Step 3: Ajouter les permissions et le service au manifest**

Remplacer le contenu de `apps/player/android/app/src/main/AndroidManifest.xml` par :

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
    <uses-permission android:name="android.permission.WAKE_LOCK" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
    <uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" />
    <uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW" />
    <application
        android:label="player"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher"
        android:usesCleartextTraffic="true">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:taskAffinity=""
            android:theme="@style/LaunchTheme"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize">
            <meta-data
              android:name="io.flutter.embedding.android.NormalTheme"
              android:resource="@style/NormalTheme"
              />
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>

        <!-- Foreground service du plugin flutter_foreground_task -->
        <service
            android:name="com.pravera.flutter_foreground_task.service.ForegroundService"
            android:foregroundServiceType="mediaPlayback"
            android:exported="false"
            android:stopWithTask="false" />

        <!-- BootReceiver custom : relance service + activity au reboot -->
        <receiver
            android:name=".BootReceiver"
            android:enabled="true"
            android:exported="true"
            android:permission="android.permission.RECEIVE_BOOT_COMPLETED">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.LOCKED_BOOT_COMPLETED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>

        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />
    </application>
    <queries>
        <intent>
            <action android:name="android.intent.action.PROCESS_TEXT"/>
            <data android:mimeType="text/plain"/>
        </intent>
    </queries>
</manifest>
```

- [ ] **Step 4: Build sanity check (Android)**

```bash
cd "D:/App de diffusion/apps/player" && flutter build apk --debug --no-tree-shake-icons 2>&1 | tail -8
```

Expected: build réussit (peut être lent à cause du gotcha Kotlin Windows, mais doit terminer sans erreur de manifest).

- [ ] **Step 5: Commit**

```bash
cd "D:/App de diffusion" && git add apps/player/pubspec.yaml apps/player/pubspec.lock apps/player/android/app/src/main/AndroidManifest.xml && git commit -m "chore(player): add flutter_foreground_task deps + Android permissions"
```

---

## Task 2 : Table Drift `LocalSettings` (schema v3)

**Files:**
- Modify: `apps/player/lib/data/local/app_database.dart`
- Test: `apps/player/test/data/local/local_settings_test.dart`

- [ ] **Step 1: Écrire le test failing**

Créer `apps/player/test/data/local/local_settings_test.dart` :

```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/data/local/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  test('getSetting returns null when key absent', () async {
    expect(await db.getSetting('foo'), isNull);
  });

  test('upsertSetting + getSetting round-trip', () async {
    await db.upsertSetting('first_run_battery_shown', '1');
    expect(await db.getSetting('first_run_battery_shown'), '1');
  });

  test('upsertSetting overwrites existing value', () async {
    await db.upsertSetting('k', 'a');
    await db.upsertSetting('k', 'b');
    expect(await db.getSetting('k'), 'b');
  });
}
```

- [ ] **Step 2: Lancer le test, vérifier qu'il échoue**

```bash
cd "D:/App de diffusion/apps/player" && flutter test test/data/local/local_settings_test.dart
```

Expected: FAIL avec "The method 'getSetting' isn't defined" / "upsertSetting isn't defined".

- [ ] **Step 3: Ajouter la table + bump schemaVersion + queries**

Dans `apps/player/lib/data/local/app_database.dart`, après la classe `CachedMedia`, ajouter :

```dart
class LocalSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}
```

Dans `@DriftDatabase(tables: [...])`, ajouter `LocalSettings` à la liste :

```dart
@DriftDatabase(
  tables: [
    CachedPlaylist,
    CachedPlaylistItems,
    CachedMedia,
    PendingPlaybackLogs,
    LocalSettings,
  ],
)
```

Bumper `schemaVersion` de 2 à 3 et étendre `onUpgrade` :

```dart
  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(pendingPlaybackLogs);
          }
          if (from < 3) {
            await m.createTable(localSettings);
          }
        },
      );
```

À la fin de la classe `AppDatabase`, juste avant la fermeture `}`, ajouter les deux queries :

```dart
  // ----- Local settings (KV) -----

  Future<String?> getSetting(String key) async {
    final row = await (select(localSettings)
          ..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> upsertSetting(String key, String value) =>
      into(localSettings).insertOnConflictUpdate(
        LocalSettingsCompanion(
          key: Value(key),
          value: Value(value),
        ),
      );
```

- [ ] **Step 4: Re-générer le code Drift**

```bash
cd "D:/App de diffusion/apps/player" && dart run build_runner build --delete-conflicting-outputs
```

Expected: `[INFO] Succeeded after ...` sans erreur.

- [ ] **Step 5: Lancer le test, vérifier qu'il passe**

```bash
cd "D:/App de diffusion/apps/player" && flutter test test/data/local/local_settings_test.dart
```

Expected: All 3 tests passed.

- [ ] **Step 6: Commit**

```bash
cd "D:/App de diffusion" && git add apps/player/lib/data/local/app_database.dart apps/player/lib/data/local/app_database.g.dart apps/player/test/data/local/local_settings_test.dart && git commit -m "feat(player): add LocalSettings KV table (drift schema v3)"
```

---

## Task 3 : `BatteryOptimChecker` Dart + plugin Kotlin natif

**Files:**
- Create: `apps/player/lib/features/lifecycle/data/battery_optim_checker.dart`
- Create: `apps/player/android/app/src/main/kotlin/com/appdiffusion/player/BatteryOptimPlugin.kt`
- Modify: `apps/player/android/app/src/main/kotlin/com/appdiffusion/player/MainActivity.kt`
- Test: `apps/player/test/features/lifecycle/battery_optim_checker_test.dart`

- [ ] **Step 1: Écrire le test failing**

Créer `apps/player/test/features/lifecycle/battery_optim_checker_test.dart` :

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/features/lifecycle/data/battery_optim_checker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('app.player/battery_optim');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('isExcluded returns true when native says true', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'isExcluded');
      return true;
    });
    final checker = NativeBatteryOptimChecker();
    expect(await checker.isExcluded(), isTrue);
  });

  test('isExcluded defaults to false when native returns null', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);
    final checker = NativeBatteryOptimChecker();
    expect(await checker.isExcluded(), isFalse);
  });

  test('openExclusionSettings invokes the right method', () async {
    var called = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'openExclusionSettings') {
        called = true;
      }
      return null;
    });
    await NativeBatteryOptimChecker().openExclusionSettings();
    expect(called, isTrue);
  });
}
```

- [ ] **Step 2: Lancer le test, vérifier qu'il échoue**

```bash
cd "D:/App de diffusion/apps/player" && flutter test test/features/lifecycle/battery_optim_checker_test.dart
```

Expected: FAIL avec "Target of URI doesn't exist".

- [ ] **Step 3: Implémenter le checker Dart**

Créer `apps/player/lib/features/lifecycle/data/battery_optim_checker.dart` :

```dart
import 'package:flutter/services.dart';

abstract class BatteryOptimChecker {
  Future<bool> isExcluded();
  Future<void> openExclusionSettings();
}

class NativeBatteryOptimChecker implements BatteryOptimChecker {
  static const _channel = MethodChannel('app.player/battery_optim');

  @override
  Future<bool> isExcluded() async {
    final result = await _channel.invokeMethod<bool>('isExcluded');
    return result ?? false;
  }

  @override
  Future<void> openExclusionSettings() async {
    await _channel.invokeMethod<void>('openExclusionSettings');
  }
}
```

- [ ] **Step 4: Lancer le test, vérifier qu'il passe**

```bash
cd "D:/App de diffusion/apps/player" && flutter test test/features/lifecycle/battery_optim_checker_test.dart
```

Expected: All 3 tests passed.

- [ ] **Step 5: Implémenter le plugin Kotlin natif**

Créer `apps/player/android/app/src/main/kotlin/com/appdiffusion/player/BatteryOptimPlugin.kt` :

```kotlin
package com.appdiffusion.player

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodChannel

class BatteryOptimPlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null
    private var appContext: Context? = null
    private var activityBinding: ActivityPluginBinding? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "app.player/battery_optim")
        channel?.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        appContext = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
    }

    override fun onDetachedFromActivity() {
        activityBinding = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activityBinding = binding
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityBinding = null
    }

    override fun onMethodCall(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        val ctx = appContext
        if (ctx == null) {
            result.error("NO_CONTEXT", "Plugin not attached", null)
            return
        }
        when (call.method) {
            "isExcluded" -> {
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
                    result.success(true) // pre-M : pas de Doze
                    return
                }
                val pm = ctx.getSystemService(Context.POWER_SERVICE) as PowerManager
                result.success(pm.isIgnoringBatteryOptimizations(ctx.packageName))
            }
            "openExclusionSettings" -> {
                val activity = activityBinding?.activity
                if (activity == null) {
                    result.error("NO_ACTIVITY", "No active activity to launch settings", null)
                    return
                }
                val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                    data = Uri.parse("package:${ctx.packageName}")
                }
                activity.startActivity(intent)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }
}
```

- [ ] **Step 6: Enregistrer le plugin dans MainActivity**

Remplacer `apps/player/android/app/src/main/kotlin/com/appdiffusion/player/MainActivity.kt` par :

```kotlin
package com.appdiffusion.player

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(BatteryOptimPlugin())
    }
}
```

- [ ] **Step 7: Commit**

```bash
cd "D:/App de diffusion" && git add apps/player/lib/features/lifecycle/data/battery_optim_checker.dart apps/player/test/features/lifecycle/battery_optim_checker_test.dart apps/player/android/app/src/main/kotlin/com/appdiffusion/player/BatteryOptimPlugin.kt apps/player/android/app/src/main/kotlin/com/appdiffusion/player/MainActivity.kt && git commit -m "feat(player): add BatteryOptimChecker (Dart + Kotlin MethodChannel)"
```

---

## Task 4 : Modèle `AdminDiagnostic` dans le package shared

**Files:**
- Create: `packages/shared/lib/src/models/admin_diagnostic.dart`
- Modify: `packages/shared/lib/shared.dart`
- Test: `packages/shared/test/models/admin_diagnostic_test.dart`

- [ ] **Step 1: Écrire le test failing**

Créer `packages/shared/test/models/admin_diagnostic_test.dart` :

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';

void main() {
  test('AdminDiagnostic copyWith works', () {
    const d = AdminDiagnostic(
      appVersion: '0.1.0',
      deviceId: 'd1',
      foregroundServiceRunning: false,
      batteryOptimExcluded: false,
    );
    final d2 = d.copyWith(batteryOptimExcluded: true);
    expect(d2.batteryOptimExcluded, isTrue);
    expect(d2.deviceId, 'd1');
  });

  test('AdminDiagnostic equality', () {
    const a = AdminDiagnostic(
      appVersion: '0.1.0',
      deviceId: 'd1',
      foregroundServiceRunning: true,
      batteryOptimExcluded: true,
    );
    const b = AdminDiagnostic(
      appVersion: '0.1.0',
      deviceId: 'd1',
      foregroundServiceRunning: true,
      batteryOptimExcluded: true,
    );
    expect(a, equals(b));
  });
}
```

- [ ] **Step 2: Lancer le test, vérifier qu'il échoue**

```bash
cd "D:/App de diffusion/packages/shared" && flutter test test/models/admin_diagnostic_test.dart
```

Expected: FAIL avec "AdminDiagnostic isn't defined".

- [ ] **Step 3: Créer le modèle freezed**

Créer `packages/shared/lib/src/models/admin_diagnostic.dart` :

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'admin_diagnostic.freezed.dart';

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

- [ ] **Step 4: Exporter depuis shared.dart**

Dans `packages/shared/lib/shared.dart`, ajouter cette ligne dans le bloc des exports modèles (alphabétique après `device.dart`) :

```dart
export 'src/models/admin_diagnostic.dart';
```

- [ ] **Step 5: Re-générer le code freezed**

```bash
cd "D:/App de diffusion/packages/shared" && dart run build_runner build --delete-conflicting-outputs
```

Expected: nouveau fichier `admin_diagnostic.freezed.dart` créé.

- [ ] **Step 6: Lancer le test, vérifier qu'il passe**

```bash
cd "D:/App de diffusion/packages/shared" && flutter test test/models/admin_diagnostic_test.dart
```

Expected: All 2 tests passed.

- [ ] **Step 7: Commit**

```bash
cd "D:/App de diffusion" && git add packages/shared/lib/src/models/admin_diagnostic.dart packages/shared/lib/src/models/admin_diagnostic.freezed.dart packages/shared/lib/shared.dart packages/shared/test/models/admin_diagnostic_test.dart && git commit -m "feat(shared): add AdminDiagnostic model"
```

---

## Task 5 : `ForegroundServiceController` Dart

**Files:**
- Create: `apps/player/lib/features/lifecycle/application/foreground_service_controller.dart`
- Test: `apps/player/test/features/lifecycle/foreground_service_controller_test.dart`

- [ ] **Step 1: Écrire le test failing**

Créer `apps/player/test/features/lifecycle/foreground_service_controller_test.dart` :

```dart
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:player/features/lifecycle/application/foreground_service_controller.dart';

class _FakeIsRunning {
  bool value = false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('start() is a no-op if already running', () async {
    final state = _FakeIsRunning()..value = true;
    var startCount = 0;
    final controller = ForegroundServiceController(
      isRunningProbe: () async => state.value,
      starter: () async {
        startCount++;
        state.value = true;
        return ServiceRequestResult.success();
      },
      stopper: () async {
        state.value = false;
        return ServiceRequestResult.success();
      },
    );
    await controller.start();
    expect(startCount, 0);
  });

  test('start() invokes starter when not running', () async {
    final state = _FakeIsRunning()..value = false;
    var startCount = 0;
    final controller = ForegroundServiceController(
      isRunningProbe: () async => state.value,
      starter: () async {
        startCount++;
        state.value = true;
        return ServiceRequestResult.success();
      },
      stopper: () async {
        state.value = false;
        return ServiceRequestResult.success();
      },
    );
    await controller.start();
    expect(startCount, 1);
  });

  test('stop() invokes stopper', () async {
    final state = _FakeIsRunning()..value = true;
    var stopCount = 0;
    final controller = ForegroundServiceController(
      isRunningProbe: () async => state.value,
      starter: () async => ServiceRequestResult.success(),
      stopper: () async {
        stopCount++;
        state.value = false;
        return ServiceRequestResult.success();
      },
    );
    await controller.stop();
    expect(stopCount, 1);
  });
}
```

- [ ] **Step 2: Lancer le test, vérifier qu'il échoue**

```bash
cd "D:/App de diffusion/apps/player" && flutter test test/features/lifecycle/foreground_service_controller_test.dart
```

Expected: FAIL avec "Target of URI doesn't exist".

- [ ] **Step 3: Implémenter le controller**

Créer `apps/player/lib/features/lifecycle/application/foreground_service_controller.dart` :

```dart
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

typedef IsRunningProbe = Future<bool> Function();
typedef ServiceStarter = Future<ServiceRequestResult> Function();
typedef ServiceStopper = Future<ServiceRequestResult> Function();

class ForegroundServiceController {
  ForegroundServiceController({
    IsRunningProbe? isRunningProbe,
    ServiceStarter? starter,
    ServiceStopper? stopper,
  })  : _isRunningProbe = isRunningProbe ?? FlutterForegroundTask.isRunningService,
        _starter = starter ?? _defaultStarter,
        _stopper = stopper ?? FlutterForegroundTask.stopService;

  final IsRunningProbe _isRunningProbe;
  final ServiceStarter _starter;
  final ServiceStopper _stopper;

  Future<void> start() async {
    if (await _isRunningProbe()) return;
    await _starter();
  }

  Future<void> stop() async {
    await _stopper();
  }

  Future<bool> isRunning() => _isRunningProbe();

  static Future<ServiceRequestResult> _defaultStarter() {
    return FlutterForegroundTask.startService(
      serviceId: 7421, // arbitraire mais stable
      notificationTitle: 'App de diffusion',
      notificationText: 'Lecture en cours',
    );
  }
}
```

- [ ] **Step 4: Lancer le test, vérifier qu'il passe**

```bash
cd "D:/App de diffusion/apps/player" && flutter test test/features/lifecycle/foreground_service_controller_test.dart
```

Expected: All 3 tests passed.

- [ ] **Step 5: Commit**

```bash
cd "D:/App de diffusion" && git add apps/player/lib/features/lifecycle/application/foreground_service_controller.dart apps/player/test/features/lifecycle/foreground_service_controller_test.dart && git commit -m "feat(player): add ForegroundServiceController wrapper"
```

---

## Task 6 : Riverpod providers `lifecycle_providers.dart`

**Files:**
- Create: `apps/player/lib/features/lifecycle/application/lifecycle_providers.dart`

- [ ] **Step 1: Écrire le code (pas de test direct — providers triviaux, testés via UI)**

Créer `apps/player/lib/features/lifecycle/application/lifecycle_providers.dart` :

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:player/data/local/app_database.dart';
import 'package:player/data/providers.dart';
import 'package:player/features/lifecycle/application/foreground_service_controller.dart';
import 'package:player/features/lifecycle/data/battery_optim_checker.dart';
import 'package:player/providers.dart';
import 'package:shared/shared.dart';

final batteryOptimCheckerProvider = Provider<BatteryOptimChecker>((ref) {
  return NativeBatteryOptimChecker();
});

final foregroundServiceProvider = Provider<ForegroundServiceController>((ref) {
  return ForegroundServiceController();
});

final isBatteryOptimExcludedProvider = FutureProvider<bool>((ref) async {
  return ref.read(batteryOptimCheckerProvider).isExcluded();
});

final foregroundServiceRunningProvider = FutureProvider<bool>((ref) async {
  return ref.read(foregroundServiceProvider).isRunning();
});

final lastSyncOkProvider = StateProvider<DateTime?>((ref) => null);

final adminDiagnosticProvider = FutureProvider<AdminDiagnostic>((ref) async {
  final creds = await ref.watch(credentialsProvider.future);
  final pkg = await PackageInfo.fromPlatform();
  final batteryExcluded =
      await ref.watch(isBatteryOptimExcludedProvider.future);
  final serviceRunning =
      await ref.watch(foregroundServiceRunningProvider.future);
  final lastSync = ref.watch(lastSyncOkProvider);
  return AdminDiagnostic(
    appVersion: '${pkg.version}+${pkg.buildNumber}',
    deviceId: creds?.deviceId ?? '—',
    establishmentName: null, // Phase 9 : non rempli, peut être branché plus tard
    lastSyncOk: lastSync,
    foregroundServiceRunning: serviceRunning,
    batteryOptimExcluded: batteryExcluded,
  );
});

const _kFirstRunBatteryShownKey = 'first_run_battery_shown';

final firstRunBatteryShownProvider = FutureProvider<bool>((ref) async {
  final db = ref.read(appDatabaseProvider);
  final v = await db.getSetting(_kFirstRunBatteryShownKey);
  return v == '1';
});

final markFirstRunBatteryShownProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    final db = ref.read(appDatabaseProvider);
    await db.upsertSetting(_kFirstRunBatteryShownKey, '1');
    ref.invalidate(firstRunBatteryShownProvider);
  };
});
```

- [ ] **Step 2: Vérifier que ça compile**

```bash
cd "D:/App de diffusion/apps/player" && flutter analyze lib/features/lifecycle/
```

Expected: `No issues found!`.

- [ ] **Step 3: Commit**

```bash
cd "D:/App de diffusion" && git add apps/player/lib/features/lifecycle/application/lifecycle_providers.dart && git commit -m "feat(player): add lifecycle Riverpod providers"
```

---

## Task 7 : `BootReceiver.kt` (Kotlin)

**Files:**
- Create: `apps/player/android/app/src/main/kotlin/com/appdiffusion/player/BootReceiver.kt`

- [ ] **Step 1: Implémenter le receiver**

Créer `apps/player/android/app/src/main/kotlin/com/appdiffusion/player/BootReceiver.kt` :

```kotlin
package com.appdiffusion.player

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != Intent.ACTION_LOCKED_BOOT_COMPLETED &&
            action != "android.intent.action.QUICKBOOT_POWERON") {
            return
        }
        val launchIntent = Intent(context, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        // Sur Android 10+ (API 29), le démarrage d'une Activity depuis un BroadcastReceiver
        // est restreint, sauf juste après BOOT_COMPLETED qui bénéficie d'une exception
        // explicite (cf. https://developer.android.com/guide/components/activities/background-starts).
        try {
            context.startActivity(launchIntent)
        } catch (_: Exception) {
            // Sur certains constructeurs (Xiaomi, Oppo), le start échoue silencieusement.
            // Le foreground service démarrera quand l'utilisateur rouvre l'app via le launcher.
        }
        // L'Activity démarre PlayerScreen → PlayerScreen démarre le foreground service via
        // ForegroundServiceController. On laisse ce flow plutôt que démarrer le service ici
        // (sinon on a besoin de connaître les options du plugin avant que Flutter init).
    }
}
```

- [ ] **Step 2: Build sanity check**

```bash
cd "D:/App de diffusion/apps/player" && flutter build apk --debug --no-tree-shake-icons 2>&1 | tail -8
```

Expected: build réussit. Si erreur Kotlin compile, vérifier l'import `Intent.ACTION_LOCKED_BOOT_COMPLETED` (constante depuis API 24, OK pour minSdk Flutter par défaut).

- [ ] **Step 3: Commit**

```bash
cd "D:/App de diffusion" && git add apps/player/android/app/src/main/kotlin/com/appdiffusion/player/BootReceiver.kt && git commit -m "feat(player): add BootReceiver to relaunch app at boot"
```

---

## Task 8 : Widget `AdminOverlay`

**Files:**
- Create: `apps/player/lib/features/lifecycle/presentation/admin_overlay.dart`
- Test: `apps/player/test/features/lifecycle/admin_overlay_test.dart`

- [ ] **Step 1: Écrire le test failing**

Créer `apps/player/test/features/lifecycle/admin_overlay_test.dart` :

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/features/lifecycle/application/lifecycle_providers.dart';
import 'package:player/features/lifecycle/presentation/admin_overlay.dart';

void main() {
  testWidgets('shows nothing when battery optim is excluded',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isBatteryOptimExcludedProvider.overrideWith((ref) async => true),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: Stack(children: [AdminOverlay()]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
  });

  testWidgets('shows orange warning icon when battery optim is NOT excluded',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isBatteryOptimExcludedProvider.overrideWith((ref) async => false),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: Stack(children: [AdminOverlay()]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
  });
}
```

- [ ] **Step 2: Lancer le test, vérifier qu'il échoue**

```bash
cd "D:/App de diffusion/apps/player" && flutter test test/features/lifecycle/admin_overlay_test.dart
```

Expected: FAIL avec "Target of URI doesn't exist".

- [ ] **Step 3: Implémenter le widget**

Créer `apps/player/lib/features/lifecycle/presentation/admin_overlay.dart` :

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:player/features/lifecycle/application/lifecycle_providers.dart';
import 'package:player/features/lifecycle/presentation/admin_screen.dart';

class AdminOverlay extends ConsumerWidget {
  const AdminOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final excludedAsync = ref.watch(isBatteryOptimExcludedProvider);
    final excluded = excludedAsync.valueOrNull ?? true; // optimiste : pas d'icône pendant le load
    if (excluded) return const SizedBox.shrink();
    return Positioned(
      top: 8,
      right: 8,
      child: Material(
        color: Colors.transparent,
        child: IconButton(
          icon: const Icon(
            Icons.warning_amber_rounded,
            color: Colors.orangeAccent,
            size: 28,
          ),
          tooltip: "Optimisation batterie active — toucher pour ouvrir l'admin",
          onPressed: () {
            Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => const AdminScreen()),
            );
          },
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Lancer le test, vérifier qu'il passe**

```bash
cd "D:/App de diffusion/apps/player" && flutter test test/features/lifecycle/admin_overlay_test.dart
```

Expected: All 2 tests passed (l'erreur de compile sur `admin_screen.dart` sera résolue par Task 9 — créer un stub vide pour l'instant si besoin).

> Si le test échoue avec "admin_screen.dart not found", créer un stub minimal :
> ```dart
> // apps/player/lib/features/lifecycle/presentation/admin_screen.dart
> import 'package:flutter/material.dart';
> class AdminScreen extends StatelessWidget {
>   const AdminScreen({super.key});
>   @override Widget build(BuildContext context) =>
>       const Scaffold(body: Center(child: Text('admin')));
> }
> ```
> Le vrai écran sera implémenté en Task 9.

- [ ] **Step 5: Commit**

```bash
cd "D:/App de diffusion" && git add apps/player/lib/features/lifecycle/presentation/admin_overlay.dart apps/player/lib/features/lifecycle/presentation/admin_screen.dart apps/player/test/features/lifecycle/admin_overlay_test.dart && git commit -m "feat(player): add AdminOverlay warning icon"
```

---

## Task 9 : Widget `AdminScreen`

**Files:**
- Modify (overwrite stub): `apps/player/lib/features/lifecycle/presentation/admin_screen.dart`
- Test: `apps/player/test/features/lifecycle/admin_screen_test.dart`

- [ ] **Step 1: Écrire le test failing**

Créer `apps/player/test/features/lifecycle/admin_screen_test.dart` :

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:player/features/lifecycle/application/lifecycle_providers.dart';
import 'package:player/features/lifecycle/data/battery_optim_checker.dart';
import 'package:player/features/lifecycle/presentation/admin_screen.dart';
import 'package:shared/shared.dart';

class _MockChecker extends Mock implements BatteryOptimChecker {}

void main() {
  testWidgets('renders diagnostic fields and battery exclusion button',
      (tester) async {
    final checker = _MockChecker();
    when(() => checker.isExcluded()).thenAnswer((_) async => false);
    when(() => checker.openExclusionSettings()).thenAnswer((_) async {});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          batteryOptimCheckerProvider.overrideWithValue(checker),
          adminDiagnosticProvider.overrideWith((ref) async {
            return const AdminDiagnostic(
              appVersion: '0.1.0+1',
              deviceId: 'd-abc',
              foregroundServiceRunning: true,
              batteryOptimExcluded: false,
            );
          }),
        ],
        child: const MaterialApp(home: AdminScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('0.1.0+1'), findsOneWidget);
    expect(find.text('d-abc'), findsOneWidget);
    expect(find.textContaining('Demander'), findsOneWidget);

    await tester.tap(find.textContaining('Demander'));
    await tester.pump();
    verify(() => checker.openExclusionSettings()).called(1);
  });
}
```

- [ ] **Step 2: Lancer le test, vérifier qu'il échoue**

```bash
cd "D:/App de diffusion/apps/player" && flutter test test/features/lifecycle/admin_screen_test.dart
```

Expected: FAIL (le stub n'a pas les champs ni le bouton).

- [ ] **Step 3: Implémenter le vrai `AdminScreen`**

Remplacer le contenu de `apps/player/lib/features/lifecycle/presentation/admin_screen.dart` par :

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:player/features/lifecycle/application/lifecycle_providers.dart';
import 'package:player/providers.dart';

class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final diagAsync = ref.watch(adminDiagnosticProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Admin Player')),
      body: diagAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur diag: $e')),
        data: (d) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _kv('Version', d.appVersion),
            _kv('Device id', d.deviceId),
            _kv('Établissement', d.establishmentName ?? '—'),
            _kv('Dernière sync OK', d.lastSyncOk?.toIso8601String() ?? 'jamais'),
            _kv(
              'Service foreground',
              d.foregroundServiceRunning ? 'actif' : 'arrêté',
            ),
            _kv(
              'Battery optimization exclue',
              d.batteryOptimExcluded ? 'oui' : 'non',
            ),
            const Divider(height: 32),
            if (!d.batteryOptimExcluded)
              FilledButton(
                onPressed: () =>
                    ref.read(batteryOptimCheckerProvider).openExclusionSettings(),
                child: const Text("Demander l'exclusion batterie"),
              ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () async {
                await ref.read(secureStorageProvider).clear();
                ref.invalidate(credentialsProvider);
                if (context.mounted) Navigator.of(context).pop();
              },
              child: const Text('Re-appairer (efface les credentials)'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Fermer'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 220,
              child: Text(k, style: const TextStyle(color: Colors.white70)),
            ),
            Expanded(child: Text(v)),
          ],
        ),
      );
}
```

- [ ] **Step 4: Lancer le test, vérifier qu'il passe**

```bash
cd "D:/App de diffusion/apps/player" && flutter test test/features/lifecycle/admin_screen_test.dart
```

Expected: All 1 test passed.

- [ ] **Step 5: Commit**

```bash
cd "D:/App de diffusion" && git add apps/player/lib/features/lifecycle/presentation/admin_screen.dart apps/player/test/features/lifecycle/admin_screen_test.dart && git commit -m "feat(player): add AdminScreen with diagnostic and admin actions"
```

---

## Task 10 : `FirstRunBatteryDialog`

**Files:**
- Create: `apps/player/lib/features/lifecycle/presentation/first_run_battery_dialog.dart`
- Test: `apps/player/test/features/lifecycle/first_run_battery_dialog_test.dart`

- [ ] **Step 1: Écrire le test failing**

Créer `apps/player/test/features/lifecycle/first_run_battery_dialog_test.dart` :

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:player/features/lifecycle/application/lifecycle_providers.dart';
import 'package:player/features/lifecycle/data/battery_optim_checker.dart';
import 'package:player/features/lifecycle/presentation/first_run_battery_dialog.dart';

class _MockChecker extends Mock implements BatteryOptimChecker {}

void main() {
  testWidgets('does NOT show dialog when already shown previously',
      (tester) async {
    var openCount = 0;
    final checker = _MockChecker();
    when(() => checker.openExclusionSettings()).thenAnswer((_) async {
      openCount++;
    });
    var markedShown = false;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          batteryOptimCheckerProvider.overrideWithValue(checker),
          firstRunBatteryShownProvider.overrideWith((ref) async => true),
          markFirstRunBatteryShownProvider.overrideWithValue(() async {
            markedShown = true;
          }),
        ],
        child: const MaterialApp(
          home: Scaffold(body: FirstRunBatteryGate(child: SizedBox.shrink())),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text("Autoriser l'exécution permanente"), findsNothing);
    expect(openCount, 0);
    expect(markedShown, isFalse);
  });

  testWidgets('shows dialog and tapping OK calls openExclusionSettings + marks shown',
      (tester) async {
    var openCount = 0;
    final checker = _MockChecker();
    when(() => checker.openExclusionSettings()).thenAnswer((_) async {
      openCount++;
    });
    var markedShown = false;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          batteryOptimCheckerProvider.overrideWithValue(checker),
          firstRunBatteryShownProvider.overrideWith((ref) async => false),
          markFirstRunBatteryShownProvider.overrideWithValue(() async {
            markedShown = true;
          }),
        ],
        child: const MaterialApp(
          home: Scaffold(body: FirstRunBatteryGate(child: SizedBox.shrink())),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text("Autoriser l'exécution permanente"), findsOneWidget);
    await tester.tap(find.text('Autoriser'));
    await tester.pumpAndSettle();
    expect(openCount, 1);
    expect(markedShown, isTrue);
  });
}
```

- [ ] **Step 2: Lancer le test, vérifier qu'il échoue**

```bash
cd "D:/App de diffusion/apps/player" && flutter test test/features/lifecycle/first_run_battery_dialog_test.dart
```

Expected: FAIL avec "Target of URI doesn't exist".

- [ ] **Step 3: Implémenter le widget**

Créer `apps/player/lib/features/lifecycle/presentation/first_run_battery_dialog.dart` :

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:player/features/lifecycle/application/lifecycle_providers.dart';

class FirstRunBatteryGate extends ConsumerStatefulWidget {
  const FirstRunBatteryGate({required this.child, super.key});
  final Widget child;

  @override
  ConsumerState<FirstRunBatteryGate> createState() =>
      _FirstRunBatteryGateState();
}

class _FirstRunBatteryGateState extends ConsumerState<FirstRunBatteryGate> {
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShow());
  }

  Future<void> _maybeShow() async {
    if (_checked) return;
    _checked = true;
    final shown = await ref.read(firstRunBatteryShownProvider.future);
    if (shown) return;
    final excluded = await ref.read(isBatteryOptimExcludedProvider.future);
    if (excluded) {
      // déjà OK, pas besoin de demander → marquer pour ne plus reposer
      await ref.read(markFirstRunBatteryShownProvider)();
      return;
    }
    if (!mounted) return;
    final action = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text("Autoriser l'exécution permanente"),
        content: const Text(
          "Pour garantir la diffusion 24h/24, l'app doit être exclue "
          "de l'optimisation batterie d'Android. Autoriser maintenant ?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Plus tard'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Autoriser'),
          ),
        ],
      ),
    );
    if (action == true) {
      await ref.read(batteryOptimCheckerProvider).openExclusionSettings();
    }
    await ref.read(markFirstRunBatteryShownProvider)();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
```

- [ ] **Step 4: Lancer le test, vérifier qu'il passe**

```bash
cd "D:/App de diffusion/apps/player" && flutter test test/features/lifecycle/first_run_battery_dialog_test.dart
```

Expected: All 2 tests passed.

- [ ] **Step 5: Commit**

```bash
cd "D:/App de diffusion" && git add apps/player/lib/features/lifecycle/presentation/first_run_battery_dialog.dart apps/player/test/features/lifecycle/first_run_battery_dialog_test.dart && git commit -m "feat(player): add FirstRunBatteryGate dialog"
```

---

## Task 11 : Wire-up dans `main.dart` et `player_screen.dart`

**Files:**
- Modify: `apps/player/lib/main.dart`
- Modify: `apps/player/lib/features/player/presentation/player_screen.dart`

- [ ] **Step 1: Init plugin dans main.dart**

Remplacer `apps/player/lib/main.dart` par :

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:player/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);

  FlutterForegroundTask.initCommunicationPort();
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'app_diffusion_playback',
      channelName: 'Lecture diffusion',
      channelDescription: "Indique que l'app de diffusion fonctionne en continu.",
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.LOW,
    ),
    iosNotificationOptions: const IOSNotificationOptions(),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.nothing(),
      autoRunOnBoot: true,
      autoRunOnMyPackageReplaced: true,
      allowWakeLock: true,
    ),
  );

  runApp(const ProviderScope(child: PlayerApp()));
}
```

- [ ] **Step 2: Wrapper PlayerScreen avec service start + overlay + first-run gate**

Dans `apps/player/lib/features/player/presentation/player_screen.dart` :

a) Ajouter ces imports avec les autres imports existants :

```dart
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:player/features/lifecycle/application/lifecycle_providers.dart';
import 'package:player/features/lifecycle/presentation/admin_overlay.dart';
import 'package:player/features/lifecycle/presentation/first_run_battery_dialog.dart';
```

b) Dans `_PlayerScreenState.initState()`, après `WakelockPlus.enable();`, ajouter :

```dart
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(foregroundServiceProvider).start();
    });
```

c) Dans `_PlayerScreenState.build(...)`, wrapper le retour final dans `WithForegroundTask` + `FirstRunBatteryGate` + `Stack` qui ajoute `AdminOverlay`. Remplacer la dernière clause `return Scaffold(...)` (celle qui rend la lecture, autour de la ligne 305) par :

```dart
    return WithForegroundTask(
      child: FirstRunBatteryGate(
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              Positioned.fill(child: Center(child: mediaWidget)),
              Positioned(
                bottom: 8,
                right: 12,
                child: Text(
                  '${_activeIndex + 1}/${_activeItems.length} · ${media.originalFilename}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.3),
                    fontSize: 10,
                  ),
                ),
              ),
              const AdminOverlay(),
            ],
          ),
        ),
      ),
    );
```

Faire le même wrapping minimal (`AdminOverlay` + `FirstRunBatteryGate`) pour les autres branches `build()` (loading initial sync + standby) — le but est que l'icône warning et le dialog soient visibles sur tous les états. Pour la branche loading initial (vers ligne 257), remplacer par :

```dart
    if (_initialSyncRunning) {
      return FirstRunBatteryGate(
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              const Center(child: CircularProgressIndicator()),
              Positioned(
                bottom: 24,
                left: 0,
                right: 0,
                child: Center(
                  child: Text(
                    'Synchronisation initiale…',
                    style:
                        TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                  ),
                ),
              ),
              const AdminOverlay(),
            ],
          ),
        ),
      );
    }
```

Pour la branche standby (vers ligne 278) :

```dart
    if (_currentMedia == null || _activeItems.isEmpty) {
      return FirstRunBatteryGate(
        child: Stack(
          children: [
            const StandbyScreen(),
            if (_syncError != null)
              Positioned(
                bottom: 16,
                left: 16,
                child: Text(
                  'Sync KO : $_syncError',
                  style: const TextStyle(color: Colors.redAccent, fontSize: 11),
                ),
              ),
            const AdminOverlay(),
          ],
        ),
      );
    }
```

Mettre à jour `lastSyncOkProvider` quand sync réussit. Dans `_runSync()` (vers ligne 67), juste après `_syncError = null;` dans le `setState`, ajouter en dehors du setState :

```dart
        ref.read(lastSyncOkProvider.notifier).state = DateTime.now();
```

- [ ] **Step 3: Vérifier que tous les tests passent encore**

```bash
cd "D:/App de diffusion/apps/player" && flutter test
```

Expected: tous les tests passent (les anciens + les nouveaux). Si un test PlayerScreen existant casse à cause du wrapping `WithForegroundTask`, corriger en ajoutant les overrides requis dans le test.

- [ ] **Step 4: Build APK release**

```bash
cd "D:/App de diffusion/apps/player" && flutter build apk --release --dart-define=SUPABASE_URL=http://192.168.1.72:54321 --dart-define=SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0 2>&1 | tail -10
```

Expected: `√ Built build/app/outputs/flutter-apk/app-release.apk`.

- [ ] **Step 5: Commit**

```bash
cd "D:/App de diffusion" && git add apps/player/lib/main.dart apps/player/lib/features/player/presentation/player_screen.dart && git commit -m "feat(player): wire foreground service + admin overlay + first-run gate"
```

---

## Task 12 : Documentation déploiement + démo manuelle

**Files:**
- Modify: `CLAUDE.md`
- Create: `docs/phase9-demo.md`

- [ ] **Step 1: Ajouter le gotcha CLAUDE.md**

Dans `CLAUDE.md`, dans la section `## Gotchas Windows (résolus mais à savoir)`, ajouter un point 9 :

```markdown
9. **Foreground service `mediaPlayback`** : depuis Phase 9, le manifest déclare le service du plugin `flutter_foreground_task`. Sur Android 14+, `FOREGROUND_SERVICE_MEDIA_PLAYBACK` est requise — déjà ajoutée. Si Play Store : justifier l'usage `mediaPlayback` (lecture vidéo en boucle pour signage) dans la fiche.
```

Mettre à jour la section `## Dette explicitement reportée` en retirant l'item :
```
- Foreground service Android (kiosque-friendly)
```
(c'est livré par cette phase).

- [ ] **Step 2: Créer la doc démo manuelle**

Créer `docs/phase9-demo.md` :

```markdown
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
```

- [ ] **Step 3: Commit**

```bash
cd "D:/App de diffusion" && git add CLAUDE.md docs/phase9-demo.md && git commit -m "docs(phase9): add deployment gotcha + manual demo script"
```

---

## Validation finale

- [ ] **Step 1: Lancer toute la suite de tests**

```bash
cd "D:/App de diffusion/apps/player" && flutter test 2>&1 | tail -20
cd "D:/App de diffusion/packages/shared" && flutter test 2>&1 | tail -10
```

Expected: 100% passing, ≥ 6 nouveaux tests Player + 2 nouveaux tests shared.

- [ ] **Step 2: Tester sur tablette physique**

Suivre `docs/phase9-demo.md` étapes 1-5 sur la tablette Samsung SM-X205. Étape 6 (soak 24h) optionnelle pour valider en conditions réelles plus tard.

- [ ] **Step 3: Vérifier le log**

```bash
cd "D:/App de diffusion" && git log --oneline -15
```

Expected : ≥ 12 commits Phase 9, dans l'ordre des tasks.

---

## Critères d'acceptation Phase 9 (rappel du spec)

- [ ] Notification persistante visible dès qu'un device est appairé.
- [ ] Au reboot, Player se relance et reprend la diffusion sans intervention.
- [ ] Icône warning orange visible si battery optim non excluded.
- [ ] AdminScreen accessible avec diagnostic + boutons fonctionnels.
- [ ] ≥ 5 nouveaux tests Dart unit + widget passent.
- [ ] Démo manuelle complète validée sur tablette physique.
- [ ] CLAUDE.md gotcha à jour, dette tech "Foreground service" retirée.
