type SuccessCallback<TValue> = (value: TValue) => void;
type ErrorCallback = (message: string) => void;

function noop() {
    return;
}

function cordovaExec<T>(
    plugin: string,
	method: string,
	successCallback: SuccessCallback<T> = noop,
	errorCallback: ErrorCallback = noop,
	args: any[] = [],
): void {
    if (window.cordova) {
        window.cordova.exec(successCallback, errorCallback, plugin, method, args);

    } else {
        console.warn(`${plugin}.${method}(...) :: cordova not available`);
        errorCallback && errorCallback(`cordova_not_available`);
    }
}

function cordovaExecPromise<T>(plugin: string, method: string, args?: any[]): Promise<T> {
    return new Promise<T>((resolve, reject) => cordovaExec<T>(plugin, method, resolve, reject, args));
}

const SECURE_LOGGER_PLUGIN = 'SecureLoggerPlugin';

// mirrors levels found in android.util.Log
export const enum SecureLogLevel {
    VERBOSE = 2,
    DEBUG = 3,
    INFO = 4,
    WARN = 5,
    ERROR = 6,
    FATAL = 7
}

export interface SecureLogEvent {
    timestamp: number; // EPOCH-based timestamp, e.g. Date.now()
    level: SecureLogLevel;
    tag: string;
    message: string;
}

export interface ConfigureOptions {

    /**
     * If provided, will filter all logs on both webview and native
     * that are below the given level from entering the file cache.
     * For example, if this is set to DEBUG, all TRACE logs will be filtered out.
     */
    minLevel?: SecureLogLevel;

    /**
     * If provided, will limit the size of each chunk file to the given value in bytes.
     *
     * Must be a positive integer
     */
    maxFileSizeBytes?: number;

    /**
     * If provided, will limit the aggregated total cache size that this plugin will use.
     * This is the total size of all chunk files, so if the max file size is 2MB and
     * this is set to 4MB, there will never be more than (approximately) 2 full chunk files
     * in storage at any given time.
     *
     * Must be a positive integer
     */
    maxTotalCacheSizeBytes?: number;

    /**
     * If provided, limits the max number of files in cache at any given time.
     * This will override both maxFileSizeBytes and maxTotalCacheSizeBytes if there
     * are a bunch of very small files in the cache and neither of these thresholds are met.
     *
     * Must be a positive integer
     */
    maxFileCount?: number;
}

/**
 * Specific info on why setting a certain option failed.
 */
export interface ConfigureOptionError {

    /**
     * The key from `ConfigureOptions` that caused the error
     */
    option: string;

    /**
     * Failure reason (e.g. negative number when indicating size, or invalid log level)
     */
    error: string;
}

/**
 * Plugin response for configure()
 * If success is false, check the `errors` property for which fields had issues
 */
export interface ConfigureResult {
    success: boolean;
    error?: string;
    errors?: ConfigureOptionError[];
}

function invokePlugin<T>(method: string, ...args: any[]): Promise<T> {
    return cordovaExecPromise<T>(SECURE_LOGGER_PLUGIN, method, args);
}

function normalizeConfigureResult(value: Partial<ConfigureResult>): ConfigureResult {

    if (!value) {
        return {success: false, error: `invalid configure response: ${value}`};
    }

    if (!Array.isArray(value.errors)) {
        value.errors = [];
    }

    if (typeof value.success !== 'boolean') {
        value.success = !value.error && value.errors.length <= 0;
    }

    return value as ConfigureResult;
}

export class SecureLoggerCordovaInterface {

    /**
     * Uses native-level formatting, and automatically inserts
     * newlines between events when writing formatted content to
     * the log cache.
     */
    public capture(events: SecureLogEvent[]): Promise<void> {
        return invokePlugin('capture', events);
    }

    /**
     * Writes the given text directly to the log cache
     * without any preprocessing.
     */
    public captureText(text: string): Promise<void> {
        return invokePlugin('captureText', text);
    }

    /**
     * Deletes all logging cache files.
     * Cannot be undone, use with caution.
     */
    public clearCache(): Promise<void> {
        return invokePlugin('clearCache');
    }

    /**
     * Retrieves a single blob of log data which
     * contains all current log files stitched back
     * together chronologically.
     */
    public getCacheBlob(): Promise<ArrayBuffer> {
        return invokePlugin('getCacheBlob');
    }

    /**
     * Customize how this plugin should operate.
     */
    public configure(options: ConfigureOptions): Promise<ConfigureResult> {
        return invokePlugin<Partial<ConfigureResult>>('configure', options)
            .then(normalizeConfigureResult)
            .then(result => result.success ? result : Promise.reject(result));
    }
}

export const SecureLogger = new SecureLoggerCordovaInterface();