import Foundation
import Combine

final class ElectrumTransactionsAdapter: TransactionsAdapterProtocol {
    private let electrum = ElectrumService.shared
    private var cancellables = Set<AnyCancellable>()

    // Publishers
    private let itemsUpdatedSubject = PassthroughSubject<[TransactionModel], Never>()
    private let lastBlockUpdatedSubject = PassthroughSubject<Void, Never>()

    var itemsUpdatedPublisher: AnyPublisher<[TransactionModel], Never> { itemsUpdatedSubject.eraseToAnyPublisher() }
    var lastBlockUpdatedPublisher: AnyPublisher<Void, Never> { lastBlockUpdatedSubject.eraseToAnyPublisher() }

    private(set) var lastBlockInfo: (height: Int, timestamp: Int)?

    // Index
    private var indexInvalidated = true
    private var heightMap: [String: Int?] = [:]  // txid -> height
    private var sortedTxids: [String] = []       // desc by (height, txid)

    // Decode cache
    private let txDecodeCache = LRUCache<String, DecodedTransaction>(capacity: 512)
    private var posCache: [String: Int] = [:] // key: "h|txid"
    private var headerTsCache: [Int: Int] = [:] // height -> timestamp
    private let mapLock = NSLock()
    private let maxConcurrentHistory = 6
    private let maxConcurrentDecode = 6
    private let maxConcurrentPos = 6

