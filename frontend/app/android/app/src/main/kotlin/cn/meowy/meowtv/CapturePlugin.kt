package cn.meowy.meowtv

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.view.PixelCopy
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.MediaRecorder
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.DisplayMetrics
import android.view.View
import android.widget.FrameLayout
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class CapturePlugin : MethodChannel.MethodCallHandler {
    var activity: Activity? = null
    private var mediaRecorder: MediaRecorder? = null
    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var isRecording = false
    private var tempFilePath: String? = null
    private var pendingResult: MethodChannel.Result? = null
    private var recordingWidth = 1920
    private var recordingHeight = 1080
    private var recordingFps = 30

    companion object {
        private const val CHANNEL = "com.meowtv.capture"
        const val REQUEST_MEDIA_PROJECTION = 2001

        fun register(flutterEngine: FlutterEngine, activity: Activity) {
            val plugin = CapturePlugin()
            plugin.activity = activity
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
                .setMethodCallHandler(plugin)
        }
    }

    /// MediaProjection 权限回调
    fun onMediaProjectionResult(resultCode: Int, data: Intent?) {
        if (resultCode != Activity.RESULT_OK || data == null) {
            pendingResult?.error("PERMISSION_DENIED", "MediaProjection permission denied", null)
            pendingResult = null
            return
        }

        val act = activity
        if (act == null) {
            pendingResult?.error("NO_ACTIVITY", "Activity is null", null)
            pendingResult = null
            return
        }

        val projectionManager = act.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        mediaProjection = projectionManager.getMediaProjection(resultCode, data)

        if (mediaProjection == null) {
            pendingResult?.error("PROJECTION_FAILED", "Failed to get MediaProjection", null)
            pendingResult = null
            return
        }

        startRecordingWithProjection(act)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "captureFrame" -> captureFrame(result)
            "startRecording" -> startRecording(call, result)
            "stopRecording" -> stopRecording(result)
            else -> result.notImplemented()
        }
    }

    private fun captureFrame(result: MethodChannel.Result) {
        val act = activity
        if (act == null) {
            result.error("NO_ACTIVITY", "Activity is null", null)
            return
        }

        try {
            val flutterView = findFlutterView(act)
            if (flutterView == null) {
                result.error("NO_VIEW", "Cannot find Flutter view", null)
                return
            }

            val width = flutterView.width
            val height = flutterView.height
            if (width <= 0 || height <= 0) {
                result.error("INVALID_SIZE", "View size is invalid: ${width}x${height}", null)
                return
            }

            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                PixelCopy.request(act.window, bitmap, { copyResult ->
                    if (copyResult == PixelCopy.SUCCESS) {
                        val stream = ByteArrayOutputStream()
                        bitmap.compress(Bitmap.CompressFormat.JPEG, 100, stream)
                        bitmap.recycle()
                        result.success(stream.toByteArray())
                    } else {
                        bitmap.recycle()
                        captureWithViewDraw(flutterView, result)
                    }
                }, Handler(Looper.getMainLooper()))
            } else {
                captureWithViewDraw(flutterView, result)
            }
        } catch (e: Exception) {
            result.error("CAPTURE_FAILED", "Screenshot failed: ${e.message}", null)
        }
    }

    private fun captureWithViewDraw(view: View, result: MethodChannel.Result) {
        try {
            val bitmap = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888)
            val canvas = android.graphics.Canvas(bitmap)
            view.draw(canvas)
            val stream = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.JPEG, 100, stream)
            bitmap.recycle()
            result.success(stream.toByteArray())
        } catch (e: Exception) {
            result.error("CAPTURE_FAILED", "View.draw fallback failed: ${e.message}", null)
        }
    }

    private fun findFlutterView(activity: Activity): View? {
        val contentView = activity.findViewById<View>(android.R.id.content)
        return findSurfaceView(contentView)
    }

    private fun findSurfaceView(view: View): View? {
        if (view is FrameLayout) {
            for (i in 0 until view.childCount) {
                val child = view.getChildAt(i)
                if (child.javaClass.name.contains("Flutter") ||
                    child.javaClass.name.contains("TextureView") ||
                    child.javaClass.name.contains("SurfaceView")) {
                    return child
                }
                val found = findSurfaceView(child)
                if (found != null) return found
            }
        }
        if (view.javaClass.name.contains("Flutter") ||
            view.javaClass.name.contains("TextureView") ||
            view.javaClass.name.contains("SurfaceView")) {
            return view
        }
        return null
    }

    private fun startRecording(call: MethodCall, result: MethodChannel.Result) {
        if (isRecording) {
            result.error("ALREADY_RECORDING", "Recording is already in progress", null)
            return
        }

        val act = activity
        if (act == null) {
            result.error("NO_ACTIVITY", "Activity is null", null)
            return
        }

        recordingFps = call.argument<Int>("fps") ?: 30
        recordingWidth = call.argument<Int>("width") ?: 1920
        recordingHeight = call.argument<Int>("height") ?: 1080

        // 保存 result，等待权限回调
        pendingResult = result

        // 请求 MediaProjection 权限
        val projectionManager = act.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        act.startActivityForResult(projectionManager.createScreenCaptureIntent(), REQUEST_MEDIA_PROJECTION)
    }

    private fun startRecordingWithProjection(activity: Activity) {
        try {
            val tempDir = activity.cacheDir
            val dateFormat = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.getDefault())
            tempFilePath = File(tempDir, "meowtv_record_${dateFormat.format(Date())}.mp4").absolutePath

            // 获取实际屏幕尺寸
            val metrics = DisplayMetrics()
            activity.windowManager.defaultDisplay.getMetrics(metrics)
            val screenWidth = metrics.widthPixels
            val screenHeight = metrics.heightPixels

            // 使用屏幕实际尺寸，但不超过请求的尺寸
            val recordWidth = minOf(screenWidth, recordingWidth)
            val recordHeight = minOf(screenHeight, recordingHeight)

            mediaRecorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                MediaRecorder(activity)
            } else {
                @Suppress("DEPRECATION")
                MediaRecorder()
            }

            mediaRecorder?.apply {
                setVideoSource(MediaRecorder.VideoSource.SURFACE)
                setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                setVideoEncoder(MediaRecorder.VideoEncoder.H264)
                setVideoSize(recordWidth, recordHeight)
                setVideoFrameRate(recordingFps)
                setVideoEncodingBitRate(8 * 1024 * 1024) // 8 Mbps
                setOutputFile(tempFilePath)
                prepare()
            }

            val surface = mediaRecorder?.surface
            if (surface == null) {
                pendingResult?.error("RECORDER_FAILED", "Failed to get recorder surface", null)
                pendingResult = null
                releaseRecording()
                return
            }

            virtualDisplay = mediaProjection?.createVirtualDisplay(
                "MeowTV Recording",
                recordWidth, recordHeight, metrics.densityDpi,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                surface, null, null
            )

            mediaRecorder?.start()
            isRecording = true

            pendingResult?.success(null)
            pendingResult = null
        } catch (e: Exception) {
            releaseRecording()
            pendingResult?.error("RECORD_START_FAILED", "Failed to start recording: ${e.message}", null)
            pendingResult = null
        }
    }

    private fun stopRecording(result: MethodChannel.Result) {
        if (!isRecording) {
            result.error("NOT_RECORDING", "No recording in progress", null)
            return
        }

        try {
            mediaRecorder?.apply {
                stop()
                release()
            }
        } catch (_: Exception) {
            // stop() may throw if recording was too short
        }

        releaseRecording()

        val path = tempFilePath
        tempFilePath = null

        if (path != null && File(path).exists()) {
            result.success(path)
        } else {
            result.error("RECORD_STOP_FAILED", "Recording file not found", null)
        }
    }

    private fun releaseRecording() {
        virtualDisplay?.release()
        virtualDisplay = null
        mediaRecorder?.release()
        mediaRecorder = null
        mediaProjection?.stop()
        mediaProjection = null
        isRecording = false
    }
}
