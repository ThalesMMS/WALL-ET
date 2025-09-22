import Foundation

@MainActor
final class TransactionService: TransactionServiceProtocol {
    private let repository: TransactionAccelerationRepository
    private let electrum: ElectrumClientProtocol
    private let feeOptimizer: FeeOptimizationServicing
    private let transactionBuilderFactory: (BitcoinService.Network) -> TransactionBuilder
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
        // Rough vbyte estimation per input by address type
        // P2WPKH ~68 vB, P2PKH ~148 vB; overhead ~10 vB; P2WPKH output ~31 vB, P2PKH ~34 vB; use 31 for dest/change typical segwit
        let overhead = 10
        var vbytes = overhead + outputs * 31
        for u in inputs {
            let addr = u.ownerAddress ?? ""
            if addr.hasPrefix("bc1") || addr.hasPrefix("tb1") { vbytes += 68 } else { vbytes += 148 }
        }
        return vbytes
    }
    
    func speedUpTransaction(_ transactionId: String) async throws { }
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

        _ = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            electrum.broadcastTransaction(rawHex) { result in
                cont.resume(with: result)
            }
        }

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
    private func fetchAllTransactions() async throws -> [TransactionModel] {
        // Electrum-only path (no external REST APIs)
        // Ensure gap-limit discovery so we include addresses that may hold history
        // Debug: reduce explored addresses to minimize log volume
        let debugGap = 3
        if let wallets = try? await WalletService().fetchWallets() {
            for w in wallets { await repository.ensureGapLimit(for: w.id, gap: debugGap) }
        }
        let addresses = repository.listAllAddresses()
        guard !addresses.isEmpty else { return [] }
        let owned = Set(addresses)
        print("[TX] total owned addresses=\(owned.count)")
        // Fetch history per address (txid + optional block height)
        let histories: [[(String, Int?)]] = try await withThrowingTaskGroup(of: [(String, Int?)].self) { group in
            for addr in owned {
                group.addTask { try await self.fetchHistory(for: addr) }
            }
            var res: [[(String, Int?)]] = []
            for try await tuples in group { res.append(tuples) }
            return res
        }
        var heightMap: [String: Int?] = [:]
        for arr in histories {
            for (h, ht) in arr {
                if let existing = heightMap[h] {
                    if existing == nil, let ht = ht { heightMap[h] = ht }
                } else {
                    heightMap[h] = ht
                }
            }
        }
        let txids = Array(heightMap.keys)
        print("[TX] unique txids total=\(txids.count)")
        // Debug: log raw tx (hex) for just one txid to avoid huge logs
        if !didLogOneRawTx, let sample = txids.first {
            let hex = try? await loadTransactionHex(sample)
            if let hex = hex {
                let preview = hex.prefix(120)
                print("[TX][RAW TX HEX SAMPLE] txid=\(sample) hex=\(preview)…")
                didLogOneRawTx = true
            }
        }
        // Current height
        let currentHeight = try await loadCurrentBlockHeight()
        print("[TX] current block height=\(currentHeight)")
        // Fetch raw transactions and build models
        let models: [TransactionModel] = try await withThrowingTaskGroup(of: TransactionModel?.self) { group in
            for txid in txids {
                let knownHeight = heightMap[txid] ?? nil
                group.addTask { try await self.buildModel(txid: txid, owned: owned, currentHeight: currentHeight, knownBlockHeight: knownHeight) }
            }
            var result: [TransactionModel] = []
            for try await m in group { if let m = m { result.append(m) } }
            let sorted = result.sorted { $0.date > $1.date }
            print("[TX] built models=\(sorted.count)")
            return sorted
        }
        return models
    }

    
    
    private func fetchHistory(for address: String) async throws -> [(String, Int?)] {
        let arr = try await loadAddressHistory(for: address)
        let tuples: [(String, Int?)] = arr.compactMap { item in
            guard let h = item["tx_hash"] as? String else { return nil }
            let height = (item["height"] as? Int).flatMap { $0 > 0 ? $0 : nil }
            return (h, height)
        }
        print("[TX] address=\(address) txids=\(tuples.count)")
        return tuples
    }

    private func buildModel(txid: String, owned: Set<String>, currentHeight: Int, knownBlockHeight: Int?) async throws -> TransactionModel? {
        let tx = try await fetchAndDecodeTx(txid)
        let height = knownBlockHeight
        let confirmations = height != nil ? max(0, currentHeight - height! + 1) : 0
        let status: TransactionStatus = (height != nil && confirmations >= 6) ? .confirmed : .pending

        // Sum outputs to our addresses
        var toOwnedSats: Int64 = 0
        var firstExternalAddress: String = ""
        var outputsTotal: Int64 = 0
        for o in tx.outputs {
            outputsTotal += o.value
            if let a = o.address, owned.contains(a) { toOwnedSats += o.value }
            else if firstExternalAddress.isEmpty, let a = o.address { firstExternalAddress = a }
        }

        // Sum inputs and fromOwned via prevouts
        var fromOwnedSats: Int64 = 0
        var inputsTotal: Int64 = 0
        var vinCount = 0
        for vin in tx.inputs {
            let parent = try await fetchAndDecodeTx(vin.prevTxid)
            if vin.vout < parent.outputs.count {
                let prev = parent.outputs[vin.vout]
                inputsTotal += prev.value
                if let a = prev.address, owned.contains(a) { fromOwnedSats += prev.value }
            }
            vinCount += 1
        }

        let feeSats = max(0, inputsTotal - outputsTotal)
        let netSats = toOwnedSats - fromOwnedSats
        let tType: TransactionModel.TransactionType = netSats >= 0 ? .received : .sent
        let amountBTC = Double(abs(netSats)) / 100_000_000.0
        let feeBTC = Double(feeSats) / 100_000_000.0
        let address = tType == .received ? (tx.outputs.first { if let a = $0.address { return owned.contains(a) } else { return false } }?.address ?? (owned.first ?? "")) : firstExternalAddress
        // Derive date from block header if available; fallback to now
        var date = Date()
        if let h = height {
            if let ts = try? await loadBlockTimestamp(height: h) {
                date = Date(timeIntervalSince1970: TimeInterval(ts))
            }
        }

        print("[TX] build txid=\(txid) vin=\(vinCount) toOwned=\(toOwnedSats) fromOwned=\(fromOwnedSats) net=\(netSats) fee=\(feeSats) conf=\(confirmations)")
        return TransactionModel(
            id: txid,
            type: tType,
            amount: amountBTC,
            fee: feeBTC,
            address: address,
            date: date,
            status: status,
            confirmations: confirmations
        )
    }
}

