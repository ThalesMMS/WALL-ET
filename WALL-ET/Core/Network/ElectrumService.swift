import Foundation
import Network
import Combine
import CryptoKit

// MARK: - Electrum Service
class ElectrumService: NSObject {
    
    // MARK: - Properties
    static let shared = ElectrumService()
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.wallet.electrum", qos: .userInitiated)
    private var cancellables = Set<AnyCancellable>()
    
    // Request tracking
    private var pendingRequests: [Int: RequestHandler] = [:]
    private var requestId = 0
    private let requestsLock = NSLock()
    
    // Mapping between addresses and scripthashes for notifications
    private var addressToScripthash: [String: String] = [:]
    private var scripthashToAddress: [String: String] = [:]
    private let mapLock = NSLock()

    // Transaction tracking
    private var knownTxidsByAddress: [String: Set<String>] = [:]
    private var trackedTxHeights: [String: Int?] = [:] // txid -> blockHeight (nil if unconfirmed)
    private let txLock = NSLock()
    private var lastBlockHeight: Int = 0
    
    // Publishers
    let connectionStatePublisher = PassthroughSubject<ConnectionState, Never>()
    let balanceUpdatePublisher = PassthroughSubject<AddressBalance, Never>()
    let transactionUpdatePublisher = PassthroughSubject<TransactionUpdate, Never>()
    let blockHeightPublisher = PassthroughSubject<Int, Never>()
    let addressStatusPublisher = PassthroughSubject<AddressStatusUpdate, Never>()
    // Debug: log raw JSON for only one transaction to avoid huge logs
    private var didLogOneRawTx = false
    
    // Configuration
    private var currentServer: ElectrumServer
    private var network: BitcoinService.Network
    
    // MARK: - Types
    struct ElectrumServer {
        let host: String
        let port: Int
        let useSSL: Bool
        
        static let mainnetServers = [
            ElectrumServer(host: "electrum.blockstream.info", port: 50002, useSSL: true),
            ElectrumServer(host: "electrum.bitaroo.net", port: 50002, useSSL: true),
            ElectrumServer(host: "bitcoin.lukechilds.co", port: 50002, useSSL: true),
            ElectrumServer(host: "electrum.coinucopia.io", port: 50002, useSSL: true)
        ]
        
        static let testnetServers = [
            ElectrumServer(host: "electrum.blockstream.info", port: 60002, useSSL: true),
            ElectrumServer(host: "testnet.qtornado.com", port: 51002, useSSL: true)
        ]
    }
    
    enum ConnectionState {
        case disconnected
        case connecting
        case connected
        case failed(Error)
    }
    
    struct AddressBalance {
        let address: String
        let confirmed: Int64
        let unconfirmed: Int64
    }
    
    struct TransactionUpdate {
        let txid: String
        let confirmations: Int
        let blockHeight: Int?
    }
    
    struct AddressStatusUpdate {
        let address: String
        let hasHistory: Bool
    }
    
    private class RequestHandler {
        let method: String
        let completion: (Result<Any, Error>) -> Void
        var timeoutWorkItem: DispatchWorkItem?
        init(method: String, completion: @escaping (Result<Any, Error>) -> Void) {
            self.method = method
            self.completion = completion
        }
    }
    
    // MARK: - Initialization
    override init() {
        self.network = .mainnet
        self.currentServer = ElectrumServer.mainnetServers.first!
        super.init()
    }
    
    init(network: BitcoinService.Network) {
        self.network = network
        self.currentServer = network == .mainnet ? 
            ElectrumServer.mainnetServers.first! : 
            ElectrumServer.testnetServers.first!
        super.init()
    }
    
    // Update server and network at runtime
    func updateServer(host: String, port: Int, useSSL: Bool, network: BitcoinService.Network) {
        self.currentServer = ElectrumServer(host: host, port: port, useSSL: useSSL)
        self.network = network
    }

    var currentNetwork: BitcoinService.Network { network }
    
