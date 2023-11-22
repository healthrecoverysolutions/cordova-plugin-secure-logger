"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.SecureLogger = exports.SecureLoggerCordovaInterface = void 0;
function noop() {
    return;
}
function cordovaExec(plugin, method, successCallback, errorCallback, args) {
    if (successCallback === void 0) { successCallback = noop; }
    if (errorCallback === void 0) { errorCallback = noop; }
    if (args === void 0) { args = []; }
    if (window.cordova) {
        window.cordova.exec(successCallback, errorCallback, plugin, method, args);
    }
    else {
        console.warn("".concat(plugin, ".").concat(method, "(...) :: cordova not available"));
        errorCallback && errorCallback("cordova_not_available");
    }
}
function cordovaExecPromise(plugin, method, args) {
    return new Promise(function (resolve, reject) { return cordovaExec(plugin, method, resolve, reject, args); });
}
var SECURE_LOGGER_PLUGIN = 'SecureLoggerPlugin';
function invokePlugin(method) {
    var args = [];
    for (var _i = 1; _i < arguments.length; _i++) {
        args[_i - 1] = arguments[_i];
    }
    return cordovaExecPromise(SECURE_LOGGER_PLUGIN, method, args);
}
function normalizeConfigureResult(value) {
    if (!value) {
        return { success: false, error: "invalid configure response: ".concat(value) };
    }
    if (!Array.isArray(value.errors)) {
        value.errors = [];
    }
    if (typeof value.success !== 'boolean') {
        value.success = !value.error && value.errors.length <= 0;
    }
    return value;
}
var SecureLoggerCordovaInterface = /** @class */ (function () {
    function SecureLoggerCordovaInterface() {
    }
    /**
     * Uses native-level formatting, and automatically inserts
     * newlines between events when writing formatted content to
     * the log cache.
     */
    SecureLoggerCordovaInterface.prototype.capture = function (events) {
        return invokePlugin('capture', events);
    };
    /**
     * Writes the given text directly to the log cache
     * without any preprocessing.
     */
    SecureLoggerCordovaInterface.prototype.captureText = function (text) {
        return invokePlugin('captureText', text);
    };
    /**
     * Deletes all logging cache files.
     * Cannot be undone, use with caution.
     */
    SecureLoggerCordovaInterface.prototype.clearCache = function () {
        return invokePlugin('clearCache');
    };
    /**
     * Retrieves a single blob of log data which
     * contains all current log files stitched back
     * together chronologically.
     */
    SecureLoggerCordovaInterface.prototype.getCacheBlob = function () {
        return invokePlugin('getCacheBlob');
    };
    /**
     * Customize how this plugin should operate.
     */
    SecureLoggerCordovaInterface.prototype.configure = function (options) {
        return invokePlugin('configure', options)
            .then(normalizeConfigureResult)
            .then(function (result) { return result.success ? result : Promise.reject(result); });
    };
    return SecureLoggerCordovaInterface;
}());
exports.SecureLoggerCordovaInterface = SecureLoggerCordovaInterface;
/**
 * Singleton reference to interact with this cordova plugin
 */
exports.SecureLogger = new SecureLoggerCordovaInterface();
