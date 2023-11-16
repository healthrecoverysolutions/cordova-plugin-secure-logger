import CryptoSwift

enum EncryptedStreamState {
    case initial, opened, closed
}

public class AESEncryptedFile {
    private static let defaultSalt = "nevergonnagiveyouup"
    
    private let padding: Padding
    private let filePath: URL
    private let key: Array<UInt8>
    
    init(_ filePath: URL, password: String) throws {
        self.padding = .pkcs7
        self.filePath = filePath
        self.key = try PKCS5.PBKDF2(
            password: Array(password.utf8),
            salt: Array(AESEncryptedFile.defaultSalt.utf8),
            iterations: 4096,
            keyLength: 32, /* AES-256 */
            variant: .sha2(SHA2.Variant.sha256)
        ).calculate()
    }
    
    public func openInputStream() throws -> InputStream {
        let fileHandle = FileHandle(forReadingAtPath: filePath.path)!
        let ivData = fileHandle.readData(ofLength: AES.blockSize)
        let iv = Array(ivData)
        let blockMode = CBC(iv: iv)
        let cryptor = try AES(key: self.key, blockMode: blockMode, padding: self.padding).makeDecryptor()
        
        fileHandle.closeFile()
        
        guard let stream = EncryptedInputStream(filePath, cryptor) else {
            throw AES.Error.invalidData
        }
        
        stream.open()
        
        // eat the IV header so subsequent read calls get actual data
        var ivBuffer = [UInt8](repeating: 0, count: AES.blockSize)
        stream.readRaw(&ivBuffer, maxLength: ivBuffer.count)
        
        return stream
    }
    
    public func openOutputStream() throws -> OutputStream {
        let iv = AES.randomIV(AES.blockSize)
        let blockMode = CBC(iv: iv)
        let cryptor = try AES(key: self.key, blockMode: blockMode, padding: self.padding).makeEncryptor()
        
        guard let stream = EncryptedOutputStream(filePath, cryptor) else {
            throw AES.Error.invalidData
        }
        
        stream.open()
        
        // write IV as the header of the file so we can decrypt it later
        stream.writeRaw(iv, maxLength: iv.count)
        
        return stream
    }
    
    class EncryptedInputStream : InputStream {
        private let filePath: URL
        private var cryptor: Updatable
        private var _hasCipherUpdateFailure: Bool
        private var _state: EncryptedStreamState
        
        init?(_ filePath: URL, _ cryptor: Updatable) {
            self.filePath = filePath
            self.cryptor = cryptor
            self._hasCipherUpdateFailure = false
            self._state = .initial
            super.init(url: filePath)
        }
        
        private var hasCipherUpdateFailure: Bool {
            return _hasCipherUpdateFailure
        }
        
        private var closed: Bool {
            return _state == .closed
        }
        
        @discardableResult
        public func readRaw(_ buffer: UnsafeMutablePointer<UInt8>, maxLength len: Int) -> Int {
            if _state == .opened {
                return super.read(buffer, maxLength: len)
            } else {
                return 0
            }
        }
        
        public override func open() {
            if _state != .initial {
                return
            }
            
            super.open()
            _state = .opened
        }
        
        public override func close() {
            if closed {
                return
            }
            
            super.close()
            _state = .closed
        }
        
        @discardableResult
        public override func read(_ buffer: UnsafeMutablePointer<UInt8>, maxLength len: Int) -> Int {
            if closed || hasCipherUpdateFailure {
                return 0
            }
            
            var ciphertextBuffer = [UInt8](repeating: 0, count: len)
            super.read(&ciphertextBuffer, maxLength: len)
            
            if let plaintext = try? cryptor.update(withBytes: ciphertextBuffer) {
                buffer.update(from: plaintext, count: plaintext.count)
                return plaintext.count
            } else {
                print("EncryptedInputStream ERROR - failed to decrypt update block")
                self._hasCipherUpdateFailure = true
                return 0
            }
        }
    }
    
    class EncryptedOutputStream : OutputStream {
        private let filePath: URL
        private var cryptor: Updatable
        private var _hasCipherUpdateFailure: Bool
        private var _state: EncryptedStreamState
        
        init?(_ filePath: URL, _ cryptor: Updatable) {
            self.filePath = filePath
            self.cryptor = cryptor
            self._hasCipherUpdateFailure = false
            self._state = .initial
            super.init(url: filePath, append: false)
        }
        
        private var hasCipherUpdateFailure: Bool {
            return _hasCipherUpdateFailure
        }
        
        private var closed: Bool {
            return _state == .closed
        }
        
        @discardableResult
        public func writeRaw(_ buffer: UnsafePointer<UInt8>, maxLength len: Int) -> Int {
            if _state == .opened {
                return super.write(buffer, maxLength: len)
            } else {
                return 0
            }
        }
        
        public override func open() {
            if _state != .initial {
                return
            }
            
            super.open()
            _state = .opened
        }
        
        public override func close() {
            if closed {
                return
            }
            
            if !hasCipherUpdateFailure {
                if let ciphertext = try? cryptor.finish() {
                    super.write(ciphertext, maxLength: ciphertext.count)
                } else {
                    print("EncryptedOutputStream ERROR - failed to encrypt final block")
                    self._hasCipherUpdateFailure = true
                }
            }
            
            super.close()
            _state = .closed
        }
        
        @discardableResult
        public override func write(_ buffer: UnsafePointer<UInt8>, maxLength len: Int) -> Int {
            if closed || hasCipherUpdateFailure {
                return 0
            }
            
            let bytes = Array(UnsafeBufferPointer(start: buffer, count: len))[0..<len]
            
            if let ciphertext = try? cryptor.update(withBytes: bytes, isLast: false) {
                return super.write(ciphertext, maxLength: len)
            } else {
                print("EncryptedOutputStream ERROR - failed to encrypt update block")
                self._hasCipherUpdateFailure = true
                return 0
            }
        }
    }
}
