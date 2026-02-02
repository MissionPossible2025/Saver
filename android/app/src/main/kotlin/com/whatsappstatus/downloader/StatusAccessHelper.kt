package com.whatsappstatus.downloader

import android.content.ContentResolver
import android.content.ContentUris
import android.content.Context
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.util.Log
import java.io.File

object StatusAccessHelper {
    private const val TAG = "StatusAccessHelper"
    
    // WhatsApp status directory paths
    private val STATUS_PATHS = listOf(
        File(Environment.getExternalStorageDirectory(), "WhatsApp/Media/.Statuses"),
        File(Environment.getExternalStorageDirectory(), "Android/media/com.whatsapp/WhatsApp/Media/.Statuses")
    )

    fun getStatusFiles(): List<StatusFileInfo> {
        val statusFiles = mutableListOf<StatusFileInfo>()

        for (statusPath in STATUS_PATHS) {
            if (statusPath.exists() && statusPath.isDirectory) {
                try {
                    val files = statusPath.listFiles()
                    files?.forEach { file ->
                        if (file.isFile && isValidStatusFile(file)) {
                            val type = getFileType(file.name)
                            statusFiles.add(
                                StatusFileInfo(
                                    path = file.absolutePath,
                                    name = file.name,
                                    type = type,
                                    size = file.length(),
                                    lastModified = file.lastModified(),
                                    uri = null
                                )
                            )
                        }
                    }
                } catch (e: SecurityException) {
                    Log.e(TAG, "Security exception accessing ${statusPath.absolutePath}", e)
                } catch (e: Exception) {
                    Log.e(TAG, "Error accessing ${statusPath.absolutePath}", e)
                }
            }
        }

        // Sort by last modified (newest first)
        statusFiles.sortByDescending { it.lastModified }
        
        return statusFiles
    }

    private fun isValidStatusFile(file: File): Boolean {
        val name = file.name.lowercase()
        return name.endsWith(".jpg") ||
                name.endsWith(".jpeg") ||
                name.endsWith(".png") ||
                name.endsWith(".mp4") ||
                name.endsWith(".gif")
    }

    private fun getFileType(fileName: String): String {
        val name = fileName.lowercase()
        return when {
            name.endsWith(".mp4") -> "video"
            else -> "image"
        }
    }

    fun getMimeType(fileName: String): String {
        val name = fileName.lowercase()
        return when {
            name.endsWith(".jpg") || name.endsWith(".jpeg") -> "image/jpeg"
            name.endsWith(".png") -> "image/png"
            name.endsWith(".gif") -> "image/gif"
            name.endsWith(".mp4") -> "video/mp4"
            else -> "application/octet-stream"
        }
    }
}

data class StatusFileInfo(
    val path: String,
    val name: String,
    val type: String,
    val size: Long,
    val lastModified: Long,
    val uri: Uri?
)


