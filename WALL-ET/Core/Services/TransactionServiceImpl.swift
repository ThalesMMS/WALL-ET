import Foundation

@MainActor
final class TransactionService: TransactionServiceProtocol {
    private let repository: TransactionAccelerationRepository
    private let electrum: ElectrumClientProtocol
    private let feeOptimizer: FeeOptimizationServicing
    private let transactionBuilderFactory: (BitcoinService.Network) -> TransactionBuilder
    private let accelerationStore = TransactionAccelerationStore.shared
    var didLogOneRawTx = false
    var txDecodeCache: [String: DecodedTransaction] = [:]

    init(
        repository: TransactionAccelerationRepository = DefaultWalletRepository(keychainService: KeychainService()),
        electrum: ElectrumClientProtocol = ElectrumService.shared,
        feeOptimizer: FeeOptimizationServicing = FeeOptimizationService.shared,
        transactionBuilderFactory: @escaping (BitcoinService.Network) -> TransactionBuilder = { TransactionBuilder(network: $0) }
    ) {
        self.repository = repository
        self.electrum = electrum
        self.feeOptimizer = feeOptimizer
        self.transactionBuilderFactory = transactionBuilderFactory
    }
    
    func fetchTransactions(page: Int, pageSize: Int) async throws -> [TransactionModel] {
        let all = try await fetchAllTransactions()
        let start = max(0, (page - 1) * pageSize)
        let end = min(all.count, start + pageSize)
        return start < end ? Array(all[start..<end]) : []
    }
    
    func fetchRecentTransactions(limit: Int) async throws -> [TransactionModel] {
        let all = try await fetchAllTransactions()
        return Array(all.prefix(limit))
    }
    
