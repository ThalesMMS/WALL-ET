import Foundation

extension DefaultWalletRepository {
    // MARK: - Wallets
    func createWallet(name: String, type: WalletType) async throws -> Wallet {
        let derivation: AccountDerivation
        do {
            derivation = try derivationService.deriveFirstAccount(for: name, type: type)
        } catch WalletDerivationError.mnemonicNotFound {
            throw NSError(
                domain: "DefaultWalletRepository",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Mnemonic not found"]
            )
        }

        logInfo("Creating wallet from stored mnemonic (redacted): \(redactMnemonic(derivation.mnemonic))")
        let walletEntity = persistence.createWallet(
            name: name,
            type: "software",
            derivationPath: derivation.accountBasePath,
            network: derivation.network == .testnet ? "testnet" : "mainnet"
        )

        _ = persistence.addAddress(
            to: walletEntity,
            address: derivation.address,
            type: "p2wpkh",
            index: 0,
            isChange: false
        )

        try keychain.save(derivation.privateKey, for: "wallet_\(name)_priv_0")
        persistence.setActiveWallet(walletEntity)

        let pub = CryptoService.shared.derivePublicKey(from: derivation.privateKey, compressed: true) ?? Data()
        let account = Account(index: 0, address: derivation.address, publicKey: pub.toHexString())

        return Wallet(
            name: name,
            type: type,
            createdAt: walletEntity.createdAt ?? Date(),
            accounts: [account]
        )
    }

    func importWallet(mnemonic: String, name: String, type: WalletType) async throws -> Wallet {
        try derivationService.saveMnemonic(mnemonic, walletName: name)
        return try await createWallet(name: name, type: type)
    }

    func importWatchOnlyWallet(address: String, name: String, type: WalletType) async throws -> Wallet {
        let network = (type == .testnet) ? "testnet" : "mainnet"
        let walletEntity = persistence.createWallet(
            name: name,
            type: "watch_only",
            derivationPath: nil,
            network: network
        )

        _ = persistence.addAddress(
            to: walletEntity,
            address: address,
            type: "watch",
            index: 0,
            isChange: false
        )

        let account = Account(index: 0, address: address, publicKey: "")

        return Wallet(
            id: walletEntity.id ?? UUID(),
            name: name,
            type: type,
            createdAt: walletEntity.createdAt ?? Date(),
            accounts: [account],
            isWatchOnly: true
        )
    }

    func getAllWallets() async throws -> [Wallet] {
        let entities = persistence.getAllWallets()
        return entities.map(mapWalletEntityToDomain)
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

    func getBalances(for addresses: [String]) async throws -> [String: Balance] {
        var results: [String: Balance] = [:]
        for address in Set(addresses).filter({ !$0.isEmpty }) {
            results[address] = try await getBalance(for: address)
        }
        return results
    }

    func getTransactions(for address: String) async throws -> [Transaction] {
        let models = try await transactionsAdapter.transactionsSingle(
            paginationData: nil,
            limit: transactionsPageLimit
        )

        let transactions = models.map { model in
            mapTransactionModel(model, walletAddress: address)
        }
        .sorted { $0.timestamp > $1.timestamp }

        return transactions
    }
}

// MARK: - Mapping
extension DefaultWalletRepository {
    func mapWalletEntityToDomain(_ entity: WalletEntity) -> Wallet {
        let addresses = persistence.getAddresses(for: entity, isChange: false)
        let count = addresses.count
        let first = addresses.first?.address ?? ""
        let walletName = entity.name ?? "Wallet"
        let firstAddress = first.isEmpty ? "<empty>" : first
        logInfo("[Repo] mapWallet: entity=\(walletName), externalCount=\(count), first=\(firstAddress)")

        let accounts = addresses.compactMap { addressEntity -> Account? in
            guard let address = addressEntity.address else { return nil }
            let balance = Balance(
                confirmed: addressEntity.balance,
                unconfirmed: addressEntity.unconfirmedBalance
            )
            return Account(
                index: Int(addressEntity.derivationIndex),
                address: address,
                publicKey: "",
                balance: balance
            )
        }

        let type: WalletType = (entity.network == "mainnet") ? .bitcoin : .testnet
        let isWatchOnly = entity.type == "watch_only"
        return Wallet(
            id: entity.id ?? UUID(),
            name: entity.name ?? "Wallet",
            type: type,
            createdAt: entity.createdAt ?? Date(),
            accounts: accounts,
            isWatchOnly: isWatchOnly
        )
    }

    private func mapTransactionModel(_ model: TransactionModel, walletAddress: String) -> Transaction {
        let type: TransactionType
        switch model.type {
        case .sent:
            type = .send
        case .received:
            type = .receive
        }

        let fromAddress: String?
        switch type {
        case .send:
            fromAddress = walletAddress
        case .receive, .swap:
            fromAddress = nil
        }

        return Transaction(
            id: model.id,
            hash: model.id,
            type: type,
            amount: model.amount.bitcoinToSatoshis(),
            fee: model.fee.bitcoinToSatoshis(),
            timestamp: model.date,
            confirmations: model.confirmations,
            status: model.status,
            fromAddress: fromAddress,
            toAddress: model.address
        )
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
