import Foundation

struct AccelerationContext {
    let ownedAddresses: Set<String>
    let utxos: [UTXO]
    let privateKeys: [Data]
    let originalFeeRate: Double
}

struct AccelerationResult {
    let originalTxid: String
    let replacementTxid: String
    let timestamp: Date
}

final class TransactionAccelerationStore {
    static let shared = TransactionAccelerationStore()

    private let queue = DispatchQueue(label: "TransactionAccelerationStore.queue", attributes: .concurrent)
    private var contexts: [String: AccelerationContext] = [:]
    private var results: [String: AccelerationResult] = [:]

    private init() {}

    func setContext(_ context: AccelerationContext, for txid: String) {
        queue.async(flags: .barrier) {
            self.contexts[txid] = context
        }
    }

    func context(for txid: String) -> AccelerationContext? {
        var context: AccelerationContext?
        queue.sync {
            context = contexts[txid]
        }
        return context
    }

    func removeContext(for txid: String) {
        queue.async(flags: .barrier) {
            self.contexts.removeValue(forKey: txid)
            self.results.removeValue(forKey: txid)
        }
    }

    func completeAcceleration(for originalTxid: String, replacementTxid: String) {
        let result = AccelerationResult(
            originalTxid: originalTxid,
            replacementTxid: replacementTxid,
            timestamp: Date()
        )
        queue.async(flags: .barrier) {
            self.results[originalTxid] = result
            self.contexts.removeValue(forKey: originalTxid)
        }
    }

    func result(for originalTxid: String) -> AccelerationResult? {
        var result: AccelerationResult?
        queue.sync {
            result = results[originalTxid]
        }
        return result
    }
}
