import Foundation

final class DefaultWalletRepository: WalletRepositoryProtocol {
    private let persistence = WalletRepository()
    private let keychain: KeychainServiceProtocol
    private let electrum = ElectrumService.shared
    private let bitcoin = BitcoinService(network: .testnet)

    init(keychainService: KeychainServiceProtocol) {
        self.keychain = keychainService
    }

    // MARK: - Wallets
    func createWallet(name: String, type: WalletType) async throws -> Wallet {
        // Derive from mnemonic saved by use case
        let key = "\(Constants.Keychain.walletSeed)_\(name)"
        guard let mnemonic = try keychain.loadString(for: key) else {
            throw NSError(domain: "DefaultWalletRepository", code: -1, userInfo: [NSLocalizedDescriptionKey: "Mnemonic not found"])
        }
        logInfo("Creating wallet from stored mnemonic (redacted): \(redactMnemonic(mnemonic))")
        let seed = MnemonicService.shared.mnemonicToSeed(mnemonic)
        let network: BitcoinService.Network = (type == .testnet) ? .testnet : .mainnet
        let coin = (type == .testnet) ? 1 : 0
        let path = "m/84'/\(coin)'/0'/0/0"
        let (priv, address) = MnemonicService.shared.deriveAddress(from: seed, path: path, network: network)
        logInfo("Derived first address at \(path) [\(type == .testnet ? "testnet" : "mainnet")]: \(address)")

        // Persist secret
        try keychain.save(priv, for: "wallet_\(name)_priv_0")

        // Persist to CoreData
        let walletEntity = persistence.createWallet(name: name, type: "software", derivationPath: "m/84'/\(coin)'/0'", network: (type == .testnet ? "testnet" : "mainnet"))
        _ = persistence.addAddress(to: walletEntity, address: address, type: "p2wpkh", index: 0, isChange: false)
        // Make the newly created wallet active
        persistence.setActiveWallet(walletEntity)

        // Map to domain
        let pub = CryptoService.shared.derivePublicKey(from: priv, compressed: true) ?? Data()
        let account = Account(index: 0, address: address, publicKey: pub.toHexString())
        return Wallet(name: name, type: type, accounts: [account])
    }

    func importWallet(mnemonic: String, name: String, type: WalletType) async throws -> Wallet {
        // Save mnemonic then derive like create
        try keychain.saveString(mnemonic, for: "\(Constants.Keychain.walletSeed)_\(name)")
        return try await createWallet(name: name, type: type)
    }

    func importWatchOnlyWallet(address: String, name: String, type: WalletType) async throws -> Wallet {
        let network = (type == .testnet) ? "testnet" : "mainnet"
        let walletEntity = persistence.createWallet(name: name, type: "watch_only", derivationPath: nil, network: network)
        _ = persistence.addAddress(to: walletEntity, address: address, type: "watch", index: 0, isChange: false)
        let account = Account(index: 0, address: address, publicKey: "")
        return Wallet(id: walletEntity.id ?? UUID(), name: name, type: type, accounts: [account], isWatchOnly: true)
    }

    func getAllWallets() async throws -> [Wallet] {
        let entities = persistence.getAllWallets()
        return entities.map { entity in
            let addresses = persistence.getAddresses(for: entity, isChange: false)
            let count = addresses.count
            let first = addresses.first?.address ?? ""
            logInfo("[Repo] getAllWallets: entity=\(entity.name ?? "Wallet"), externalCount=\(count), first=\(first.isEmpty ? "<empty>" : first)")
            let account = Account(index: 0, address: first, publicKey: "")
            let type: WalletType = (entity.network == "mainnet") ? .bitcoin : .testnet
            return Wallet(id: entity.id ?? UUID(), name: entity.name ?? "Wallet", type: type, accounts: [account], isWatchOnly: false)
        }
    }

    func getWallet(by id: UUID) async throws -> Wallet? {
        let all = try await getAllWallets()
        return all.first { $0.id == id }
    }

