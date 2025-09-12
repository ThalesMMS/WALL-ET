import Foundation
import CloudKit
import CryptoKit
import Combine

class WalletBackupService {
    
    static let shared = WalletBackupService()
    private let secureStorage = SecureStorageService.shared
    private let mnemonicService = MnemonicService.shared
    private let container = CKContainer(identifier: "iCloud.com.wallet.bitcoin")
    private let database = CKContainer.default().privateCloudDatabase
    
    // MARK: - Seed Phrase Backup
    
    struct SeedPhraseBackup {
        let mnemonic: String
        let createdAt: Date
        let verifiedAt: Date?
        let metadata: BackupMetadata
    }
    
    struct BackupMetadata {
        let walletName: String
        let network: String
        let derivationPath: String
        let addressCount: Int
        let hasTransactions: Bool
    }
    
    func generateSeedPhrase(strength: MnemonicService.MnemonicStrength = .words24) throws -> String {
        return try mnemonicService.generateMnemonic(strength: strength)
    }
    
    func verifySeedPhrase(_ mnemonic: String) throws -> Bool {
        return try mnemonicService.validateMnemonic(mnemonic)
    }
    
    func saveSeedPhrase(_ mnemonic: String, requiresBiometric: Bool = true) throws {
        // Validate mnemonic first
        guard try verifySeedPhrase(mnemonic) else {
            throw BackupError.invalidMnemonic
        }
        
        // Convert to seed
        let seed = mnemonicService.mnemonicToSeed(mnemonic)
        
        // Save encrypted seed
        try secureStorage.saveSeed(seed, requiresBiometric: requiresBiometric)
        
        // Mark as unverified backup
        UserDefaults.standard.set(false, forKey: "seed_phrase_verified")
        UserDefaults.standard.set(Date(), forKey: "seed_phrase_created")
    }
    
    // MARK: - Seed Phrase Verification Flow
    
    struct VerificationChallenge {
        let wordIndices: [Int]
        let mnemonic: String
        
        func verify(words: [String]) -> Bool {
            let mnemonicWords = mnemonic.split(separator: " ").map(String.init)
            
            for (index, word) in zip(wordIndices, words) {
                if mnemonicWords[index] != word.lowercased() {
                    return false
                }
            }
            
            return true
        }
    }
    
    func createVerificationChallenge() throws -> VerificationChallenge {
        // Retrieve seed and convert back to mnemonic
        let seed = try secureStorage.retrieveSeed()
        
        // For this example, we'll need to store the mnemonic separately
        // In production, you'd retrieve it from secure storage
        guard let mnemonic = UserDefaults.standard.string(forKey: "temp_mnemonic_for_verification") else {
            throw BackupError.noBackupFound
        }
        
        let words = mnemonic.split(separator: " ").map(String.init)
        
        // Select random words to verify (e.g., 3 random words)
        let indicesToVerify = (0..<words.count).shuffled().prefix(3).sorted()
        
        return VerificationChallenge(
            wordIndices: Array(indicesToVerify),
            mnemonic: mnemonic
        )
    }
    
    func markSeedPhraseAsVerified() {
        UserDefaults.standard.set(true, forKey: "seed_phrase_verified")
        UserDefaults.standard.set(Date(), forKey: "seed_phrase_verified_date")
    }
    
    // MARK: - iCloud Backup
    
