import Foundation
import CryptoKit
import CommonCrypto

// MARK: - Mnemonic Service (BIP39)
class MnemonicService {
    
    // MARK: - Properties
    static let shared = MnemonicService()
    // Internal for tests via @testable import
    let wordList: [String]
    
    // MARK: - Enums
    enum MnemonicStrength: Int {
        case words12 = 128  // 128 bits = 12 words
        case words15 = 160  // 160 bits = 15 words
        case words18 = 192  // 192 bits = 18 words
        case words21 = 224  // 224 bits = 21 words
        case words24 = 256  // 256 bits = 24 words
        
        var wordCount: Int {
            return (rawValue + rawValue / 32) / 11
        }
    }
    
    enum MnemonicError: LocalizedError {
        case invalidWordCount
        case invalidWord(String)
        case invalidChecksum
        case invalidEntropy
        
        var errorDescription: String? {
            switch self {
            case .invalidWordCount:
                return "Invalid word count. Must be 12, 15, 18, 21, or 24 words"
            case .invalidWord(let word):
                return "Invalid word: \(word)"
            case .invalidChecksum:
                return "Invalid mnemonic checksum"
            case .invalidEntropy:
                return "Invalid entropy data"
            }
        }
    }
    
    // MARK: - Initialization
    init() {
        // Load BIP39 English word list
        self.wordList = MnemonicService.loadWordList()
    }
    
    private static func loadWordList() -> [String] {
        // Attempt to load BIP39 English word list (2048 words) from bundle.
        if let url = Bundle.main.url(forResource: "english", withExtension: "txt", subdirectory: "Resources/BIP39"),
           let wordString = try? String(contentsOf: url) {
            let words = wordString.components(separatedBy: .newlines).filter { !$0.isEmpty }
            // Validate count and fallback if incorrect.
            if words.count == 2048 { return words }
            logWarning("BIP39 wordlist from bundle has \(words.count) entries; falling back to embedded list")
        }
        // Fallback to embedded list
        let embedded = loadEmbeddedWordList()
        if embedded.count != 2048 {
            logError("Embedded BIP39 wordlist has \(embedded.count) entries; validation may fail")
        }
        return embedded
    }
    
    private static func loadEmbeddedWordList() -> [String] {
        // Load from embedded string as fallback and sanitize
        let raw = completeBIP39EnglishWordList
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        // If the embedded list is known to contain stray items (e.g., "drown", "rush"), remove them.
        var words = raw
        if words.count != 2048 {
            let extras: Set<String> = ["drown", "rush"]
            words = words.filter { !extras.contains($0) }
        }
        // Final sanity log if still not 2048
        if words.count != 2048 { logError("Embedded BIP39 wordlist has \(words.count) entries; expected 2048") }
        return words
    }
    
