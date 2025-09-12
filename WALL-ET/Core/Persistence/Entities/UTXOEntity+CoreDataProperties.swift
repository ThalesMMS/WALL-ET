import Foundation
import CoreData

extension UTXOEntity {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<UTXOEntity> {
        return NSFetchRequest<UTXOEntity>(entityName: "UTXOEntity")
    }
    
    @NSManaged public var txid: String?
    @NSManaged public var vout: Int32
    @NSManaged public var amount: Int64
    @NSManaged public var scriptPubKey: Data?
    @NSManaged public var blockHeight: Int32
    @NSManaged public var confirmations: Int32
    @NSManaged public var isSpent: Bool
    @NSManaged public var spentTxid: String?
    @NSManaged public var address: AddressEntity?
}