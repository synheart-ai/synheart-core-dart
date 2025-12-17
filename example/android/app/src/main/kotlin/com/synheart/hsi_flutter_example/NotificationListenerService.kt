package com.synheart.hsi_flutter_example

import android.os.Build
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import io.flutter.plugin.common.EventChannel
import java.time.Instant
import java.time.ZoneOffset

class HsiNotificationListenerService : NotificationListenerService() {
    companion object {
        var eventSink: EventChannel.EventSink? = null
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        super.onNotificationPosted(sbn)

        // Ensure event sink is set (in case it wasn't set when permission was granted)
        if (eventSink == null) {
            // Don't log warnings repeatedly - only log once per session
            // The event sink will be set when Flutter connects to the stream
            return
        }

        eventSink?.let { sink ->
            try {
                val notification = sbn.notification
                val packageName = sbn.packageName

                // Extract category if available (Android 7.0+)
                val category =
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                            notification.category
                        } else {
                            null
                        }

                // Determine notification type from category or package
                val notificationCategory = category ?: _inferCategory(packageName)

                val timestamp =
                        Instant.ofEpochMilli(System.currentTimeMillis())
                                .atOffset(ZoneOffset.UTC)
                                .toString()

                val eventData =
                        mapOf(
                                "timestamp" to timestamp,
                                "opened" to false, // Posted, not opened
                                "category" to notificationCategory,
                                "sourceApp" to packageName
                        )

                sink.success(eventData)
            } catch (e: Exception) {
                sink.error(
                        "NOTIFICATION_ERROR",
                        "Error processing notification: ${e.message}",
                        null
                )
            }
        }
    }

    override fun onNotificationRemoved(
            sbn: StatusBarNotification,
            rankingMap: android.service.notification.NotificationListenerService.RankingMap?,
            reason: Int
    ) {
        super.onNotificationRemoved(sbn, rankingMap, reason)

        // Check if notification was removed because user opened it
        if (reason == REASON_CLICK || reason == REASON_USER_STOPPED) {
            eventSink?.let { sink ->
                try {
                    val notification = sbn.notification
                    val packageName = sbn.packageName

                    val category =
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                                notification.category
                            } else {
                                null
                            }

                    val notificationCategory = category ?: _inferCategory(packageName)

                    val timestamp =
                            Instant.ofEpochMilli(System.currentTimeMillis())
                                    .atOffset(ZoneOffset.UTC)
                                    .toString()

                    val eventData =
                            mapOf(
                                    "timestamp" to timestamp,
                                    "opened" to
                                            (reason == REASON_CLICK), // True if clicked, false if
                                    // dismissed
                                    "category" to notificationCategory,
                                    "sourceApp" to packageName
                            )

                    sink.success(eventData)
                } catch (e: Exception) {
                    sink.error(
                            "NOTIFICATION_ERROR",
                            "Error processing notification removal: ${e.message}",
                            null
                    )
                }
            }
        }
    }

    private fun _inferCategory(packageName: String): String {
        return when {
            packageName.contains("message") ||
                    packageName.contains("sms") ||
                    packageName.contains("whatsapp") ||
                    packageName.contains("telegram") -> "message"
            packageName.contains("mail") ||
                    packageName.contains("gmail") ||
                    packageName.contains("email") -> "email"
            packageName.contains("social") ||
                    packageName.contains("facebook") ||
                    packageName.contains("twitter") ||
                    packageName.contains("instagram") -> "social"
            packageName.contains("system") || packageName.contains("android") -> "system"
            else -> "other"
        }
    }
}
