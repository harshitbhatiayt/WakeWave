package com.harshitbhatia.alarm101

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorFilter
import android.graphics.Outline
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.RenderEffect
import android.graphics.Shader
import android.graphics.Typeface
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.TextUtils
import android.text.format.DateFormat
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.ViewOutlineProvider
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import android.view.animation.AccelerateDecelerateInterpolator
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/**
 * Full-screen alarm page shown over the lock screen while a ring is sounding.
 * Same look as the app: dark canvas, blurred song poster, frosted glass.
 */
class AlarmActivity : Activity() {
    companion object {
        const val ACTION_CLOSE = "com.harshitbhatia.alarm101.CLOSE"
        private const val ORANGE = 0xFFFF8A1F.toInt()
        private const val PINK = 0xFFFF3B6B.toInt()
        private const val VIOLET = 0xFF7B5CFF.toInt()
        private const val INK = 0xFF07060B.toInt()
        private const val TEXT2 = 0x99FFFFFF.toInt()
        private const val TEXT3 = 0x66FFFFFF
    }

    private val closer = object : BroadcastReceiver() {
        override fun onReceive(c: Context?, i: Intent?) = finish()
    }
    private val ticker = Handler(Looper.getMainLooper())
    private val animators = mutableListOf<ValueAnimator>()
    private var dp = 1f

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setShowWhenLocked(true)
        setTurnScreenOn(true)
        if (Build.VERSION.SDK_INT >= 33) {
            registerReceiver(closer, IntentFilter(ACTION_CLOSE), RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(closer, IntentFilter(ACTION_CLOSE))
        }

        val ring = AlarmService.current
        if (ring == null) {
            finish(); return
        }
        dp = resources.displayMetrics.density

        val bg = FrameLayout(this).apply { setBackgroundColor(INK) }
        bg.addView(glows())
        val poster = ImageView(this).apply {
            scaleType = ImageView.ScaleType.CENTER_CROP
            alpha = 0f
            if (Build.VERSION.SDK_INT >= 31) {
                setRenderEffect(RenderEffect.createBlurEffect(60 * dp, 60 * dp, Shader.TileMode.CLAMP))
            }
        }
        bg.addView(poster, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        // Darken top and bottom so text and buttons always read.
        bg.addView(View(this).apply {
            background = GradientDrawable(
                GradientDrawable.Orientation.TOP_BOTTOM,
                intArrayOf(0x8C000000.toInt(), 0x33000000, 0x59000000, 0xF207060B.toInt())
            )
        }, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))

        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
        }
        bg.addView(content, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))

        // ---- clock --------------------------------------------------------
        content.addView(text("ALARM 101", 12f, TEXT3, 600).apply {
            letterSpacing = .28f
        }, lp(top = 36))
        val date = text("", 17f, TEXT2, 500)
        content.addView(date, lp(top = 18))
        val timeRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.BOTTOM
        }
        val time = text("", 96f, Color.WHITE, 300).apply {
            letterSpacing = -.03f
            includeFontPadding = false
        }
        val ampm = text("", 22f, TEXT2, 500).apply { setPadding((6 * dp).toInt(), 0, 0, (14 * dp).toInt()) }
        timeRow.addView(time)
        timeRow.addView(ampm)
        content.addView(timeRow, lp(top = 2))
        val greeting = text("", 17f, TEXT2, 400)
        content.addView(greeting, lp(top = 2))

        fun tick() {
            val now = Date()
            val h24 = DateFormat.is24HourFormat(this)
            time.text = SimpleDateFormat(if (h24) "H:mm" else "h:mm", Locale.getDefault()).format(now)
            ampm.text = if (h24) "" else SimpleDateFormat("a", Locale.ENGLISH).format(now).uppercase()
            ampm.visibility = if (h24) View.GONE else View.VISIBLE
            date.text = SimpleDateFormat("EEEE, d MMMM", Locale.ENGLISH).format(now)
            val hour = Calendar.getInstance().get(Calendar.HOUR_OF_DAY)
            greeting.text = when (hour) {
                in 4..11 -> "Good morning"
                in 12..16 -> "Good afternoon"
                else -> "Good evening"
            }
        }
        tick()
        ticker.post(object : Runnable {
            override fun run() {
                tick(); ticker.postDelayed(this, 5000)
            }
        })

        content.addView(View(this), LinearLayout.LayoutParams(MATCH_PARENT, 0, 1f))

        // ---- now playing card ---------------------------------------------
        val card = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            background = glass(26f)
            setPadding((12 * dp).toInt(), (12 * dp).toInt(), (18 * dp).toInt(), (12 * dp).toInt())
        }
        val thumb = ImageView(this).apply {
            scaleType = ImageView.ScaleType.CENTER_CROP
            background = GradientDrawable(GradientDrawable.Orientation.TL_BR, intArrayOf(ORANGE, PINK))
            outlineProvider = rounded(16f)
            clipToOutline = true
        }
        card.addView(thumb, LinearLayout.LayoutParams((64 * dp).toInt(), (64 * dp).toInt()))
        val labels = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding((14 * dp).toInt(), 0, (10 * dp).toInt(), 0)
        }
        labels.addView(text("NOW PLAYING", 11f, ORANGE, 700, Gravity.START).apply { letterSpacing = .16f })
        labels.addView(text(ring.getStringExtra(AlarmScheduler.EXTRA_TITLE) ?: "Wake up", 18f,
            Color.WHITE, 600, Gravity.START).apply {
            maxLines = 1
            ellipsize = TextUtils.TruncateAt.MARQUEE
            marqueeRepeatLimit = -1
            isSelected = true
            setHorizontallyScrolling(true)
            setPadding(0, (3 * dp).toInt(), 0, 0)
        })
        labels.addView(text(ring.getStringExtra(AlarmScheduler.EXTRA_ARTIST) ?: "", 15f, TEXT2, 400,
            Gravity.START).apply { maxLines = 1; ellipsize = TextUtils.TruncateAt.END })
        card.addView(labels, LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f))
        card.addView(equalizer())
        content.addView(card, lp(MATCH_PARENT, side = 20))

        // ---- buttons --------------------------------------------------------
        content.addView(button("Full Song", PlayIcon(), AlarmService.ACTION_FULL, hero = false).apply {
            background = GradientDrawable(GradientDrawable.Orientation.LEFT_RIGHT, intArrayOf(ORANGE, PINK))
                .apply { cornerRadius = 30 * dp }
            if (Build.VERSION.SDK_INT >= 28) {
                elevation = 14 * dp
                outlineSpotShadowColor = PINK
                outlineAmbientShadowColor = ORANGE
            }
        }, lp(MATCH_PARENT, (60 * dp).toInt(), top = 22, side = 20))
        content.addView(button("Stop", StopIcon(), AlarmService.ACTION_STOP, hero = true).apply {
            background = glass(34f, fill = .20f, edge = 0x52FFFFFF)
        }, lp(MATCH_PARENT, (68 * dp).toInt(), top = 12, side = 20, bottom = 28))

        setContentView(bg, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        goEdgeToEdge()
        bg.setOnApplyWindowInsetsListener { _, ins ->
            val (top, bottom) = if (Build.VERSION.SDK_INT >= 30) {
                val i = ins.getInsetsIgnoringVisibility(
                    WindowInsets.Type.systemBars() or WindowInsets.Type.displayCutout()
                )
                i.top to i.bottom
            } else {
                @Suppress("DEPRECATION")
                ins.systemWindowInsetTop to ins.systemWindowInsetBottom
            }
            content.setPadding(0, top, 0, bottom)
            ins
        }

        Art.load(this, ring.getStringExtra(AlarmScheduler.EXTRA_ART)) { bmp ->
            if (bmp == null || isFinishing) return@load
            thumb.setImageBitmap(bmp)
            poster.setImageBitmap(bmp)
            poster.animate().alpha(if (Build.VERSION.SDK_INT >= 31) .85f else .35f).setDuration(600).start()
            // Slow drift so the background feels alive.
            animators += ValueAnimator.ofFloat(1.15f, 1.35f).apply {
                duration = 18000
                repeatMode = ValueAnimator.REVERSE
                repeatCount = ValueAnimator.INFINITE
                interpolator = AccelerateDecelerateInterpolator()
                addUpdateListener { poster.scaleX = it.animatedValue as Float; poster.scaleY = poster.scaleX }
                start()
            }
        }
    }

    // ---- building blocks ----------------------------------------------------

    private fun goEdgeToEdge() {
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        @Suppress("DEPRECATION")
        window.statusBarColor = Color.TRANSPARENT
        @Suppress("DEPRECATION")
        window.navigationBarColor = Color.TRANSPARENT
        if (Build.VERSION.SDK_INT >= 30) {
            window.setDecorFitsSystemWindows(false)
            window.insetsController?.apply {
                hide(WindowInsets.Type.systemBars())
                systemBarsBehavior = WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            }
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_LAYOUT_STABLE or
                View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_FULLSCREEN or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
        }
        if (Build.VERSION.SDK_INT >= 30) {
            window.attributes.layoutInDisplayCutoutMode =
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
        }
    }

    /** Soft orange / pink / violet glows (the app's backdrop), shown until the poster loads. */
    private fun glows(): View = FrameLayout(this).apply {
        fun glow(color: Int, size: Int, g: Int, x: Int, y: Int) = addView(View(context).apply {
            background = GradientDrawable().apply {
                gradientType = GradientDrawable.RADIAL_GRADIENT
                gradientRadius = size * dp / 2
                colors = intArrayOf(color, color and 0x00FFFFFF)
            }
        }, FrameLayout.LayoutParams((size * dp).toInt(), (size * dp).toInt(), g).apply {
            leftMargin = (x * dp).toInt(); rightMargin = (x * dp).toInt(); topMargin = (y * dp).toInt()
            bottomMargin = (y * dp).toInt()
        })
        glow((ORANGE and 0x00FFFFFF) or 0x8C000000.toInt(), 520, Gravity.TOP or Gravity.START, -180, -160)
        glow((PINK and 0x00FFFFFF) or 0x73000000, 560, Gravity.CENTER_VERTICAL or Gravity.END, -240, 0)
        glow((VIOLET and 0x00FFFFFF) or 0x73000000, 600, Gravity.BOTTOM or Gravity.START, -200, -220)
    }

    /** Frosted glass surface: light diagonal fill + hairline edge. */
    private fun glass(radius: Float, fill: Float = .13f, edge: Int = 0x2EFFFFFF) = GradientDrawable(
        GradientDrawable.Orientation.TL_BR,
        intArrayOf(Color.argb((fill * 255).toInt(), 255, 255, 255), Color.argb((fill * 150).toInt(), 255, 255, 255))
    ).apply {
        cornerRadius = radius * dp
        setStroke(dp.toInt().coerceAtLeast(1), edge)
    }

    private fun rounded(radius: Float) = object : ViewOutlineProvider() {
        override fun getOutline(v: View, o: Outline) = o.setRoundRect(0, 0, v.width, v.height, radius * dp)
    }

    private fun text(s: String, size: Float, color: Int, weight: Int, g: Int = Gravity.CENTER) =
        TextView(this).apply {
            text = s
            textSize = size
            setTextColor(color)
            gravity = g
            typeface = if (Build.VERSION.SDK_INT >= 28) Typeface.create(Typeface.DEFAULT, weight, false)
            else if (weight >= 600) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
        }

    private fun lp(
        w: Int = WRAP_CONTENT, h: Int = WRAP_CONTENT,
        top: Int = 0, side: Int = 0, bottom: Int = 0,
    ) = LinearLayout.LayoutParams(w, h).apply {
        topMargin = (top * dp).toInt()
        bottomMargin = (bottom * dp).toInt()
        leftMargin = (side * dp).toInt()
        rightMargin = (side * dp).toInt()
    }

    /** Four bouncing bars: "this song is playing". */
    private fun equalizer(): View = LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.BOTTOM
        val h = (20 * dp).toInt()
        listOf(520L, 380L, 610L, 450L).forEachIndexed { i, ms ->
            val bar = View(context).apply {
                background = GradientDrawable(GradientDrawable.Orientation.BOTTOM_TOP, intArrayOf(ORANGE, PINK))
                    .apply { cornerRadius = 2 * dp }
                pivotY = h.toFloat()
            }
            addView(bar, LinearLayout.LayoutParams((3 * dp).toInt(), h).apply {
                if (i > 0) leftMargin = (3 * dp).toInt()
            })
            animators += ValueAnimator.ofFloat(.25f, 1f).apply {
                duration = ms
                repeatMode = ValueAnimator.REVERSE
                repeatCount = ValueAnimator.INFINITE
                startDelay = i * 90L
                addUpdateListener { bar.scaleY = it.animatedValue as Float }
                start()
            }
        }
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun button(label: String, icon: Drawable, action: String, hero: Boolean) =
        LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            val s = ((if (hero) 16 else 14) * dp).toInt()
            addView(ImageView(context).apply { setImageDrawable(icon) }, LinearLayout.LayoutParams(s, s))
            addView(text(label, if (hero) 20f else 17f, Color.WHITE, 600), LinearLayout.LayoutParams(
                WRAP_CONTENT, WRAP_CONTENT
            ).apply { leftMargin = (10 * dp).toInt() })
            isClickable = true
            setOnTouchListener { v, e ->
                when (e.action) {
                    MotionEvent.ACTION_DOWN -> v.animate().scaleX(.96f).scaleY(.96f).setDuration(90).start()
                    MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL ->
                        v.animate().scaleX(1f).scaleY(1f).setDuration(140).start()
                }
                false
            }
            setOnClickListener {
                startService(Intent(this@AlarmActivity, AlarmService::class.java).setAction(action))
                finish()
            }
        }

    /** Small solid triangle. */
    private class PlayIcon : ShapeIcon() {
        override fun path(w: Float, h: Float) = Path().apply {
            moveTo(w * .12f, 0f); lineTo(w, h / 2); lineTo(w * .12f, h); close()
        }
    }

    /** Small rounded square. */
    private class StopIcon : ShapeIcon() {
        override fun path(w: Float, h: Float) = Path().apply {
            addRoundRect(w * .1f, h * .1f, w * .9f, h * .9f, w * .2f, w * .2f, Path.Direction.CW)
        }
    }

    private abstract class ShapeIcon : Drawable() {
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE }
        abstract fun path(w: Float, h: Float): Path
        override fun draw(c: Canvas) {
            c.save()
            c.translate(bounds.left.toFloat(), bounds.top.toFloat())
            c.drawPath(path(bounds.width().toFloat(), bounds.height().toFloat()), paint)
            c.restore()
        }
        override fun setAlpha(a: Int) { paint.alpha = a }
        override fun setColorFilter(f: ColorFilter?) { paint.colorFilter = f }
        @Deprecated("Deprecated in Java")
        override fun getOpacity() = PixelFormat.TRANSLUCENT
    }

    override fun onDestroy() {
        ticker.removeCallbacksAndMessages(null)
        animators.forEach { it.cancel() }
        try {
            unregisterReceiver(closer)
        } catch (_: Exception) {
        }
        super.onDestroy()
    }
}
