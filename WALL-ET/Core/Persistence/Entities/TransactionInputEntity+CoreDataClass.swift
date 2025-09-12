import Foundation
import CoreData

@objc(TransactionInputEntity)
public class TransactionInputEntity: NSManagedObject {
    
    convenience init(context: NSManagedObjectContext) {
        self.init(entity: TransactionInputEntity.entity(), insertInto: context)
        self.sequence = 0xFFFFFFFF
    }
}