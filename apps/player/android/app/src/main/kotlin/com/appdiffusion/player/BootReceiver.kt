package com.appdiffusion.player

import android.content.BroadcastReceiver
import android.content.ComponentName
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

        // 1. Start the foreground service directly. The plugin's ForegroundService
        //    will read its persisted options (set by FlutterForegroundTask.init in main.dart
        //    last time the app ran) and post the notification before Flutter cold-starts.
        try {
            val serviceIntent = Intent().apply {
                component = ComponentName(
                    context,
                    "com.pravera.flutter_foreground_task.service.ForegroundService"
                )
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent)
            } else {
                context.startService(serviceIntent)
            }
        } catch (_: Exception) {
            // OEM may block service start from boot — fall through to activity launch.
        }

        // 2. Launch the activity so the player UI is visible right after boot.
        try {
            val launchIntent = Intent(context, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            }
            context.startActivity(launchIntent)
        } catch (_: Exception) {
            // OEM restrictions (Xiaomi/Oppo) may silently fail.
        }
    }
}