    // MARK: - Connection Management
    func applySavedSettingsAndReconnect() {
        let defaults = UserDefaults.standard
        let host = defaults.string(forKey: "electrum_host") ?? "electrum.blockstream.info"
        var port = defaults.object(forKey: "electrum_port") as? Int ?? 50001
        // Default SSL OFF for initial configuration
        let useSSL = defaults.object(forKey: "electrum_ssl") as? Bool ?? false
        let netStr = defaults.string(forKey: "network_type") ?? "mainnet"
        let net: BitcoinService.Network = (netStr == "testnet") ? .testnet : .mainnet
        if host == "electrum.blockstream.info" && !useSSL {
            port = (net == .mainnet) ? 50001 : 60001
        }
        updateServer(host: host, port: port, useSSL: useSSL, network: net)
        disconnect()
        connect()
    }
    func connect() {
        connectionStatePublisher.send(.connecting)
        
        let host = NWEndpoint.Host(currentServer.host)
        let port = NWEndpoint.Port(rawValue: UInt16(currentServer.port))!
        
        let parameters: NWParameters
        if currentServer.useSSL {
            parameters = NWParameters.tls
            let options = NWProtocolTLS.Options()
            parameters.defaultProtocolStack.applicationProtocols.insert(options, at: 0)
        } else {
            parameters = .tcp
        }
        
        connection = NWConnection(host: host, port: port, using: parameters)
        
        connection?.stateUpdateHandler = { [weak self] state in
            self?.handleConnectionStateChange(state)
        }
        
        connection?.start(queue: queue)
        startReceiving()
    }
    
    func disconnect() {
        connection?.cancel()
        connection = nil
        requestsLock.lock(); pendingRequests.removeAll(); requestsLock.unlock()
        connectionStatePublisher.send(.disconnected)
    }
    
    private func handleConnectionStateChange(_ state: NWConnection.State) {
        switch state {
        case .ready:
            connectionStatePublisher.send(.connected)
            performHandshake()
        case .failed(let error):
            connectionStatePublisher.send(.failed(error))
            reconnect()
        case .cancelled:
            connectionStatePublisher.send(.disconnected)
        default:
            break
        }
    }
    
