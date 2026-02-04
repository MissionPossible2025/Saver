package com.whatsappstatus.downloader

import android.content.ContentValues
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.Environment
import android.provider.MediaStore
import android.provider.DocumentsContract
import android.util.Log
import androidx.annotation.NonNull
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.InputStream
import java.io.OutputStream
import java.io.ByteArrayOutputStream

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.whatsappstatus.downloader/channel"
    private val TAG = "StatusDownloader"
    private val PREFS_NAME = "status_downloader_prefs"
    private val KEY_TREE_URI = "tree_uri"
    private val KEY_APP_VERSION = "app_version"
    private val REQUEST_CODE_FOLDER_ACCESS = 1001
    
    private var folderAccessResult: MethodChannel.Result? = null
    
    private val prefs: SharedPreferences by lazy {
        getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
    }
    
    private fun getAppVersion(): Int {
        return try {
            val packageInfo = packageManager.getPackageInfo(packageName, 0)
            // Use longVersionCode for API 28+, fallback to versionCode for older versions
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
                packageInfo.longVersionCode.toInt()
            } else {
                @Suppress("DEPRECATION")
                packageInfo.versionCode
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error getting app version", e)
            0
        }
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
                    val currentVersion = getAppVersion()
                    val savedVersion = prefs.getInt(KEY_APP_VERSION, -1)
                    
                    // If version doesn't match, this is a fresh install - clear everything
                    if (savedVersion != currentVersion) {
                        Log.d(TAG, "App version changed or fresh install - clearing permissions")
                        prefs.edit().clear().apply()
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    
                    val treeUriString = prefs.getString(KEY_TREE_URI, null)
                    if (treeUriString == null) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    
                    // Verify the permission is actually still valid
                    // After uninstall/reinstall, the URI might exist but permission is lost
                    try {
                        val treeUri = Uri.parse(treeUriString)
                        val persistedUriPermissions = contentResolver.persistedUriPermissions
                        val hasValidPermission = persistedUriPermissions.any { 
                            it.uri == treeUri && it.isReadPermission 
                        }
                        
                        // Also verify we can actually access the folder
                        if (hasValidPermission) {
                            val documentFile = DocumentFile.fromTreeUri(applicationContext, treeUri)
                            if (documentFile != null && documentFile.exists()) {
                                result.success(true)
                            } else {
                                // Permission exists but folder is not accessible - clear it
                                Log.d(TAG, "Permission exists but folder not accessible - clearing")
                                prefs.edit().remove(KEY_TREE_URI).apply()
                                result.success(false)
                            }
                        } else {
                            // Permission was revoked or app was reinstalled - clear it
                            Log.d(TAG, "Permission not found in system - clearing")
                            prefs.edit().remove(KEY_TREE_URI).apply()
                            result.success(false)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Error checking permission validity", e)
                        // Clear invalid permission
                        prefs.edit().remove(KEY_TREE_URI).apply()
                        result.success(false)
                    }
                }
                "requestStatusFolderAccess" -> {
                    folderAccessResult = result
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
                    // Force the picker to start at a neutral location instead of re-opening
                    // the previously used folder from system memory.
                    // This makes the experience match a first-time launch on reinstall.
                    try {
                        val initialUri = Uri.parse("content://com.android.externalstorage.documents/root/primary")
                        intent.putExtra(DocumentsContract.EXTRA_INITIAL_URI, initialUri)
                    } catch (e: Exception) {
                        Log.w(TAG, "Failed to set initial picker location", e)
                    }
                    startActivityForResult(intent, REQUEST_CODE_FOLDER_ACCESS)
                }
                "readFileBytes" -> {
                    try {
                        val uriString = call.argument<String>("uri") ?: ""
                        val uri = Uri.parse(uriString)
                        val inputStream: InputStream? = contentResolver.openInputStream(uri)
                        if (inputStream == null) {
                            result.error("ERROR", "Failed to open file", null)
                            return@setMethodCallHandler
                        }
                        val outputStream = ByteArrayOutputStream()
                        inputStream.use { input ->
                            input.copyTo(outputStream)
                        }
                        result.success(outputStream.toByteArray())
                    } catch (e: Exception) {
                        Log.e(TAG, "Error reading file bytes", e)
                        result.error("ERROR", "Failed to read file: ${e.message}", null)
                    }
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
                    try {
                        // Take persistent permission (lightweight operation)
                        // This must be done synchronously while we have the result
                        contentResolver.takePersistableUriPermission(
                            treeUri,
                            Intent.FLAG_GRANT_READ_URI_PERMISSION
                        )
                        
                        // Save the URI and app version (lightweight operation)
                        // Use commit() instead of apply() to ensure it's saved immediately
                        val currentVersion = getAppVersion()
                        prefs.edit()
                            .putString(KEY_TREE_URI, treeUri.toString())
                            .putInt(KEY_APP_VERSION, currentVersion)
                            .commit()
                        
                        // Return success immediately - let Flutter handle timing
                        // Do NOT perform ANY file operations here - it will crash during Activity recreation
                        // Flutter will handle file scanning after app lifecycle resumes
                        result?.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error handling SAF result", e)
                        result?.error("ERROR", "Failed to save permission: ${e.message}", null)
                    }
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


