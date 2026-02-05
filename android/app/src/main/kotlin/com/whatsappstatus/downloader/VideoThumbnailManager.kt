package com.whatsappstatus.downloader

import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.Future

/**
 * Video thumbnail pipeline:
 * - Never runs on main thread (fixed executor pool).
 * - Visibility-based: Flutter requests per-visible item.
 * - Cancellation: Flutter cancels when item goes off-screen.
 * - Concurrency limit: fixed thread pool size 2.
 * - Aggressive cache: cacheDir/video_thumbs/<sha256(uri|lastModified)>.jpg
 * - Refresh deferral: notifyRefresh() pauses new work; requests are started after 300ms via Handler.
 */
object VideoThumbnailManager {
    private const val TAG = "VideoThumbnailManager"

    // Max 2 concurrent thumbnail decodes (CPU + IO heavy)
    private val executor = Executors.newFixedThreadPool(2)

    private val mainHandler = Handler(Looper.getMainLooper())

    // Pause window after refresh (milliseconds, uptime clock)
    @Volatile
    private var pausedUntilUptimeMs: Long = 0L

    // Track in-flight work and request ownership
    private val jobByKey: ConcurrentHashMap<String, Future<*>> = ConcurrentHashMap()
    private val requestIdsByKey: ConcurrentHashMap<String, MutableSet<String>> = ConcurrentHashMap()
    private val keyByRequestId: ConcurrentHashMap<String, String> = ConcurrentHashMap()

    fun notifyRefresh() {
        // Requirement: use Handler(...) postDelayed to defer thumbnail jobs by 300ms.
        pausedUntilUptimeMs = SystemClock.uptimeMillis() + 300L
        mainHandler.postDelayed({
            // no-op: the pause window elapses; requests will proceed when scheduled.
        }, 300L)
    }

    /**
     * Synchronous cache check for UI build.
     * Returns cached thumbnail path if exists, null otherwise.
     * This is fast file existence check - safe to call on main thread.
     */
    fun checkCacheSync(context: Context, uriString: String, lastModified: Long): String? {
        val key = cacheKey(uriString, lastModified)
        val cached = cachedFile(context, key)
        return if (cached.exists() && cached.length() > 0) {
            cached.absolutePath
        } else {
            null
        }
    }

    fun cancel(requestId: String) {
        val key = keyByRequestId.remove(requestId) ?: return
        val set = requestIdsByKey[key]
        if (set != null) {
            synchronized(set) {
                set.remove(requestId)
                if (set.isEmpty()) {
                    requestIdsByKey.remove(key)
                    jobByKey.remove(key)?.cancel(true)
                }
            }
        }
    }

    fun getOrCreateThumbnailAsync(
        context: Context,
        requestId: String,
        uriString: String,
        lastModified: Long,
        maxWidth: Int = 250,
        jpegQuality: Int = 60,
        onResult: (String?) -> Unit,
    ) {
        val uri = Uri.parse(uriString)
        val key = cacheKey(uriString, lastModified)

        keyByRequestId[requestId] = key
        val owners = requestIdsByKey.getOrPut(key) { mutableSetOf() }
        synchronized(owners) { owners.add(requestId) }

        // Cache check is cheap IO; do it before any job scheduling
        val cached = cachedFile(context, key)
        if (cached.exists() && cached.length() > 0) {
            onResult(cached.absolutePath)
            return
        }

        // If a job is already running for this key, don't enqueue another one.
        val existing = jobByKey[key]
        if (existing != null && !existing.isDone) {
            // When the existing job finishes, Flutter will re-request when visible again,
            // or the cached file will be hit next time.
            // We still try to deliver quickly by polling cache shortly.
            scheduleCachePoll(context, requestId, key, onResult)
            return
        }

        val delayMs = remainingPauseMs()
        if (delayMs > 0) {
            mainHandler.postDelayed(
                { startJob(context, requestId, uri, key, maxWidth, jpegQuality, onResult) },
                delayMs
            )
        } else {
            startJob(context, requestId, uri, key, maxWidth, jpegQuality, onResult)
        }
    }

