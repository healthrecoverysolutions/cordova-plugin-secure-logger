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
export const enum LogLevel {
    VERBOSE = 2,
    DEBUG = 3,
    INFO = 4,
    WARN = 5,
    ERROR = 6,
    FATAL = 7
}

export interface HRSLogEvent {
    timestamp: number; // EPOCH-based timestamp, e.g. Date.now()
    level: LogLevel;
    tag: string;
    message: string;
}

function invokePlugin<T>(method: string, ...args: any[]): Promise<T> {
    return cordovaExecPromise<T>(SECURE_LOGGER_PLUGIN, method, args);
}

export class NativeLoggerDefinition {

    /**
     * Uses native-level formatting, and automatically inserts
     * newlines between events when writing formatted content to
     * the log cache.
     */
    public capture(events: HRSLogEvent[]): Promise<void> {
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
}

export const NativeLogger = new NativeLoggerDefinition();