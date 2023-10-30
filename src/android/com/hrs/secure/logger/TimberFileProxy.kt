package com.hrs.secure.logger

import timber.log.Timber

class TimberFileProxy(
    private val stream: RotatingFileStream
) : Timber.DebugTree() {

    override fun log(priority: Int, tag: String?, message: String, t: Throwable?) {
        val text = serializeNativeEvent(priority, tag, message, t)
        stream.appendLine(text)
    }
}
