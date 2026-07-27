package cn.meowy.meowtv

import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class SubtitlePlugin : MethodChannel.MethodCallHandler {

    companion object {
        private const val TAG = "SubtitlePlugin"
        private const val CHANNEL = "com.meowtv.subtitle/render"

        fun register(flutterEngine: FlutterEngine) {
            val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            channel.setMethodCallHandler(SubtitlePlugin())
        }
    }

    private val handler = Handler(Looper.getMainLooper())

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getEmbeddedTracks" -> getEmbeddedTracks(result)
            "selectEmbeddedTrack" -> selectEmbeddedTrack(call, result)
            "loadExternalSubtitle" -> loadExternalSubtitle(call, result)
            "updateOffset" -> updateOffset(call, result)
            "clearSubtitle" -> clearSubtitle(result)
            else -> result.notImplemented()
        }
    }

    private fun getEmbeddedTracks(result: MethodChannel.Result) {
        handler.post {
            // TODO: Integrate with ExoPlayer via video_player plugin to enumerate text tracks
            result.success(emptyList<Map<String, Any?>>())
        }
    }

    private fun selectEmbeddedTrack(call: MethodCall, result: MethodChannel.Result) {
        handler.post {
            val trackIndex = call.argument<Int>("trackIndex") ?: 0
            Log.d(TAG, "selectEmbeddedTrack: $trackIndex (not yet connected to ExoPlayer)")
            // TODO: Integrate with ExoPlayer via video_player plugin to select text track
            result.success(true)
        }
    }

    private fun loadExternalSubtitle(call: MethodCall, result: MethodChannel.Result) {
        handler.post {
            try {
                val cues = call.argument<List<Map<String, Any>>>("cues")
                val offsetMs = call.argument<Double>("offsetMs") ?: 0.0
                Log.d(TAG, "External subtitle loaded: ${cues?.size ?: 0} cues, offset: ${offsetMs}ms")
                result.success(true)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to load external subtitle", e)
                result.success(false)
            }
        }
    }

    private fun updateOffset(call: MethodCall, result: MethodChannel.Result) {
        handler.post {
            try {
                val offsetMs = call.argument<Double>("offsetMs") ?: 0.0
                Log.d(TAG, "Subtitle offset updated: ${offsetMs}ms")
                result.success(true)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to update offset", e)
                result.success(false)
            }
        }
    }

    private fun clearSubtitle(result: MethodChannel.Result) {
        handler.post {
            // TODO: Integrate with ExoPlayer via video_player plugin to clear text track selection
            result.success(null)
        }
    }
}
