import Foundation
import CocoaLumberjack

@objc(SecureLoggerPlugin)
public class SecureLoggerPlugin : CDVPlugin {
    private static let LOG_DIR = "logs"
    private static let LOG_CONFIG_FILE = "logs-config.json"
    private static let CONFIG_KEY_MIN_LEVEL = "minLevel"

    private var logsConfigFile: URL!
    private var fileStream: SecureLoggerFileStream!
    private var lumberjackProxy: SecureLoggerLumberjackFileProxy!
    
    @objc(pluginInitialize)
    public override func pluginInitialize() {
        super.pluginInitialize()
        
        let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        var appRootCacheDirectory = cachesDirectory
        
        if let appBundleId = Bundle.main.bundleIdentifier {
            appRootCacheDirectory = appRootCacheDirectory.appendingPathComponent(appBundleId)
        }
        
        let logsDirectory = appRootCacheDirectory.appendingPathComponent(SecureLoggerPlugin.LOG_DIR)
        print("using log directory \(logsDirectory)")
    
        let streamOptions = SecureLoggerFileStreamOptions()

        self.logsConfigFile = appRootCacheDirectory.appendingPathComponent(SecureLoggerPlugin.LOG_CONFIG_FILE)
        self.fileStream = SecureLoggerFileStream(logsDirectory, options: streamOptions)
        self.lumberjackProxy = SecureLoggerLumberjackFileProxy(self.fileStream!)
        
        tryLoadStoredConfig()
        DDLog.add(self.lumberjackProxy!)
        DDLogDebug("init success!")
    }
    
    @objc(onAppTerminate)
    override public func onAppTerminate() {
        DDLogDebug("running teardown actions...")
        self.fileStream.destroy()
        super.onAppTerminate()
    }

    @objc(capture:)
    func capture(command: CDVInvokedUrlCommand) {
        DispatchQueue.main.async(flags: .barrier) {
            if let eventList = command.arguments[0] as? [NSDictionary] {
                self.captureLogEvents(eventList)
                self.sendOk(command.callbackId)
            } else {
                self.sendError(command.callbackId, "input must be an array of events")
            }
        }
    }
    
    @objc(captureText:)
    func captureText(command: CDVInvokedUrlCommand) {
        DispatchQueue.main.async(flags: .barrier) {
            if let text = command.arguments[0] as? String {
                do {
                    try self.fileStream.append(text)
                    self.sendOk(command.callbackId)
                } catch {
                    print("Failed to capture webview text in log file!")
                    self.sendError(command.callbackId, "failed to capture log text")
                }
            } else {
                self.sendError(command.callbackId, "input must be a string")
            }
        }
    }
    
    @objc(clearCache:)
    func clearCache(command: CDVInvokedUrlCommand) {
        DispatchQueue.main.async(flags: .barrier) {
            let success = self.fileStream.deleteAllCacheFiles()
            print("clearCache success = \(success)")
            self.sendOk(command.callbackId, String(success))
      }
    }
    
    @objc(getCacheBlob:)
    func getCacheBlob(command: CDVInvokedUrlCommand) {
        DispatchQueue.main.async(flags: .barrier) {
            if let bytes = self.fileStream.getCacheBlob() {
                print("getCacheBlob() sending response with \(bytes.count) bytes")
                self.sendOkBytes(command.callbackId, bytes)
            } else {
                self.sendError(command.callbackId, "Failed to load cache blob")
            }
        }
    }

    @objc(configure:)
    func configure(command: CDVInvokedUrlCommand) {
        DispatchQueue.main.async(flags: .barrier) {
            print("TODO: configure()")
            self.sendOk(command.callbackId)
        }
    }

    private func sendOk(_ callbackId: String, _ message: String? = nil) {
        let pluginResult = CDVPluginResult(status: .ok, messageAs: message)
        self.commandDelegate.send(pluginResult, callbackId: callbackId)
    }
    
    private func sendOkBytes(_ callbackId: String, _ message: [UInt8]) {
        let pluginResult = CDVPluginResult(status: .ok, messageAsArrayBuffer: Data(message))
        self.commandDelegate.send(pluginResult, callbackId: callbackId)
    }
    
    private func sendError(_ callbackId: String, _ message: String? = nil) {
        let pluginResult = CDVPluginResult(status: .error, messageAs: message)
        self.commandDelegate.send(pluginResult, callbackId: callbackId)
    }

    private func captureLogEvents(_ eventList: [NSDictionary]) {
        for logEvent in eventList {
            do {
                let logLine = logEvent.asSerializedWebEvent()
                try fileStream.appendLine(logLine)
            } catch {
                print("Failed to capture webview event in log file!")
            }
        }
    }
    
    private func trySaveCurrentConfig() {
        var output = fileStream.options.toJSON()
        output[SecureLoggerPlugin.CONFIG_KEY_MIN_LEVEL] = lumberjackProxy.minLevelInt
        
        if !logsConfigFile.writeJson(output) {
            DDLogWarn("failed to save current config")
        }
    }
    
    private func tryLoadStoredConfig() {
        guard let input = logsConfigFile.readJson() else {
            DDLogWarn("failed to load stored config")
            return
        }
        
        let storedOptions = fileStream.options.fromJSON(input)
        fileStream.options = storedOptions
        
        if let minLevelInt = input[SecureLoggerPlugin.CONFIG_KEY_MIN_LEVEL] as? Int {
            DDLogDebug("updating minLevel to \(minLevelInt) (from storage)")
            lumberjackProxy.minLevelInt = minLevelInt
        }
    }
}
