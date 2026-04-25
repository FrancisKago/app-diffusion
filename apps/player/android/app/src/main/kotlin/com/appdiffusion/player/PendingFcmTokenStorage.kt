package com.appdiffusion.player

import android.content.Context

/**
 * Stocke un token FCM reçu par le service natif quand l'engine Flutter n'est
 * pas vivant. Le Dart side le lira au prochain démarrage et le pushera en DB.
 */
object PendingFcmTokenStorage {
    private const val PREFS_NAME = "fcm_pending"
    private const val KEY_TOKEN = "pending_token"

    fun save(context: Context, token: String) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_TOKEN, token)
            .apply()
    }

    fun read(context: Context): String? {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_TOKEN, null)
    }

    fun clear(context: Context) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .remove(KEY_TOKEN)
            .apply()
    }
}