    func backupToiCloud(password: String, completion: @escaping (Result<Void, Error>) -> Void) {
        Task {
            do {
                // Export encrypted backup
                let backupData = try secureStorage.exportEncryptedBackup(password: password)
                
                // Create metadata
                let metadata = createBackupMetadata()
                
                // Upload to iCloud
                try await uploadToiCloud(backupData: backupData, metadata: metadata)
                
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    func restoreFromiCloud(password: String, completion: @escaping (Result<Void, Error>) -> Void) {
        Task {
            do {
                // Fetch from iCloud
                let backupData = try await fetchFromiCloud()
                
                // Import encrypted backup
                try secureStorage.importEncryptedBackup(backupData, password: password)
                
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    private func uploadToiCloud(backupData: Data, metadata: BackupMetadata) async throws {
        let record = CKRecord(recordType: "WalletBackup")
        
        // Encrypt metadata
        let metadataJSON = try JSONEncoder().encode(metadata)
        
        record["backupData"] = backupData as CKRecordValue
        record["metadata"] = metadataJSON as CKRecordValue
        record["createdAt"] = Date() as CKRecordValue
        record["version"] = "1.0" as CKRecordValue
        
        // Save to iCloud
        _ = try await database.save(record)
        
        // Save backup date
        UserDefaults.standard.set(Date(), forKey: "last_icloud_backup")
    }
    
    private func fetchFromiCloud() async throws -> Data {
        let query = CKQuery(
            recordType: "WalletBackup",
            predicate: NSPredicate(value: true)
        )
        query.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        
        let results = try await database.records(matching: query)
        
        guard let result = results.matchResults.first?.1,
              case .success(let record) = result,
              let backupData = record["backupData"] as? Data else {
            throw BackupError.noBackupFound
        }
        
        return backupData
    }
    
    private func createBackupMetadata() -> BackupMetadata {
        let walletRepo = WalletRepository()
        let activeWallet = walletRepo.getActiveWallet()
        
        return BackupMetadata(
            walletName: activeWallet?.name ?? "Bitcoin Wallet",
            network: activeWallet?.network ?? "mainnet",
            derivationPath: activeWallet?.derivationPath ?? "m/84'/0'/0'",
            addressCount: walletRepo.getAddresses(for: activeWallet!).count,
            hasTransactions: !walletRepo.getTransactions(for: activeWallet!).isEmpty
        )
    }
    
    // MARK: - Automatic Backup
    
    func enableAutomaticBackup(password: String) {
        UserDefaults.standard.set(true, forKey: "automatic_backup_enabled")
        
        // Schedule daily backup
        Timer.scheduledTimer(withTimeInterval: 86400, repeats: true) { _ in
            self.performAutomaticBackup(password: password)
        }
    }
    
    private func performAutomaticBackup(password: String) {
        backupToiCloud(password: password) { result in
            switch result {
            case .success:
                print("Automatic backup successful")
            case .failure(let error):
                print("Automatic backup failed: \(error)")
            }
        }
    }
    
    // MARK: - Recovery Testing
    
    func testRecoveryPhrase(_ mnemonic: String, completion: @escaping (Result<RecoveryTestResult, Error>) -> Void) {
        Task {
            do {
                // Validate mnemonic
                guard try mnemonicService.validateMnemonic(mnemonic) else {
                    throw BackupError.invalidMnemonic
                }
                
                // Generate test addresses
                let seed = mnemonicService.mnemonicToSeed(mnemonic)
                
                var addresses: [String] = []
                for i in 0..<5 {
                    let (_, address) = mnemonicService.deriveAddress(
                        from: seed,
                        path: "m/84'/0'/0'/0/\(i)",
                        network: .mainnet
                    )
                    addresses.append(address)
                }
                
                // Check if any addresses have been used
                let hasActivity = await checkAddressActivity(addresses)
                
                let result = RecoveryTestResult(
                    isValid: true,
                    generatedAddresses: addresses,
                    hasActivity: hasActivity,
                    walletAge: nil
                )
                
                completion(.success(result))
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    private func checkAddressActivity(_ addresses: [String]) async -> Bool {
        // Check with Electrum service
        for address in addresses {
            // This would check blockchain for activity
            // Simplified for example
            if UserDefaults.standard.bool(forKey: "address_\(address)_used") {
                return true
            }
        }
        return false
    }
    
    struct RecoveryTestResult {
        let isValid: Bool
        let generatedAddresses: [String]
        let hasActivity: Bool
        let walletAge: Date?
    }
    
    // MARK: - Error Types
    
    enum BackupError: LocalizedError {
        case invalidMnemonic
        case noBackupFound
        case iCloudNotAvailable
        case encryptionFailed
        case verificationFailed
        
        var errorDescription: String? {
            switch self {
            case .invalidMnemonic:
                return "Invalid recovery phrase"
            case .noBackupFound:
                return "No backup found"
            case .iCloudNotAvailable:
                return "iCloud is not available"
            case .encryptionFailed:
                return "Failed to encrypt backup"
            case .verificationFailed:
                return "Verification failed"
            }
        }
    }
}

// MARK: - Codable Extensions

extension WalletBackupService.BackupMetadata: Codable {}