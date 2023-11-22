/**
 * Values to indicate the level of an event.
 * mirrors levels found in android.util.Log to minimize plugin friction.
 */
export declare const enum SecureLogLevel {
    VERBOSE = 2,
    DEBUG = 3,
    INFO = 4,
    WARN = 5,
    ERROR = 6,
    FATAL = 7
}
export interface SecureLogEvent {
    /**
     * EPOCH-based timestamp, e.g. Date.now()
     */
    timestamp: number;
    /**
     * Priority level of this event
     */
    level: SecureLogLevel;
    /**
     * Scope indicating what module the event came from
     */
    tag: string;
    /**
     * Description of what happened when the event occurred
     */
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
export declare class SecureLoggerCordovaInterface {
    /**
     * Uses native-level formatting, and automatically inserts
     * newlines between events when writing formatted content to
     * the log cache.
     */
    capture(events: SecureLogEvent[]): Promise<void>;
    /**
     * Writes the given text directly to the log cache
     * without any preprocessing.
     */
    captureText(text: string): Promise<void>;
    /**
     * Deletes all logging cache files.
     * Cannot be undone, use with caution.
     */
    clearCache(): Promise<void>;
    /**
     * Retrieves a single blob of log data which
     * contains all current log files stitched back
     * together chronologically.
     */
    getCacheBlob(): Promise<ArrayBuffer>;
    /**
     * Customize how this plugin should operate.
     */
    configure(options: ConfigureOptions): Promise<ConfigureResult>;
}
/**
 * Singleton reference to interact with this cordova plugin
 */
export declare const SecureLogger: SecureLoggerCordovaInterface;
