package com.harshitbhatia.alarm101

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import kotlin.concurrent.thread

/** Song posters cached on disk, so the ring screen can show them offline. */
object Art {
    private fun file(ctx: Context, url: String) =
        File(File(ctx.cacheDir, "art").apply { mkdirs() }, "${url.hashCode().toUInt()}.jpg")

    private fun fetch(ctx: Context, url: String): File? {
        val f = file(ctx, url)
        if (f.length() > 0) return f
        return try {
            val c = URL(url).openConnection() as HttpURLConnection
            c.connectTimeout = 4000
            c.readTimeout = 6000
            val tmp = File(f.path + ".part")
            c.inputStream.use { i -> tmp.outputStream().use { i.copyTo(it) } }
            tmp.renameTo(f)
            f
        } catch (e: Exception) {
            null
        }
    }

    fun prefetch(ctx: Context, urls: List<String>) {
        val todo = urls.filter { it.startsWith("http") }.distinct()
        if (todo.isEmpty()) return
        val app = ctx.applicationContext
        thread {
            todo.forEach { fetch(app, it) }
            // Drop posters no ring uses any more.
            val keep = todo.map { file(app, it).name }.toSet()
            File(app.cacheDir, "art").listFiles()?.filter { it.name !in keep }?.forEach { it.delete() }
        }
    }

    /** Loads the poster for [url] off the main thread; [done] gets null when unavailable. */
    fun load(ctx: Context, url: String?, done: (Bitmap?) -> Unit) {
        val main = Handler(Looper.getMainLooper())
        if (url.isNullOrEmpty() || !url.startsWith("http")) {
            done(null); return
        }
        thread {
            val bmp = fetch(ctx.applicationContext, url)?.let { BitmapFactory.decodeFile(it.path) }
            main.post { done(bmp) }
        }
    }
}
