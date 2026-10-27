package hk.badminton.coach

import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.pose.PoseDetection
import com.google.mlkit.vision.pose.defaults.PoseDetectorOptions
import java.io.File
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import kotlin.math.abs

/** One bounded, cancellable on-device job. Called on MainActivity's media worker, never the UI thread. */
class PoseEngine {
    private val active = AtomicReference<String?>(null)
    private val cancelled = AtomicBoolean(false)

    fun begin(job: String): Boolean {
        if (!active.compareAndSet(null, job)) return false
        cancelled.set(false)
        return true
    }
    fun cancel(job: String?) {
        if (job == null || job == active.get()) cancelled.set(true)
    }
    fun finish(job: String) { active.compareAndSet(job, null) }
    private fun checkRunning() { check(!cancelled.get()) { "分析已停止；返回頁面後可以重新分析。" } }

    fun analyze(file: File, timeline: List<Long>, progress: (Map<String, Any>) -> Unit): Map<String, Any> {
        val reader = MediaMetadataRetriever()
        val options = PoseDetectorOptions.Builder()
            .setDetectorMode(PoseDetectorOptions.STREAM_MODE)
            .setPreferredHardwareConfigs(PoseDetectorOptions.CPU)
            .build()
        val detector = PoseDetection.getClient(options)
        try {
            checkRunning()
            reader.setDataSource(file.path)
            val duration = reader.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0
            require(duration in 1..180000) { "請使用 3 分鐘內嘅影片。" }
            val sourceWidth = reader.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 0
            val sourceHeight = reader.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0
            require(sourceWidth > 0 && sourceHeight > 0 && sourceWidth.toLong() * sourceHeight <= 16777216) { "影片尺寸不支援。" }
            val indices = ArrayList<Int>()
            val times = ArrayList<Long>()
            var previous = -1
            for (target in 0L until duration step 125L) {
                if (timeline.isEmpty()) { times.add(target); indices.add(-1); continue }
                val found = timeline.binarySearch(target)
                val insertion = if (found >= 0) found else -found - 1
                val hi = insertion.coerceIn(0, timeline.lastIndex)
                val lo = (insertion - 1).coerceIn(0, timeline.lastIndex)
                val index = if (abs(timeline[lo] - target) <= abs(timeline[hi] - target)) lo else hi
                if (index != previous) { times.add(timeline[index]); indices.add(index); previous = index }
            }
            val frames = ArrayList<Map<String, Any>>()
            var failed = 0
            progress(mapOf("done" to 0, "total" to times.size))
            for (i in times.indices) {
                checkRunning()
                val raw = try {
                    if (indices[i] >= 0) reader.getFrameAtIndex(indices[i])
                    else reader.getScaledFrameAtTime(times[i] * 1000, MediaMetadataRetriever.OPTION_CLOSEST, 960, 960)
                } catch (_: RuntimeException) { null }
                if (raw == null) {
                    failed++
                    frames.add(mapOf("t" to times[i], "index" to indices[i], "width" to 0, "height" to 0, "points" to emptyList<Any>()))
                } else {
                    val scale = minOf(1.0, 960.0 / maxOf(raw.width, raw.height))
                    val bitmap = if (scale < 1) Bitmap.createScaledBitmap(raw, (raw.width * scale).toInt().coerceAtLeast(1), (raw.height * scale).toInt().coerceAtLeast(1), true) else raw
                    try {
                        // The retriever already applies the video's display rotation; don't rotate twice.
                        val pose = Tasks.await(detector.process(InputImage.fromBitmap(bitmap, 0)), 45, TimeUnit.SECONDS)
                        checkRunning()
                        val points = pose.allPoseLandmarks.filter { it.landmarkType >= 11 }.map {
                            // Body points only. No face image, identity embedding, or experimental Z claim.
                            listOf(it.landmarkType.toDouble(), it.position.x.toDouble() / bitmap.width,
                                it.position.y.toDouble() / bitmap.height, it.inFrameLikelihood.toDouble())
                        }
                        frames.add(mapOf("t" to times[i], "index" to indices[i], "width" to bitmap.width,
                            "height" to bitmap.height, "points" to points))
                    } finally { if (bitmap !== raw) bitmap.recycle(); raw.recycle() }
                }
                progress(mapOf("done" to i + 1, "total" to times.size))
            }
            checkRunning()
            return mapOf("model" to "ML Kit Pose 18.0.0-beta5 / CPU", "sampleMs" to 125,
                "duration" to duration, "precise" to timeline.isNotEmpty(), "failed" to failed, "frames" to frames)
        } finally { detector.close(); reader.release() }
    }
}
