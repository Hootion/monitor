package com.mutualwatch.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class DeviceEventReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED -> EventLogStore.record(context, "boot_completed")
            Intent.ACTION_SHUTDOWN -> EventLogStore.record(context, "shutdown_detected")
            Intent.ACTION_POWER_CONNECTED -> EventLogStore.record(context, "charge_started")
            Intent.ACTION_POWER_DISCONNECTED -> EventLogStore.record(context, "charge_ended")
        }
    }
}

