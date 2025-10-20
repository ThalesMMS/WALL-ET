import Foundation

protocol WalletDataRepository: AnyObject {
    func fetchWallets() async throws -> [Wallet]
    func createWallet(name: String, type: WalletType) async throws -> Wallet
    func importWallet(mnemonic: String, name: String, type: WalletType) async throws -> Wallet
    func deleteWallet(by id: UUID) async throws
    func getWallet(by id: UUID) async throws -> Wallet?
    func listAllAddresses() -> [String]
    func listAddresses(for walletId: UUID) -> [String]
    func getActiveWallet() -> Wallet?
    func setActiveWallet(id: UUID)
    func ensureGapLimit(for walletId: UUID, gap: Int) async
    func getNextReceiveAddress(for walletId: UUID, gap: Int) async -> String?
    func updateAddressBalances(for walletId: UUID, balances: [String: Balance])
}

extension DefaultWalletRepository: WalletDataRepository {
    func fetchWallets() async throws -> [Wallet] { try await getAllWallets() }
}

enum WalletExportError: LocalizedError {
    case walletNotFound
    case mnemonicMissing
    case serializationFailed

    var errorDescription: String? {
        switch self {
        case .walletNotFound:
            return "Wallet not found"
        case .mnemonicMissing:
            return "Seed phrase could not be located for this wallet"
        case .serializationFailed:
            return "Failed to serialize wallet export data"
        }
    }
}

struct WalletExportPayload: Codable, Equatable {
    struct Metadata: Codable, Equatable {
        enum Kind: String, Codable {
            case software
            case watchOnly
        }

        let id: String
        let name: String
        let kind: Kind
        let network: String
        let derivationPath: String?
        let createdAt: Date
        let exportedAt: Date
    }

    struct Address: Codable, Equatable {
        let index: Int
        let address: String
    }

    let version: Int
    let metadata: Metadata
    let addresses: [Address]
    let mnemonic: String?
}

@MainActor
final class WalletService: WalletServiceProtocol {
    private let repo: WalletDataRepository
    private let keychain: KeychainServiceProtocol
    private struct CachedWalletBalance {
        var confirmed: Int64
        var unconfirmed: Int64
        var updatedAt: Date?
    }
    private var balanceCache: [UUID: CachedWalletBalance] = [:]

    init(repository: WalletDataRepository? = nil, keychainService: KeychainServiceProtocol? = nil) {
        let keychain = keychainService ?? KeychainService()
        self.keychain = keychain
        if let repository = repository {
            self.repo = repository
        } else {
            self.repo = DefaultWalletRepository(keychainService: keychain)
        }
    }

    func fetchWallets() async throws -> [WalletModel] {
        let wallets = try await repo.fetchWallets()
        return mapWallets(wallets)
    }

    func refreshWalletBalances() async throws -> [WalletModel] {
        let wallets = try await repo.fetchWallets()
        guard !wallets.isEmpty else { return [] }

        struct WalletBalanceComputation {
            let walletId: UUID
            let balances: [String: Balance]
        }

        var computations: [WalletBalanceComputation] = []
        var pendingRequests: [(UUID, [String])] = []

        for wallet in wallets {
            let uniqueAddresses = Array(Set(repo.listAddresses(for: wallet.id).filter { !$0.isEmpty }))
            if uniqueAddresses.isEmpty {
                computations.append(WalletBalanceComputation(walletId: wallet.id, balances: [:]))
            } else {
                pendingRequests.append((wallet.id, uniqueAddresses))
            }
        }

        try await withThrowingTaskGroup(of: WalletBalanceComputation.self) { group in
            for (walletId, addresses) in pendingRequests {
                group.addTask {
                    let balances = try await Self.fetchBalances(for: addresses)
                    return WalletBalanceComputation(walletId: walletId, balances: balances)
                }
            }

            for try await computation in group {
                computations.append(computation)
            }
        }

        for computation in computations {
            if !computation.balances.isEmpty {
                repo.updateAddressBalances(for: computation.walletId, balances: computation.balances)
            }
            let totals = computation.balances.values.reduce((confirmed: Int64(0), unconfirmed: Int64(0))) { partial, balance in
                (partial.confirmed + balance.confirmed, partial.unconfirmed + balance.unconfirmed)
            }
            updateCache(
                for: computation.walletId,
                confirmed: totals.confirmed,
                unconfirmed: totals.unconfirmed,
                updatedAt: Date()
            )
        }

        let refreshedWallets = try await repo.fetchWallets()
        let models = mapWallets(refreshedWallets)
        if !computations.isEmpty {
            NotificationCenter.default.post(name: .walletUpdated, object: nil)
        }
        return models
    }

    func createWallet(name: String, type: WalletType) async throws -> WalletModel {
        let wallet = try await repo.createWallet(name: name, type: type)
        return mapWallet(wallet)
    }

