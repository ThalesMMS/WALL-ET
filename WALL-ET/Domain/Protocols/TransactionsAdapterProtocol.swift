import Foundation
import Combine

// MARK: - Transactions Adapter Protocol (parity-inspired)
protocol TransactionsAdapterProtocol: AnyObject {
    // Stream of incremental updates to existing items (optional for MVP)
    var itemsUpdatedPublisher: AnyPublisher<[TransactionModel], Never> { get }
    // Notifies when last block info changes (affects confirmations)
    var lastBlockUpdatedPublisher: AnyPublisher<Void, Never> { get }
    // Current last block info if known
    var lastBlockInfo: (height: Int, timestamp: Int)? { get }

    // Paged load: returns up to `limit` items after `paginationData` (exclusive)
    // For MVP, `paginationData` can be last transaction id (txid)
    func transactionsSingle(paginationData: String?, limit: Int) async throws -> [TransactionModel]
}