    init() {
        // Observe block height changes and emit updates
        electrum.blockHeightPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] h in
                guard let self = self else { return }
                self.lastBlockInfo = (height: h, timestamp: Int(Date().timeIntervalSince1970))
                self.lastBlockUpdatedSubject.send(())
            }
            .store(in: &cancellables)

        // Observe transaction updates and propagate minimal diffs (MVP: just emit empty list to trigger refresh)
        electrum.transactionUpdatePublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] update in
                // Mark index invalid; let consumer request new page
                self?.indexInvalidated = true
                self?.itemsUpdatedSubject.send([])
            }
            .store(in: &cancellables)

        // Try load persisted index for faster warm start
        loadIndexFromDisk()
        loadCachesFromDisk()
    }

    func transactionsSingle(paginationData: String?, limit: Int) async throws -> [TransactionModel] {
        await ensureIndex(minCount: limit)
        // Determine slice after cursor (height,index) cursor for stability
        let startIdx: Int = {
            guard let cur = paginationData, let cursor = parseCursor(cur) else { return 0 }
            // Find by txid first; if missing/reorg, find next lower by ordering
            if let i = sortedTxids.firstIndex(of: cursor.txid) {
                return i + 1
            }
            // Binary scan for first item strictly less than cursor (desc ordering)
            var lo = 0, hi = sortedTxids.count
            while lo < hi {
                let mid = (lo + hi) / 2
                let id = sortedTxids[mid]
                if compare(txid: id, against: cursor) { // id comes before cursor
                    hi = mid
                } else {
                    lo = mid + 1
                }
            }
            return lo
        }()
        guard startIdx < sortedTxids.count else { return [] }
        let endIdx = min(sortedTxids.count, startIdx + limit)
        let batchIds = Array(sortedTxids[startIdx..<endIdx])
        let refinedIds = try await refineOrderWithPositions(ids: batchIds)

        let currentHeight = try await currentTipHeight()
        let owned = Set(await fetchOwnedAddresses())

        // Build models with limited concurrency
        var models: [TransactionModel] = []
        models.reserveCapacity(refinedIds.count)
        let modelChunks = stride(from: 0, to: refinedIds.count, by: maxConcurrentDecode)
            .map { Array(refinedIds[$0..<min(refinedIds.count, $0+maxConcurrentDecode)]) }
        for chunk in modelChunks {
            var partial: [TransactionModel] = []
            partial.reserveCapacity(chunk.count)
            try await withThrowingTaskGroup(of: TransactionModel?.self) { group in
                for txid in chunk {
                    let h = heightMap[txid] ?? nil
                    group.addTask { try await self.buildModel(txid: txid, owned: owned, currentHeight: currentHeight, knownBlockHeight: h) }
                }
                for try await m in group { if let m = m { models.append(m); partial.append(m) } }
            }
            // Stream partial results to UI for progressive rendering
            if !partial.isEmpty { itemsUpdatedSubject.send(partial) }
        }

        // Sort by date desc to stabilize output
        models.sort { $0.date > $1.date }
        return models
    }

    // MARK: - Index
    private func ensureIndex(minCount: Int) async {
        if !indexInvalidated, !sortedTxids.isEmpty { return }
        indexInvalidated = false
        let addresses = await fetchOwnedAddresses()
        mapLock.lock(); heightMap.removeAll(keepingCapacity: true); mapLock.unlock()
        // Fetch histories in throttled batches; return early after first batch
        let chunks = stride(from: 0, to: addresses.count, by: maxConcurrentHistory)
            .map { Array(addresses[$0..<min(addresses.count, $0+maxConcurrentHistory)]) }
        var first = true
        for batch in chunks {
            await withTaskGroup(of: [(String, Int?)].self) { group in
                for addr in batch {
                    group.addTask { await self.fetchHistorySafe(for: addr) }
                }
                for await tuples in group {
                    mapLock.lock()
                    for (txid, h) in tuples {
                        if let existing = heightMap[txid] {
                            if existing == nil, let h = h { heightMap[txid] = h }
                        } else {
                            heightMap[txid] = h
                        }
                    }
                    mapLock.unlock()
                }
            }
            // after a batch, sort and optionally return early
            mapLock.lock(); sortedTxids = heightMap.keys.sorted(by: order); mapLock.unlock()
            if first { first = false; if sortedTxids.count >= minCount { break } }
        }
        saveIndexToDisk()
        // Continue scanning remaining batches in background
        Task.detached { [addresses, maxConcurrentHistory, mapLock, orderFn = self.order] in
            let start = min(maxConcurrentHistory, addresses.count)
            if start >= addresses.count { return }
            let rest = Array(addresses[start...])
            let restChunks = stride(from: 0, to: rest.count, by: maxConcurrentHistory)
                .map { Array(rest[$0..<min(rest.count, $0+maxConcurrentHistory)]) }
            for batch in restChunks {
                await withTaskGroup(of: [(String, Int?)].self) { group in
                    for addr in batch { group.addTask { await self.fetchHistorySafe(for: addr) } }
                    for await tuples in group {
                        mapLock.lock()
                        for (txid, h) in tuples {
                            if let existing = self.heightMap[txid] {
                                if existing == nil, let h = h { self.heightMap[txid] = h }
                            } else { self.heightMap[txid] = h }
                        }
                        self.sortedTxids = self.heightMap.keys.sorted(by: orderFn)
                        mapLock.unlock()
                    }
                }
                self.saveIndexToDisk()
            }
        }
    }

    private func fetchHistorySafe(for address: String) async -> [(String, Int?)] {
        await withCheckedContinuation { cont in
            electrum.getAddressHistory(for: address) { result in
                switch result {
                case .success(let arr):
                    let tuples: [(String, Int?)] = arr.compactMap { item in
                        guard let h = item["tx_hash"] as? String else { return nil }
                        let ht = (item["height"] as? Int).flatMap { $0 > 0 ? $0 : nil }
                        return (h, ht)
                    }
                    cont.resume(returning: tuples)
                case .failure:
                    cont.resume(returning: [])
                }
            }
        }
    }

    private func fetchHistory(for address: String) async throws -> [(String, Int?)] {
        try await withCheckedThrowingContinuation { cont in
            electrum.getAddressHistory(for: address) { result in
                switch result {
                case .success(let arr):
                    let tuples: [(String, Int?)] = arr.compactMap { item in
                        guard let h = item["tx_hash"] as? String else { return nil }
                        let ht = (item["height"] as? Int).flatMap { $0 > 0 ? $0 : nil }
                        return (h, ht)
                    }
                    cont.resume(returning: tuples)
                case .failure(let e): cont.resume(throwing: e)
                }
            }
        }
    }

    private func currentTipHeight() async throws -> Int {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Int, Error>) in
            electrum.getCurrentBlockHeight { cont.resume(with: $0) }
        }
    }

    // MARK: - Build Model (local decode)
    private func fetchAndDecodeTx(_ txid: String) async throws -> DecodedTransaction {
        if let c = txDecodeCache.get(txid) { return c }
        let rawHex: String = try await withCheckedThrowingContinuation { cont in
            electrum.getTransaction(txid) { cont.resume(with: $0) }
        }
        let decoder = TransactionDecoder(network: electrum.currentNetwork)
        let decoded = try decoder.decode(rawHex: rawHex)
        txDecodeCache.set(txid, decoded)
        return decoded
    }

    private func buildModel(txid: String, owned: Set<String>, currentHeight: Int, knownBlockHeight: Int?) async throws -> TransactionModel? {
        let tx = try await fetchAndDecodeTx(txid)
        let height = knownBlockHeight
        let confirmations = height != nil ? max(0, currentHeight - height! + 1) : 0
        let status: TransactionStatus = (height != nil && confirmations >= 6) ? .confirmed : .pending

        var toOwned: Int64 = 0
        var firstExternal: String = ""
        var outTotal: Int64 = 0
        for o in tx.outputs {
            outTotal += o.value
            if let a = o.address, owned.contains(a) { toOwned += o.value }
            else if firstExternal.isEmpty, let a = o.address { firstExternal = a }
        }
        var fromOwned: Int64 = 0
        var inTotal: Int64 = 0
        for vin in tx.inputs {
            let parent = try await fetchAndDecodeTx(vin.prevTxid)
            if vin.vout < parent.outputs.count {
                let prev = parent.outputs[vin.vout]
                inTotal += prev.value
                if let a = prev.address, owned.contains(a) { fromOwned += prev.value }
            }
        }
        let feeSats = max(0, inTotal - outTotal)
        let netSats = toOwned - fromOwned
        let tType: TransactionModel.TransactionType = netSats >= 0 ? .received : .sent
        let amountBTC = Double(abs(netSats)) / 100_000_000.0
        let feeBTC = Double(feeSats) / 100_000_000.0
        let address = tType == .received ? (tx.outputs.first { if let a = $0.address { return owned.contains(a) } else { return false } }?.address ?? (owned.first ?? "")) : firstExternal
        // Timestamp via header
        var date = Date()
        if let h = height {
            mapLock.lock(); let cachedTs = headerTsCache[h]; mapLock.unlock()
            if let cached = cachedTs {
                date = Date(timeIntervalSince1970: TimeInterval(cached))
            } else if let ts: Int = try? await withCheckedThrowingContinuation({ (cont: CheckedContinuation<Int, Error>) in
                electrum.getBlockTimestamp(height: h) { cont.resume(with: $0) }
            }) {
                mapLock.lock(); headerTsCache[h] = ts; mapLock.unlock(); persistCaches(); date = Date(timeIntervalSince1970: TimeInterval(ts))
            }
        }
        // Persist metadata (best-effort)
        let metaRepo = TransactionMetadataRepository()
        await metaRepo.upsert(
            txid: txid,
            amountSats: Int64(abs(netSats)),
            feeSats: feeSats,
            blockHeight: height,
            timestamp: date,
            type: (tType == .received ? "received" : "sent"),
            status: (status == .confirmed ? "confirmed" : status == .pending ? "pending" : "failed"),
            fromAddress: (tType == .sent ? nil : address),
            toAddress: (tType == .sent ? address : nil)
        )

        return TransactionModel(id: txid, type: tType, amount: amountBTC, fee: feeBTC, address: address, date: date, status: status, confirmations: confirmations)
    }

    // Refine ordering with intra-block position when available
    private func refineOrderWithPositions(ids: [String]) async throws -> [String] {
        // Group by height
        var groups: [Int: [String]] = [:]
        for id in ids {
            if let h = heightMap[id] ?? nil { groups[h, default: []].append(id) }
        }
        var result: [String] = []
        // Keep unconfirmed at end, no reordering needed
        // For confirmed groups, sort by position
        for id in ids {
            if (heightMap[id] ?? nil) == nil { result.append(id) }
        }
        // Build list of confirmed ids respecting original order of heights
        let confirmedIds = ids.filter { (heightMap[$0] ?? nil) != nil }
        // Unique heights in order
        var seenHeights = Set<Int>()
        var orderedHeights: [Int] = []
        for id in confirmedIds {
            let h = heightMap[id]!!
            if seenHeights.insert(h).inserted { orderedHeights.append(h) }
        }
        for h in orderedHeights {
            var arr = groups[h] ?? []
            // fetch positions if missing (throttled + backoff)
            let missing = arr.filter { posCache[keyForPos(h, $0)] == nil }
            let posChunks = stride(from: 0, to: missing.count, by: maxConcurrentPos).map { Array(missing[$0..<min(missing.count, $0+maxConcurrentPos)]) }
            for chunk in posChunks {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    for txid in chunk {
                        group.addTask {
                            let key = self.keyForPos(h, txid)
                            if self.posCache[key] != nil { return }
                            if let pos = try? await self.retrying(operation: { try await self.getPosition(txid: txid, height: h) }) {
                                self.mapLock.lock(); self.posCache[key] = pos; self.mapLock.unlock()
                            }
                        }
                    }
                    for try await _ in group { }
                }
            }
            arr.sort { (a, b) in
                mapLock.lock(); let pa = posCache[keyForPos(h, a)] ?? Int.max; let pb = posCache[keyForPos(h, b)] ?? Int.max; mapLock.unlock()
                if pa != pb { return pa < pb }
                return a < b
            }
            result.append(contentsOf: arr)
        }
        // Append any remaining (should be none)
        let remaining = ids.filter { !result.contains($0) }
        if !remaining.isEmpty { result += remaining }
        persistCaches()
        return result
    }

    private func getPosition(txid: String, height: Int) async throws -> Int {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Int, Error>) in
            electrum.getTransactionPosition(txid: txid, height: height) { cont.resume(with: $0) }
        }
    }

    private func keyForPos(_ h: Int, _ txid: String) -> String { "\(h)|\(txid)" }
}

