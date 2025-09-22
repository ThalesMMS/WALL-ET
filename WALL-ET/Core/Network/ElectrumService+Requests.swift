import Foundation

extension ElectrumService {
    private final class RequestHandler {
        let method: String
        let completion: (Result<Any, Error>) -> Void
        var timeoutWorkItem: DispatchWorkItem?

        init(method: String, completion: @escaping (Result<Any, Error>) -> Void) {
            self.method = method
            self.completion = completion
        }
    }

    func getServerFeatures(completion: @escaping (Result<[String: Any], Error>) -> Void) {
        let id = nextRequestId()
        let request: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": "server.features",
            "params": []
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: request),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            completion(.failure(ElectrumError.invalidRequest))
            return
        }

        let message = jsonString + "\n"
        let data = message.data(using: .utf8)!

        requestsLock.lock()
        pendingRequests[id] = RequestHandler(method: "server.features") { result in
            switch result {
            case .success(let value):
                if let dict = value as? [String: Any] {
                    self.deliverOnMain(.success(dict), to: completion)
                } else {
                    self.deliverOnMain(.failure(ElectrumError.invalidResponse), to: completion)
                }
            case .failure(let error):
                self.deliverOnMain(.failure(error), to: completion)
            }
        }
        requestsLock.unlock()

        connection?.send(content: data, completion: .contentProcessed { error in
            if let error {
                self.requestsLock.lock()
                let handler = self.pendingRequests.removeValue(forKey: id)
                self.requestsLock.unlock()
                handler?.completion(.failure(error))
            }
        })
    }

    func getBalance(for address: String, completion: @escaping (Result<AddressBalance, Error>) -> Void) {
        let scripthash = scripthash(for: address)
        let id = nextRequestId()

        let request: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": "blockchain.scripthash.get_balance",
            "params": [scripthash]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: request),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            completion(.failure(ElectrumError.invalidRequest))
            return
        }

        let message = jsonString + "\n"
        let data = message.data(using: .utf8)!

        requestsLock.lock()
        pendingRequests[id] = RequestHandler(method: "blockchain.scripthash.get_balance") { result in
            switch result {
            case .success(let value):
                if let balance = value as? [String: Any] {
                    let cAny = balance["confirmed"]
                    let uAny = balance["unconfirmed"]
                    let confirmed: Int64 = (cAny as? Int64)
                        ?? (cAny as? Int).map(Int64.init)
                        ?? (cAny as? NSNumber)?.int64Value
                        ?? 0
                    let unconfirmed: Int64 = (uAny as? Int64)
                        ?? (uAny as? Int).map(Int64.init)
                        ?? (uAny as? NSNumber)?.int64Value
                        ?? 0

                    let addressBalance = AddressBalance(
                        address: address,
                        confirmed: confirmed,
                        unconfirmed: unconfirmed
                    )
                    self.deliverOnMain(.success(addressBalance), to: completion)
                } else {
                    self.deliverOnMain(.failure(ElectrumError.invalidResponse), to: completion)
                }
            case .failure(let error):
                self.deliverOnMain(.failure(error), to: completion)
            }
        }
        requestsLock.unlock()

        connection?.send(content: data, completion: .contentProcessed { error in
            if let error {
                self.requestsLock.lock()
                let handler = self.pendingRequests.removeValue(forKey: id)
                self.requestsLock.unlock()
                handler?.completion(.failure(error))
            }
        })
    }

    func getAddressHistory(for address: String, completion: @escaping (Result<[[String: Any]], Error>) -> Void) {
        ensureConnected()
        let scripthash = scripthash(for: address)
        print("[Electrum] get_history address=\(address) scripthash=\(scripthash)")
        let id = nextRequestId()

        let request: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": "blockchain.scripthash.get_history",
            "params": [scripthash]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: request),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            completion(.failure(ElectrumError.invalidRequest))
            return
        }

        let message = jsonString + "\n"
        let data = message.data(using: .utf8)!

        requestsLock.lock()
        pendingRequests[id] = RequestHandler(method: "blockchain.scripthash.get_history") { result in
            switch result {
            case .success(let value):
                if let array = value as? [[String: Any]] {
                    self.deliverOnMain(.success(array), to: completion)
                } else if let arr = value as? [Any] {
                    let casted = arr.compactMap { $0 as? [String: Any] }
                    if casted.count == arr.count {
                        self.deliverOnMain(.success(casted), to: completion)
                    } else {
                        self.deliverOnMain(.failure(ElectrumError.invalidResponse), to: completion)
                    }
                } else {
                    self.deliverOnMain(.failure(ElectrumError.invalidResponse), to: completion)
                }
            case .failure(let error):
                self.deliverOnMain(.failure(error), to: completion)
            }
        }
        requestsLock.unlock()

        connection?.send(content: data, completion: .contentProcessed { error in
            if let error {
                self.requestsLock.lock()
                let handler = self.pendingRequests.removeValue(forKey: id)
                self.requestsLock.unlock()
                handler?.completion(.failure(error))
            }
        })
    }

    func getUTXOs(for address: String, completion: @escaping (Result<[ElectrumUTXO], Error>) -> Void) {
        ensureConnected()
        let scripthash = scripthash(for: address)
        let id = nextRequestId()
        let request: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": "blockchain.scripthash.listunspent",
            "params": [scripthash]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: request),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            completion(.failure(ElectrumError.invalidRequest))
            return
        }

        let message = jsonString + "\n"
        let data = message.data(using: .utf8)!

        requestsLock.lock()
        pendingRequests[id] = RequestHandler(method: "blockchain.scripthash.listunspent") { result in
            switch result {
            case .success(let value):
                if let utxos = value as? [[String: Any]] {
                    let parsed = utxos.compactMap { dict -> ElectrumUTXO? in
                        guard let txHash = dict["tx_hash"] as? String,
                              let txPos = dict["tx_pos"] as? Int,
                              let value = dict["value"] as? Int64 ?? (dict["value"] as? Int).map(Int64.init),
                              let height = dict["height"] as? Int else {
                            return nil
                        }
                        return ElectrumUTXO(
                            txHash: txHash,
                            txPos: txPos,
                            value: value,
                            height: height,
                            ownerAddress: address
                        )
                    }
                    self.deliverOnMain(.success(parsed), to: completion)
                } else {
                    self.deliverOnMain(.failure(ElectrumError.invalidResponse), to: completion)
                }
            case .failure(let error):
                self.deliverOnMain(.failure(error), to: completion)
            }
        }
        requestsLock.unlock()

        connection?.send(content: data, completion: .contentProcessed { error in
            if let error {
                self.requestsLock.lock()
                let handler = self.pendingRequests.removeValue(forKey: id)
                self.requestsLock.unlock()
                handler?.completion(.failure(error))
            }
        })
    }

    func getTransaction(_ txid: String, completion: @escaping (Result<String, Error>) -> Void) {
        sendRequest(method: "blockchain.transaction.get", params: [txid, true], completion: completion)
    }

    func getTransactionVerbose(_ txid: String, completion: @escaping (Result<[String: Any], Error>) -> Void) {
        ensureConnected()
        let id = nextRequestId()

        let request: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": "blockchain.transaction.get",
            "params": [txid, true]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: request),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            completion(.failure(ElectrumError.invalidRequest))
            return
        }

        let message = jsonString + "\n"
        let data = message.data(using: .utf8)!
        requestsLock.lock()
        let handler = RequestHandler(method: "blockchain.transaction.get") { result in
            switch result {
            case .success(let value):
                if let dict = value as? [String: Any] {
                    let vinC = (dict["vin"] as? [Any])?.count ?? 0
                    let voutC = (dict["vout"] as? [Any])?.count ?? 0
                    let bh = (dict["blockheight"] as? Int) ?? (dict["height"] as? Int) ?? -1
                    print("[Electrum] tx verbose: txid=\(txid) vin=\(vinC) vout=\(voutC) blockheight=\(bh)")
                    self.deliverOnMain(.success(dict), to: completion)
                } else if let str = value as? String, let d = str.data(using: .utf8),
                          let dict = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                    let vinC = (dict["vin"] as? [Any])?.count ?? 0
                    let voutC = (dict["vout"] as? [Any])?.count ?? 0
                    let bh = (dict["blockheight"] as? Int) ?? (dict["height"] as? Int) ?? -1
                    print("[Electrum] tx verbose(hex->json): txid=\(txid) vin=\(vinC) vout=\(voutC) blockheight=\(bh)")
                    self.deliverOnMain(.success(dict), to: completion)
                } else {
                    print("[Electrum] invalid tx verbose for txid=\(txid): \(value)")
                    self.deliverOnMain(.failure(ElectrumError.invalidResponse), to: completion)
                }
            case .failure(let error):
                print("[Electrum] tx verbose error for txid=\(txid): \(error)")
                self.deliverOnMain(.failure(error), to: completion)
            }
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.requestsLock.lock()
            let timedOut = self.pendingRequests.removeValue(forKey: id)
            self.requestsLock.unlock()
            timedOut?.completion(.failure(ElectrumError.timeout))
        }
        handler.timeoutWorkItem = work
        pendingRequests[id] = handler
        requestsLock.unlock()
        DispatchQueue.global().asyncAfter(deadline: .now() + 12, execute: work)
        connection?.send(content: data, completion: .contentProcessed { error in
            if let error {
                self.requestsLock.lock()
                let handler = self.pendingRequests.removeValue(forKey: id)
                self.requestsLock.unlock()
                handler?.timeoutWorkItem?.cancel()
                handler?.completion(.failure(error))
            }
        })
    }

    func broadcastTransaction(_ rawTx: String, completion: @escaping (Result<String, Error>) -> Void) {
        sendRequest(method: "blockchain.transaction.broadcast", params: [rawTx], completion: completion)
    }

    func getTransactionStatus(_ txid: String, completion: @escaping (Result<TransactionStatus, Error>) -> Void) {
        let id = nextRequestId()

        let request: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": "blockchain.transaction.get_merkle",
            "params": [txid]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: request),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            completion(.failure(ElectrumError.invalidRequest))
            return
        }

        let message = jsonString + "\n"
        let data = message.data(using: .utf8)!

        requestsLock.lock()
        pendingRequests[id] = RequestHandler(method: "blockchain.transaction.get_merkle") { result in
            switch result {
            case .success(let value):
                if let merkle = value as? [String: Any] {
                    let blockHeight = merkle["block_height"] as? Int

                    self.getCurrentBlockHeight { heightResult in
                        switch heightResult {
                        case .success(let currentHeight):
                            let confirmations = blockHeight != nil ? currentHeight - blockHeight! + 1 : 0

                            let status: TransactionStatus
                            if blockHeight != nil && confirmations >= 6 {
                                status = .confirmed
                            } else if blockHeight != nil {
                                status = .pending
                            } else {
                                status = .pending
                            }
                            self.deliverOnMain(.success(status), to: completion)

                        case .failure(let error):
                            self.deliverOnMain(.failure(error), to: completion)
                        }
                    }
                } else {
                    self.deliverOnMain(.failure(ElectrumError.invalidResponse), to: completion)
                }
            case .failure(let error):
                self.deliverOnMain(.failure(error), to: completion)
            }
        }
        requestsLock.unlock()
        connection?.send(content: data, completion: .contentProcessed { error in
            if let error {
                self.requestsLock.lock()
                let handler = self.pendingRequests.removeValue(forKey: id)
                self.requestsLock.unlock()
                handler?.completion(.failure(error))
            }
        })
    }

    func getTransactionPosition(txid: String, height: Int, completion: @escaping (Result<Int, Error>) -> Void) {
        let id = nextRequestId()
        let request: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": "blockchain.transaction.get_merkle",
            "params": [txid, height]
        ]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: request),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            completion(.failure(ElectrumError.invalidRequest))
            return
        }
        let data = (jsonString + "\n").data(using: .utf8)!
        requestsLock.lock()
        let handler = RequestHandler(method: "blockchain.transaction.get_merkle") { result in
            switch result {
            case .success(let value):
                if let dict = value as? [String: Any], let pos = (dict["pos"] as? Int) ?? (dict["position"] as? Int) {
                    self.deliverOnMain(.success(pos), to: completion)
                } else {
                    self.deliverOnMain(.failure(ElectrumError.invalidResponse), to: completion)
                }
            case .failure(let e):
                self.deliverOnMain(.failure(e), to: completion)
            }
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.requestsLock.lock()
            let timedOut = self.pendingRequests.removeValue(forKey: id)
            self.requestsLock.unlock()
            timedOut?.completion(.failure(ElectrumError.timeout))
        }
        handler.timeoutWorkItem = work
        pendingRequests[id] = handler
        requestsLock.unlock()
        DispatchQueue.global().asyncAfter(deadline: .now() + 12, execute: work)
        connection?.send(content: data, completion: .contentProcessed { error in
            if let error {
                self.requestsLock.lock()
                let handler = self.pendingRequests.removeValue(forKey: id)
                self.requestsLock.unlock()
                handler?.timeoutWorkItem?.cancel()
                handler?.completion(.failure(error))
            }
        })
    }

    func getFeeEstimate(blocks: Int, completion: @escaping (Result<Double, Error>) -> Void) {
        sendRequest(method: "blockchain.estimatefee", params: [blocks], completion: completion)
    }

    func getCurrentBlockHeight(completion: @escaping (Result<Int, Error>) -> Void) {
        let id = nextRequestId()

        let request: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": "blockchain.headers.subscribe",
            "params": []
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: request),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            completion(.failure(ElectrumError.invalidRequest))
            return
        }

        let message = jsonString + "\n"
        let data = message.data(using: .utf8)!

        requestsLock.lock()
        pendingRequests[id] = RequestHandler(method: "blockchain.headers.subscribe") { result in
            switch result {
            case .success(let value):
                if let header = value as? [String: Any],
                   let height = header["height"] as? Int {
                    self.deliverOnMain(.success(height), to: completion)
                } else {
                    self.deliverOnMain(.failure(ElectrumError.invalidResponse), to: completion)
                }
            case .failure(let error):
                self.deliverOnMain(.failure(error), to: completion)
            }
        }
        requestsLock.unlock()
        connection?.send(content: data, completion: .contentProcessed { error in
            if let error {
                self.requestsLock.lock()
                let handler = self.pendingRequests.removeValue(forKey: id)
                self.requestsLock.unlock()
                handler?.completion(.failure(error))
            }
        })
    }

    func getBlockHeader(height: Int, completion: @escaping (Result<Data, Error>) -> Void) {
        ensureConnected()
        let id = nextRequestId()
        let request: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": "blockchain.block.header",
            "params": [height]
        ]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: request),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            completion(.failure(ElectrumError.invalidRequest))
            return
        }
        let data = (jsonString + "\n").data(using: .utf8)!
        requestsLock.lock()
        let handler = RequestHandler(method: "blockchain.block.header") { result in
            switch result {
            case .success(let value):
                if let hex = value as? String {
                    let d = hex.hexStringToData()
                    self.deliverOnMain(.success(d), to: completion)
                } else if let dict = value as? [String: Any], let hex = dict["hex"] as? String {
                    let d = hex.hexStringToData()
                    self.deliverOnMain(.success(d), to: completion)
                } else {
                    self.deliverOnMain(.failure(ElectrumError.invalidResponse), to: completion)
                }
            case .failure(let e):
                self.deliverOnMain(.failure(e), to: completion)
            }
        }
        pendingRequests[id] = handler
        requestsLock.unlock()
        connection?.send(content: data, completion: .contentProcessed { error in
            if let error {
                self.requestsLock.lock()
                let handler = self.pendingRequests.removeValue(forKey: id)
                self.requestsLock.unlock()
                handler?.completion(.failure(error))
            }
        })
    }

    func getBlockTimestamp(height: Int, completion: @escaping (Result<Int, Error>) -> Void) {
        getBlockHeader(height: height) { result in
            switch result {
            case .success(let data):
                guard data.count >= 80 else {
                    completion(.failure(ElectrumError.invalidResponse))
                    return
                }
                let timestampData = data.subdata(in: 68..<72)
                let timestamp = timestampData.withUnsafeBytes { ptr -> UInt32 in
                    ptr.load(as: UInt32.self).littleEndian
                }
                completion(.success(Int(timestamp)))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func batchGetBalances(for addresses: [String], completion: @escaping (Result<[AddressBalance], Error>) -> Void) {
        let group = DispatchGroup()
        var balances: [AddressBalance] = []
        var errors: [Error] = []

        for address in addresses {
            group.enter()
            getBalance(for: address) { result in
                switch result {
                case .success(let balance):
                    balances.append(balance)
                case .failure(let error):
                    errors.append(error)
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            if !errors.isEmpty {
                completion(.failure(errors.first!))
            } else {
                completion(.success(balances))
            }
        }
    }

    func sendRequest<T: Decodable>(
        method: String,
        params: [Any] = [],
        completion: @escaping (Result<T, Error>) -> Void
    ) {
        ensureConnected()
        let id = nextRequestId()

        let request: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: request),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            completion(.failure(ElectrumError.invalidRequest))
            return
        }

        let message = jsonString + "\n"
        let data = message.data(using: .utf8)!

        requestsLock.lock()
        let handler = RequestHandler(method: method) { result in
            switch result {
            case .success(let value):
                if let typedValue = value as? T {
                    self.deliverOnMain(.success(typedValue), to: completion)
                } else if let dict = value as? [String: Any] {
                    if let data = try? JSONSerialization.data(withJSONObject: dict),
                       let decoded = try? JSONDecoder().decode(T.self, from: data) {
                        self.deliverOnMain(.success(decoded), to: completion)
                    } else {
                        self.deliverOnMain(.failure(ElectrumError.invalidResponse), to: completion)
                    }
                } else if let arr = value as? [Any] {
                    if let data = try? JSONSerialization.data(withJSONObject: arr),
                       let decoded = try? JSONDecoder().decode(T.self, from: data) {
                        self.deliverOnMain(.success(decoded), to: completion)
                    } else {
                        self.deliverOnMain(.failure(ElectrumError.invalidResponse), to: completion)
                    }
                } else if let str = value as? String, let data = str.data(using: .utf8),
                          let decoded = try? JSONDecoder().decode(T.self, from: data) {
                    self.deliverOnMain(.success(decoded), to: completion)
                } else {
                    self.deliverOnMain(.failure(ElectrumError.invalidResponse), to: completion)
                }
            case .failure(let error):
                self.deliverOnMain(.failure(error), to: completion)
            }
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.requestsLock.lock()
            let timedOut = self.pendingRequests.removeValue(forKey: id)
            self.requestsLock.unlock()
            timedOut?.completion(.failure(ElectrumError.timeout))
        }
        handler.timeoutWorkItem = work
        DispatchQueue.global().asyncAfter(deadline: .now() + 12, execute: work)
        pendingRequests[id] = handler
        requestsLock.unlock()

        connection?.send(content: data, completion: .contentProcessed { error in
            if let error {
                self.requestsLock.lock()
                let handler = self.pendingRequests.removeValue(forKey: id)
                self.requestsLock.unlock()
                handler?.timeoutWorkItem?.cancel()
                handler?.completion(.failure(error))
            }
        })
    }

    func handleResponse(_ json: [String: Any]) {
        if let method = json["method"] as? String {
            handleNotification(method: method, params: json["params"])
            return
        }

        guard let id = json["id"] as? Int else { return }
        requestsLock.lock()
        let handler = pendingRequests.removeValue(forKey: id)
        requestsLock.unlock()
        guard let handler else { return }

        if let error = json["error"] {
            handler.timeoutWorkItem?.cancel()
            handler.completion(.failure(ElectrumError.serverError(error)))
        } else if let result = json["result"] {
            handler.timeoutWorkItem?.cancel()
            handler.completion(.success(result))
        } else {
            handler.timeoutWorkItem?.cancel()
            handler.completion(.failure(ElectrumError.invalidResponse))
        }
    }

    func nextRequestId() -> Int {
        requestsLock.lock()
        requestId += 1
        let id = requestId
        requestsLock.unlock()
        return id
    }

    private func deliverOnMain<T>(_ result: Result<T, Error>, to completion: @escaping (Result<T, Error>) -> Void) {
        if Thread.isMainThread {
            completion(result)
        } else {
            DispatchQueue.main.async { completion(result) }
        }
    }
}

// MARK: - ElectrumClientProtocol
extension ElectrumService: ElectrumClientProtocol {
    func getUTXOs(for address: String) async throws -> [ElectrumUTXO] {
        try await withCheckedThrowingContinuation { continuation in
            getUTXOs(for: address) { continuation.resume(with: $0) }
        }
    }

    func getTransaction(_ txid: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            getTransaction(txid) { continuation.resume(with: $0) }
        }
    }

    func broadcastTransaction(_ rawTx: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            broadcastTransaction(rawTx) { continuation.resume(with: $0) }
        }
    }

    func getCurrentBlockHeight() async throws -> Int {
        try await withCheckedThrowingContinuation { continuation in
            getCurrentBlockHeight { continuation.resume(with: $0) }
        }
    }

    func getAddressHistory(for address: String) async throws -> [[String: Any]] {
        try await withCheckedThrowingContinuation { continuation in
            getAddressHistory(for: address) { continuation.resume(with: $0) }
        }
    }

    func getBlockTimestamp(height: Int) async throws -> Int {
        try await withCheckedThrowingContinuation { continuation in
            getBlockTimestamp(height: height) { continuation.resume(with: $0) }
        }
    }
}