    func updateWallet(_ wallet: Wallet) async throws {
        // No-op for now; persistence updates flow through dedicated repositories.
    }

    func deleteWallet(by id: UUID) async throws {
        if let entity = persistence.getAllWallets().first(where: { $0.id == id }) {
            persistence.deleteWallet(entity)
        }
    }

    // MARK: - Address data
    func getBalance(for address: String) async throws -> Balance {
        try await withCheckedThrowingContinuation { cont in
            electrum.getBalance(for: address) { result in
                switch result {
                case .success(let ab):
                    cont.resume(returning: Balance(confirmed: ab.confirmed, unconfirmed: ab.unconfirmed))
                case .failure(let err):
                    cont.resume(throwing: err)
                }
            }
        }
    }

    func getTransactions(for address: String) async throws -> [Transaction] {
        // Not implemented yet; return empty
        return []
    }
}

private extension Data {
    func toHexString() -> String { map { String(format: "%02x", $0) }.joined() }
}

// MARK: - Redaction helper for logging
private func redactMnemonic(_ phrase: String) -> String {
    let ws = phrase.split(separator: " ")
    if ws.count <= 6 { return phrase }
    let head = ws.prefix(3).joined(separator: " ")
    let tail = ws.suffix(3).joined(separator: " ")
    return "\(head) … \(tail)"
}

// MARK: - Address listing helpers
extension DefaultWalletRepository {
    func getActiveWallet() -> Wallet? {
        guard let entity = persistence.getActiveWallet() else { return nil }
        let addresses = persistence.getAddresses(for: entity, isChange: false)
        let first = addresses.first?.address ?? ""
        let account = Account(index: 0, address: first, publicKey: "")
        let type: WalletType = (entity.network == "mainnet") ? .bitcoin : .testnet
        return Wallet(id: entity.id ?? UUID(), name: entity.name ?? "Wallet", type: type, accounts: [account], isWatchOnly: entity.type == "watch_only")
    }

    func setActiveWallet(id: UUID) {
        let wallets = persistence.getAllWallets()
        guard let entity = wallets.first(where: { ($0.id ?? UUID()) == id }) else { return }
        persistence.setActiveWallet(entity)
    }

    func listAddresses(for walletId: UUID) -> [String] {
        let entities = persistence.getAllWallets()
        guard let entity = entities.first(where: { ($0.id ?? UUID()) == walletId }) else { return [] }
        return persistence.getAddresses(for: entity).compactMap { $0.address }
    }
    
    func listAllAddresses() -> [String] {
        let entities = persistence.getAllWallets()
        return entities.flatMap { entity in persistence.getAddresses(for: entity).compactMap { $0.address } }
    }
}

// MARK: - Gap limit scanning
extension DefaultWalletRepository {
    func ensureGapLimit(for walletId: UUID, gap: Int = 20) async {
        let wallets = persistence.getAllWallets()
        guard let entity = wallets.first(where: { ($0.id ?? UUID()) == walletId }) else { return }
        let basePath = entity.derivationPath ?? "m/84'/1'/0'"
        let name = entity.name ?? "Wallet"
        let net: BitcoinService.Network = (entity.network == "mainnet") ? .mainnet : .testnet
        // Ensure change index 0 exists
        if persistence.getAddresses(for: entity, isChange: true).isEmpty {
            if let addr = deriveAddress(name: name, path: "\(basePath)/1/0", network: net) {
                _ = persistence.addAddress(to: entity, address: addr, type: "p2wpkh", index: 0, isChange: true)
            }
        }
        var unused = 0
        var index: Int32 = Int32(persistence.getAddresses(for: entity, isChange: false).map { $0.derivationIndex }.max() ?? -1)
        // Start from current max+1
        index += 1
        while unused < gap {
            guard let addr = deriveAddress(name: name, path: "\(basePath)/0/\(index)", network: net) else { break }
            // Check history; on failure, stop scanning to avoid drifting indices when offline.
            let historyResult: Result<[[String: Any]], Error> = await withCheckedContinuation { cont in
                ElectrumService.shared.getAddressHistory(for: addr) { cont.resume(returning: $0) }
            }
            switch historyResult {
            case .failure:
                return // abort scanning when offline or error
            case .success(let arr):
                _ = persistence.addAddress(to: entity, address: addr, type: "p2wpkh", index: index, isChange: false)
                unused = arr.isEmpty ? (unused + 1) : 0
                index += 1
            }
        }
    }
    
