package com.appdiffusion.player

import com.google.firebase.messaging.FirebaseMessaging
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(BatteryOptimPlugin())
        FcmEngineHolder.engine = flutterEngine

        val fcmChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "app.player/fcm",
        )
        fcmChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getCurrentToken" -> {
                    FirebaseMessaging.getInstance().token
                        .addOnSuccessListener { token -> result.success(token) }
                        .addOnFailureListener { e -> result.error("FCM_TOKEN_ERROR", e.message, null) }
                }
                else -> result.notImplemented()
            }
        }

        // Drain any pending FCM token captured by FcmService while the engine
        // was not yet attached (cold start scenarios).
        val pendingToken = PendingFcmTokenStorage.read(applicationContext)
        if (pendingToken != null) {
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.player/fcm_events")
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
