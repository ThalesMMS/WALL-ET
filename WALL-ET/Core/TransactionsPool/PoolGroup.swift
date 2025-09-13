import Foundation
import Combine

final class PoolGroup {
    private let pools: [Pool]
    private var cancellables = Set<AnyCancellable>()

    private let itemsUpdatedSubject = PassthroughSubject<[TransactionModel], Never>()
    private let invalidatedSubject = PassthroughSubject<Void, Never>()

    var itemsUpdatedPublisher: AnyPublisher<[TransactionModel], Never> { itemsUpdatedSubject.eraseToAnyPublisher() }
    var invalidatedPublisher: AnyPublisher<Void, Never> { invalidatedSubject.eraseToAnyPublisher() }

    init(pools: [Pool]) {
        self.pools = pools
        // Merge invalidations and updates
        for p in pools {
            p.invalidatedPublisher.sink { [weak self] in self?.invalidatedSubject.send(()) }.store(in: &cancellables)
            p.itemsUpdatedPublisher.sink { [weak self] items in self?.itemsUpdatedSubject.send(items) }.store(in: &cancellables)
        }
    }

    func itemsSingle(count: Int) async throws -> [TransactionModel] {
        if pools.isEmpty { return [] }
        // For now, single pool; extend to merge later
        let items = try await pools[0].itemsSingle(count: count)
        // Already sorted by adapter date desc; ensure
        return items.sorted { $0.date > $1.date }
    }
}

