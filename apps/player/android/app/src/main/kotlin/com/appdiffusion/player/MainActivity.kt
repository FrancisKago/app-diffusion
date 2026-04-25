package com.appdiffusion.player

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(BatteryOptimPlugin())
        FcmEngineHolder.engine = flutterEngine
    }

    override fun onDestroy() {
        if (FcmEngineHolder.engine === flutterEngine) {
            FcmEngineHolder.engine = null
        }
        super.onDestroy()
    }
}