#if DEBUG
extension ElectrumTransactionsAdapter {
    func debugSetHeightMap(_ map: [String: Int?]) {
        mapLock.lock()
        heightMap = map
        mapLock.unlock()
    }

    func debugSetPosCache(_ cache: [String: Int]) {
        mapLock.lock()
        posCache = cache
        mapLock.unlock()
    }

    func debugRefineOrder(ids: [String]) async throws -> [String] {
        try await refineOrderWithPositions(ids: ids)
    }
}
#endif

// MARK: - Cursor & Ordering & Persistence
private extension ElectrumTransactionsAdapter {
    struct Cursor { let height: Int?; let txid: String }

    func makeCursor(height: Int?, txid: String) -> String {
        let h = height ?? 0
        return "\(h)|\(txid)"
    }

    func parseCursor(_ s: String) -> Cursor? {
        let parts = s.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2, let h = Int(parts[0]) else { return nil }
        let height: Int? = h == 0 ? nil : h
        return Cursor(height: height, txid: parts[1])
    }

    func order(_ a: String, _ b: String) -> Bool {
        let ha = heightMap[a] ?? nil
        let hb = heightMap[b] ?? nil
        switch (ha, hb) {
        case let (.some(x), .some(y)):
            if x != y { return x > y }
            return a < b
        case (.some, .none): return true
        case (.none, .some): return false
        case (.none, .none): return a < b
        }
    }

