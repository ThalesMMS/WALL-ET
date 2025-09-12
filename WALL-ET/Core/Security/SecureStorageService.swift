import Foundation
import Security
import CryptoKit
import LocalAuthentication
import CommonCrypto

// MARK: - Secure Storage Service
class SecureStorageService {
    
    // MARK: - Properties
    static let shared = SecureStorageService()
    private let keychainService = InternalKeychainService()
    private let encryptionService = EncryptionService()
    
    // MARK: - Keys
    private struct Keys {
        static let masterSeed = "wallet.master.seed"
        static let encryptionKey = "wallet.encryption.key"
        static let biometricKey = "wallet.biometric.key"
        static let pin = "wallet.pin"
        static let walletData = "wallet.data"
        static let settings = "wallet.settings"
    }
    
    // MARK: - Initialization
    private init() {
        setupEncryptionKey()
    }
    
    private func setupEncryptionKey() {
        // Generate or retrieve master encryption key
        if keychainService.retrieve(key: Keys.encryptionKey) == nil {
            let key = SymmetricKey(size: .bits256)
            let keyData = key.withUnsafeBytes { Data($0) }
            try? keychainService.save(key: Keys.encryptionKey, data: keyData, requiresBiometric: false)
        }
    }
    
    // MARK: - Seed Storage
    func saveSeed(_ seed: Data, requiresBiometric: Bool = true) throws {
        // Encrypt seed before storing
        let encryptedSeed = try encryptionService.encrypt(seed)
        
        // Store in keychain with biometric protection
        try keychainService.save(
            key: Keys.masterSeed,
            data: encryptedSeed,
            requiresBiometric: requiresBiometric
        )
    }
    
    func retrieveSeed() throws -> Data {
        guard let encryptedSeed = keychainService.retrieve(key: Keys.masterSeed) else {
            throw StorageError.seedNotFound
        }
        
        return try encryptionService.decrypt(encryptedSeed)
    }
    
    func deleteSeed() throws {
        try keychainService.delete(key: Keys.masterSeed)
    }
    
    // MARK: - Wallet Data Storage
    func saveWalletData<T: Codable>(_ data: T, key: String) throws {
        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(data)
        let encryptedData = try encryptionService.encrypt(jsonData)
        
        try keychainService.save(
            key: "wallet.data.\(key)",
            data: encryptedData,
            requiresBiometric: false
        )
    }
    
    func retrieveWalletData<T: Codable>(_ type: T.Type, key: String) throws -> T {
        guard let encryptedData = keychainService.retrieve(key: "wallet.data.\(key)") else {
            throw StorageError.dataNotFound
        }
        
        let decryptedData = try encryptionService.decrypt(encryptedData)
        let decoder = JSONDecoder()
        return try decoder.decode(type, from: decryptedData)
    }
    
    // MARK: - PIN Management
    func setPIN(_ pin: String) throws {
        let hashedPIN = SHA256.hash(data: pin.data(using: .utf8)!)
        let pinData = Data(hashedPIN)
        
        try keychainService.save(
            key: Keys.pin,
            data: pinData,
            requiresBiometric: false
        )
    }
    
    func verifyPIN(_ pin: String) -> Bool {
        guard let storedPINHash = keychainService.retrieve(key: Keys.pin) else {
            return false
        }
        
        let hashedPIN = SHA256.hash(data: pin.data(using: .utf8)!)
        let pinData = Data(hashedPIN)
        
        return pinData == storedPINHash
    }
    
    // MARK: - Secure Backup
    func exportEncryptedBackup(password: String) throws -> Data {
        // Gather all wallet data
        var backupData: [String: Data] = [:]
        
        // Add seed if exists
        if let seed = keychainService.retrieve(key: Keys.masterSeed) {
            backupData["seed"] = seed
        }
        
        // Add wallet data
        let walletKeys = keychainService.getAllKeys(prefix: "wallet.data.")
        for key in walletKeys {
            if let data = keychainService.retrieve(key: key) {
                backupData[key] = data
            }
        }
        
        // Serialize backup data
        let backupJSON = try JSONSerialization.data(withJSONObject: backupData)
        
        // Encrypt with password
        let salt = generateSalt()
        let key = deriveKey(from: password, salt: salt)
        let encryptedBackup = try encryptionService.encrypt(backupJSON, with: key)
        
        // Combine salt and encrypted data
        var finalBackup = Data()
        finalBackup.append(salt)
        finalBackup.append(encryptedBackup)
        
        return finalBackup
    }
    
    func importEncryptedBackup(_ backupData: Data, password: String) throws {
        guard backupData.count > 32 else {
            throw StorageError.invalidBackup
        }
        
        // Extract salt and encrypted data
        let salt = backupData.prefix(32)
        let encryptedData = backupData.suffix(from: 32)
        
        // Derive key and decrypt
        let key = deriveKey(from: password, salt: salt)
        let decryptedData = try encryptionService.decrypt(encryptedData, with: key)
        
        // Parse backup data
        guard let backupDict = try JSONSerialization.jsonObject(with: decryptedData) as? [String: Data] else {
            throw StorageError.invalidBackup
        }
        
        // Restore data
        for (key, value) in backupDict {
            try keychainService.save(key: key, data: value, requiresBiometric: key == Keys.masterSeed)
        }
    }
    
    // MARK: - Helper Methods
    private func generateSalt() -> Data {
        var salt = Data(count: 32)
        _ = salt.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, 32, bytes.baseAddress!)
        }
        return salt
    }
    
    private func deriveKey(from password: String, salt: Data) -> SymmetricKey {
        let passwordData = password.data(using: .utf8)!
        let derivedKey = PBKDF2.deriveKey(
            from: passwordData,
            salt: salt,
            iterations: 100_000,
            keyLength: 32
        )
        return SymmetricKey(data: derivedKey)
    }
    
    // MARK: - Wipe All Data
    func wipeAllData() throws {
        try keychainService.deleteAll()
    }
}

