import Foundation
import CryptoSwift

// Generlized encrypted rotating file stream implementation
public class SecureLoggerFileStream {
    
    private static let LOG_FILE_NAME_PREFIX = "SCR-LOG-V"
    private static let LOG_FILE_NAME_EXTENSION = ".log"
    private static let RFS_SERIALIZER_VERSION = 1
    private static let MAX_FILE_SIZE_BYTES: UInt64 = 2 * 1000 * 1000 // 2MB
    private static let MAX_TOTAL_CACHE_SIZE_BYTES: UInt64 = 7 * 1000 * 1000 // 8MB
    private static let MAX_FILE_COUNT = 20
    
    private let outputDirectory: URL
    private let mutex = NSLock()
    private var destroyed = false
    private var activeFilePath: URL?
    private var activeStream: OutputStreamLike?
    
    init(_ outputDirectory: URL) {
        self.outputDirectory = outputDirectory
    }

    private var maxFileSize: UInt64 {
        return SecureLoggerFileStream.MAX_FILE_SIZE_BYTES
    }
    
    private var maxCacheSize: UInt64 {
        return SecureLoggerFileStream.MAX_TOTAL_CACHE_SIZE_BYTES
    }
    
    private var maxFileCount: Int {
        return SecureLoggerFileStream.MAX_FILE_COUNT
    }
    
    func destroy() {
        self.mutex.lock()
        self.destroyed = true
        self.closeActiveStream()
        self.mutex.unlock()
    }
    
    func appendLine(_ line: String) throws {
        if !self.destroyed && !line.isEmpty {
            try self.append(line + "\n")
        }
    }

    func append(_ text: String) throws {
        self.mutex.lock()
        if !self.destroyed && !text.isEmpty {
            if let stream = try self.loadActiveStream() {
                stream.writeText(text)
            }
        }
        self.mutex.unlock()
    }
    
    func deleteAllCacheFiles() -> Bool {
        self.mutex.lock()
        let result = !self.destroyed
            && self.outputDirectory.deleteFileSystemEntry()
            && self.outputDirectory.mkdirs()
        self.mutex.unlock()
        return result
    }
    
    func getCacheBlob() -> [UInt8]? {
        
        if self.destroyed {
            print("getCacheBlob() stream is destroyed!")
            return nil;
        }
        
        self.mutex.lock()

        // Data at the end of the file will be partially corrupted if
        // the stream is not shut down, so need to close it before we can read it
        closeActiveStream()

        var files = outputDirectory.listFiles()
        
        if files.count <= 0 {
            print("getCacheBlob() no files in cache!")
            return []
        }
        
        let bufferSize = Int(Double(maxCacheSize) * 1.25)
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        let outputStream = OutputStream.init(toBuffer: &buffer, capacity: bufferSize)
        var bytesWritten: Int = 0

        files.sort(by: SecureLoggerFileStream.fileNameComparator)
        var openedReadStream: InputStreamLike? = nil

        for file in files {
            do {
                openedReadStream = try openReadStream(file)
                bytesWritten += Int(openedReadStream!.pipeTo(outputStream))
                print("getCacheBlob() wrote \(bytesWritten) bytes to output")
            } catch {
                openedReadStream = nil
                let errorMessage = "\n\n[[FILE DECRYPT FAILURE - " +
                    "${file.name} (${file.length()} bytes)]]" +
                    "\n<<<<<<<<<<<<<<<<\n\(error)\n>>>>>>>>>>>>>>>>\n\n"
                print("getCacheBlob() ERROR: \(errorMessage)")
                bytesWritten += outputStream.writeText(errorMessage)
            }
            
            openedReadStream?.close()
        }

        let result = Array(buffer[..<bytesWritten])
        self.mutex.unlock()
        
        return result
    }
    
    private static func generateArchiveFileName() -> String {
        // Generates a unique name like "SCR-LOG-V1-1698079640670.log"
        return "\(LOG_FILE_NAME_PREFIX)\(RFS_SERIALIZER_VERSION)-\(Date.nowMilliseconds)\(LOG_FILE_NAME_EXTENSION)"
    }
    
