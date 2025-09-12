import Foundation

final class TransactionService: TransactionServiceProtocol {
    private let repo = DefaultWalletRepository(keychainService: KeychainService())
    private let electrum = ElectrumService.shared
    
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
        let ws = WalletService()
        let fallbackList = try? await ws.fetchWallets()
        guard let active = await ws.getActiveWallet() ?? fallbackList?.first else {
            throw NSError(domain: "TransactionService", code: -2, userInfo: [NSLocalizedDescriptionKey: "No wallets available"])
        }
        // Gather addresses + metadata
        let addressInfos = repo.getAddressInfos(for: active.id)
        let allAddresses = addressInfos.map { $0.address }
        guard !allAddresses.isEmpty else { throw TransactionError.insufficientFunds }
        // Fetch UTXOs across all addresses
        let utxos: [ElectrumUTXO] = try await withThrowingTaskGroup(of: [ElectrumUTXO].self, returning: [ElectrumUTXO].self) { group in
            for addr in allAddresses {
                group.addTask {
                    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[ElectrumUTXO], Error>) in
                        ElectrumService.shared.getUTXOs(for: addr) { result in
                            switch result { case .success(let u): cont.resume(returning: u); case .failure(let e): cont.resume(throwing: e) }
                        }
                    }
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
        let changeAddr = await repo.getChangeAddress(for: active.id) ?? (active.address)
        // Build UTXO inputs for builder
        let inputs: [UTXO] = selected.map { u in
            let addr = u.ownerAddress ?? changeAddr
            let spk = scriptForAddress(addr) ?? Data()
            return UTXO(outpoint: u.outpoint, value: u.value, scriptPubKey: spk, address: addr, confirmations: max(0, u.height))
        }
        // Build transaction
        let builderNet: BitcoinService.Network = ElectrumService.shared.currentNetwork
        let builder = TransactionBuilder(network: builderNet)
        var tx = try builder.buildTransaction(
            inputs: inputs,
            outputs: [(address: address, amount: amountSats)],
            changeAddress: changeAddr,
            feeRate: feeRate
        )
        // Derive private keys for each input address from seed
        guard let meta = repo.getWalletMeta(for: active.id) else {
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
        let txid: String = try await withCheckedThrowingContinuation { cont in
            ElectrumService.shared.broadcastTransaction(rawHex) { result in
                switch result { case .success(let id): cont.resume(returning: id); case .failure(let e): cont.resume(throwing: e) }
            }
        }
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
        let ws = WalletService()
        let fallbackList = try? await ws.fetchWallets()
        guard let active = await ws.getActiveWallet() ?? fallbackList?.first else {
            throw NSError(domain: "TransactionService", code: -2, userInfo: [NSLocalizedDescriptionKey: "No wallets available"])
        }
        let addressInfos = repo.getAddressInfos(for: active.id)
        let allAddresses = addressInfos.map { $0.address }
        guard !allAddresses.isEmpty else { throw TransactionError.insufficientFunds }
        // Fetch UTXOs across all addresses
        let utxos: [ElectrumUTXO] = try await withThrowingTaskGroup(of: [ElectrumUTXO].self, returning: [ElectrumUTXO].self) { group in
            for addr in allAddresses {
                group.addTask {
                    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[ElectrumUTXO], Error>) in
                        ElectrumService.shared.getUTXOs(for: addr) { result in
                            switch result { case .success(let u): cont.resume(returning: u); case .failure(let e): cont.resume(throwing: e) }
                        }
                    }
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
    func cancelTransaction(_ transactionId: String) async throws { }
    
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
        let addresses = repo.listAllAddresses()
        guard !addresses.isEmpty else { return [] }
        let owned = Set(addresses)
        // Fetch history per address
        let histories: [[String]] = try await withThrowingTaskGroup(of: [String].self) { group in
            for addr in owned {
                group.addTask { try await self.fetchTxids(for: addr) }
            }
            var res: [[String]] = []
            for try await ids in group { res.append(ids) }
            return res
        }
        let txids = Array(Set(histories.flatMap { $0 }))
        // Current height
        let currentHeight = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Int, Error>) in
            electrum.getCurrentBlockHeight { result in
                switch result { case .success(let h): cont.resume(returning: h); case .failure(let e): cont.resume(throwing: e) }
            }
        }
        // Fetch verbose transactions and build models
        let models: [TransactionModel] = try await withThrowingTaskGroup(of: TransactionModel?.self) { group in
            for txid in txids {
                group.addTask { try await self.buildModel(txid: txid, owned: owned, currentHeight: currentHeight) }
            }
            var result: [TransactionModel] = []
            for try await m in group { if let m = m { result.append(m) } }
            return result.sorted { $0.date > $1.date }
        }
        return models
    }
    
