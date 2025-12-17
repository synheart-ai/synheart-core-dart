package com.synheart.hsi_flutter_example

import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val SETTINGS_CHANNEL = "com.synheart.hsi_flutter_example/settings"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(ScreenStatePlugin())
        flutterEngine.plugins.add(AppFocusPlugin())
        flutterEngine.plugins.add(NotificationPlugin())

        // Method channel for opening settings and checking permissions
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SETTINGS_CHANNEL)
                .setMethodCallHandler { call, result ->
                    when (call.method) {
                        "openUsageStatsSettings" -> {
                            openUsageStatsSettings()
                            result.success(null)
                        }
                        "openNotificationSettings" -> {
                            openNotificationSettings()
                            result.success(null)
                        }
                        "checkUsageStatsPermission" -> {
                            result.success(checkUsageStatsPermission())
                        }
                        "checkNotificationPermission" -> {
                            result.success(checkNotificationPermission())
                        }
                        else -> result.notImplemented()
                    }
                }
    }

    private fun openUsageStatsSettings() {
        val intent =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
                } else {
                    Intent(Settings.ACTION_SETTINGS)
                }
        startActivity(intent)
    }

    private fun openNotificationSettings() {
        val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
        startActivity(intent)
    }

    private fun checkUsageStatsPermission(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            try {
                val usageStatsManager =
                        getSystemService(Context.USAGE_STATS_SERVICE) as
                                android.app.usage.UsageStatsManager
                val time = System.currentTimeMillis()

                // Try querying with multiple time ranges to be more reliable
                // INTERVAL_BEST might return empty even with permission if there's no recent
                // activity

                // First, try a short range (last minute)
                var stats =
                        usageStatsManager.queryUsageStats(
                                android.app.usage.UsageStatsManager.INTERVAL_BEST,
                                time - java.util.concurrent.TimeUnit.MINUTES.toMillis(1),
                                time
                        )

                // If empty, try a longer range (last hour)
                if (stats == null || stats.isEmpty()) {
                    stats =
                            usageStatsManager.queryUsageStats(
                                    android.app.usage.UsageStatsManager.INTERVAL_DAILY,
                                    time - java.util.concurrent.TimeUnit.HOURS.toMillis(1),
                                    time
                            )
                }

                // If still empty, try querying all apps (this should work if permission is granted)
                if (stats == null || stats.isEmpty()) {
                    stats =
                            usageStatsManager.queryUsageStats(
                                    android.app.usage.UsageStatsManager.INTERVAL_BEST,
                                    time -
                                            java.util.concurrent.TimeUnit.DAYS.toMillis(
                                                    1
                                            ), // Last 24 hours
                                    time
                            )
                }

                val hasResults = stats != null && stats.isNotEmpty()

                if (hasResults) {
                    return true
                } else {
                    // Even with empty results, try checking own app's usage
                    try {
                        val ownPackageName = packageName
                        val ownStats =
                                usageStatsManager.queryUsageStats(
                                                android.app.usage.UsageStatsManager.INTERVAL_BEST,
                                                time -
                                                        java.util.concurrent.TimeUnit.DAYS.toMillis(
                                                                7
                                                        ), // Last week
                                                time
                                        )
                                        ?.firstOrNull { it.packageName == ownPackageName }

                        return ownStats != null
                    } catch (e: Exception) {
                        // Ignore - just means we can't check own stats
                    }

                    return false
                }
            } catch (e: SecurityException) {
                return false
            } catch (e: Exception) {
                return false
            }
        }
        return false
    }

    private fun checkNotificationPermission(): Boolean {
        val pkgName = packageName
        val flat = Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
        if (!android.text.TextUtils.isEmpty(flat)) {
            val names = flat.split(":").toTypedArray()
            for (name in names) {
                val componentName = android.content.ComponentName.unflattenFromString(name)
                if (componentName != null) {
                    if (android.text.TextUtils.equals(pkgName, componentName.packageName)) {
                        return true
                    }
                }
            }
        }
        return false
    }
}
