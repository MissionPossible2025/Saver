package com.whatsappstatus.downloader

import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Environment
import android.provider.MediaStore
import android.util.Log
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.InputStream
import java.io.OutputStream

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.whatsappstatus.downloader/channel"
    private val TAG = "StatusDownloader"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getStatusItems" -> {
                    try {
                        val statusItems = getWhatsAppStatusItems()
                        result.success(statusItems)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error getting status items", e)
                        result.error("ERROR", "Failed to get status items: ${e.message}", null)
                    }
                }
                "downloadStatus" -> {
                    try {
                        val path = call.argument<String>("path") ?: ""
                        val name = call.argument<String>("name") ?: ""
                        val type = call.argument<String>("type") ?: ""
                        val message = downloadToGallery(path, name, type)
                        result.success(message)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error downloading status", e)
                        result.error("ERROR", "Failed to download: ${e.message}", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun getWhatsAppStatusItems(): List<Map<String, Any>> {
        val statusFiles = StatusAccessHelper.getStatusFiles()
        return statusFiles.map { file ->
            mapOf(
                "path" to file.path,
                "name" to file.name,
                "type" to file.type,
                "size" to file.size,
                "lastModified" to file.lastModified
            )
        }
    }

    private fun downloadToGallery(sourcePath: String, fileName: String, type: String): String {
        val sourceFile = File(sourcePath)
        if (!sourceFile.exists()) {
            throw Exception("Source file does not exist")
        }

        val contentValues = ContentValues().apply {
            if (type == "video") {
                put(MediaStore.Video.Media.DISPLAY_NAME, fileName)
                put(MediaStore.Video.Media.MIME_TYPE, getMimeType(fileName))
                put(MediaStore.Video.Media.RELATIVE_PATH, Environment.DIRECTORY_MOVIES + "/WhatsApp Status")
            } else {
                put(MediaStore.Images.Media.DISPLAY_NAME, fileName)
                put(MediaStore.Images.Media.MIME_TYPE, getMimeType(fileName))
                put(MediaStore.Images.Media.RELATIVE_PATH, Environment.DIRECTORY_PICTURES + "/WhatsApp Status")
            }
        }

        val contentResolver = applicationContext.contentResolver
        val collection = if (type == "video") {
            MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        } else {
            MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        }

        val uri = contentResolver.insert(collection, contentValues)
            ?: throw Exception("Failed to create media file")

        try {
            val inputStream: InputStream = FileInputStream(sourceFile)
            val outputStream: OutputStream? = contentResolver.openOutputStream(uri)
            
            if (outputStream == null) {
                throw Exception("Failed to open output stream")
            }

            inputStream.use { input ->
                outputStream.use { output ->
                    input.copyTo(output)
                }
            }

            // Notify media scanner
            val mediaScanIntent = Intent(Intent.ACTION_MEDIA_SCANNER_SCAN_FILE)
            mediaScanIntent.data = uri
            applicationContext.sendBroadcast(mediaScanIntent)

            return "Downloaded successfully to gallery"
        } catch (e: Exception) {
            // Delete the created entry if copy failed
            contentResolver.delete(uri, null, null)
            throw Exception("Failed to copy file: ${e.message}")
        }
    }

    private fun getMimeType(fileName: String): String {
        return StatusAccessHelper.getMimeType(fileName)
    }
}