private extension TransactionService {
    struct AccelerationContext {
        let wallet: WalletModel
        let meta: (name: String, basePath: String, network: BitcoinService.Network)
        let decodedTx: DecodedTransaction
        let inputs: [UTXO]
        let privateKeys: [Data]
        let totalInputSats: Int64
        let estimatedOriginalFeeRate: Int
        let safeAddress: String
        let builder: TransactionBuilder
    }

    func buildAccelerationContext(for transactionId: String) async throws -> AccelerationContext {
        let walletService = WalletService()
        let fallbackWallets = try? await walletService.fetchWallets()
        guard let wallet = await walletService.getActiveWallet() ?? fallbackWallets?.first else {
            throw NSError(domain: "TransactionService", code: -10, userInfo: [NSLocalizedDescriptionKey: "No active wallet found"])
        }

        guard let meta = repo.getWalletMeta(for: wallet.id) else {
            throw NSError(domain: "TransactionService", code: -11, userInfo: [NSLocalizedDescriptionKey: "Wallet metadata not found"])
        }

        let decoded = try await fetchAndDecodeTx(transactionId)

        let infos = repo.getAddressInfos(for: wallet.id)
        let infoMap = Dictionary(uniqueKeysWithValues: infos.map { ($0.address, $0) })

        let keyName = "\(Constants.Keychain.walletSeed)_\(meta.name)"
        guard let mnemonic = try? KeychainService().loadString(for: keyName) else {
            throw NSError(domain: "TransactionService", code: -12, userInfo: [NSLocalizedDescriptionKey: "Seed not available for wallet"])
        }
        let seed = MnemonicService.shared.mnemonicToSeed(mnemonic)

        var utxos: [UTXO] = []
        var privateKeys: [Data] = []
        var totalInput: Int64 = 0

        for input in decoded.inputs {
            let parent = try await fetchAndDecodeTx(input.prevTxid)
            guard input.vout < parent.outputs.count else {
                throw NSError(domain: "TransactionService", code: -13, userInfo: [NSLocalizedDescriptionKey: "Referenced output missing for input"])
            }
            let prevOutput = parent.outputs[input.vout]
            totalInput += prevOutput.value

            guard let address = prevOutput.address else {
                throw NSError(domain: "TransactionService", code: -14, userInfo: [NSLocalizedDescriptionKey: "Unable to determine address for input"])
            }

            guard let info = infoMap[address] else {
                throw NSError(domain: "TransactionService", code: -15, userInfo: [NSLocalizedDescriptionKey: "Input address \(address) is not controlled by this wallet"])
            }

            let txidData = Data(input.prevTxid.hexStringToData().reversed())
            let outpoint = Outpoint(txid: txidData, vout: UInt32(input.vout))
            let utxo = UTXO(outpoint: outpoint, value: prevOutput.value, scriptPubKey: prevOutput.scriptPubKey, address: address, confirmations: 0)
            utxos.append(utxo)

            let chain = info.isChange ? 1 : 0
            let path = "\(meta.basePath)/\(chain)/\(info.index)"
            let (privKey, _) = MnemonicService.shared.deriveAddress(from: seed, path: path, network: meta.network)
            privateKeys.append(privKey)
        }

        guard utxos.count == decoded.inputs.count, privateKeys.count == decoded.inputs.count else {
            throw TransactionError.privateKeyMismatch
        }

        let safeAddress = await repo.getChangeAddress(for: wallet.id) ?? (await repo.getNextReceiveAddress(for: wallet.id)) ?? wallet.address
        guard !safeAddress.isEmpty else {
            throw NSError(domain: "TransactionService", code: -16, userInfo: [NSLocalizedDescriptionKey: "Unable to resolve a cancellation address"])
        }

        let outputsTotal = decoded.outputs.reduce(0) { $0 + $1.value }
        let originalFee = max(0, totalInput - outputsTotal)
        let estimatedSize = max(1, estimateBuilderVBytes(inputs: utxos, outputs: decoded.outputs.count))
        let estimatedRate = max(1, Int((Double(originalFee) / Double(estimatedSize)).rounded(.up)))

        let builder = TransactionBuilder(network: ElectrumService.shared.currentNetwork)

        return AccelerationContext(
            wallet: wallet,
            meta: meta,
            decodedTx: decoded,
            inputs: utxos,
            privateKeys: privateKeys,
            totalInputSats: totalInput,
            estimatedOriginalFeeRate: estimatedRate,
            safeAddress: safeAddress,
            builder: builder
        )
    }

