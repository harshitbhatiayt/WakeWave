package com.harshitbhatia.alarm101

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Fires at ring time (starts the ringing service) and restores alarms after boot. */
class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            "android.intent.action.TIME_SET",
            "android.intent.action.TIMEZONE_CHANGED" -> AlarmScheduler.restore(ctx)

            "com.harshitbhatia.alarm101.RING" -> {
                val service = Intent(ctx, AlarmService::class.java).putExtras(intent)
                ctx.startForegroundService(service)
            }
        }
    }
}
