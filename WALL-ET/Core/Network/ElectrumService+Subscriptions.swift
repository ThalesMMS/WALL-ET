import Foundation
import CryptoKit

extension ElectrumService {
    func subscribeToHeaders() {
        let id = nextRequestId()
        let request: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": "blockchain.headers.subscribe",
            "params": []
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: request),
              let message = String(data: jsonData, encoding: .utf8) else {
            return
        }

        let data = (message + "\n").data(using: .utf8)!
        connection?.send(content: data, completion: .contentProcessed { _ in })
    }

    func subscribeToAddress(_ address: String) {
        let scripthash = scripthash(for: address)
        addressMap.map(address: address, to: scripthash)
        ensureConnected()
        sendRequest(method: "blockchain.scripthash.subscribe", params: [scripthash]) { (result: Result<String?, Error>) in
            if case .success = result {
                print("Subscribed to address: \(address)")
                self.getAddressHistory(for: address) { res in
                    if case .success(let hist) = res {
                        let txids: Set<String> = Set(hist.compactMap { $0["tx_hash"] as? String })
                        self.transactionCache.setKnownTxids(txids, for: address)
                    }
                }
            }
        }
    }

    func performHandshake() {
        subscribeToHeaders()

        getServerFeatures { result in
            switch result {
            case .success(let features):
                print("Connected to Electrum server: \(features)")
            case .failure(let error):
                print("Handshake failed: \(error)")
            }
        }
    }

    func handleNotification(method: String, params: Any?) {
        switch method {
        case "blockchain.headers.subscribe":
            if let params = params as? [[String: Any]],
               let height = params.first?["height"] as? Int {
                lastBlockHeight = height
                blockHeightPublisher.send(height)
                recomputeConfirmations()
            }

        case "blockchain.scripthash.subscribe":
            if let arr = params as? [Any], let scripthash = arr.first as? String {
                fetchBalanceForScripthash(scripthash)
                if let address = addressForScripthash(scripthash) {
                    getAddressHistory(for: address) { result in
                        if case .success(let history) = result {
                            let used = !history.isEmpty
                            self.addressStatusPublisher.send(AddressStatusUpdate(address: address, hasHistory: used))
                            self.handleHistoryUpdate(address: address, entries: history)
                        }
                    }
                }
            }

        default:
            break
        }
    }

    func handleHistoryUpdate(address: String, entries: [[String: Any]]) {
        let newIds = transactionCache.newTxids(for: address, entries: entries)
        guard !newIds.isEmpty else { return }

        if !didLogOneRawTx, let sampleTxid = newIds.first {
            getTransactionVerbose(sampleTxid) { result in
                switch result {
                case .success(let dict):
                    if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
                       let json = String(data: data, encoding: .utf8) {
                        print("[Electrum][RAW TX JSON SAMPLE] txid=\(sampleTxid) json=\(json)")
                    } else {
                        print("[Electrum][RAW TX JSON SAMPLE] txid=\(sampleTxid) (failed to serialize)")
                    }
                case .failure(let err):
                    print("[Electrum][RAW TX JSON SAMPLE] txid=\(sampleTxid) error=\(err)")
                }
            }
            didLogOneRawTx = true
        }

        for txid in newIds {
            getTransactionVerbose(txid) { result in
                switch result {
                case .success(let dict):
                    let bh = (dict["blockheight"] as? Int) ?? (dict["height"] as? Int)
                    self.transactionCache.updateHeight(bh, for: txid)
                    let conf = (bh != nil && self.lastBlockHeight > 0) ? max(0, self.lastBlockHeight - bh! + 1) : 0
                    self.transactionUpdatePublisher.send(TransactionUpdate(txid: txid, confirmations: conf, blockHeight: bh))
                case .failure:
                    self.transactionCache.markUnknownHeight(for: txid)
                    self.transactionUpdatePublisher.send(TransactionUpdate(txid: txid, confirmations: 0, blockHeight: nil))
                }
            }
        }
    }

    func recomputeConfirmations() {
        let snapshot = transactionCache.snapshotHeights()
        let height = lastBlockHeight
        guard height > 0 else { return }
        for (txid, bhOpt) in snapshot {
            if let bh = bhOpt {
                let conf = max(0, height - bh + 1)
                transactionUpdatePublisher.send(TransactionUpdate(txid: txid, confirmations: conf, blockHeight: bh))
            }
        }
    }

    func scripthash(for address: String) -> String {
        if let cached = addressMap.cachedScripthash(for: address) {
            return cached
        }

        var script: Data?
        if address.starts(with: "bc1") || address.starts(with: "tb1") {
            if let bech = Bech32.decode(address) {
                let (version, program) = bech
                if version == 0 && program.count == 20 {
                    script = BitcoinService().createP2WPKHScript(for: address)
                } else if version == 0 && program.count == 32 {
                    var s = Data(); s.append(0x00); s.append(0x20); s.append(program); script = s
                } else if version == 1 && program.count == 32 {
                    var s = Data(); s.append(0x51); s.append(0x20); s.append(program); script = s
                }
            }
        } else {
            script = BitcoinService().createP2PKHScript(for: address)
            if script == nil, let decoded = Base58.decode(address) {
                let hash = decoded.dropFirst().prefix(20)
                var s = Data(); s.append(0xa9); s.append(0x14); s.append(hash); s.append(0x87); script = s
            }
        }

        let spk = script ?? Data()
        let hash = SHA256.hash(data: spk)
        let result = Data(hash.reversed()).hexString
        addressMap.map(address: address, to: result)
        return result
    }

    private func addressForScripthash(_ scripthash: String) -> String? {
        addressMap.address(for: scripthash)
    }

    private func fetchBalanceForScripthash(_ scripthash: String) {
        let id = nextRequestId()

        let request: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": "blockchain.scripthash.get_balance",
            "params": [scripthash]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: request),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return
        }

        let message = jsonString + "\n"
        let data = message.data(using: .utf8)!

        requestsLock.lock()
        pendingRequests[id] = RequestHandler(method: "blockchain.scripthash.get_balance") { result in
            if case .success(let value) = result,
               let balance = value as? [String: Any] {
                let cAny = balance["confirmed"]
                let uAny = balance["unconfirmed"]
                let confirmed: Int64 = (cAny as? Int64) ?? (cAny as? Int).map(Int64.init) ?? (cAny as? NSNumber)?.int64Value ?? 0
                let unconfirmed: Int64 = (uAny as? Int64) ?? (uAny as? Int).map(Int64.init) ?? (uAny as? NSNumber)?.int64Value ?? 0
                if let address = self.addressForScripthash(scripthash) {
                    let ab = AddressBalance(address: address, confirmed: confirmed, unconfirmed: unconfirmed)
                    self.balanceUpdatePublisher.send(ab)
                }
            }
        }
        requestsLock.unlock()
        connection?.send(content: data, completion: .contentProcessed { error in
            if let error {
                self.requestsLock.lock()
                self.pendingRequests.removeValue(forKey: id)
                self.requestsLock.unlock()
                print("Failed to fetch balance for scripthash=\(scripthash) error=\(error)")
            }
        })
    }
}
