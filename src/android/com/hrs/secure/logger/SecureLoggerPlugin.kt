package com.hrs.secure.logger

import org.apache.cordova.BuildConfig
import org.apache.cordova.CallbackContext
import org.apache.cordova.CordovaPlugin
import org.json.JSONArray
import org.json.JSONObject
import timber.log.Timber
import java.io.File
import java.lang.Thread.UncaughtExceptionHandler

private const val LOG_DIR = "logs"

class SecureLoggerPlugin : CordovaPlugin(), UncaughtExceptionHandler {
    private lateinit var rotatingFileStream: RotatingFileStream
    private lateinit var timberFileProxy: TimberFileProxy
    private var defaultExceptionHandler: UncaughtExceptionHandler? = null
    private var timberDebug: Timber.DebugTree? = null

    override fun pluginInitialize() {
        if (BuildConfig.DEBUG) {
            timberDebug = Timber.DebugTree()
            Timber.plant(timberDebug!!)
        }

        val logDir = File(cordova.context.cacheDir.path, LOG_DIR)
        val streamOptions = RotatingFileStreamOptions(logDir)

        defaultExceptionHandler = Thread.getDefaultUncaughtExceptionHandler()
        rotatingFileStream = RotatingFileStream(cordova.context, streamOptions)
        timberFileProxy = TimberFileProxy(rotatingFileStream)

        Timber.plant(timberFileProxy)
        Thread.setDefaultUncaughtExceptionHandler(this)
    }

    override fun uncaughtException(t: Thread, e: Throwable) {
        Timber.e("Uncaught Native Error!", e)
        defaultExceptionHandler?.uncaughtException(t, e)
    }

    override fun onDestroy() {
        Timber.uproot(timberFileProxy)

        if (timberDebug != null)
            Timber.uproot(timberDebug!!)

        rotatingFileStream.destroy()
    }

    override fun execute(action: String, args: JSONArray, callbackContext: CallbackContext): Boolean {
        Timber.v("execute action '$action'")
        when (action) {
            "capture" -> {
                cordova.threadPool.execute {
                    try {
                        val eventList = args.optJSONArray(0)
                        captureLogEvents(eventList)
                        callbackContext.success()
                    } catch (ex: Exception) {
                        Timber.e("failed plugin action '$action' -> ${ex.message}")
                        callbackContext.error(ex.message)
                    }
                }
            }
            "captureText" -> {
                cordova.threadPool.execute {
                    try {
                        val text = args.optString(0, "")
                        rotatingFileStream.append(text)
                        callbackContext.success()
                    } catch (ex: Exception) {
                        Timber.e("failed plugin action '$action' -> ${ex.message}")
                        callbackContext.error(ex.message)
                    }
                }
            }
            "clearCache" -> {
                cordova.threadPool.execute {
                    try {
                        val success = rotatingFileStream.deleteAllFiles()
                        callbackContext.success(success.toString())
                    } catch (ex: Exception) {
                        Timber.e("failed plugin action '$action' -> ${ex.message}")
                        callbackContext.error(ex.message)
                    }
                }
            }
            "getCacheBlob" -> {
                cordova.threadPool.execute {
                    try {
                        val combinedBytes = rotatingFileStream.toBlob()
                        if (combinedBytes != null) {
                            callbackContext.success(combinedBytes)
                        } else {
                            callbackContext.error("cannot fetch cache blob after app destroy")
                        }
                    } catch (ex: Exception) {
                        Timber.e("failed plugin action '$action' -> ${ex.message}")
                        callbackContext.error(ex.message)
                    }
                }
            }
            else -> {
                Timber.w("rejecting unsupported action '$action'")
                callbackContext.error("Action $action is not implemented in SecureLoggerPlugin.")
                return false
            }
        }
        return true
    }

    private fun captureLogEvents(events: JSONArray?) {
        if (events == null || events.length() <= 0) {
            return
        }

        for (i in 0 until events.length()) {
            val ev: JSONObject = events.optJSONObject(i) ?: continue
            val text = serializeWebEventFromJSON(ev)
            rotatingFileStream.appendLine(text)
        }
    }
}
