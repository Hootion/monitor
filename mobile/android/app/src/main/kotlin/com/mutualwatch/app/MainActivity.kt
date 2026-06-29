package com.mutualwatch.app

import android.Manifest
import android.app.AppOpsManager
import android.app.usage.NetworkStats
import android.app.usage.NetworkStatsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.bluetooth.BluetoothAdapter
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.media.AudioManager
import android.net.ConnectivityManager
import android.net.Uri
import android.net.NetworkCapabilities
import android.net.TrafficStats
import android.net.wifi.WifiManager
import android.location.LocationManager
import android.os.BatteryManager
import android.os.Build
import android.os.Environment
import android.os.StatFs
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.time.LocalDate
import java.time.ZoneId

class MainActivity : FlutterActivity() {
    private val channelName = "app.mutual_watch/device"
    private val appNameCache = mutableMapOf<String, String>()

    private data class NetworkInfo(
        val type: String,
        val name: String?,
        val speedKbps: Int?
    )

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "hasUsageAccess" -> result.success(hasUsageAccess())
                    "openUsageAccessSettings" -> {
                        startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
                        result.success(null)
                    }
                    "openAppSettings" -> {
                        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                            data = Uri.parse("package:$packageName")
                        }
                        startActivity(intent)
                        result.success(null)
                    }
                    "openUrl" -> {
                        val url = call.argument<String>("url")
                        if (url.isNullOrBlank()) {
                            result.error("invalid_url", "URL is required", null)
                        } else {
                            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                            result.success(null)
                        }
                    }
                    "startForegroundCollection" -> {
                        val intent = Intent(this, TelemetryForegroundService::class.java).apply {
                            putExtra("apiBaseUrl", call.argument<String>("apiBaseUrl"))
                            putExtra("accessToken", call.argument<String>("accessToken"))
                            putExtra("refreshToken", call.argument<String>("refreshToken"))
                        }
                        runCatching {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                startForegroundService(intent)
                            } else {
                                startService(intent)
                            }
                        }
                        result.success(null)
                    }
                    "getDeviceSnapshot" -> result.success(deviceSnapshot())
                    "getLocationSnapshot" -> result.success(locationSnapshot())
                    "getTodayUsageReport" -> result.success(todayUsageReport())
                    "getAppUsage" -> result.success(appUsageSessions())
                    "getRecentEvents" -> result.success(recentEvents())
                    else -> result.notImplemented()
                }
            } catch (exception: Exception) {
                result.error("native_error", exception.message, null)
            }
        }
    }

    private fun hasUsageAccess(): Boolean {
        val appOps = getSystemService(AppOpsManager::class.java)
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, android.os.Process.myUid(), packageName)
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, android.os.Process.myUid(), packageName)
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun deviceSnapshot(): Map<String, Any?> {
        val battery = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = battery?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = battery?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
        val status = battery?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val batteryPercent = if (level >= 0 && scale > 0) (level * 100 / scale) else null
        val audio = getSystemService(AudioManager::class.java)
        val maxVolume = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        val volume = if (maxVolume > 0) audio.getStreamVolume(AudioManager.STREAM_MUSIC) * 100 / maxVolume else null
        val storage = StatFs(Environment.getDataDirectory().path)
        val totalBytes = storage.blockSizeLong * storage.blockCountLong
        val availableBytes = storage.blockSizeLong * storage.availableBlocksLong
        val network = networkInfo()
        val traffic = todayTraffic()
        val unsupported = mutableListOf<String>()
        if (traffic.first == null) unsupported.add("wifi_daily_traffic_requires_network_stats_access")
        if (traffic.second == null) unsupported.add("mobile_daily_traffic_requires_network_stats_access")

        return mapOf(
            "platform" to "android",
            "capturedAt" to isoNow(),
            "wifiBytesToday" to traffic.first,
            "mobileBytesToday" to traffic.second,
            "networkSpeedKbps" to network.speedKbps,
            "networkType" to network.type,
            "networkName" to network.name,
            "bluetoothState" to bluetoothState(),
            "volumePercent" to volume,
            "batteryPercent" to batteryPercent,
            "batteryCharging" to (status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL),
            "model" to "${Build.MANUFACTURER} ${Build.MODEL}",
            "osVersion" to "Android ${Build.VERSION.RELEASE}",
            "storageUsedBytes" to totalBytes - availableBytes,
            "storageTotalBytes" to totalBytes,
            "unsupported" to unsupported
        )
    }

    private fun networkInfo(): NetworkInfo {
        val connectivity = getSystemService(ConnectivityManager::class.java)
        val capabilities = connectivity.getNetworkCapabilities(connectivity.activeNetwork) ?: return NetworkInfo("offline", null, null)
        val type = when {
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "cellular"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_BLUETOOTH) -> "bluetooth"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
            else -> "unknown"
        }
        val name = if (type == "wifi") wifiNetworkName() else null
        return NetworkInfo(type, name, capabilities.linkDownstreamBandwidthKbps)
    }

    private fun wifiNetworkName(): String {
        if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            return "unauthorized"
        }
        val wifi = applicationContext.getSystemService(WifiManager::class.java) ?: return "unsupported"
        val ssid = wifi.connectionInfo?.ssid
            ?.trim()
            ?.trim('"')
            ?.takeIf { it.isNotEmpty() && it != "<unknown ssid>" && !it.startsWith("0x") }
        return ssid ?: "unknown"
    }

    private fun locationSnapshot(): Map<String, Any?> {
        if (!hasLocationPermission()) {
            return locationStatus("unauthorized")
        }
        return runCatching {
            val locationManager = getSystemService(LocationManager::class.java)
            val providers = locationManager.getProviders(true)
            if (providers.isEmpty()) {
                locationStatus("disabled")
            } else {
                val location = providers.mapNotNull { provider ->
                    runCatching { locationManager.getLastKnownLocation(provider) }.getOrNull()
                }.maxByOrNull { it.time }
                if (location == null) {
                    locationStatus("unavailable")
                } else {
                    mapOf(
                        "platform" to "android",
                        "capturedAt" to isoFromMillis(location.time),
                        "status" to "available",
                        "latitude" to location.latitude,
                        "longitude" to location.longitude,
                        "accuracyMeters" to if (location.hasAccuracy()) location.accuracy.toDouble() else null
                    )
                }
            }
        }.getOrElse {
            locationStatus("unknown")
        }
    }

    private fun locationStatus(status: String): Map<String, Any?> {
        return mapOf(
            "platform" to "android",
            "capturedAt" to isoNow(),
            "status" to status
        )
    }

    private fun hasLocationPermission(): Boolean {
        return checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
            checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
    }

    private fun bluetoothState(): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED
        ) {
            return "unauthorized"
        }
        return runCatching {
            val adapter = BluetoothAdapter.getDefaultAdapter() ?: return "unsupported"
            if (adapter.isEnabled) "on" else "off"
        }.getOrDefault("unknown")
    }

    private fun todayTraffic(): Pair<Long?, Long?> {
        val start = LocalDate.now().atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli()
        val end = System.currentTimeMillis()
        val stats = getSystemService(NetworkStatsManager::class.java)
        val wifi = runCatching {
            stats.querySummaryForDevice(ConnectivityManager.TYPE_WIFI, "", start, end).totalBytes()
        }.getOrNull()
        val mobile = runCatching {
            stats.querySummaryForDevice(ConnectivityManager.TYPE_MOBILE, "", start, end).totalBytes()
        }.getOrNull()
        if (wifi == null && mobile == null) {
            val total = TrafficStats.getTotalRxBytes() + TrafficStats.getTotalTxBytes()
            return Pair(total.takeIf { it >= 0 }, null)
        }
        return Pair(wifi, mobile)
    }

    private fun NetworkStats.Bucket.totalBytes(): Long = rxBytes + txBytes

    private fun todayUsageReport(): Map<String, Any?> {
        val sessions = appUsageSessions()
        val total = sessions.sumOf { it["durationMs"] as Long }
        val first = sessions.minByOrNull { it["startedAt"].toString() }?.get("startedAt") as String?
        val longest = sessions.maxOfOrNull { it["durationMs"] as Long } ?: 0L
        val date = LocalDate.now().toString()
        return mapOf(
            "date" to date,
            "platform" to "android",
            "screenTimeMs" to total,
            "pickupCount" to sessions.size,
            "firstUseAt" to first,
            "longestContinuousMs" to longest,
            "unsupported" to if (hasUsageAccess()) emptyList<String>() else listOf("usage_access_not_granted")
        )
    }

    private fun appUsageSessions(): List<Map<String, Any?>> {
        if (!hasUsageAccess()) return emptyList()
        val start = LocalDate.now().atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli()
        val end = System.currentTimeMillis()
        val usage = getSystemService(UsageStatsManager::class.java)
        val events = usage.queryEvents(start, end)
        val event = UsageEvents.Event()
        val active = mutableMapOf<String, Long>()
        val sessions = mutableListOf<Map<String, Any?>>()
        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            val packageName = event.packageName ?: continue
            when (event.eventType) {
                UsageEvents.Event.MOVE_TO_FOREGROUND,
                UsageEvents.Event.ACTIVITY_RESUMED -> {
                    active[packageName] = event.timeStamp
                }
                UsageEvents.Event.MOVE_TO_BACKGROUND,
                UsageEvents.Event.ACTIVITY_PAUSED,
                UsageEvents.Event.ACTIVITY_STOPPED -> {
                    val startedAt = active.remove(packageName) ?: continue
                    val duration = event.timeStamp - startedAt
                    if (duration > 0) {
                        sessions.add(sessionMap(packageName, startedAt, event.timeStamp, duration))
                    }
                }
            }
        }
        for ((packageName, startedAt) in active) {
            val duration = end - startedAt
            if (duration > 0) {
                sessions.add(sessionMap(packageName, startedAt, end, duration))
            }
        }
        return sessions
            .sortedByDescending { it["durationMs"] as Long }
            .take(120)
    }

    private fun sessionMap(packageName: String, startedAt: Long, endedAt: Long, duration: Long): Map<String, Any?> {
        return mapOf(
            "platform" to "android",
            "packageName" to packageName,
            "appName" to appName(packageName),
            "clientSessionId" to "app_usage:$packageName:$startedAt",
            "startedAt" to isoFromMillis(startedAt),
            "endedAt" to isoFromMillis(endedAt),
            "durationMs" to duration,
            "openCount" to 1
        )
    }

    private fun recentEvents(): List<Map<String, Any?>> {
        val systemEvents = EventLogStore.recent(this, 100)
        if (!hasUsageAccess()) return systemEvents
        val start = LocalDate.now().atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli()
        val end = System.currentTimeMillis()
        val usage = getSystemService(UsageStatsManager::class.java)
        val events = usage.queryEvents(start, end)
        val event = UsageEvents.Event()
        val appEvents = mutableListOf<Map<String, Any?>>()
        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            val packageName = event.packageName ?: continue
            if (event.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND ||
                event.eventType == UsageEvents.Event.ACTIVITY_RESUMED
            ) {
                appEvents.add(
                    mapOf(
                        "clientEventId" to "app_opened:$packageName:${event.timeStamp}",
                        "type" to "app_opened",
                        "occurredAt" to isoFromMillis(event.timeStamp),
                        "platform" to "android",
                        "details" to mapOf("packageName" to packageName, "appName" to appName(packageName))
                    )
                )
            }
        }
        return (systemEvents + appEvents)
            .sortedByDescending { it["occurredAt"].toString() }
            .take(120)
    }

    private fun appName(packageName: String): String {
        appNameCache[packageName]?.let { return it }
        val label = runCatching {
            val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packageManager.getApplicationInfo(packageName, PackageManager.ApplicationInfoFlags.of(0))
            } else {
                @Suppress("DEPRECATION")
                packageManager.getApplicationInfo(packageName, 0)
            }
            packageManager.getApplicationLabel(info).toString()
                .trim()
                .takeIf { it.isNotEmpty() }
                ?: packageName
        }.getOrDefault(packageName)
        appNameCache[packageName] = label
        return label
    }
}
