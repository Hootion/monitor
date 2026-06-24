package com.mutualwatch.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.ConnectivityManager
import android.net.Network
import android.os.Build
import android.os.IBinder
import android.telephony.PhoneStateListener
import android.telephony.TelephonyCallback
import android.telephony.TelephonyManager

class TelemetryForegroundService : Service() {
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

    private var legacyPhoneListener: PhoneStateListener? = null
    private var phoneCallback: TelephonyCallback? = null
    private var callActive = false

    override fun onCreate() {
        super.onCreate()
        startForeground(18, notification())
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
    }

    override fun onDestroy() {
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
            .setContentText("状态共享正在运行")
            .setOngoing(true)
            .setSmallIcon(android.R.drawable.ic_menu_view)
            .build()
    }

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
}
