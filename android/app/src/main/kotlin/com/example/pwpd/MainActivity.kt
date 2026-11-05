package com.pwpd.application

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.media.AudioAttributes
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)

        // Create the geofence notification channel (required for Android 8+)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "geofence_alerts",
                "Geofence Alerts",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Alerts when the wearable device exits or enters a geofence"
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 500, 250, 500)
                enableLights(true)
                lightColor = android.graphics.Color.RED
                setShowBadge(true)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                setSound(
                    Settings.System.DEFAULT_NOTIFICATION_URI,
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                        .build()
                )
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }
}
