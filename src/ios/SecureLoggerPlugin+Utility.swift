import CocoaLumberjack

enum LogLevel : Int {
    case VERBOSE = 2
    case DEBUG = 3
    case INFO = 4
    case WARN = 5
    case ERROR = 6
    case FATAL = 7
}

class LogEventUtility {
    static let iso6801Formatter = DateFormatter.iSO8601DateWithMillisec
}

extension DateFormatter {

    static var iSO8601DateWithMillisec: DateFormatter {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        dateFormatter.timeZone = TimeZone(abbreviation: "UTC")
        return dateFormatter
    }
}

extension Date {
    
    static var nowMilliseconds : Int {
        return Int(Date().timeIntervalSince1970 * 1000.0)
    }
    
    static func from(epoch: Int) -> Date {
        return Date(timeIntervalSince1970: Double(epoch) / 1000.0)
    }
    
    func toISOString() -> String {
        return LogEventUtility.iso6801Formatter.string(from: self)
    }
}

extension Int {
    
    func toLogLevel() -> LogLevel {
        if let level = LogLevel(rawValue: self) {
            return level
        }
        if self > LogLevel.FATAL.rawValue {
            return .FATAL
        }
        return .VERBOSE
    }
}

extension LogLevel {

    func toString() -> String {
        switch self {
        case .VERBOSE:  return "TRACE"
        case .DEBUG:    return "DEBUG"
        case .INFO:     return "INFO"
        case .WARN:     return "WARN"
        case .ERROR:    return "ERROR"
        case .FATAL:    return "FATAL"
        }
    }
}

extension DDLogLevel {

    func toPluginLevel() -> LogLevel {
        switch self {
        case .all:      return .VERBOSE
        case .verbose:  return .VERBOSE
        case .debug:    return .DEBUG
        case .info:     return .INFO
        case .warning:  return .WARN
        case .error:    return .ERROR
        default:        return .VERBOSE
        }
    }
}

extension DDLogMessage {
    
    func asSerializedNativeEvent() -> String? {
        
        let timestamp = self.timestamp.toISOString()
        let level = self.level.toPluginLevel().toString()
        let tag = "\(self.fileName):\(self.function ?? "NO_FUNC"):\(self.line)"
        
        return "\(timestamp) [\(level)] [\(tag)] \(message)"
    }
}

extension NSDictionary {

    func asSerializedWebEvent() -> String {
        
        let timestamp = self["timestamp"] as? Int ?? Date.nowMilliseconds
        let level = self["level"] as? Int ?? LogLevel.DEBUG.rawValue
        let tag = self["tag"] as? String ?? "NO_TAG"
        let message = self["message"] as? String ?? "<MISSING_MESSAGE>"
        let timestampString = Date.from(epoch: timestamp).toISOString()
        let levelString = level.toLogLevel().toString()
        
        return "\(timestampString) [\(levelString)] [webview-\(tag)] \(message)"
    }
}

extension InputStream {
    
    static let DEFAULT_BUFFER_SIZE: Int = 8192

    @discardableResult
    func pipeTo(_ output: OutputStream) -> Int {
        
        let bufferSize = InputStream.DEFAULT_BUFFER_SIZE
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        var transferred: Int = 0
        var read: Int = 1
        
        while read > 0 && self.hasBytesAvailable {
            read = self.read(&buffer, maxLength: bufferSize)
            if read > 0 {
                output.write(buffer, maxLength: read)
                transferred += read
            }
        }
        
        return transferred
    }
}

extension OutputStream {
    
    @discardableResult
    func writeText(_ text: String) -> Int {
        let utf8Bytes = Array(text.utf8)
        return self.write(utf8Bytes, maxLength: utf8Bytes.count)
    }
}

extension URL {
    
    var isRegularFile: Bool {
       (try? resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
    }
    
    var isDirectory: Bool {
       (try? resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }
    
    func fileOrDirectoryExists() -> Bool {
        return FileManager.default.fileExists(atPath: self.path)
    }
    
    func deleteFileSystemEntry() -> Bool {
        do {
            let fs = FileManager.default
            let target = self.path
            if fs.isDeletableFile(atPath: target) {
                try fs.removeItem(atPath: target)
                return true
            } else {
                return false
            }
        } catch {
            return false
        }
    }
    
    func fileLength() -> UInt64 {
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: self.path)
            return attrs[FileAttributeKey.size] as! UInt64;
        } catch {
            return 0
        }
    }
    
    func mkdirs() -> Bool {
        do {
            let fs = FileManager.default
            let target = self.path
            try fs.createDirectory(atPath: target, withIntermediateDirectories: true)
            return true
        } catch {
            return false
        }
    }
    
    func listFiles() -> [URL] {
        do {
            let contents = try FileManager.default.contentsOfDirectory(atPath: self.path)
            let urls = contents.map { URL.init(string: $0) ?? nil }
            return urls.filter { $0 != nil && $0!.isRegularFile } as! [URL]
        } catch {
            return []
        }
    }
}