    private func deriveAddress(name: String, path: String, network: BitcoinService.Network) -> String? {
        guard let mnemonic = try? keychain.loadString(for: "\(Constants.Keychain.walletSeed)_\(name)") else { return nil }
        let seed = MnemonicService.shared.mnemonicToSeed(mnemonic)
        let (_, address) = MnemonicService.shared.deriveAddress(from: seed, path: path, network: network)
        logInfo("Derived address at path \(path) [\(network == .mainnet ? "mainnet" : "testnet")]: \(address)")
        return address
    }

    // Compute next unused external receive address using history (gap-limit aware)
    func getNextReceiveAddress(for walletId: UUID, gap: Int = 20) async -> String? {
        await ensureGapLimit(for: walletId, gap: gap)
        let wallets = persistence.getAllWallets()
        guard let entity = wallets.first(where: { ($0.id ?? UUID()) == walletId }) else { return nil }
        let net: BitcoinService.Network = (entity.network == "mainnet") ? .mainnet : .testnet
        let ext = persistence.getAddresses(for: entity, isChange: false)
        // Iterate in order; find first with no history
        for a in ext {
            guard let addr = a.address else { continue }
            let hasHistory = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                ElectrumService.shared.getAddressHistory(for: addr) { result in
                    switch result { case .success(let arr): cont.resume(returning: !arr.isEmpty); case .failure: cont.resume(returning: false) }
                }
            }
            if !hasHistory { return addr }
        }
        // If all have history, derive next index and return it
        let basePath = entity.derivationPath ?? "m/84'/1'/0'"
        let nextIndex = (ext.map { Int($0.derivationIndex) }.max() ?? -1) + 1
        if let name = entity.name, let addr = deriveAddress(name: name, path: "\(basePath)/0/\(nextIndex)", network: net) {
            _ = persistence.addAddress(to: entity, address: addr, type: "p2wpkh", index: Int32(nextIndex), isChange: false)
            return addr
        }
        return nil
    }

    // Additional helpers for transaction building/signing
    struct AddressInfo { let address: String; let isChange: Bool; let index: Int32 }
    func getAddressInfos(for walletId: UUID) -> [AddressInfo] {
        let wallets = persistence.getAllWallets()
        guard let entity = wallets.first(where: { ($0.id ?? UUID()) == walletId }) else { return [] }
        let entities = persistence.getAddresses(for: entity)
        return entities.compactMap { AddressInfo(address: $0.address ?? "", isChange: $0.isChange, index: $0.derivationIndex) }
    }
    
    func getWalletMeta(for walletId: UUID) -> (name: String, basePath: String, network: BitcoinService.Network)? {
        let wallets = persistence.getAllWallets()
        guard let entity = wallets.first(where: { ($0.id ?? UUID()) == walletId }) else { return nil }
        let name = entity.name ?? "Wallet"
        let base = entity.derivationPath ?? "m/84'/1'/0'"
        let net: BitcoinService.Network = (entity.network == "mainnet") ? .mainnet : .testnet
        return (name, base, net)
    }
    
    func getChangeAddress(for walletId: UUID) async -> String? {
        await ensureGapLimit(for: walletId, gap: 0)
        let wallets = persistence.getAllWallets()
        guard let entity = wallets.first(where: { ($0.id ?? UUID()) == walletId }) else { return nil }
        let change = persistence.getAddresses(for: entity, isChange: true)
        return change.first?.address
    }
}
