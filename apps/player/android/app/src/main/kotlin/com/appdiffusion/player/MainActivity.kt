package com.appdiffusion.player

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(BatteryOptimPlugin())
        FcmEngineHolder.engine = flutterEngine

        // Drain any pending FCM token captured by FcmService while the engine
        // was not yet attached (cold start scenarios).
        val pendingToken = PendingFcmTokenStorage.read(applicationContext)
        if (pendingToken != null) {
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.player/fcm")
                .invokeMethod("onTokenRefresh", pendingToken)
            PendingFcmTokenStorage.clear(applicationContext)
        }
    }

    override fun onDestroy() {
        if (FcmEngineHolder.engine === flutterEngine) {
            FcmEngineHolder.engine = null
        }
        super.onDestroy()
    }
}
