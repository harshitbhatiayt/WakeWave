package com.harshitbhatia.alarm101

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject

/**
 * Keeps one exact AlarmManager alarm per ring (alarm X on date Y). The list is
 * persisted so it can be restored after a reboot.
 */
object AlarmScheduler {
    const val EXTRA_ID = "ringId"
    const val EXTRA_TITLE = "title"
    const val EXTRA_ARTIST = "artist"
    const val EXTRA_SOUND = "sound"
    const val EXTRA_URL = "url"
    const val EXTRA_ART = "art"
    const val EXTRA_HOOK = "hook"

    fun prefs(ctx: Context): SharedPreferences =
        ctx.getSharedPreferences("alarm101", Context.MODE_PRIVATE)

    fun sync(ctx: Context, items: List<Map<String, Any?>>) {
        val arr = JSONArray()
        for (m in items) {
            arr.put(JSONObject().apply {
                put("id", m["id"]); put("at", (m["at"] as Number).toLong())
                put("sound", m["sound"]); put("title", m["title"])
                put("artist", m["artist"]); put("url", m["url"])
                put("art", m["art"] ?: "")
                put("hook", (m["hook"] as Number?)?.toDouble() ?: 0.0)
            })
        }
        apply(ctx, arr)
        // Cache posters now so the ring screen has them even offline.
        Art.prefetch(ctx, (0 until arr.length()).map { arr.getJSONObject(it).optString("art") })
    }

    /** Re-registers the stored list (after boot / app update). */
    fun restore(ctx: Context) {
        val arr = JSONArray(prefs(ctx).getString("items", "[]"))
        apply(ctx, arr)
    }

    private fun apply(ctx: Context, arr: JSONArray) {
        val am = ctx.getSystemService(AlarmManager::class.java)
        val p = prefs(ctx)

        // Cancel everything set last time.
        val old = JSONArray(p.getString("items", "[]"))
        for (i in 0 until old.length()) {
            am.cancel(pending(ctx, old.getJSONObject(i)))
        }

        val now = System.currentTimeMillis()
        val kept = JSONArray()
        for (i in 0 until arr.length()) {
            val o = arr.getJSONObject(i)
            if (o.getLong("at") <= now) continue
            val show = PendingIntent.getActivity(
                ctx, o.getString("id").hashCode(),
                Intent(ctx, MainActivity::class.java),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            try {
                am.setAlarmClock(AlarmManager.AlarmClockInfo(o.getLong("at"), show), pending(ctx, o))
                kept.put(o)
            } catch (e: SecurityException) {
                // Exact alarm permission missing; the app shows a banner.
            }
        }
        p.edit().putString("items", kept.toString()).apply()
    }

    private fun pending(ctx: Context, o: JSONObject): PendingIntent {
        val intent = Intent(ctx, AlarmReceiver::class.java).apply {
            action = "com.harshitbhatia.alarm101.RING"
            putExtra(EXTRA_ID, o.getString("id"))
            putExtra(EXTRA_TITLE, o.optString("title"))
            putExtra(EXTRA_ARTIST, o.optString("artist"))
            putExtra(EXTRA_SOUND, o.optString("sound"))
            putExtra(EXTRA_URL, o.optString("url"))
            putExtra(EXTRA_ART, o.optString("art"))
            putExtra(EXTRA_HOOK, o.optDouble("hook", 0.0))
        }
        return PendingIntent.getBroadcast(
            ctx, o.getString("id").hashCode(), intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
    }
}
