package com.harshitbhatia.alarm101

import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import java.nio.ByteOrder
import kotlin.math.exp
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * How danceable/upbeat a preview sounds, plus where its punchiest part starts.
 * Same maths as `Energy` in ios/Runner/AppDelegate.swift; tuned on known party
 * vs romantic songs (party ≈ 2.9–3.6, romantic ≈ 0.5–1.9).
 */
object Energy {
    data class Result(val score: Double, val hook: Double)

    fun analyze(path: String): Result {
        val (mono, rate) = decodeMono(path)
        return analyze(mono, rate.toDouble())
    }

    fun analyze(mono: FloatArray, rate: Double): Result {
        val step = max(1, (rate / 22050).roundToInt())
        val sr = rate / step
        val hop = 512
        val x = DoubleArray(mono.size / step) { mono[it * step].toDouble() }
        val frames = x.size / hop
        if (frames < 64) return Result(0.0, 0.0)

        val a = exp(-2 * Math.PI * 150 / sr)
        var lp = 0.0
        var prev = 0.0
        val e = DoubleArray(frames) { 1e-10 }
        val l = DoubleArray(frames) { 1e-10 }
        val h = DoubleArray(frames) { 1e-10 }
        for (f in 0 until frames) {
            var se = 0.0; var sl = 0.0; var sh = 0.0
            for (j in 0 until hop) {
                val v = x[f * hop + j]
                lp = (1 - a) * v + a * lp
                val d = v - prev
                prev = v
                se += v * v; sl += lp * lp; sh += d * d
            }
            e[f] += se / hop; l[f] += sl / hop; h[f] += sh / hop
        }
        fun db(v: Double) = 10 * log10(v)
        val env = DoubleArray(frames - 1)
        var oL = 0.0
        var oH = 0.0
        for (f in 1 until frames) {
            val ul = max(0.0, db(l[f]) - db(l[f - 1]))
            val uh = max(0.0, db(h[f]) - db(h[f - 1]))
            oL += ul; oH += uh; env[f - 1] = ul + uh
        }
        oL /= (frames - 1); oH /= (frames - 1)
        val mean = env.average()
        for (k in env.indices) env[k] -= mean
        val fps = sr / hop
        val ac0 = env.sumOf { it * it } + 1e-9
        var beat = 0.0
        for (lag in (0.25 * fps).toInt() until (1.0 * fps).toInt()) {
            if (lag >= env.size) break
            var s = 0.0
            for (k in 0 until env.size - lag) s += env[k] * env[k + lag]
            beat = max(beat, s / ac0)
        }
        val bass = db(l.average()) - db(e.average())
        val score = oL + oH + 1.5 * beat + 0.1 * bass

        // Hook = start of the loudest 6 s window (only if the preview has a clear build-up).
        val w = (6 * fps).toInt()
        var hook = 0.0
        if (frames > w) {
            val d = DoubleArray(frames) { db(e[it]) }
            var run = (0 until w).sumOf { d[it] }
            var best = run
            var worst = run
            var at = 0
            for (f in w until frames) {
                run += d[f] - d[f - w]
                if (run > best) { best = run; at = f - w + 1 }
                worst = min(worst, run)
            }
            if ((best - worst) / w >= 2) hook = max(0.0, at / fps - 0.3)
        }
        return Result(score, hook)
    }

    /** Decodes an mp3/m4a file to mono float samples. */
    private fun decodeMono(path: String): Pair<FloatArray, Int> {
        val ex = MediaExtractor()
        ex.setDataSource(path)
        val track = (0 until ex.trackCount).first {
            ex.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
        }
        ex.selectTrack(track)
        val fmt = ex.getTrackFormat(track)
        val codec = MediaCodec.createDecoderByType(fmt.getString(MediaFormat.KEY_MIME)!!)
        codec.configure(fmt, null, null, 0)
        codec.start()

        var rate = fmt.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        var channels = fmt.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
        var isFloat = false
        var out = FloatArray(rate * 32)
        var n = 0
        val info = MediaCodec.BufferInfo()
        var inputDone = false
        try {
            while (true) {
                if (!inputDone) {
                    val i = codec.dequeueInputBuffer(10_000)
                    if (i >= 0) {
                        val size = ex.readSampleData(codec.getInputBuffer(i)!!, 0)
                        if (size < 0) {
                            codec.queueInputBuffer(i, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            codec.queueInputBuffer(i, 0, size, ex.sampleTime, 0)
                            ex.advance()
                        }
                    }
                }
                val o = codec.dequeueOutputBuffer(info, 10_000)
                if (o == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    val f = codec.outputFormat
                    rate = f.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                    channels = f.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                    isFloat = f.containsKey(MediaFormat.KEY_PCM_ENCODING) &&
                        f.getInteger(MediaFormat.KEY_PCM_ENCODING) == AudioFormat.ENCODING_PCM_FLOAT
                } else if (o >= 0) {
                    val buf = codec.getOutputBuffer(o)!!.order(ByteOrder.nativeOrder())
                    buf.position(info.offset)
                    buf.limit(info.offset + info.size)
                    val frames = if (isFloat) info.size / 4 / channels else info.size / 2 / channels
                    if (n + frames > out.size) out = out.copyOf(max(out.size * 2, n + frames))
                    if (isFloat) {
                        val fb = buf.asFloatBuffer()
                        for (k in 0 until frames) {
                            var s = 0f
                            for (c in 0 until channels) s += fb.get()
                            out[n++] = s / channels
                        }
                    } else {
                        val sb = buf.asShortBuffer()
                        for (k in 0 until frames) {
                            var s = 0f
                            for (c in 0 until channels) s += sb.get() / 32768f
                            out[n++] = s / channels
                        }
                    }
                    codec.releaseOutputBuffer(o, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break
                }
            }
        } finally {
            codec.stop(); codec.release(); ex.release()
        }
        return Pair(out.copyOf(n), rate)
    }
}
