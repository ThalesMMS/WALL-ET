import Foundation

protocol CreateWalletUseCaseProtocol {
    func execute(name: String, type: WalletType) async throws -> Wallet
}

final class CreateWalletUseCase: CreateWalletUseCaseProtocol {
    private let walletRepository: WalletRepositoryProtocol
    private let keychainService: KeychainServiceProtocol
    
    init(walletRepository: WalletRepositoryProtocol, keychainService: KeychainServiceProtocol) {
        self.walletRepository = walletRepository
        self.keychainService = keychainService
    }
    
    func execute(name: String, type: WalletType) async throws -> Wallet {
        // Generate mnemonic
        let mnemonic = try generateMnemonic()
        
        // Save mnemonic to keychain
        try keychainService.saveString(mnemonic, for: "\(Constants.Keychain.walletSeed)_\(name)")
        
        // Create wallet
        let wallet = try await walletRepository.createWallet(name: name, type: type)
        
        logInfo("Wallet created successfully: \(wallet.id)")
        
        return wallet
    }
    
    private func generateMnemonic() throws -> String {
        // In a real implementation, use a proper BIP39 library
        // This is a placeholder
        let words = [
            "abandon", "ability", "able", "about", "above", "absent",
            "absorb", "abstract", "absurd", "abuse", "access", "accident"
        ]
        return words.joined(separator: " ")
    }
}