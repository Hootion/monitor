package com.mutualwatch.app

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.app.usage.NetworkStats
import android.app.usage.NetworkStatsManager
import android.bluetooth.BluetoothAdapter
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.media.AudioManager
import android.content.pm.ServiceInfo
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.TrafficStats
import android.net.wifi.WifiManager
import android.os.BatteryManager
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.StatFs
import android.telephony.PhoneStateListener
import android.telephony.TelephonyCallback
import android.telephony.TelephonyManager
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.time.LocalDate
import java.time.ZoneId

class TelemetryForegroundService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private var latestLocation: Location? = null
    private var apiBaseUrl: String? = null
    private var accessToken: String? = null
    private var refreshToken: String? = null
    @Volatile private var lastDeviceSnapshotUploadAt = 0L

    private data class NetworkInfo(
        val type: String,
        val name: String?,
        val speedKbps: Int?
    )

    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                Intent.ACTION_SCREEN_ON -> EventLogStore.record(context, "screen_on")
                Intent.ACTION_SCREEN_OFF -> EventLogStore.record(context, "screen_off")
            }
        }
    }

    private val networkCallback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
            EventLogStore.record(this@TelemetryForegroundService, "network_connected")
        }

        override fun onLost(network: Network) {
            EventLogStore.record(this@TelemetryForegroundService, "network_disconnected")
        }
    }

    private val locationListener = object : LocationListener {
        override fun onLocationChanged(location: Location) {
            if (location.isBetterThan(latestLocation)) {
                latestLocation = location
            }
        }

        @Deprecated("Deprecated by Android")
        override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) = Unit

        override fun onProviderEnabled(provider: String) = Unit

        override fun onProviderDisabled(provider: String) = Unit
    }

    private val uploadRunnable = object : Runnable {
        override fun run() {
            uploadTelemetrySnapshot()
            handler.postDelayed(this, LOCATION_UPLOAD_INTERVAL_MS)
        }
    }

    private var legacyPhoneListener: PhoneStateListener? = null
    private var phoneCallback: TelephonyCallback? = null
    private var callActive = false

    override fun onCreate() {
        super.onCreate()
        startForegroundCompat()
        val screenFilter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_SCREEN_OFF)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(screenReceiver, screenFilter, RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            registerReceiver(screenReceiver, screenFilter)
        }
        runCatching { getSystemService(ConnectivityManager::class.java)?.registerDefaultNetworkCallback(networkCallback) }
        runCatching { registerPhoneCallbacks() }
        runCatching { startLocationUpdates() }
        scheduleLocationUpload(immediate = false)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        updateAuth(intent)
        runCatching { startLocationUpdates() }
        scheduleLocationUpload(immediate = true)
        return START_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacks(uploadRunnable)
        runCatching { stopLocationUpdates() }
        runCatching { unregisterReceiver(screenReceiver) }
        runCatching { getSystemService(ConnectivityManager::class.java)?.unregisterNetworkCallback(networkCallback) }
        unregisterPhoneCallbacks()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun notification(): Notification {
        val channelId = "mutual_watch_collection"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(
                NotificationChannel(channelId, "Mutual Watch", NotificationManager.IMPORTANCE_LOW)
            )
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, channelId)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setContentTitle("Mutual Watch")
            .setContentText("Status sharing is running")
            .setOngoing(true)
            .setSmallIcon(android.R.drawable.ic_menu_view)
            .build()
    }

    private fun startForegroundCompat() {
        val notification = notification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val serviceTypes = ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC or
                if (hasLocationPermission()) ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION else 0
            runCatching {
                startForeground(18, notification, serviceTypes)
            }.onFailure {
                startForeground(18, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
            }
        } else {
            startForeground(18, notification)
        }
    }

    private fun scheduleLocationUpload(immediate: Boolean) {
        handler.removeCallbacks(uploadRunnable)
        handler.postDelayed(uploadRunnable, if (immediate) 5000L else LOCATION_UPLOAD_INTERVAL_MS)
    }

    private fun updateAuth(intent: Intent?) {
        val base = intent?.getStringExtra("apiBaseUrl")?.takeIf { it.isNotBlank() }
        val access = intent?.getStringExtra("accessToken")?.takeIf { it.isNotBlank() }
        val refresh = intent?.getStringExtra("refreshToken")?.takeIf { it.isNotBlank() }
        if (base != null) apiBaseUrl = base
        if (access != null) accessToken = access
        if (refresh != null) refreshToken = refresh
        nativePrefs().edit().apply {
            if (base != null) putString("apiBaseUrl", base)
            if (access != null) putString("accessToken", access)
            if (refresh != null) putString("refreshToken", refresh)
        }.apply()
    }

    private fun startLocationUpdates() {
        if (!hasLocationPermission() || !hasBackgroundLocationPermission()) {
            return
        }
        val manager = getSystemService(LocationManager::class.java) ?: return
        val providers = listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)
            .filter { provider -> runCatching { manager.isProviderEnabled(provider) }.getOrDefault(false) }
        latestLocation = (
            providers.mapNotNull { provider ->
                runCatching { manager.getLastKnownLocation(provider) }.getOrNull()
            } + listOfNotNull(latestLocation)
        ).bestAvailableLocation()
        for (provider in providers) {
            runCatching {
                manager.requestLocationUpdates(
                    provider,
                    LOCATION_UPDATE_INTERVAL_MS,
                    3f,
                    locationListener
                )
            }
        }
    }

    private fun stopLocationUpdates() {
        val manager = getSystemService(LocationManager::class.java) ?: return
        manager.removeUpdates(locationListener)
    }

    private fun hasLocationPermission(): Boolean {
        return checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
            checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
    }

    private fun hasBackgroundLocationPermission(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.Q ||
            checkSelfPermission(Manifest.permission.ACCESS_BACKGROUND_LOCATION) == PackageManager.PERMISSION_GRANTED
    }

    private fun uploadTelemetrySnapshot() {
        Thread {
            val baseUrl = currentApiBaseUrl() ?: return@Thread
            val token = currentAccessToken() ?: return@Thread
            val includeDeviceSnapshot = shouldUploadDeviceSnapshot()
            val bodyJson = JSONObject()
                .put("locationSnapshot", locationJson())
            if (includeDeviceSnapshot) {
                bodyJson.put("deviceSnapshot", deviceSnapshotJson())
            }
            val body = bodyJson.toString()
            val status = postJson("$baseUrl/telemetry/batch", token, body)
            var accepted = status in 200..299
            if (status == HttpURLConnection.HTTP_UNAUTHORIZED && refreshSession(baseUrl)) {
                currentAccessToken()?.let { refreshed ->
                    accepted = postJson("$baseUrl/telemetry/batch", refreshed, body) in 200..299
                }
            }
            if (accepted && includeDeviceSnapshot) {
                lastDeviceSnapshotUploadAt = System.currentTimeMillis()
            }
        }.start()
    }

    private fun shouldUploadDeviceSnapshot(): Boolean {
        val ageMs = System.currentTimeMillis() - lastDeviceSnapshotUploadAt
        return lastDeviceSnapshotUploadAt == 0L || ageMs >= DEVICE_SNAPSHOT_UPLOAD_INTERVAL_MS
    }

    private fun deviceSnapshotJson(): JSONObject {
        val battery = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = battery?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = battery?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
        val status = battery?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val batteryPercent = if (level >= 0 && scale > 0) (level * 100 / scale) else null
        val audio = getSystemService(AudioManager::class.java)
        val maxVolume = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        val volume = if (maxVolume > 0) {
            audio.getStreamVolume(AudioManager.STREAM_MUSIC) * 100 / maxVolume
        } else {
            null
        }
        val storage = StatFs(Environment.getDataDirectory().path)
        val totalBytes = storage.blockSizeLong * storage.blockCountLong
        val availableBytes = storage.blockSizeLong * storage.availableBlocksLong
        val network = networkInfo()
        val traffic = todayTraffic()
        val unsupported = mutableListOf<String>()
        if (traffic.first == null) unsupported.add("wifi_daily_traffic_requires_network_stats_access")
        if (traffic.second == null) unsupported.add("mobile_daily_traffic_requires_network_stats_access")

        return JSONObject()
            .put("platform", "android")
            .put("capturedAt", isoNow())
            .putNullable("wifiBytesToday", traffic.first)
            .putNullable("mobileBytesToday", traffic.second)
            .putNullable("networkSpeedKbps", network.speedKbps)
            .putNullable("networkType", network.type)
            .putNullable("networkName", network.name)
            .putNullable("bluetoothState", bluetoothState())
            .putNullable("volumePercent", volume)
            .putNullable("batteryPercent", batteryPercent)
            .put(
                "batteryCharging",
                status == BatteryManager.BATTERY_STATUS_CHARGING ||
                    status == BatteryManager.BATTERY_STATUS_FULL
            )
            .put("model", "${Build.MANUFACTURER} ${Build.MODEL}")
            .put("osVersion", "Android ${Build.VERSION.RELEASE}")
            .put("storageUsedBytes", totalBytes - availableBytes)
            .put("storageTotalBytes", totalBytes)
            .put("unsupported", JSONArray(unsupported))
    }

    private fun networkInfo(): NetworkInfo {
        val connectivity = getSystemService(ConnectivityManager::class.java)
        val capabilities = connectivity.getNetworkCapabilities(connectivity.activeNetwork)
            ?: return NetworkInfo("offline", null, null)
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
        val fallbackTotal = TrafficStats.getTotalRxBytes() + TrafficStats.getTotalTxBytes()
        val stats = getSystemService(NetworkStatsManager::class.java)
            ?: return Pair(fallbackTotal.takeIf { it >= 0 }, null)
        val start = LocalDate.now().atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli()
        val end = System.currentTimeMillis()
        val wifi = runCatching {
            stats.querySummaryForDevice(ConnectivityManager.TYPE_WIFI, "", start, end).totalBytes()
        }.getOrNull()
        val mobile = runCatching {
            stats.querySummaryForDevice(ConnectivityManager.TYPE_MOBILE, "", start, end).totalBytes()
        }.getOrNull()
        if (wifi == null && mobile == null) {
            return Pair(fallbackTotal.takeIf { it >= 0 }, null)
        }
        return Pair(wifi, mobile)
    }

    private fun NetworkStats.Bucket.totalBytes(): Long = rxBytes + txBytes

    private fun JSONObject.putNullable(name: String, value: Any?): JSONObject {
        put(name, value ?: JSONObject.NULL)
        return this
    }

    private fun locationJson(): JSONObject {
        if (!hasLocationPermission()) {
            return locationStatusJson("unauthorized")
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && !hasBackgroundLocationPermission()) {
            return locationStatusJson("unauthorized")
        }
        val location = latestLocation
        if (location == null) {
            return locationStatusJson("unavailable")
        }
        val coordinate = location.toAmapCoordinate()
        return JSONObject()
            .put("platform", "android")
            .put("capturedAt", isoFromMillis(location.time))
            .put("status", "available")
            .put("latitude", coordinate.latitude)
            .put("longitude", coordinate.longitude)
            .put("accuracyMeters", if (location.hasAccuracy()) location.accuracy.toDouble() else JSONObject.NULL)
    }

    private fun locationStatusJson(status: String): JSONObject {
        return JSONObject()
            .put("platform", "android")
            .put("capturedAt", isoNow())
            .put("status", status)
    }

    private fun postJson(url: String, token: String, body: String): Int {
        return runCatching {
            val connection = (URL(url).openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                connectTimeout = 12000
                readTimeout = 12000
                doOutput = true
                setRequestProperty("Authorization", "Bearer $token")
                setRequestProperty("Content-Type", "application/json")
            }
            connection.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
            val status = connection.responseCode
            readResponse(connection)
            connection.disconnect()
            status
        }.getOrDefault(-1)
    }

    private fun refreshSession(baseUrl: String): Boolean {
        val refresh = currentRefreshToken() ?: return false
        return runCatching {
            val connection = (URL("$baseUrl/auth/refresh").openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                connectTimeout = 12000
                readTimeout = 12000
                doOutput = true
                setRequestProperty("Content-Type", "application/json")
            }
            val body = JSONObject().put("refreshToken", refresh).toString()
            connection.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
            val response = readResponse(connection)
            val ok = connection.responseCode in 200..299
            connection.disconnect()
            if (!ok) return@runCatching false
            val json = JSONObject(response)
            val newAccess = json.optString("accessToken").takeIf { it.isNotBlank() } ?: return@runCatching false
            val newRefresh = json.optString("refreshToken").takeIf { it.isNotBlank() } ?: return@runCatching false
            accessToken = newAccess
            refreshToken = newRefresh
            nativePrefs().edit()
                .putString("accessToken", newAccess)
                .putString("refreshToken", newRefresh)
                .apply()
            flutterPrefs().edit()
                .putString("flutter.accessToken", newAccess)
                .putString("flutter.refreshToken", newRefresh)
                .apply()
            true
        }.getOrDefault(false)
    }

    private fun readResponse(connection: HttpURLConnection): String {
        val stream = if (connection.responseCode >= 400) connection.errorStream else connection.inputStream
        return stream?.bufferedReader(Charsets.UTF_8)?.use { it.readText() } ?: ""
    }

    private fun currentApiBaseUrl(): String? {
        return apiBaseUrl
            ?: nativePrefs().getString("apiBaseUrl", null)
    }

    private fun currentAccessToken(): String? {
        return accessToken
            ?: nativePrefs().getString("accessToken", null)
            ?: flutterPrefs().getString("flutter.accessToken", null)
    }

    private fun currentRefreshToken(): String? {
        return refreshToken
            ?: nativePrefs().getString("refreshToken", null)
            ?: flutterPrefs().getString("flutter.refreshToken", null)
    }

    private fun nativePrefs(): SharedPreferences =
        getSharedPreferences("MutualWatchNative", Context.MODE_PRIVATE)

    private fun flutterPrefs(): SharedPreferences =
        getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

    @Suppress("DEPRECATION")
    private fun registerPhoneCallbacks() {
        val telephony = getSystemService(TelephonyManager::class.java) ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val callback = object : TelephonyCallback(), TelephonyCallback.CallStateListener {
                override fun onCallStateChanged(state: Int) {
                    recordCallState(state)
                }
            }
            phoneCallback = callback
            telephony.registerTelephonyCallback(mainExecutor, callback)
        } else {
            val listener = object : PhoneStateListener() {
                override fun onCallStateChanged(state: Int, phoneNumber: String?) {
                    recordCallState(state)
                }
            }
            legacyPhoneListener = listener
            telephony.listen(listener, PhoneStateListener.LISTEN_CALL_STATE)
        }
    }

    @Suppress("DEPRECATION")
    private fun unregisterPhoneCallbacks() {
        val telephony = getSystemService(TelephonyManager::class.java) ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            phoneCallback?.let { telephony.unregisterTelephonyCallback(it) }
        } else {
            legacyPhoneListener?.let { telephony.listen(it, PhoneStateListener.LISTEN_NONE) }
        }
    }

    private fun recordCallState(state: Int) {
        when (state) {
            TelephonyManager.CALL_STATE_OFFHOOK, TelephonyManager.CALL_STATE_RINGING -> if (!callActive) {
                callActive = true
                EventLogStore.record(this, "call_started")
            }
            TelephonyManager.CALL_STATE_IDLE -> if (callActive) {
                callActive = false
                EventLogStore.record(this, "call_ended")
            }
        }
    }

    companion object {
        private const val LOCATION_UPDATE_INTERVAL_MS = 15_000L
        private const val LOCATION_UPLOAD_INTERVAL_MS = 30_000L
        private const val DEVICE_SNAPSHOT_UPLOAD_INTERVAL_MS = 5 * 60_000L
    }
}
