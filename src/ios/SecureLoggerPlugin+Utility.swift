import Foundation
import Security
import CocoaLumberjack
import IDZSwiftCommonCrypto

public enum LogLevel : Int {
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
    public enum Error : Swift.Error {
        case keyGenerationFailed
    }
    
    public static func deriveStreamPassword(_ input: String) throws -> String {
        let fingerprint = try CryptoUtility.loadLoggerIdentifier()
        return "\(fingerprint)+\(input)"
    }
    
    private static func loadLoggerIdentifier() throws -> String {
        
        let key = "loggerId"
        
        if let identifier = KeychainUtility.getValue(forKey: key) {
            return identifier
        }
        
        let identifierBytes = try Random.generateBytes(byteCount: 16)
        let identifier = hexString(fromArray: identifierBytes)
        
        if KeychainUtility.addValue(identifier, forKey: key) {
            return identifier
        }
        
        throw Error.keyGenerationFailed
    }
}

public class KeychainUtility {
    
    private static func getCompositeKey(_ key: String) -> String {
        let bundleId = Bundle.main.bundleIdentifier!
        return "\(bundleId)+\(key)"
    }
    
    public static func setValue(_ value: String, forKey key: String) -> Bool {
        return if KeychainUtility.getValue(forKey: key) != nil {
            KeychainUtility.updateValue(value, forKey: key)
        } else {
            KeychainUtility.addValue(value, forKey: key)
        }
    }
    
    public static func remove(_ key: String) -> Bool {
        
        let bundleKey = KeychainUtility.getCompositeKey(key)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrLabel as String: bundleKey,
        ]
        
        return SecItemDelete(query as CFDictionary) == noErr
    }
    
    public static func addValue(_ value: String, forKey key: String) -> Bool {
        
        let bundleKey = KeychainUtility.getCompositeKey(key)
        let valueData = value.data(using: .utf8)!

        let attributes: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrLabel as String: bundleKey,
            kSecValueData as String: valueData,
        ]
        
        return SecItemAdd(attributes as CFDictionary, nil) == noErr
    }
    
    public static func updateValue(_ value: String, forKey key: String) -> Bool {
        
        let bundleKey = KeychainUtility.getCompositeKey(key)
        let valueData = value.data(using: .utf8)!
        let attributes: [String: Any] = [kSecValueData as String: valueData]
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrLabel as String: bundleKey,
        ]
        
        return SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == noErr
    }
    
    public static func getValue(forKey key: String) -> String? {
        
        let bundleKey = KeychainUtility.getCompositeKey(key)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrLabel as String: bundleKey,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
        ]
        
        var item: CFTypeRef?
        
        if SecItemCopyMatching(query as CFDictionary, &item) != noErr {
            return nil
        }
        
        if let existingItem = item as? [String: Any],
           let extractedBundleKey = existingItem[kSecAttrLabel as String] as? String,
           let valueData = existingItem[kSecValueData as String] as? Data,
           let value = String(data: valueData, encoding: .utf8),
           extractedBundleKey == bundleKey
        {
            return value
        }
        
        return nil
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
    
    func readJson() -> [String: Any]? {
        do {
            let jsonData = try Data(contentsOf: self, options: .mappedIfSafe)
            let json = try JSONSerialization.jsonObject(with: jsonData, options: [.mutableContainers, .mutableLeaves])
            return json as? [String: Any]
        } catch {
            print("readJson() ERROR: \(error)")
            return nil
        }
    }
    
    func writeJson(_ value: [String: Any]) -> Bool {
        do {
            let data = try JSONSerialization.data(withJSONObject: value)
            try data.write(to: self, options: [.atomic])
            return true
        } catch {
            print("writeJson() ERROR: \(error)")
            return false
        }
    }
}
