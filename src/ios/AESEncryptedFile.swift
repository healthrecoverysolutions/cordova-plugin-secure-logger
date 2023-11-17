import CryptoSwift

public protocol Closeable {
    func close() -> Void
}

public protocol InputStreamLike : Closeable {
    var hasBytesAvailable: Bool { get }
    @discardableResult
    func read(_ buffer: UnsafeMutablePointer<UInt8>, maxLength len: Int) -> Int
}

public protocol OutputStreamLike : Closeable {
    @discardableResult
    func write(_ buffer: UnsafePointer<UInt8>, maxLength len: Int) -> Int
}

extension Stream : Closeable {
}

// Workaround to avoid errors from inheriting the actual InputStream class
extension InputStream : InputStreamLike {
}

// Workaround to avoid errors from inheriting the actual OutputStream class
extension OutputStream : OutputStreamLike {
}

public class CipherInputStream : InputStreamLike {
    private var cryptor: Updatable
    private var stream: InputStreamLike
    private var hasCipherUpdateFailure: Bool = false
    private var closed: Bool = false
    
    // NOTE: given stream is expected to have already been opened
    init(_ cryptor: Updatable, forStream stream: InputStreamLike) {
        self.cryptor = cryptor
        self.stream = stream
    }
    
    public var hasBytesAvailable: Bool {
        return self.stream.hasBytesAvailable
    }
    
    public func close() {
        if self.closed {
            return
        }
        
        self.stream.close()
        self.closed = true
    }
    
    @discardableResult
    public func read(_ buffer: UnsafeMutablePointer<UInt8>, maxLength len: Int) -> Int {
        if self.closed || self.hasCipherUpdateFailure {
            return 0
        }
        
        var ciphertextBuffer = [UInt8](repeating: 0, count: len)
        self.stream.read(&ciphertextBuffer, maxLength: len)
        
        if let plaintext = try? self.cryptor.update(withBytes: ciphertextBuffer) {
            buffer.update(from: plaintext, count: plaintext.count)
            return plaintext.count
        } else {
            print("EncryptedInputStream ERROR - failed to decrypt update block")
            self.hasCipherUpdateFailure = true
            return 0
        }
    }
}

public class CipherOutputStream : OutputStreamLike {
    private var cryptor: Updatable
    private var stream: OutputStreamLike
    private var hasCipherUpdateFailure: Bool = false
    private var closed: Bool = false
    
    // NOTE: given stream is expected to have already been opened
    init(_ cryptor: Updatable, forStream stream: OutputStreamLike) {
        self.cryptor = cryptor
        self.stream = stream
    }
    
    public func close() {
        if self.closed {
            return
        }
        
        if !self.hasCipherUpdateFailure {
            if let cipherText = try? self.cryptor.finish(), !cipherText.isEmpty {
                self.stream.write(cipherText, maxLength: cipherText.count)
            } else {
                print("CipherOutputStream ERROR - failed to encrypt final block")
                self.hasCipherUpdateFailure = true
            }
        } else {
            print("CipherOutputStream ERROR - could not fully close stream due to previous update error")
        }
        
        self.stream.close()
        self.closed = true
    }
    
    @discardableResult
    public func write(_ buffer: UnsafePointer<UInt8>, maxLength len: Int) -> Int {
        if self.closed || self.hasCipherUpdateFailure {
            return 0
        }
        
        let bytes = Array(UnsafeBufferPointer(start: buffer, count: len))
        
        if let cipherText = try? self.cryptor.update(withBytes: bytes, isLast: false) {
            return self.stream.write(cipherText, maxLength: len)
        } else {
            print("EncryptedOutputStream ERROR - failed to encrypt update block")
            self.hasCipherUpdateFailure = true
            return 0
        }
    }
}

public class AESEncryptedFile {
    public enum Error : Swift.Error {
        case createStreamFailure, headerWriteFailure, headerReadFailure
    }
    
    private static let defaultSalt = "nevergonnagiveyouup"
    
    private let filePath: URL
    private let key: Array<UInt8>
    private let padding: Padding
    
    convenience init(_ filePath: URL, password: String) throws {
        try self.init(filePath, password: password, salt: AESEncryptedFile.defaultSalt)
    }
    
    convenience init(_ filePath: URL, password: String, salt: String, padding: Padding = .pkcs7) throws {
        let key = try AESEncryptedFile.deriveKey(password, salt: salt)
        self.init(filePath, key: key, padding: padding)
    }
    
    init(_ filePath: URL, key: Array<UInt8>, padding: Padding) {
        self.filePath = filePath
        self.key = key
        self.padding = padding
    }
    
    private static func deriveKey(_ password: String, salt: String) throws -> Array<UInt8> {
        return try PKCS5.PBKDF2(
            password: Array(password.utf8),
            salt: Array(salt.utf8),
            iterations: 8,
            keyLength: 32, /* AES-256 */
            variant: .sha2(SHA2.Variant.sha256)
        ).calculate()
    }
    
    public func openInputStream() throws -> InputStreamLike {
        guard let innerStream = InputStream(url: self.filePath) else {
            throw Error.createStreamFailure
        }
        
        innerStream.open()
        
        // slice off the IV from the start of the file
        var iv = [UInt8](repeating: 0, count: AES.blockSize)
        let bytesRead = innerStream.read(&iv, maxLength: iv.count)
        
        if bytesRead != iv.count {
            innerStream.close()
            throw Error.headerReadFailure
        }
        
        let blockMode = CBC(iv: iv)
        let cryptor = try AES(key: self.key, blockMode: blockMode, padding: self.padding).makeDecryptor()
        
        return CipherInputStream(cryptor, forStream: innerStream)
    }
    
    public func openOutputStream() throws -> OutputStreamLike {
        guard let innerStream = OutputStream(url: self.filePath, append: false) else {
            throw Error.createStreamFailure
        }
        
        let iv = AES.randomIV(AES.blockSize)
        let blockMode = CBC(iv: iv)
        let cryptor = try AES(key: self.key, blockMode: blockMode, padding: self.padding).makeEncryptor()
        
        innerStream.open()
        
        // write IV as the header of the file so we can decrypt it later
        let bytesWritten = innerStream.write(iv, maxLength: iv.count)
        
        if bytesWritten != iv.count {
            innerStream.close()
            throw Error.headerWriteFailure
        }
        
        return CipherOutputStream(cryptor, forStream: innerStream)
    }
}