    func importWallet(seedPhrase: String, name: String, type: WalletType) async throws -> WalletModel {
        let wallet = try await repo.importWallet(mnemonic: seedPhrase, name: name, type: type)
        return mapWallet(wallet)
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
        guard let wallet = try await repo.getWallet(by: walletId) else { throw NSError(domain: "WalletService", code: -1) }
        return mapWallet(wallet)
    }

    func updateWallet(_ wallet: WalletModel) async throws { /* Not needed for now */ }

    func exportWallet(_ walletId: UUID) async throws -> String {
        guard let wallet = try await repo.getWallet(by: walletId) else {
            throw WalletExportError.walletNotFound
        }

        let addresses = wallet.accounts
            .sorted { $0.index < $1.index }
            .map { account in
                WalletExportPayload.Address(index: account.index, address: account.address)
            }

        let metadata = WalletExportPayload.Metadata(
            id: wallet.id.uuidString,
            name: wallet.name,
            kind: wallet.isWatchOnly ? .watchOnly : .software,
            network: wallet.type == .testnet ? "testnet" : "mainnet",
            derivationPath: wallet.isWatchOnly ? nil : (wallet.type == .testnet ? "m/84'/1'/0'" : "m/84'/0'/0'"),
            createdAt: wallet.createdAt,
            exportedAt: Date()
        )

        let mnemonic: String?
        if wallet.isWatchOnly {
            mnemonic = nil
        } else {
            let key = "\(Constants.Keychain.walletSeed)_\(wallet.name)"
            guard let phrase = try keychain.loadString(for: key), !phrase.isEmpty else {
                throw WalletExportError.mnemonicMissing
            }
            mnemonic = phrase
        }

        let payload = WalletExportPayload(
            version: 1,
            metadata: metadata,
            addresses: addresses,
            mnemonic: mnemonic
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data: Data
        do {
            data = try encoder.encode(payload)
        } catch {
            throw WalletExportError.serializationFailed
        }

        guard let json = String(data: data, encoding: .utf8) else {
            throw WalletExportError.serializationFailed
        }

        return json
    }

    private func mapWallets(_ wallets: [Wallet]) -> [WalletModel] {
        wallets.map { mapWallet($0) }
    }

    private func mapWallet(_ wallet: Wallet) -> WalletModel {
        let totals = aggregatedBalance(for: wallet)
        updateCache(for: wallet.id, confirmed: totals.confirmed, unconfirmed: totals.unconfirmed)
        let confirmedBTC = Double(totals.confirmed).satoshisToBitcoin()
        let unconfirmedBTC = Double(totals.unconfirmed).satoshisToBitcoin()
        let primaryAddress = wallet.accounts.sorted { $0.index < $1.index }.first?.address ?? ""
        let isTestnet = wallet.type == .testnet
        let derivation = isTestnet ? "m/84'/1'/0'" : "m/84'/0'/0'"
        let lastUpdated = balanceCache[wallet.id]?.updatedAt

        return WalletModel(
            id: wallet.id,
            name: wallet.name,
            address: primaryAddress,
            confirmedBalance: confirmedBTC,
            unconfirmedBalance: unconfirmedBTC,
            isTestnet: isTestnet,
            derivationPath: derivation,
            createdAt: wallet.createdAt,
            lastBalanceUpdate: lastUpdated
        )
    }

    private func aggregatedBalance(for wallet: Wallet) -> (confirmed: Int64, unconfirmed: Int64) {
        wallet.accounts.reduce((confirmed: Int64(0), unconfirmed: Int64(0))) { partial, account in
            (
                partial.confirmed + account.balance.confirmed,
                partial.unconfirmed + account.balance.unconfirmed
            )
        }
    }

    private func updateCache(for walletId: UUID, confirmed: Int64, unconfirmed: Int64, updatedAt: Date? = nil) {
        var cached = balanceCache[walletId] ?? CachedWalletBalance(confirmed: 0, unconfirmed: 0, updatedAt: nil)
        cached.confirmed = confirmed
        cached.unconfirmed = unconfirmed
        if let updatedAt { cached.updatedAt = updatedAt }
        balanceCache[walletId] = cached
    }

    private nonisolated static func fetchBalances(for addresses: [String]) async throws -> [String: Balance] {
        guard !addresses.isEmpty else { return [:] }
        return try await withThrowingTaskGroup(of: (String, Balance).self, returning: [String: Balance].self) { group in
            for address in addresses {
                group.addTask {
                    try await withCheckedThrowingContinuation { continuation in
                        ElectrumService.shared.getBalance(for: address) { result in
                            switch result {
                            case .success(let balance):
                                let mapped = Balance(confirmed: balance.confirmed, unconfirmed: balance.unconfirmed)
                                continuation.resume(returning: (address, mapped))
                            case .failure(let error):
                                continuation.resume(throwing: error)
                            }
                        }
                    }
                }
            }

            var results: [String: Balance] = [:]
            for try await (address, balance) in group {
                results[address] = balance
            }
            return results
        }
    }

    // MARK: - Active wallet helpers
    func getActiveWallet() async -> WalletModel? {
        if let w = repo.getActiveWallet() {
            return mapWallet(w)
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
