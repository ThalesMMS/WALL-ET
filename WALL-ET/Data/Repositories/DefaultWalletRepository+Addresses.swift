import Foundation

extension DefaultWalletRepository {
    // MARK: - Address listing helpers
    func getActiveWallet() -> Wallet? {
        guard let entity = persistence.getActiveWallet() else { return nil }
        return mapWalletEntityToDomain(entity)
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

    func updateAddressBalances(for walletId: UUID, balances: [String: Balance]) {
        guard !balances.isEmpty else { return }
        let wallets = persistence.getAllWallets()
        guard let entity = wallets.first(where: { ($0.id ?? UUID()) == walletId }) else { return }
        let addressEntities = persistence.getAddresses(for: entity)
        for addressEntity in addressEntities {
            guard let address = addressEntity.address, let balance = balances[address] else { continue }
            persistence.updateAddressBalance(
                addressEntity,
                balance: balance.confirmed,
                unconfirmedBalance: balance.unconfirmed
            )
        }
    }

    // MARK: - Gap limit scanning
    func ensureGapLimit(for walletId: UUID, gap: Int = 20) async {
        let wallets = persistence.getAllWallets()
        guard let entity = wallets.first(where: { ($0.id ?? UUID()) == walletId }) else { return }
        guard let name = entity.name else { return }

        let basePath = entity.derivationPath ?? defaultBasePath(for: entity)
        let network = entity.network == "mainnet" ? BitcoinService.Network.mainnet : .testnet

        if persistence.getAddresses(for: entity, isChange: true).isEmpty {
            if let addr = try? derivationService.deriveAddress(
                for: name,
                path: "\(basePath)/1/0",
                network: network
            ).address {
                _ = persistence.addAddress(
                    to: entity,
                    address: addr,
                    type: "p2wpkh",
                    index: 0,
                    isChange: true
                )
            }
        }

        var unused = 0
        var index: Int32 = Int32(persistence.getAddresses(for: entity, isChange: false).map { $0.derivationIndex }.max() ?? -1)
        index += 1

        while unused < gap {
            guard let addr = try? derivationService.deriveAddress(
                for: name,
                path: "\(basePath)/0/\(index)",
                network: network
            ).address else { break }

            let historyResult: Result<[[String: Any]], Error> = await withCheckedContinuation { cont in
                ElectrumService.shared.getAddressHistory(for: addr) { cont.resume(returning: $0) }
            }

            switch historyResult {
            case .failure:
                return
            case .success(let arr):
                _ = persistence.addAddress(
                    to: entity,
                    address: addr,
                    type: "p2wpkh",
                    index: index,
                    isChange: false
                )
                unused = arr.isEmpty ? (unused + 1) : 0
                index += 1
            }
        }
    }

    func getNextReceiveAddress(for walletId: UUID, gap: Int = 20) async -> String? {
        await ensureGapLimit(for: walletId, gap: gap)
        let wallets = persistence.getAllWallets()
        guard let entity = wallets.first(where: { ($0.id ?? UUID()) == walletId }) else { return nil }
        guard let name = entity.name else { return nil }

        let network = entity.network == "mainnet" ? BitcoinService.Network.mainnet : .testnet
        let basePath = entity.derivationPath ?? defaultBasePath(for: entity)
        let ext = persistence.getAddresses(for: entity, isChange: false)

        for entry in ext {
            guard let addr = entry.address else { continue }
            let hasHistory = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                ElectrumService.shared.getAddressHistory(for: addr) { result in
                    switch result {
                    case .success(let arr):
                        cont.resume(returning: !arr.isEmpty)
                    case .failure:
                        cont.resume(returning: false)
                    }
                }
            }
            if !hasHistory { return addr }
        }

        let nextIndex = (ext.map { Int($0.derivationIndex) }.max() ?? -1) + 1
        guard let address = try? derivationService.deriveAddress(
            for: name,
            path: "\(basePath)/0/\(nextIndex)",
            network: network
        ).address else { return nil }

        _ = persistence.addAddress(
            to: entity,
            address: address,
            type: "p2wpkh",
            index: Int32(nextIndex),
            isChange: false
        )

        return address
    }

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
        guard let name = entity.name else { return nil }
        let base = entity.derivationPath ?? defaultBasePath(for: entity)
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

private extension DefaultWalletRepository {
    func defaultBasePath(for entity: WalletEntity) -> String {
        let coin = entity.network == "mainnet" ? 0 : 1
        return "m/84'/\(coin)'/0'"
    }
}

// MARK: - Protocol Conformance
@MainActor
extension DefaultWalletRepository: TransactionAccelerationRepository {
    func addressInfos(for walletId: UUID) -> [WalletAddressInfo] {
        getAddressInfos(for: walletId).map { info in
            WalletAddressInfo(address: info.address, isChange: info.isChange, index: Int(info.index))
        }
    }

    func walletMeta(for walletId: UUID) -> (name: String, basePath: String, network: BitcoinService.Network)? {
        getWalletMeta(for: walletId)
    }

    func changeAddress(for walletId: UUID) async -> String? {
        await getChangeAddress(for: walletId)
    }
}
