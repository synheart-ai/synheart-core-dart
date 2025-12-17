package com.synheart.hsi_flutter_example

import android.app.usage.UsageStatsManager
import android.content.Context
import android.os.Build
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.*

class AppFocusPlugin : FlutterPlugin, EventChannel.StreamHandler {
    private var eventChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null
    private var context: Context? = null
    private var job: Job? = null
    private val scope = CoroutineScope(Dispatchers.Default + SupervisorJob())
    private var lastAppPackage: String? = null
    private var permissionGrantedState: Boolean =
            false // Track permission state to log only on change

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        eventChannel = EventChannel(binding.binaryMessenger, "app_focus")
        eventChannel?.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        eventChannel?.setStreamHandler(null)
        stopTracking()
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        // Always start tracking - it will check permission internally
        // This allows the stream to be re-established after permission is granted
        android.util.Log.d("AppFocusPlugin", "onListen called, starting tracking")
        startTracking()
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
        stopTracking()
        permissionGrantedState = false // Reset state when stream is cancelled
    }

    private fun startTracking() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) {
            eventSink?.error("UNSUPPORTED", "App tracking requires Android 5.0+", null)
            return
        }

        // Don't send error events for permission - just wait silently
        // Sending errors can cause the EventChannel stream to close
        android.util.Log.d("AppFocusPlugin", "Starting app tracking loop")

        // Cancel any existing job first
        job?.cancel()

        job =
                scope.launch {
                    // Initialize permission state by checking once at start (silently)
                    permissionGrantedState =
                            try {
                                withContext(Dispatchers.Main) { hasUsageStatsPermission() }
                            } catch (e: Exception) {
                                false
                            }
                    // No logging - permission state tracked silently

                    while (isActive) {
                        try {
                            // Re-check permission periodically in case it was granted
                            // Must run on main thread for getSystemService
                            val permissionGranted =
                                    try {
                                        withContext(Dispatchers.Main) { hasUsageStatsPermission() }
                                    } catch (e: CancellationException) {
                                        throw e
                                    } catch (e: Exception) {
                                        // Don't log errors - just return false
                                        false
                                    }

                            // Update state silently - no logging
                            permissionGrantedState = permissionGranted

                            if (!permissionGranted) {
                                // No logging - just wait and retry
                                delay(2000) // Check every 2 seconds if permission not granted
                                continue
                            }

                            // Get current app - must run on main thread for getSystemService
                            val currentApp =
                                    try {
                                        withContext(Dispatchers.Main.immediate) {
                                            // Capture context reference before switching threads
                                            val ctx =
                                                    this@AppFocusPlugin.context
                                                            ?: return@withContext null

                                            if (Build.VERSION.SDK_INT >=
                                                            Build.VERSION_CODES.LOLLIPOP
                                            ) {
                                                // Ensure we're on main thread before calling
                                                // getSystemService
                                                val usageStatsManager =
                                                        ctx.getSystemService(
                                                                Context.USAGE_STATS_SERVICE
                                                        ) as
                                                                UsageStatsManager
                                                val time = System.currentTimeMillis()
                                                val stats =
                                                        usageStatsManager.queryUsageStats(
                                                                UsageStatsManager.INTERVAL_BEST,
                                                                time - TimeUnit.SECONDS.toMillis(5),
                                                                time
                                                        )
                                                if (stats.isNotEmpty()) {
                                                    stats
                                                            .maxByOrNull { it.lastTimeUsed }
                                                            ?.packageName
                                                } else null
                                            } else null
                                        }
                                    } catch (e: CancellationException) {
                                        // Coroutine was cancelled - rethrow to stop the loop
                                        throw e
                                    } catch (e: Exception) {
                                        // Log error for debugging
                                        android.util.Log.e(
                                                "AppFocusPlugin",
                                                "Error getting current app: ${e.message}",
                                                e
                                        )
                                        null
                                    }

                            if (currentApp != null) {
                                // Check if this is a new app (different from last known app)
                                val isNewApp = currentApp != lastAppPackage

                                // android.util.Log.d(
                                //         "AppFocusPlugin",
                                //         "Current app: '$currentApp', lastApp: '$lastAppPackage', isNewApp: $isNewApp, eventSink: ${if (eventSink != null) "not null" else "NULL"}"
                                // )

                                if (isNewApp) {
                                    // This is a real app switch
                                    val previousApp = lastAppPackage
                                    lastAppPackage = currentApp
                                    android.util.Log.d(
                                            "AppFocusPlugin",
                                            "🔄 App switched from '$previousApp' to '$currentApp'"
                                    )
                                    if (eventSink != null) {
                                        try {
                                            eventSink?.success(currentApp)
                                            android.util.Log.d(
                                                    "AppFocusPlugin",
                                                    "✅ Event sent to Flutter: $currentApp"
                                            )
                                        } catch (e: Exception) {
                                            android.util.Log.e(
                                                    "AppFocusPlugin",
                                                    "❌ Error sending event to Flutter: ${e.message}",
                                                    e
                                            )
                                        }
                                    } else {
                                        android.util.Log.w(
                                                "AppFocusPlugin",
                                                "⚠️ Event sink is null, cannot send event"
                                        )
                                    }
                                } else if (lastAppPackage == null) {
                                    // First run - send initial app
                                    lastAppPackage = currentApp
                                    android.util.Log.d(
                                            "AppFocusPlugin",
                                            "Initial app detected: $currentApp"
                                    )
                                    if (eventSink != null) {
                                        try {
                                            eventSink?.success(currentApp)
                                            android.util.Log.d(
                                                    "AppFocusPlugin",
                                                    "✅ Initial app event sent to Flutter: $currentApp"
                                            )
                                        } catch (e: Exception) {
                                            android.util.Log.e(
                                                    "AppFocusPlugin",
                                                    "❌ Error sending initial app event: ${e.message}",
                                                    e
                                            )
                                        }
                                    } else {
                                        android.util.Log.w(
                                                "AppFocusPlugin",
                                                "⚠️ Event sink is null for initial app"
                                        )
                                    }
                                } else {
                                    // Same app - no switch needed
                                    android.util.Log.d(
                                            "AppFocusPlugin",
                                            "Same app '$currentApp' - no switch event"
                                    )
                                }
                            } else {
                                // Log occasionally if we can't get current app
                                if (System.currentTimeMillis() % 10000 < 1000) {
                                    android.util.Log.d(
                                            "AppFocusPlugin",
                                            "Could not get current app (might be normal if no recent activity)"
                                    )
                                }
                            }
                        } catch (e: CancellationException) {
                            // Coroutine was cancelled - exit the loop
                            android.util.Log.d("AppFocusPlugin", "Tracking cancelled")
                            break
                        } catch (e: Exception) {
                            // Permission might have been revoked or other error
                            // Don't send error events - just wait and retry
                            // Sending errors can cause the EventChannel stream to close
                            if (e is SecurityException) {
                                // Permission revoked - wait and retry
                                delay(2000)
                                continue
                            } else {
                                // Other error - wait a bit and retry
                                delay(1000)
                            }
                        }
                        delay(1000) // Check every second
                    }
                }
    }

    private fun hasUsageStatsPermission(): Boolean {
        val context = this.context ?: return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            try {
                val usageStatsManager =
                        context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
                val time = System.currentTimeMillis()

                // Try querying with multiple time ranges to be more reliable
                // INTERVAL_BEST might return empty even with permission if there's no recent
                // activity

                // First, try a short range (last minute)
                var stats =
                        usageStatsManager.queryUsageStats(
                                UsageStatsManager.INTERVAL_BEST,
                                time - TimeUnit.MINUTES.toMillis(1),
                                time
                        )

                // If empty, try a longer range (last hour)
                if (stats == null || stats.isEmpty()) {
                    stats =
                            usageStatsManager.queryUsageStats(
                                    UsageStatsManager.INTERVAL_DAILY,
                                    time - TimeUnit.HOURS.toMillis(1),
                                    time
                            )
                }

                // If still empty, try querying all apps (this should work if permission is granted)
                if (stats == null || stats.isEmpty()) {
                    stats =
                            usageStatsManager.queryUsageStats(
                                    UsageStatsManager.INTERVAL_BEST,
                                    time - TimeUnit.DAYS.toMillis(1), // Last 24 hours
                                    time
                            )
                }

                // The key insight: queryUsageStats() returns an empty list (not null) when
                // permission is denied
                // So we can't rely on null checks. Instead, we need to check if we can actually get
                // results
                // from a reasonable time range. If we query 24 hours and get nothing, it's likely
                // no permission.
                // But if we get ANY results, permission is definitely granted.

                val hasResults = stats != null && stats.isNotEmpty()

                if (hasResults) {
                    // Don't log here - let the caller log on state change
                    return true
                } else {
                    // Empty results could mean:
                    // 1. Permission denied (most likely)
                    // 2. Permission granted but no app activity in the time range (unlikely for 24h
                    // range)
                    //
                    // Since we queried up to 24 hours, if we get nothing, it's very likely
                    // permission is denied
                    // However, to be safe, let's also try querying the current app's own usage
                    // If we can see our own app's stats, permission is definitely granted
                    try {
                        val ownPackageName = context.packageName
                        val ownStats =
                                usageStatsManager.queryUsageStats(
                                                UsageStatsManager.INTERVAL_BEST,
                                                time - TimeUnit.DAYS.toMillis(7), // Last week
                                                time
                                        )
                                        ?.firstOrNull { it.packageName == ownPackageName }

                        if (ownStats != null) {
                            // Don't log here - let the caller log on state change
                            return true
                        }
                    } catch (e: Exception) {
                        // Ignore - just means we can't check own stats
                    }

                    // Don't log here - let the caller log on state change
                    return false
                }
            } catch (e: SecurityException) {
                // No logging - silently return false
                return false
            } catch (e: Exception) {
                // No logging - silently return false
                return false
            }
        }
        return false
    }

    private fun stopTracking() {
        job?.cancel()
        job = null
        lastAppPackage = null
        permissionGrantedState = false // Reset state when stopping
    }

    private fun getCurrentAppPackage(): String? {
        val context = this.context ?: return null

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            try {
                val usageStatsManager =
                        context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
                val time = System.currentTimeMillis()
                val stats =
                        usageStatsManager.queryUsageStats(
                                UsageStatsManager.INTERVAL_BEST,
                                time - TimeUnit.SECONDS.toMillis(5),
                                time
                        )

                if (stats.isNotEmpty()) {
                    val mostRecentStats = stats.maxByOrNull { it.lastTimeUsed }
                    return mostRecentStats?.packageName
                }
            } catch (e: Exception) {
                // UsageStatsManager failed - no fallback needed
                // getRunningTasks() is deprecated and requires UI thread, so we skip it
            }
        }

        // No fallback - UsageStatsManager is the only reliable method
        // getRunningTasks() is deprecated and causes threading issues
        return null
    }
}
