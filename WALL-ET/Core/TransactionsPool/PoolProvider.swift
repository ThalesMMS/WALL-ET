import Foundation
import Combine

final class PoolProvider {
    private let adapter: TransactionsAdapterProtocol

    init(adapter: TransactionsAdapterProtocol) { self.adapter = adapter }

    var itemsUpdatedPublisher: AnyPublisher<[TransactionModel], Never> { adapter.itemsUpdatedPublisher }
    var lastBlockUpdatedPublisher: AnyPublisher<Void, Never> { adapter.lastBlockUpdatedPublisher }
    var lastBlockInfo: (height: Int, timestamp: Int)? { adapter.lastBlockInfo }

    func recordsSingle(from lastId: String?, limit: Int) async throws -> [TransactionModel] {
        try await adapter.transactionsSingle(paginationData: lastId, limit: limit)
    }
}