    func estimateBuilderFee(inputs: [UTXO], outputCount: Int, feeRate: Int) -> Int64 {
        let estimatedSize = estimateBuilderVBytes(inputs: inputs, outputs: outputCount + 1)
        return Int64(estimatedSize * feeRate)
    }

    func estimateBuilderVBytes(inputs: [UTXO], outputs: Int) -> Int {
        var size = 10
        for utxo in inputs {
            switch detectScriptType(utxo.scriptPubKey) {
            case .p2pkh:
                size += 148
            case .p2wpkh:
                size += 68
            case .p2sh:
                size += 91
            default:
                size += 148
            }
        }
        size += outputs * 34
        return size
    }

    func detectScriptType(_ script: Data) -> ScriptType {
        if script.count == 25 && script[0] == 0x76 && script[1] == 0xa9 {
            return .p2pkh
        } else if script.count == 23 && script[0] == 0xa9 {
            return .p2sh
        } else if script.count == 22 && script[0] == 0x00 && script[1] == 0x14 {
            return .p2wpkh
        } else if script.count == 34 && script[0] == 0x00 && script[1] == 0x20 {
            return .p2wsh
        } else if script.count == 34 && script[0] == 0x51 && script[1] == 0x20 {
            return .p2tr
        }
        return .unknown
    }
}
