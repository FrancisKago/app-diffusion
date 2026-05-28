import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fvp/fvp.dart' as fvp;
import 'package:player/app.dart';
import 'package:player/services/fcm_handler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Route video_player through fvp (libmpv/MDK) on Android. ExoPlayer renders
  // a black surface for some H.264 MP4s on certain tablet SoCs even though the
  // file is valid and plays elsewhere; fvp's renderer fixes that.
  fvp.registerWith(
    options: {
      'platforms': ['android'],
    },
  );

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

  final container = ProviderContainer();
  final fcmHandler = FcmHandlerImpl(ref: container);
  fcmHandler.wireChannel();
  setGlobalFcmHandler(fcmHandler);

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const PlayerApp(),
    ),
  );
}
