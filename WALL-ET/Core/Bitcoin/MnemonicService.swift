import Foundation
import CryptoKit
import CommonCrypto

// MARK: - Mnemonic Service (BIP39)
class MnemonicService {
    
    // MARK: - Properties
    static let shared = MnemonicService()
    private let wordList: [String]
    
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
        // BIP39 English word list (2048 words)
        // In production, load from a file
        return englishWordList
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
        
        // Calculate checksum
        let checksumBits = entropyBits / 32
        let hash = SHA256.hash(data: entropy)
        let checksumByte = hash.first!
        let checksum = checksumByte >> (8 - checksumBits)
        
        // Combine entropy and checksum
        var combined = entropy
        combined.append(checksum)
        
        // Convert to binary string
        let binaryString = combined.map { byte in
            String(byte, radix: 2).padLeft(toLength: 8, withPad: "0")
        }.joined()
        
        // Split into 11-bit chunks and convert to words
        let totalBits = entropyBits + checksumBits
        var words: [String] = []
        
        for i in stride(from: 0, to: totalBits, by: 11) {
            let startIndex = binaryString.index(binaryString.startIndex, offsetBy: i)
            let endIndex = binaryString.index(startIndex, offsetBy: 11)
            let chunk = String(binaryString[startIndex..<endIndex])
            
            if let index = Int(chunk, radix: 2) {
                words.append(wordList[index])
            }
        }
        
        return words.joined(separator: " ")
    }
    
    // MARK: - Mnemonic Validation
    func validateMnemonic(_ mnemonic: String) throws -> Bool {
        let words = mnemonic.lowercased().split(separator: " ").map(String.init)
        
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
        
        // Split entropy and checksum
        let totalBits = words.count * 11
        let checksumBits = totalBits / 33
        let entropyBits = totalBits - checksumBits
        
        let entropyBinary = String(binaryString.prefix(entropyBits))
        let checksumBinary = String(binaryString.suffix(checksumBits))
        
        // Convert entropy to data
        var entropyData = Data()
        for i in stride(from: 0, to: entropyBinary.count, by: 8) {
            let startIndex = entropyBinary.index(entropyBinary.startIndex, offsetBy: i)
            let endIndex = entropyBinary.index(startIndex, offsetBy: min(8, entropyBinary.count - i))
            let byte = String(entropyBinary[startIndex..<endIndex])
            if let value = UInt8(byte.padRight(toLength: 8, withPad: "0"), radix: 2) {
                entropyData.append(value)
            }
        }
        
        // Calculate expected checksum
        let hash = SHA256.hash(data: entropyData)
        let expectedChecksumByte = hash.first!
        let expectedChecksum = expectedChecksumByte >> (8 - checksumBits)
        let expectedChecksumBinary = String(expectedChecksum, radix: 2).padLeft(toLength: checksumBits, withPad: "0")
        
        // Verify checksum
        guard checksumBinary == expectedChecksumBinary else {
            throw MnemonicError.invalidChecksum
        }
        
        return true
    }
    
    // MARK: - Seed Generation (BIP39)
    func mnemonicToSeed(_ mnemonic: String, passphrase: String = "") -> Data {
        let salt = "mnemonic" + passphrase
        return pbkdf2(password: mnemonic, salt: salt, iterations: 2048, keyLength: 64)
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
        
        // Append index as big-endian
        var indexBytes = actualIndex.bigEndian
        data.append(Data(bytes: &indexBytes, count: 4))
        
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
            let index = UInt32(isHardened ? component.dropLast() : component) ?? 0
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
    
    private func ripemd160(_ data: Data) -> Data {
        // Simplified - use actual RIPEMD160 in production
        var digest = [UInt8](repeating: 0, count: 20)
        data.withUnsafeBytes { bytes in
            _ = CC_SHA1(bytes.baseAddress, CC_LONG(data.count), &digest)
        }
        return Data(digest)
    }
    
    private func addPrivateKeys(_ key1: Data, _ key2: Data) -> Data {
        // Simplified - implement proper secp256k1 scalar addition
        var result = Data()
        for i in 0..<32 {
            let byte1 = i < key1.count ? key1[i] : 0
            let byte2 = i < key2.count ? key2[i] : 0
            result.append((byte1 &+ byte2) & 0xFF)
        }
        return result
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

// MARK: - BIP39 English Word List (First 100 words for example)
// In production, load the complete 2048-word list from a file
private let englishWordList = [
    "abandon", "ability", "able", "about", "above", "absent", "absorb", "abstract",
    "absurd", "abuse", "access", "accident", "account", "accuse", "achieve", "acid",
    "acoustic", "acquire", "across", "act", "action", "actor", "actress", "actual",
    "adapt", "add", "addict", "address", "adjust", "admit", "adult", "advance",
    "advice", "aerobic", "affair", "afford", "afraid", "again", "age", "agent",
    "agree", "ahead", "aim", "air", "airport", "aisle", "alarm", "album",
    "alcohol", "alert", "alien", "all", "alley", "allow", "almost", "alone",
    "alpha", "already", "also", "alter", "always", "amateur", "amazing", "among",
    "amount", "amused", "analyst", "anchor", "ancient", "anger", "angle", "angry",
    "animal", "ankle", "announce", "annual", "another", "answer", "antenna", "antique",
    "anxiety", "any", "apart", "apology", "appear", "apple", "approve", "april",
    "arch", "arctic", "area", "arena", "argue", "arm", "armed", "armor",
    "army", "around", "arrange", "arrest", "arrive", "arrow", "art", "artefact"
    // ... continue with all 2048 words
]