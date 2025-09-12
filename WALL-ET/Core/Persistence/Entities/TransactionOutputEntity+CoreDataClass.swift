import Foundation
import CoreData

@objc(TransactionOutputEntity)
public class TransactionOutputEntity: NSManagedObject {
    
    convenience init(context: NSManagedObjectContext) {
        self.init(entity: TransactionOutputEntity.entity(), insertInto: context)
        self.isSpent = false
    }
}