    private fun startJob(
        context: Context,
        requestId: String,
        uri: Uri,
        key: String,
        maxWidth: Int,
        jpegQuality: Int,
        onResult: (String?) -> Unit,
    ) {
        // If request was cancelled before the job started, skip.
        if (keyByRequestId[requestId] != key) return

        // Double-check cache (might have been created in the meantime)
        val cached = cachedFile(context, key)
        if (cached.exists() && cached.length() > 0) {
            onResult(cached.absolutePath)
            return
        }

        val future = executor.submit {
            // Heavy work ONLY here (background threads)
            val path = try {
                generateThumbnailToCache(context, uri, key, maxWidth, jpegQuality)
            } catch (t: Throwable) {
                Log.e(TAG, "Thumbnail generation failed", t)
                null
            }

            // Deliver only if request still owned (not cancelled)
            if (keyByRequestId[requestId] == key) {
                mainHandler.post { onResult(path) }
            }

            // Cleanup job tracking
            jobByKey.remove(key)
        }

        jobByKey[key] = future
    }

    private fun scheduleCachePoll(
        context: Context,
        requestId: String,
        key: String,
        onResult: (String?) -> Unit
    ) {
        // Very light: re-check cache after a short delay; avoids waiting on job hooks
        mainHandler.postDelayed({
            if (keyByRequestId[requestId] != key) return@postDelayed
            val cached = cachedFile(context, key)
            if (cached.exists() && cached.length() > 0) {
                onResult(cached.absolutePath)
            }
        }, 120L)
    }

    private fun remainingPauseMs(): Long {
        val now = SystemClock.uptimeMillis()
        val until = pausedUntilUptimeMs
        return if (until > now) (until - now) else 0L
    }

    private fun cachedFile(context: Context, key: String): File {
        val dir = File(context.cacheDir, "video_thumbs")
        if (!dir.exists()) dir.mkdirs()
        return File(dir, "$key.jpg")
    }

    private fun cacheKey(uri: String, lastModified: Long): String {
        val raw = "$uri|$lastModified"
        val digest = MessageDigest.getInstance("SHA-256").digest(raw.toByteArray(Charsets.UTF_8))
        return digest.joinToString("") { b -> "%02x".format(b) }
    }

    private fun generateThumbnailToCache(
        context: Context,
        uri: Uri,
        key: String,
        maxWidth: Int,
        jpegQuality: Int
    ): String? {
        val outFile = cachedFile(context, key)
        val tmpFile = File(outFile.parentFile, "${outFile.name}.tmp")

        if (outFile.exists() && outFile.length() > 0) return outFile.absolutePath

        val retriever = MediaMetadataRetriever()
        var frame: Bitmap? = null
        var scaled: Bitmap? = null
        try {
            if (Thread.currentThread().isInterrupted) return null

            // SAF/content URI friendly: use FileDescriptor where possible
            val pfd = context.contentResolver.openFileDescriptor(uri, "r") ?: return null
            pfd.use {
                retriever.setDataSource(it.fileDescriptor)
            }

            if (Thread.currentThread().isInterrupted) return null

            frame = retriever.getFrameAtTime(0, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                ?: return null

            if (Thread.currentThread().isInterrupted) return null

            scaled = if (frame!!.width > maxWidth) {
                val h = (frame!!.height * (maxWidth.toFloat() / frame!!.width.toFloat())).toInt().coerceAtLeast(1)
                Bitmap.createScaledBitmap(frame!!, maxWidth, h, true)
            } else {
                frame
            }

            FileOutputStream(tmpFile).use { fos ->
                scaled!!.compress(Bitmap.CompressFormat.JPEG, jpegQuality, fos)
                fos.flush()
            }

            // Atomic-ish replace
            if (outFile.exists()) outFile.delete()
            if (!tmpFile.renameTo(outFile)) {
                // fallback copy
                tmpFile.copyTo(outFile, overwrite = true)
                tmpFile.delete()
            }

            return outFile.absolutePath
        } catch (t: Throwable) {
            try { tmpFile.delete() } catch (_: Throwable) {}
            return null
        } finally {
            try { retriever.release() } catch (_: Throwable) {}
            try { if (scaled != null && scaled !== frame) scaled!!.recycle() } catch (_: Throwable) {}
            try { frame?.recycle() } catch (_: Throwable) {}
        }
    }
}