    // MARK: - Mnemonic Generation
    func generateMnemonic(strength: MnemonicStrength = .words24) throws -> String {
        // Generate random entropy
        let entropyBytes = strength.rawValue / 8
        var entropy = Data(count: entropyBytes)
        let result = entropy.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, entropyBytes, bytes.baseAddress!)
        }
        
        guard result == errSecSuccess else {
            throw MnemonicError.invalidEntropy
        }
        
        return try mnemonicFromEntropy(entropy)
    }
    
    func mnemonicFromEntropy(_ entropy: Data) throws -> String {
        let entropyBits = entropy.count * 8
        // Validate entropy length
        guard [128, 160, 192, 224, 256].contains(entropyBits) else {
            throw MnemonicError.invalidEntropy
        }
        // a = entropy as binary string
        let a = entropy.map { String($0, radix: 2).padLeft(toLength: 8, withPad: "0") }.joined()
        // c = sha256(entropy) as 256-bit binary string
        let hash = SHA256.hash(data: entropy)
        let c = hash.data.map { String($0, radix: 2).padLeft(toLength: 8, withPad: "0") }.joined()
        // d = first entropyBits/32 bits of c
        let checksumBits = entropyBits / 32
        let dEnd = c.index(c.startIndex, offsetBy: checksumBits)
        let d = String(c[..<dEnd])
        // b = a + d
        let b = a + d
        // Split b into 11-bit groups to map into words
        var words: [String] = []
        let groups = b.count / 11
        var cursor = b.startIndex
        for _ in 0..<groups {
            let next = b.index(cursor, offsetBy: 11)
            let chunk = String(b[cursor..<next])
            if let idx = Int(chunk, radix: 2) { words.append(wordList[idx]) }
            cursor = next
        }
        return words.joined(separator: " ")
    }
    
    // MARK: - Mnemonic Validation
    func validateMnemonic(_ mnemonic: String) throws -> Bool {
        // Normalize to NFKD and collapse whitespace (per BIP39 reference)
        let normalized = mnemonic
            .decomposedStringWithCompatibilityMapping
            .lowercased()
        let words = normalized.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        
        // Check word count
        guard [12, 15, 18, 21, 24].contains(words.count) else {
            throw MnemonicError.invalidWordCount
        }
        
        // Check all words are in word list
        var indices: [Int] = []
        for word in words {
            guard let index = wordList.firstIndex(of: word) else {
                throw MnemonicError.invalidWord(word)
            }
            indices.append(index)
        }
        
        // Convert words back to binary
        let binaryString = indices.map { index in
            String(index, radix: 2).padLeft(toLength: 11, withPad: "0")
        }.joined()
        
        // Split entropy and checksum per reference implementation
        let totalBits = words.count * 11
        let checksumBits = totalBits / 33
        let entropyBinary = String(binaryString.prefix(totalBits - checksumBits))
        let checksumBinary = String(binaryString.suffix(checksumBits))
        
        // Convert entropy to data (8 bits per byte, with no right-side padding)
        var entropyData = Data()
        var tempEntropy = entropyBinary
        while !tempEntropy.isEmpty {
            let chunk = String(tempEntropy.prefix(8))
            tempEntropy = String(tempEntropy.dropFirst(min(8, tempEntropy.count)))
            guard let byte = UInt8(chunk, radix: 2) else { throw MnemonicError.invalidEntropy }
            entropyData.append(byte)
        }
        // Compute the expected checksum from the first 'checksumBits' of the full SHA256 output (symmetric with generation)
        let hashBits = SHA256.hash(data: entropyData).data
            .map { String($0, radix: 2).padLeft(toLength: 8, withPad: "0") }
            .joined()
        let expectedChecksumBinary = String(hashBits.prefix(checksumBits))
        
        // Verify checksum
        guard checksumBinary == expectedChecksumBinary else {
            let sample = indices.prefix(8).map { String($0) }.joined(separator: ",")
            logWarning("Mnemonic checksum mismatch: expected=\(expectedChecksumBinary), got=\(checksumBinary), words=\(words.count), indices[0..7]=[\(sample)]")
            throw MnemonicError.invalidChecksum
        }
        
        return true
    }
    
    // MARK: - Seed Generation (BIP39)
    func mnemonicToSeed(_ mnemonic: String, passphrase: String = "") -> Data {
        // Per BIP39: NFKD normalize both mnemonic and passphrase, and collapse spaces
        let normMnemonic = mnemonic
            .decomposedStringWithCompatibilityMapping
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        let normPassphrase = passphrase
            .decomposedStringWithCompatibilityMapping
        let salt = "mnemonic" + normPassphrase
        return pbkdf2(password: normMnemonic, salt: salt, iterations: 2048, keyLength: 64)
    }
    
    // MARK: - HD Key Derivation (BIP32)
    func generateMasterKey(from seed: Data) -> HDKey {
        let hmac = HMAC<SHA512>.authenticationCode(for: seed, using: SymmetricKey(data: "Bitcoin seed".data(using: .utf8)!))
        let hmacData = Data(hmac)
        
        let privateKey = hmacData.prefix(32)
        let chainCode = hmacData.suffix(32)
        
        return HDKey(
            privateKey: privateKey,
            chainCode: chainCode,
            depth: 0,
            index: 0,
            parentFingerprint: Data(repeating: 0, count: 4)
        )
    }
    
    func deriveKey(from parent: HDKey, at index: UInt32, hardened: Bool = false) -> HDKey {
        let hardenedOffset: UInt32 = 0x80000000
        let actualIndex = hardened ? index + hardenedOffset : index
        
        var data = Data()
        
        if hardened {
            // Hardened derivation: use private key
            data.append(0x00)
            data.append(parent.privateKey)
        } else {
            // Non-hardened derivation: use public key
            let publicKey = BitcoinService.shared.derivePublicKey(from: parent.privateKey, compressed: true)
            data.append(publicKey)
        }
        
        // Append index as 4-byte big-endian (explicit)
        let beIndex: [UInt8] = [
            UInt8((actualIndex >> 24) & 0xff),
            UInt8((actualIndex >> 16) & 0xff),
            UInt8((actualIndex >> 8) & 0xff),
            UInt8(actualIndex & 0xff)
        ]
        data.append(contentsOf: beIndex)
        
        // Calculate HMAC
        let hmac = HMAC<SHA512>.authenticationCode(for: data, using: SymmetricKey(data: parent.chainCode))
        let hmacData = Data(hmac)
        
        let childKey = hmacData.prefix(32)
        let childChainCode = hmacData.suffix(32)
        
        // Add parent key to child key (modulo secp256k1 order)
        let childPrivateKey = addPrivateKeys(parent.privateKey, childKey)
        
        // Calculate fingerprint
        let publicKey = BitcoinService.shared.derivePublicKey(from: parent.privateKey, compressed: true)
        let hash = ripemd160(sha256(publicKey))
        let fingerprint = hash.prefix(4)
        
        return HDKey(
            privateKey: childPrivateKey,
            chainCode: childChainCode,
            depth: parent.depth + 1,
            index: actualIndex,
            parentFingerprint: fingerprint
        )
    }
    
    // MARK: - BIP44/49/84 Path Derivation
    func deriveAddress(from seed: Data, path: String, network: BitcoinService.Network = .mainnet) -> (privateKey: Data, address: String) {
        let masterKey = generateMasterKey(from: seed)
        let derivedKey = derivePath(from: masterKey, path: path)
        
        let publicKey = BitcoinService.shared.derivePublicKey(from: derivedKey.privateKey, compressed: true)
        
        // Determine address type from path
        let addressType: BitcoinService.AddressType
        if path.contains("m/44'") {
            addressType = .p2pkh  // Legacy
        } else if path.contains("m/49'") {
            addressType = .p2sh   // Nested SegWit
        } else if path.contains("m/84'") {
            addressType = .p2wpkh // Native SegWit
        } else if path.contains("m/86'") {
            addressType = .p2tr   // Taproot
        } else {
            addressType = .p2wpkh // Default to Native SegWit
        }
        
        let address = BitcoinService(network: network).generateAddress(from: publicKey, type: addressType)
        
        return (derivedKey.privateKey, address)
    }
    
    private func derivePath(from masterKey: HDKey, path: String) -> HDKey {
        let components = path.split(separator: "/").dropFirst() // Remove "m"
        
        var currentKey = masterKey
        
        for component in components {
            let isHardened = component.hasSuffix("'")
            let indexString = String(isHardened ? component.dropLast() : component)
            let index = UInt32(indexString) ?? 0
            currentKey = deriveKey(from: currentKey, at: index, hardened: isHardened)
        }
        
        return currentKey
    }
    
    // MARK: - Helper Functions
    private func pbkdf2(password: String, salt: String, iterations: Int, keyLength: Int) -> Data {
        let passwordData = password.data(using: .utf8)!
        let saltData = salt.data(using: .utf8)!
        
        var derivedKey = Data(repeating: 0, count: keyLength)
        
        let result = derivedKey.withUnsafeMutableBytes { derivedKeyBytes in
            saltData.withUnsafeBytes { saltBytes in
                passwordData.withUnsafeBytes { passwordBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress, passwordData.count,
                        saltBytes.baseAddress, saltData.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA512),
                        UInt32(iterations),
                        derivedKeyBytes.baseAddress, keyLength
                    )
                }
            }
        }
        
        return result == kCCSuccess ? derivedKey : Data()
    }
    
    private func sha256(_ data: Data) -> Data {
        return SHA256.hash(data: data).data
    }
    
    private func ripemd160(_ data: Data) -> Data { RIPEMD160.hash(data) }
    
    private func addPrivateKeys(_ key1: Data, _ key2: Data) -> Data {
        // Proper scalar addition modulo curve order using libsecp256k1
        return CryptoService.shared.tweakAddPrivateKey(key1, tweak: key2) ?? Data()
    }
}

// MARK: - HD Key Structure
struct HDKey {
    let privateKey: Data
    let chainCode: Data
    let depth: UInt8
    let index: UInt32
    let parentFingerprint: Data
    
    var extendedPrivateKey: String {
        var data = Data()
        
        // Version bytes (xprv for mainnet)
        let version: UInt32 = 0x0488ade4
        var versionBytes = version.bigEndian
        data.append(Data(bytes: &versionBytes, count: 4))
        
        // Depth
        data.append(depth)
        
        // Parent fingerprint
        data.append(parentFingerprint)
        
        // Child index
        var indexBytes = index.bigEndian
        data.append(Data(bytes: &indexBytes, count: 4))
        
        // Chain code
        data.append(chainCode)
        
        // Private key (with 0x00 prefix)
        data.append(0x00)
        data.append(privateKey)
        
        return Base58.encode(data)
    }
}

// MARK: - String Extensions
extension String {
    func padLeft(toLength: Int, withPad: String) -> String {
        let padding = String(repeating: withPad, count: max(0, toLength - count))
        return padding + self
    }
    
    func padRight(toLength: Int, withPad: String) -> String {
        let padding = String(repeating: withPad, count: max(0, toLength - count))
        return self + padding
    }
}

