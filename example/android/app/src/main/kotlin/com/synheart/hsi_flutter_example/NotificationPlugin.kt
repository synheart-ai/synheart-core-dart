package com.synheart.hsi_flutter_example

import android.content.ComponentName
import android.content.Context
import android.provider.Settings
import android.text.TextUtils
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel

class NotificationPlugin : FlutterPlugin, EventChannel.StreamHandler {
    private var eventChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null
    private var context: Context? = null
    private var reconnectHandler: android.os.Handler? = null
    private var reconnectRunnable: Runnable? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        eventChannel = EventChannel(binding.binaryMessenger, "notifications")
        eventChannel?.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        eventChannel?.setStreamHandler(null)
        HsiNotificationListenerService.eventSink = null
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        android.util.Log.d("NotificationPlugin", "onListen called, setting event sink")

        // Always set the event sink in the service (even if permission not granted yet)
        // This allows notifications to flow when permission is granted later
        HsiNotificationListenerService.eventSink = eventSink
        android.util.Log.d("NotificationPlugin", "Event sink set in service: ${eventSink != null}")

        // Check if notification access is granted
        val hasPermission = isNotificationServiceEnabled()
        if (!hasPermission) {
            android.util.Log.d(
                    "NotificationPlugin",
                    "Notification access not granted, but keeping stream open"
            )
            // Send error once, but keep stream open so it can recover when permission is granted
            eventSink?.error(
                    "PERMISSION_DENIED",
                    "Notification access not granted. Please enable it in Settings -> Apps -> Special app access -> Notification access",
                    null
            )
        } else {
            // Permission granted
            android.util.Log.d("NotificationPlugin", "Notification access granted, service ready")
        }

        // Periodically ensure event sink is connected (in case service restarted)
        // This ensures the event sink stays connected even if the service restarts
        reconnectHandler = android.os.Handler(android.os.Looper.getMainLooper())
        reconnectRunnable =
                object : Runnable {
                    override fun run() {
                        if (eventSink != null) {
                            // Always ensure event sink is set (service might have restarted)
                            if (HsiNotificationListenerService.eventSink != eventSink) {
                                android.util.Log.d(
                                        "NotificationPlugin",
                                        "Re-connecting event sink to service"
                                )
                                HsiNotificationListenerService.eventSink = eventSink
                            }
                            // Check again in 5 seconds
                            reconnectHandler?.postDelayed(this, 5000)
                        }
                    }
                }
        reconnectHandler?.postDelayed(reconnectRunnable!!, 1000)
    }

    override fun onCancel(arguments: Any?) {
        // Stop reconnection handler
        reconnectRunnable?.let { reconnectHandler?.removeCallbacks(it) }
        reconnectHandler = null
        reconnectRunnable = null

        eventSink = null
        HsiNotificationListenerService.eventSink = null
    }

    private fun isNotificationServiceEnabled(): Boolean {
        val context = this.context ?: return false
        val pkgName = context.packageName
        val flat =
                Settings.Secure.getString(context.contentResolver, "enabled_notification_listeners")
        if (!TextUtils.isEmpty(flat)) {
            val names = flat.split(":").toTypedArray()
            for (name in names) {
                val componentName = ComponentName.unflattenFromString(name)
                if (componentName != null) {
                    // Check if our service is in the list
                    if (componentName.packageName == pkgName &&
                                    componentName.className.contains(
                                            "HsiNotificationListenerService"
                                    )
                    ) {
                        android.util.Log.d(
                                "NotificationPlugin",
                                "Notification service enabled: ${componentName.flattenToString()}"
                        )
                        return true
                    }
                }
            }
        }
        android.util.Log.d(
                "NotificationPlugin",
                "Notification service not enabled. Package: $pkgName, Flat: $flat"
        )
        return false
    }
}
