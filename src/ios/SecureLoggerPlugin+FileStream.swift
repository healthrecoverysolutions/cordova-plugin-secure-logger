import CocoaLumberjack
import IDZSwiftCommonCrypto

// Generlized encrypted rotating file stream implementation
public class SecureLoggerFileStream {
    
    private static let LOG_FILE_NAME_PREFIX = "SCR-LOG-V"
    private static let LOG_FILE_NAME_EXTENSION = ".log"
    private static let RFS_SERIALIZER_VERSION = 1
    private static let MAX_FILE_SIZE_BYTES: UInt64 = 2 * 1000 * 1000 // 2MB
    private static let MAX_TOTAL_CACHE_SIZE_BYTES: UInt64 = 7 * 1000 * 1000 // 8MB
    private static let MAX_FILE_COUNT = 20
    
    private let outputDirectory: URL
    private var destroyed = false
    private var activeFilePath: URL?
    private var activeStream: OutputStream?
    
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
        destroyed = true
        closeActiveStream()
    }
    
    func appendLine(_ line: String) throws {
        if !destroyed && !line.isEmpty {
            try self.append(line + "\n")
        }
    }

    func append(_ text: String) throws {
        if !destroyed && !text.isEmpty {
            if let stream = try loadActiveStream() {
                stream.writeText(text)
            }
        }
    }
    
    func deleteAllCacheFiles() -> Bool {
        return !destroyed 
            && outputDirectory.deleteFileSystemEntry()
            && outputDirectory.mkdirs()
    }
    
    func getCacheBlob() -> [UInt8]? {
        
        if destroyed {
            return nil;
        }

        // Data at the end of the file will be partially corrupted if
        // the stream is not shut down, so need to close it before we can read it
        closeActiveStream()

        var files = outputDirectory.listFiles()
        
        if files.count <= 0 {
            return []
        }
        
        let bufferSize = Int(Double(maxCacheSize) * 1.25)
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        let outputStream = OutputStream.init(toBuffer: &buffer, capacity: bufferSize)
        var bytesWritten: Int = 0

        files.sort(by: SecureLoggerFileStream.fileNameComparator)
        var openedReadStream: InputStream? = nil

        for file in files {
            do {
                if let readStream = try openReadStream(file) {
                    openedReadStream = readStream
                    bytesWritten += Int(readStream.pipeTo(outputStream))
                }
            } catch {
                let errorMessage = "\n\n[[FILE DECRYPT FAILURE - " +
                    "${file.name} (${file.length()} bytes)]]" +
                    "\n<<<<<<<<<<<<<<<<\n\(error)\n>>>>>>>>>>>>>>>>\n\n"
                bytesWritten += outputStream.writeText(errorMessage)
            }
            
            openedReadStream?.close()
        }

        return Array(buffer[..<bytesWritten])
    }
    
    private static func generateArchiveFileName() -> String {
        // Generates a unique name like "SCR-LOG-V1-1698079640670.log"
        return "\(LOG_FILE_NAME_PREFIX)\(RFS_SERIALIZER_VERSION)-\(Date.nowMilliseconds)\(LOG_FILE_NAME_EXTENSION)"
    }
    
    private static func fileNameComparator(a: URL, b: URL) -> Bool {
        let comparisonResult = a.lastPathComponent.localizedStandardCompare(b.lastPathComponent)
        return comparisonResult == ComparisonResult.orderedAscending
    }
    
    private func openReadStream(_ filePath: URL) throws -> InputStream? {
        
        // TODO: use IDZSwiftCommonCrypto + the file name as IV to create encrypted stream
        // return InputStream(url: filePath)
        
        // !!! IMPORTANT !!!
        // Don't allow any apps to use unencrypted streams, since this will bleed out sensitive user data
        print("SecureLoggerFileStream openReadStream() ERROR - encrypted streaming not implemented")
        return nil
    }

    private func openWriteStream(_ filePath: URL) throws -> OutputStream? {
        
        // TODO: use IDZSwiftCommonCrypto + the file name as IV to create encrypted stream
        // return OutputStream(url: filePath, append: false)
        
        // !!! IMPORTANT !!!
        // Don't allow any apps to use unencrypted streams, since this will bleed out sensitive user data
        print("SecureLoggerFileStream openWriteStream() ERROR - encrypted streaming not implemented")
        return nil
    }

    private func closeActiveStream() {
        if (activeStream != nil) {
            activeStream!.close()
            activeStream = nil
        }
    }

    private func loadActiveStream() throws -> OutputStream? {
        if activeStream != nil
            && activeFilePath != nil
            && activeFilePath!.fileOrDirectoryExists()
            && activeFilePath!.fileLength() < maxFileSize {
            return activeStream!
        }

        normalizeFileCache()

        return try createNewStream()
    }

    private func createNewStream() throws -> OutputStream? {
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
