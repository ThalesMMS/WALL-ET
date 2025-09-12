import Foundation
import CoreData

extension TransactionOutputEntity {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<TransactionOutputEntity> {
        return NSFetchRequest<TransactionOutputEntity>(entityName: "TransactionOutputEntity")
    }
    
    @NSManaged public var index: Int32
    @NSManaged public var amount: Int64
    @NSManaged public var scriptPubKey: Data?
    @NSManaged public var address: String?
    @NSManaged public var isSpent: Bool
    @NSManaged public var spentBy: String?
    @NSManaged public var transaction: TransactionEntity?
}