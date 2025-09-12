import Foundation
import Combine

final class WalletRepository: WalletRepositoryProtocol {
    private let storageService: StorageServiceProtocol
    private let keychainService: KeychainServiceProtocol
    private let storageKey = "wallets"
    
    init(storageService: StorageServiceProtocol, keychainService: KeychainServiceProtocol) {
        self.storageService = storageService
        self.keychainService = keychainService
    }
    
    func createWallet(name: String, type: WalletType) async throws -> Wallet {
        // Generate first account
        let account = Account(
            index: 0,
            address: generateAddress(for: type),
            publicKey: UUID().uuidString // Placeholder
        )
        
        let wallet = Wallet(
            name: name,
            type: type,
            accounts: [account]
        )
        
        // Save wallet
        var wallets = try await getAllWallets()
        wallets.append(wallet)
        try storageService.save(wallets, for: storageKey)
        
        return wallet
    }
    
    func importWallet(mnemonic: String, name: String, type: WalletType) async throws -> Wallet {
        // Validate mnemonic
        guard !mnemonic.isEmpty else {
            throw WalletError.invalidAddress
        }
        
        // Save mnemonic to keychain
        try keychainService.saveString(mnemonic, for: "\(Constants.Keychain.walletSeed)_\(name)")
        
        // Create wallet with imported seed
        return try await createWallet(name: name, type: type)
    }
    
    func importWatchOnlyWallet(address: String, name: String, type: WalletType) async throws -> Wallet {
        guard address.isValidBitcoinAddress else {
            throw WalletError.invalidAddress
        }
        
        let account = Account(
            index: 0,
            address: address,
            publicKey: "" // Watch-only doesn't have public key
        )
        
        let wallet = Wallet(
            name: name,
            type: type,
            accounts: [account],
            isWatchOnly: true
        )
        
        var wallets = try await getAllWallets()
        wallets.append(wallet)
        try storageService.save(wallets, for: storageKey)
        
        return wallet
    }
    
    func getAllWallets() async throws -> [Wallet] {
        return try storageService.load([Wallet].self, for: storageKey) ?? []
    }
    
    func getWallet(by id: UUID) async throws -> Wallet? {
        let wallets = try await getAllWallets()
        return wallets.first { $0.id == id }
    }
    
    func updateWallet(_ wallet: Wallet) async throws {
        var wallets = try await getAllWallets()
        guard let index = wallets.firstIndex(where: { $0.id == wallet.id }) else {
            throw WalletError.transactionFailed
        }
        wallets[index] = wallet
        try storageService.save(wallets, for: storageKey)
    }
    
    func deleteWallet(by id: UUID) async throws {
        var wallets = try await getAllWallets()
        wallets.removeAll { $0.id == id }
        try storageService.save(wallets, for: storageKey)
    }
    
    func getBalance(for address: String) async throws -> Balance {
        // In a real implementation, this would query a Bitcoin node or API
        // For now, return mock data
        return Balance(confirmed: 100000000, unconfirmed: 0) // 1 BTC
    }
    
    func getTransactions(for address: String) async throws -> [Transaction] {
        // In a real implementation, this would query a Bitcoin node or API
        // For now, return mock data
        return [
            Transaction(
                id: "1",
                hash: "abc123",
                type: .receive,
                amount: 50000000,
                fee: 1000,
                timestamp: Date().addingTimeInterval(-86400),
                confirmations: 6,
                status: .confirmed,
                toAddress: address
            ),
            Transaction(
                id: "2",
                hash: "def456",
                type: .send,
                amount: 10000000,
                fee: 2000,
                timestamp: Date().addingTimeInterval(-172800),
                confirmations: 12,
                status: .confirmed,
                fromAddress: address,
                toAddress: "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh"
            )
        ]
    }
    
    private func generateAddress(for type: WalletType) -> String {
        // In a real implementation, this would generate a proper Bitcoin address
        // For now, return a mock address
        switch type {
        case .bitcoin:
            return "bc1q" + UUID().uuidString.prefix(39).lowercased()
        case .testnet:
            return "tb1q" + UUID().uuidString.prefix(39).lowercased()
        }
    }
}