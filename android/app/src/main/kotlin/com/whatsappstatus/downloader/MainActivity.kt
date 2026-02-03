package com.whatsappstatus.downloader

import android.content.ContentValues
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.Environment
import android.provider.MediaStore
import android.util.Log
import androidx.annotation.NonNull
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.InputStream
import java.io.OutputStream

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.whatsappstatus.downloader/channel"
    private val TAG = "StatusDownloader"
    private val PREFS_NAME = "status_downloader_prefs"
    private val KEY_TREE_URI = "tree_uri"
    private val REQUEST_CODE_FOLDER_ACCESS = 1001
    
    private var folderAccessResult: MethodChannel.Result? = null
    
    private val prefs: SharedPreferences by lazy {
        getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getStatusFiles" -> {
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
                        val uriString = call.argument<String>("uri") ?: ""
                        val name = call.argument<String>("name") ?: ""
                        val mimeType = call.argument<String>("mimeType") ?: ""
                        val message = downloadToGallery(uriString, name, mimeType)
                        result.success(message)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error downloading status", e)
                        result.error("ERROR", "Failed to download: ${e.message}", null)
                    }
                }
                "hasPersistedPermission" -> {
                    val treeUriString = prefs.getString(KEY_TREE_URI, null)
                    result.success(treeUriString != null)
                }
                "requestStatusFolderAccess" -> {
                    folderAccessResult = result
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
                    startActivityForResult(intent, REQUEST_CODE_FOLDER_ACCESS)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
    
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        
        if (requestCode == REQUEST_CODE_FOLDER_ACCESS) {
            val result = folderAccessResult
            folderAccessResult = null
            
            if (resultCode == RESULT_OK && data != null) {
                val treeUri = data.data
                if (treeUri != null) {
                    // Take persistent permission
                    contentResolver.takePersistableUriPermission(
                        treeUri,
                        Intent.FLAG_GRANT_READ_URI_PERMISSION
                    )
                    
                    // Save the URI
                    prefs.edit().putString(KEY_TREE_URI, treeUri.toString()).apply()
                    result?.success(true)
                } else {
                    result?.success(false)
                }
            } else {
                result?.success(false)
            }
        }
    }

    private fun getWhatsAppStatusItems(): List<Map<String, Any>> {
        val treeUriString = prefs.getString(KEY_TREE_URI, null)
            ?: throw Exception("No folder access granted. Please select the WhatsApp Status folder.")
        
        val treeUri = Uri.parse(treeUriString)
        val statusFiles = StatusAccessHelper.getStatusFiles(applicationContext, treeUri)
        return statusFiles.map { file ->
            mapOf(
                "uri" to file.uri.toString(),
                "name" to file.name,
                "mimeType" to file.mimeType,
                "size" to file.size,
                "lastModified" to file.lastModified
            )
        }
    }

    private fun downloadToGallery(uriString: String, fileName: String, mimeType: String): String {
        val sourceUri = Uri.parse(uriString)
        val isVideo = mimeType.startsWith("video/")

        val contentValues = ContentValues().apply {
            if (isVideo) {
                put(MediaStore.Video.Media.DISPLAY_NAME, fileName)
                put(MediaStore.Video.Media.MIME_TYPE, mimeType)
                put(MediaStore.Video.Media.RELATIVE_PATH, Environment.DIRECTORY_MOVIES + "/WhatsApp Status")
            } else {
                put(MediaStore.Images.Media.DISPLAY_NAME, fileName)
                put(MediaStore.Images.Media.MIME_TYPE, mimeType)
                put(MediaStore.Images.Media.RELATIVE_PATH, Environment.DIRECTORY_PICTURES + "/WhatsApp Status")
            }
        }

        val contentResolver = applicationContext.contentResolver
        val collection = if (isVideo) {
            MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        } else {
            MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        }

        val destinationUri = contentResolver.insert(collection, contentValues)
            ?: throw Exception("Failed to create media file")

        try {
            val inputStream: InputStream? = contentResolver.openInputStream(sourceUri)
            if (inputStream == null) {
                throw Exception("Failed to open source file")
            }
            
            val outputStream: OutputStream? = contentResolver.openOutputStream(destinationUri)
            if (outputStream == null) {
                inputStream.close()
                throw Exception("Failed to open output stream")
            }

            inputStream.use { input ->
                outputStream.use { output ->
                    input.copyTo(output)
                }
            }

            // MediaStore.insert() automatically triggers media scanner on Android 10+
            // For older versions, we can use MediaScannerConnection if needed
            return "Downloaded successfully to gallery"
        } catch (e: Exception) {
            // Delete the created entry if copy failed
            contentResolver.delete(destinationUri, null, null)
            throw Exception("Failed to copy file: ${e.message}")
        }
    }
}


