package com.appdiffusion.player

import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import io.flutter.plugin.common.MethodChannel

class FcmService : FirebaseMessagingService() {
    override fun onNewToken(token: String) {
        super.onNewToken(token)
        val engine = FcmEngineHolder.engine
        if (engine != null) {
            MethodChannel(engine.dartExecutor.binaryMessenger, "app.player/fcm_events")
                .invokeMethod("onTokenRefresh", token)
        } else {
            PendingFcmTokenStorage.save(applicationContext, token)
        }
    }

    override fun onMessageReceived(message: RemoteMessage) {
        super.onMessageReceived(message)
        val engine = FcmEngineHolder.engine ?: return
        val data = HashMap<String, String>(message.data)
        MethodChannel(engine.dartExecutor.binaryMessenger, "app.player/fcm_events")
            .invokeMethod("onMessage", data)
    }
}
