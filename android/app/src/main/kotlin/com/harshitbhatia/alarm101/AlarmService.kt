package com.harshitbhatia.alarm101

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager

/** Plays the ring's song (looped) and shows the alarm screen. */
class AlarmService : Service() {
    companion object {
        const val ACTION_STOP = "com.harshitbhatia.alarm101.STOP"
        const val ACTION_FULL = "com.harshitbhatia.alarm101.FULL"
        private const val CHANNEL = "alarm"
        private const val NOTIF_ID = 101
        private const val MAX_RING_MS = 10 * 60 * 1000L

        /** The ring currently sounding, for AlarmActivity. */
        var current: Intent? = null
    }

    private var player: MediaPlayer? = null
    private var wake: PowerManager.WakeLock? = null
    private val handler = Handler(Looper.getMainLooper())

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopRinging(); return START_NOT_STICKY
            }
            ACTION_FULL -> {
                val ring = current
                stopRinging()
                // Hand over to WakeWave, which opens the chosen music app.
                startActivity(
                    Intent(this, MainActivity::class.java)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                        .putExtra(AlarmScheduler.EXTRA_ID, ring?.getStringExtra(AlarmScheduler.EXTRA_ID))
                )
                return START_NOT_STICKY
            }
        }
        if (intent == null) {
            stopSelf(); return START_NOT_STICKY
        }

        current = intent
        startForegroundCompat(buildNotification(intent))
        // When the phone is unlocked Android shows the full-screen intent only as a
        // banner; try opening the alarm page directly too (allowed on some OEM builds).
        try {
            startActivity(Intent(this, AlarmActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        } catch (_: Exception) {
        }
        wake =getSystemService(PowerManager::class.java)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "alarm101:ring")
            .apply { acquire(MAX_RING_MS) }
        play(intent.getStringExtra(AlarmScheduler.EXTRA_SOUND),
            intent.getDoubleExtra(AlarmScheduler.EXTRA_HOOK, 0.0))
        handler.postDelayed({ stopRinging() }, MAX_RING_MS)
        return START_NOT_STICKY
    }

    /** Loops the preview, starting at its punchiest part ([hook] seconds). */
    private fun play(path: String?, hook: Double) {
        player?.release()
        val attrs = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
            .build()
        player = try {
            MediaPlayer().apply {
                setAudioAttributes(attrs)
                setDataSource(path)
                isLooping = true
                prepare()
                seekTo((hook * 1000).toInt())
                start()
            }
        } catch (e: Exception) {
            // Song file missing: fall back to the system alarm tone.
            MediaPlayer().apply {
                setAudioAttributes(attrs)
                setDataSource(this@AlarmService, RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM))
                isLooping = true
                prepare()
                start()
            }
        }
    }

    private fun buildNotification(ring: Intent): Notification {
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL, "Alarms", NotificationManager.IMPORTANCE_HIGH).apply {
                setSound(null, null)
                setBypassDnd(true)
            }
        )
        val flags = PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        val screen = PendingIntent.getActivity(
            this, 0, Intent(this, AlarmActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK), flags
        )
        val stop = PendingIntent.getService(this, 1, Intent(this, AlarmService::class.java).setAction(ACTION_STOP), flags)
        val full = PendingIntent.getService(this, 2, Intent(this, AlarmService::class.java).setAction(ACTION_FULL), flags)
        return Notification.Builder(this, CHANNEL)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle("🎵 ${ring.getStringExtra(AlarmScheduler.EXTRA_TITLE)}")
            .setContentText(ring.getStringExtra(AlarmScheduler.EXTRA_ARTIST))
            .setCategory(Notification.CATEGORY_ALARM)
            .setOngoing(true)
            .setFullScreenIntent(screen, true)
            .setContentIntent(screen)
            .addAction(Notification.Action.Builder(null, "Stop", stop).build())
            .addAction(Notification.Action.Builder(null, "Full Song", full).build())
            .build()
    }

    private fun startForegroundCompat(n: Notification) {
        if (android.os.Build.VERSION.SDK_INT >= 29) {
            startForeground(NOTIF_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
        } else {
            startForeground(NOTIF_ID, n)
        }
    }

    private fun stopRinging() {
        handler.removeCallbacksAndMessages(null)
        player?.release()
        player = null
        wake?.let { if (it.isHeld) it.release() }
        wake = null
        current = null
        sendBroadcast(Intent(AlarmActivity.ACTION_CLOSE).setPackage(packageName))
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        player?.release()
        super.onDestroy()
    }
}
