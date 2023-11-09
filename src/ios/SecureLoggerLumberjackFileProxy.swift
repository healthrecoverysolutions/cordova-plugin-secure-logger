import CocoaLumberjack

// Forwards native logs captured by Lumberjack into this plugin's file stream
public class SecureLoggerLumberjackFileProxy : DDAbstractLogger {
    
    private var fileStream: SecureLoggerFileStream

    init(_ fileStream: SecureLoggerFileStream) {
        self.fileStream = fileStream
    }

    public override func log(message logMessage: DDLogMessage) {
        if let serializedEvent = logMessage.asSerializedNativeEvent() {
            do {
                try self.fileStream.appendLine(serializedEvent)
            } catch {
                print("Failed to append lumberjack log event to log file stream!")
            }
        }
    }
}
