import Foundation
import Network
import Combine

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
    
    // Publishers
    let connectionStatePublisher = PassthroughSubject<ConnectionState, Never>()
    let balanceUpdatePublisher = PassthroughSubject<AddressBalance, Never>()
    let transactionUpdatePublisher = PassthroughSubject<TransactionUpdate, Never>()
    let blockHeightPublisher = PassthroughSubject<Int, Never>()
    
    // Configuration
    private var currentServer: ElectrumServer
    private let network: BitcoinService.Network
    
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
    
    private struct RequestHandler {
        let method: String
        let completion: (Result<Any, Error>) -> Void
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
    
    // MARK: - Connection Management
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
        pendingRequests.removeAll()
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
        requestId += 1
        let id = requestId
        
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
        
        pendingRequests[id] = RequestHandler(method: method) { result in
            switch result {
            case .success(let value):
                if let typedValue = value as? T {
                    completion(.success(typedValue))
                } else if let data = try? JSONSerialization.data(withJSONObject: value),
                          let decoded = try? JSONDecoder().decode(T.self, from: data) {
                    completion(.success(decoded))
                } else {
                    completion(.failure(ElectrumError.invalidResponse))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
        
        connection?.send(content: data, completion: .contentProcessed { error in
            if let error = error {
                self.pendingRequests[id]?.completion(.failure(error))
                self.pendingRequests.removeValue(forKey: id)
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
        guard let id = json["id"] as? Int,
              let handler = pendingRequests[id] else { return }
        
        pendingRequests.removeValue(forKey: id)
        
        if let error = json["error"] {
            handler.completion(.failure(ElectrumError.serverError(error)))
        } else if let result = json["result"] {
            handler.completion(.success(result))
        } else {
            handler.completion(.failure(ElectrumError.invalidResponse))
        }
    }
    
    private func handleNotification(method: String, params: Any?) {
        switch method {
        case "blockchain.headers.subscribe":
            if let params = params as? [[String: Any]],
               let height = params.first?["height"] as? Int {
                blockHeightPublisher.send(height)
            }
            
        case "blockchain.scripthash.subscribe":
            if let params = params as? [String],
               params.count >= 2 {
                let scripthash = params[0]
                // Fetch balance for this scripthash
                fetchBalanceForScripthash(scripthash)
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
        sendRequest(method: "blockchain.headers.subscribe", params: []) { (result: Result<[String: Any], Error>) in
            if case .success(let header) = result,
               let height = header["height"] as? Int {
                self.blockHeightPublisher.send(height)
            }
        }
    }
    
    func getServerFeatures(completion: @escaping (Result<[String: Any], Error>) -> Void) {
        sendRequest(method: "server.features", params: [], completion: completion)
    }
    
    // MARK: - Address Operations
    func getBalance(for address: String, completion: @escaping (Result<AddressBalance, Error>) -> Void) {
        let scripthash = addressToScripthash(address)
        
        sendRequest(method: "blockchain.scripthash.get_balance", params: [scripthash]) { (result: Result<[String: Any], Error>) in
            switch result {
            case .success(let balance):
                let confirmed = (balance["confirmed"] as? Int64) ?? 0
                let unconfirmed = (balance["unconfirmed"] as? Int64) ?? 0
                
                let addressBalance = AddressBalance(
                    address: address,
                    confirmed: confirmed,
                    unconfirmed: unconfirmed
                )
                completion(.success(addressBalance))
                
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    func subscribeToAddress(_ address: String) {
        let scripthash = addressToScripthash(address)
        
        sendRequest(method: "blockchain.scripthash.subscribe", params: [scripthash]) { (result: Result<String?, Error>) in
            if case .success = result {
                print("Subscribed to address: \(address)")
            }
        }
    }
    
    func getAddressHistory(for address: String, completion: @escaping (Result<[[String: Any]], Error>) -> Void) {
        let scripthash = addressToScripthash(address)
        sendRequest(method: "blockchain.scripthash.get_history", params: [scripthash], completion: completion)
    }
    
    func getUTXOs(for address: String, completion: @escaping (Result<[ElectrumUTXO], Error>) -> Void) {
        let scripthash = addressToScripthash(address)
        
        sendRequest(method: "blockchain.scripthash.listunspent", params: [scripthash]) { (result: Result<[[String: Any]], Error>) in
            switch result {
            case .success(let utxos):
                let electrumUTXOs = utxos.compactMap { utxo -> ElectrumUTXO? in
                    guard let txHash = utxo["tx_hash"] as? String,
                          let txPos = utxo["tx_pos"] as? Int,
                          let value = utxo["value"] as? Int64,
                          let height = utxo["height"] as? Int else {
                        return nil
                    }
                    
                    return ElectrumUTXO(
                        txHash: txHash,
                        txPos: txPos,
                        value: value,
                        height: height
                    )
                }
                completion(.success(electrumUTXOs))
                
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Transaction Operations
    func broadcastTransaction(_ rawTx: String, completion: @escaping (Result<String, Error>) -> Void) {
        sendRequest(method: "blockchain.transaction.broadcast", params: [rawTx], completion: completion)
    }
    
    func getTransaction(_ txid: String, completion: @escaping (Result<String, Error>) -> Void) {
        sendRequest(method: "blockchain.transaction.get", params: [txid], completion: completion)
    }
    
    func getTransactionStatus(_ txid: String, completion: @escaping (Result<TransactionStatus, Error>) -> Void) {
        sendRequest(method: "blockchain.transaction.get_merkle", params: [txid]) { (result: Result<[String: Any], Error>) in
            switch result {
            case .success(let merkle):
                let blockHeight = merkle["block_height"] as? Int
                let position = merkle["pos"] as? Int
                
                // Get current block height
                self.getCurrentBlockHeight { heightResult in
                    switch heightResult {
                    case .success(let currentHeight):
                        let confirmations = blockHeight != nil ? currentHeight - blockHeight! + 1 : 0
                        
                        let status = TransactionStatus(
                            confirmed: blockHeight != nil,
                            blockHeight: blockHeight,
                            confirmations: confirmations,
                            position: position
                        )
                        completion(.success(status))
                        
                    case .failure(let error):
                        completion(.failure(error))
                    }
                }
                
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    func getFeeEstimate(blocks: Int, completion: @escaping (Result<Double, Error>) -> Void) {
        sendRequest(method: "blockchain.estimatefee", params: [blocks], completion: completion)
    }
    
    func getCurrentBlockHeight(completion: @escaping (Result<Int, Error>) -> Void) {
        sendRequest(method: "blockchain.headers.subscribe", params: []) { (result: Result<[String: Any], Error>) in
            switch result {
            case .success(let header):
                if let height = header["height"] as? Int {
                    completion(.success(height))
                } else {
                    completion(.failure(ElectrumError.invalidResponse))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Helper Methods
    private func addressToScripthash(_ address: String) -> String {
        // Convert address to script
        let script = try? BitcoinService.shared.createP2PKHScript(for: address) ?? Data()
        
        // SHA256 and reverse for Electrum scripthash format
        let hash = SHA256.hash(data: script ?? Data())
        return Data(hash.reversed()).hexString
    }
    
    private func fetchBalanceForScripthash(_ scripthash: String) {
        sendRequest(method: "blockchain.scripthash.get_balance", params: [scripthash]) { (result: Result<[String: Any], Error>) in
            if case .success(let balance) = result {
                // Find address for this scripthash and publish update
                // This would need a scripthash->address mapping
            }
        }
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
    
    var outpoint: Outpoint {
        let txidData = Data(txHash.hexStringToData().reversed())
        return Outpoint(txid: txidData, vout: UInt32(txPos))
    }
}

struct TransactionStatus {
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