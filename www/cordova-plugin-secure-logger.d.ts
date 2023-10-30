export declare const enum SecureLogLevel {
    VERBOSE = 2,
    DEBUG = 3,
    INFO = 4,
    WARN = 5,
    ERROR = 6,
    FATAL = 7
}
export interface SecureLogEvent {
    timestamp: number;
    level: SecureLogLevel;
    tag: string;
    message: string;
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
}
export declare const SecureLogger: SecureLoggerCordovaInterface;
