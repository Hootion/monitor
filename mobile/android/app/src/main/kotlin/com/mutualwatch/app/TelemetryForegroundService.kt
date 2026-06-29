package com.mutualwatch.app

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.net.ConnectivityManager
import android.net.Network
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.telephony.PhoneStateListener
import android.telephony.TelephonyCallback
import android.telephony.TelephonyManager
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

class TelemetryForegroundService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private var latestLocation: Location? = null
    private var apiBaseUrl: String? = null
    private var accessToken: String? = null
    private var refreshToken: String? = null

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
            latestLocation = location
        }

        @Deprecated("Deprecated by Android")
        override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) = Unit

        override fun onProviderEnabled(provider: String) = Unit

        override fun onProviderDisabled(provider: String) = Unit
    }

    private val uploadRunnable = object : Runnable {
        override fun run() {
            uploadLatestLocation()
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
        latestLocation = providers.mapNotNull { provider ->
            runCatching { manager.getLastKnownLocation(provider) }.getOrNull()
        }.maxByOrNull { it.time } ?: latestLocation
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

    private fun uploadLatestLocation() {
        val baseUrl = currentApiBaseUrl() ?: return
        val body = JSONObject().put("locationSnapshot", locationJson()).toString()
        Thread {
            val token = currentAccessToken() ?: return@Thread
            val status = postJson("$baseUrl/telemetry/batch", token, body)
            if (status == HttpURLConnection.HTTP_UNAUTHORIZED && refreshSession(baseUrl)) {
                currentAccessToken()?.let { refreshed ->
                    postJson("$baseUrl/telemetry/batch", refreshed, body)
                }
            }
        }.start()
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
        return JSONObject()
            .put("platform", "android")
            .put("capturedAt", isoFromMillis(location.time))
            .put("status", "available")
            .put("latitude", location.latitude)
            .put("longitude", location.longitude)
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
    }
}
