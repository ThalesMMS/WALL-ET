import Foundation
import Combine
import Network

final class ElectrumService: NSObject {
    static let shared = ElectrumService()

    private(set) var currentServer: ElectrumServer
    private(set) var network: BitcoinService.Network

    var connection: NWConnection?
    let queue: DispatchQueue
    var pendingRequests: [Int: RequestHandler] = [:]
    var requestId: Int = 0
    let requestsLock = NSLock()

    let addressMap = AddressMapping()
    let transactionCache = TransactionCache()
    var lastBlockHeight: Int = 0
    var didLogOneRawTx = false

    private let userDefaults: UserDefaults

    let connectionStatePublisher = PassthroughSubject<ConnectionState, Never>()
    let balanceUpdatePublisher = PassthroughSubject<AddressBalance, Never>()
    let transactionUpdatePublisher = PassthroughSubject<TransactionUpdate, Never>()
    let blockHeightPublisher = PassthroughSubject<Int, Never>()
    let addressStatusPublisher = PassthroughSubject<AddressStatusUpdate, Never>()

    override init() {
        self.queue = DispatchQueue(label: "com.wallet.electrum", qos: .userInitiated)
        self.userDefaults = .standard
        self.network = .mainnet
        self.currentServer = ElectrumServer.mainnetServers.first!
        super.init()
    }

    init(
        network: BitcoinService.Network,
        userDefaults: UserDefaults = .standard,
        queue: DispatchQueue? = nil
    ) {
        self.queue = queue ?? DispatchQueue(label: "com.wallet.electrum", qos: .userInitiated)
        self.userDefaults = userDefaults
        self.network = network
        self.currentServer = network == .mainnet
            ? ElectrumServer.mainnetServers.first!
            : ElectrumServer.testnetServers.first!
        super.init()
    }

    var currentNetwork: BitcoinService.Network { network }

    func updateServer(host: String, port: Int, useSSL: Bool, network: BitcoinService.Network) {
        currentServer = ElectrumServer(host: host, port: port, useSSL: useSSL)
        self.network = network
    }

    func applySavedSettingsAndReconnect() {
        let host = userDefaults.string(forKey: "electrum_host") ?? "electrum.blockstream.info"
        var port = userDefaults.object(forKey: "electrum_port") as? Int ?? 50001
        let useSSL = userDefaults.object(forKey: "electrum_ssl") as? Bool ?? false
        let netStr = userDefaults.string(forKey: "network_type") ?? "mainnet"
        let net: BitcoinService.Network = (netStr == "testnet") ? .testnet : .mainnet
        if host == "electrum.blockstream.info" && !useSSL {
            port = (net == .mainnet) ? 50001 : 60001
        }
        updateServer(host: host, port: port, useSSL: useSSL, network: net)
        disconnect()
        connect()
    }
}
