package ro.madcodestudios.ticket.box

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException

class MainActivity : FlutterActivity() {
    private var pendingResult: MethodChannel.Result? = null
    private var pendingRequestCode: Int? = null
    private var pendingSourcePath: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BACKUP_FILES_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "saveFile" -> startSaveFile(
                    call.argument<String>("sourcePath"),
                    call.argument<String>("fileName"),
                    call.argument<String>("mimeType"),
                    result,
                )
                "openFile" -> startOpenFile(result)
                else -> result.notImplemented()
            }
        }
    }

    // Opens the system "Save as" picker (Storage Access Framework), so the user can keep a copy of
    // [sourcePath] anywhere on the device without the app holding any storage permission.
    private fun startSaveFile(sourcePath: String?, fileName: String?, mimeType: String?, result: MethodChannel.Result) {
        if (sourcePath == null || fileName == null) {
            result.error("bad_args", "sourcePath and fileName are required", null)
            return
        }
        if (!claimPending(result, SAVE_FILE_REQUEST_CODE)) {
            return
        }

        pendingSourcePath = sourcePath
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT)
            .addCategory(Intent.CATEGORY_OPENABLE)
            .setType(mimeType ?: "application/octet-stream")
            .putExtra(Intent.EXTRA_TITLE, fileName)
        startActivityForResult(intent, SAVE_FILE_REQUEST_CODE)
    }

    // Opens the system "Open" picker and answers with the picked file's text. Any type is offered:
    // file managers label a .json file inconsistently, so the content is validated in Dart instead.
    private fun startOpenFile(result: MethodChannel.Result) {
        if (!claimPending(result, OPEN_FILE_REQUEST_CODE)) {
            return
        }

        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT)
            .addCategory(Intent.CATEGORY_OPENABLE)
            .setType("*/*")
        startActivityForResult(intent, OPEN_FILE_REQUEST_CODE)
    }

    // Only one picker can be on screen at a time, and its result is answered from onActivityResult.
    private fun claimPending(result: MethodChannel.Result, requestCode: Int): Boolean {
        if (pendingResult != null) {
            result.error("busy", "A file picker is already open", null)
            return false
        }
        pendingResult = result
        pendingRequestCode = requestCode
        return true
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != SAVE_FILE_REQUEST_CODE && requestCode != OPEN_FILE_REQUEST_CODE) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        if (requestCode != pendingRequestCode) {
            return
        }

        val result = pendingResult ?: return
        val sourcePath = pendingSourcePath
        pendingResult = null
        pendingRequestCode = null
        pendingSourcePath = null

        val uri = data?.data
        if (requestCode == OPEN_FILE_REQUEST_CODE) {
            if (resultCode != RESULT_OK || uri == null) {
                result.success(null)
                return
            }
            try {
                val input = contentResolver.openInputStream(uri) ?: throw IOException("Could not open $uri")
                result.success(input.use { it.readBytes().toString(Charsets.UTF_8) })
            } catch (e: IOException) {
                result.error("read_failed", e.message, null)
            }
            return
        }

        if (resultCode != RESULT_OK || uri == null || sourcePath == null) {
            result.success(false)
            return
        }

        try {
            val output = contentResolver.openOutputStream(uri) ?: throw IOException("Could not open $uri")
            output.use { out -> File(sourcePath).inputStream().use { input -> input.copyTo(out) } }
            result.success(true)
        } catch (e: IOException) {
            result.error("write_failed", e.message, null)
        }
    }

    companion object {
        private const val BACKUP_FILES_CHANNEL = "ticket_box/backup_files"
        private const val SAVE_FILE_REQUEST_CODE = 4711
        private const val OPEN_FILE_REQUEST_CODE = 4712
    }
}
