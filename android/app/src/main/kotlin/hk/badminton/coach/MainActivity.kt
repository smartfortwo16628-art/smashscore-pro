package hk.badminton.coach

import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors

/** All media stays in app-private storage. Only the system document picker sees external files. */
class MainActivity : FlutterActivity() {
    private val worker = Executors.newSingleThreadExecutor()
    private var pickerResult: MethodChannel.Result? = null
    private var exportSource: File? = null
    private val timelines = LinkedHashMap<String, List<Long>>()
    private var disposed = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "hk.badminton.coach/media")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "importVideo" -> launchPicker(result, null)
                    "exportImage" -> try {
                        val file = privateFile(call.argument<String>("path"))
                        require(file.parentFile?.canonicalFile == File(filesDir, "images").canonicalFile && file.extension == "png")
                        launchPicker(result, file)
                    } catch (_: Exception) { result.error("image", "圖片不存在或不屬於此 App", null) }
                    "directory" -> result.success(File(filesDir, "images").apply { mkdirs() }.absolutePath)
                    "info" -> background(result) { timelineInfo(privateFile(call.argument<String>("path"))) }
                    "frame" -> background(result) { decodeFrame(call) }
                    else -> result.notImplemented()
                }
            }
    }

    private fun privateFile(path: String?): File {
        require(!path.isNullOrBlank()) { "檔案路徑無效" }
        val file = File(path).canonicalFile
        require(file.path.startsWith(filesDir.canonicalPath + File.separator) && file.isFile) { "私人檔案不存在" }
        return file
    }

    private fun background(result: MethodChannel.Result, block: () -> Any?) {
        if (disposed) { result.error("closed", "頁面已關閉", null); return }
        worker.execute {
            try {
                val value = block()
                runOnUiThread { if (!disposed) result.success(value) }
            } catch (e: Exception) {
                runOnUiThread { if (!disposed) result.error("media", e.message ?: "影片處理失敗", null) }
            }
        }
    }

    private fun launchPicker(result: MethodChannel.Result, source: File?) {
        if (pickerResult != null) { result.error("busy", "請先完成上一個檔案選擇", null); return }
        pickerResult = result
        exportSource = source
        val intent = if (source == null) {
            Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "video/*"
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
        } else {
            Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "image/png"
                putExtra(Intent.EXTRA_TITLE, "badminton_${System.currentTimeMillis()}.png")
            }
        }
        try { startActivityForResult(intent, if (source == null) 704 else 705) }
        catch (e: Exception) { pickerResult = null; exportSource = null; result.error("picker", "手機無法開啟檔案選擇器", null) }
    }

    @Deprecated("Android document picker activity result")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 704 && requestCode != 705) return
        val result = pickerResult ?: return
        val source = exportSource
        pickerResult = null
        exportSource = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(if (requestCode == 704) null else false)
            return
        }
        background(result) {
            if (requestCode == 704) importVideo(uri) else {
                require(source != null && source.isFile) { "原圖片已不存在" }
                contentResolver.openOutputStream(uri, "w").use { output ->
                    requireNotNull(output) { "無法寫入所選位置" }
                    source.inputStream().use { it.copyTo(output) }
                }
                true
            }
        }
    }

    private fun <T> retrieve(file: File, block: (MediaMetadataRetriever) -> T): T {
        val reader = MediaMetadataRetriever()
        try { reader.setDataSource(this, Uri.fromFile(file)); return block(reader) }
        finally { reader.release() }
    }

    private fun importVideo(uri: Uri): Map<String, Any> {
        var title = "訓練影片"
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)?.use {
            if (it.moveToFirst()) {
                title = it.getString(0)?.take(120) ?: title
                if (!it.isNull(1)) require(it.getLong(1) <= MAX_BYTES) { "影片超過 300 MiB" }
            }
        }
        val destination = File(File(filesDir, "media").apply { mkdirs() }, "${UUID.randomUUID()}.video")
        try {
            contentResolver.openInputStream(uri).use { input ->
                requireNotNull(input) { "無法讀取所選影片" }
                destination.outputStream().use { output ->
                    val buffer = ByteArray(65536)
                    var total = 0L
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        total += count
                        require(total <= MAX_BYTES) { "影片超過 300 MiB" }
                        output.write(buffer, 0, count)
                    }
                }
            }
            val duration = retrieve(destination) { reader ->
                val ms = reader.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0
                val width = reader.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 0
                val height = reader.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0
                require(ms in 1..180000) { "請選擇 3 分鐘內嘅影片" }
                require(width > 0 && height > 0 && width.toLong() * height <= 16777216) { "影片尺寸太大或格式不支援" }
                val sample = reader.getScaledFrameAtTime(0, MediaMetadataRetriever.OPTION_CLOSEST, 160, 160)
                requireNotNull(sample) { "手機未能解碼此影片" }
                sample.recycle()
                ms
            }
            return mapOf("path" to destination.absolutePath, "name" to title, "duration" to duration)
        } catch (e: Exception) { destination.delete(); throw e }
    }

    private fun timelineInfo(file: File): Map<String, Any> {
        val times = timeline(file)
        return mapOf("precise" to times.isNotEmpty(), "times" to times)
    }

    /** Never estimate indices using average FPS: accept only complete, unique presentation timestamps. */
    private fun timeline(file: File): List<Long> {
        timelines[file.path]?.let { return it }
        val expected = retrieve(file) { it.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_FRAME_COUNT)?.toIntOrNull() ?: 0 }
        if (expected !in 1..30000) return emptyList()
        val extractor = MediaExtractor()
        val samples = ArrayList<Long>()
        try {
            extractor.setDataSource(file.path)
            val track = (0 until extractor.trackCount).firstOrNull {
                extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("video/") == true
            } ?: return emptyList()
            extractor.selectTrack(track)
            while (extractor.sampleTime >= 0 && samples.size <= 30000) {
                samples.add(extractor.sampleTime)
                if (!extractor.advance()) break
            }
        } finally { extractor.release() }
        samples.sort()
        if (samples.size != expected || samples.toSet().size != expected) return emptyList()
        val start = samples.first()
        val milliseconds = samples.map { (it - start) / 1000 }
        if (milliseconds.toSet().size != expected || milliseconds.last() > 180000) return emptyList()
        if (timelines.size >= 4) timelines.remove(timelines.keys.first())
        timelines[file.path] = milliseconds
        return milliseconds
    }

    private fun decodeFrame(call: MethodCall): Map<String, Any> {
        val file = privateFile(call.argument<String>("path"))
        val index = call.argument<Number>("index")?.toInt()
        val position = (call.argument<Number>("position")?.toLong() ?: 0).coerceIn(0, 180000)
        val times = if (index != null) timeline(file) else emptyList()
        if (index != null) require(index in times.indices) { "此影片不支援可靠逐格或影格超出範圍" }
        return retrieve(file) { reader ->
            val raw = if (index != null) reader.getFrameAtIndex(index)
                else reader.getFrameAtTime(position * 1000, MediaMetadataRetriever.OPTION_CLOSEST)
            requireNotNull(raw) { "此影格未能解碼，請改用其他影片" }
            val factor = minOf(1.0, 1280.0 / maxOf(raw.width, raw.height))
            val bitmap = if (factor < 1) Bitmap.createScaledBitmap(raw, (raw.width * factor).toInt().coerceAtLeast(1), (raw.height * factor).toInt().coerceAtLeast(1), true) else raw
            try {
                val output = ByteArrayOutputStream()
                check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, output)) { "影格編碼失敗" }
                mapOf("bytes" to output.toByteArray(), "width" to bitmap.width, "height" to bitmap.height,
                    "index" to (index ?: -1), "position" to (if (index != null) times[index] else position))
            } finally { if (bitmap !== raw) bitmap.recycle(); raw.recycle() }
        }
    }

    override fun onDestroy() {
        disposed = true
        pickerResult?.error("closed", "頁面已關閉，請重新選擇檔案", null)
        pickerResult = null
        worker.shutdown()
        super.onDestroy()
    }

    companion object { private const val MAX_BYTES = 300L * 1024 * 1024 }
}
