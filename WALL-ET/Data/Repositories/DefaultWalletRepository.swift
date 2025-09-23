import Foundation

@MainActor
final class DefaultWalletRepository: WalletRepositoryProtocol {
    let persistence = WalletRepository()
    let keychain: KeychainServiceProtocol
    let electrum = ElectrumService.shared
    let bitcoin = BitcoinService(network: .testnet)
    let transactionsAdapter: TransactionsAdapterProtocol
    let derivationService: WalletDerivationServicing
    let transactionsPageLimit = 50

    init(
        keychainService: KeychainServiceProtocol,
        transactionsAdapter: TransactionsAdapterProtocol = ElectrumTransactionsAdapter(),
        derivationService: WalletDerivationServicing? = nil
    ) {
        self.keychain = keychainService
        self.transactionsAdapter = transactionsAdapter
        self.derivationService = derivationService ?? WalletDerivationService(keychain: keychainService)
    }
}
