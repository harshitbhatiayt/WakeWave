package com.harshitbhatia.alarm101

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaPlayer
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/** Native side of lib/native.dart. */
class MainActivity : FlutterActivity() {
    private var player: MediaPlayer? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        rememberFired(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        rememberFired(intent)
    }

    /** Opened from the alarm screen's "Full Song" button. */
    private fun rememberFired(intent: Intent?) {
        val id = intent?.getStringExtra(AlarmScheduler.EXTRA_ID) ?: return
        AlarmScheduler.prefs(this).edit().putString("fired", id).apply()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "alarm101/native")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "paths" -> result.success(mapOf("docs" to filesDir.absolutePath))

                    "requestPermission" -> {
                        if (Build.VERSION.SDK_INT >= 33 &&
                            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                            PackageManager.PERMISSION_GRANTED
                        ) {
                            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
                        }
                        result.success(canAlarm())
                    }

                    "status" -> result.success(mapOf("alarms" to canAlarm()))

                    "analyze" -> {
                        val path = call.argument<String>("path")!!
                        Thread {
                            val r = try { Energy.analyze(path) } catch (e: Exception) { null }
                            runOnUiThread {
                                result.success(r?.let { mapOf("score" to it.score, "hook" to it.hook) })
                            }
                        }.start()
                    }

                    // Android plays the downloaded preview file directly (from the hook).
                    "prepareSound" -> result.success(call.argument<String>("src"))

                    "cleanSounds" -> result.success(null)

                    "syncAlarms" -> {
                        val items = call.argument<List<Map<String, Any?>>>("items") ?: emptyList()
                        AlarmScheduler.sync(this, items)
                        result.success(null)
                    }

                    "playPreview" -> {
                        player?.release()
                        player = MediaPlayer().apply {
                            setDataSource(call.argument<String>("path"))
                            prepare()
                            seekTo(((call.argument<Double>("start") ?: 0.0) * 1000).toInt())
                            start()
                        }
                        result.success(null)
                    }

                    "stopPreview" -> {
                        player?.release()
                        player = null
                        result.success(null)
                    }

                    "openUrl" -> {
                        try {
                            startActivity(
                                Intent(Intent.ACTION_VIEW, Uri.parse(call.argument<String>("url")))
                                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            )
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }

                    "consumeFired" -> {
                        val p = AlarmScheduler.prefs(this)
                        val id = p.getString("fired", null)
                        p.edit().remove("fired").apply()
                        result.success(id)
                    }

                    "openSettings" -> {
                        openPermissionSettings()
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    /** Exact alarms, notifications and the full-screen alarm page are all allowed. */
    private fun canAlarm(): Boolean {
        val am = getSystemService(AlarmManager::class.java)
        val nm = getSystemService(NotificationManager::class.java)
        val exact = Build.VERSION.SDK_INT < 31 || am.canScheduleExactAlarms()
        val full = Build.VERSION.SDK_INT < 34 || nm.canUseFullScreenIntent()
        return exact && full && nm.areNotificationsEnabled()
    }

    private fun openPermissionSettings() {
        val nm = getSystemService(NotificationManager::class.java)
        val intent = when {
            !nm.areNotificationsEnabled() ->
                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                    .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
            Build.VERSION.SDK_INT >= 34 && !nm.canUseFullScreenIntent() ->
                Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT, Uri.parse("package:$packageName"))
            else ->
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
        }
        startActivity(intent)
    }

    override fun onDestroy() {
        player?.release()
        super.onDestroy()
    }
}
