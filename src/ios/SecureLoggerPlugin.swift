import Cordova
import Foundation
import CocoaLumberjack
import SwiftyJSON

@objc(SecureLoggerPlugin)
public class SecureLoggerPlugin : CDVPlugin {
    
    private var fileStream: SecureLoggerFileStream!
    private var lumberjackProxy: SecureLoggerLumberjackFileProxy!
    
    @objc(pluginInitialize)
    public override func pluginInitialize() {
        let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let logsDirectory = cachesDirectory.appendingPathComponent("logs")
        print("using log directory \(logsDirectory)")
        
        fileStream = SecureLoggerFileStream(logsDirectory)
        lumberjackProxy = SecureLoggerLumberjackFileProxy(fileStream!)
        
        DDLog.add(lumberjackProxy!)
        DDLogDebug("SecureLoggerPlugin initialize")
    }

    @objc(capture:)
    func capture(command: CDVInvokedUrlCommand) {
      DispatchQueue.main.async {
          self.captureLogEvents(fromCommand: command)
          self.sendOk(command.callbackId)
      }
    }
    
    @objc(captureText:)
    func captureText(command: CDVInvokedUrlCommand) {
      DispatchQueue.main.async {
          if let text = JSON(command.arguments[0]).string {
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
          let bytes = self.fileStream.getCacheBlob()
          self.sendOkBytes(command.callbackId, bytes)
      }
    }

    private func sendOk(_ callbackId: String, _ message: String? = nil) {
        let pluginResult = CDVPluginResult(status: .ok, messageAs: message)
        self.commandDelegate.send(pluginResult, callbackId: callbackId)
    }
    
    private func sendOkBytes(_ callbackId: String, _ message: [UInt8]? = nil) {
        let pluginResult = CDVPluginResult(status: .ok, messageAs: message)
        self.commandDelegate.send(pluginResult, callbackId: callbackId)
    }
    
    private func sendError(_ callbackId: String, _ message: String? = nil) {
        let pluginResult = CDVPluginResult(status: .error, messageAs: message)
        self.commandDelegate.send(pluginResult, callbackId: callbackId)
    }

    private func captureLogEvents(fromCommand: CDVInvokedUrlCommand) {
        for (_, logEvent) in JSON(fromCommand.arguments[0]) {
            if let logLine = logEvent.asSerializedWebEvent() {
                do {
                    try fileStream.appendLine(logLine)
                } catch {
                    print("Failed to capture webview event in log file!")
                }
            }
        }
    }
}