    private func fetchTxids(for address: String) async throws -> [String] {
        try await withCheckedThrowingContinuation { cont in
            electrum.getAddressHistory(for: address) { result in
                switch result {
                case .success(let arr):
                    let ids = arr.compactMap { $0["tx_hash"] as? String }
                    cont.resume(returning: ids)
                case .failure(let e): cont.resume(throwing: e)
                }
            }
        }
    }
    
    private func fetchTxJSON(_ txid: String) async throws -> [String: Any] {
        try await withCheckedThrowingContinuation { cont in
            electrum.getTransactionVerbose(txid) { result in
                switch result { case .success(let dict): cont.resume(returning: dict); case .failure(let e): cont.resume(throwing: e) }
            }
        }
    }
    
    private func scriptForAddress(_ address: String) -> Data? {
        if address.starts(with: "bc1") || address.starts(with: "tb1") {
            return BitcoinService().createP2WPKHScript(for: address)
        } else {
            return BitcoinService().createP2PKHScript(for: address)
        }
    }
    
    private func buildModel(txid: String, owned: Set<String>, currentHeight: Int) async throws -> TransactionModel? {
        let json = try await fetchTxJSON(txid)
        let time = (json["time"] as? TimeInterval).map { Date(timeIntervalSince1970: $0) } ?? Date()
        let height = json["blockheight"] as? Int
        let confirmations = height != nil ? max(0, currentHeight - height! + 1) : 0
        let status: TransactionStatus = (height != nil && confirmations >= 6) ? .confirmed : .pending
        
        // Sum outputs to our addresses
        var toOwnedSats: Int64 = 0
        var firstExternalAddress: String = ""
        if let vouts = json["vout"] as? [[String: Any]] {
            for vout in vouts {
                // value can be BTC or sats
                let valueSats: Int64
                if let v = vout["value"] as? Double { valueSats = Int64(v * 100_000_000) }
                else if let v = vout["value"] as? Int { valueSats = Int64(v) }
                else { valueSats = 0 }
                var outAddresses: [String] = []
                if let spk = vout["scriptPubKey"] as? [String: Any] {
                    if let addrs = spk["addresses"] as? [String] { outAddresses = addrs }
                    if outAddresses.isEmpty, let asm = spk["address"] as? String { outAddresses = [asm] }
                }
                let hitOwned = outAddresses.first(where: { owned.contains($0) })
                if let _ = hitOwned {
                    toOwnedSats += valueSats
                } else if firstExternalAddress.isEmpty, let ext = outAddresses.first { firstExternalAddress = ext }
            }
        }
        // Sum inputs from our addresses by inspecting previous outputs
        var fromOwnedSats: Int64 = 0
        if let vins = json["vin"] as? [[String: Any]] {
            for vin in vins {
                guard let prevTxid = vin["txid"] as? String, let voutIndex = vin["vout"] as? Int else { continue }
                let prev = try? await fetchTxJSON(prevTxid)
                if let prevVouts = prev?["vout"] as? [[String: Any]], voutIndex < prevVouts.count {
                    let p = prevVouts[voutIndex]
                    let valueSats: Int64
                    if let v = p["value"] as? Double { valueSats = Int64(v * 100_000_000) }
                    else if let v = p["value"] as? Int { valueSats = Int64(v) }
                    else { valueSats = 0 }
                    var outAddresses: [String] = []
                    if let spk = p["scriptPubKey"] as? [String: Any] {
                        if let addrs = spk["addresses"] as? [String] { outAddresses = addrs }
                        if outAddresses.isEmpty, let a = spk["address"] as? String { outAddresses = [a] }
                    }
                    if outAddresses.contains(where: { owned.contains($0) }) {
                        fromOwnedSats += valueSats
                    }
                }
            }
        }
        let netSats = toOwnedSats - fromOwnedSats
        let amountBTC = Double(abs(netSats)) / 100_000_000.0
        let tType: TransactionModel.TransactionType = netSats >= 0 ? .received : .sent
        let address = tType == .received ? (owned.first ?? "") : firstExternalAddress
        let feeBTC: Double = {
            if let fsats = json["fee"] as? Int64 { return Double(fsats) / 100_000_000.0 }
            if let fs = json["fee"] as? Int { return Double(fs) / 100_000_000.0 }
            if let fd = json["fee"] as? Double { return fd / 100_000_000.0 }
            return 0
        }()
        return TransactionModel(
            id: txid,
            type: tType,
            amount: amountBTC,
            fee: feeBTC,
            address: address,
            date: time,
            status: status,
            confirmations: confirmations
        )
    }
}
