package com.whatsappstatus.downloader

import android.content.Context
import android.net.Uri
import android.util.Log
import androidx.documentfile.provider.DocumentFile

object StatusAccessHelper {
    private const val TAG = "StatusAccessHelper"
    private const val WRONG_FOLDER_MESSAGE_PREFIX =
        "SELECT_WHATSAPP_STATUSES_FOLDER: Selected folder does not contain the WhatsApp .Statuses folder."

    fun getStatusFiles(context: Context, treeUri: Uri): List<StatusFileInfo> {
        val statusFiles = mutableListOf<StatusFileInfo>()

        try {
            val root = DocumentFile.fromTreeUri(context, treeUri)
                ?: throw IllegalStateException(WRONG_FOLDER_MESSAGE_PREFIX)

            // If user picked the .Statuses folder directly, use it.
            val statusesDir: DocumentFile? = when {
                root.isDirectory && (root.name == ".Statuses") -> root
                else -> {
                    // If user picked a parent (e.g. Media or WhatsApp), try to find .Statuses under it.
                    root.listFiles().firstOrNull { dir ->
                        dir.isDirectory && dir.name == ".Statuses"
                    }
                }
            }

            if (statusesDir == null) {
                // This folder cannot lead to .Statuses – signal this explicitly.
                throw IllegalStateException(WRONG_FOLDER_MESSAGE_PREFIX)
            }

            statusesDir.listFiles().forEach { docFile ->
                if (docFile.isFile && isValidStatusFile(docFile)) {
                    val name = docFile.name ?: "status"
                    val mimeType = docFile.type ?: getMimeTypeFromName(name)
                    statusFiles.add(
                        StatusFileInfo(
                            uri = docFile.uri,
                            name = name,
                            mimeType = mimeType,
                            size = docFile.length(),
                            lastModified = docFile.lastModified()
                        )
                    )
                }
            }
        } catch (e: SecurityException) {
            Log.e(TAG, "Security exception accessing status folder", e)
            throw e
        } catch (e: IllegalStateException) {
            Log.e(TAG, "Invalid status folder selection", e)
            throw e
        } catch (e: Exception) {
            Log.e(TAG, "Error accessing status folder", e)
            throw e
        }

        // Sort by last modified (newest first)
        statusFiles.sortByDescending { it.lastModified }
        
        return statusFiles
    }

    private fun isValidStatusFile(file: DocumentFile): Boolean {
        val mime = file.type ?: ""
        if (mime.startsWith("image/") || mime.startsWith("video/")) {
            return true
        }

        val name = file.name?.lowercase() ?: return false
        return name.endsWith(".jpg") ||
                name.endsWith(".jpeg") ||
                name.endsWith(".png") ||
                name.endsWith(".mp4") ||
                name.endsWith(".gif")
    }

    private fun getMimeTypeFromName(fileName: String): String {
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
    val name: String,
    val mimeType: String,
    val size: Long,
    val lastModified: Long,
    val uri: Uri
)


