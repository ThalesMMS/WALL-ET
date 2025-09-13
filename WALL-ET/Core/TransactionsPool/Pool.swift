import Foundation
import Combine

final class Pool {
    private let provider: PoolProvider
    private var items: [TransactionModel] = []
    private var invalidated = true
    private var allLoaded = false
    private let queue = DispatchQueue(label: "pool.transactions", qos: .userInitiated)
    private var cancellables = Set<AnyCancellable>()

    private let invalidatedSubject = PassthroughSubject<Void, Never>()
    private let itemsUpdatedSubject = PassthroughSubject<[TransactionModel], Never>()

    var invalidatedPublisher: AnyPublisher<Void, Never> { invalidatedSubject.eraseToAnyPublisher() }
    var itemsUpdatedPublisher: AnyPublisher<[TransactionModel], Never> { itemsUpdatedSubject.eraseToAnyPublisher() }

    init(provider: PoolProvider) {
        self.provider = provider
        // Forward provider item updates (partial batches)
        provider.itemsUpdatedPublisher
            .sink { [weak self] items in
                guard let self = self else { return }
                if items.isEmpty { return }
                // Merge into local cache and emit
                // De-dupe by id
                var existingIds = Set(self.items.map { $0.id })
                var appended: [TransactionModel] = []
                for it in items where !existingIds.contains(it.id) {
                    self.items.append(it)
                    existingIds.insert(it.id)
                    appended.append(it)
                }
                if !appended.isEmpty { self.itemsUpdatedSubject.send(appended) }
            }
            .store(in: &cancellables)
    }

    func itemsSingle(count: Int) async throws -> [TransactionModel] {
        try await queue.sync(execute: { () -> [TransactionModel] in return [] })
        // Use async path outside sync to avoid deadlocks
        if invalidated {
            invalidated = false
            allLoaded = false
            let fetched = try await provider.recordsSingle(from: nil, limit: count)
            items = fetched
            allLoaded = fetched.count < count
            return items
        }
        if allLoaded || items.count >= count { return Array(items.prefix(count)) }
        let required = count - items.count
        let lastId = items.last?.id
        let next = try await provider.recordsSingle(from: lastId, limit: required)
        items += next
        allLoaded = next.count < required
        return items
    }

    func invalidate() {
        invalidated = true
        invalidatedSubject.send(())
    }
}
