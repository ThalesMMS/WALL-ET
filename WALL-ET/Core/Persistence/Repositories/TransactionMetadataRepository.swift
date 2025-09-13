import Foundation
import CoreData

final class TransactionMetadataRepository {
    private let stack: CoreDataStack

    init(stack: CoreDataStack = .shared) {
        self.stack = stack
    }

    func upsert(
        txid: String,
        amountSats: Int64,
        feeSats: Int64,
        blockHeight: Int?,
        timestamp: Date?,
        type: String,
        status: String,
        fromAddress: String?,
        toAddress: String?
    ) async {
        await withCheckedContinuation { cont in
            stack.performBackgroundTask { context in
                let request: NSFetchRequest<TransactionEntity> = TransactionEntity.fetchRequest()
                request.predicate = NSPredicate(format: "txid == %@", txid)
                request.fetchLimit = 1
                let entity: TransactionEntity
                if let existing = (try? context.fetch(request))?.first {
                    entity = existing
                } else {
                    entity = TransactionEntity(context: context)
                    entity.txid = txid
                }
                entity.amount = amountSats
                entity.fee = feeSats
                entity.blockHeight = Int32(blockHeight ?? 0)
                entity.timestamp = timestamp
                entity.type = type
                entity.status = status
                entity.fromAddress = fromAddress
                entity.toAddress = toAddress
                // Save (ignore errors here to avoid crashing UI; logs are printed inside stack.save)
                self.stack.save(context: context)
                cont.resume()
            }
        }
    }
}
