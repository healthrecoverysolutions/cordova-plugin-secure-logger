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
private const val ACTION_CAPTURE = "capture"
private const val ACTION_CAPTURE_TEXT = "captureText"
private const val ACTION_CLEAR_CACHE = "clearCache"
private const val ACTION_GET_CACHE_BLOB = "getCacheBlob"
private const val ACTION_CONFIGURE = "configure"
private const val CONFIG_RESULT_KEY_SUCCESS = "success"
private const val CONFIG_RESULT_KEY_ERRORS = "errors"
private const val CONFIG_ERROR_KEY_OPTION = "option"
private const val CONFIG_ERROR_KEY_ERROR = "error"
private const val CONFIG_KEY_MIN_LEVEL = "minLevel"
private const val CONFIG_KEY_MAX_FILE_SIZE_BYTES = "maxFileSizeBytes"
private const val CONFIG_KEY_MAX_TOTAL_CACHE_SIZE_BYTES = "maxTotalCacheSizeBytes"
private const val CONFIG_KEY_MAX_FILE_COUNT = "maxFileCount"

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
			ACTION_CAPTURE -> {
                cordova.threadPool.execute {
                    try {
                        val eventList = args.optJSONArray(0)
                        captureLogEvents(eventList)
                        callbackContext.success()
                    } catch (ex: Exception) {
						onActionFailure(callbackContext, action, ex)
                    }
                }
            }
			ACTION_CAPTURE_TEXT -> {
                cordova.threadPool.execute {
                    try {
                        val text = args.optString(0, "")
                        rotatingFileStream.append(text)
                        callbackContext.success()
                    } catch (ex: Exception) {
						onActionFailure(callbackContext, action, ex)
                    }
                }
            }
			ACTION_CLEAR_CACHE -> {
                cordova.threadPool.execute {
                    try {
                        val success = rotatingFileStream.deleteAllFiles()
                        callbackContext.success(success.toString())
                    } catch (ex: Exception) {
						onActionFailure(callbackContext, action, ex)
                    }
                }
            }
			ACTION_GET_CACHE_BLOB -> {
                cordova.threadPool.execute {
                    try {
                        val combinedBytes = rotatingFileStream.toBlob()
                        if (combinedBytes != null) {
                            callbackContext.success(combinedBytes)
                        } else {
                            callbackContext.error("cannot fetch cache blob after app destroy")
                        }
                    } catch (ex: Exception) {
						onActionFailure(callbackContext, action, ex)
                    }
                }
            }
			ACTION_CONFIGURE -> {
                cordova.threadPool.execute {
                    try {
                        val options = args.optJSONObject(0)
                        val result = applyConfigurationFromJson(options)
                        callbackContext.success(result)
                    } catch (ex: Exception) {
						onActionFailure(callbackContext, action, ex)
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

	private fun onActionFailure(
		callbackContext: CallbackContext,
		action: String,
		ex: Exception
	) {
		Timber.e("failed plugin action '$action' -> ${ex.message}")
		callbackContext.error(ex.message)
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

	private fun toConfigError(key: String, error: String): JSONObject {
		return JSONObject()
			.put(CONFIG_ERROR_KEY_OPTION, key)
			.put(CONFIG_ERROR_KEY_ERROR, error)
	}

    private fun applyConfigurationFromJson(config: JSONObject?): JSONObject {

		val result = JSONObject()

        if (config == null) return result.put(CONFIG_RESULT_KEY_SUCCESS, true)

		val errors = mutableListOf<JSONObject>()

		if (config.has(CONFIG_KEY_MIN_LEVEL)) {
			timberFileProxy.minLevel = config.getInt(CONFIG_KEY_MIN_LEVEL)
		}

		val updatedOptions = rotatingFileStream.options.copy()
		var didUpdateOptions = false

		if (config.has(CONFIG_KEY_MAX_FILE_SIZE_BYTES)) {
			val value = config.getInt(CONFIG_KEY_MAX_FILE_SIZE_BYTES)
			val min = 1000
			val max = 4 * 1000 * 1000
			if (value in min .. max) {
				updatedOptions.maxFileSizeBytes = value.toLong()
				didUpdateOptions = true
			} else {
				errors.add(toConfigError(
					CONFIG_KEY_MAX_FILE_SIZE_BYTES,
					"must be in range [$min, $max]"
				))
			}
		}

		if (config.has(CONFIG_KEY_MAX_TOTAL_CACHE_SIZE_BYTES)) {
			val value = config.getInt(CONFIG_KEY_MAX_TOTAL_CACHE_SIZE_BYTES)
			val min = 1000
			val max = 64 * 1000 * 1000
			if (value in min .. max) {
				updatedOptions.maxTotalCacheSizeBytes = value.toLong()
				didUpdateOptions = true
			} else {
				errors.add(toConfigError(
					CONFIG_KEY_MAX_TOTAL_CACHE_SIZE_BYTES,
					"must be in range [$min, $max]"
				))
			}
		}

		if (config.has(CONFIG_KEY_MAX_FILE_COUNT)) {
			val value = config.getInt(CONFIG_KEY_MAX_FILE_COUNT)
			val min = 1
			val max = 100
			if (value in min .. max) {
				updatedOptions.maxFileCount = value.toLong()
				didUpdateOptions = true
			} else {
				errors.add(toConfigError(
					CONFIG_KEY_MAX_FILE_COUNT,
					"must be in range [$min, $max]"
				))
			}
		}

		if (didUpdateOptions) {
			rotatingFileStream.options = updatedOptions
		}

		result.put(CONFIG_RESULT_KEY_SUCCESS, errors.isEmpty())
		result.put(CONFIG_RESULT_KEY_ERRORS, JSONArray(errors))

		return result
    }
}
