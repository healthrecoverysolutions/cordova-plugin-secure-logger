import Foundation
import CocoaLumberjack

@objc(SecureLoggerPlugin)
public class SecureLoggerPlugin : CDVPlugin {
    
    private var fileStream: SecureLoggerFileStream!
    private var lumberjackProxy: SecureLoggerLumberjackFileProxy!
    
    @objc(pluginInitialize)
    public override func pluginInitialize() {
        
        let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        var appRootCacheDirectory = cachesDirectory
        
        if let appBundleId = Bundle.main.bundleIdentifier {
            appRootCacheDirectory = appRootCacheDirectory.appendingPathComponent(appBundleId)
        }
        
        let logsDirectory = appRootCacheDirectory.appendingPathComponent("logs")
        print("using log directory \(logsDirectory)")
    
        self.fileStream = SecureLoggerFileStream(logsDirectory)
        self.lumberjackProxy = SecureLoggerLumberjackFileProxy(self.fileStream!)
        
        DDLog.add(self.lumberjackProxy!)
        DDLogDebug("SecureLoggerPlugin initialize")
    }

    @objc(capture:)
    func capture(command: CDVInvokedUrlCommand) {
      DispatchQueue.main.async {
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
      DispatchQueue.main.async {
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
      DispatchQueue.main.async {
          let success = self.fileStream.deleteAllCacheFiles()
          self.sendOk(command.callbackId, String(success))
      }
    }
    
    @objc(getCacheBlob:)
    func getCacheBlob(command: CDVInvokedUrlCommand) {
      DispatchQueue.main.async {
          if let bytes = self.fileStream.getCacheBlob() {
              print("getCacheBlob() sending response with \(bytes.count) bytes")
              self.sendOkBytes(command.callbackId, bytes)
          } else {
              self.sendError(command.callbackId, "Failed to load cache blob")
          }
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
}