// MARK: - Keychain Service
class InternalKeychainService {
    
    private let serviceName = "com.wallet.bitcoin"
    
    // MARK: - Save
    func save(key: String, data: Data, requiresBiometric: Bool) throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        
        // Add biometric protection if required
        if requiresBiometric {
            let access = SecAccessControlCreateWithFlags(
                nil,
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                .biometryCurrentSet,
                nil
            )
            query[kSecAttrAccessControl as String] = access
        } else {
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }
        
        // Delete existing item
        SecItemDelete(query as CFDictionary)
        
        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }
    
    // MARK: - Retrieve
    func retrieve(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        
        return data
    }
    
    // MARK: - Delete
    func delete(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
    
    // MARK: - Delete All
    func deleteAll() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
    
    // MARK: - Get All Keys
    func getAllKeys(prefix: String) -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let items = result as? [[String: Any]] else {
            return []
        }
        
        return items.compactMap { item in
            guard let key = item[kSecAttrAccount as String] as? String,
                  key.hasPrefix(prefix) else { return nil }
            return key
        }
    }
}

// MARK: - Encryption Service
class EncryptionService {
    
    // MARK: - Encrypt
    func encrypt(_ data: Data, with key: SymmetricKey? = nil) throws -> Data {
        let actualKey = try key ?? getOrCreateMasterKey()
        
        let sealedBox = try AES.GCM.seal(data, using: actualKey)
        guard let combined = sealedBox.combined else {
            throw EncryptionError.encryptionFailed
        }
        
        return combined
    }
    
    // MARK: - Decrypt
    func decrypt(_ data: Data, with key: SymmetricKey? = nil) throws -> Data {
        let actualKey = try key ?? getOrCreateMasterKey()
        
        let sealedBox = try AES.GCM.SealedBox(combined: data)
        let decryptedData = try AES.GCM.open(sealedBox, using: actualKey)
        
        return decryptedData
    }
    
    // MARK: - Master Key Management
    private func getOrCreateMasterKey() throws -> SymmetricKey {
        let keychain = InternalKeychainService()
        let keyIdentifier = "wallet.master.encryption.key"
        
        if let keyData = keychain.retrieve(key: keyIdentifier) {
            return SymmetricKey(data: keyData)
        } else {
            let newKey = SymmetricKey(size: .bits256)
            let keyData = newKey.withUnsafeBytes { Data($0) }
            try keychain.save(key: keyIdentifier, data: keyData, requiresBiometric: false)
            return newKey
        }
    }
}

// MARK: - PBKDF2
struct PBKDF2 {
    static func deriveKey(from password: Data, salt: Data, iterations: Int, keyLength: Int) -> Data {
        var derivedKey = Data(repeating: 0, count: keyLength)
        
        derivedKey.withUnsafeMutableBytes { derivedKeyBytes in
            password.withUnsafeBytes { passwordBytes in
                salt.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress, password.count,
                        saltBytes.baseAddress, salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        derivedKeyBytes.baseAddress, keyLength
                    )
                }
            }
        }
        
        return derivedKey
    }
}

// MARK: - Biometric Authentication
class BiometricAuthService {
    
    private let context = LAContext()
    
    // MARK: - Check Availability
    func isBiometricAvailable() -> Bool {
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }
    
    var biometricType: BiometricType {
        guard isBiometricAvailable() else { return .none }
        
        switch context.biometryType {
        case .faceID:
            return .faceID
        case .touchID:
            return .touchID
        case .opticID:
            return .opticID
        default:
            return .none
        }
    }
    
    // MARK: - Authenticate
    func authenticate(reason: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        guard isBiometricAvailable() else {
            completion(.failure(BiometricError.notAvailable))
            return
        }
        
        context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: reason
        ) { success, error in
            DispatchQueue.main.async {
                if success {
                    completion(.success(true))
                } else if let error = error {
                    completion(.failure(error))
                } else {
                    completion(.failure(BiometricError.authenticationFailed))
                }
            }
        }
    }
    
    // MARK: - Types
    enum BiometricType {
        case none
        case touchID
        case faceID
        case opticID
    }
    
    enum BiometricError: LocalizedError {
        case notAvailable
        case authenticationFailed
        
        var errorDescription: String? {
            switch self {
            case .notAvailable:
                return "Biometric authentication is not available"
            case .authenticationFailed:
                return "Biometric authentication failed"
            }
        }
    }
}

// MARK: - Error Types
enum StorageError: LocalizedError {
    case seedNotFound
    case dataNotFound
    case invalidBackup
    case encryptionFailed
    case decryptionFailed
    
    var errorDescription: String? {
        switch self {
        case .seedNotFound:
            return "Wallet seed not found"
        case .dataNotFound:
            return "Requested data not found"
        case .invalidBackup:
            return "Invalid backup file"
        case .encryptionFailed:
            return "Failed to encrypt data"
        case .decryptionFailed:
            return "Failed to decrypt data"
        }
    }
}

enum KeychainError: LocalizedError {
    case saveFailed(OSStatus)
    case deleteFailed(OSStatus)
    
    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Failed to save to keychain: \(status)"
        case .deleteFailed(let status):
            return "Failed to delete from keychain: \(status)"
        }
    }
}

enum EncryptionError: LocalizedError {
    case encryptionFailed
    case decryptionFailed
    
    var errorDescription: String? {
        switch self {
        case .encryptionFailed:
            return "Encryption failed"
        case .decryptionFailed:
            return "Decryption failed"
        }
    }
}