    private func reconnect() {
        queue.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.connect()
        }
    }
    
    // MARK: - Communication
    private func sendRequest<T: Decodable>(
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
                } else if let data = try? JSONSerialization.data(withJSONObject: value),
                          let decoded = try? JSONDecoder().decode(T.self, from: data) {
                    self.deliverOnMain(.success(decoded), to: completion)
                } else {
                    self.deliverOnMain(.failure(ElectrumError.invalidResponse), to: completion)
                }
            case .failure(let error):
                self.deliverOnMain(.failure(error), to: completion)
            }
        }
        // Timeout safeguard
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
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
            if let error = error {
                self.requestsLock.lock()
                let handler = self.pendingRequests.removeValue(forKey: id)
                self.requestsLock.unlock()
                handler?.timeoutWorkItem?.cancel()
                handler?.completion(.failure(error))
            }
        })
    }
    
    private func startReceiving() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            if let data = data, !data.isEmpty {
                self?.handleReceivedData(data)
            }
            
            if let error = error {
                print("Receive error: \(error)")
            }
            
            if !isComplete {
                self?.startReceiving()
            }
        }
    }
    
    private func handleReceivedData(_ data: Data) {
        guard let string = String(data: data, encoding: .utf8) else { return }
        
        // Handle multiple responses separated by newlines
        let responses = string.split(separator: "\n")
        
        for response in responses {
            if let responseData = response.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] {
                handleResponse(json)
            }
        }
    }
    
    private func handleResponse(_ json: [String: Any]) {
        // Check if it's a notification
        if let method = json["method"] as? String {
            handleNotification(method: method, params: json["params"])
            return
        }
        
        // Handle request response
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
    
    private func handleNotification(method: String, params: Any?) {
        switch method {
        case "blockchain.headers.subscribe":
            if let params = params as? [[String: Any]],
               let height = params.first?["height"] as? Int {
                lastBlockHeight = height
                blockHeightPublisher.send(height)
                // Recompute confirmations for tracked transactions
                recomputeConfirmations()
            }
            
        case "blockchain.scripthash.subscribe":
            // params: [scripthash, status]
            if let arr = params as? [Any], let scripthash = arr.first as? String {
                // Publish balance for this scripthash
                fetchBalanceForScripthash(scripthash)
                // Also check history and publish address used status
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
    
    // MARK: - Electrum Protocol Methods
    private func performHandshake() {
        // Subscribe to headers
        subscribeToHeaders()
        
        // Get server features
        getServerFeatures { result in
            switch result {
            case .success(let features):
                print("Connected to Electrum server: \(features)")
            case .failure(let error):
                print("Handshake failed: \(error)")
            }
        }
    }
    
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
            if let error = error {
                self.requestsLock.lock()
                let handler = self.pendingRequests.removeValue(forKey: id)
                self.requestsLock.unlock()
                handler?.completion(.failure(error))
            }
        })
    }
    
    // MARK: - Address Operations
    func getBalance(for address: String, completion: @escaping (Result<AddressBalance, Error>) -> Void) {
        let scripthash = addressToScripthash(address)
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
            if let error = error {
                self.requestsLock.lock()
                let handler = self.pendingRequests.removeValue(forKey: id)
                self.requestsLock.unlock()
                handler?.completion(.failure(error))
            }
        })
    }
    
    func subscribeToAddress(_ address: String) {
        let scripthash = addressToScripthash(address)
        mapLock.lock()
        addressToScripthash[address] = scripthash
        scripthashToAddress[scripthash] = address
        mapLock.unlock()
        ensureConnected()
        sendRequest(method: "blockchain.scripthash.subscribe", params: [scripthash]) { (result: Result<String?, Error>) in
            if case .success = result {
                print("Subscribed to address: \(address)")
                // Seed known txids baseline so we don't emit existing history as new
                self.getAddressHistory(for: address) { res in
                    if case .success(let hist) = res {
                        let txids: Set<String> = Set(hist.compactMap { $0["tx_hash"] as? String })
                        self.txLock.lock(); self.knownTxidsByAddress[address] = txids; self.txLock.unlock()
                    }
                }
            }
        }
    }
    
    func getAddressHistory(for address: String, completion: @escaping (Result<[[String: Any]], Error>) -> Void) {
        let scripthash = addressToScripthash(address)
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
                if let history = value as? [[String: Any]] {
                    print("[Electrum] history count for \(address): \(history.count)")
                    self.deliverOnMain(.success(history), to: completion)
                } else {
                    print("[Electrum] invalid history response for \(address): \(value)")
                    self.deliverOnMain(.failure(ElectrumError.invalidResponse), to: completion)
                }
            case .failure(let error):
                print("[Electrum] history error for \(address): \(error)")
                self.deliverOnMain(.failure(error), to: completion)
            }
        }
        requestsLock.unlock()
        
        connection?.send(content: data, completion: .contentProcessed { error in
            if let error = error {
                self.requestsLock.lock()
                let handler = self.pendingRequests.removeValue(forKey: id)
                self.requestsLock.unlock()
                handler?.completion(.failure(error))
            }
        })
    }
    
    func getUTXOs(for address: String, completion: @escaping (Result<[ElectrumUTXO], Error>) -> Void) {
        let scripthash = addressToScripthash(address)
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
                    let electrumUTXOs = utxos.compactMap { utxo -> ElectrumUTXO? in
                        guard let txHash = utxo["tx_hash"] as? String,
                              let txPos = (utxo["tx_pos"] as? Int) ?? (utxo["tx_pos"] as? NSNumber)?.intValue,
                              let value = (utxo["value"] as? Int64) ?? (utxo["value"] as? Int).map(Int64.init) ?? (utxo["value"] as? NSNumber)?.int64Value,
                              let height = (utxo["height"] as? Int) ?? (utxo["height"] as? NSNumber)?.intValue else {
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
                    self.deliverOnMain(.success(electrumUTXOs), to: completion)
                } else {
                    self.deliverOnMain(.failure(ElectrumError.invalidResponse), to: completion)
                }
            case .failure(let error):
                self.deliverOnMain(.failure(error), to: completion)
            }
        }
        requestsLock.unlock()
        
        connection?.send(content: data, completion: .contentProcessed { error in
            if let error = error {
                self.requestsLock.lock()
                let handler = self.pendingRequests.removeValue(forKey: id)
                self.requestsLock.unlock()
                handler?.completion(.failure(error))
            }
        })
    }
    
    // MARK: - Transaction Operations
    func broadcastTransaction(_ rawTx: String, completion: @escaping (Result<String, Error>) -> Void) {
        sendRequest(method: "blockchain.transaction.broadcast", params: [rawTx], completion: completion)
    }
    
    func getTransaction(_ txid: String, completion: @escaping (Result<String, Error>) -> Void) {
        sendRequest(method: "blockchain.transaction.get", params: [txid], completion: completion)
    }
    
    func getTransactionVerbose(_ txid: String, completion: @escaping (Result<[String: Any], Error>) -> Void) {
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
        pendingRequests[id] = RequestHandler(method: "blockchain.transaction.get") { result in
            switch result {
            case .success(let value):
                if let dict = value as? [String: Any] {
                    // Log a compact summary of the verbose tx JSON
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
        requestsLock.unlock()
        connection?.send(content: data, completion: .contentProcessed { error in
            if let error = error {
                self.requestsLock.lock()
                let handler = self.pendingRequests.removeValue(forKey: id)
                self.requestsLock.unlock()
                handler?.completion(.failure(error))
            }
        })
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
                    
                    // Get current block height
                    self.getCurrentBlockHeight { heightResult in
                        switch heightResult {
                        case .success(let currentHeight):
                            let confirmations = blockHeight != nil ? currentHeight - blockHeight! + 1 : 0
                            
                            // TransactionStatus is an enum, determine which case
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
            if let error = error {
                self.requestsLock.lock()
                let handler = self.pendingRequests.removeValue(forKey: id)
                self.requestsLock.unlock()
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
            if let error = error {
                self.requestsLock.lock()
                let handler = self.pendingRequests.removeValue(forKey: id)
                self.requestsLock.unlock()
                handler?.completion(.failure(error))
            }
        })
    }
    
    // MARK: - Helper Methods
    private func addressToScripthash(_ address: String) -> String {
        // Convert address to scriptPubKey depending on address type
        var script: Data? = nil
        if address.starts(with: "bc1") || address.starts(with: "tb1") {
            // Bech32 – could be P2WPKH or P2WSH or P2TR
            if let bech = Bech32.decode(address) {
                let (version, program) = bech
                if version == 0 && program.count == 20 {
                    script = BitcoinService().createP2WPKHScript(for: address)
                } else if version == 0 && program.count == 32 {
                    // P2WSH scriptPubKey
                    var s = Data(); s.append(0x00); s.append(0x20); s.append(program); script = s
                } else if version == 1 && program.count == 32 {
                    // P2TR scriptPubKey: OP_1 + 32-byte x-only key
                    var s = Data(); s.append(0x51); s.append(0x20); s.append(program); script = s
                }
            }
        } else {
            // Base58 – P2PKH/P2SH
            script = BitcoinService().createP2PKHScript(for: address)
            if script == nil, let decoded = Base58.decode(address) {
                // P2SH script (hash is last 20 bytes after version)
                let hash = decoded.dropFirst().prefix(20)
                var s = Data(); s.append(0xa9); s.append(0x14); s.append(hash); s.append(0x87); script = s
            }
        }
        
        let spk = script ?? Data()
        // SHA256 and reverse for Electrum scripthash format
        let hash = SHA256.hash(data: spk)
        return Data(hash.reversed()).hexString
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
            if let error = error {
                self.requestsLock.lock()
                self.pendingRequests.removeValue(forKey: id)
                self.requestsLock.unlock()
            }
        })
    }
    
    // MARK: - Batch Operations
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
}

// MARK: - Supporting Types
struct ElectrumUTXO {
    let txHash: String
    let txPos: Int
    let value: Int64
    let height: Int
    let ownerAddress: String?
    
    var outpoint: Outpoint {
        let txidData = Data(txHash.hexStringToData().reversed())
        return Outpoint(txid: txidData, vout: UInt32(txPos))
    }
}

struct ElectrumTransactionStatus {
    let confirmed: Bool
    let blockHeight: Int?
    let confirmations: Int
    let position: Int?
}

enum ElectrumError: LocalizedError {
    case connectionFailed
    case invalidRequest
    case invalidResponse
    case serverError(Any)
    case timeout
    
    var errorDescription: String? {
        switch self {
        case .connectionFailed:
            return "Failed to connect to Electrum server"
        case .invalidRequest:
            return "Invalid request format"
        case .invalidResponse:
            return "Invalid response from server"
        case .serverError(let error):
            return "Server error: \(error)"
        case .timeout:
            return "Request timeout"
        }
    }
}

// MARK: - Extensions
extension String {
    func hexStringToData() -> Data {
        var data = Data()
        var hex = self
        
        // Remove 0x prefix if present
        if hex.hasPrefix("0x") {
            hex = String(hex.dropFirst(2))
        }
        
        // Ensure even length
        if hex.count % 2 != 0 {
            hex = "0" + hex
        }
        
        for i in stride(from: 0, to: hex.count, by: 2) {
            let startIndex = hex.index(hex.startIndex, offsetBy: i)
            let endIndex = hex.index(startIndex, offsetBy: 2)
            let byteString = hex[startIndex..<endIndex]
            if let byte = UInt8(byteString, radix: 16) {
                data.append(byte)
            }
        }
        
        return data
    }
}

// MARK: - Thread-safety helpers
private extension ElectrumService {
    func nextRequestId() -> Int {
        requestsLock.lock()
        requestId += 1
        let id = requestId
        requestsLock.unlock()
        return id
    }

    func deliverOnMain<T>(_ result: Result<T, Error>, to completion: @escaping (Result<T, Error>) -> Void) {
        if Thread.isMainThread {
            completion(result)
        } else {
            DispatchQueue.main.async { completion(result) }
        }
    }
    
    func ensureConnected() {
        if connection == nil {
            connect()
        }
    }
    
    func addressForScripthash(_ scripthash: String) -> String? {
        mapLock.lock(); defer { mapLock.unlock() }
        return scripthashToAddress[scripthash]
    }

    func handleHistoryUpdate(address: String, entries: [[String: Any]]) {
        // Determine new txids for this address
        let newIds: [String] = {
            let latest = Set(entries.compactMap { $0["tx_hash"] as? String })
            txLock.lock(); let known = knownTxidsByAddress[address] ?? Set<String>(); txLock.unlock()
            let diff = latest.subtracting(known)
            if !diff.isEmpty {
                txLock.lock(); knownTxidsByAddress[address] = latest; txLock.unlock()
            }
            return Array(diff)
        }()
        guard !newIds.isEmpty else { return }
        // Debug: log raw JSON for only one txid across the app lifetime
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
        // For each new tx, fetch verbose to get blockheight and publish
        for txid in newIds {
            getTransactionVerbose(txid) { result in
                switch result {
                case .success(let dict):
                    let bh = (dict["blockheight"] as? Int) ?? (dict["height"] as? Int)
                    self.txLock.lock(); self.trackedTxHeights[txid] = bh; self.txLock.unlock()
                    let conf = (bh != nil && self.lastBlockHeight > 0) ? max(0, self.lastBlockHeight - bh! + 1) : 0
                    self.transactionUpdatePublisher.send(TransactionUpdate(txid: txid, confirmations: conf, blockHeight: bh))
                case .failure:
                    self.txLock.lock(); self.trackedTxHeights[txid] = nil; self.txLock.unlock()
                    self.transactionUpdatePublisher.send(TransactionUpdate(txid: txid, confirmations: 0, blockHeight: nil))
                }
            }
        }
    }

    func recomputeConfirmations() {
        txLock.lock(); let snapshot = trackedTxHeights; let height = lastBlockHeight; txLock.unlock()
        guard height > 0 else { return }
        for (txid, bhOpt) in snapshot {
            if let bh = bhOpt {
                let conf = max(0, height - bh + 1)
                transactionUpdatePublisher.send(TransactionUpdate(txid: txid, confirmations: conf, blockHeight: bh))
            }
        }
    }
}