    // Return true if id comes before cursor (desc order)
    func compare(txid id: String, against cursor: Cursor) -> Bool {
        let h = heightMap[id] ?? nil
        switch (h, cursor.height) {
        case let (.some(x), .some(y)):
            if x != y { return x > y }
            return id < cursor.txid
        case (.some, .none): return true
        case (.none, .some): return false
        case (.none, .none): return id < cursor.txid
        }
    }

    struct PersistedIndex: Codable { let network: String; let items: [Item]
        struct Item: Codable { let txid: String; let height: Int? }
    }

    func indexURL() -> URL? {
        let fm = FileManager.default
        guard let dir = fm.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let net = electrum.currentNetwork == .mainnet ? "mainnet" : "testnet"
        return dir.appendingPathComponent("tx_index_\(net).json")
    }

    func saveIndexToDisk() {
        guard let url = indexURL() else { return }
        let net = electrum.currentNetwork == .mainnet ? "mainnet" : "testnet"
        let items = heightMap.map { PersistedIndex.Item(txid: $0.key, height: $0.value ?? nil) }
        let payload = PersistedIndex(network: net, items: items)
        do {
            let data = try JSONEncoder().encode(payload)
            try data.write(to: url, options: .atomic)
        } catch {
            print("[Adapter] failed to persist index: \(error)")
        }
    }

