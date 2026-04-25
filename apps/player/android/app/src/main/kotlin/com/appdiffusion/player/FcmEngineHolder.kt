package com.appdiffusion.player

import io.flutter.embedding.engine.FlutterEngine

/**
 * Singleton holder that lets background services (FcmService) reach the live
 * Flutter engine when one is attached. Set on MainActivity attach, cleared on detach.
 */
object FcmEngineHolder {
    @Volatile
    var engine: FlutterEngine? = null
}
