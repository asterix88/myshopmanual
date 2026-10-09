package com.tracksection.mymanual

import android.annotation.TargetApi
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ActivityNotFoundException
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import java.io.File

/** Copies downloaded manuals to the phone's Download/MyManual folder, where
 *  File Manager and other apps can see them. Android 10 and newer only (no
 *  storage permission needed there); older phones don't get the button. */
// Every MediaStore call below runs only when [supported] (Android 10+).
@TargetApi(Build.VERSION_CODES.Q)
object PublicDownloads {
    private const val FOLDER = "MyManual"
    private const val CHANNEL = "saves"
    private const val NOTIFICATION = 7302

    val supported get() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q

    /** The saved copy named [name], or null when there is none (never saved,
     *  or deleted from the Download folder since). */
    fun find(context: Context, name: String): Uri? {
        if (!supported) return null
        // Match on the name only and check the folder here: phones differ in
        // how they store RELATIVE_PATH, and an exact match missed saved copies.
        val collection = MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL)
        context.contentResolver.query(
            collection,
            arrayOf(MediaStore.MediaColumns._ID, MediaStore.MediaColumns.RELATIVE_PATH, MediaStore.MediaColumns.IS_PENDING),
            "${MediaStore.MediaColumns.DISPLAY_NAME} = ?",
            arrayOf(name),
            null,
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                val path = cursor.getString(1)?.trim('/')?.lowercase() ?: ""
                if (cursor.getInt(2) == 0 && path.endsWith("/${FOLDER.lowercase()}")) {
                    return Uri.withAppendedPath(collection, cursor.getLong(0).toString())
                }
            }
        }
        return null
    }

    /** Whether the copy is there: in MediaStore, or as a plain file. */
    fun exists(context: Context, name: String): Boolean {
        if (!supported) return false
        if (find(context, name) != null) return true
        @Suppress("DEPRECATION")
        val dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        return try {
            File(File(dir, FOLDER), name).exists()
        } catch (e: SecurityException) {
            false
        }
    }

    /** Copies [source] in the background, with a progress notification, then
     *  calls [done] on the main thread with null or an error message. */
    fun save(context: Context, source: String, name: String, done: (String?) -> Unit) {
        val app = context.applicationContext
        val main = Handler(Looper.getMainLooper())
        Thread {
            val error = try {
                copy(app, File(source), name)
                null
            } catch (e: Exception) {
                e.message ?: e.toString()
            }
            notifyDone(app, name, error)
            main.post { done(error) }
        }.start()
    }

    private fun copy(context: Context, source: File, name: String) {
        if (!supported) throw IllegalStateException("Butuh Android 10 atau lebih baru")
        val total = source.length()
        val resolver = context.contentResolver
        find(context, name)?.let { resolver.delete(it, null, null) }
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, "application/pdf")
            put(MediaStore.MediaColumns.RELATIVE_PATH, "${Environment.DIRECTORY_DOWNLOADS}/$FOLDER/")
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = resolver.insert(MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL), values)
            ?: throw IllegalStateException("Folder Download tidak bisa ditulis")
        try {
            resolver.openOutputStream(uri)!!.use { out -> pump(context, source, out, name, total) }
            resolver.update(uri, ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }, null, null)
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            throw e
        }
    }

    private fun pump(context: Context, source: File, out: java.io.OutputStream, name: String, total: Long) {
        val buffer = ByteArray(1 shl 20)
        var copied = 0L
        var lastPercent = -1
        source.inputStream().use { input ->
            while (true) {
                val n = input.read(buffer)
                if (n < 0) break
                out.write(buffer, 0, n)
                copied += n
                val percent = if (total > 0) (copied * 100 / total).toInt() else 0
                if (percent != lastPercent) {
                    lastPercent = percent
                    notifyProgress(context, name, percent)
                }
            }
        }
    }

    /** Opens the saved copy in another app (a PDF reader). */
    fun open(context: Context, name: String): Boolean {
        val uri = find(context, name) ?: return false
        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, "application/pdf")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            context.startActivity(intent)
            true
        } catch (e: ActivityNotFoundException) {
            false
        }
    }

    private fun builder(context: Context): Notification.Builder {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(NotificationChannel(CHANNEL, "Simpan ke Download", NotificationManager.IMPORTANCE_LOW))
            Notification.Builder(context, CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }.setSmallIcon(R.drawable.ic_notification)
    }

    private fun notifyProgress(context: Context, name: String, percent: Int) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(
            NOTIFICATION,
            builder(context)
                .setContentTitle("Menyimpan ke Download…")
                .setContentText(name)
                .setProgress(100, percent, false)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .build(),
        )
    }

    private fun notifyDone(context: Context, name: String, error: String?) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (error == null) {
            manager.notify(
                NOTIFICATION,
                builder(context)
                    .setContentTitle("Tersimpan di Download/$FOLDER")
                    .setContentText(name)
                    .setAutoCancel(true)
                    .build(),
            )
        } else {
            manager.cancel(NOTIFICATION)
        }
    }
}
