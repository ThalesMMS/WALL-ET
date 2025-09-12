import Foundation
import CoreData

extension TransactionInputEntity {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<TransactionInputEntity> {
        return NSFetchRequest<TransactionInputEntity>(entityName: "TransactionInputEntity")
    }
    
    @NSManaged public var previousTxid: String?
    @NSManaged public var previousVout: Int32
    @NSManaged public var scriptSig: Data?
    @NSManaged public var witness: Data?
    @NSManaged public var sequence: Int32
    @NSManaged public var address: String?
    @NSManaged public var amount: Int64
    @NSManaged public var transaction: TransactionEntity?
}