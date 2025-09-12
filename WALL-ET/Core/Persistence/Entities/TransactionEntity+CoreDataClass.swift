import Foundation
import CoreData

@objc(TransactionEntity)
public class TransactionEntity: NSManagedObject {
    
    convenience init(context: NSManagedObjectContext) {
        self.init(entity: TransactionEntity.entity(), insertInto: context)
        self.timestamp = Date()
        self.confirmations = 0
        self.status = "pending"
    }
}