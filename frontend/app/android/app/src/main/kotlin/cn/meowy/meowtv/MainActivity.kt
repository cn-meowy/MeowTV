package cn.meowy.meowtv

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.DocumentsContract
import fl.pip.FlPiPActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlPiPActivity() {
    private val CHANNEL = "com.meowtv/file_picker"
    private val REQUEST_CODE_PICK_FILE = 1001

    private var pendingResult: MethodChannel.Result? = null
    private var pendingMimeTypes: List<String>? = null
    private var capturePlugin: CapturePlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        SubtitlePlugin.register(flutterEngine)
        capturePlugin = CapturePlugin()
        capturePlugin?.activity = this
        CapturePlugin.register(flutterEngine, this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickFile" -> {
                        val mimeTypes = call.argument<List<String>>("mimeTypes")
                        if (pendingResult != null) {
                            result.error("ALREADY_ACTIVE", "Another file pick is already in progress", null)
                            return@setMethodCallHandler
                        }
                        pendingResult = result
                        pendingMimeTypes = mimeTypes
                        openFilePicker(mimeTypes)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun openFilePicker(mimeTypes: List<String>?) {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            if (mimeTypes != null && mimeTypes.isNotEmpty()) {
                putExtra(Intent.EXTRA_MIME_TYPES, mimeTypes.toTypedArray())
            }
        }
        try {
            startActivityForResult(intent, REQUEST_CODE_PICK_FILE)
        } catch (e: Exception) {
            pendingResult?.success(null)
            pendingResult = null
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQUEST_CODE_PICK_FILE) {
            val result = pendingResult
            pendingResult = null
            if (resultCode == Activity.RESULT_OK && data != null) {
                val uri: Uri? = data.data
                if (uri != null) {
                    // 获取持久化权限，以便 media_kit 可以读取文件
                    try {
                        contentResolver.takePersistableUriPermission(
                            uri,
                            Intent.FLAG_GRANT_READ_URI_PERMISSION
                        )
                    } catch (_: Exception) {
                        // 某些 URI 不支持持久化权限，忽略
                    }
                    // 返回 content:// URI，media_kit (libmpv) 在 Android 上支持此格式
                    result?.success(uri.toString())
                } else {
                    result?.success(null)
                }
            } else {
                result?.success(null)
            }
            return
        }
        if (requestCode == CapturePlugin.REQUEST_MEDIA_PROJECTION) {
            capturePlugin?.onMediaProjectionResult(resultCode, data)
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }
}
