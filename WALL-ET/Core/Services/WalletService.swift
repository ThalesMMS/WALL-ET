import Foundation

final class WalletService: WalletServiceProtocol {
    private let repo: DefaultWalletRepository
    init(repository: DefaultWalletRepository = DefaultWalletRepository(keychainService: KeychainService())) {
        self.repo = repository
    }

    func fetchWallets() async throws -> [WalletModel] {
        let wallets = try await repo.getAllWallets()
        return wallets.map { w in
            let address = w.accounts.first?.address ?? ""
            return WalletModel(
                id: w.id,
                name: w.name,
                address: address,
                balance: 0,
                isTestnet: (w.type == .testnet),
                derivationPath: (w.type == .testnet ? "m/84'/1'/0'" : "m/84'/0'/0'"),
                createdAt: w.createdAt
            )
        }
    }

    func createWallet(name: String, type: WalletType) async throws -> WalletModel {
        let w = try await repo.createWallet(name: name, type: type)
        let address = w.accounts.first?.address ?? ""
        return WalletModel(
            id: w.id,
            name: w.name,
            address: address,
            balance: 0,
            isTestnet: (w.type == .testnet),
            derivationPath: (w.type == .testnet ? "m/84'/1'/0'" : "m/84'/0'/0'"),
            createdAt: w.createdAt
        )
    }

    func importWallet(seedPhrase: String, name: String, type: WalletType) async throws -> WalletModel {
        let w = try await repo.importWallet(mnemonic: seedPhrase, name: name, type: type)
        let address = w.accounts.first?.address ?? ""
        return WalletModel(
            id: w.id,
            name: w.name,
            address: address,
            balance: 0,
            isTestnet: (w.type == .testnet),
            derivationPath: (w.type == .testnet ? "m/84'/1'/0'" : "m/84'/0'/0'"),
            createdAt: w.createdAt
        )
    }

    func deleteWallet(_ walletId: UUID) async throws { try await repo.deleteWallet(by: walletId) }

    func getAvailableBalance() async throws -> Double {
        // Sum confirmed + unconfirmed over all known addresses
        let addresses = repo.listAllAddresses()
        guard !addresses.isEmpty else { return 0 }
        let totalSats = try await withThrowingTaskGroup(of: Int64.self) { group in
            for addr in addresses {
                group.addTask {
                    try await withCheckedThrowingContinuation { cont in
                        ElectrumService.shared.getBalance(for: addr) { result in
                            switch result {
                            case .success(let ab): cont.resume(returning: ab.confirmed + ab.unconfirmed)
                            case .failure(let err): cont.resume(throwing: err)
                            }
                        }
                    }
                }
            }
            var sum: Int64 = 0
            for try await val in group { sum += val }
            return sum
        }
        return Double(totalSats) / 100_000_000.0
    }

    func getWalletDetails(_ walletId: UUID) async throws -> WalletModel {
        guard let w = try await repo.getWallet(by: walletId) else { throw NSError(domain: "WalletService", code: -1) }
        let address = w.accounts.first?.address ?? ""
        return WalletModel(
            id: w.id,
            name: w.name,
            address: address,
            balance: 0,
            isTestnet: (w.type == .testnet),
            derivationPath: (w.type == .testnet ? "m/84'/1'/0'" : "m/84'/0'/0'"),
            createdAt: w.createdAt
        )
    }

    func updateWallet(_ wallet: WalletModel) async throws { /* Not needed for now */ }
    func exportWallet(_ walletId: UUID) async throws -> String { "" }

    // MARK: - Active wallet helpers
    func getActiveWallet() async -> WalletModel? {
        if let w = repo.getActiveWallet() {
            let address = w.accounts.first?.address ?? ""
            return WalletModel(
                id: w.id,
                name: w.name,
                address: address,
                balance: 0,
                isTestnet: (w.type == .testnet),
                derivationPath: (w.type == .testnet ? "m/84'/1'/0'" : "m/84'/0'/0'"),
                createdAt: w.createdAt
            )
        }
        return nil
    }

    func setActiveWallet(_ walletId: UUID) async { repo.setActiveWallet(id: walletId) }

    // MARK: - Next receive address (gap-limit aware)
    func getNextReceiveAddress(for walletId: UUID, gap: Int = 20) async -> String? {
        await repo.ensureGapLimit(for: walletId, gap: gap)
        return await repo.getNextReceiveAddress(for: walletId, gap: gap)
    }
}
