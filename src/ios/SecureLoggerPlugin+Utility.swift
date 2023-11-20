import Foundation
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

public class CryptoUtility {
    
    public static var deviceFingerprint: String? {
        return UIDevice.current.identifierForVendor?.uuidString
    }
    
    public static func deriveStreamPassword(_ input: String) throws -> String {
        // TODO: come up with a less terrible derivation than this
        return "\(CryptoUtility.deviceFingerprint!)+\(input)"
    }
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
            try FileManager.default.removeItem(at: self)
            return true
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
            try FileManager.default.createDirectory(
                atPath: self.path,
                withIntermediateDirectories: true
            )
            return true
        } catch {
            return false
        }
    }
    
    func listEntryNames() -> [String] {
        do {
            return try FileManager.default.contentsOfDirectory(atPath: self.path)
        } catch {
            return []
        }
    }
    
    func listEntries() -> [URL] {
        return self.listEntryNames()
            .map { self.appendingPathComponent($0) }
            .filter { $0.fileOrDirectoryExists() }
    }
    
    func listFiles() -> [URL] {
        return self.listEntries()
            .filter { $0.isFileURL }
    }
}
