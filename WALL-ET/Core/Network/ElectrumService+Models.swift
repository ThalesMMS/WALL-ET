import Foundation

extension ElectrumService {
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

    final class AddressMapping {
        private var addressToScripthash: [String: String] = [:]
        private var scripthashToAddress: [String: String] = [:]
        private let lock = NSLock()

        func map(address: String, to scripthash: String) {
            lock.lock()
            addressToScripthash[address] = scripthash
            scripthashToAddress[scripthash] = address
            lock.unlock()
        }

        func cachedScripthash(for address: String) -> String? {
            lock.lock()
            let value = addressToScripthash[address]
            lock.unlock()
            return value
        }

        func address(for scripthash: String) -> String? {
            lock.lock()
            let value = scripthashToAddress[scripthash]
            lock.unlock()
            return value
        }
    }

    final class TransactionCache {
        private var knownTxidsByAddress: [String: Set<String>] = [:]
        private var trackedTxHeights: [String: Int?] = [:]
        private let lock = NSLock()

        func setKnownTxids(_ txids: Set<String>, for address: String) {
            lock.lock()
            knownTxidsByAddress[address] = txids
            lock.unlock()
        }

        func newTxids(for address: String, entries: [[String: Any]]) -> [String] {
            let latest = Set(entries.compactMap { $0["tx_hash"] as? String })
            lock.lock()
            let known = knownTxidsByAddress[address] ?? Set<String>()
            let diff = latest.subtracting(known)
            if !diff.isEmpty {
                knownTxidsByAddress[address] = latest
            }
            lock.unlock()
            return Array(diff)
        }

        func updateHeight(_ height: Int?, for txid: String) {
            lock.lock()
            trackedTxHeights[txid] = height
            lock.unlock()
        }

        func markUnknownHeight(for txid: String) {
            lock.lock()
            trackedTxHeights[txid] = nil
            lock.unlock()
        }

        func snapshotHeights() -> [String: Int?] {
            lock.lock()
            let snapshot = trackedTxHeights
            lock.unlock()
            return snapshot
        }
    }
}

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
