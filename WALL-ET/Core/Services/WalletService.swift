import Foundation

protocol WalletDataRepository: AnyObject {
    func fetchWallets() async throws -> [Wallet]
    func createWallet(name: String, type: WalletType) async throws -> Wallet
    func importWallet(mnemonic: String, name: String, type: WalletType) async throws -> Wallet
    func deleteWallet(by id: UUID) async throws
    func getWallet(by id: UUID) async throws -> Wallet?
    func listAllAddresses() -> [String]
    func getActiveWallet() -> Wallet?
    func setActiveWallet(id: UUID)
    func ensureGapLimit(for walletId: UUID, gap: Int) async
    func getNextReceiveAddress(for walletId: UUID, gap: Int) async -> String?
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