    private static func fileNameComparator(a: URL, b: URL) -> Bool {
        let comparisonResult = a.lastPathComponent.localizedStandardCompare(b.lastPathComponent)
        return comparisonResult == ComparisonResult.orderedAscending
    }
    
    private func openReadStream(_ filePath: URL) throws -> InputStreamLike {
        let startTime = Date.nowMilliseconds
        let password = try CryptoUtility.deriveStreamPassword(filePath.lastPathComponent)
        let encryptedFile = try AESEncryptedFile(filePath, password: password)
        let inputStream = try encryptedFile.openInputStream()
        print("logger input stream created in \(Date.nowMilliseconds - startTime) ms")
        return inputStream;
    }

    private func openWriteStream(_ filePath: URL) throws -> OutputStreamLike {
        let startTime = Date.nowMilliseconds
        let password = try CryptoUtility.deriveStreamPassword(filePath.lastPathComponent)
        let encryptedFile = try AESEncryptedFile(filePath, password: password)
        let outputStream = try encryptedFile.openOutputStream()
        print("logger output stream created in \(Date.nowMilliseconds - startTime) ms")
        return outputStream;
    }

    private func closeActiveStream() {
        if (activeStream != nil) {
            activeStream!.close()
            activeStream = nil
        }
    }

    private func loadActiveStream() throws -> OutputStreamLike? {
        if activeStream != nil
            && activeFilePath != nil
            && activeFilePath!.fileOrDirectoryExists()
            && activeFilePath!.fileLength() < maxFileSize {
            return activeStream!
        }

        normalizeFileCache()

        return try createNewStream()
    }

    private func createNewStream() throws -> OutputStreamLike? {
        closeActiveStream()

        let nextFileName = SecureLoggerFileStream.generateArchiveFileName()
        activeFilePath = outputDirectory.appendingPathComponent(nextFileName)

        if activeFilePath!.fileOrDirectoryExists() {
            if !activeFilePath!.deleteFileSystemEntry() {
                print("Failed to delete file at \(String(describing: activeFilePath))")
            }
        }

        activeStream = try openWriteStream(activeFilePath!)

        return activeStream
    }

    private func normalizeFileCache() {
        if !outputDirectory.fileOrDirectoryExists() {
            if !outputDirectory.mkdirs() {
                print("Failed to create directory at \(String(describing: outputDirectory))")
            }
        }

        if (activeFilePath != nil
            && activeFilePath!.fileOrDirectoryExists()
            && activeFilePath!.fileLength() >= maxFileSize) {
            closeActiveStream()
        }

        var files = outputDirectory
            .listFiles()
            .filter { $0.fileOrDirectoryExists() && $0.isRegularFile }

        files.sort(by: SecureLoggerFileStream.fileNameComparator)

        // TODO: may want to try consolidating log files together
        //      before deletion to avoid unnecessary data loss.
        
        var deleteRetryCounter = 0
        
        func trackFileRemovalRetry() {
            print("Failed to delete file at \(String(describing: files[0]))")
            deleteRetryCounter += 1
            if (deleteRetryCounter >= 3) {
                files.remove(at: 0)
                deleteRetryCounter = 0
            }
        }

        while (files.count > 0 && files.count > maxFileCount) {
            if files[0].deleteFileSystemEntry() {
                files.remove(at: 0)
            } else {
                trackFileRemovalRetry()
            }
        }

        var totalFileSize: UInt64 = 0
        
        for fileUrl in files {
            totalFileSize += fileUrl.fileLength()
        }

        while (files.count > 0 && totalFileSize > maxCacheSize) {
            let currentFileSize = files[0].fileLength()
            
            if files[0].deleteFileSystemEntry() {
                totalFileSize -= currentFileSize
                files.remove(at: 0)
            } else {
                trackFileRemovalRetry()
            }
        }
    }
}
