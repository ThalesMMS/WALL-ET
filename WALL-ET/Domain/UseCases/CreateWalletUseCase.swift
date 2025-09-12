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
        // Generate mnemonic (BIP39)
        let mnemonic = try MnemonicService.shared.generateMnemonic(strength: .words24)
        
        // Save mnemonic to keychain
        try keychainService.saveString(mnemonic, for: "\(Constants.Keychain.walletSeed)_\(name)")
        
        // Create wallet
        let wallet = try await walletRepository.createWallet(name: name, type: type)
        
        logInfo("Wallet created successfully: \(wallet.id)")
        
        return wallet
    }
    
    // Legacy placeholder removed; using MnemonicService instead
}