    func loadIndexFromDisk() {
        guard let url = indexURL(), let data = try? Data(contentsOf: url) else { return }
        do {
            let decoded = try JSONDecoder().decode(PersistedIndex.self, from: data)
            var map: [String: Int?] = [:]
            for i in decoded.items { map[i.txid] = i.height }
            heightMap = map
            sortedTxids = heightMap.keys.sorted(by: order)
            indexInvalidated = false
        } catch { /* ignore */ }
    }

    func cachesURL() -> URL? {
        let fm = FileManager.default
        guard let dir = fm.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let net = electrum.currentNetwork == .mainnet ? "mainnet" : "testnet"
        return dir.appendingPathComponent("tx_caches_\(net).json")
    }

    struct PersistedCaches: Codable { let positions: [String: Int]; let headers: [Int: Int] }

    func persistCaches() {
        guard let url = cachesURL() else { return }
        // Snapshot under lock to avoid races
        mapLock.lock(); let positions = posCache; let headers = headerTsCache; mapLock.unlock()
        let payload = PersistedCaches(positions: positions, headers: headers)
        if let data = try? JSONEncoder().encode(payload) { try? data.write(to: url, options: Data.WritingOptions.atomic) }
    }

    func loadCachesFromDisk() {
        guard let url = cachesURL(), let data = try? Data(contentsOf: url) else { return }
        if let decoded = try? JSONDecoder().decode(PersistedCaches.self, from: data) {
            posCache = decoded.positions
            headerTsCache = decoded.headers
        }

    }

    func fetchOwnedAddresses() async -> [String] {
        await MainActor.run {
            let repo = DefaultWalletRepository(keychainService: KeychainService())
            return repo.listAllAddresses()
        }
    }

    // Exponential backoff retry helper
    func retrying<T>(attempts: Int = 3, initialDelayMs: UInt64 = 200, factor: Double = 2.0, operation: @escaping () async throws -> T) async throws -> T {
        var delay = initialDelayMs
        var lastError: Error?
        for i in 0..<attempts {
            do { return try await operation() } catch {
                lastError = error
                if i == attempts - 1 { break }
                try? await Task.sleep(nanoseconds: delay * 1_000_000)
                delay = UInt64(Double(delay) * factor)
            }
        }
        throw lastError ?? ElectrumError.invalidResponse
    }
}
