import Foundation

@MainActor
final class DefaultWalletRepository: WalletRepositoryProtocol {
    private let persistence = WalletRepository()
    private let keychain: KeychainServiceProtocol
    private let electrum = ElectrumService.shared
    private let bitcoin = BitcoinService(network: .testnet)
    private let transactionsAdapter: TransactionsAdapterProtocol
    private let derivationService: WalletDerivationServicing
    private let transactionsPageLimit = 50

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