    func fetchTransaction(by id: String) async throws -> TransactionModel {
        let all = try await fetchAllTransactions()
        if let t = all.first(where: { $0.id == id }) { return t }
        throw NSError(domain: "TransactionService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Transaction not found"])
    }
    
    func sendBitcoin(to address: String, amount: Double, fee: Double, note: String?) async throws -> TransactionModel {
        // Resolve active wallet
        let active = try await resolveActiveWallet()
        // Gather addresses + metadata
        let addressInfos = repository.addressInfos(for: active.id)
        let allAddresses = addressInfos.map { $0.address }
        guard !allAddresses.isEmpty else { throw TransactionError.insufficientFunds }
        // Fetch UTXOs across all addresses
        let utxos: [ElectrumUTXO] = try await withThrowingTaskGroup(of: [ElectrumUTXO].self, returning: [ElectrumUTXO].self) { group in
            for addr in allAddresses {
                group.addTask {
                    try await self.loadUTXOs(for: addr)
                }
            }
            var acc: [ElectrumUTXO] = []
            for try await arr in group { acc.append(contentsOf: arr) }
            return acc
        }
        guard !utxos.isEmpty else { throw TransactionError.insufficientFunds }
        // Fee rate (sat/vB)
        let feeRate = (try? await FeeService().getRecommendedFeeRate()) ?? 20
        let amountSats = Int64((amount * 100_000_000.0).rounded())
        // Select coins: compare largest-first vs smallest-first, choose minimal waste including fee
        let nOutputs = 2 // dest + change
        func estimate(for sel: [ElectrumUTXO]) -> (ok: Bool, feeSats: Int64, vbytes: Int, sum: Int64) {
            let vbytes = estimateVBytes(inputs: sel, outputs: nOutputs)
            let feeSats = Int64(vbytes * feeRate)
            let sum = sel.reduce(0) { $0 + $1.value }
            let ok = sum >= amountSats + feeSats
            return (ok: ok, feeSats: feeSats, vbytes: vbytes, sum: sum)
        }
        let largest = utxos.sorted { $0.value > $1.value }
        let smallest = utxos.sorted { $0.value < $1.value }
        func accumulate(_ arr: [ElectrumUTXO]) -> ([ElectrumUTXO], (ok: Bool, feeSats: Int64, vbytes: Int, sum: Int64)) {
            var sel: [ElectrumUTXO] = []
            for u in arr { sel.append(u); let e = estimate(for: sel); if e.ok { return (sel, e) } }
            return (sel, estimate(for: sel))
        }
        let (selLarge, estLarge) = accumulate(largest)
        let (selSmall, estSmall) = accumulate(smallest)
        guard estLarge.ok || estSmall.ok else { throw TransactionError.insufficientFunds }
        let candidateA = (selLarge, estLarge)
        let candidateB = (selSmall, estSmall)
        func waste(_ c: ([ElectrumUTXO], (ok: Bool, feeSats: Int64, vbytes: Int, sum: Int64))) -> Int64 { c.1.sum - (amountSats + c.1.feeSats) }
        let best = (!estLarge.ok) ? candidateB : (!estSmall.ok) ? candidateA : (waste(candidateA) <= waste(candidateB) ? candidateA : candidateB)
        let selected = best.0
        let feeSats = best.1.feeSats
        let estVBytes = best.1.vbytes
        // Change address
        let changeAddr = await repository.changeAddress(for: active.id) ?? (active.address)
        // Build UTXO inputs for builder
        let inputs: [UTXO] = selected.map { u in
            let addr = u.ownerAddress ?? changeAddr
            let spk = scriptForAddress(addr) ?? Data()
            return UTXO(outpoint: u.outpoint, value: u.value, scriptPubKey: spk, address: addr, confirmations: max(0, u.height))
        }
        // Build transaction
        let builderNet: BitcoinService.Network = electrum.currentNetwork
        let builder = transactionBuilderFactory(builderNet)
        var tx = try builder.buildTransaction(
            inputs: inputs,
            outputs: [(address: address, amount: amountSats)],
            changeAddress: changeAddr,
            feeRate: feeRate
        )
        // Derive private keys for each input address from seed
        guard let meta = repository.walletMeta(for: active.id) else {
            throw NSError(domain: "TransactionService", code: -3, userInfo: [NSLocalizedDescriptionKey: "Wallet metadata not found"])
        }
        let keyName = "\(Constants.Keychain.walletSeed)_\(meta.name)"
        guard let mnemonic = try? KeychainService().loadString(for: keyName) else {
            throw NSError(domain: "TransactionService", code: -4, userInfo: [NSLocalizedDescriptionKey: "Seed not available"])
        }
        let seed = MnemonicService.shared.mnemonicToSeed(mnemonic)
        let infosMap = Dictionary(uniqueKeysWithValues: addressInfos.map { ($0.address, $0) })
        let privKeys: [Data] = inputs.compactMap { input in
            let a = input.address
            guard let info = infosMap[a] else { return nil }
            let chain = info.isChange ? 1 : 0
            let path = "\(meta.basePath)/\(chain)/\(info.index)"
            let (priv, _) = MnemonicService.shared.deriveAddress(from: seed, path: path, network: meta.network)
            return priv
        }
        guard privKeys.count == inputs.count else { throw TransactionError.privateKeyMismatch }
        try builder.signTransaction(&tx, with: privKeys, utxos: inputs)
        let raw = tx.serialize()
        let rawHex = raw.map { String(format: "%02x", $0) }.joined()
        // Broadcast
        let txid = try await broadcastRawTransaction(rawHex)
        return TransactionModel(
            id: txid,
            type: .sent,
            amount: amount,
            fee: Double(feeSats) / 100_000_000.0,
            address: address,
            date: Date(),
            status: .pending,
            confirmations: 0
        )
    }

    // Public estimator for UI (re-estimates after coin selection)
    func estimateFee(to address: String, amount: Double, feeRateSatPerVb: Int) async throws -> (vbytes: Int, feeSats: Int64) {
        // Resolve active wallet
        let active = try await resolveActiveWallet()
        let addressInfos = repository.addressInfos(for: active.id)
        let allAddresses = addressInfos.map { $0.address }
        guard !allAddresses.isEmpty else { throw TransactionError.insufficientFunds }
        // Fetch UTXOs across all addresses
        let utxos: [ElectrumUTXO] = try await withThrowingTaskGroup(of: [ElectrumUTXO].self, returning: [ElectrumUTXO].self) { group in
            for addr in allAddresses {
                group.addTask {
                    try await self.loadUTXOs(for: addr)
                }
            }
            var acc: [ElectrumUTXO] = []
            for try await arr in group { acc.append(contentsOf: arr) }
            return acc
        }
        let amountSats = Int64((amount * 100_000_000.0).rounded())
        let nOutputs = 2
        func estimate(for sel: [ElectrumUTXO]) -> (ok: Bool, feeSats: Int64, vbytes: Int, sum: Int64) {
            let vbytes = estimateVBytes(inputs: sel, outputs: nOutputs)
            let feeSats = Int64(vbytes * feeRateSatPerVb)
            let sum = sel.reduce(0) { $0 + $1.value }
            let ok = sum >= amountSats + feeSats
            return (ok: ok, feeSats: feeSats, vbytes: vbytes, sum: sum)
        }
        let largest = utxos.sorted { $0.value > $1.value }
        var selected: [ElectrumUTXO] = []
        var best: (ok: Bool, feeSats: Int64, vbytes: Int, sum: Int64)? = nil
        for u in largest {
            selected.append(u)
            let e = estimate(for: selected)
            if e.ok { best = e; break }
        }
        guard let b = best else { throw TransactionError.insufficientFunds }
        return (vbytes: b.vbytes, feeSats: b.feeSats)
    }

    private func estimateVBytes(inputs: [ElectrumUTXO], outputs: Int) -> Int {
        let overhead = 10
        var vbytes = overhead + outputs * 31
        for u in inputs {
            let addr = u.ownerAddress ?? ""
            if addr.hasPrefix("bc1") || addr.hasPrefix("tb1") { vbytes += 68 } else { vbytes += 148 }
        }
        return vbytes
    }
    
    func speedUpTransaction(_ transactionId: String) async throws {
        guard let context = accelerationStore.context(for: transactionId) else {
            throw TransactionError.accelerationContextMissing
        }

        let feeRates = try? await FeeService().getFeeRates()
        var targetFeeRate = context.originalFeeRate + 1
        if let rates = feeRates {
            targetFeeRate = max(Double(rates.fastest), context.originalFeeRate + 1)
        }
        if targetFeeRate <= context.originalFeeRate {
            targetFeeRate = context.originalFeeRate + 1
        }

        let rbf = try await feeOptimizer.createRBFTransaction(
            originalTxid: transactionId,
            newFeeRate: targetFeeRate,
            ownedAddresses: context.ownedAddresses
        )

        var replacementTx = rbf.replacementTx
        let builder = transactionBuilderFactory(electrum.currentNetwork)
        try builder.signTransaction(&replacementTx, with: context.privateKeys, utxos: context.utxos)

        let rawHex = replacementTx.serialize().hexString
        let newTxid = try await broadcastRawTransaction(rawHex)

        accelerationStore.completeAcceleration(for: transactionId, replacementTxid: newTxid)
        txDecodeCache.removeValue(forKey: transactionId)
    }
    
    func cancelTransaction(_ transactionId: String) async throws {
        let context = try await buildAccelerationContext(for: transactionId)

        guard context.totalInputSats > 0 else {
            throw TransactionError.insufficientFunds
        }

        let feeRates = try? await FeeService().getFeeRates()
        var aggressiveRate = max(context.estimatedOriginalFeeRate * 2, 1)
        if let rates = feeRates {
            aggressiveRate = max(aggressiveRate, rates.fastest)
        }
        if aggressiveRate <= 0 { aggressiveRate = 1 }

        let estimatedFee = estimateBuilderFee(inputs: context.inputs, outputCount: 1, feeRate: aggressiveRate)
        let spendAmount = context.totalInputSats - estimatedFee
        guard spendAmount > Int64(TransactionBuilder.Constants.dustLimit) else {
            throw TransactionError.insufficientFunds
        }

        var replacementTx = try context.builder.buildTransaction(
            inputs: context.inputs,
            outputs: [(address: context.safeAddress, amount: spendAmount)],
            changeAddress: context.safeAddress,
            feeRate: aggressiveRate
        )

        try context.builder.signTransaction(&replacementTx, with: context.privateKeys, utxos: context.inputs)

        let rawHex = replacementTx.serialize().hexString
        _ = try await broadcastRawTransaction(rawHex)

        txDecodeCache.removeValue(forKey: transactionId)
    }
    
    func exportTransactions(_ transactions: [TransactionModel], format: TransactionsViewModel.ExportFormat) async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("transactions.csv")
        let header = "id,type,amount,fee,address,date,status,confirmations\n"
        let rows = transactions.map { t in
            "\(t.id),\(t.type.rawValue),\(t.amount),\(t.fee),\(t.address),\(ISO8601DateFormatter().string(from: t.date)),\(t.status),\(t.confirmations)"
        }.joined(separator: "\n")
        try (header + rows).write(to: url, atomically: true, encoding: .utf8)
        return url
    }
    
    // MARK: - Internals
    // [Rest of the implementation with helper methods...]
}