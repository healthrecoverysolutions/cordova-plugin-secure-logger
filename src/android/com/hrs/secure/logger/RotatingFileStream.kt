package com.hrs.secure.logger

import android.content.Context
import androidx.security.crypto.EncryptedFile
import androidx.security.crypto.MasterKey
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream

private const val LOG_FILE_NAME_PREFIX = "SCR-LOG-V"
private const val LOG_FILE_NAME_EXTENSION = ".log"
private const val RFS_SERIALIZER_VERSION = 1

data class RotatingFileStreamOptions(
    val outputDir: File,
    var maxFileSizeBytes: Long = 2 * 1000 * 1000, // 2MB
    var maxTotalCacheSizeBytes: Long = 7 * 1000 * 1000, // 8MB
    var maxFileCount: Long = 20
)

class RotatingFileStream(
    private val mContext: Context,
    private val mOptions: RotatingFileStreamOptions
) {
    private val mLock = Any()

    private val mMasterKey = MasterKey.Builder(mContext)
        .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
        .build()

    private var mActiveFile: File? = null
    private var mActiveStream: FileOutputStream? = null
    private var mDestroyed: Boolean = false

    private val output: File
        get() = mOptions.outputDir

    private val maxFileSize: Long
        get() = mOptions.maxFileSizeBytes

    private val maxFileCount: Long
        get() = mOptions.maxFileCount

    private val maxCacheSize: Long
        get() = mOptions.maxTotalCacheSizeBytes

    fun destroy() {
        mDestroyed = true
        closeActiveStream()
    }

    @Throws(
        java.io.IOException::class,
        java.lang.SecurityException::class,
        java.security.GeneralSecurityException::class
    )
    fun appendLine(text: String) {
        if (!mDestroyed && text.isNotEmpty()) {
            append(text + "\n")
        }
    }

    @Throws(java.lang.SecurityException::class)
    fun deleteAllFiles(): Boolean {
        synchronized(mLock) {
            return !mDestroyed && output.deleteRecursively() && output.mkdirs()
        }
    }

    @Throws(
        java.io.IOException::class,
        java.lang.SecurityException::class,
        java.security.GeneralSecurityException::class
    )
    fun append(text: String) {
        synchronized(mLock) {
            if (!mDestroyed && text.isNotEmpty()) {
                val stream = loadActiveStream()
                stream.write(text.toByteArray())
                stream.flush()
            }
        }
    }

    @Throws(
        java.io.IOException::class,
        java.security.GeneralSecurityException::class
    )
    fun toBlob(): ByteArray? {
        synchronized(mLock) {

            if (mDestroyed) {
                return null;
            }

            // Data at the end of the file will be partially corrupted if
            // the stream is not shut down, so need to close it before we can read it
            closeActiveStream()

            val files: Array<File> = output.listFiles() ?: arrayOf()
            val outputStream = ByteArrayOutputStream()

            if (files.isEmpty()) {
                return outputStream.toByteArray()
            }

            files.sortWith { a, b -> a.name.compareTo(b.name) }
            var readStream: FileInputStream? = null

            for (file in files) {
                try {
                    readStream = openReadStream(file)
                    readStream.pipeTo(outputStream)
                } catch (ex: Exception) {
                    val errorMessage = "\n\n[[FILE DECRYPT FAILURE - " +
                        "${file.name} (${file.length()} bytes)]]\n<<<<<<<<<<<<<<<<\n" +
                        ex.message +
                        "\n>>>>>>>>>>>>>>>>\n\n"
                    outputStream.write(errorMessage.toByteArray())
                } finally {
                    readStream?.close()
                }
            }

            return outputStream.toByteArray()
        }
    }

    private fun generateArchiveFileName(): String {
        // Generates a unique name like "SCR-LOG-V1-1698079640670.log"
        return LOG_FILE_NAME_PREFIX +
            RFS_SERIALIZER_VERSION +
            "-" +
            currentTimeMillis() +
            LOG_FILE_NAME_EXTENSION
    }

    @Throws(
        java.io.IOException::class,
        java.security.GeneralSecurityException::class
    )
    private fun openReadStream(file: File): FileInputStream {
        return wrapEncryptedFile(file).openFileInput()
    }

    @Throws(
        java.io.IOException::class,
        java.security.GeneralSecurityException::class
    )
    private fun openWriteStream(file: File): FileOutputStream {
        return wrapEncryptedFile(file).openFileOutput()
    }

    @Throws(
        java.io.IOException::class,
        java.security.GeneralSecurityException::class
    )
    private fun wrapEncryptedFile(file: File): EncryptedFile {
        return EncryptedFile.Builder(
            mContext,
            file,
            mMasterKey,
            EncryptedFile.FileEncryptionScheme.AES256_GCM_HKDF_4KB
        ).build()
    }

    @Throws(java.io.IOException::class)
    private fun closeActiveStream() {
        synchronized(mLock) {
            if (mActiveStream != null) {
                mActiveStream!!.flush()
                mActiveStream!!.close()
                mActiveStream = null
            }
        }
    }

    @Throws(
        java.io.IOException::class,
        java.lang.SecurityException::class,
        java.security.GeneralSecurityException::class
    )
    private fun loadActiveStream(): FileOutputStream {
        if (mActiveStream != null
            && mActiveFile != null
            && mActiveFile!!.exists()
            && mActiveFile!!.length() < maxFileSize)
            return mActiveStream!!

        normalizeFileCache()

        return createNewStream()
    }

    @Throws(
        java.io.IOException::class,
        java.lang.SecurityException::class,
        java.security.GeneralSecurityException::class
    )
    private fun createNewStream(): FileOutputStream {
        closeActiveStream()

        mActiveFile = File(output.path, generateArchiveFileName())

        if (mActiveFile!!.exists())
            mActiveFile!!.delete()

        mActiveStream = openWriteStream(mActiveFile!!)

        return mActiveStream!!
    }

    @Throws(
        java.io.IOException::class,
        java.lang.SecurityException::class
    )
    private fun normalizeFileCache() {
        if (!output.exists())
            output.mkdirs()

        if (mActiveFile != null
            && mActiveFile!!.exists()
            && mActiveFile!!.length() >= maxFileSize) {
            closeActiveStream()
        }

        val files: MutableList<File> = output
            .listFiles()
            ?.filter { f: File? -> (f != null) && f.exists() && f.isFile }
            ?.toMutableList()
            ?: mutableListOf()

        files.sortWith { a, b -> a.name.compareTo(b.name) }

        // TODO: may want to try consolidating log files together
        //      before deletion to avoid unnecessary data loss.

        while (files.isNotEmpty() && files.size > maxFileCount) {
            files[0].delete()
            files.removeAt(0)
        }

        var totalFileSize = files.sumOf { it.length() }

        while (files.isNotEmpty() && totalFileSize > maxCacheSize) {
            totalFileSize -= files[0].length()
            files[0].delete()
            files.removeAt(0)
        }
    }
}
