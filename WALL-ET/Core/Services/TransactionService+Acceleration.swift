import Foundation

@MainActor
extension TransactionService {
    struct AccelerationContext {
        let wallet: WalletModel
        let decodedTransaction: DecodedTransaction
        let inputUTXOs: [UTXO]
        let signingKeys: [Data]
        let ownedAddresses: Set<String>
        let changeAddress: String
        let builder: TransactionBuilder
    }

    func makeAccelerationContext(for transactionId: String) async throws -> AccelerationContext {
        let wallet = try await resolveActiveWallet()
        let addressInfos = repository.addressInfos(for: wallet.id)
        let ownedAddresses = Set(addressInfos.map { $0.address })
        let changeAddress = await repository.changeAddress(for: wallet.id) ?? wallet.address
        let decodedTransaction = try await fetchAndDecodeTx(transactionId)
        let builder = transactionBuilderFactory(electrum.currentNetwork)

        guard let meta = repository.walletMeta(for: wallet.id) else {
            throw NSError(domain: "TransactionService", code: -3, userInfo: [NSLocalizedDescriptionKey: "Wallet metadata not found"])
        }

        let keyName = "\(Constants.Keychain.walletSeed)_\(meta.name)"
        guard let mnemonic = try? KeychainService().loadString(for: keyName) else {
            throw NSError(domain: "TransactionService", code: -4, userInfo: [NSLocalizedDescriptionKey: "Seed not available"])
        }

        let seed = MnemonicService.shared.mnemonicToSeed(mnemonic)
        let infoMap: [String: WalletAddressInfo] = addressInfos.reduce(into: [:]) { result, info in
            result[info.address] = info
        }

        var inputUTXOs: [UTXO] = []
        var signingKeys: [Data] = []
        for vin in decodedTransaction.inputs {
            let parent = try await fetchAndDecodeTx(vin.prevTxid)
            guard vin.vout < parent.outputs.count else { continue }
            let prev = parent.outputs[vin.vout]
            guard let address = prev.address else { throw TransactionError.privateKeyMismatch }
            guard let info = infoMap[address] else { throw TransactionError.privateKeyMismatch }

            let outpoint = Outpoint(
                txid: Data(vin.prevTxid.hexStringToData().reversed()),
                vout: UInt32(vin.vout)
            )
            let utxo = UTXO(
                outpoint: outpoint,
                value: prev.value,
                scriptPubKey: prev.scriptPubKey,
                address: address,
                confirmations: 0
            )
            inputUTXOs.append(utxo)

            let chain = info.isChange ? 1 : 0
            let path = "\(meta.basePath)/\(chain)/\(info.index)"
            let (privKey, _) = MnemonicService.shared.deriveAddress(from: seed, path: path, network: meta.network)
            signingKeys.append(privKey)
        }

        guard signingKeys.count == inputUTXOs.count else {
            throw TransactionError.privateKeyMismatch
        }

        return AccelerationContext(
            wallet: wallet,
            decodedTransaction: decodedTransaction,
            inputUTXOs: inputUTXOs,
            signingKeys: signingKeys,
            ownedAddresses: ownedAddresses,
            changeAddress: changeAddress,
            builder: builder
        )
    }

    func resolveActiveWallet() async throws -> WalletModel {
        let service = WalletService()
        let fallback = try? await service.fetchWallets()
        if let wallet = await service.getActiveWallet() ?? fallback?.first {
            return wallet
        }
        throw NSError(domain: "TransactionService", code: -2, userInfo: [NSLocalizedDescriptionKey: "No wallets available"])
    }

    func loadUTXOs(for address: String) async throws -> [ElectrumUTXO] {
        try await electrum.getUTXOs(for: address)
    }

    func loadAddressHistory(for address: String) async throws -> [[String: Any]] {
        try await electrum.getAddressHistory(for: address)
    }

    func loadTransactionHex(_ txid: String) async throws -> String {
        try await electrum.getTransaction(txid)
    }

    func loadCurrentBlockHeight() async throws -> Int {
        try await electrum.getCurrentBlockHeight()
    }

    func loadBlockTimestamp(height: Int) async throws -> Int {
        try await electrum.getBlockTimestamp(height: height)
    }

    func broadcastRawTransaction(_ hex: String) async throws -> String {
        try await electrum.broadcastTransaction(hex)
    }

    func fetchAndDecodeTx(_ txid: String) async throws -> DecodedTransaction {
        if let cached = txDecodeCache[txid] { return cached }
        let rawHex = try await loadTransactionHex(txid)
        let decoder = TransactionDecoder(network: electrum.currentNetwork)
        let decoded = try decoder.decode(rawHex: rawHex)
        txDecodeCache[txid] = decoded
        return decoded
    }

    func scriptForAddress(_ address: String) -> Data? {
        if address.starts(with: "bc1") || address.starts(with: "tb1") {
            return BitcoinService().createP2WPKHScript(for: address)
        } else {
            return BitcoinService().createP2PKHScript(for: address)
        }
    }
}
